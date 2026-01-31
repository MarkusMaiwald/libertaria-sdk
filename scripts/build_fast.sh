#!/bin/bash
set -e

echo "Building capsule on host..."
cd capsule-core
zig build
cd ..

echo "Preparing libs..."
mkdir -p libs
cp /usr/lib/libduckdb.so libs/

echo "Building Fast-Track container..."
podman build --platform linux/amd64 -f Containerfile.fast -t capsule-wolfi .

echo "Running Capsule Node in Fast-Track container..."
mkdir -p /tmp/libertaria-container-data
podman run -d --rm --network host --name capsule-wolfi \
  -v "/tmp/libertaria-container-data:/app/data" \
  -v "$(pwd)/capsule-core/config.json:/app/config.json" \
  capsule-wolfi \
  capsule start --port 9001 --data-dir /app/data
