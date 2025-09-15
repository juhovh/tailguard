#!/bin/sh

TG_VERSION="v1.0"
TG_PATCH_VERSION="v1.0.3"

docker buildx build --no-cache \
  --platform linux/arm,linux/arm64,linux/386,linux/amd64 --push \
  -t docker.io/juhovh/tailguard:${TG_VERSION} \
  -t docker.io/juhovh/tailguard:${TG_PATCH_VERSION} \
  -t docker.io/juhovh/tailguard:latest \
  -f Dockerfile .
