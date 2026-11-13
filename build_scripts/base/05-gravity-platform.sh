#!/usr/bin/bash
# Apple Silicon platform support from Gravity Linux: bootloader bits (m1n1 stage 2,
# U-Boot), firmware loading in the initramfs, audio, and Asahi Mesa configuration.

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

GRAVITY_PACKAGES=(
    # platform core: dracut-gravity, update-m1n1, gravity-fwupdate, alsa-ucm-asahi, tiny-dfr, ...
    gravity-platform-metapackage-core
    gravity-platform-metapackage-desktop
    gravity-platform-metapackage-plasma
    gravity-platform-metapackage-mesa
    gravity-platform-metapackage-audio
    gravity-bootloader
    gravity-scripts
    gravity-remix-scripts
    dracut-gravity
    update-m1n1
    uboot-images-armv8
    linux-firmware-vendor
    gravity-audio-j713
    gravity-battery
)

dnf5 -y install --setopt=install_weak_deps=False "${GRAVITY_PACKAGES[@]}"

# --- m1n1 stage 2 on ostree ------------------------------------------------
# On a package-based system, kernel-install runs update-m1n1 and DTBs come from
# /boot/dtb. On ostree neither happens, so point update-m1n1 at the deployment's
# /usr and let aurora-gravity-m1n1-sync.service call it (see that script).
cat > /etc/sysconfig/update-m1n1 <<'EOF'
# aurora-gravity: values can be overridden by the caller's environment
# (aurora-gravity-m1n1-sync points them at the deployment that boots next).
M1N1="${M1N1:-/usr/lib64/m1n1/m1n1.bin}"
U_BOOT="${U_BOOT:-/usr/share/uboot/apple_m1/u-boot-nodtb.bin}"
DTBS="${DTBS:-/usr/lib/modules/$(uname -r)/dtb}"
EOF

# ostree normalizes mtimes to 0; gzip then warns and exits 2, which aborts
# update-m1n1 under `set -e`. -n drops the timestamp from the gzip header.
sed -i 's/gzip -c "\$U_BOOT"/gzip -nc "$U_BOOT"/' /usr/bin/update-m1n1
grep -q 'gzip -nc "$U_BOOT"' /usr/bin/update-m1n1

# kernel-install never runs on the client, the hook is dead weight
rm -f /usr/lib/kernel/install.d/15-update-m1n1.install

# The vendor firmware tmpfs is mounted here by the initramfs
mkdir -p /usr/lib/firmware/vendor

# aurora-gravity-m1n1-sync.service ships in system_files and is enabled in 17-cleanup.sh

echo "::endgroup::"
