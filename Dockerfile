# syntax = docker/dockerfile:latest
FROM ubuntu:22.04 AS base

ENV OPENSSL_VERSION 3.1.0
ENV NGHTTP3_VERSION v0.11.0
ENV NGTCP2_VERSION  v0.15.0
ENV CURL_VERSION    8_1_2

ENV OPENSSL_DIR /usr/local/openssl
ENV NGHTTP3_DIR /usr/local/nghttp3
ENV NGTCP2_DIR  /usr/local/ngtcp2
ENV CURL_DIR    /usr/local/curl

RUN rm -f /etc/apt/apt.conf.d/docker-clean; \
    echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN apt update
RUN --mount=type=cache,target=/var/cache/apt \
    apt install -y -qq build-essential ca-certificates git autoconf automake libtool pkg-config 

# OpenSSL with QUIC interface
FROM base AS openssl-builder
RUN git clone --depth 1 --branch openssl-${OPENSSL_VERSION}+quic https://github.com/quictls/openssl
WORKDIR /openssl
RUN ./config --prefix=${OPENSSL_DIR}
RUN make
RUN make install

# nghttp3
FROM base AS nghttp3-builder
RUN git clone --depth 1 --branch ${NGHTTP3_VERSION} https://github.com/ngtcp2/nghttp3
WORKDIR /nghttp3
RUN autoreconf --force --install
RUN --mount=type=bind,from=openssl-builder,source=${OPENSSL_DIR},target=${OPENSSL_DIR} \
    ./configure --prefix=${NGHTTP3_DIR} --enable-lib-only \
    && make \
    && make install

# ngtcp2
FROM base AS ngtcp2-builder
RUN git clone --depth 1 --branch ${NGTCP2_VERSION} https://github.com/ngtcp2/ngtcp2
WORKDIR /ngtcp2
RUN autoreconf --force --install
RUN --mount=type=bind,from=openssl-builder,source=${OPENSSL_DIR},target=${OPENSSL_DIR} --mount=type=bind,from=nghttp3-builder,source=${NGHTTP3_DIR},target=${NGHTTP3_DIR} \
    ./configure PKG_CONFIG_PATH=${OPENSSL_DIR}/lib/pkgconfig:${NGHTTP3_DIR}/lib/pkgconfig LDFLAGS="-Wl,-rpath,${OPENSSL_DIR}/lib" --prefix=${NGTCP2_DIR} --with-openssl --enable-lib-only \
    && make \
    && make install

# curl
FROM base AS curl-builder
RUN git clone --depth 1 --branch curl-${CURL_VERSION} https://github.com/curl/curl
WORKDIR /curl
RUN autoreconf --force --install
RUN --mount=type=bind,from=openssl-builder,source=${OPENSSL_DIR},target=${OPENSSL_DIR} --mount=type=bind,from=nghttp3-builder,source=${NGHTTP3_DIR},target=${NGHTTP3_DIR} --mount=type=bind,from=ngtcp2-builder,source=${NGTCP2_DIR},target=${NGTCP2_DIR} \
    LDFLAGS="-Wl,-rpath,${OPENSSL_DIR}/lib" ./configure --with-openssl=${OPENSSL_DIR} --with-nghttp3=${NGHTTP3_DIR} --with-ngtcp2=${NGTCP2_DIR} --prefix=${CURL_DIR} \
    && make \
    && make install

FROM ubuntu:22.04 AS runner
COPY --link --from=openssl-builder ${OPENSSL_DIR} ${OPENSSL_DIR}
COPY --link --from=nghttp3-builder ${NGHTTP3_DIR} ${NGHTTP3_DIR}
COPY --link --from=ngtcp2-builder  ${NGTCP2_DIR}  ${NGTCP2_DIR}
COPY --link --from=curl-builder    ${CURL_DIR}    ${CURL_DIR}
ENV PATH ${PATH}:/usr/local/curl/bin
