#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

LIBUSB_TAG="v1.0.30"
BUILD_DIR="/tmp/libusb-build"
OUT_X64="$SCRIPT_DIR/libs/macos/x86_64"
OUT_ARM64="$SCRIPT_DIR/libs/macos/arm64"
OUT="$SCRIPT_DIR/libs/macos"

if ! command -v clang >/dev/null 2>&1; then
    echo "Xcode command line tools not found. Run: xcode-select --install"
    exit 1
fi

for tool in autoconf automake libtool; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "$tool not found. Run: brew install autoconf automake libtool"
        exit 1
    fi
done

lipo_bin() {
    local out="$1" in_a="$2" in_b="$3" tool=""
    if command -v lipo >/dev/null 2>&1; then
        tool="lipo"
    elif command -v llvm-lipo >/dev/null 2>&1; then
        tool="llvm-lipo"
    else
        tool="$(compgen -c llvm-lipo- 2>/dev/null | sort -V | tail -1)"
    fi

    if [ -z "$tool" ]; then
        echo "  [ERROR] No lipo/llvm-lipo(-N) found."
        exit 1
    fi
    "$tool" -create -output "$out" "$in_a" "$in_b"
}

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_X64" "$OUT_ARM64"

echo "Cloning libusb $LIBUSB_TAG..."
git clone --depth 1 --branch "$LIBUSB_TAG" https://github.com/libusb/libusb.git "$BUILD_DIR/src"

echo "Running autoreconf..."
cd "$BUILD_DIR/src"
autoreconf --install --force

build_arch() {
    local arch="$1"
    local target="$2"
    local prefix="$BUILD_DIR/out-$arch"
    local build="$BUILD_DIR/build-$arch"

    echo ""
    echo "Building $arch..."
    mkdir -p "$build"
    cd "$build"

    "$BUILD_DIR/src/configure" \
        --host="$target" \
        CC="clang -target $target" \
        --prefix="$prefix" \
        --disable-dependency-tracking

    make -j"$(sysctl -n hw.ncpu)"
    make install
}

build_arch x86_64 x86_64-apple-darwin
build_arch arm64  arm64-apple-darwin

fix_install_name() {
    local src="$1"
    local dest="$2"
    cp "$src" "$dest"
    install_name_tool -id "@executable_path/libusb-omnircm.dylib" "$dest"
    echo "✓  $(file "$dest" | grep -o 'arm64\|x86_64')  →  $dest"
    echo "   install name: $(otool -D "$dest" | tail -1)"
}

echo ""
echo "Copying and fixing install names..."
fix_install_name "$BUILD_DIR/out-x86_64/lib/libusb-1.0.0.dylib" "$OUT_X64/libusb-omnircm.dylib"
fix_install_name "$BUILD_DIR/out-arm64/lib/libusb-1.0.0.dylib"  "$OUT_ARM64/libusb-omnircm.dylib"
lipo_bin "$OUT/libusb-omnircm.dylib" "$OUT_X64/libusb-omnircm.dylib" "$OUT_ARM64/libusb-omnircm.dylib"
rm -rf "$OUT_X64" "$OUT_ARM64"

echo ""