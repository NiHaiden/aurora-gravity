#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -ouex pipefail

# Apply IP Forwarding before installing Docker to prevent messing with LXC networking
sysctl -p

# DX packages from Fedora repos - common to all versions
FEDORA_PACKAGES=(
    android-tools
    bcc
    bcvk
    bpftop
    bpftrace
    cockpit-bridge
    cockpit-machines
    cockpit-networkmanager
    cockpit-ostree
    cockpit-podman
    cockpit-selinux
    cockpit-storaged
    cockpit-system
    edk2-ovmf
    flatpak-builder
    incus
    incus-agent
    iotop
    libvirt
    libvirt-nss
    lxc
    nicstat
    numactl
    osbuild-selinux
    p7zip
    p7zip-plugins
    podman-compose
    podman-machine
    podman-tui
    qemu
    qemu-char-spice
    qemu-device-display-virtio-gpu
    qemu-device-display-virtio-vga
    qemu-device-usb-redirect
    qemu-img
    qemu-system-x86-core
    qemu-user-binfmt
    qemu-user-static
    sysprof
    trace-cmd
    udica
    virt-manager
    virt-v2v
    virt-viewer
    ydotool
)

# rocm doesn't work well on nvidia
# aurora-gravity: rocm-hip/rocm-opencl are x86_64-only in Fedora, and there is
# no AMD GPU on Apple Silicon anyway
if [[ ! "${IMAGE_NAME}" =~ nvidia && "$(arch)" == "x86_64" ]]; then
  FEDORA_PACKAGES+=("rocm-hip" "rocm-opencl" "rocm-smi")
fi

# aurora-gravity: UEFI firmware for native (KVM) aarch64 guests in libvirt/virt-manager.
# edk2-ovmf above only covers emulated x86_64 guests.
if [[ "$(arch)" == "aarch64" ]]; then
  FEDORA_PACKAGES+=("edk2-aarch64")
fi

DNF_EXCLUDES=()
# aurora-gravity: bcc Recommends kernel-devel, which would pull in Gravity's 4K
# kernel-devel. gravity-platform-metapackage-core (needed by steam) conflicts with
# it. Headers for the 16K kernel come from kernel-16k-devel instead
# (02-install-gravity-kernel.sh).
if [[ "$(arch)" == "aarch64" ]]; then
  DNF_EXCLUDES+=("--exclude=kernel-devel")
fi

dnf5 -y install "${DNF_EXCLUDES[@]}" "${FEDORA_PACKAGES[@]}"

# We could use Fedora's moby packages, these are "official"
DOCKER_CE=(
  containerd.io
  docker-buildx-plugin
  docker-ce
  docker-ce-cli
  docker-compose-plugin
)

COPR_PREFIX="copr:copr.fedorainfracloud.org"

# shellcheck disable=SC1010
dnf do -y \
  --action install --from-repo=code code \
  --action install --from-repo=docker-ce-stable "${DOCKER_CE[@]}" \
  --action install --from-repo="${COPR_PREFIX}:karmab:kcli" kcli

dnf -y install --from-repo="${COPR_PREFIX}:ublue-os:packages" ublue-os-libvirt-workarounds

rsync -rvK /ctx/system_files/dx/ /

# Load iptable_nat module for docker-in-docker.
# See:
#   - https://github.com/ublue-os/bluefin/issues/2365
#   - https://github.com/devcontainers/features/issues/1235
mkdir -p /etc/modules-load.d
tee /etc/modules-load.d/ip_tables.conf <<EOF
iptable_nat
EOF

# Branding Changes
echo "Variant=Developer Experience" >> /usr/share/kde-settings/kde-profile/default/xdg/kcm-about-distrorc

echo "::endgroup::"
