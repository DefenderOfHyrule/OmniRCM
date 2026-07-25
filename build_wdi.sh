#!/bin/bash
#
#  build_wdi.sh - builds omnircm-wdi.dll
#
#  run this from the MSYS2 MinGW terminal:
#    cd <location of omnircm repository>
#    bash build_wdi.sh
#
#  prerequisites:
#    pacman -S --needed mingw-w64-x86_64-toolchain autoconf automake libtool make

set -e

# configure these two paths

# MSYS2 path to the extracted libusbK binary SDK, bin subfolder
LIBUSBK_MSYS=/c/libusbK-3.1.0.0-bin/bin

# Path to libwdi source, relative to this script
LIBWDI_SRC=libs/libwdi

REPO="$(cd "$(dirname "$0")" && pwd)"
LIBWDI_ABS="$REPO/$LIBWDI_SRC"
PATCHED_DIR="$REPO/build/libwdi-patched"
WDI_C="$REPO/wdi/omnircm_wdi.c"
OUT_DIR="$REPO/libs/windows"

SDK_COPY_MSYS=/c/omnircm-wdi-sdk
SDK_COPY_WIN='C:\omnircm-wdi-sdk'

echo ""
echo "============================================================"
echo " OmniRCM - building omnircm-wdi.dll"
echo "============================================================"
echo " Repo:       $REPO"
echo " libusbK:    $LIBUSBK_MSYS"
echo " libwdi src: $LIBWDI_ABS"
echo " Output:     $OUT_DIR/omnircm-wdi.dll"
echo "============================================================"
echo ""

if [ ! -f "$LIBWDI_ABS/configure.ac" ]; then
    echo "[ERROR] libwdi source not found at $LIBWDI_ABS"
    exit 1
fi

if [ ! -d "$LIBUSBK_MSYS" ]; then
    echo "[ERROR] libusbK SDK/bin not found at $LIBUSBK_MSYS"
    exit 1
fi

if [ ! -f "$WDI_C" ]; then
    echo "[ERROR] omnircm_wdi.c not found at $WDI_C"
    exit 1
fi

echo "[1/5] Copying SDK to $SDK_COPY_WIN..."
rm -rf "$SDK_COPY_MSYS"
cp -r "$LIBUSBK_MSYS" "$SDK_COPY_MSYS"

for arch in amd64 x86; do
    src="$SDK_COPY_MSYS/sys/$arch/WdfCoInstaller01009.dll"
    dst="$SDK_COPY_MSYS/sys/$arch/WdfCoInstaller1009.dll"
    [ -f "$src" ] && [ ! -f "$dst" ] && cp "$src" "$dst"
done
echo "    done."

echo ""
echo "[2/5] Copying and patching libwdi source..."
rm -rf "$PATCHED_DIR"
cp -r "$LIBWDI_ABS" "$PATCHED_DIR"

perl -i -0pe '
    s/\tif test "x\$WDK_DIR" != "x"; then.*?^\tfi\n//ms;
    s/\tif test "x\$LIBUSB0_DIR" != "x"; then.*?^\tfi\n//ms;
' "$PATCHED_DIR/configure.ac"

echo "    done."

echo ""
echo "[3/5] Bootstrapping patched libwdi..."
cd "$PATCHED_DIR"
./bootstrap.sh

echo ""
echo "[4/5] Configuring libwdi..."
./configure \
    --disable-32bit \
    --with-wdfver=1009 \
    --with-libusbk="$SDK_COPY_WIN"

perl -i -pe '
    if (/^#define LIBUSBK_DIR/) { s|\\|\\\\|g; }
' config.h
grep 'LIBUSBK_DIR' config.h

echo ""
echo "    Building libwdi..."
make -j"$(nproc)"

echo ""
echo "[5/5] Compiling omnircm_wdi.c -> omnircm-wdi.dll..."
mkdir -p "$OUT_DIR"

gcc \
    -shared \
    -o "$OUT_DIR/omnircm-wdi.dll" \
    "$WDI_C" \
    -I"$PATCHED_DIR/libwdi" \
    -L"$PATCHED_DIR/libwdi/.libs" \
    "$PATCHED_DIR/libwdi/.libs/libwdi.a" \
    -lsetupapi -lole32 -lshell32 -ladvapi32 \
    -Wl,--subsystem,windows \
    -static-libgcc \
    -Wl,-Bstatic -lpthread -Wl,-Bdynamic

rm -rf "$SDK_COPY_MSYS"

echo ""
echo "============================================================"
echo " Done!  libs/windows/omnircm-wdi.dll is ready."
echo "============================================================"
