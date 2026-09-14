# Dive

A desktop OS that installs from one command on Windows, boots side by side with it, brings your Windows files, apps and Wi‑Fi over, and runs .exe files. Windows plus GNOME, designed to look good.

Dive is a Linux system (Fedora + GNOME) with its own shell setup, boot menu, installer, migration tool and Windows-app layer. It is not a new kernel: that is the only way to get real hardware support and .exe compatibility in months instead of decades.

## What is in this folder

| Path | What it is |
|---|---|
| `app/` | The Dive desktop as a real app (Electron). Inside it, Chromium loads real web pages, Files shows your real home folder, Terminal runs a real shell, Text Editor and Code read and write real files, Photos shows your real pictures, System Monitor reads real CPU and memory. `npm start` runs it, `npm run build` makes `app/out/Dive-darwin-arm64/Dive.app`. |
| `prototype/dive.html` | Fully working demo of the whole journey. Every app on the desktop works (files, browser, terminal, settings, mail, calendar, music, games, code, Photoshop, Word…), plus right-click menus, quick settings, lock screen, dock position and wallpaper settings. |
| `distro/dive-setup.sh` | Turns a Fedora Workstation into Dive. Used by the ISO build and for testing in a VM. |
| `distro/dive-install.ks` | Kickstart injected into Fedora's live ISO: on install it copies the Dive sources in and runs the setup. This is how the released `Dive-0.1-x86_64.iso` is made (`.github/workflows/build-iso-live.yml`). |
| `distro/dive-live.ks`, `distro/build-iso.sh` | Full custom live image build (experimental; fails inside GitHub's containers, works on a Fedora machine). |
| `distro/files/dconf/00-dive` | System defaults: dock left, Windows-style menu, dark teal look, shortcuts. |
| `distro/files/grub/theme.txt` | The boot menu theme (Windows and Dive side by side, 10 s countdown). |
| `distro/files/art/` | Logo (`dive-logo.png`, the blue wave, plus an SVG fallback) and a generator for the wallpaper and boot background. |
| `shell/dive-hoverbar@dive.sh/` | GNOME extension: top bar hidden until you touch the top edge. |
| `bridge/dive-bridge` | Dive Bridge: double-click any .exe or .msi and it runs, each in its own Windows environment. |
| `migrate/dive-migrate.py` | Brings files, apps, browser data and Wi‑Fi over from the Windows partition. |
| `welcome/dive-welcome.py` | First-run setup app (Welcome → Bring Windows over → You → Ready). |
| `installer/windows/install.ps1` | The one-command Windows installer. |

## How the pieces fit

1. **On Windows** you run `irm https://dive.sh/install | iex` (or `install.ps1`). It checks UEFI, Secure Boot and BitLocker, asks how many GB Dive gets, exports your app list (`winget export`), Wi‑Fi profiles (`netsh wlan export`) and user info, shrinks `C:`, creates a small `DIVE_LIVE` partition with the Dive image on it, adds a "Dive Installer" firmware boot entry and restarts into it once.
2. **Dive's installer** (Fedora's installer, branded) puts Dive into the free space and installs GRUB.
3. **The boot menu** is GRUB with the Dive theme. It lists Dive and Windows (found by `os-prober`) and starts Dive after 10 seconds.
4. **First login** opens Dive Setup. The "Bring Windows over" step runs `dive-migrate`, which mounts the Windows partition read-only, links your folders, installs Flatpak versions of your apps, copies browser data and adds your Wi‑Fi networks.
5. **The desktop** is GNOME with Dash to Dock at the bottom (macOS style, position changeable in Settings), black with a light-blue accent, ArcMenu in Windows layout as the Dive menu, the Dive hover bar, Clipboard Indicator on Super+V, GNOME's own screenshot/recording tool on Super+Shift+S and the app grid on Super+A.
6. **.exe files** are associated with Dive Bridge. It creates a Wine prefix per program, installs fonts, the C++ runtime and DXVK, runs the program, and adds installed programs to the app grid.

## Run the demo app

```bash
cd app
npm install
npm start          # opens Dive in its own window
npm run build      # makes out/Dive-darwin-arm64/Dive.app
```

Drag `Dive.app` to Applications if you want it in Launchpad. It is not code-signed, so the first launch may need right-click → Open.

## Make it boot (real hardware or a VM)

**The installer image exists:** https://github.com/Foxflame27/dive/releases/tag/v0.1 (two parts, joined automatically by `installer/windows/install.ps1`, or by hand with `cat Dive-0.1-x86_64.iso.part* > Dive-0.1-x86_64.iso`). It is Fedora 43 Workstation live with the Dive kickstart and sources inside; the installed system runs `dive-setup.sh` and becomes Dive. GitHub Actions rebuilds it on every `v*` tag. Follow `GUIDE.md` for the VM test and the laptop install.

Other ways to get a Dive system:

1. **UTM on this Mac** (installed). Download the Fedora Workstation ISO for Apple Silicon (aarch64) from fedoraproject.org, create a VM in UTM with 8 GB RAM and 60 GB disk, install Fedora, then copy this folder in and run `sudo ./distro/dive-setup.sh`. That VM *is* Dive: the boot menu, the desktop, the setup app and the migration tool all run for real. Only Wine is missing on aarch64.
2. **Any x86_64 PC or VM** with Fedora: run `sudo ./distro/build-iso.sh` to get `out/Dive-0.1-x86_64.iso`, boot a Windows VM from it (or run `installer/windows/install.ps1` inside the Windows VM) and you have the full journey, .exe support included.

## Test it

You cannot test an OS on the machine you are using, so use virtual machines. Go in this order: each step is smaller than the next.

### Step 1: the desktop (30 minutes)

You need a Fedora Workstation VM. On an Intel PC use VirtualBox or VMware; on an Apple Silicon Mac use UTM with the aarch64 Fedora Workstation ISO (everything works except Wine, which needs x86_64).

```bash
# inside the Fedora VM, after installing it and logging in
sudo dnf install -y git
git clone <this folder>   # or copy it in with a shared folder / scp
cd dive
sudo ./distro/dive-setup.sh
```

Log out and back in. You should see: dark teal look, Dive wallpaper, dock on the left, no top bar until you move the pointer to the top edge, Super+V clipboard history, Super+Shift+S screenshot tool, Super+A app grid. Open ArcMenu Settings once and set "Display ArcMenu on → Dash to Dock" so the Dive button sits in the dock, and check that "Menu Hotkey" is Left Super. On an x86_64 VM, copy any Windows program in and double-click it to test Dive Bridge.

`dive-welcome --again` opens the first-run setup app any time. `dive-migrate scan` shows what it would find.

### Step 2: the boot menu (10 minutes)

In the same VM run `sudo grub2-mkconfig -o /boot/grub2/grub.cfg` and reboot. The GRUB menu should use the Dive theme. If the VM also has Windows installed, os-prober adds it as a second entry.

### Step 3: build the image (1 hour, x86_64 Fedora only)

```bash
sudo ./distro/build-iso.sh
```

Produces `out/Dive-0.1-x86_64.iso`. Boot a fresh VM from it: you get the Dive live desktop with "Install Dive". Keep `LiveOS/squashfs.img` under 4 GB or the Windows installer cannot copy it onto FAT32.

### Step 4: the full journey from Windows (2 hours)

Make a Windows 11 VM with UEFI and a 120 GB or bigger disk. Copy the ISO in, open PowerShell as administrator:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install.ps1 -IsoPath C:\Users\you\Downloads\Dive-0.1-x86_64.iso -SizeGB 60
```

Answer YES, let it restart. The firmware boots "Dive Installer", you choose Install Dive, install into the free space, reboot, and the Dive boot menu should show Dive and Windows. Log in, and Dive Setup offers to bring your Windows over.

Do not run `install.ps1` on a real PC until Step 4 has passed in a VM. It resizes the system partition.

## Honest limits

- **Wine is not Windows.** Most everyday programs and Steam games run. Anti-cheat games (Valorant, Fortnite), hardware drivers, and some Adobe and Office versions do not. Bridge should get a compatibility check (ProtonDB / WineHQ AppDB) before v1.
- **Chrome and Edge passwords cannot be moved.** They are locked with the Windows account. Bookmarks and settings move; you sign in once. Firefox profiles move completely.
- **Windows partition is read-only** in Dive. Windows "fast startup" leaves NTFS in a half-open state and writing then corrupts it. Turn fast startup off in Windows if you want read-write later.
- **Secure Boot** works because the installer boots Fedora's Microsoft-signed shim. If a PC refuses it, turn Secure Boot off.
- **Untested here.** The code was written and syntax-checked on a Mac. Things that touch real hardware (Resize-Partition, bcdedit, os-prober, extension keys for the exact ArcMenu version you get) need the VM tests above. Expect to fix small things in Step 1 and 4.
- `dive.sh` and the GitHub release URL in `install.ps1` are placeholders until you host the ISO and script.

## Design

Logo: the blue wave in `distro/files/art/dive-logo.png` (512 px, transparent). Desktop tokens: bluish dark greys (#1b2028 windows, #232a34 headers) with a teal accent (#2f9aae) by default; the accent, light/dark style, dock position and wallpaper are user settings. Windows use left-aligned titles with Windows-style controls, the dock is macOS-style, the menu is Windows-style. Wallpaper and boot background are generated by `distro/files/art/make-art.py`.
