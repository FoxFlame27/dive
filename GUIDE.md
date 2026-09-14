# Getting Dive onto the Razer, step by step

Three stages. Do them in order. Stage 1 and 2 are safe. Stage 3 touches the laptop's disk, so it has a test first.

## Before anything: back up the Razer (30 min)

1. Open **Settings → Privacy & security → Device encryption** (or search "BitLocker"). If it is on, go to **aka.ms/myrecoverykey** while signed in with your Microsoft account and confirm the recovery key for this PC is listed. Write it down.
2. Plug in an external drive with at least as much free space as C: uses. Install **Macrium Reflect Free** (macrium.com) and choose **Image this disk** on the Windows disk. Wait for it to finish. Keep the drive somewhere safe.
3. In Macrium, choose **Other Tasks → Create Rescue Media** onto a USB stick. This is what you boot from if Windows ever refuses to start.

## Stage 1: build the Dive image (GitHub does the work)

1. Create a free account at **github.com** if you do not have one, then create a new **public** repository called `dive`.
2. On the Mac, in the folder `Operating system`, run:

```bash
git init
git add .
git commit -m "Dive 0.1"
git branch -M main
git remote add origin https://github.com/YOUR-NAME/dive.git
git push -u origin main
git tag v0.1
git push origin v0.1
```

3. Open the repository on GitHub → **Actions**. A job called **Build Dive ISO** starts on the tag. It takes 30 to 60 minutes.
4. When it turns green, go to **Releases** on the repository. Release `v0.1` has `Dive-0.1-x86_64.iso` attached. That is the image. Its link looks like `https://github.com/YOUR-NAME/dive/releases/download/v0.1/Dive-0.1-x86_64.iso`.

If the job turns red, open it and read the last lines. The two usual causes are a package name that changed in Fedora (edit `distro/dive-live.ks`) or the image growing over 4 GB (remove packages there).

Fallback without GitHub: install Fedora Workstation in a VM on the Razer (VirtualBox, 60 GB disk, 8 GB RAM), copy the folder in, run `sudo ./distro/build-iso.sh`, and copy `out/Dive-0.1-x86_64.iso` out through a shared folder.

## Stage 2: point the installer at the image

1. Open `installer/windows/install.ps1` and replace the `IsoUrl` default near the top (the line starting with `[string]$IsoUrl`) with the release link from Stage 1.
2. To get the one-line command working, upload `install.ps1` somewhere it can be downloaded as raw text. The simplest is the GitHub repository itself: the raw link is `https://raw.githubusercontent.com/YOUR-NAME/dive/main/installer/windows/install.ps1`. Then the command is:

```powershell
irm https://raw.githubusercontent.com/YOUR-NAME/dive/main/installer/windows/install.ps1 | iex
```

A short domain like `dive.sh` is just a redirect to that link; buy one later if you want it.

## Stage 3: test in a Windows VM, then the Razer

### 3a. The test (2 hours, no risk to the laptop)

1. On the Razer, install **VirtualBox** (virtualbox.org). Download a **Windows 11** ISO from microsoft.com/software-download/windows11.
2. New VM: Windows 11, 8 GB RAM, **120 GB** disk, and in Settings → System tick **Enable EFI** and **Enable Secure Boot**. Install Windows inside it (any local account is fine, skip Microsoft sign-in).
3. Inside the VM, download `Dive-0.1-x86_64.iso` and `install.ps1`. Open **PowerShell as administrator** and run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
cd $env:USERPROFILE\Downloads
.\install.ps1 -IsoPath .\Dive-0.1-x86_64.iso -SizeGB 60
```

4. Answer the questions, type `YES`, let it restart. You should see the Dive installer boot. Choose **Install Dive**, let it use the free space, reboot.
5. You should now get the boot menu with **Dive** and **Windows Boot Manager**. Boot each one once. Log into Dive, walk through the setup, open Chromium, open Files → Windows files.

If any step fails, that is exactly what the VM is for. Note what happened and fix it before going near the laptop. Snapshots in VirtualBox let you retry from step 3 in seconds.

### 3b. The Razer (1 hour)

Only after 3a passed completely:

1. Backup from the top of this guide is done and the recovery key is written down.
2. Plug the charger in. Close everything.
3. Open PowerShell as administrator and run the one-line command from Stage 2 (or the same `.\install.ps1` call as in the VM). Pick how many GB Dive gets; 80 to 150 GB is sensible.
4. Type `YES`, restart, choose **Install Dive**, install into the free space, reboot.
5. The boot menu shows Dive and Windows. If Windows asks for the BitLocker recovery key on its first start, enter the key you wrote down; that happens once.

Afterwards, in Dive: open Software and install the NVIDIA driver if games feel slow (Settings → About shows the GPU). Steam games run through Proton.

## If Windows will not boot afterwards

Boot the Macrium rescue USB and restore the image from before. Nothing done by Dive survives that. This is why the backup comes first.
