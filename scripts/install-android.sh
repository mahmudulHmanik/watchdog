#!/usr/bin/env bash
# Install the built arm64 APK on the connected device (adb install -r) and start it.
# Usage: scripts/install-android.sh [adb-serial]
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

apk="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
[ -f "$apk" ] || { echo "Missing $apk. Run scripts/build-android.sh first." >&2; exit 1; }

adb_cmd=(adb)
[ $# -ge 1 ] && adb_cmd+=(-s "$1")

"${adb_cmd[@]}" install -r "$apk"
# Package id from the APK would need aapt; keep in sync with android/app/build.gradle.kts.
app_id="$(sed -n 's/.*applicationId = "\(.*\)".*/\1/p' android/app/build.gradle.kts | head -n1)"
[ -n "$app_id" ] || { echo "Could not read applicationId." >&2; exit 1; }
"${adb_cmd[@]}" shell monkey -p "$app_id" -c android.intent.category.LAUNCHER 1 >/dev/null
echo "Installed and started $app_id"
