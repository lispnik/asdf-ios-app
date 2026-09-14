#!/bin/sh
# Make spiral.drawing, the PencilKit drawing the app ships, with the Mac's own
# PencilKit.  Skipped while the drawing is newer than the script.
#
# Compiled, not interpreted, and with an Info.plist embedded: PencilKit saves
# a preference under the process's bundle identifier the first time a
# drawing is made, and a bare command-line binary has none, so
# CoreFoundation traps on a null key (CFEqual, under PKReplicaManager).  The
# __info_plist section is how a tool without a bundle gets an identifier.
set -e
cd "$(dirname "$0")"
if [ spiral.drawing -nt make-drawing.swift ]; then echo "spiral.drawing is current"; exit 0; fi
mkdir -p build
xcrun swiftc -O -o build/make-drawing make-drawing.swift \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker make-drawing-info.plist
./build/make-drawing
