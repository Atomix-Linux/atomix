#!/bin/bash

set -e
set -x

source /config

pacman-key --populate

locale-gen

# Disable parallel downloads
sed -i '/ParallelDownloads/s/^/#/g' /etc/pacman.conf

# Cannot check space in chroot
sed -i '/CheckSpace/s/^/#/g' /etc/pacman.conf

# update package databases
pacman --noconfirm -Syy

# Install terminus-font
pacman --noconfirm -S terminus-font

# Disable check and debug for makepkg on the final image
sed -i '/BUILDENV/s/ check/ !check/g' /etc/makepkg.conf
sed -i '/OPTIONS/s/ debug/ !debug/g' /etc/makepkg.conf

# install kernel package
if [ "$KERNEL_PACKAGE_ORIGIN" == "local" ] ; then
	pacman --noconfirm -U --overwrite '*' \
	/override_pkgs/${KERNEL_PACKAGE}-*.pkg.tar.zst
else
	pacman --noconfirm -S "${KERNEL_PACKAGE}" "${KERNEL_PACKAGE}-headers"
fi

pacman --noconfirm -U --overwrite '*' /local_pkgs/*
rm -rf /var/cache/pacman/pkg

pacman --noconfirm -Rdd jack2 || true

pacman --noconfirm -S --overwrite '*' --disable-download-timeout ${PACKAGES}
rm -rf /var/cache/pacman/pkg

# Install the new iptables
# See https://gitlab.archlinux.org/archlinux/packaging/packages/iptables/-/issues/1
# Since base package group adds iptables by default
# pacman will ask for confirmation to replace that package
# but the default answer is no.
# doing yes | pacman omitting --noconfirm is a necessity
yes | pacman -S iptables-nft

# enable services
systemctl enable ${SERVICES}

# enable user services
systemctl --global enable ${USER_SERVICES}

# disable root login
passwd --lock root

# create user
groupadd -r autologin
useradd -m ${USERNAME} -G autologin,wheel,plugdev
echo "${USERNAME}:${USERNAME}" | chpasswd

echo "${SYSTEM_NAME}" > /etc/hostname

# set the default editor, so visudo works
echo "export EDITOR=nano" >> /etc/bash.bashrc

# enable multicast dns in avahi
sed -i "/^hosts:/ s/resolve/mdns resolve/" /etc/nsswitch.conf

# configure ssh
echo "
AuthorizedKeysFile	.ssh/authorized_keys
PasswordAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
PrintMotd no # pam does that
Subsystem	sftp	/usr/lib/ssh/sftp-server
" > /etc/ssh/sshd_config

echo "
LABEL=aldm_root /var       btrfs     defaults,subvolid=256,rw,noatime,nodatacow,nofail                                                                                                                                                                                                                      0   0
LABEL=aldm_root /home      btrfs     defaults,subvolid=257,rw,noatime,nodatacow,nofail                                                                                                                                                                                                                      0   0
LABEL=aldm_root /aldm_root btrfs     defaults,subvolid=5,rw,noatime,nodatacow,x-initrd.mount                                                                                                                                                                                                                0   2
overlay         /etc       overlay   defaults,x-systemd.requires-mounts-for=/aldm_root,x-systemd.requires-mounts-for=/sysroot/aldm_root,x-systemd.rw-only,lowerdir=/sysroot/etc,upperdir=/sysroot/aldm_root/etc,workdir=/sysroot/aldm_root/.etc,index=off,metacopy=off,comment=etcoverlay,x-initrd.mount    0   0
" > /etc/fstab

echo "
LSB_VERSION=1.4
DISTRIB_ID=${SYSTEM_NAME}
DISTRIB_RELEASE=\"${LSB_VERSION}\"
DISTRIB_DESCRIPTION=${SYSTEM_DESC}
" > /etc/lsb-release

echo 'NAME="${SYSTEM_DESC}"
VERSION="${DISPLAY_VERSION}"
VERSION_ID="${VERSION_NUMBER}"
BUILD_ID="${BUILD_ID}"
PRETTY_NAME="${SYSTEM_DESC} ${DISPLAY_VERSION}"
ID=${SYSTEM_NAME}
ID_LIKE=arch
ANSI_COLOR="1;33"
HOME_URL="${WEBSITE}"
DOCUMENTATION_URL="${DOCUMENTATION_URL}"
BUG_REPORT_URL="${BUG_REPORT_URL}"' > /usr/lib/os-release

postinstallhook


pacman -Q > /config

# preserve installed package database
mkdir -p /usr/var/lib/pacman
cp -r /var/lib/pacman/local /usr/var/lib/pacman/

# move kernel image and initrd to a defualt location if "linux" is not used
if [ ${KERNEL_PACKAGE} != 'linux' ] ; then
	mv /boot/vmlinuz-${KERNEL_PACKAGE} /boot/vmlinuz-linux
	mv /boot/initramfs-${KERNEL_PACKAGE}.img /boot/initramfs-linux.img
	mv /boot/initramfs-${KERNEL_PACKAGE}-fallback.img /boot/initramfs-linux-fallback.img
fi

# clean up/remove unnecessary files
rm -rf \
/home \
/var \
/local_pkgs \

rm -rf ${FILES_TO_DELETE}

# create necessary directories
mkdir -p /home
mkdir -p /var
mkdir -p /aldm_root
mkdir -p /efi
