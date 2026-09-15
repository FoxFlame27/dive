#!/usr/bin/env bash
# dive-setup.sh — turns a Fedora Workstation (42 or newer) into Dive.
#
#   sudo ./distro/dive-setup.sh            # on a running Fedora (VM or PC)
#   bash dive-setup.sh image               # inside the ISO build (%post)
#
# Everything it does is additive: packages, extensions, defaults, branding,
# GRUB theme, Dive Bridge, Dive Migrate and the first-run app.
set -euo pipefail

MODE="${1:-live}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIVE_VERSION="0.1"
DIVE_CODENAME="Coral"
SHARE=/usr/share/dive
EXT_DIR=/usr/share/gnome-shell/extensions

log()  { printf '\033[1;36m[dive]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[dive] warning:\033[0m %s\n' "$*" >&2; }

[[ $EUID -eq 0 ]] || { echo "Run this with sudo."; exit 1; }
[[ -r /etc/fedora-release ]] || { echo "Dive is built on Fedora Workstation. Install that first."; exit 1; }
ARCH="$(uname -m)"

# ---------------------------------------------------------------- packages
log "Installing packages"
PKGS=(gnome-shell gnome-extensions-app gnome-tweaks curl jq unzip
      python3 python3-gobject gtk4 libadwaita zenity libnotify
      os-prober ntfs-3g ntfsprogs efibootmgr flatpak
      google-noto-sans-fonts google-noto-sans-mono-fonts)
dnf install -y "${PKGS[@]}"
if [[ "$ARCH" == "x86_64" ]]; then
  dnf install -y wine winetricks || warn "Wine could not be installed; .exe support will be missing"
else
  warn "This machine is $ARCH. Windows programs need an x86_64 PC; skipping Wine."
fi
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

# ---------------------------------------------------------------- shared files
log "Installing Dive files to $SHARE"
install -d "$SHARE" "$SHARE/grub" /usr/share/backgrounds/dive /usr/share/pixmaps
install -m644 "$ROOT/distro/files/art/dive-logo.svg" "$SHARE/dive-logo.svg"
install -m644 "$ROOT/distro/files/art/dive-logo.png" "$SHARE/dive-logo.png"
install -m644 "$ROOT/distro/files/art/dive-logo.png" /usr/share/pixmaps/dive.png
install -d /usr/share/icons/hicolor/512x512/apps
install -m644 "$ROOT/distro/files/art/dive-logo.png" /usr/share/icons/hicolor/512x512/apps/dive.png
gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
install -m644 "$ROOT/distro/files/grub/theme.txt" "$SHARE/grub/theme.txt"
python3 "$ROOT/distro/files/art/make-art.py" \
  --wallpaper /usr/share/backgrounds/dive/dive-deep.png \
  --grub "$SHARE/grub/background.png"
# GRUB fonts (Fedora ships unicode.pf2)
for f in /usr/share/grub/unicode.pf2 /boot/grub2/fonts/unicode.pf2; do
  [[ -r "$f" ]] && { cp "$f" "$SHARE/grub/unicode.pf2"; break; }
done

# ---------------------------------------------------------------- GNOME extensions
shell_major="$(gnome-shell --version | grep -oE '[0-9]+' | head -1)"
log "GNOME Shell $shell_major"

install_ego() {  # install an extension from extensions.gnome.org system-wide
  local uuid="$1" info url tmp
  if [[ -d "$EXT_DIR/$uuid" ]]; then log "  $uuid already installed"; return 0; fi
  info="$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=${uuid}&shell_version=${shell_major}" || true)"
  url="$(printf '%s' "$info" | jq -r '.download_url // empty')"
  if [[ -z "$url" ]]; then warn "  no build of $uuid for GNOME $shell_major on extensions.gnome.org"; return 1; fi
  tmp="$(mktemp -d)"
  curl -fsSL "https://extensions.gnome.org${url}" -o "$tmp/ext.zip"
  install -d "$EXT_DIR/$uuid"
  unzip -qo "$tmp/ext.zip" -d "$EXT_DIR/$uuid"
  if [[ -d "$EXT_DIR/$uuid/schemas" ]]; then glib-compile-schemas "$EXT_DIR/$uuid/schemas" || true; fi
  rm -rf "$tmp"
  log "  installed $uuid"
}

log "Installing shell extensions"
dnf install -y gnome-shell-extension-dash-to-dock 2>/dev/null || install_ego dash-to-dock@micxgx.gmail.com || warn "Dash to Dock missing"
install_ego arcmenu@arcmenu.com            || warn "ArcMenu missing (the Dive menu)"
install_ego clipboard-indicator@tudmotu.com || warn "Clipboard history missing"

log "Installing the Dive hover bar extension"
install -d "$EXT_DIR/dive-hoverbar@dive.sh"
cp -r "$ROOT/shell/dive-hoverbar@dive.sh/." "$EXT_DIR/dive-hoverbar@dive.sh/"

# ---------------------------------------------------------------- defaults (dconf)
log "Writing system defaults"
install -d /etc/dconf/profile /etc/dconf/db/local.d
printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user
install -m644 "$ROOT/distro/files/dconf/00-dive" /etc/dconf/db/local.d/00-dive
dconf update

# ---------------------------------------------------------------- Dive Bridge (.exe)
log "Installing Dive Bridge"
install -m755 "$ROOT/bridge/dive-bridge" /usr/bin/dive-bridge
install -m644 "$ROOT/bridge/dive-bridge.desktop" /usr/share/applications/dive-bridge.desktop
install -d /etc/xdg
if ! grep -qs 'dive-bridge.desktop' /etc/xdg/mimeapps.list 2>/dev/null; then
  cat >> /etc/xdg/mimeapps.list <<'MIME'
[Default Applications]
application/x-ms-dos-executable=dive-bridge.desktop
application/x-msdownload=dive-bridge.desktop
application/vnd.microsoft.portable-executable=dive-bridge.desktop
application/x-msi=dive-bridge.desktop
MIME
fi
update-desktop-database /usr/share/applications || true

# ---------------------------------------------------------------- Gaming
log "Gaming: drivers, Steam, GameMode, tuning"
bash "$ROOT/distro/dive-gaming.sh" || warn "gaming setup had errors (see above)"

# ---------------------------------------------------------------- Migrate + Welcome
log "Installing Dive Migrate and the first-run app"
install -m755 "$ROOT/migrate/dive-migrate.py" /usr/bin/dive-migrate
install -m755 "$ROOT/welcome/dive-welcome.py" /usr/bin/dive-welcome
install -m644 "$ROOT/welcome/dive-welcome.desktop" /usr/share/applications/dive-welcome.desktop
install -d /etc/xdg/autostart
install -m644 "$ROOT/welcome/dive-welcome-autostart.desktop" /etc/xdg/autostart/dive-welcome.desktop

# ---------------------------------------------------------------- branding
log "Branding"
if [[ -L /etc/os-release || -f /etc/os-release ]]; then
  src="$(readlink -f /etc/os-release)"
  tmp="$(mktemp)"
  sed -e "s/^PRETTY_NAME=.*/PRETTY_NAME=\"Dive $DIVE_VERSION ($DIVE_CODENAME)\"/" \
      -e "s/^NAME=.*/NAME=\"Dive\"/" \
      -e "s/^LOGO=.*/LOGO=dive/" "$src" > "$tmp"
  grep -q '^LOGO=' "$tmp" || echo 'LOGO=dive' >> "$tmp"
  rm -f /etc/os-release; install -m644 "$tmp" /etc/os-release; rm -f "$tmp"
fi
cat > /etc/dive-release <<REL
DIVE_VERSION=$DIVE_VERSION
DIVE_CODENAME=$DIVE_CODENAME
REL

# ---------------------------------------------------------------- GRUB boot menu
log "Configuring the boot menu"
GRUBDEF=/etc/default/grub
touch "$GRUBDEF"
set_grub() { local k="$1" v="$2"; if grep -q "^$k=" "$GRUBDEF"; then sed -i "s|^$k=.*|$k=$v|" "$GRUBDEF"; else echo "$k=$v" >> "$GRUBDEF"; fi; }
set_grub GRUB_TIMEOUT 10
set_grub GRUB_TIMEOUT_STYLE menu
set_grub GRUB_DISTRIBUTOR '"Dive"'
set_grub GRUB_DISABLE_OS_PROBER false
set_grub GRUB_TERMINAL_OUTPUT gfxterm
set_grub GRUB_GFXMODE auto
set_grub GRUB_THEME "$SHARE/grub/theme.txt"
if [[ "$MODE" == "live" ]]; then
  if [[ -d /sys/firmware/efi ]]; then
    grub2-mkconfig -o /boot/grub2/grub.cfg || warn "grub2-mkconfig failed"
  else
    grub2-mkconfig -o /boot/grub2/grub.cfg || warn "grub2-mkconfig failed"
  fi
  # Remove the temporary firmware entry the Windows installer created, if present.
  if command -v efibootmgr >/dev/null && [[ -d /sys/firmware/efi ]]; then
    efibootmgr | grep -i 'Dive Installer' | grep -oE 'Boot[0-9A-F]{4}' | sed 's/Boot//' | while read -r n; do efibootmgr -b "$n" -B >/dev/null || true; done
  fi
fi

# ---------------------------------------------------------------- finish
if [[ "$MODE" == "live" && -n "${SUDO_USER:-}" ]]; then
  log "Enabling extensions for $SUDO_USER"
  for e in dash-to-dock@micxgx.gmail.com arcmenu@arcmenu.com clipboard-indicator@tudmotu.com dive-hoverbar@dive.sh; do
    [[ -d "$EXT_DIR/$e" ]] && sudo -u "$SUDO_USER" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$SUDO_USER")/bus" gnome-extensions enable "$e" 2>/dev/null || true
  done
fi
log "Done. Log out and back in (or reboot) to see Dive."
log "If the Super key does not open the Dive menu, open ArcMenu Settings and set Menu Hotkey to Left Super."
log "To put the Dive button in the dock: ArcMenu Settings → General → Display ArcMenu on → Dash to Dock."
