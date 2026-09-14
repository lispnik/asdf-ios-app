#!/bin/sh
# Train Area.mlmodel with Create ML on the Mac, then compile it with coremlc
# into the Area.mlmodelc directory the app ships.  Skipped while the compiled
# model is newer than the script.  Needs Xcode: Create ML and coremlc are its.
set -e
cd "$(dirname "$0")"
if [ -d Area.mlmodelc ] && [ Area.mlmodelc -nt make-model.swift ]; then echo "Area.mlmodelc is current"; exit 0; fi
mkdir -p build
xcrun swiftc -O -o build/make-model make-model.swift \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker ../ink/make-drawing-info.plist
./build/make-model
rm -rf Area.mlmodelc
xcrun coremlc compile Area.mlmodel . > /dev/null
echo "compiled Area.mlmodelc"
