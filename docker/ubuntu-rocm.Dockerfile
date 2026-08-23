FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl cmake ninja-build python3 python3-pip \
      g++ libstdc++-14-dev \
      patchelf zip unzip xz-utils pkg-config libssl-dev libcurl4-openssl-dev \
      git patch \
    && rm -rf /var/lib/apt/lists/*

# TheRock supplies clang. Host /opt/rocm is NOT bind-mounted.
WORKDIR /work
