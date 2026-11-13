#!/usr/bin/bash
# Replace Fedora's generic 4K-page aarch64 kernel with the Gravity Linux
# 16K-page kernel for Apple Silicon (https://github.com/GravityLinux/linux).
# This takes the place of upstream Aurora's 02-install-common-kernel-akmods.sh.

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

if [[ "$(arch)" != "aarch64" ]]; then
    echo "aurora-gravity only targets aarch64 Apple Silicon"
    exit 1
fi

# Remove the stock kernel (the Gravity platform metapackage conflicts with it)
for pkg in kernel kernel{-core,-modules,-modules-core,-modules-extra,-tools-libs,-tools}; do
    rpm -q "${pkg}" >/dev/null 2>&1 && rpm --erase --nodeps "${pkg}"
done

# cleanup leftovers that are not covered by kernel-* packages for some reason
rm -rf /usr/lib/modules

GRAVITY_KERNEL_PKGS=(
    kernel-16k
    kernel-16k-core
    kernel-16k-modules
    kernel-16k-modules-core
    kernel-16k-modules-extra
    kernel-modules-extra-matched
)

if [[ "${IMAGE_FLAVOR}" == "dx" ]]; then
    GRAVITY_KERNEL_PKGS+=(kernel-16k-devel)
fi

# Shims to keep kernel-install from running dracut/rpm-ostree/update-m1n1 at
# build time; the initramfs is generated in 19-initramfs.sh and m1n1 stage 2 is
# assembled on the target machine (see aurora-gravity-m1n1-sync).
INSTALL_D=/usr/lib/kernel/install.d
SHIMMED=()
for hook in 05-rpmostree.install 50-dracut.install; do
    if [[ -e "${INSTALL_D}/${hook}" ]]; then
        mv "${INSTALL_D}/${hook}" "${INSTALL_D}/${hook}.bak"
        printf '%s\n' '#!/bin/sh' 'exit 0' > "${INSTALL_D}/${hook}"
        chmod +x "${INSTALL_D}/${hook}"
        SHIMMED+=("${hook}")
    fi
done
export M1N1_UPDATE_DISABLED=1

dnf5 -y install --from-repo=gravity "${GRAVITY_KERNEL_PKGS[@]}"

for hook in "${SHIMMED[@]}"; do
    mv -f "${INSTALL_D}/${hook}.bak" "${INSTALL_D}/${hook}"
done

# Exactly one kernel, and it must be the Gravity 16K build
mapfile -t KVERS < <(ls /usr/lib/modules)
if [[ "${#KVERS[@]}" -ne 1 || ! "${KVERS[0]}" =~ gravity.*\+16k$ ]]; then
    echo "Unexpected kernel(s) in /usr/lib/modules: ${KVERS[*]}"
    exit 1
fi
test -f "/usr/lib/modules/${KVERS[0]}/vmlinuz"

dnf5 versionlock add "${GRAVITY_KERNEL_PKGS[@]}" kernel-16k-devel kernel-16k-devel-matched

echo "::endgroup::"
