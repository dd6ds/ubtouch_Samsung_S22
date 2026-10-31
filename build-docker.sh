#!/bin/bash
# Run ./build.sh inside an Ubuntu 24.04 container with all host packages.
#   ./build-docker.sh r0s kernel
# The kit folder is mounted at the same path, so work/ stays on the host.
set -euo pipefail
cd "$(dirname "$0")"
docker build -q -t s22-ut-build docker/ >/dev/null
TTY=(); [ -t 0 ] && TTY=(-it)
exec docker run --rm "${TTY[@]}" \
	-u "$(id -u):$(id -g)" -e HOME=/tmp \
	-e JOBS -e USE_SYSTEM_CLANG -e CLANG_VERSION -e CLANG_BRANCH -e ALLOW_NO_FIRMWARE \
	-v "$PWD:$PWD" -w "$PWD" \
	s22-ut-build ./build.sh "$@"
