#!/bin/sh
#
# build-ecl-ios.sh -- build a host ECL and cross-build it for iOS.
#
#   build-ecl-ios.sh <ecl-source-tree> <install-root> [platform ...]
#
# Platforms are "host", "iphoneos" and "iphonesimulator"; the default is all
# three. Products under <install-root>:
#
#   host/              a host ECL, which DRIVES the cross builds
#   iphoneos/          arm64, iPhoneOS SDK
#   iphonesimulator/   arm64, iPhoneSimulator SDK
#
# The host ECL is not a convenience. The cross build reuses its dpp and
# ecl_min, and dpp resolves each @[pkg::sym] in the C sources to a numeric
# *index* into src/c/symbols_list.h -- so a host ECL from a different revision
# does not fail, it silently resolves every symbol to the wrong index. It must
# come from the same tree as the cross builds, which is why this script builds
# it rather than looking for one on PATH.

set -e

SOURCE=$1
ROOT=$2
[ -n "$SOURCE" ] && [ -n "$ROOT" ] || {
  echo "usage: $0 <ecl-source-tree> <install-root> [platform ...]" >&2
  exit 2
}
shift 2
PLATFORMS=${*:-"host iphoneos iphonesimulator"}

SOURCE=`cd "$SOURCE" && pwd`
mkdir -p "$ROOT"
ROOT=`cd "$ROOT" && pwd`

SDKS=`xcode-select --print-path`/Platforms
JOBS=`sysctl -n hw.ncpu 2>/dev/null || echo 4`

host_prefix() { echo "$ROOT/host"; }

# --------------------------------------------------------------------------
# host
# --------------------------------------------------------------------------

build_host() {
  prefix=`host_prefix`
  if [ -x "$prefix/bin/ecl" ] &&
     [ ! "$SOURCE/src/c/symbols_list.h" -nt "$prefix/bin/ecl" ]; then
    echo "host: up to date"
    return 0
  fi
  echo "=== building host ECL ==="
  (
    cd "$SOURCE"
    # None of the iOS settings, nor anything inherited from the caller, may
    # leak in. LIBRARY_PATH matters especially: a Homebrew LIBRARY_PATH with no
    # matching header path makes configure find -lgmp but not gmp.h, and it
    # then errors out rather than falling back to the bundled copy.
    unset CC CXX CPP LD CFLAGS CXXFLAGS CPPFLAGS LDFLAGS LIBS ECL_TO_RUN
    unset LIBRARY_PATH CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH

    # The bundled GMP on purpose: this ECL is a build tool and should not
    # depend on whatever happens to be installed on the machine.
    buildir="$ROOT/build-host" ./configure --prefix="$prefix" \
                                           --disable-c99complex \
                                           --enable-gmp=included
    # Bypass the top-level Makefile: it hardcodes `cd build'.
    make -C "$ROOT/build-host" -j"$JOBS"
    make -C "$ROOT/build-host" install
  )
}

# --------------------------------------------------------------------------
# cross
# --------------------------------------------------------------------------

build_cross() {
  platform=$1
  sdk=$2
  min_flag=$3
  prefix="$ROOT/$platform"
  builddir="$ROOT/build-$platform"

  [ -x "`host_prefix`/bin/ecl" ] || {
    echo "no host ECL at `host_prefix` -- build it first" >&2
    exit 1
  }

  if [ -f "$prefix/lib/libecl.a" ] &&
     [ ! "$SOURCE/src/c/symbols_list.h" -nt "$prefix/lib/libecl.a" ]; then
    echo "$platform: up to date"
    return 0
  fi

  # Reconfiguring on top of a finished cross tree leaves it inconsistent:
  # ecl_min dies part-way through building the target image. So when there IS
  # work to do, start from nothing rather than trying to reuse.
  echo "=== cross-building ECL for $platform ==="
  rm -rf "$builddir" "$prefix"
  (
    cd "$SOURCE"
    CFLAGS="-arch arm64 $min_flag -isysroot $sdk"
    CFLAGS="$CFLAGS -pipe -Wno-trigraphs -Wreturn-type -Wunused-variable"
    CFLAGS="$CFLAGS -fmessage-length=0 -fvisibility=hidden"
    CFLAGS="$CFLAGS -O2 -DNO_ASM -DGC_DISABLE_INCREMENTAL -DECL_RWLOCK"

    # configure ties ENABLE_DLOPEN to --enable-shared, but they are not the
    # same question. An iOS app must link statically and can still dlsym its
    # own symbols. Without this SI:FIND-FOREIGN-SYMBOL refuses to resolve
    # anything, which costs us CFFI: its ECL backend looks foreign functions
    # up by name.
    CFLAGS="$CFLAGS -DENABLE_DLOPEN=1"

    export CC=clang CXX=clang++ LD=ld
    export CFLAGS
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS="-arch arm64 $min_flag -isysroot $sdk -pipe -gdwarf-2"
    export LIBS="-framework Foundation"
    export ECL_TO_RUN="`host_prefix`/bin/ecl"

    buildir="$builddir" ./configure \
        --host=aarch64-apple-darwin \
        --prefix="$prefix" \
        --disable-c99complex \
        --disable-shared \
        --with-cross-config="$SOURCE/src/util/iOS-arm64.cross_config"

    make -C "$builddir" -j"$JOBS"
    make -C "$builddir" install
  )
}

for platform in $PLATFORMS; do
  case $platform in
    host) build_host ;;
    iphoneos)
      build_cross iphoneos \
        "$SDKS/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk" \
        "-miphoneos-version-min=15.0" ;;
    iphonesimulator)
      build_cross iphonesimulator \
        "$SDKS/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk" \
        "-mios-simulator-version-min=15.0" ;;
    *) echo "unknown platform: $platform" >&2; exit 2 ;;
  esac
done
