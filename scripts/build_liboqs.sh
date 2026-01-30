#!/usr/bin/env bash
set -e

# Build script for liboqs (Post-Quantum Crypto)
# Configured for static linking with minimal dependencies (OpenSSL disabled)
# Targets: ML-KEM-768 (standardized Kyber)

echo "🚀 Building liboqs (ML-KEM-768)..."
rm -rf vendor/liboqs/build
mkdir -p vendor/liboqs/build
cd vendor/liboqs/build

# CMake Configuration
cmake -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DOQS_BUILD_ONLY_LIB=ON \
      -DOQS_USE_OPENSSL=OFF \
      -DOQS_ENABLE_KEM_KYBER=OFF \
      -DOQS_ENABLE_KEM_ML_KEM=ON \
      ..

# Build & Install
cmake --build . --parallel $(nproc)
cmake --install . --prefix ../install

echo "✅ liboqs build complete. Installed to vendor/liboqs/install."
