# Probe only. The first steps are the ones of ../Dockerfile, up to the clone.
FROM debian:trixie-slim AS probe

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    unzip \
    build-essential \
    pkg-config \
    libssl-dev \
    python3 \
    python3-pip \
    wget \
    ca-certificates \
    gnupg \
    apt-transport-https \
    gcc-12 g++-12 libstdc++-12-dev \
    lsb-release \
    sudo \
    make \
    libtool \
    ruby \
    perl \
    gdb \
    jq \
    ccache \
    ripgrep

RUN mkdir -p /workspace/bun
WORKDIR /workspace

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    --default-toolchain none --profile minimal --no-modify-path
ENV PATH="/root/.cargo/bin:${PATH}"

RUN case "$(uname -m)" in \
      arm64 | aarch64)  arch=aarch64;; \
      *)                arch=x64;; \
    esac \
    && target="bun-linux-${arch}" \
    && curl -LO "https://pub-5e11e972747a44bf9aaf9394f185a982.r2.dev/releases/latest/${target}.zip" --retry 5 \
    && unzip ${target}.zip \
    && mkdir -p /usr/local/bun/bin \
    && mv ${target}/bun* /usr/local/bun/bin/ \
    && chmod +x /usr/local/bun/bin/* \
    && ln -fs /usr/local/bun/bin/bun /usr/local/bun/bin/bunx \
    && ln -fs /usr/local/bun/bin/bun /usr/local/bin/bun \
    && ln -fs /usr/local/bun/bin/bunx /usr/local/bin/bunx \
    && rm -rf ${target}.zip ${target}

ARG BUN_REF=main
RUN git clone --branch ${BUN_REF} https://github.com/oven-sh/bun.git /workspace/bun
WORKDIR /workspace/bun

ENV BUN_NO_CORE_DUMP=1

COPY probe.sh /probe/probe.sh

# The whole script, once, cut before the prefetch.
RUN sh /probe/probe.sh whole

# What the `prebuilt` stage of ../Dockerfile sets before it builds.
ENV ENABLE_ZIG_ASAN=0
ENV BUN_DEBUG_QUIET_LOGS=1
ENV BUN_GARBAGE_COLLECTOR_LEVEL=0
ENV BUN_FEATURE_FLAG_INTERNAL_FOR_TESTING=1
RUN sh /probe/probe.sh build

# Is the script safe to run a second time?
RUN sh /probe/probe.sh twice
