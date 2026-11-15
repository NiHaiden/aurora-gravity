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
    # Valve's native ARM64 Steam client launcher (4K-page process via the P3S kernel).
    # Pulls fex-guestos-mesa (x86 Mesa pinned to our Mesa revision) for x86 games.
    # The client and Proton are downloaded per user at first start, not shipped here.
    steam
    # Recommends of steam; listed because weak deps are off: makes Proton (ARM64, Gravity) the default
    steam-gravity-proton-default
)

# --- Gravity's fc44 Python packages on a newer Fedora -----------------------
# Gravity only publishes fedora-44 builds (see gravity.repo). python3-gravity_firmware
# (gravity-fwextract, required by gravity-fwupdate -> metapackage-core) is pure Python
# but requires python(abi) = 3.14, which Fedora 45 (Python 3.15) can't satisfy. Install
# it without that one dependency and make the package importable from the system
# Python. Drop this block once Gravity builds for the image's Fedora release.
GF_PKG=python3-gravity_firmware
GF_ABI=$(dnf5 -q repoquery --repo=gravity --latest-limit=1 --requires "${GF_PKG}" | sed -n 's/^python(abi) = //p')
SYS_ABI=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
if [[ -n "${GF_ABI}" && "${GF_ABI}" != "${SYS_ABI}" ]]; then
    echo "${GF_PKG} is built for Python ${GF_ABI}, system has ${SYS_ABI}: installing with relocation"
    # Its other dependencies (liblzfse, python3dist(asn1), ...) must still be real
    mapfile -t GF_DEPS < <(dnf5 -q repoquery --repo=gravity --latest-limit=1 --requires "${GF_PKG}" \
        | grep -vE '^(python\(abi\)|rpmlib\()')
    dnf5 -y install --setopt=install_weak_deps=False "${GF_DEPS[@]}"
    GF_DL=$(mktemp -d)
    dnf5 -y download --repo=gravity --destdir="${GF_DL}" "${GF_PKG}"
    rpm -i --nodeps "${GF_DL}"/"${GF_PKG}"-*.rpm
    rm -rf "${GF_DL}"
    GF_SRC="/usr/lib/python${GF_ABI}/site-packages"
    GF_DST="/usr/lib/python${SYS_ABI}/site-packages"
    for path in "${GF_SRC}"/gravity_firmware "${GF_SRC}"/gravity_firmware-*.dist-info; do
        ln -s "../../python${GF_ABI}/site-packages/$(basename "${path}")" "${GF_DST}/"
    done
    # /usr is read-only at runtime, so precompile for the system Python now
    python3 -m compileall -q "${GF_SRC}/gravity_firmware"
    python3 -c 'import gravity_firmware.update'
fi

dnf5 -y install --setopt=install_weak_deps=False "${GRAVITY_PACKAGES[@]}"

# --- U-Boot ------------------------------------------------------------------
# Gravity's U-Boot carries the Apple Silicon patches and ends up in m1n1 stage 2.
# When Fedora's build is newer (F45: 2026.10 vs Gravity's 2026.07), the copy from
# the base image is "already installed" and stays. Force Gravity's build and lock it.
UBOOT_PKGS=()
for pkg in uboot-images-armv8 uboot-tools; do
    rpm -q "${pkg}" >/dev/null 2>&1 && UBOOT_PKGS+=("${pkg}")
done
dnf5 -y distro-sync --from-repo=gravity "${UBOOT_PKGS[@]}"
for pkg in "${UBOOT_PKGS[@]}"; do
    rpm -q --qf '%{RELEASE}\n' "${pkg}" | grep -q gravity || { echo "${pkg} is not the Gravity build"; exit 1; }
done
dnf5 versionlock add "${UBOOT_PKGS[@]}"

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
