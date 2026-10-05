#!/bin/bash
# Build + install + launch Haider on the MacBook's booted iPhone 17 Pro sim.
#
# This Mac has no Xcode (Command Line Tools only), so the iOS build runs on the
# MacBook. Run from anywhere:  bash tools/build-sim.sh
set -euo pipefail

REMOTE=snailmac@snails-macbook-pro
SRC="$(cd "$(dirname "$0")/.." && pwd)"
DST='~/haider-ios'
UDID="${UDID:-C83F08A6-AB9C-402A-8B39-E7E85C237A0D}"
BUNDLE=com.snail3d.haider

echo "==> sync"
ssh "$REMOTE" "mkdir -p $DST"
rsync -az --delete \
  --exclude '.git' --exclude 'build' --exclude 'DerivedData' \
  "$SRC/" "$REMOTE:$DST/"

echo "==> generate project"
ssh "$REMOTE" "cd $DST && ~/bin/xcodegen generate --quiet && echo generated"

echo "==> build"
ssh "$REMOTE" "cd $DST && xcodebuild -project Haider.xcodeproj -scheme Haider \
  -destination 'platform=iOS Simulator,id=$UDID' -configuration Debug \
  -derivedDataPath build build 2>&1 | tail -25"

echo "==> install + launch"
ssh "$REMOTE" "xcrun simctl bootstatus $UDID -b >/dev/null 2>&1 || true; \
  xcrun simctl install $UDID $DST/build/Build/Products/Debug-iphonesimulator/Haider.app && \
  xcrun simctl launch $UDID $BUNDLE"

echo "==> screenshot"
ssh "$REMOTE" "sleep 3; xcrun simctl io $UDID screenshot /tmp/haider_shot.png"
rsync -az "$REMOTE:/tmp/haider_shot.png" /tmp/haider_shot.png
echo "shot: /tmp/haider_shot.png"