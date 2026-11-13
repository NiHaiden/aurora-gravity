#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# kernel-16k installs to <evr>.<arch>+16k, so take the version from the modules dir
KERNEL_VERSION=$(ls /usr/lib/modules)
[[ $(wc -w <<<"${KERNEL_VERSION}") -eq 1 ]]

export DRACUT_NO_XATTR=1
/usr/bin/dracut --kver "${KERNEL_VERSION}" --reproducible -v -f "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"
chmod 0600 "/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"

echo "::endgroup::"
