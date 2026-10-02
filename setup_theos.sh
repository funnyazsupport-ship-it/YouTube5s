#!/bin/bash
# One-time setup of the iOS build tools inside WSL (run as root): Theos + Linux iOS toolchain + iPhoneOS SDK.
# Shared by YouTube5s and TikTok5s; running it twice is harmless.
set -u
export THEOS=/opt/theos

apt-get update -qq
apt-get install -y -qq build-essential fakeroot rsync curl perl zip unzip git libtinfo6 zstd libxml2

if [ ! -d "$THEOS/makefiles" ]; then
    git clone --recursive https://github.com/theos/theos.git "$THEOS"
fi
mkdir -p "$THEOS/toolchain" "$THEOS/sdks"

if [ ! -d "$THEOS/toolchain/linux/iphone" ]; then
    if [ -d /toolchain/linux ]; then
        # left over from an earlier attempt that unpacked into the filesystem root
        mv /toolchain/linux "$THEOS/toolchain/" && rmdir /toolchain
    else
        cd /tmp
        [ -f iOSToolchain-x86_64.tar.xz ] || curl -LO https://github.com/L1ghtmann/llvm-project/releases/latest/download/iOSToolchain-x86_64.tar.xz
        tar -xf iOSToolchain-x86_64.tar.xz -C "$THEOS/toolchain/"
    fi
fi

if [ -z "$(ls "$THEOS/sdks")" ]; then
    [ -d /tmp/sdks ] || git clone --depth 1 https://github.com/theos/sdks.git /tmp/sdks
    cp -r /tmp/sdks/iPhoneOS14.5.sdk "$THEOS/sdks/"
fi

echo
echo "SDK:       $(ls "$THEOS/sdks")"
echo "Toolchain: $(ls "$THEOS/toolchain/linux/iphone/bin" 2>/dev/null | wc -l) tools"
[ -x "$THEOS/toolchain/linux/iphone/bin/clang" ] && echo "OK - now run build.sh" || echo "FAILED - clang is missing"
