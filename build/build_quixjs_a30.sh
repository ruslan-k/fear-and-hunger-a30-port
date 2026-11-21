#!/bin/bash
# Reproducible armhf build of the quixjs 0.3.0 runtime for the Miyoo A30.
# Run in an amd64 Debian/Ubuntu container with network access.
set -euo pipefail

BASE=$(cd "$(dirname "$0")/.." && pwd)
SRC=${QUIXJS_SRC:-$BASE/build/quixjs-0.3.0}
VERSION=0.3.0
TARGET=arm-linux-gnueabihf
A30_SYSROOT=/opt/a30/a30/$TARGET/sysroot

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  build-essential clang lld cmake ninja-build ruby perl python3 curl xz-utils \
  unzip git pkg-config binutils-arm-linux-gnueabihf ca-certificates >/dev/null

[ -d "$SRC/.git" ] || git clone --depth 1 --branch "$VERSION" \
  https://github.com/lowlevel-1989/quixjs.git "$SRC"
cd "$SRC"

# A30 patches: landscape->portrait presentation (QUIX_ROT) and the
# glibc 2.23 roundeven fallback needed by JavaScriptCore.
# Apply both the device support patch and the optional old-kernel memory
# availability fallback. Applying twice is harmless; other conflicts fail.
for PATCH in "$BASE/patches/quixjs-a30.patch" "$BASE/patches/quixjs-a30-memavailable.patch"; do
  if git apply --check "$PATCH" 2>/dev/null; then
    git apply "$PATCH"
  elif git apply --reverse --check "$PATCH" 2>/dev/null; then
    echo "Already applied: $(basename "$PATCH")"
  else
    echo "Patch does not apply: $PATCH" >&2
    exit 1
  fi
done

# The device buildroot toolchain (glibc 2.23); a stock armhf cross toolchain
# links against a newer glibc and the binary will not load on the A30.
[ -d /opt/a30/a30 ] || {
  mkdir -p /opt/a30
  curl -fsSL https://github.com/steward-fu/website/releases/download/miyoo-a30/a30_toolchain-v1.0.tar.gz \
    -o /tmp/a30_toolchain.tar.gz
  tar xzf /tmp/a30_toolchain.tar.gz -C /opt/a30
}

# build-jsc.sh expects its sysroot at obj/deps/sysroot-armhf.
mkdir -p obj/deps
rm -rf obj/deps/sysroot-armhf
cp -a "$A30_SYSROOT" obj/deps/sysroot-armhf
touch obj/deps/sysroot-armhf/.ready
# clang needs the gcc runtime objects from the toolchain inside the sysroot.
mkdir -p obj/deps/sysroot-armhf/usr/lib/gcc/$TARGET/13.2.0
cp -a /opt/a30/a30/lib/gcc/arm-a30-linux-gnueabihf/13.2.0/. \
  obj/deps/sysroot-armhf/usr/lib/gcc/$TARGET/13.2.0/
ln -sf "$(command -v arm-linux-gnueabihf-ar)" /usr/local/bin/arm-linux-gnu-ar
ln -sf "$(command -v arm-linux-gnueabihf-ranlib)" /usr/local/bin/arm-linux-gnu-ranlib

# Static JavaScriptCore + ICU + libc++, built against the A30 sysroot.
JOBS=${JOBS:-8} tools/build-jsc.sh armhf libcxx icu jsc install

SYSROOT="$SRC/obj/deps/sysroot-armhf"
JSC="$SRC/obj/deps/jsc-armhf"
CC="clang --target=$TARGET -march=armv7-a -mfpu=vfpv3-d16 -mfloat-abi=hard --sysroot=$SYSROOT"
LIBS="-L$JSC/lib -lJavaScriptCore -lWTF -lbmalloc -l:libatomic.a \
 -licui18n -licuuc -licudata -l:libc++.a -l:libc++abi.a \
 -lSDL2_ttf -lSDL2_image -lSDL2 -lm -lpthread -ldl -static-libgcc \
 -Wl,--gc-sections -Wl,--strip-all -Wl,--disable-new-dtags"

make -j"$JOBS" \
  CC="$CC" \
  JSC_BUILD="$JSC" \
  JSC_LIBS= \
  CFLAGS="-O2 -D_GNU_SOURCE -DQUIX_HANDHELD -Iruntime -Iruntime/thirdparty \
    -Iruntime/thirdparty/tomlc17 -Iobj/gen -I$JSC/include \
    -I$SYSROOT/usr/include/SDL2" \
  LDFLAGS="$LIBS" \
  VIDEO=0 \
  quixjs

file quixjs
readelf -V quixjs | grep -o 'GLIBC_[0-9.]*' | sort -uV | tail -1
readelf -d quixjs | grep NEEDED
cp quixjs "$BASE/runtime/quixjs.armhf"
md5sum "$BASE/runtime/quixjs.armhf"
