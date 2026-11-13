#!/bin/bash
# Build GravityLinux Mesa as a Flatpak GL extension (org.freedesktop.Platform.GL.gravity)
# and make Flatpak apps use it.
#
# Why: Flathub's org.freedesktop.Platform.GL.default Mesa only speaks the upstream Asahi
# kernel UAPI. Gravity's GPU driver (e.g. asahi_m4 on M4) differs, so every GPU submit
# from a Flatpak app fails (DRM_IOCTL_ASAHI_QUEUE_CREATE: EINVAL) and windows render as
# solid pink. The host Mesa can't simply be copied in (it needs a newer glibc than the
# runtime), so this rebuilds the host's exact Mesa revision against the Flatpak SDK.
#
# Usage (as your normal user, on the host):
#   contrib/flatpak-gl-gravity.sh            # build + install, then log out and back in
# Re-run it after a gravity Mesa update (the script tells you if the extension is stale:
#   contrib/flatpak-gl-gravity.sh --check).
#
# Env: WORK (default ~/.cache/flatpak-gl-gravity), RUNTIME_BRANCH (default 25.08)
set -euo pipefail

RUNTIME_BRANCH="${RUNTIME_BRANCH:-25.08}"
LLVM_EXT=llvm22          # matches the LLVM the host Mesa links against
LLVM_TAG=llvmorg-22.1.8  # libclc source; keep in step with the SDK's llvm22 extension
TRANSLATOR_TAG=v22.1.8   # SPIRV-LLVM-Translator for that LLVM
SPIRV_TOOLS_TAG=vulkan-sdk-1.4.363.0
ARCH=aarch64
EXT_ID=org.freedesktop.Platform.GL.gravity
EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/extension/$EXT_ID/$ARCH/$RUNTIME_BRANCH"
ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/environment.d/60-flatpak-gl-gravity.conf"
SELF="$(readlink -f "$0")"

host_mesa_rev() {
  rpm -q --provides mesa-dri-drivers | sed -n 's/^gravity-mesa-revision = //p' | head -n1
}

# ---------------------------------------------------------------- inside the SDK
if [ "${1:-}" = "--inside-sdk" ]; then
  WORK="$2"
  source "/usr/lib/sdk/$LLVM_EXT/enable.sh"
  DEPS="$WORK/deps"
  PREFIX="/usr/lib/$ARCH-linux-gnu/GL/gravity"
  STAGE="$WORK/stage"
  JOBS=$(nproc)
  export PATH="$DEPS/bin:$PATH"
  export PKG_CONFIG_PATH="$DEPS/lib/pkgconfig:$DEPS/share/pkgconfig"
  export LD_LIBRARY_PATH="$DEPS/lib:/usr/lib/sdk/$LLVM_EXT/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  export PYTHONPATH="$DEPS/py"
  CMAKE=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$DEPS"
         -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_POSITION_INDEPENDENT_CODE=ON)
  LLVM_CMAKE="/usr/lib/sdk/$LLVM_EXT/lib/cmake/llvm"
  mkdir -p "$DEPS"
  once() { [ -e "$DEPS/.done-$1" ] || { echo "=== $1"; "$2"; touch "$DEPS/.done-$1"; }; }

  b_py() { pip3 install -q --target "$DEPS/py" pyyaml $(python3 -c 'import mako' 2>/dev/null || echo mako); }
  b_spirv_tools() {
    cmake -S "$WORK/SPIRV-Tools" -B "$WORK/build/spirv-tools" "${CMAKE[@]}" \
      -DSPIRV-Headers_SOURCE_DIR="$WORK/SPIRV-Headers" -DSPIRV_SKIP_TESTS=ON \
      -DSPIRV_SKIP_EXECUTABLES=ON -DSPIRV_WERROR=OFF -DBUILD_SHARED_LIBS=OFF
    ninja -C "$WORK/build/spirv-tools" -j"$JOBS" install
  }
  b_translator() {
    cmake -S "$WORK/SPIRV-LLVM-Translator" -B "$WORK/build/translator" "${CMAKE[@]}" \
      -DLLVM_DIR="$LLVM_CMAKE" \
      -DLLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR="$WORK/SPIRV-Headers-translator" \
      -DLLVM_SPIRV_INCLUDE_TESTS=OFF -DBUILD_SHARED_LIBS=OFF
    ninja -C "$WORK/build/translator" -j"$JOBS" install
  }
  b_libclc() {
    cmake -S "$WORK/llvm-project/libclc" -B "$WORK/build/libclc" "${CMAKE[@]}" \
      -DLLVM_DIR="$LLVM_CMAKE" -DLLVM_SPIRV="$DEPS/bin/llvm-spirv" \
      -DLIBCLC_TARGETS_TO_BUILD="spirv-mesa3d-;spirv64-mesa3d-"
    ninja -C "$WORK/build/libclc" -j"$JOBS" install
  }
  once py b_py
  once spirv-tools b_spirv_tools
  once translator b_translator
  once libclc b_libclc

  echo "=== mesa"
  if [ ! -e "$WORK/build/mesa/build.ninja" ]; then
    meson setup "$WORK/build/mesa" "$WORK/mesa" \
      --prefix="$PREFIX" --libdir=lib --buildtype=release -Db_ndebug=true \
      -Dplatforms=x11,wayland \
      -Dgallium-drivers=asahi,llvmpipe -Dvulkan-drivers=asahi -Dvulkan-layers=device-select \
      -Dgles1=enabled -Dgles2=enabled -Dopengl=true \
      -Dgbm=enabled -Dglx=dri -Degl=enabled -Dglvnd=enabled \
      -Dllvm=enabled -Dshared-llvm=enabled \
      -Dgallium-rusticl=false -Dgallium-va=disabled -Dteflon=false \
      -Dmicrosoft-clc=disabled -Dinstall-mesa-clc=false \
      -Dspirv-tools=enabled -Dvalgrind=disabled -Dlibunwind=disabled \
      -Dlmsensors=disabled -Dandroid-libbacktrace=disabled -Dbuild-tests=false
  fi
  ninja -C "$WORK/build/mesa" -j"$JOBS"

  echo "=== stage"
  rm -rf "$STAGE"
  DESTDIR="$STAGE" meson install -C "$WORK/build/mesa" --no-rebuild --quiet
  cd "$STAGE$PREFIX"
  # Same layout as GL.default: vulkan/ and glvnd/ at the root (they're merge-dirs of the
  # runtime's GL extension point); drirc.d stays in share/ where Mesa looks for it.
  for d in share/*; do [ "$(basename "$d")" = drirc.d ] || mv "$d" .; done
  rm -rf include lib/pkgconfig
  cp -L "/usr/lib/sdk/$LLVM_EXT/lib/libLLVM.so.22.1" lib/   # llvmpipe; not in the runtime
  missing=$(for f in lib/*.so* lib/*/*.so*; do LD_LIBRARY_PATH="$PWD/lib" ldd "$f" 2>/dev/null | grep 'not found' || true; done)
  [ -z "$missing" ] || { echo "unresolved libraries:"; echo "$missing"; exit 1; }
  exit 0
fi

# ---------------------------------------------------------------- on the host
if [ -e /.flatpak-info ]; then echo "run this on the host, not inside a sandbox" >&2; exit 1; fi

REV="$(host_mesa_rev)"
[ -n "$REV" ] || { echo "mesa-dri-drivers has no gravity-mesa-revision; is this a Gravity system?" >&2; exit 1; }

if [ "${1:-}" = "--check" ]; then
  have="$(cat "$EXT_DIR/.gravity-mesa-revision" 2>/dev/null || echo none)"
  if [ "$have" = "$REV" ]; then echo "up to date ($REV)"; exit 0; fi
  echo "stale: extension $have, host $REV. Re-run $SELF"; exit 1
fi

WORK="${WORK:-${XDG_CACHE_HOME:-$HOME/.cache}/flatpak-gl-gravity}"
mkdir -p "$WORK"
cd "$WORK"

echo "=== SDK $RUNTIME_BRANCH + $LLVM_EXT"
flatpak install -y --noninteractive flathub \
  "org.freedesktop.Sdk//$RUNTIME_BRANCH" "org.freedesktop.Sdk.Extension.$LLVM_EXT//$RUNTIME_BRANCH"

echo "=== sources (gravity mesa $REV)"
gitclone() { [ -d "$2" ] || git -c advice.detachedHead=false clone -q --depth 1 -b "$3" "$1" "$2"; }
gitclone https://github.com/KhronosGroup/SPIRV-Tools SPIRV-Tools "$SPIRV_TOOLS_TAG"
gitclone https://github.com/KhronosGroup/SPIRV-Headers SPIRV-Headers "$SPIRV_TOOLS_TAG"
gitclone https://github.com/KhronosGroup/SPIRV-LLVM-Translator SPIRV-LLVM-Translator "$TRANSLATOR_TAG"
if [ ! -d SPIRV-Headers-translator ]; then
  git init -q SPIRV-Headers-translator
  git -C SPIRV-Headers-translator fetch -q --depth 1 https://github.com/KhronosGroup/SPIRV-Headers \
    "$(cat SPIRV-LLVM-Translator/spirv-headers-tag.conf)"
  git -C SPIRV-Headers-translator -c advice.detachedHead=false checkout -q FETCH_HEAD
fi
if [ ! -d llvm-project ]; then
  git -c advice.detachedHead=false clone -q --depth 1 --filter=blob:none --sparse -b "$LLVM_TAG" \
    https://github.com/llvm/llvm-project
  git -C llvm-project sparse-checkout set libclc cmake llvm/cmake/modules
fi
# The RPM records an abbreviated hash, so keep commit history (no trees/blobs) to resolve it.
[ -d mesa ] || git clone -q --filter=tree:0 --no-checkout https://github.com/GravityLinux/mesa mesa
if ! git -C mesa rev-parse -q --verify "$REV^{commit}" >/dev/null; then
  git -C mesa fetch -q --filter=tree:0 origin
fi
git -C mesa -c advice.detachedHead=false checkout -q "$REV"

echo "=== build (inside org.freedesktop.Sdk//$RUNTIME_BRANCH)"
cp "$SELF" "$WORK/.flatpak-gl-gravity.sh"
flatpak run --command=bash --filesystem="$WORK" --share=network \
  "org.freedesktop.Sdk//$RUNTIME_BRANCH" "$WORK/.flatpak-gl-gravity.sh" --inside-sdk "$WORK"

echo "=== install to $EXT_DIR"
rm -rf "$EXT_DIR"
mkdir -p "$EXT_DIR"
cp -a "$WORK/stage/usr/lib/$ARCH-linux-gnu/GL/gravity/." "$EXT_DIR/"
echo "$REV" > "$EXT_DIR/.gravity-mesa-revision"

mkdir -p "$(dirname "$ENV_FILE")"
cat > "$ENV_FILE" <<EOF
# Flatpak apps use GravityLinux Mesa ($EXT_ID), see contrib/flatpak-gl-gravity.sh
FLATPAK_GL_DRIVERS=gravity
EOF
systemctl --user set-environment FLATPAK_GL_DRIVERS=gravity || true

echo
echo "Done: $EXT_ID ($REV) installed."
echo "Log out and back in so apps started from Plasma pick up FLATPAK_GL_DRIVERS=gravity."
