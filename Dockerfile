FROM ubuntu:focal AS builder-curl
RUN apt-get update && apt-get install -y --no-install-recommends \
    git g++ make binutils autoconf automake autotools-dev libtool \
    pkg-config libev-dev libjemalloc-dev \
    ca-certificates mime-support
RUN git clone --depth 1 -b OpenSSL_1_1_1g-quic-draft-32 https://github.com/tatsuhiro-t/openssl && \
    cd openssl && ./config enable-tls1_3 --prefix=/build/openssl && make -j$(nproc) && make install_sw && cd .. && rm -rf openssl && \
    git clone --depth 1 https://github.com/ngtcp2/nghttp3 && \
    cd nghttp3 && autoreconf -i && \
    ./configure --prefix=/build/nghttp3 --enable-lib-only && \
    make -j$(nproc) && make install-strip && cd .. && rm -rf nghttp3
RUN git clone --depth 1 https://github.com/ngtcp2/ngtcp2 && \
    cd ngtcp2 && autoreconf -i && \
    ./configure \
    PKG_CONFIG_PATH=/build/openssl/lib/pkgconfig:/build/nghttp3/lib/pkgconfig \
    LDFLAGS="-Wl,-rpath,/build/openssl/lib" \
    --prefix=/build/ngtcp2 && \
    make -j$(nproc) && \
    make install && \
    strip examples/client examples/server && \
    cp examples/client examples/server /usr/local/bin && \
    cd .. && rm -rf ngtcp2
RUN git clone https://github.com/curl/curl && \
    cd curl && \
    autoreconf -fi && \
    LDFLAGS="-Wl,-rpath,/build/openssl/lib" ./configure --with-ssl=/build/openssl --with-nghttp3=/build/nghttp3 --with-ngtcp2=/build/ngtcp2 && \
    make && make DESTDIR="/ubuntu/" install

FROM rust:1.40-slim-buster AS builder-boringtun

WORKDIR /src

COPY boringtun .
RUN ls
RUN cargo build --release \
    && strip ./target/release/boringtun
FROM ubuntu:focal
RUN apt-get update && apt-get install -y curl
COPY --from=builder-curl /ubuntu/usr/local /usr/local/
COPY --from=builder-curl /build/ /build/
RUN ldconfig
WORKDIR /app
COPY --from=builder-boringtun /src/target/release/boringtun /app
ENV WG_LOG_LEVEL=info \
    WG_THREADS=4
RUN apt-get update && apt-get install -y --no-install-suggests wireguard-tools iproute2 iptables tcpdump
