#!/bin/sh
# Build libfingerprint.a for each iOS platform, under build/<platform>/.
# Plain clang; no Swift here.  ledger.asd runs this before building the
# app, and nothing is rebuilt while the archive is newer than the source.
set -e
cd "$(dirname "$0")"
build() {
  platform=$1; sdk=$2; target=$3
  out="build/$platform"
  if [ "$out/libfingerprint.a" -nt fingerprint.c ]; then
    echo "$out/libfingerprint.a is current"
    return
  fi
  mkdir -p "$out"
  xcrun clang -c -O2 -target "$target" -isysroot "$(xcrun --sdk "$sdk" --show-sdk-path)" \
    -o "$out/fingerprint.o" fingerprint.c
  rm -f "$out/libfingerprint.a"
  xcrun libtool -static -o "$out/libfingerprint.a" "$out/fingerprint.o"
  echo "built $out/libfingerprint.a"
}
build iphonesimulator iphonesimulator arm64-apple-ios15.0-simulator
build iphoneos        iphoneos        arm64-apple-ios15.0
