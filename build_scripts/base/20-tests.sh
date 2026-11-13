#!/usr/bin/bash

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

# We need to have the ublue-os signing keys on the image!
# Published images without these keys won't be able to pull ghcr.io/ublue-os/*
# and can therefore not update!
# https://github.com/ublue-os/main/blob/963609eaf01f7c2bb1a76821fe6d0ec269d2df25/build_files/install.sh#L56
# https://github.com/ublue-os/packages/tree/1f77c7e7faa9ebad120609a10d79e0412376c3b7/packages/ublue-os-signing/src

KEY1=$(jq -r '.transports.docker."ghcr.io/ublue-os"[0].keyPaths[0]' /etc/containers/policy.json)
BACKUP_KEY=$(jq -r '.transports.docker."ghcr.io/ublue-os"[0].keyPaths[1]' /etc/containers/policy.json)
KEY1_SHA256="af78ecfda6eb21c35195af3739341715e9cfc3f2f5911dd9c10b0670547bf6e8"
BACKUP_KEY_SHA256="b723467015ba562d40b4645c98c51c65d8254bb59444f6e9962debcfe2315da0"

RPM_OSTREED_CONF_SHA256="f48bb2359e9c31ed464127048138993e2e058bb648e5fd9ba7b7386a2b5eb174"
echo "${RPM_OSTREED_CONF_SHA256}  /etc/rpm-ostreed.conf" | sha256sum -c -

echo "${KEY1_SHA256}  ${KEY1}" | sha256sum -c -
echo "${BACKUP_KEY_SHA256}  ${BACKUP_KEY}" | sha256sum -c -

# branding related changes
test -f /usr/share/icons/hicolor/scalable/distributor-logo.svg
test -f /usr/share/pixmaps/system-logo-white.png
test -f /usr/share/icons/hicolor/scalable/apps/start-here.svg
test -f /usr/share/pixmaps/fedora-logo.svg
test -d /usr/share/plasma/look-and-feel/dev.getaurora.aurora.desktop

test -f /usr/share/backgrounds/aurora/aurora-wallpaper-10/contents/images/3840x2160.jxl
test -f /usr/share/wallpapers/aurora-wallpaper-10/contents/images/3840x2160.jxl
test -L /usr/share/backgrounds/default.jxl

xmllint --noout \
  /usr/share/backgrounds/default.xml

# If this file is not on the image bazaar will automatically be removed from users systems :(
# See: https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall
test -f /usr/share/flatpak/preinstall.d/bazaar.preinstall

# Make sure this garbage never makes it to an image
test -f /usr/lib/systemd/system/flatpak-add-fedora-repos.service && false

# Is flathub enabled by default?
test -f /etc/flatpak/remotes.d/flathub.flatpakrepo

# Make sure to not pull in the bazzite one
rpm -q plasma-setup --qf "%{RELEASE}" | grep -q aurora

test -f /usr/share/doc/aurora/aurora.pdf
test -f /usr/share/homebrew.tar.zst

# aurora-gravity: Homebrew's portable Ruby must match the image architecture.
# A per-arch amd64 brew digest once shipped x86-64 Ruby on aarch64 and broke brew.
BREW_RUBY_DIR="$(mktemp -d)"
tar --zstd -xf /usr/share/homebrew.tar.zst -C "${BREW_RUBY_DIR}" --wildcards '*/vendor/portable-ruby/*/bin/ruby'
BREW_RUBY="$(find "${BREW_RUBY_DIR}" -path '*/portable-ruby/*/bin/ruby' -type f | head -n1)"
# ELF e_machine (offset 18, little endian): 0xb7 = aarch64, 0x3e = x86-64
BREW_RUBY_MACHINE="$(od -An -tx1 -j18 -N1 "${BREW_RUBY}" | tr -d ' ')"
case "$(uname -m)" in
  aarch64) test "${BREW_RUBY_MACHINE}" = "b7" ;;
  x86_64) test "${BREW_RUBY_MACHINE}" = "3e" ;;
esac
rm -rf "${BREW_RUBY_DIR}"

desktop-file-validate \
  /usr/share/applications/dev.getaurora.discussions.desktop \
  /usr/share/applications/dev.getaurora.boot-to-windows.desktop \
  /usr/share/applications/dev.getaurora.offline-docs.desktop \
  /usr/share/applications/dev.getaurora.documentation.desktop \
  /usr/share/applications/dev.getaurora.system-update.desktop 

# Check for KDE Plasma version mismatch
# Fedora Repos have gotten the newer one, trying to upgrade

KDE_VER="$(rpm -q --qf '%{VERSION}' plasma-desktop)"
# package picked by failures in the past
KSCREEN_VERS="$(rpm -q --qf '%{VERSION}' kscreen)"
KWIN_VERS="$(rpm -q --qf '%{VERSION}' kwin)"

# Doing QT as well just in case, we have a versionlock in main
QT_VER="$(rpm -q --qf '%{VERSION}' qt6-qtbase)"
# Not an important package in itself, just a good indicator
QTFS_VER="$(rpm -q --qf '%{VERSION}' qt6-filesystem)"

if [[ "$KDE_VER" != "$KSCREEN_VERS" || "$KDE_VER" != "$KWIN_VERS" ]]; then
    echo "KDE Version mismatch"
    exit 1
fi

if [[ "$QT_VER" != "$QTFS_VER" ]]; then
    echo "QT Version mismatch"
    exit 1
fi

IMPORTANT_PACKAGES=(
    distrobox
    fish
    flatpak
    krunner-bazaar
    kwin
    pipewire
    plasma-desktop
    podman
    plasma-login-manager
    Sunshine
    systemd
    tailscale
    uupd
    wireplumber
    zsh
)

for package in "${IMPORTANT_PACKAGES[@]}"; do
    rpm -q "${package}" >/dev/null || { echo "Missing package: ${package}... Exiting"; exit 1 ; }
done

# these should be sourced from negativo's fedora-multimedia repo
# as Fedora can't ship patent encumbered video codecs
NEGATIVO=(
    ffmpeg
    libheif
    libva
    pipewire-libs-extra
    x264-libs
    x265-libs
)

for package in "${NEGATIVO[@]}"; do
  rpm -q --qf "%{NAME} %{VENDOR}" "${package}" | grep -q "negativo17\.org" || { echo "${package} not from negativo... Exiting"; exit 1 ; }
done

# aurora-gravity: Apple Silicon platform checks
GRAVITY_PACKAGES=(
    kernel-16k-core
    mesa-dri-drivers
    mesa-filesystem
    mesa-vulkan-drivers
    dracut-gravity
    update-m1n1
    gravity-bootloader
    uboot-images-armv8
)

for package in "${GRAVITY_PACKAGES[@]}"; do
  rpm -q --qf "%{RELEASE}" "${package}" | grep -q "gravity" || { echo "${package} is not the Gravity build... Exiting"; exit 1 ; }
done

if rpm -q kernel-core >/dev/null 2>&1; then
  echo "Stock Fedora kernel-core is installed... Exiting"; exit 1
fi

mapfile -t KVERS < <(ls /usr/lib/modules)
[[ "${#KVERS[@]}" -eq 1 && "${KVERS[0]}" =~ \+16k$ ]] || { echo "Expected exactly one 16k kernel, got: ${KVERS[*]}"; exit 1; }
KDIR="/usr/lib/modules/${KVERS[0]}"
test -f "${KDIR}/vmlinuz"
test -f "${KDIR}/initramfs.img"
test -f "${KDIR}/dtb/apple/t8132-j713.dtb" # MacBook Air 13" M4
test -f /usr/lib64/m1n1/m1n1.bin
test -f /usr/share/uboot/apple_m1/u-boot-nodtb.bin
test -x /usr/libexec/aurora-gravity-m1n1-sync
grep -q 'gzip -nc' /usr/bin/update-m1n1
systemctl is-enabled aurora-gravity-m1n1-sync.service | grep -q '^enabled$'

# Gravity dracut modules (Apple platform drivers + vendor firmware loading) must be in the initramfs
INITRD_LIST=$(lsinitrd "${KDIR}/initramfs.img")
for needle in gravity-firmware kernel-modules-gravity load-gravity-firmware.sh gravity-scripts/functions.sh; do
  grep -q -- "${needle}" <<<"${INITRD_LIST}" || { echo "initramfs is missing ${needle}... Exiting"; exit 1; }
done

# these packages are supposed to be removed
# and are considered footguns
UNWANTED_PACKAGES=(
    akonadi-server
    fedora-flathub-remote
    fedora-logos
    fedora-third-party
    firefox
    plasma-discover
)

for package in "${UNWANTED_PACKAGES[@]}"; do
    if rpm -q "${package}" >/dev/null 2>&1; then
        echo "Unwanted package found: ${package}... Exiting"; exit 1
    fi
done

if [[ "${IMAGE_NAME}" =~ nvidia ]]; then
  NV_PACKAGES=(
      kmod-nvidia
      libnvidia-container-tools
      nvidia-driver-cuda
)
  for package in "${NV_PACKAGES[@]}"; do
      rpm -q "${package}" >/dev/null || { echo "Missing NVIDIA package: ${package}... Exiting"; exit 1 ; }
  done
fi

if [[ ${AKMODS_FLAVOR} =~ coreos ]]; then
  ZFS_PACKAGES=(
      kmod-zfs
      zfs
      python3-pyzfs
)
  for package in "${ZFS_PACKAGES[@]}"; do
      rpm -q "${package}" >/dev/null || { echo "Missing ZFS package: ${package}... Exiting"; exit 1 ; }
  done
fi

IMPORTANT_UNITS=(
    rpm-ostree-countme.timer
    tailscaled.service
    ublue-system-setup.service
    uupd.timer
  )

for unit in "${IMPORTANT_UNITS[@]}"; do
    if ! systemctl is-enabled "$unit" 2>/dev/null | grep -q "^enabled$"; then
        echo "${unit} is not enabled"
        exit 1
    fi
done

if [[ "${IMAGE_FLAVOR}" == "dx" ]]; then
  /ctx/build_scripts/dx/10-tests-dx.sh;
fi

echo "::endgroup::"
