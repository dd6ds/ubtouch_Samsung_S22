FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      bc bison build-essential ca-certificates cpio curl fakeroot flex git \
      kmod libelf-dev libssl-dev lz4 python3 python-is-python3 rsync xz-utils \
      e2fsprogs zstd file \
      clang lld llvm \
    && rm -rf /var/lib/apt/lists/*
