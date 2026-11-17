#!/usr/bin/bash
# Build LibrePods (AirPods control: battery, listening modes, ear detection, ...)
# from source and stage it under /out for the image to COPY in.
#
# Ported from strudelrora. The published Linux release is far behind, so we build
# the Rust rewrite on the upstream `linux/rust` branch, which is what upstream
# recommends. `just build` resolves the branch HEAD and passes it as
# LIBREPODS_REF, which also busts the cached builder layer when upstream changes.
# The builder runs on the same base image as the final image, so the binary
# links against the same libraries.

echo "::group:: ===$(basename "$0")==="

set -eoux pipefail

LIBREPODS_REPO="https://github.com/librepods-org/librepods.git"
LIBREPODS_REF="${LIBREPODS_REF:-linux/rust}"

dnf5 install -y --setopt=install_weak_deps=False \
    cargo rust gcc pkgconf-pkg-config dbus-devel pulseaudio-libs-devel git

git init -q /tmp/librepods
cd /tmp/librepods
git remote add origin "${LIBREPODS_REPO}"
git fetch -q --depth 1 origin "${LIBREPODS_REF}"
git checkout -q FETCH_HEAD
LIBREPODS_COMMIT="$(git rev-parse HEAD)"
echo "Building LibrePods ${LIBREPODS_COMMIT}"

cd linux-rust
CARGO_HOME=/tmp/cargo cargo build --release --locked

install -Dm0755 target/release/librepods /out/usr/bin/librepods
install -Dm0644 assets/me.kavishdevar.librepods.desktop \
    /out/usr/share/applications/me.kavishdevar.librepods.desktop
install -Dm0644 assets/icon.png \
    /out/usr/share/icons/hicolor/256x256/apps/me.kavishdevar.librepods.png
mkdir -p /out/usr/share/librepods
echo "${LIBREPODS_COMMIT}" > /out/usr/share/librepods/commit

echo "::endgroup::"
