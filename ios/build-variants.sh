#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [ -z "${THEOS:-}" ]; then
  echo "error: \$THEOS is not set. Install/configure Theos first: https://theos.dev/docs/installation" >&2
  exit 1
fi

echo "== Building rootful variant (iOS 9-14 jailbreaks) =="
make clean package FINALPACKAGE=1

echo "== Building rootless variant (iOS 15+ jailbreaks) =="
cp control control.rootful.tmp
trap 'mv -f control.rootful.tmp control 2>/dev/null || true' EXIT
cp control.rootless control
make clean package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
mv control.rootful.tmp control
trap - EXIT

echo "== Done =="
ls -la packages/*.deb