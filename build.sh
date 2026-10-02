#!/bin/bash
# Builds YouTube5s.ipa (run inside WSL after setup_theos.sh). The .ipa lands next to this script.
set -eu
NAME=YouTube5s
export THEOS="${THEOS:-/opt/theos}"
SRC="$(cd "$(dirname "$0")" && pwd)"
WORK="$HOME/ios-build/$NAME"

# Build on the Linux filesystem: Theos needs real Unix permissions, which /mnt/d does not have.
mkdir -p "$WORK"
rsync -a --delete --exclude '.theos' --exclude '_ipa' --exclude '*.ipa' "$SRC/" "$WORK/"
cd "$WORK"

make clean >/dev/null 2>&1 || true
make FINALPACKAGE=1 stage

rm -rf "$WORK/_ipa"
mkdir -p "$WORK/_ipa/Payload"
cp -r "$WORK/.theos/_/Applications/$NAME.app" "$WORK/_ipa/Payload/"
(cd "$WORK/_ipa" && zip -qr "$WORK/$NAME.ipa" Payload)
cp "$WORK/$NAME.ipa" "$SRC/$NAME.ipa"
echo "Done: $SRC/$NAME.ipa"
