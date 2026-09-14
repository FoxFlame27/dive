#!/usr/bin/env python3
"""dive-migrate — bring files, apps, browser data and Wi‑Fi over from Windows.

    dive-migrate scan                       # what Windows installs and users exist
    dive-migrate run  [--user NAME] [--files] [--apps] [--browser] [--wifi] [--all]
    dive-migrate export-dir                 # where the Windows installer left its exports

Windows stays untouched: its partition is mounted read-only and files are
linked, not copied. Passwords saved in Chrome or Edge cannot be read outside
Windows (they are locked with the Windows account), so Chrome and Edge get
bookmarks and settings and are asked to sign in once. Firefox profiles move whole,
including saved logins.
"""
import argparse, json, os, shutil, subprocess, sys, xml.etree.ElementTree as ET
from pathlib import Path

HOME = Path.home()
MNT = Path('/run/dive/windows')
EXPORT_LABEL = 'DIVE_LIVE'

# winget package id  ->  Flatpak id on Flathub (or a note)
APP_MAP = {
    'Discord.Discord': 'com.discordapp.Discord',
    'Spotify.Spotify': 'com.spotify.Client',
    'Valve.Steam': 'com.valvesoftware.Steam',
    'Microsoft.VisualStudioCode': 'com.visualstudio.code',
    'Google.Chrome': 'com.google.Chrome',
    'Mozilla.Firefox': 'org.mozilla.firefox',
    'Microsoft.Edge': 'com.microsoft.Edge',
    'Brave.Brave': 'com.brave.Browser',
    'VideoLAN.VLC': 'org.videolan.VLC',
    'OBSProject.OBSStudio': 'com.obsproject.Studio',
    'SlackTechnologies.Slack': 'com.slack.Slack',
    'Zoom.Zoom': 'us.zoom.Zoom',
    'Telegram.TelegramDesktop': 'org.telegram.desktop',
    'GIMP.GIMP': 'org.gimp.GIMP',
    'BlenderFoundation.Blender': 'org.blender.Blender',
    'Bitwarden.Bitwarden': 'com.bitwarden.desktop',
    'Audacity.Audacity': 'org.audacityteam.Audacity',
    'KDE.Krita': 'org.kde.krita',
    'Inkscape.Inkscape': 'org.inkscape.Inkscape',
    'TheDocumentFoundation.LibreOffice': 'org.libreoffice.LibreOffice',
    'EpicGames.EpicGamesLauncher': 'com.heroicgameslauncher.hgl',
    'Notion.Notion': 'notion-app-enhanced? (no official Linux app; use notion.so in the browser)',
    'WhatsApp.WhatsApp': '(no Linux app; use web.whatsapp.com)',
    'Microsoft.Teams': 'com.github.IsmaelMartinez.teams_for_linux',
    'Microsoft.Office': '(Office runs partly through Dive Bridge; Office on the web works fully)',
    'Adobe.Acrobat.Reader.64-bit': '(use Document Viewer; Acrobat works through Dive Bridge)',
    '7zip.7zip': '(built in: Files handles archives)',
    'Notepad++.Notepad++': 'org.gnome.TextEditor (built in)',
    'Git.Git': '(built in: sudo dnf install git)',
    'Python.Python.3.12': '(built in: python3)',
    'Oracle.JavaRuntimeEnvironment': '(sudo dnf install java-latest-openjdk)',
    'Nvidia.GeForceExperience': '(not needed on Dive)',
    'Logitech.GHUB': '(not available; use Solaar from Software)',
}

def sh(*cmd, check=True, capture=True):
    return subprocess.run(cmd, check=check, text=True, capture_output=capture)

def say(msg): print(f'[dive-migrate] {msg}', flush=True)

# ------------------------------------------------------------------ discovery
def block_devices():
    out = sh('lsblk', '-J', '-o', 'NAME,PATH,FSTYPE,LABEL,SIZE,MOUNTPOINT,UUID').stdout
    devs = []
    def walk(nodes):
        for n in nodes:
            devs.append(n); walk(n.get('children', []))
    walk(json.loads(out)['blockdevices'])
    return devs

def find_windows_partition():
    best = None
    for d in block_devices():
        if d.get('fstype') != 'ntfs': continue
        if d.get('mountpoint') and Path(d['mountpoint'], 'Windows').is_dir():
            return d, Path(d['mountpoint'])
        # pick the biggest NTFS partition, that is C:
        if best is None or size_bytes(d['size']) > size_bytes(best['size']): best = d
    return best, None

def size_bytes(s):
    units = {'K': 1e3, 'M': 1e6, 'G': 1e9, 'T': 1e12}
    return float(s[:-1]) * units.get(s[-1], 1) if s and s[-1] in units else float(s or 0)

def mount_windows():
    dev, mnt = find_windows_partition()
    if dev is None: return None
    if mnt: return mnt
    MNT.mkdir(parents=True, exist_ok=True)
    # read-only: Windows "fast startup" leaves NTFS half-open; writing then is unsafe.
    for fstype in ('ntfs3', 'ntfs-3g', 'ntfs'):
        r = subprocess.run(['sudo', 'mount', '-t', fstype, '-o', 'ro,noatime', dev['path'], str(MNT)], capture_output=True, text=True)
        if r.returncode == 0: return MNT
    say(f'could not mount {dev["path"]}: {r.stderr.strip()}')
    return None

def windows_users(root):
    users = []
    for p in sorted((root / 'Users').glob('*')):
        if p.name.lower() in ('public', 'default', 'default user', 'all users') or not p.is_dir(): continue
        if (p / 'NTUSER.DAT').exists() or (p / 'Desktop').exists(): users.append(p)
    return users

def export_dir():
    """Folder the Windows installer wrote to the DIVE_LIVE partition."""
    for d in block_devices():
        if d.get('label') == EXPORT_LABEL:
            mp = d.get('mountpoint')
            if not mp:
                mp = f'/run/dive/{EXPORT_LABEL}'
                Path(mp).mkdir(parents=True, exist_ok=True)
                if subprocess.run(['sudo', 'mount', '-o', 'ro', d['path'], mp], capture_output=True).returncode != 0: continue
            e = Path(mp, 'dive-migrate')
            if e.is_dir(): return e
    return None

# ------------------------------------------------------------------ steps
def step_files(user):
    say('Linking your Windows folders')
    link_root = HOME / 'Windows'
    if not link_root.exists(): link_root.symlink_to(user)
    for name in ('Desktop', 'Documents', 'Pictures', 'Downloads', 'Music', 'Videos'):
        src = user / name
        if not src.is_dir(): continue
        dst = HOME / name / f'{name} (Windows)'
        (HOME / name).mkdir(exist_ok=True)
        if not dst.exists(): dst.symlink_to(src)
    bm = HOME / '.config/gtk-3.0/bookmarks'
    bm.parent.mkdir(parents=True, exist_ok=True)
    line = f'file://{user} Windows files\n'
    if not bm.exists() or line not in bm.read_text(): bm.open('a').write(line)
    # remount at boot, read-only
    dev, _ = find_windows_partition()
    if dev and dev.get('uuid'):
        entry = f'UUID={dev["uuid"]} {MNT} ntfs3 ro,noatime,nofail,x-systemd.automount,uid={os.getuid()},gid={os.getgid()} 0 0\n'
        fstab = Path('/etc/fstab').read_text()
        if dev['uuid'] not in fstab:
            subprocess.run(['sudo', 'tee', '-a', '/etc/fstab'], input=entry, text=True, capture_output=True)
    say(f'Your Windows files are in Files → Windows files, and in each folder as "<Folder> (Windows)".')

def step_wifi(exp):
    if not exp: say('No Wi‑Fi export found (it is written by the Windows installer).'); return
    n = 0
    for xml in sorted(exp.glob('wifi/*.xml')):
        try:
            ns = {'w': 'http://www.microsoft.com/networking/WLAN/profile/v1'}
            t = ET.parse(xml).getroot()
            ssid = t.findtext('w:SSIDConfig/w:SSID/w:name', namespaces=ns) or t.findtext('w:name', namespaces=ns)
            auth = (t.findtext('.//w:authentication', namespaces=ns) or 'open').upper()
            key = t.findtext('.//w:keyMaterial', namespaces=ns)
            if not ssid: continue
            cmd = ['nmcli', 'connection', 'add', 'type', 'wifi', 'con-name', ssid, 'ssid', ssid]
            if key and auth in ('WPA2PSK', 'WPAPSK', 'WPA2', 'WPA'):
                cmd += ['wifi-sec.key-mgmt', 'wpa-psk', 'wifi-sec.psk', key]
            elif key and auth == 'WPA3SAE':
                cmd += ['wifi-sec.key-mgmt', 'sae', 'wifi-sec.psk', key]
            r = subprocess.run(cmd, capture_output=True, text=True)
            if r.returncode == 0: n += 1
            else: say(f'  {ssid}: {r.stderr.strip()}')
        except ET.ParseError:
            pass
    say(f'{n} Wi‑Fi network(s) added.')

def step_apps(exp, install=True):
    src = exp / 'winget-export.json' if exp else None
    if not src or not src.exists():
        say('No app list found (winget export). Skipping apps.'); return
    ids = [p.get('PackageIdentifier') for s in json.loads(src.read_text(encoding='utf-8-sig')).get('Sources', []) for p in s.get('Packages', [])]
    ids = [i for i in ids if i]
    say(f'{len(ids)} Windows apps found')
    todo, notes, unknown = [], [], []
    for i in ids:
        m = APP_MAP.get(i)
        if m is None: unknown.append(i)
        elif m.startswith('(') or '?' in m or ' ' in m: notes.append((i, m))
        else: todo.append((i, m))
    if install and todo:
        subprocess.run(['flatpak', 'remote-add', '--user', '--if-not-exists', 'flathub', 'https://dl.flathub.org/repo/flathub.flatpakrepo'], capture_output=True)
        for i, fp in todo:
            say(f'  installing {i} → {fp}')
            subprocess.run(['flatpak', 'install', '--user', '-y', '--noninteractive', 'flathub', fp], capture_output=True)
    for i, m in notes: say(f'  {i}: {m}')
    if unknown:
        say('  Windows-only or unknown (open their .exe from your Windows files to run them through Dive Bridge):')
        for i in unknown: say(f'    {i}')
    report = HOME / '.config/dive/apps-report.json'
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text(json.dumps({'installed': todo, 'notes': notes, 'unknown': unknown}, indent=2))

def copy_profile_files(src, dst, names):
    if not src.is_dir(): return False
    dst.mkdir(parents=True, exist_ok=True)
    for n in names:
        f = src / n
        if f.exists(): shutil.copy2(f, dst / n)
    return True

def step_browser(user):
    say('Bringing browser data over')
    local = user / 'AppData/Local'; roaming = user / 'AppData/Roaming'
    chrome_like = [
        ('Chrome', local / 'Google/Chrome/User Data/Default', [HOME / '.config/google-chrome/Default', HOME / '.var/app/com.google.Chrome/config/google-chrome/Default']),
        ('Edge',   local / 'Microsoft/Edge/User Data/Default', [HOME / '.config/microsoft-edge/Default', HOME / '.var/app/com.microsoft.Edge/config/microsoft-edge/Default']),
        ('Brave',  local / 'BraveSoftware/Brave-Browser/User Data/Default', [HOME / '.config/BraveSoftware/Brave-Browser/Default', HOME / '.var/app/com.brave.Browser/config/BraveSoftware/Brave-Browser/Default']),
    ]
    for name, src, dsts in chrome_like:
        if not src.is_dir(): continue
        for d in dsts:
            copy_profile_files(src, d, ['Bookmarks', 'Preferences', 'History', 'Favicons', 'Shortcuts', 'Top Sites'])
        say(f'  {name}: bookmarks, history and settings copied. Sign in once to get passwords and extensions back.')
    ff = roaming / 'Mozilla/Firefox/Profiles'
    if ff.is_dir():
        profiles = [p for p in ff.iterdir() if p.is_dir() and (p / 'places.sqlite').exists()]
        if profiles:
            src = max(profiles, key=lambda p: (p / 'places.sqlite').stat().st_size)
            for base in (HOME / '.mozilla/firefox', HOME / '.var/app/org.mozilla.firefox/.mozilla/firefox'):
                dst = base / 'windows.default'
                if dst.exists(): continue
                shutil.copytree(src, dst, ignore=shutil.ignore_patterns('cache2', 'startupCache', 'parent.lock', 'lock', '*.lock'))
                ini = base / 'profiles.ini'
                base.mkdir(parents=True, exist_ok=True)
                n = ini.read_text().count('[Profile') if ini.exists() else 0
                with ini.open('a') as f:
                    if n == 0: f.write('[General]\nStartWithLastProfile=1\nVersion=2\n\n')
                    f.write(f'[Profile{n}]\nName=Windows\nIsRelative=1\nPath=windows.default\nDefault=1\n\n')
            say('  Firefox: whole profile copied, including saved logins.')

# ------------------------------------------------------------------ main
def cmd_scan(a):
    root = mount_windows()
    if not root: print(json.dumps({'windows': None})); return
    users = windows_users(root)
    exp = export_dir()
    info = {'windows': str(root), 'users': [u.name for u in users], 'export': str(exp) if exp else None}
    for u in users:
        sizes = {}
        for n in ('Desktop', 'Documents', 'Pictures', 'Downloads', 'Music', 'Videos'):
            p = u / n
            sizes[n] = sum(f.stat().st_size for f in p.rglob('*') if f.is_file()) if p.is_dir() else 0
        info.setdefault('sizes', {})[u.name] = sizes
    if exp and (exp / 'winget-export.json').exists():
        info['apps'] = len(json.loads((exp / 'winget-export.json').read_text(encoding='utf-8-sig')).get('Sources', [{}])[0].get('Packages', []))
        info['wifi'] = len(list((exp / 'wifi').glob('*.xml')))
    print(json.dumps(info, indent=2))

def cmd_run(a):
    root = mount_windows()
    if not root: say('No Windows installation found on this disk.'); sys.exit(1)
    users = windows_users(root)
    user = next((u for u in users if u.name == a.user), users[0] if users else None)
    if not user: say('No Windows user folders found.'); sys.exit(1)
    exp = export_dir()
    if a.all: a.files = a.apps = a.browser = a.wifi = True
    if a.files: step_files(user)
    if a.browser: step_browser(user)
    if a.wifi: step_wifi(exp)
    if a.apps: step_apps(exp)
    say('Done.')

def cmd_export_dir(a):
    e = export_dir(); print(e or '')

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('scan').set_defaults(f=cmd_scan)
    r = sub.add_parser('run'); r.set_defaults(f=cmd_run)
    r.add_argument('--user'); r.add_argument('--files', action='store_true'); r.add_argument('--apps', action='store_true')
    r.add_argument('--browser', action='store_true'); r.add_argument('--wifi', action='store_true'); r.add_argument('--all', action='store_true')
    sub.add_parser('export-dir').set_defaults(f=cmd_export_dir)
    a = ap.parse_args(); a.f(a)
