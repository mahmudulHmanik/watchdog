#!/bin/sh
# watchdog installer: downloads the latest release APK, verifies it and installs it.
#
#   curl -fsSL https://raw.githubusercontent.com/mahmudulHmanik/watchdog/main/scripts/install.sh | sh
#
# What it does
#   1. Finds the newest release through GitHub's /releases/latest redirect (no API, no rate limit).
#   2. Downloads watchdog-<tag>-arm64.apk and its .sha256 and checks the SHA-256.
#   3. If `apksigner` (Android SDK build-tools) is available, checks the signing certificate
#      against the project's key. Otherwise prints the fingerprint so you can compare it.
#   4. Installs:
#        - `adb` + one connected phone  -> adb install -r   (fully automatic)
#        - Termux on the phone          -> opens Android's installer (tap Install once)
#        - anything else                -> keeps the APK and tells you where it is
#
# Options (environment variables)
#   WATCHDOG_TAG=v0.3.3   install this version instead of the latest
#   WATCHDOG_DIR=DIR      keep the downloaded APK in DIR (default: temp dir, removed afterwards,
#                         unless nothing could install it)
#   ANDROID_SERIAL=ID     choose the phone when several are connected (adb)
#   WATCHDOG_BASE_URL=URL for testing: serve the release files from another place
#
# Only the arm64 build is published. The script never needs root and never installs anything
# but the APK it just verified.
set -eu

REPO="mahmudulHmanik/watchdog"
# SHA-256 fingerprint of the release signing certificate (see CLAUDE.md "Release signing").
SIGNER_SHA256="11e47da4d9a89482a94725662bd151387b902304457fc4e06de1896fa463344c"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
# A file that failed verification is deleted, even in a user-chosen directory.
reject() { rm -f "$dir/$apk" "$dir/$apk.sha256"; die "$@"; }
have() { command -v "$1" >/dev/null 2>&1; }

have curl || die "curl is required"

# ---- which version -----------------------------------------------------------------------
tag="${WATCHDOG_TAG:-}"
if [ -z "$tag" ]; then
  final=$(curl -fsSIL -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest") \
    || die "could not reach github.com"
  tag=${final##*/}
fi
case "$tag" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) die "unexpected release tag '$tag' (is there a published release?)" ;;
esac
case "$tag" in
  *[!A-Za-z0-9._-]*) die "unsafe release tag" ;;
esac

apk="watchdog-$tag-arm64.apk"
base="${WATCHDOG_BASE_URL:-https://github.com/$REPO/releases/download/$tag}"

# ---- download ----------------------------------------------------------------------------
if [ -n "${WATCHDOG_DIR:-}" ]; then
  dir=$WATCHDOG_DIR
  mkdir -p "$dir"
  keep=1
else
  dir=$(mktemp -d 2>/dev/null || mktemp -d -t watchdog)
  keep=0
fi
cleanup() { [ "$keep" = 1 ] || rm -rf "$dir"; }
trap cleanup EXIT INT TERM

say "watchdog $tag"
say "downloading $apk ..."
curl -fL --progress-bar -o "$dir/$apk" "$base/$apk" || die "download failed: $base/$apk"
curl -fsSL -o "$dir/$apk.sha256" "$base/$apk.sha256" || die "checksum file missing for $tag"

# ---- verify checksum ---------------------------------------------------------------------
want=$(sed -n 's/^\([0-9a-fA-F]\{64\}\).*/\1/p' "$dir/$apk.sha256" | head -n 1 | tr 'A-F' 'a-f')
[ -n "$want" ] || die "could not read the checksum file"
if have sha256sum; then
  got=$(sha256sum "$dir/$apk" | cut -d' ' -f1)
elif have shasum; then
  got=$(shasum -a 256 "$dir/$apk" | cut -d' ' -f1)
elif have openssl; then
  got=$(openssl dgst -sha256 "$dir/$apk" | sed 's/^.*= //')
else
  die "need sha256sum, shasum or openssl to verify the download"
fi
[ "$got" = "$want" ] || reject "checksum mismatch (expected $want, got $got). Not installing."
say "checksum OK ($got)"

# ---- verify signer (when apksigner is available) -----------------------------------------
signer_ok=unknown
apksigner=""
if have apksigner; then
  apksigner=apksigner
elif [ -n "${ANDROID_HOME:-}" ] && ls "$ANDROID_HOME"/build-tools/*/apksigner >/dev/null 2>&1; then
  apksigner=$( (ls -d "$ANDROID_HOME"/build-tools/*/apksigner | sort -V 2>/dev/null \
    || ls -d "$ANDROID_HOME"/build-tools/*/apksigner) | tail -n 1)
fi
if [ -n "$apksigner" ]; then
  cert=$("$apksigner" verify --print-certs "$dir/$apk" 2>/dev/null \
    | sed -n 's/.*certificate SHA-256 digest: *//p' | head -n 1 | tr 'A-F' 'a-f')
  if [ "$cert" = "$SIGNER_SHA256" ]; then
    signer_ok=yes
    say "signing key OK ($cert)"
  else
    reject "signing key does not match the project's key (got '${cert:-none}'). Not installing."
  fi
else
  say "note: apksigner not found, so the signing key was not checked."
  say "      expected certificate SHA-256: $SIGNER_SHA256"
fi

# ---- install -----------------------------------------------------------------------------
installed=0
if have adb; then
  # adb must never read our stdin: when piped from curl, stdin IS this script.
  count=0
  while read -r serial state _; do
    [ "$state" = device ] && count=$((count + 1))
  done <<EOF_DEVICES
$(adb devices 2>/dev/null < /dev/null | sed -n '2,$p')
EOF_DEVICES
  if [ -n "${ANDROID_SERIAL:-}" ] || [ "$count" = 1 ]; then
    say "installing with adb ..."
    if adb install -r "$dir/$apk" < /dev/null; then
      installed=1
      say "done: watchdog $tag installed."
    else
      say "adb could not install it (see the message above)."
    fi
  elif [ "$count" -gt 1 ]; then
    say "several devices are connected; set ANDROID_SERIAL=<id> (adb devices) and run again."
  fi
fi

if [ "$installed" = 0 ] && [ -n "${PREFIX:-}" ] && [ "${PREFIX#*com.termux}" != "$PREFIX" ] \
  && have termux-open; then
  # Termux can hand the APK to Android's installer; keep a copy the installer can read.
  out="${WATCHDOG_DIR:-$HOME}/$apk"
  [ "$dir/$apk" = "$out" ] || cp "$dir/$apk" "$out"
  keep=1
  say "opening Android's installer ... tap Install (you may need to allow Termux to install apps)."
  termux-open "$out" && installed=1
fi

if [ "$installed" = 0 ]; then
  out="${WATCHDOG_DIR:-${PWD:-.}}/$apk"
  [ "$dir/$apk" = "$out" ] || cp "$dir/$apk" "$out"
  keep=1
  say ""
  say "verified APK saved to: $out"
  say "install it on the phone with one of:"
  say "  adb install -r $out          (USB / wireless debugging)"
  say "  copy it to the phone and open it (allow 'Install unknown apps' once)"
fi
