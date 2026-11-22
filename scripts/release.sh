#!/usr/bin/env bash
# Build the signed arm64 APK and publish it as a GitHub release, which is what
# the in-app updater (Settings -> Check for updates) looks for.
#
#   scripts/release.sh                 # tag = v<version in pubspec.yaml>, pre-release
#   scripts/release.sh --final         # mark as a normal (non pre-)release
#   NOTES="what changed" scripts/release.sh
#
# Needs: gh (authenticated), android/key.properties + keystore. Updates only
# install over an existing app when signed with the SAME key, so never rebuild
# with a different keystore. Back the keystore up.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if command -v mise >/dev/null 2>&1; then eval "$(mise env)"; fi
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"

# This script PUBLISHES a public GitHub release. Never run it by accident.
if [ "${RELEASE_CONFIRM:-}" != "yes" ]; then
  [ -t 0 ] || { echo "Refusing: not interactive. Set RELEASE_CONFIRM=yes to publish." >&2; exit 1; }
  read -r -p "Publish a PUBLIC GitHub release now? Type 'publish': " ans
  [ "$ans" = "publish" ] || { echo "Aborted." >&2; exit 1; }
fi

pre=(--prerelease)
[ "${1:-}" = "--final" ] && pre=()

[ -f android/key.properties ] || {
  echo "android/key.properties missing. Refusing to build a debug-signed release." >&2
  exit 1
}

ver="$(sed -n 's/^version: *\([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml | head -n1)"
build="$(sed -n 's/^version: *[0-9.]*+\([0-9]*\).*/\1/p' pubspec.yaml | head -n1)"
[ -n "$ver" ] && [ -n "$build" ] || { echo "Cannot read version from pubspec.yaml" >&2; exit 1; }
tag="v$ver"

grep -q "appVersion = '$ver+$build'" lib/core/app_info.dart || {
  echo "lib/core/app_info.dart appVersion must be '$ver+$build' (mirror pubspec.yaml)." >&2
  exit 1
}
if gh release view "$tag" >/dev/null 2>&1; then
  echo "Release $tag already exists. Bump version in pubspec.yaml and app_info.dart." >&2
  exit 1
fi

flutter pub get
flutter build apk --release --split-per-abi --target-platform android-arm64

src="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
out="build/watchdog-$tag-arm64.apk"
cp "$src" "$out"

# Make sure it is not signed with the debug key (updates would never install).
bt="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -n1)"
if "$bt/apksigner" verify --print-certs "$out" | grep -qi "Android Debug"; then
  echo "APK is debug-signed. Check android/key.properties." >&2
  exit 1
fi

sha256sum "$out" | tee "$out.sha256"
notes="${NOTES:-}"
if [ -n "$notes" ]; then
  gh release create "$tag" "$out" "$out.sha256" --title "watchdog $tag" "${pre[@]}" --notes "$notes"
else
  gh release create "$tag" "$out" "$out.sha256" --title "watchdog $tag" "${pre[@]}" --generate-notes
fi
echo "Published $tag"
