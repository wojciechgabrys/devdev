#!/bin/sh
# Builds appcast.xml, the feed Sparkle reads, for one release. The feed holds one item: this version.
#
# Usage: scripts/make-appcast.sh <dmg> <version> <notes.md> <private-key-file> <output.xml>
#
#   <dmg>               The disk image to sign. Only its bytes are read.
#   <version>           The release version, such as 0.2.2.
#   <notes.md>          The release notes, as the Markdown GitHub generates.
#   <private-key-file>  One line: the base64 of the 32-byte EdDSA seed. "-" reads it from standard input.
#   <output.xml>        Where the appcast is written.
#
# The key is handed to Sparkle's sign_update as a file. It is never printed, never passed as an
# argument, never written to the output, and the Keychain is never read.
#
# sign_update comes with the Sparkle package and is not in the built app. It is looked for in:
#   1. $SIGN_UPDATE, the path of the tool itself
#   2. $DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin/
#   3. Xcode's own DerivedData folder for this checkout
# Resolve the packages first: xcodebuild -project devdev.xcodeproj -scheme devdev -resolvePackageDependencies

set -eu

if [ $# -ne 5 ]; then
    echo "Usage: $0 <dmg> <version> <notes.md> <private-key-file> <output.xml>" >&2
    exit 64
fi

dmg=$1
version=$2
notes=$3
key_file=$4
output=$5

repository="https://github.com/wojciechgabrys/devdev"
minimum_system_version="26.0"

# The version goes into the XML and the URL unescaped, so only digits and dots are allowed.
if ! printf '%s\n' "$version" | grep -Eq '^[0-9]+(\.[0-9]+)*$'; then
    echo "The version must be numbers and dots, such as 0.2.2." >&2
    exit 64
fi
if [ ! -f "$dmg" ]; then
    echo "$dmg is not a file." >&2
    exit 1
fi
if [ ! -f "$notes" ]; then
    echo "$notes is not a file." >&2
    exit 1
fi
if [ "$key_file" != "-" ] && [ ! -s "$key_file" ]; then
    echo "The private key file is missing or empty." >&2
    exit 1
fi

tool_in_artifacts="SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"

find_sign_update() {
    if [ -n "${SIGN_UPDATE:-}" ]; then
        printf '%s\n' "$SIGN_UPDATE"
        return
    fi
    if [ -n "${DERIVED_DATA:-}" ] && [ -x "$DERIVED_DATA/$tool_in_artifacts" ]; then
        printf '%s\n' "$DERIVED_DATA/$tool_in_artifacts"
        return
    fi
    # Every DerivedData folder records the project it belongs to in info.plist. The folder's name is
    # not checked: Xcode names it devdev-<hash>, but xcodebuild -derivedDataPath can name it anything.
    project="$(cd "$(dirname "$0")/.." && pwd -P)/devdev.xcodeproj"
    for folder in "$HOME"/Library/Developer/Xcode/DerivedData/*; do
        [ -x "$folder/$tool_in_artifacts" ] || continue
        workspace=$(/usr/libexec/PlistBuddy -c "Print :WorkspacePath" "$folder/info.plist" 2>/dev/null || true)
        if [ "$workspace" = "$project" ]; then
            printf '%s\n' "$folder/$tool_in_artifacts"
            return
        fi
    done
}

sign_update=$(find_sign_update)
if [ -z "$sign_update" ] || [ ! -x "$sign_update" ]; then
    echo "Sparkle's sign_update was not found. Resolve the packages first:" >&2
    echo "  xcodebuild -project devdev.xcodeproj -scheme devdev -resolvePackageDependencies" >&2
    echo "Or set SIGN_UPDATE to the tool's path." >&2
    exit 1
fi

# -p prints only the signature. With "-" as the key file, sign_update reads the key from standard input.
signature=$("$sign_update" -p --ed-key-file "$key_file" "$dmg")
if ! printf '%s\n' "$signature" | grep -Eq '^[A-Za-z0-9+/]+=*$'; then
    echo "sign_update did not print a signature." >&2
    exit 1
fi

length=$(stat -f %z "$dmg")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The notes go in as Markdown inside CDATA, where <, & and quotes need no escaping.
# Three things could still break the XML:
#   - bytes that are not UTF-8: iconv refuses them
#   - control characters XML 1.0 forbids: removed
#   - the sequence ]]>, which would end the CDATA early: split across two CDATA sections
if ! iconv -f UTF-8 -t UTF-8 "$notes" > "$work/notes"; then
    echo "$notes is not UTF-8 text." >&2
    exit 1
fi
LC_ALL=C tr -d '\000-\010\013\014\016-\037' < "$work/notes" | LC_ALL=C sed 's/]]>/]]]]><![CDATA[>/g' > "$work/cdata"

{
    cat <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>devdev</title>
    <link>$repository/releases/latest/download/appcast.xml</link>
    <item>
      <title>devdev $version</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$version</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$minimum_system_version</sparkle:minimumSystemVersion>
XML
    printf '      <description sparkle:format="markdown"><![CDATA['
    cat "$work/cdata"
    printf ']]></description>\n'
    cat <<XML
      <enclosure url="$repository/releases/download/v$version/devdev-$version.dmg" length="$length" type="application/octet-stream" sparkle:edSignature="$signature"/>
    </item>
  </channel>
</rss>
XML
} > "$work/appcast.xml"

mv "$work/appcast.xml" "$output"

echo "Created $output"
