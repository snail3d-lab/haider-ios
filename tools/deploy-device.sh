#!/bin/bash
# Build Haider, sign it, and install it on Eric's iPhone.
#
# Run this from an interactive Terminal ON THE MACBOOK, not over ssh: the login
# keychain has to be unlocked for `codesign` to reach the signing key, and a
# non-interactive ssh session gets "User interaction is not allowed"
# (errSecInternalComponent) instead.
#
#   bash tools/deploy-device.sh
#
# Prerequisites: the iPhone awake and unlocked, and a cable connected.
set -euo pipefail

REMOTE=snailmac@snails-macbook-pro
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DST='~/haider-ios'
DEVICE="${DEVICE:-0084299D-CFAF-53B6-A07A-89FECF059B91}"   # Eric's iPhone 17 Pro Max
BUNDLE=com.snail3d.haider
APP="build-device/Build/Products/Debug-iphoneos/Haider.app"

echo "==> keychain"
if ! security show-keychain-info ~/Library/Keychains/login.keychain-db >/dev/null 2>&1; then
  echo "    login keychain is locked; unlocking (your password stays local)"
  security unlock-keychain ~/Library/Keychains/login.keychain-db
fi

echo "==> device visible?"
if ! xcrun devicectl list devices 2>/dev/null | grep -q "$DEVICE"; then
  echo "    iPhone not found. Wake it, unlock it, and check the cable." >&2
  exit 1
fi
if xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | grep -q unavailable; then
  echo "    iPhone is asleep or locked. Wake it and unlock it, then rerun." >&2
  exit 1
fi

echo "==> sync sources"
rsync -az --delete --exclude '.git' --exclude 'build' --exclude 'build-device' \
  "$SRC/" "$REMOTE:$DST/"

echo "==> generate + build (signed)"
ssh "$REMOTE" "cd $DST && ~/bin/xcodegen generate --quiet && \
  xcodebuild -project Haider.xcodeproj -scheme Haider \
    -destination 'platform=iOS,id=$DEVICE' -configuration Debug \
    -derivedDataPath build-device -allowProvisioningUpdates build 2>&1 | \
  grep -E 'error:|Signing Identity|BUILD' | tail -6"

echo "==> install + launch"
ssh "$REMOTE" "xcrun devicectl device install app --device $DEVICE $DST/$APP && \
  xcrun devicectl device process launch --device $DEVICE $BUNDLE"

echo "==> done: Haider is on the phone"