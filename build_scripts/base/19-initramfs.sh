#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# kernel-16k installs to <evr>.<arch>+16k, so take the version from the modules dir
KERNEL_VERSION=$(ls /usr/lib/modules)
[[ $(wc -w <<<"${KERNEL_VERSION}") -eq 1 ]]
INITRAMFS="/usr/lib/modules/${KERNEL_VERSION}/initramfs.img"

# aurora-gravity: no ublue akmods, so upstream's kmod-v4l2loopback exclusion
# (DRACUT_REMOVE) doesn't apply here.

# https://github.com/ublue-os/aurora/issues/2568
# these strings change with every build
TMP_OS_RELEASE=$(mktemp --tmpdir 'os-release-XXXXXXXXXX')
OS_RELEASE="/usr/lib/os-release"
cp "${OS_RELEASE}" "${TMP_OS_RELEASE}"
sed -Ei -e '/^((OSTREE_)?(IMAGE_)?VERSION|PRETTY_NAME|BUILD_ID)=/d' "${OS_RELEASE}"

DRACUT_NO_XATTR=1 /usr/bin/dracut \
  --kver "${KERNEL_VERSION}" \
  --reproducible \
  --verbose \
  --force \
  "${INITRAMFS}"

# mv causes permissions to change
cp "${TMP_OS_RELEASE}" "${OS_RELEASE}"
rm "${TMP_OS_RELEASE}"

chmod 0600 "${INITRAMFS}"

# for debugging
sha256sum "${INITRAMFS}"

echo "::endgroup::"
