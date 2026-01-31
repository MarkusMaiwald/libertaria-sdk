#!/bin/bash
set -e

# Build
echo "Building Wolfi container..."
podman build -f Containerfile.wolfi -t capsule-wolfi .

# Run
echo "Running Capsule Node in Wolfi container..."
mkdir -p data-container
# Note: we override the CMD to pass arguments
podman run -d --rm --network host --name capsule-wolfi \
  -v $(pwd)/data-container:/app/data \
  capsule-wolfi \
  ./zig-out/bin/capsule start --port 9001 --data-dir /app/data
