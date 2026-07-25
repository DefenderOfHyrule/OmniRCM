#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LIBUSB_TAG="v1.0.30"
BUILD_DIR="/tmp/libusb-linux-build"
OUT="$SCRIPT_DIR/libs/linux/x86_64"

for tool in gcc make autoconf automake libtool; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found."
        echo "Run: sudo apt install build-essential autoconf automake libtool"
        echo " or: sudo dnf install gcc make autoconf automake libtool"
        exit 1
    fi
done

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT"

echo "Cloning libusb $LIBUSB_TAG..."
git clone --depth 1 --branch "$LIBUSB_TAG" https://github.com/libusb/libusb.git "$BUILD_DIR/src"

echo "Running autoreconf..."
cd "$BUILD_DIR/src"
autoreconf --install --force

echo ""
echo "Building x86_64..."
mkdir -p "$BUILD_DIR/build"
cd "$BUILD_DIR/build"

"$BUILD_DIR/src/configure" \
    --prefix="$BUILD_DIR/out" \
    --enable-shared \
    --enable-static \
    --with-pic

make -j"$(nproc)"
make install

echo ""
echo "Copying libusb-omnircm.so..."
SO=$(find "$BUILD_DIR/out/lib" -name "libusb-1.0.so.0.*" -not -type l | head -1)
if [ -z "$SO" ]; then
    echo "[ERROR] Could not find built libusb-1.0.so in $BUILD_DIR/out/lib"
    exit 1
fi
echo "  found: $SO"
cp "$SO" "$OUT/libusb-omnircm.so"
strip "$OUT/libusb-omnircm.so"

echo ""
echo "Done."
echo "  $(file "$OUT/libusb-omnircm.so")"