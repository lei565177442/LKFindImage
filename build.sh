#!/usr/bin/env bash
# 编译 LKFindImage.dylib（在 macOS + Xcode 环境下运行）
set -euo pipefail

cd "$(dirname "$0")"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
MINVER="14.0"
OUT="LKFindImage.dylib"
OBJDIR="build"

echo "==> SDK: ${SDK}"
xcrun --sdk iphoneos clang --version | head -2

mkdir -p "${OBJDIR}"
rm -f "${OBJDIR}"/*.o

CFLAGS=(-arch arm64 -miphoneos-version-min="${MINVER}" -isysroot "${SDK}" -O2 -fPIC)

# Objective-C 源文件
for f in src/*.m; do
  echo "==> CC ${f}"
  xcrun --sdk iphoneos clang "${CFLAGS[@]}" -fobjc-arc -c "${f}" \
    -o "${OBJDIR}/$(basename "${f%.m}").o"
done

# C 源文件（不带 ARC 标志）
for f in src/*.c; do
  echo "==> CC ${f}"
  xcrun --sdk iphoneos clang "${CFLAGS[@]}" -c "${f}" \
    -o "${OBJDIR}/$(basename "${f%.c}").o"
done

echo "==> LINK ${OUT}"
xcrun --sdk iphoneos clang \
  -arch arm64 \
  -miphoneos-version-min="${MINVER}" \
  -isysroot "${SDK}" \
  -dynamiclib \
  -install_name "@executable_path/Frameworks/LKFindImage.dylib" \
  -framework UIKit -framework Foundation -framework QuartzCore \
  -framework CoreGraphics \
  -o "${OUT}" \
  "${OBJDIR}"/*.o

# 自签名（注入工具会重新签名，这里确保产物本身可被加载）
codesign --force --sign - "${OUT}" 2>/dev/null || true

echo "==> OK: $(pwd)/${OUT}"
ls -lh "${OUT}"
