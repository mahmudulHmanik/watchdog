#!/bin/sh
# watchdog for Linux: installs the run-time dependencies, then the latest release.
#
#   curl -fsSL https://raw.githubusercontent.com/mahmudulHmanik/watchdog/main/scripts/install-linux.sh | sh
#   ... | sh -s -- --uninstall        remove it again
#
# What it does
#   1. Installs the system libraries the app needs (mpv/libmpv, GTK 3, libsecret) with your
#      package manager (pacman / apt / dnf). This is the only step that needs root (sudo); it is
#      skipped when nothing is missing or with WATCHDOG_SKIP_DEPS=1.
#   2. Finds the newest release through the /releases/latest redirect (no API, no rate limit),
#      downloads watchdog-<tag>-linux-x64.tar.gz + its .sha256 and verifies the SHA-256.
#   3. Installs into ~/.local (no root): app in ~/.local/opt/watchdog, command `watchdog` in
#      ~/.local/bin, a launcher entry and an icon.
#
# Options (environment variables)
#   WATCHDOG_TAG=v0.3.3     install this version instead of the latest
#   WATCHDOG_PREFIX=DIR     install under DIR instead of ~/.local
#   WATCHDOG_SKIP_DEPS=1    do not touch system packages (print what is missing instead)
#   WATCHDOG_BASE_URL=URL   for testing: serve the release files from another place
#
# Playing needs a BDIX connection (the media servers are not on the public internet).
# The tarball is verified by checksum only (Linux builds are not code-signed).
set -eu

REPO="mahmudulHmanik/watchdog"
PREFIX="${WATCHDOG_PREFIX:-$HOME/.local}"
OPT="$PREFIX/opt"
BIN="$PREFIX/bin"
SHARE="$PREFIX/share"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---- uninstall ---------------------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$OPT"/watchdog "$OPT"/watchdog-v*
  rm -f "$BIN/watchdog" "$SHARE/applications/watchdog.desktop" \
    "$SHARE/icons/hicolor/256x256/apps/watchdog.png" \
    "$SHARE/icons/hicolor/scalable/apps/watchdog.svg"
  have update-desktop-database && update-desktop-database "$SHARE/applications" 2>/dev/null || true
  say "watchdog removed. Its settings and index stay in ~/.local/share/dev.watchdog.watchdog (delete by hand if you want)."
  exit 0
fi

have curl || die "curl is required"
have tar || die "tar is required"
[ "$(uname -s)" = Linux ] || die "this installer is for Linux"
[ "$(uname -m)" = x86_64 ] || die "only x86_64 Linux builds are published (this is $(uname -m))"

# ---- system dependencies -----------------------------------------------------------------
# Debian-family package for libmpv differs by release: libmpv2 (new) or libmpv1 (older).
deps_family=""
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  ids=" ${ID:-} ${ID_LIKE:-} "
  case "$ids" in
    *" arch "*|*" omarchy "*) deps_family=arch ;;
    *" debian "*|*" ubuntu "*) deps_family=debian ;;
    *" fedora "*|*" rhel "*) deps_family=fedora ;;
  esac
fi

SUDO=""
as_root() {
  if [ "$(id -u)" = 0 ]; then "$@" < /dev/null
  elif have sudo; then sudo "$@" < /dev/null
  else return 1
  fi
}

missing=""
case "$deps_family" in
  arch)
    want="mpv gtk3 libsecret"
    for p in $want; do pacman -Q "$p" >/dev/null 2>&1 || missing="$missing $p"; done
    install_cmd="pacman -S --needed --noconfirm"
    ;;
  debian)
    libmpv=libmpv2
    have apt-cache && ! apt-cache show libmpv2 >/dev/null 2>&1 && libmpv=libmpv1
    want="$libmpv libgtk-3-0 libsecret-1-0"
    for p in $want; do dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"; done
    install_cmd="apt-get install -y"
    ;;
  fedora)
    want="mpv-libs gtk3 libsecret"
    for p in $want; do rpm -q "$p" >/dev/null 2>&1 || missing="$missing $p"; done
    install_cmd="dnf install -y"
    ;;
  *)
    say "note: unknown distribution, so system packages are not checked."
    say "      watchdog needs these libraries: libmpv, GTK 3, libsecret."
    ;;
esac

if [ -n "$missing" ] && [ "${WATCHDOG_SKIP_DEPS:-0}" != 1 ]; then
  say "installing system packages:$missing (needs sudo)"
  # shellcheck disable=SC2086
  as_root $install_cmd $missing \
    || die "could not install:$missing. Run '$install_cmd$missing' as root, then run this again."
elif [ -n "$missing" ]; then
  say "missing system packages (skipped, WATCHDOG_SKIP_DEPS=1):$missing"
fi

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

pkg="watchdog-$tag-linux-x64.tar.gz"
base="${WATCHDOG_BASE_URL:-https://github.com/$REPO/releases/download/$tag}"

# ---- download + verify -------------------------------------------------------------------
tmp=$(mktemp -d 2>/dev/null || mktemp -d -t watchdog)
trap 'rm -rf "$tmp"' EXIT INT TERM

say "watchdog $tag"
say "downloading $pkg ..."
curl -fL --progress-bar -o "$tmp/$pkg" "$base/$pkg" \
  || die "download failed: $base/$pkg (no Linux build published for $tag?)"
curl -fsSL -o "$tmp/$pkg.sha256" "$base/$pkg.sha256" || die "checksum file missing for $tag"

want=$(sed -n 's/^\([0-9a-fA-F]\{64\}\).*/\1/p' "$tmp/$pkg.sha256" | head -n 1 | tr 'A-F' 'a-f')
[ -n "$want" ] || die "could not read the checksum file"
if have sha256sum; then got=$(sha256sum "$tmp/$pkg" | cut -d' ' -f1)
elif have shasum; then got=$(shasum -a 256 "$tmp/$pkg" | cut -d' ' -f1)
elif have openssl; then got=$(openssl dgst -sha256 "$tmp/$pkg" | sed 's/^.*= //')
else die "need sha256sum, shasum or openssl to verify the download"
fi
[ "$got" = "$want" ] || die "checksum mismatch (expected $want, got $got). Not installing."
say "checksum OK ($got)"

# ---- install (no root) -------------------------------------------------------------------
mkdir -p "$tmp/x"
tar -xzf "$tmp/$pkg" -C "$tmp/x"
src="$tmp/x/watchdog-$tag-linux-x64"
[ -x "$src/watchdog" ] || die "unexpected archive layout (no executable 'watchdog' inside)"

mkdir -p "$OPT" "$BIN" "$SHARE/applications" "$SHARE/icons/hicolor/256x256/apps" \
  "$SHARE/icons/hicolor/scalable/apps"
dest="$OPT/watchdog-$tag"
rm -rf "$dest"
mv "$src" "$dest"

# Switch over only after the new files are in place.
ln -sfn "$dest" "$OPT/watchdog"
ln -sfn "$OPT/watchdog/watchdog" "$BIN/watchdog"
for old in "$OPT"/watchdog-v*; do
  [ "$old" = "$dest" ] || rm -rf "$old"
done

[ -f "$dest/watchdog.png" ] && cp "$dest/watchdog.png" "$SHARE/icons/hicolor/256x256/apps/watchdog.png"
[ -f "$dest/watchdog.svg" ] && cp "$dest/watchdog.svg" "$SHARE/icons/hicolor/scalable/apps/watchdog.svg"
cat > "$SHARE/applications/watchdog.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=watchdog
Comment=Unofficial browser and player for DhakaFlix media servers
Exec=$BIN/watchdog
Icon=watchdog
Terminal=false
Categories=AudioVideo;Video;
Keywords=media;video;player;
StartupWMClass=dev.watchdog.watchdog
EOF
have update-desktop-database && update-desktop-database "$SHARE/applications" 2>/dev/null || true
have gtk-update-icon-cache && gtk-update-icon-cache -q -t "$SHARE/icons/hicolor" 2>/dev/null || true

# Anything the dynamic linker still cannot find?
if have ldd; then
  lack=$(ldd "$dest/watchdog" 2>/dev/null | sed -n 's/^[[:space:]]*\(.*\) => not found.*/\1/p' | tr '\n' ' ')
  [ -z "$lack" ] || say "warning: missing libraries: $lack (install them and run again)"
fi

say "done: watchdog $tag installed. Start it from your launcher or run: watchdog"
case ":${PATH:-}:" in
  *":$BIN:"*) ;;
  *) say "note: $BIN is not in your PATH; add it to run 'watchdog' from a terminal." ;;
esac
