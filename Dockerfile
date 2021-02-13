FROM python:3.8-slim as builder

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
ADD https://raw.githubusercontent.com/music-assistant/server/master/requirements.txt /tmp/requirements.txt
WORKDIR /wheels
RUN pip wheel uvloop cchardet aiodns brotlipy \
    && pip wheel -r /tmp/requirements.txt
    
#### FINAL IMAGE
FROM python:3.8-slim AS final-image

WORKDIR /wheels
COPY --from=builder /wheels /wheels
COPY --from=builder /usr/local/lib/libjemalloc.so /usr/local/lib/libjemalloc.so
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
    # install all music assistant dependencies using the prebuilt wheels
    && pip install /wheels \
    # cleanup
    && rm -rf /tmp/* \
    && rm -rf /wheels \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /root/*

ENV LD_PRELOAD=/usr/local/lib/libjemalloc.so
