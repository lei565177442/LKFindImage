#!/usr/bin/env bash
# 编译 LKFindImage.dylib（在 macOS + Xcode 环境下运行）
set -euo pipefail

cd "$(dirname "$0")"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
MINVER="14.0"
OUT="LKFindImage.dylib"

echo "==> SDK: ${SDK}"

xcrun --sdk iphoneos clang \
  -arch arm64 \
  -miphoneos-version-min="${MINVER}" \
  -isysroot "${SDK}" \
  -O2 -fobjc-arc \
  -dynamiclib \
  -install_name "@executable_path/Frameworks/LKFindImage.dylib" \
  -framework UIKit -framework Foundation -framework QuartzCore \
  -o "${OUT}" \
  src/LKFIMatcher.c \
  src/LKFISupport.m \
  src/LKFIUI.m \
  src/LKFIEntry.m

# 自签名（注入工具会重新签名，这里确保产物本身可被加载）
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "${OUT}" 2>/dev/null || true
fi

echo "==> OK: $(pwd)/${OUT}"
ls -lh "${OUT}"
