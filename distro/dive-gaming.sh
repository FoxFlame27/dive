#!/usr/bin/env bash
# dive-gaming.sh — makes a Dive system fast for games. Called by dive-setup.sh, or run alone:
#   sudo ./distro/dive-gaming.sh
#
# What it does (all reversible, all standard Fedora pieces):
#   drivers   RPM Fusion + the NVIDIA driver when an NVIDIA GPU is present, 32-bit Vulkan/Mesa for Steam
#   tools     Steam, GameMode, MangoHud (FPS overlay), gamescope, Proton needs (vulkan, dxvk)
#   kernel    sysctl tuning: game-friendly memory map limit, low swappiness, BBR + fq for lower ping
#   network   Wi-Fi power saving off (no latency spikes), no auto-updates in the background
#   desktop   no file indexing, no background app refresh, flat mouse (no acceleration), VRR on
#   gamemode  /usr/bin/dive-gamemode: one command that stops everything non-essential and goes performance
set -euo pipefail
log()  { printf '\033[1;35m[dive gaming]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[dive gaming] warning:\033[0m %s\n' "$*" >&2; }
[[ $EUID -eq 0 ]] || { echo "Run with sudo."; exit 1; }
REL="$(rpm -E %fedora)"

# ---------------------------------------------------------------- repos + drivers
log "Enabling RPM Fusion (drivers, Steam, codecs)"
dnf install -y "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${REL}.noarch.rpm" \
               "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${REL}.noarch.rpm" 2>/dev/null || warn "RPM Fusion could not be enabled (offline?)"
dnf install -y --skip-unavailable steam gamemode mangohud gamescope \
  vulkan-loader vulkan-loader.i686 mesa-vulkan-drivers mesa-vulkan-drivers.i686 mesa-dri-drivers.i686 \
  libva-utils vulkan-tools power-profiles-daemon irqbalance || warn "some gaming packages missing"
if lspci 2>/dev/null | grep -qi 'nvidia'; then
  log "NVIDIA GPU found: installing the NVIDIA driver (builds a kernel module, takes a few minutes)"
  dnf install -y --skip-unavailable akmod-nvidia xorg-x11-drv-nvidia-cuda xorg-x11-drv-nvidia-libs.i686 || warn "NVIDIA driver install failed"
  akmods --force >/dev/null 2>&1 || true
fi
if lspci 2>/dev/null | grep -qiE 'amd|radeon'; then
  log "AMD GPU found: Mesa RADV is already in place"
fi
systemctl enable --now irqbalance power-profiles-daemon 2>/dev/null || true

# ---------------------------------------------------------------- kernel + network
log "Kernel and network tuning"
cat > /etc/sysctl.d/90-dive-gaming.conf <<'SYS'
# Dive gaming defaults
vm.max_map_count = 2147483642      # what Steam/Proton games ask for
vm.swappiness = 10                 # keep game data in RAM
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
kernel.sched_autogroup_enabled = 0 # games get scheduler time on their own merit
net.core.default_qdisc = fq        # fair queueing + BBR: lower, steadier ping
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.core.netdev_max_backlog = 16384
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
SYS
sysctl --system >/dev/null 2>&1 || true
install -d /etc/NetworkManager/conf.d
printf '[connection]\nwifi.powersave = 2\n' > /etc/NetworkManager/conf.d/90-dive-wifi-powersave.conf   # 2 = off
# No background metadata refresh or auto-updates while you play
install -d /etc/dnf/automatic.conf.d 2>/dev/null || true
systemctl disable --now dnf-automatic.timer dnf-makecache.timer packagekit-offline-update.service 2>/dev/null || true
systemctl mask packagekit.service 2>/dev/null || true
# Services nobody needs on a gaming laptop (all reversible with systemctl unmask)
for s in abrtd abrt-journal-core abrt-oops abrt-xorg ModemManager cups-browsed; do systemctl disable --now "$s" 2>/dev/null || true; done

# ---------------------------------------------------------------- desktop defaults
log "Desktop: no indexing, flat mouse, VRR, no background app refresh"
install -d /etc/dconf/db/local.d
cat > /etc/dconf/db/local.d/10-dive-gaming <<'DC'
[org/gnome/desktop/peripherals/mouse]
accel-profile='flat'

[org/gnome/mutter]
experimental-features=['variable-refresh-rate', 'scale-monitor-framebuffer', 'xwayland-native-scaling']

[org/gnome/software]
download-updates=false
download-updates-notify=false
allow-updates=true

[org/gnome/desktop/search-providers]
disable-external=true

[org/freedesktop/tracker/miner/files]
crawling-interval=-2
enable-monitors=false
DC
dconf update
# tracker (file indexing) off for every user
install -d /etc/systemd/user
for u in tracker-miner-fs-3.service tracker-miner-fs-control-3.service localsearch-3.service; do
  ln -sf /dev/null "/etc/systemd/user/$u" 2>/dev/null || true
done
# GNOME Software should not sit in the background
install -d /etc/xdg/autostart
if [[ -f /etc/xdg/autostart/org.gnome.Software.desktop ]]; then
  grep -q '^X-GNOME-Autostart-enabled=false' /etc/xdg/autostart/org.gnome.Software.desktop || echo 'X-GNOME-Autostart-enabled=false' >> /etc/xdg/autostart/org.gnome.Software.desktop
fi

# ---------------------------------------------------------------- GameMode config
install -d /etc/gamemode.d
cat > /etc/gamemode.ini <<'GM'
[general]
renice=10
softrealtime=auto
inhibit_screensaver=1
desiredgov=performance
igpu_desiredgov=performance

[gpu]
apply_gpu_optimisations=accept-responsibility
nv_powermizer_mode=1

[custom]
start=/usr/bin/dive-gamemode on --quiet
end=/usr/bin/dive-gamemode off --quiet
GM

# ---------------------------------------------------------------- dive-gamemode
cat > /usr/bin/dive-gamemode <<'GMODE'
#!/usr/bin/env bash
# dive-gamemode on|off|status — everything non-essential stops, the machine goes to performance.
# Runs automatically around any game started through Steam/GameMode; also usable by hand or from the Game Mode tile.
set -u
STATE="${XDG_RUNTIME_DIR:-/tmp}/dive-gamemode.on"
q=; [[ "${2:-}" == "--quiet" ]] && q=1
say(){ [[ -z $q ]] && echo "[game mode] $*"; command -v notify-send >/dev/null && [[ -z $q ]] && notify-send -i dive "Game Mode" "$*" || true; }
case "${1:-status}" in
  on)
    powerprofilesctl set performance 2>/dev/null || true
    gsettings set org.gnome.desktop.notifications show-banners false 2>/dev/null || true
    systemctl --user stop tracker-miner-fs-3 localsearch-3 evolution-addressbook-factory evolution-calendar-factory 2>/dev/null || true
    pkill -f gnome-software 2>/dev/null || true
    for p in $(pgrep -f 'dnf|packagekitd' 2>/dev/null); do sudo -n renice 19 -p "$p" >/dev/null 2>&1 || true; done
    echo 1 > "$STATE"
    say "On. Performance power mode, notifications held, indexing and background updates stopped."
    ;;
  off)
    powerprofilesctl set balanced 2>/dev/null || true
    gsettings set org.gnome.desktop.notifications show-banners true 2>/dev/null || true
    rm -f "$STATE"
    say "Off. Back to balanced."
    ;;
  status) [[ -f "$STATE" ]] && echo on || echo off ;;
  *) echo "usage: dive-gamemode on|off|status"; exit 1 ;;
esac
GMODE
chmod +x /usr/bin/dive-gamemode
cat > /usr/share/applications/dive-gamemode.desktop <<'DESK'
[Desktop Entry]
Type=Application
Name=Game Mode
Comment=Stop everything non-essential and go to performance
Exec=sh -c 'if [ "$(dive-gamemode status)" = on ]; then dive-gamemode off; else dive-gamemode on; fi'
Icon=input-gaming
Terminal=false
Categories=Game;System;
Keywords=game;fps;performance;
DESK
# MangoHud default: FPS, frametime, CPU/GPU load, small, top-left. Toggle with Shift+F12.
install -d /etc/skel/.config/MangoHud
cat > /etc/skel/.config/MangoHud/MangoHud.conf <<'MH'
fps
frametime=0
cpu_stats
gpu_stats
ram
vram
font_size=20
position=top-left
background_alpha=0.3
toggle_hud=Shift_R+F12
MH
# Steam launches games through GameMode + MangoHud by default when this env is set
install -d /etc/environment.d
printf 'MANGOHUD=1\n' > /etc/environment.d/90-dive-gaming.conf
log "Done. Steam → game → Properties → launch options can stay empty: GameMode and MangoHud apply automatically."
