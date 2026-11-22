#!/usr/bin/env bash
# Build the Linux release bundle. Needs gtk3, cmake, ninja, clang and (at runtime) mpv/libmpv.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if command -v mise >/dev/null 2>&1; then eval "$(mise env)"; fi

flutter pub get
flutter build linux --release

echo
echo "Bundle: build/linux/x64/release/bundle/watchdog"
echo "Desktop entry and icon: packaging/linux/"
