#!/bin/bash
# build_mesa32.sh -- cross-build the Switch GL stack for AArch32 (libnx32):
#   libdrm_nouveau 1.0.1   devkitPro's nouveau <-> nvgpu/nvmap glue, downloaded
#                          into build/ (the v1.0.1 tag, checked by commit)
#   Mesa 20.1.0-rc3        this tree
# Output: static libEGL, libGLESv1_CM, libGLESv2, libglapi and libdrm_nouveau
# with headers and pkg-config files, installed into ./prefix.
#
# Run inside the toolchain container (./build.sh does that):
#   docker run --rm --platform linux/amd64 -v "$PWD:/work" -w /work \
#     ghcr.io/vita2hos/devcontainer/vita2hos:latest bash -lc "./build_mesa32.sh [step]"
# Steps: drm, mesa-setup, mesa, install, or all (the default).
set -euo pipefail
cd "$(dirname "$0")"
TOP=$PWD
PREFIX=$TOP/prefix
BUILD=$TOP/build
NX=$DEVKITPRO/libnx32
ARCH="-march=armv8-a+crc+crypto -mtune=cortex-a57 -mfloat-abi=softfp -mfpu=neon-fp-armv8 -mtp=soft -fPIE -ftls-model=local-exec"
CC=$DEVKITPRO/devkitARM/bin/arm-none-eabi-gcc
AR=$DEVKITPRO/devkitARM/bin/arm-none-eabi-gcc-ar
DRM_VERSION=1.0.1
DRM_COMMIT=137265185c95cf58ce94c7afecba14f895dac2a7
DRM_SRC=$BUILD/libdrm_nouveau-$DRM_VERSION
step=${1:-all}

fetch_drm() {
  [ -d "$DRM_SRC" ] && return
  mkdir -p "$BUILD"
  rm -rf "$DRM_SRC.part"
  git clone -q --depth 1 --branch "v$DRM_VERSION" \
    https://github.com/devkitPro/libdrm_nouveau.git "$DRM_SRC.part"
  local got
  got=$(git -C "$DRM_SRC.part" rev-parse HEAD)
  if [ "$got" != "$DRM_COMMIT" ]; then
    echo "libdrm_nouveau v$DRM_VERSION is $got, expected $DRM_COMMIT" >&2
    exit 1
  fi
  mv "$DRM_SRC.part" "$DRM_SRC"
}

build_drm() {
  fetch_drm
  local S=$DRM_SRC B=$BUILD/drm
  rm -rf "$B" && mkdir -p "$B" "$PREFIX/lib/pkgconfig" "$PREFIX/include"
  for f in "$S"/source/*.c; do
    echo "  drm: $(basename "$f")"
    $CC -g -O2 -Wall -Werror -ffunction-sections -fdata-sections $ARCH -D__SWITCH__ \
      -I"$S/include" -I"$NX/include" -c "$f" -o "$B/$(basename "${f%.c}").o"
  done
  $AR rcs "$PREFIX/lib/libdrm_nouveau.a" "$B"/*.o
  cp -r "$S"/include/* "$PREFIX/include/"
  sed -e "s,^prefix=.*,prefix=$PREFIX," "$S/libdrm_nouveau.pc" > "$PREFIX/lib/pkgconfig/libdrm_nouveau.pc"
  echo "libdrm_nouveau -> $PREFIX/lib/libdrm_nouveau.a"
}

flags() { local out=""; for a in "$@"; do out+="'$a',"; done; echo "${out%,}"; }

mesa_setup() {
  mkdir -p "$BUILD"
  local X=$BUILD/switch32_cross.txt
  local CARGS=($ARCH -O2 -ffunction-sections -fdata-sections -D__SWITCH__ -DHAVE_TIMESPEC_GET -I$PREFIX/include -isystem $NX/include)
  local LARGS=($ARCH -Wl,-z,notext -specs=$NX/switch32.specs -L$PREFIX/lib -L$NX/lib -lnx)
  cat > "$X" <<EOC
[binaries]
c = '$CC'
cpp = '$DEVKITPRO/devkitARM/bin/arm-none-eabi-g++'
ar = '$AR'
strip = '$DEVKITPRO/devkitARM/bin/arm-none-eabi-strip'
pkgconfig = '/usr/bin/pkg-config'

[properties]
pkg_config_libdir = '$PREFIX/lib/pkgconfig'

[built-in options]
c_args = [$(flags "${CARGS[@]}")]
cpp_args = [$(flags "${CARGS[@]}")]
c_link_args = [$(flags "${LARGS[@]}")]
cpp_link_args = [$(flags "${LARGS[@]}")]

[host_machine]
system = 'horizon'
cpu_family = 'arm'
cpu = 'cortex-a57'
endian = 'little'
EOC
  rm -rf "$BUILD/mesa"
  PKG_CONFIG_LIBDIR=$PREFIX/lib/pkgconfig meson setup \
    --buildtype=plain --cross-file="$X" --default-library=static --prefix="$PREFIX" \
    --libdir=lib -Db_ndebug=true "$BUILD/mesa" "$TOP"
}

mesa_build() {
  ninja -C "$BUILD/mesa" -j"$(nproc)" "$@"
}

case "$step" in
  drm) build_drm ;;
  mesa-setup) mesa_setup ;;
  mesa) mesa_build "${@:2}" ;;
  install) ninja -C "$BUILD/mesa" install ;;
  all) build_drm; mesa_setup; mesa_build; ninja -C "$BUILD/mesa" install ;;
  *) echo "unknown step $step (drm, mesa-setup, mesa, install, all)"; exit 1 ;;
esac
