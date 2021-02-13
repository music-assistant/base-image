# syntax=docker/dockerfile:experimental
FROM python:3.8-slim as wheels-builder

ENV PIP_EXTRA_INDEX_URL=https://www.piwheels.org/simple

RUN set -x \
    # Install buildtime packages
    && apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        build-essential \
        gcc \
        libtag1-dev \
        libffi-dev \
        libssl-dev \
        zlib1g-dev \
        xvfb \
        tcl8.6-dev \
        tk8.6-dev \
        libjpeg-turbo-progs \
        libjpeg62-turbo-dev

# build jemalloc
ARG JEMALLOC_VERSION=5.2.1
RUN curl -L -s https://github.com/jemalloc/jemalloc/releases/download/${JEMALLOC_VERSION}/jemalloc-${JEMALLOC_VERSION}.tar.bz2 \
        | tar -xjf - -C /tmp \
    && cd /tmp/jemalloc-${JEMALLOC_VERSION} \
    && ./configure \
    && NB_CORES=$(grep -c '^processor' /proc/cpuinfo) \
    && export MAKEFLAGS="-j$((NB_CORES+1)) -l${NB_CORES}" \
    && make \
    && make install

# build python wheels
WORKDIR /wheels
ADD https://raw.githubusercontent.com/music-assistant/server/master/requirements.txt /wheels/requirements.txt
RUN pip wheel -r /wheels/requirements.txt
    
#### FINAL IMAGE
FROM python:3.8-slim AS final-image

COPY --from=wheels-builder /usr/local/lib/libjemalloc.so /usr/local/lib/libjemalloc.so
RUN set -x \
    # Install runtime dependency packages
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        tzdata \
        ca-certificates \
        flac \
        sox \
        libsox-fmt-all \
        ffmpeg \
        libtag1v5 \
        openssl \
        libjpeg62-turbo \
        zlib1g \
    # cleanup
    && rm -rf /tmp/* \
    && rm -rf /var/lib/apt/lists/*

# https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/syntax.md#build-mounts-run---mount
# Install pip dependencies with built wheels
RUN --mount=type=bind,target=/wheels,source=/wheels,from=wheels-builder,rw \
    pip install --no-cache-dir -f /wheels -r /wheels/requirements.txt

ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so
