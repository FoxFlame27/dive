<#
.SYNOPSIS
  Install Dive next to Windows, from Windows.  One line:

      irm https://dive.sh/install | iex

  or, with a local ISO:

      .\install.ps1 -IsoPath C:\Downloads\Dive-0.1-x86_64.iso -SizeGB 120

.DESCRIPTION
  1. Checks UEFI, Secure Boot, BitLocker and free space.
  2. Downloads the Dive image (or uses -IsoPath).
  3. Asks how much of the disk Dive gets.
  4. Exports your app list, Wi‑Fi profiles and user info so Dive can bring them over.
  5. Shrinks C:, creates a small partition with the Dive installer, adds a "Dive Installer"
     entry to the firmware boot menu and restarts into it. Windows is not modified.
  After Dive is installed, GRUB shows the Dive boot menu with Windows in it.

  TEST THIS IN A VIRTUAL MACHINE FIRST. It resizes your system partition.
#>
#Requires -RunAsAdministrator
[CmdletBinding()]
param(
  [int]$SizeGB = 0,
  [string]$IsoUrl = "https://github.com/dive-os/dive/releases/latest/download/Dive-x86_64.iso",
  [string]$IsoPath = "",
  [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
$LiveGB = 6          # partition that holds the installer image
$MinGB  = 40
$Label  = 'DIVE_LIVE'

function Say($m)  { Write-Host "  $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "  ✓ $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  ! $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "  ✗ $m" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "  Dive Setup" -ForegroundColor White
Write-Host "  Windows stays exactly as it is. You choose Windows or Dive at every start." -ForegroundColor DarkGray
Write-Host ""

# ---------------------------------------------------------------- checks
if ($env:firmware_type -ne 'UEFI') { Die "This PC boots in legacy BIOS mode. Dive needs UEFI." }
Ok "UEFI firmware"
try { if (Confirm-SecureBootUEFI) { Ok "Secure Boot on (Dive's boot loader is signed, this is fine)" } else { Ok "Secure Boot off" } } catch { Warn "Could not read Secure Boot state" }

$sys = Get-Partition -DriveLetter C
$disk = Get-Disk -Number $sys.DiskNumber
if ($disk.PartitionStyle -ne 'GPT') { Die "Disk $($disk.Number) is not GPT." }
$sizes = Get-PartitionSupportedSize -DriveLetter C
$maxShrinkGB = [math]::Floor(($sys.Size - $sizes.SizeMin) / 1GB) - 2
Ok "Disk: $($disk.FriendlyName), $([math]::Round($disk.Size/1GB)) GB. C: can give up to $maxShrinkGB GB."
if ($maxShrinkGB -lt ($MinGB + $LiveGB)) { Die "Not enough shrinkable space. Free up files, run Disk Cleanup, disable hibernation (powercfg /h off) and try again." }

$bl = $null
try { $bl = Get-BitLockerVolume -MountPoint C: -ErrorAction Stop } catch {}
if ($bl -and $bl.ProtectionStatus -eq 'On') { Warn "BitLocker is on. It will be suspended for one restart so the boot change does not ask for a recovery key." }

# ---------------------------------------------------------------- how much space
if ($SizeGB -le 0) {
  $default = [math]::Min(120, $maxShrinkGB - $LiveGB)
  $in = Read-Host "  How many GB should Dive get? [$MinGB-$($maxShrinkGB - $LiveGB), Enter for $default]"
  $SizeGB = if ($in) { [int]$in } else { $default }
}
if ($SizeGB -lt $MinGB -or $SizeGB -gt ($maxShrinkGB - $LiveGB)) { Die "Pick between $MinGB and $($maxShrinkGB - $LiveGB) GB." }
Ok "Dive gets $SizeGB GB"

# ---------------------------------------------------------------- image
if (-not $IsoPath) {
  $IsoPath = Join-Path $env:TEMP 'Dive.iso'
  if (-not (Test-Path $IsoPath)) {
    Say "Downloading Dive…"
    try { Start-BitsTransfer -Source $IsoUrl -Destination $IsoPath -DisplayName 'Dive' } catch { Invoke-WebRequest -Uri $IsoUrl -OutFile $IsoPath }
  }
}
if (-not (Test-Path $IsoPath)) { Die "Image not found: $IsoPath" }
Ok "Image: $IsoPath ($([math]::Round((Get-Item $IsoPath).Length/1GB,1)) GB)"

# ---------------------------------------------------------------- export for Dive Migrate
$exp = Join-Path $env:TEMP 'dive-migrate'
Remove-Item -Recurse -Force $exp -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Path "$exp\wifi" | Out-Null
Say "Exporting your app list and Wi‑Fi networks for Dive…"
try { winget export -o "$exp\winget-export.json" --accept-source-agreements 2>$null | Out-Null; Ok "Apps exported" } catch { Warn "winget not available; apps will not be listed" }
try { netsh wlan export profile key=clear folder="$exp\wifi" 2>$null | Out-Null; Ok "Wi‑Fi profiles exported" } catch { Warn "No Wi‑Fi profiles" }
@{
  user      = $env:USERNAME
  profile   = $env:USERPROFILE
  computer  = $env:COMPUTERNAME
  timezone  = (Get-TimeZone).Id
  locale    = (Get-Culture).Name
  keyboard  = (Get-WinUserLanguageList)[0].InputMethodTips -join ','
  accent    = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\DWM' -Name AccentColor -ErrorAction SilentlyContinue).AccentColor
  exported  = (Get-Date).ToString('o')
} | ConvertTo-Json | Set-Content "$exp\windows.json" -Encoding UTF8
Copy-Item "$env:APPDATA\Microsoft\Windows\Themes\TranscodedWallpaper" "$exp\wallpaper" -ErrorAction SilentlyContinue

# ---------------------------------------------------------------- go / no-go
Write-Host ""
Write-Host "  Ready to:" -ForegroundColor White
Write-Host "   • shrink C: by $($SizeGB + $LiveGB) GB"
Write-Host "   • create a $LiveGB GB partition '$Label' with the Dive installer"
Write-Host "   • add 'Dive Installer' to the firmware boot menu and restart into it once"
Write-Host "  Dive will then install itself into the $SizeGB GB of free space and add the boot menu."
$go = Read-Host "  Type YES to continue"
if ($go -ne 'YES') { Say "Nothing changed."; exit 0 }

# ---------------------------------------------------------------- partitions
if ($bl -and $bl.ProtectionStatus -eq 'On') { Suspend-BitLocker -MountPoint C: -RebootCount 1 | Out-Null; Ok "BitLocker suspended for one restart" }
Say "Shrinking C:…"
$newSize = $sys.Size - ($SizeGB + $LiveGB) * 1GB
Resize-Partition -DriveLetter C -Size $newSize
Ok "C: shrunk"

Say "Creating the installer partition…"
$live = New-Partition -DiskNumber $disk.Number -Size ($LiveGB * 1GB) -AssignDriveLetter
$live | Format-Volume -FileSystem FAT32 -NewFileSystemLabel $Label -Confirm:$false | Out-Null
$L = "$($live.DriveLetter):"
Ok "Partition $L ($Label)"

Say "Copying the Dive image (a few minutes)…"
$img = Mount-DiskImage -ImagePath $IsoPath -PassThru
$isoLetter = ($img | Get-Volume).DriveLetter
robocopy "${isoLetter}:\" "$L\" /E /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
New-Item -ItemType Directory -Path "$L\dive-migrate" -Force | Out-Null
robocopy $exp "$L\dive-migrate" /E /NFL /NDL /NJH /NJS | Out-Null
Ok "Image copied"

# ---------------------------------------------------------------- EFI boot entry
Say "Adding the boot entry…"
$esp = 'S:'
if (Test-Path "$esp\") { $esp = 'T:' }
mountvol $esp /S | Out-Null
New-Item -ItemType Directory -Path "$esp\EFI\dive" -Force | Out-Null
Copy-Item "${isoLetter}:\EFI\BOOT\BOOTX64.EFI" "$esp\EFI\dive\BOOTX64.EFI" -Force   # shim, Microsoft-signed
Copy-Item "${isoLetter}:\EFI\BOOT\grubx64.efi" "$esp\EFI\dive\grubx64.efi" -Force
Copy-Item "${isoLetter}:\EFI\BOOT\mmx64.efi"   "$esp\EFI\dive\mmx64.efi"   -Force -ErrorAction SilentlyContinue
@"
set timeout=3
set default=0
search --no-floppy --set=root -l $Label
menuentry 'Install Dive' {
  linux /images/pxeboot/vmlinuz root=live:LABEL=$Label rd.live.image quiet rhgb
  initrd /images/pxeboot/initrd.img
}
"@ | Set-Content "$esp\EFI\dive\grub.cfg" -Encoding ASCII
Dismount-DiskImage -ImagePath $IsoPath | Out-Null

$out = bcdedit /copy "{bootmgr}" /d "Dive Installer"
if ($out -notmatch '\{[0-9a-f-]+\}') { Die "bcdedit could not create the boot entry: $out" }
$guid = $Matches[0]
bcdedit /set $guid path \EFI\dive\BOOTX64.EFI | Out-Null
bcdedit /set "{fwbootmgr}" bootsequence $guid | Out-Null          # boot into it once
mountvol $esp /D | Out-Null
Ok "Boot entry '$guid' added"

Write-Host ""
Ok "All set. After the restart, Dive's installer starts. Choose 'Install Dive' and let it use the free space."
if (-not $NoRestart) {
  $r = Read-Host "  Restart now? [Y/n]"
  if ($r -eq '' -or $r -match '^[Yy]') { Restart-Computer -Force }
}
