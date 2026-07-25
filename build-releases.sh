#!/bin/bash
# build-releases.sh - OmniRCM
# produces portable archives for all platforms from any host OS.
# requires: dotnet SDK, zip (Linux/macOS), 7z or PowerShell (Windows)
#
# usage:
#  bash build-releases.sh OR ./build-releases.sh
#
# environment variables:
#   OMNI_VERSION      override version string (default: parsed from OmniVersion.cs)
#   SKIP_WDI          set to 1 to skip rebuilding omnircm-wdi.dll on Windows

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -n "${OMNI_VERSION:-}" ]; then
    VERSION="$OMNI_VERSION"
else
    VERSION=$(sed -n 's/.*CurrentVersion = new(\([0-9]*\), *\([0-9]*\), *\([0-9]*\)).*/\1.\2.\3/p' \
        MainWindow.axaml.cs | head -1)
    VERSION="${VERSION:-0.0.0}"
fi
echo "Building OmniRCM $VERSION"

PROJECT="OmniRCM.csproj"
OUT="$SCRIPT_DIR/releases"
rm -rf "$OUT" && mkdir -p "$OUT"

echo "Cleaning obj/bin to avoid stale Avalonia XAML compiler cache..."
rm -rf "$SCRIPT_DIR/obj" "$SCRIPT_DIR/bin"

# detect platform
IS_WINDOWS=0; IS_LINUX=0; IS_MAC=0
case "$(uname -s 2>/dev/null || echo Windows)" in
    MINGW*|MSYS*|CYGWIN*|Windows) IS_WINDOWS=1 ;;
    Linux)                          IS_LINUX=1   ;;
    Darwin)                         IS_MAC=1     ;;
esac

if [ "$IS_WINDOWS" = "1" ]; then
    WDI_DLL="$SCRIPT_DIR/libs/windows/omnircm-wdi.dll"
    if [ "${SKIP_WDI:-0}" = "1" ] && [ -f "$WDI_DLL" ]; then
        echo ""
        echo "- Skipping omnircm-wdi.dll build (SKIP_WDI=1, dll exists)"
    else
        echo ""
        echo "- Building omnircm-wdi.dll (libusbK driver installer)..."
        if [ ! -f "$SCRIPT_DIR/build_wdi.sh" ]; then
            echo "  [ERROR] build_wdi.sh not found at repo root."
            echo "          Cannot build omnircm-wdi.dll."
            exit 1
        fi
        bash "$SCRIPT_DIR/build_wdi.sh"
        if [ ! -f "$WDI_DLL" ]; then
            echo "  [ERROR] build_wdi.sh completed but $WDI_DLL was not produced."
            exit 1
        fi
        echo "✓  omnircm-wdi.dll"
    fi
fi

# helpers
publish() {
    local rid="$1" label="$2"
    echo ""
    echo "- Publishing $label ($rid)..."
    dotnet publish "$PROJECT" \
        -c Release \
        -r "$rid" \
        --self-contained true \
        -p:PublishSingleFile=true \
        -p:IncludeNativeLibrariesForSelfExtract=true \
        -p:PublishTrimmed=false \
        -p:ApplicationVersion="$VERSION" \
        -o "$OUT/$rid"
}

make_zip() {
    local src="$1" dest="$2"
    if [ "$IS_WINDOWS" = "1" ]; then
        if command -v 7z >/dev/null 2>&1; then
            7z a -tzip "$dest" "$src" >/dev/null
        else
            powershell -NoProfile -Command \
                "Compress-Archive -Path '$src' -DestinationPath '$dest' -Force"
        fi
    else
        if [ -d "$src" ]; then
            local parent dir
            parent="$(dirname "$src")"
            dir="$(basename "$src")"
            (cd "$parent" && zip -qr "$dest" "$dir")
        else
            local parent file
            parent="$(dirname "$src")"
            file="$(basename "$src")"
            (cd "$parent" && zip -q "$dest" "$file")
        fi
    fi
}

app_bundle() {
    local rid="$1" exe_name="$2" arch="${3:-x86_64}"
    local APP="$OUT/$rid/OmniRCM.app"
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    cp "$OUT/$rid/$exe_name" "$APP/Contents/MacOS/OmniRCM"
    chmod +x "$APP/Contents/MacOS/OmniRCM"

    local DYLIB_SRC="$SCRIPT_DIR/libs/macos/$arch/libusb-omnircm.dylib"
    if [ -f "$DYLIB_SRC" ]; then
        cp "$DYLIB_SRC" "$APP/Contents/MacOS/libusb-omnircm.dylib"
        echo "  bundled libusb ($arch)"
    else
        echo "  [WARN] $DYLIB_SRC not found."
    fi

    local ARCH_ENTRY=""
    if [ "$arch" != "x86_64" ]; then
        ARCH_ENTRY="
    <key>LSArchitecturePriority</key>
    <array><string>$arch</string></array>"
    fi

    cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>         <string>OmniRCM</string>
    <key>CFBundleIdentifier</key>         <string>io.github.defenderofhyrule.omnircm</string>
    <key>CFBundleName</key>               <string>OmniRCM</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>     <string>10.15</string>
    <key>NSHighResolutionCapable</key>    <true/>${ARCH_ENTRY}
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
</dict>
</plist>
PLIST

    if [ -f "Assets/icon.icns" ]; then
        cp "Assets/icon.icns" "$APP/Contents/Resources/AppIcon.icns"
    fi
}

sign_and_notarize() {
    local app="$1"

    if [ "$IS_MAC" = "1" ]; then
        if [ -z "${APPLE_SIGN_ID:-}" ]; then
            echo "  (skipping signing: APPLE_SIGN_ID not set)"
            return
        fi
        echo "  signing with codesign ($APPLE_SIGN_ID)..."
        codesign --force --deep --timestamp --options runtime \
            --sign "$APPLE_SIGN_ID" "$app"
        codesign --verify --deep --strict --verbose=2 "$app"
        echo "  ✓ signed"

        if [ -n "${APPLE_NOTARY_KEY:-}" ]; then
            if [ -z "${APPLE_NOTARY_PROFILE:-}" ]; then
                echo "  [ERROR] APPLE_NOTARY_KEY is set but APPLE_NOTARY_PROFILE is not."
                echo "          Run 'xcrun notarytool store-credentials' once to create a profile."
                exit 1
            fi
            echo "  notarizing via notarytool..."
            local tmpzip
            tmpzip="$(mktemp -t omnircm-notarize-XXXXXX).zip"
            ditto -c -k --keepParent "$app" "$tmpzip"
            xcrun notarytool submit "$tmpzip" --keychain-profile "$APPLE_NOTARY_PROFILE" --wait
            rm -f "$tmpzip"
            xcrun stapler staple "$app"
            echo "  ✓ notarized + stapled"
        fi
    else
        if [ -z "${APPLE_P12:-}" ]; then
            echo "  (skipping signing: APPLE_P12 not set)"
            return
        fi
        if ! command -v rcodesign >/dev/null 2>&1; then
            echo "  [ERROR] APPLE_P12 is set but rcodesign is not installed/on PATH."
            echo "          Install with: cargo install apple-codesign"
            exit 1
        fi
        if [ -z "${APPLE_P12_PW:-}" ]; then
            echo "  [ERROR] APPLE_P12 is set but APPLE_P12_PW is not."
            exit 1
        fi
        echo "  signing with rcodesign..."
        rcodesign sign --p12-file "$APPLE_P12" --p12-password-file "$APPLE_P12_PW" \
            --code-signature-flags runtime "$app"
        echo "  ✓ signed"

        if [ -n "${APPLE_NOTARY_KEY:-}" ]; then
            echo "  notarizing via rcodesign..."
            rcodesign notary-submit --api-key-file "$APPLE_NOTARY_KEY" --staple "$app"
            echo "  ✓ notarized + stapled"
        fi
    fi
}

publish win-x64 "Windows x64"
mv "$OUT/win-x64/OmniRCM.exe" "$OUT/OmniRCM-win-x64.exe"
echo "✓  OmniRCM-win-x64.exe"

publish linux-x64 "Linux x64"
mv "$OUT/linux-x64/OmniRCM" "$OUT/OmniRCM-linux-x64"
chmod +x "$OUT/OmniRCM-linux-x64"
echo "✓  OmniRCM-linux-x64"

publish linux-arm64 "Linux ARM64"
mv "$OUT/linux-arm64/OmniRCM" "$OUT/OmniRCM-linux-arm64"
chmod +x "$OUT/OmniRCM-linux-arm64"
echo "✓  OmniRCM-linux-arm64"

publish osx-x64 "macOS x64"
mv "$OUT/osx-x64/OmniRCM" "$OUT/osx-x64/OmniRCM-osx-x64"
chmod +x "$OUT/osx-x64/OmniRCM-osx-x64"
app_bundle osx-x64 OmniRCM-osx-x64 x86_64
sign_and_notarize "$OUT/osx-x64/OmniRCM.app"
make_zip "$OUT/osx-x64/OmniRCM.app" "$OUT/OmniRCM-osx-x64.zip"
echo "✓  OmniRCM-osx-x64.zip"

publish osx-arm64 "macOS ARM64 (Apple Silicon)"
mv "$OUT/osx-arm64/OmniRCM" "$OUT/osx-arm64/OmniRCM-osx-arm64"
chmod +x "$OUT/osx-arm64/OmniRCM-osx-arm64"
app_bundle osx-arm64 OmniRCM-osx-arm64 arm64
sign_and_notarize "$OUT/osx-arm64/OmniRCM.app"
make_zip "$OUT/osx-arm64/OmniRCM.app" "$OUT/OmniRCM-osx-arm64.zip"
echo "✓  OmniRCM-osx-arm64.zip"

echo ""
echo "════════════════════════════════"
echo " OmniRCM $VERSION - done"
echo "════════════════════════════════"
ls -lh "$OUT"/OmniRCM-* 2>/dev/null || true
