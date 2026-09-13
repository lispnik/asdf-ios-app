#!/bin/sh
# Build LispSwift.framework for each iOS platform, under build/<platform>/.
# Needs Xcode's swiftc.  swift.asd runs this before building the app, and
# nothing is rebuilt while the framework is newer than the source.
#
# The install name is the part that matters: the app is linked with an rpath
# of @executable_path/Frameworks, and dyld finds the framework there only if
# the framework names itself @rpath/LispSwift.framework/LispSwift.  Without
# that it names this build directory, which the phone does not have.
set -e
cd "$(dirname "$0")"
MIN=16.0   # Swift Charts and ImageRenderer arrived in iOS 16

build() {
  platform=$1; sdk=$2; target=$3; supported=$4
  out="build/$platform/LispSwift.framework"
  if [ "$out/LispSwift" -nt LispSwift.swift ]; then
    echo "$out is current"
    return
  fi
  mkdir -p "$out"
  # SDKROOT as well as -sdk: the link step swiftc runs reads the former, and
  # without it warns about using the macOS sysroot for an iPhone target.
  SDKROOT="$(xcrun --sdk "$sdk" --show-sdk-path)" \
  xcrun swiftc -O -swift-version 5 \
    -sdk "$(xcrun --sdk "$sdk" --show-sdk-path)" -target "$target" \
    -emit-library -module-name LispSwift \
    -Xlinker -install_name -Xlinker @rpath/LispSwift.framework/LispSwift \
    -o "$out/LispSwift" LispSwift.swift
  cat > "$out/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>org.asdf-ios-app.LispSwift</string>
  <key>CFBundleExecutable</key><string>LispSwift</string>
  <key>CFBundleName</key><string>LispSwift</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>MinimumOSVersion</key><string>$MIN</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$supported</string></array>
</dict>
</plist>
PLIST
  echo "built $out"
}

build iphonesimulator iphonesimulator "arm64-apple-ios$MIN-simulator" iPhoneSimulator
build iphoneos        iphoneos        "arm64-apple-ios$MIN"           iPhoneOS
