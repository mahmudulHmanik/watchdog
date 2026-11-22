#!/usr/bin/env bash
# (Replaces the earlier dist/*-linux-x86_64.tar.gz packager: the tarball now has no bundled
# install.sh; scripts/install-linux.sh is the installer.)
# Package the Linux release bundle for GitHub: build/watchdog-<tag>-linux-x64.tar.gz + .sha256.
# scripts/install-linux.sh downloads exactly this file name. Build first with scripts/build-linux.sh
# (needs gtk3, libsecret, mpv headers, clang, ninja and cmake; mise.toml pins cmake + ninja).
#
#   scripts/package-linux.sh          # package the existing bundle
#   scripts/package-linux.sh --build  # build it first
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if command -v mise >/dev/null 2>&1; then eval "$(mise env)"; fi

ver="$(sed -n 's/^version: *\([0-9][0-9.]*\)+.*/\1/p' pubspec.yaml | head -n1)"
[ -n "$ver" ] || { echo "Cannot read version from pubspec.yaml" >&2; exit 1; }
tag="v$ver"
bundle="build/linux/x64/release/bundle"

if [ "${1:-}" = "--build" ] || [ ! -x "$bundle/watchdog" ]; then
  flutter pub get
  flutter build linux --release
fi
[ -x "$bundle/watchdog" ] || { echo "No Linux bundle at $bundle" >&2; exit 1; }

name="watchdog-$tag-linux-x64"
stage="build/linux-pkg/$name"
rm -rf "build/linux-pkg"
mkdir -p "$stage"
cp -r "$bundle"/. "$stage"/
# libdartjni.so comes from an Android-only package, is never loaded on Linux, and links libjvm.so
# with a RUNPATH into the build machine's JDK: leave it out.
rm -f "$stage/lib/libdartjni.so"
cp packaging/linux/watchdog.png packaging/linux/watchdog.svg packaging/linux/watchdog.desktop "$stage"/
# Apache-2.0 asks for the license and notices to travel with redistributed copies.
cp LICENSE NOTICE "$stage"/

out="build/$name.tar.gz"
tar --owner=0 --group=0 --numeric-owner -czf "$out" -C build/linux-pkg "$name"
(cd build && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
rm -rf "build/linux-pkg"

echo "Package: $out ($(du -h "$out" | cut -f1))"
cat "$out.sha256"
echo "Upload with: gh release upload $tag $out $out.sha256"
