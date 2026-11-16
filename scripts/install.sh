#!/bin/sh
# Builds the Release configuration and copies the app to /Applications/devdev.app.
#
# A running Helper is left alone: it keeps its Processes and keeps running the build it was
# started from. The App shows a banner when the running Helper is outdated, and you decide there.
#
# Usage: scripts/install.sh [folder]
#   folder  Where devdev.app goes. Defaults to /Applications.

set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
destination_folder=${1:-/Applications}
destination="$destination_folder/devdev.app"
derived_data="$root/.build/install"
built="$derived_data/Build/Products/Release/devdev.app"

cd "$root"
xcodebuild -project devdev.xcodeproj -scheme devdev -configuration Release \
    -destination platform=macOS -derivedDataPath "$derived_data" build

if [ ! -d "$built/Contents/Helpers/devdevHelper.app" ]; then
    echo "The Release build has no Helper inside $built." >&2
    exit 1
fi
if [ ! -x "$built/Contents/Helpers/devdev" ]; then
    echo "The Release build has no devdev CLI inside $built." >&2
    exit 1
fi

# Copy beside the old app first, then swap, so a failed copy leaves the old app in place.
staging="$destination_folder/.devdev-install.$$"
rm -rf "$staging"
ditto "$built" "$staging"
rm -rf "$destination"
mv "$staging" "$destination"

echo "Installed $destination"
