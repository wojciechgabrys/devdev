#!/bin/sh
# Packs a built devdev.app into a compressed disk image with an Applications shortcut,
# so the app can be dragged into /Applications.
#
# Usage: scripts/make-dmg.sh <devdev.app> <output.dmg>

set -eu

if [ $# -ne 2 ]; then
    echo "Usage: $0 <devdev.app> <output.dmg>" >&2
    exit 64
fi

app=$1
output=$2

if [ ! -d "$app/Contents/Helpers/devdevHelper.app" ]; then
    echo "$app has no Helper inside it." >&2
    exit 1
fi
if [ ! -x "$app/Contents/Helpers/devdev" ]; then
    echo "$app has no devdev CLI inside it." >&2
    exit 1
fi

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

ditto "$app" "$staging/devdev.app"
ln -s /Applications "$staging/Applications"

rm -f "$output"
hdiutil create -volname devdev -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$output"

echo "Created $output"
