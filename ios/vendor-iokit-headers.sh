#!/usr/bin/env bash
set -euo pipefail

if [ -z "${THEOS:-}" ]; then
  echo "error: \$THEOS is not set. Install/configure Theos first: https://theos.dev/docs/installation" >&2
  exit 1
fi

SDK_ROOT="https://raw.githubusercontent.com/phracker/MacOSX-SDKs/master/MacOSX11.3.sdk/System/Library/Frameworks"
IOKIT_HEADERS="$SDK_ROOT/IOKit.framework/Versions/A/Headers"
KERNEL_USB_HEADERS="$SDK_ROOT/Kernel.framework/Versions/A/Headers/IOKit/usb"

DEST="$THEOS/vendor/include/IOKit"

mkdir -p "$DEST/usb"

fetch() {
  local base="$1" rel="$2" dest="$3"
  echo "Fetching $rel..."
  if ! curl -sfL "$base/$rel" -o "$dest"; then
    echo "error: failed to download $rel from $base" >&2
    rm -f "$dest"
    exit 1
  fi
}

fetch "$IOKIT_HEADERS" "IOCFPlugIn.h" "$DEST/IOCFPlugIn.h"

for f in \
  IOUSBLib.h \
  USB.h \
  USBSpec.h \
  IOUSBHostFamilyDefinitions.h \
  AppleUSBDefinitions.h
do
  fetch "$IOKIT_HEADERS/usb" "$f" "$DEST/usb/$f"
done

# Testing
#for f in \
#  StandardUSB.h \
#  IOUSBHostFamily.h
#do
#  fetch "$KERNEL_USB_HEADERS" "$f" "$DEST/usb/$f"
#done

echo ""
echo "IOKit headers vendored to: $DEST"