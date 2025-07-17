#!/bin/bash

set -e
set -x

if [ $EUID -ne 0 ]; then
    echo "$(basename $0) must be run as root"
    exit 1
fi

BUILD_USER=${BUILD_USER:-}
OUTPUT_DIR=${OUTPUT_DIR:-}

source config

if [ -z "${SYSTEM_NAME}" ]; then
    echo "SYSTEM_NAME must be specified"
    exit
fi

if [ -z "${VERSION}" ]; then
    echo "VERSION must be specified"
    exit
fi

DISPLAY_VERSION=${VERSION}
LSB_VERSION=${VERSION}
VERSION_NUMBER=${VERSION}

if [ -n "$1" ]; then
	DISPLAY_VERSION="${VERSION} (${1})"
	VERSION="${VERSION}_${1}"
	LSB_VERSION="${LSB_VERSION}　(${1})"
	BUILD_ID="${1}"
fi

MOUNT_PATH=/tmp/${SYSTEM_NAME}-build
BUILD_PATH=${MOUNT_PATH}/subvolume
SNAP_PATH=${MOUNT_PATH}/${SYSTEM_NAME}-${VERSION}
BUILD_IMG=/output/${SYSTEM_NAME}-build.img

mkdir -p ${MOUNT_PATH}

fallocate -l ${SIZE} ${BUILD_IMG}
mkfs.btrfs -f ${BUILD_IMG}
mount -t btrfs -o loop,compress-force=zstd:15 ${BUILD_IMG} ${MOUNT_PATH}
btrfs subvolume create ${BUILD_PATH}

cp /etc/makepkg.conf fs/etc/makepkg.conf

pacstrap -K -C fs/etc/pacman.conf ${BUILD_PATH}

mkdir -p fs/etc/pacman.d
cp /etc/pacman.d/mirrorlist fs/etc/pacman.d/mirrorlist

cp -R config fs/. ${BUILD_PATH}/


mkdir ${BUILD_PATH}/local_pkgs
cp -rv pkgs/*.pkg.tar* ${BUILD_PATH}/local_pkgs


# TODO - Other packages (AUR, Local)

# Chroot system
mount --bind ${BUILD_PATH} ${BUILD_PATH}
arch-chroot ${BUILD_PATH} /bin/bash -s < ./configure-image.sh

btrfs filesystem defragment -r ${BUILD_PATH}

cp -R fs/. ${BUILD_PATH}/
echo "${SYSTEM_NAME}-${VERSION}" > ${BUILD_PATH}/build_info
echo "" >> ${BUILD_PATH}/build_info
cat ${BUILD_PATH}/config >> ${BUILD_PATH}/build_info
rm ${BUILD_PATH}/config

if [ -z "${ARCHIVE_DATE}" ]; then
	export TODAY_DATE=$(date +%Y/%m/%d)
	echo "Server=https://archive.archlinux.org/repos/${TODAY_DATE}/\$repo/os/\$arch" > \
	${BUILD_PATH}/etc/pacman.d/mirrorlist
fi

btrfs subvolume snapshot -r ${BUILD_PATH} ${SNAP_PATH}
btrfs send -f ${SYSTEM_NAME}-${VERSION}.img ${SNAP_PATH}

cp ${BUILD_PATH}/build_info build_info.txt

#Clean
umount -l ${BUILD_PATH}
umount -l ${MOUNT_PATH}
rm -rf ${MOUNT_PATH}
rm -rf ${BUILD_IMG}

IMG_FILENAME="${SYSTEM_NAME}-${VERSION}.img.tar.xz"
if [ -z "${NO_COMPRESS}" ]; then
	tar -c -I'xz -8 -T4' -f "${IMG_FILENAME}" "${SYSTEM_NAME}-${VERSION}.img"
	rm "${SYSTEM_NAME}-${VERSION}.img"

	# DZIELENIE na części po 1900 MB
	split -b 1900M "${IMG_FILENAME}" "${IMG_FILENAME}.part."
	rm "${IMG_FILENAME}"  # opcjonalnie

	# Tworzenie sumy SHA256 z połączonych części
	sha256sum *.part.* > sha256sum.txt
	cat sha256sum.txt

	# Przeniesienie do OUTPUT_DIR
	if [ -n "${OUTPUT_DIR}" ]; then
		mkdir -p "${OUTPUT_DIR}"
		mv ${IMG_FILENAME}.part.* "${OUTPUT_DIR}"
		mv build_info.txt "${OUTPUT_DIR}"
		mv sha256sum.txt "${OUTPUT_DIR}"
	fi

	# GitHub Actions output
	if [ -f "${GITHUB_OUTPUT}" ]; then
		echo "version=${VERSION}" >> "${GITHUB_OUTPUT}"
		echo "display_version=${DISPLAY_VERSION}" >> "${GITHUB_OUTPUT}"
		echo "display_name=${SYSTEM_DESC}" >> "${GITHUB_OUTPUT}"
		echo "image_filename=${IMG_FILENAME}.part.*" >> "${GITHUB_OUTPUT}"
	else
		echo "No github output file set"
	fi
else
	echo "Local build, output IMG directly"
	if [ -n "${OUTPUT_DIR}" ]; then
		mkdir -p "${OUTPUT_DIR}"
		mv ${SYSTEM_NAME}-${VERSION}.img ${OUTPUT_DIR}
	fi
fi
