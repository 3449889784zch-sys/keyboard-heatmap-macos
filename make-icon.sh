#!/bin/bash
# 生成 Resources/AppIcon.icns —— 用 CoreGraphics 画各尺寸 PNG，再用 iconutil 合成。
set -euo pipefail
cd "$(dirname "$0")"

CACHE_ROOT="${TMPDIR:-/tmp}"
MODCACHE="${CACHE_ROOT%/}/keystats-modcache"   # 必须 ASCII 路径（见 build.sh 说明）
mkdir -p "$MODCACHE" .build

SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
[ -x "$SWIFTC" ] || SWIFTC="swiftc"
SDK="$(/usr/bin/xcrun --show-sdk-path 2>/dev/null || echo /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk)"
TARGET="$(uname -m)-apple-macos13.0"

echo "▶ 编译图标生成器 ..."
"$SWIFTC" Tools/MakeIcon.swift -o .build/makeicon \
  -sdk "$SDK" -target "$TARGET" -module-cache-path "$MODCACHE"

ICONSET="${CACHE_ROOT%/}/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p Resources
echo "▶ 绘制各尺寸 PNG + 直接打包 .icns ..."
.build/makeicon "$ICONSET" Resources/AppIcon.icns

echo "✅ 已生成 Resources/AppIcon.icns"
