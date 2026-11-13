# Aurora on Apple Silicon (Gravity Linux kernel)

`aurora-gravity` is [Aurora](https://github.com/ublue-os/aurora) (KDE, bootc/ostree,
Fedora 44 Kinoite base) rebuilt for **aarch64 Apple Silicon** using the
[Gravity Linux](https://github.com/GravityLinux) platform stack instead of
Universal Blue's x86-oriented kernel/akmods:

| Piece | Upstream Aurora | aurora-gravity |
|---|---|---|
| Kernel | `ghcr.io/ublue-os/akmods` (Fedora/CoreOS, 4K pages) | Gravity `kernel-16k` (COPR `adevwithanidea/gravity`) |
| Mesa | negativo17 | Gravity Mesa (Apple AGX/Asahi driver) |
| Initramfs | stock dracut | + `dracut-gravity` (Apple platform drivers, vendor firmware from the ESP) |
| Boot chain | shim → GRUB | m1n1 stage 1 → **m1n1 stage 2 + DTBs + U-Boot** (`ESP:/m1n1/boot.bin`) → shim → GRUB |
| Kernel modules (xone, v4l2loopback, ZFS, NVIDIA) | yes | not included |
| Arch | x86_64 | aarch64 only |

Images: `ghcr.io/nihaiden/aurora-gravity:latest` (daily) and `:stable` (weekly),
signed with [`aurora-gravity.pub`](system_files/shared/etc/pki/containers/aurora-gravity.pub).

## How the Apple Silicon bits work on ostree

On package-based Gravity, `kernel-install` runs `update-m1n1`, which rebuilds
`ESP:/m1n1/boot.bin` from the kernel's DTBs. ostree never runs kernel-install, so
the image ships `aurora-gravity-m1n1-sync.service`. It rebuilds `boot.bin` from
the deployment that boots next (`ostree admin status` lists it first), once at boot
and once at shutdown, after `ostree-finalize-staged`. So after a `bootc upgrade`,
the new kernel's DTBs are in place before you reboot into it. `update-m1n1` keeps
the previous file as `boot.bin.old`.

## Installing on a Mac that already runs Gravity Linux

This **replaces** the existing Gravity installation in place with
`bootc install to-existing-root`. It reuses your existing APFS stub (m1n1 stage 1),
ESP, `/boot` and btrfs partitions; macOS is never touched.

What happens to your data:
- **`/home`** (btrfs subvolume `home`) is kept and remounted at `/var/home`.
- **The old root** (subvolume `root`) is kept on disk, but stops being bootable:
  `/boot` is wiped, and the ESP's `EFI/` is rewritten. `m1n1/` and `vendorfw/` are
  kept, because bootc ≥ 1.17 only removes `EFI/` and `loader/`.
- **Users and `/etc`** come fresh from the image. You recreate your user on first
  boot.

### 0. Prerequisites

- macOS still boots. Hold the power button at startup to get the boot picker.
- An external drive for backups.
- The image is built and published. Check the Actions tab, or run
  `skopeo inspect docker://ghcr.io/nihaiden/aurora-gravity:latest`.

### 1. Back up

```bash
BK=/run/media/$USER/<your-external-drive>/pre-aurora   # adjust
mkdir -p "$BK"
sudo tar -C /boot/efi -cpf "$BK/esp.tar" .      # m1n1/boot.bin, vendorfw/, EFI/
sudo tar -C /boot     -cpf "$BK/boot.tar" .     # old kernels + GRUB config
sudo cp /etc/fstab "$BK/fstab"
# and of course: back up anything in /home you can't lose
```

### 2. Pull and verify the image

```bash
sudo podman pull ghcr.io/nihaiden/aurora-gravity:latest
# optional: verify the signature
curl -LO https://raw.githubusercontent.com/NiHaiden/aurora-gravity/gravity/system_files/shared/etc/pki/containers/aurora-gravity.pub
cosign verify --key aurora-gravity.pub ghcr.io/nihaiden/aurora-gravity:latest
```

### 3. Install over the running system

```bash
sudo podman run --rm --privileged --pid=host \
  -v /dev:/dev -v /var/lib/containers:/var/lib/containers -v /:/target \
  --security-opt label=type:unconfined_t \
  ghcr.io/nihaiden/aurora-gravity:latest \
  bootc install to-existing-root \
    --acknowledge-destructive \
    --generic-image \
    --target-imgref ghcr.io/nihaiden/aurora-gravity:latest
```

- `--generic-image` stops bootupd from writing EFI boot variables, which U-Boot
  doesn't persist. Your ESP keeps using the fallback path `EFI/BOOT/BOOTAA64.EFI`,
  exactly like Gravity does today.
- `root=UUID=…` and `rootflags=subvol=root` are inherited from the running kernel's
  command line.
- The `/boot` line is carried over from `/etc/fstab`.

### 4. Before rebooting: check the boot chain and mount /home

```bash
sudo ls -l /boot/efi/m1n1/boot.bin /boot/efi/vendorfw/firmware.cpio  # must exist
sudo ls /boot/efi/EFI/BOOT /boot/efi/EFI/fedora                      # BOOTAA64.EFI, shimaa64.efi, grubaa64.efi
sudo ls /boot/loader/entries                                         # one ostree-1-*.conf entry

# If m1n1/ or vendorfw/ are missing, restore them from the backup:
#   sudo tar -C /boot/efi -xpf "$BK/esp.tar" ./m1n1 ./vendorfw

# Mount the existing home subvolume in the new deployment
DEPLOY=$(sudo ls -d /ostree/deploy/default/deploy/*.0 | head -n1)
ROOT_UUID=$(findmnt -no UUID /)
echo "UUID=${ROOT_UUID} /var/home btrfs compress=zstd:1,subvol=home 0 0" | sudo tee -a "${DEPLOY}/etc/fstab"
sudo cat "${DEPLOY}/etc/fstab"
```

### 5. First boot

Reboot. Plasma Setup runs on first boot. Create your user with the **same username**
as before (for example `niklas`). As the first user it gets UID 1000 and reuses the
existing `/var/home/<user>`. Then:

```bash
# switch to signature-verified updates (uses the key baked into the image)
sudo bootc switch --enforce-container-sigpolicy ghcr.io/nihaiden/aurora-gravity:latest
bootc status
systemctl status aurora-gravity-m1n1-sync.service   # should be active (exited)
uname -r                                            # …gravity.fc44.aarch64+16k
```

Updates come from `uupd` automatically, or run `ujust update`. To roll back, run
`sudo bootc rollback`, or pick the previous entry in the GRUB menu.

### Recovery

- **macOS** is unaffected. Hold the power button and pick it in the boot picker.
- **A new deployment doesn't boot:** choose the older entry in GRUB. Its DTBs may be
  newer for one boot; `aurora-gravity-m1n1-sync` re-syncs `boot.bin` once you're
  back in.
- **Bad `boot.bin`:** boot macOS, mount the ESP (`diskutil list`, then
  `diskutil mount diskXsY`), and copy `m1n1/boot.bin.old` (or `boot.bin` from
  `esp.tar`) over `m1n1/boot.bin`.
- **Going back to package-based Gravity:** the old root is still in subvolume
  `root`. Restore `boot.tar` into `/boot`, and `EFI/` from `esp.tar` into the ESP,
  from any Linux environment that can mount them. Or reinstall Gravity with its
  installer.

## Building locally (on an Apple Silicon Linux machine)

```bash
just build aurora-gravity latest main   # needs podman/buildah, just, yq, cosign, skopeo
```

CI builds on GitHub's `ubuntu-26.04-arm` runners. See
`.github/workflows/build-image-latest-main.yml`.
