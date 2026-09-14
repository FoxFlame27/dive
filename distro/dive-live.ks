# Dive live/installer image. Built on top of Fedora's Workstation live kickstart.
# Build with distro/build-iso.sh on a Fedora x86_64 machine.
%include /usr/share/spin-kickstarts/fedora-live-workstation.ks

lang en_US.UTF-8
keyboard us
timezone Europe/Zurich

%packages --ignoremissing
wine
winetricks
ntfs-3g
os-prober
efibootmgr
python3-gobject
libadwaita
zenity
jq
unzip
google-noto-sans-fonts
google-noto-sans-mono-fonts
# Note: the Workstation kickstart pins LibreOffice and Boxes, so they cannot be excluded here.
# The image must stay under 4 GB (FAT32 limit for install-from-Windows); the workflow checks that.
%end

%post --nochroot --log=/tmp/dive-post-nochroot.log
# copy the Dive sources into the image so %post can run them
mkdir -p "$INSTALL_ROOT/usr/share/dive-src"
cp -r /dive-src/. "$INSTALL_ROOT/usr/share/dive-src/"
%end

%post --log=/root/dive-post.log
bash /usr/share/dive-src/distro/dive-setup.sh image
rm -rf /usr/share/dive-src
# Live session: Dive look right away, and "Install Dive" on the desktop
sed -i 's/Install to Hard Drive/Install Dive/' /usr/share/applications/liveinst.desktop 2>/dev/null || true
%end
