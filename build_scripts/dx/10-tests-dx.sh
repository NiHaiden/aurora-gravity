#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

IMPORTANT_PACKAGES_DX=(
    code
    containerd.io
    docker-ce
    docker-buildx-plugin
    docker-compose-plugin
    flatpak-builder
    libvirt
    qemu
)

# aurora-gravity: native aarch64 VMs need UEFI firmware, and DKMS/out-of-tree
# module builds need headers for the Gravity 16K kernel
if [[ "$(arch)" == "aarch64" ]]; then
    IMPORTANT_PACKAGES_DX+=(edk2-aarch64 kernel-16k-devel)
fi

for package in "${IMPORTANT_PACKAGES_DX[@]}"; do
    rpm -q "${package}" >/dev/null || { echo "Missing package: ${package}... Exiting"; exit 1 ; }
done

if [[ "$(arch)" == "aarch64" ]]; then
    KCORE="$(rpm -q --qf '%{VERSION}-%{RELEASE}' kernel-16k-core)"
    KDEVEL="$(rpm -q --qf '%{VERSION}-%{RELEASE}' kernel-16k-devel)"
    [[ "${KCORE}" == "${KDEVEL}" ]] || { echo "kernel-16k-devel ${KDEVEL} does not match kernel-16k-core ${KCORE}... Exiting"; exit 1; }
fi

IMPORTANT_UNITS=(
    docker.socket
    podman.socket
)

for unit in "${IMPORTANT_UNITS[@]}"; do
    if ! systemctl is-enabled "$unit" 2>/dev/null | grep -q "^enabled$"; then
        echo "${unit} is not enabled"
        exit 1
    fi
done

echo "::endgroup::"
