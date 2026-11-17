#!/bin/bash
# Sets up the key that signs DevDev updates. Run it once, by hand.
#
# 1. Checks that gh is signed in and can set secrets on the repo.
# 2. Runs Sparkle's generate_keys. The private key stays in your login Keychain.
#    A key that is already there is reused. This script never makes a second one.
# 3. Sets the private key as the Actions secret SPARKLE_ED_PRIVATE_KEY.
# 4. Prints the public key and says what happens next.
#
# The private key is never printed. It touches the disk only as a temporary file that
# only you can read, and that file is removed when the script ends, also on failure.
#
# Usage: scripts/setup-update-key.sh
#
# SPARKLE_BIN, when set, names the folder that holds generate_keys. Without it the
# script looks in Xcode's DerivedData for the Sparkle package the project pins.

set -euo pipefail

repo="wojciechgabrys/devdev"
secret="SPARKLE_ED_PRIVATE_KEY"

fail() {
    echo "Error: $*" >&2
    exit 1
}

# Prints the path of generate_keys, or fails when no resolved Sparkle package holds it.
find_generate_keys() {
    local folder
    if [ -n "${SPARKLE_BIN:-}" ]; then
        [ -x "$SPARKLE_BIN/generate_keys" ] || return 1
        printf '%s\n' "$SPARKLE_BIN/generate_keys"
        return 0
    fi
    for folder in "$HOME"/Library/Developer/Xcode/DerivedData/devdev-*/SourcePackages/artifacts/sparkle/Sparkle/bin; do
        if [ -x "$folder/generate_keys" ]; then
            printf '%s\n' "$folder/generate_keys"
            return 0
        fi
    done
    return 1
}

work=""
cleanup() {
    if [ -n "$work" ]; then
        rm -rf "$work"
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM HUP

cd "$(dirname "$0")/.."

echo "Step 1 of 4: checking gh."
command -v gh > /dev/null || fail "gh is not installed. Install it with: brew install gh"
gh auth status > /dev/null 2>&1 || fail "gh is not signed in. Run: gh auth login"
# Listing a repo's secrets needs the same access as setting one, and changes nothing.
gh secret list --repo "$repo" > /dev/null 2>&1 \
    || fail "gh cannot manage Actions secrets on $repo. Sign in as an account that can, with the repo scope."

echo "Step 2 of 4: the key in your Keychain."
if ! generate_keys=$(find_generate_keys); then
    [ -z "${SPARKLE_BIN:-}" ] || fail "No generate_keys in $SPARKLE_BIN."
    echo "Sparkle's tools are not downloaded yet. Resolving the packages."
    xcodebuild -project devdev.xcodeproj -scheme devdev -resolvePackageDependencies > /dev/null \
        || fail "xcodebuild could not resolve the packages."
    generate_keys=$(find_generate_keys) \
        || fail "No generate_keys found. Set SPARKLE_BIN to the folder that holds it."
fi

echo "macOS may ask to let generate_keys use the Keychain. Choose Allow."
# -p only looks a key up. Without arguments generate_keys makes a key only when none exists.
if public_key=$("$generate_keys" -p 2> /dev/null) && [ -n "$public_key" ]; then
    echo "Found a key in your Keychain. Reusing it."
else
    "$generate_keys" > /dev/null || fail "generate_keys could not make a key."
    public_key=$("$generate_keys" -p) || fail "generate_keys made a key but could not read it back."
    echo "Made a new key in your Keychain."
fi
[[ "$public_key" =~ ^[A-Za-z0-9+/]{43}=$ ]] \
    || fail "generate_keys printed something that is not a public key."

echo "Step 3 of 4: setting the $secret secret on $repo."
umask 077
work=$(mktemp -d "${TMPDIR:-/tmp}/devdev-update-key.XXXXXX")
# generate_keys refuses to write over a file, so the export goes to a new name in a new folder.
"$generate_keys" -x "$work/private-key" > /dev/null || fail "generate_keys could not export the private key."
[ -s "$work/private-key" ] || fail "The exported private key is empty."
gh secret set "$secret" --repo "$repo" < "$work/private-key" || fail "gh could not set $secret on $repo."
rm -rf "$work"
work=""

echo "Step 4 of 4: done."
echo
echo "Public key:"
echo
echo "    $public_key"
echo
echo "What happens next:"
echo "- This public key goes into Config/App-Info.plist as SUPublicEDKey. It is not a secret."
echo "- Each v* tag signs the DMG with the secret and publishes appcast.xml with the release."
echo "- The private key lives only in your login Keychain, account ed25519. Keep a backup of it."
echo "  If it is lost, installed copies can no longer be updated."
echo "- Running this script again reuses the same key and sets the secret again."
