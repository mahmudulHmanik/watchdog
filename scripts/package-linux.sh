#!/usr/bin/env bash
# Package the Linux release bundle as dist/watchdog-<version>-linux-x86_64.tar.gz
# (bundle + install.sh + desktop entry + icons). Run scripts/build-linux.sh first.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

ver="$(sed -n 's/^version: \([0-9.]*\).*/\1/p' pubspec.yaml)"
bundle="build/linux/x64/release/bundle"
[ -x "$bundle/watchdog" ] || { echo "Missing $bundle. Run scripts/build-linux.sh first." >&2; exit 1; }

name="watchdog-$ver-linux-x86_64"
out="dist/$name"
rm -rf "$out" && mkdir -p "$out/app" dist
cp -r "$bundle/." "$out/app/"
cp packaging/linux/watchdog.desktop packaging/linux/watchdog.png packaging/linux/watchdog.svg "$out/"
cp LICENSE NOTICE "$out/"

cat > "$out/install.sh" <<'INSTALL'
#!/usr/bin/env bash
# User-level install (no sudo): ~/.local/opt/watchdog, launcher entry, icon.
# Needs mpv (libmpv) installed: pacman -S mpv / apt install libmpv2 / dnf install mpv-libs
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
d="$HOME/.local/opt/watchdog"
mkdir -p "$d" "$HOME/.local/bin" "$HOME/.local/share/applications" \
  "$HOME/.local/share/icons/hicolor/256x256/apps" "$HOME/.local/share/icons/hicolor/scalable/apps"
rm -rf "$d"/* && cp -r "$here/app/." "$d/"
ln -sf "$d/watchdog" "$HOME/.local/bin/watchdog"
sed "s|^Exec=.*|Exec=$d/watchdog|" "$here/watchdog.desktop" > "$HOME/.local/share/applications/watchdog.desktop"
cp "$here/watchdog.png" "$HOME/.local/share/icons/hicolor/256x256/apps/watchdog.png"
cp "$here/watchdog.svg" "$HOME/.local/share/icons/hicolor/scalable/apps/watchdog.svg"
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
command -v mpv >/dev/null || echo "Note: install mpv/libmpv or playback will not work."
echo "Installed. Run: watchdog (make sure ~/.local/bin is on PATH)"
INSTALL
cat > "$out/uninstall.sh" <<'UNINSTALL'
#!/usr/bin/env bash
rm -rf "$HOME/.local/opt/watchdog" "$HOME/.local/bin/watchdog" \
  "$HOME/.local/share/applications/watchdog.desktop" \
  "$HOME"/.local/share/icons/hicolor/*/apps/watchdog.*
echo "Removed."
UNINSTALL
chmod +x "$out/install.sh" "$out/uninstall.sh"
tar -C dist -czf "dist/$name.tar.gz" "$name"
rm -rf "$out"
( cd dist && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256" )
echo "dist/$name.tar.gz ($(du -h "dist/$name.tar.gz" | cut -f1))"
