# Dive install kickstart, injected into Fedora's Workstation live ISO by mkksiso.
# The live session is stock Fedora; the *installed* system becomes Dive in %post.
lang en_US.UTF-8
keyboard us
timezone Europe/Zurich --utc

%post --nochroot --log=/tmp/dive-post-nochroot.log
# Copy the Dive sources from the live medium into the installed system.
for m in /run/initramfs/live /run/install/repo /mnt/install/repo; do
  if [ -d "$m/dive-src" ]; then
    mkdir -p "$ANA_INSTALL_PATH/usr/share/dive-src"
    cp -r "$m/dive-src/." "$ANA_INSTALL_PATH/usr/share/dive-src/"
    echo "copied dive-src from $m"; break
  fi
done
%end

%post --log=/root/dive-post.log
if [ -f /usr/share/dive-src/distro/dive-setup.sh ]; then
  bash /usr/share/dive-src/distro/dive-setup.sh image || echo "dive-setup failed, see above"
  rm -rf /usr/share/dive-src
fi
%end
