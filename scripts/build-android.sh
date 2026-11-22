#!/usr/bin/env bash
# Build the arm64 release APK and print path, size and sha256.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if command -v mise >/dev/null 2>&1; then eval "$(mise env)"; fi
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"

flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm64

apk="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
echo
echo "APK:    $apk"
echo "Size:   $(du -h "$apk" | cut -f1)"
echo "SHA256: $(sha256sum "$apk" | cut -d' ' -f1)"
