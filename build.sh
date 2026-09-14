#!/bin/bash
# 构建「键盘热力图.app」——无需完整 Xcode，仅用 Command Line Tools。
# 直接调用真实的 swiftc 编译 Sources/*.swift，打包成 .app，再用稳定的本机签名签名。
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="键盘热力图"
BIN_NAME="KeyStats"
BUNDLE_ID="com.allen.keystats"
APP="${APP_NAME}.app"
BUILD=".build"
PKG="${APP_NAME}-安装包.pkg"
SIGNING_IDENTITY="KeyStats Local Dev"
SIGNING_DIR="$BUILD/local-signing"
SIGNING_PASSWORD="keystats-local-dev"

# ⚠ 关键：module cache / 临时目录必须是【纯 ASCII 路径】。
# 实测：swift 编译器在「含中文的 module-cache 路径」上会直接 SIGTRAP 崩溃，
# 而本项目目录名是中文，所以把缓存放到系统临时目录（ASCII）下，别放进项目目录。
mkdir -p "$BUILD"
CACHE_ROOT="${TMPDIR:-/tmp}"
MODCACHE="${CACHE_ROOT%/}/keystats-modcache"
mkdir -p "$MODCACHE"

# 选择编译器：优先用 Command Line Tools 里的真实 swiftc，其次回退到 PATH 里的 swiftc
CLT_SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
if [ -x "$CLT_SWIFTC" ]; then SWIFTC="$CLT_SWIFTC"; else SWIFTC="swiftc"; fi

# 选择 SDK：优先问 xcrun，问不到就回退到 CLT 的 SDK 软链
SDK="$(/usr/bin/xcrun --show-sdk-path 2>/dev/null || true)"
if [ -z "$SDK" ] || [ ! -d "$SDK" ]; then
  SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
fi

ARCH="$(uname -m)"           # arm64 或 x86_64
TARGET="${ARCH}-apple-macos13.0"

echo "▶ 编译器: $SWIFTC"
echo "▶ SDK   : $SDK"
echo "▶ 目标  : $TARGET"
echo "▶ 编译源码 ..."

"$SWIFTC" \
  Sources/*.swift \
  -o "$BUILD/$BIN_NAME" \
  -sdk "$SDK" \
  -target "$TARGET" \
  -module-cache-path "$MODCACHE" \
  -parse-as-library \
  -swift-version 5

echo "▶ 组装 .app 包 ..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/$BIN_NAME" "$APP/Contents/MacOS/$BIN_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  echo "⚠ 未找到 Resources/AppIcon.icns（先跑 ./make-icon.sh 生成图标）"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▶ 检查本机开发签名 ..."

# macOS 的「输入监控」权限会记录签名身份。ad-hoc 签名的 cdhash 会随着
# 每次编译变化，导致系统把新构建误认为另一个 app。这里生成一次免费的
# 本机代码签名证书，之后所有构建都复用同一个身份。
if ! security find-certificate -c "$SIGNING_IDENTITY" >/dev/null 2>&1; then
  echo "▶ 首次生成免费的本机签名证书 ..."
  mkdir -p "$SIGNING_DIR"
  KEY_FILE="$SIGNING_DIR/local-dev.key"
  CERT_FILE="$SIGNING_DIR/local-dev.crt"
  P12_FILE="$SIGNING_DIR/local-dev.p12"

  if [ ! -f "$P12_FILE" ]; then
    openssl req -new -x509 -newkey rsa:2048 -nodes \
      -keyout "$KEY_FILE" \
      -out "$CERT_FILE" \
      -days 3650 \
      -subj "/CN=$SIGNING_IDENTITY/O=KeyStats Local Development" \
      -addext "basicConstraints=critical,CA:FALSE" \
      -addext "keyUsage=critical,digitalSignature" \
      -addext "extendedKeyUsage=codeSigning" \
      -addext "subjectKeyIdentifier=hash"
    openssl pkcs12 -export \
      -legacy \
      -out "$P12_FILE" \
      -inkey "$KEY_FILE" \
      -in "$CERT_FILE" \
      -passout "pass:$SIGNING_PASSWORD"
  fi

  LOGIN_KEYCHAIN="$(security login-keychain | sed -e 's/^ *//' -e 's/^"//' -e 's/"$//')"
  security import "$P12_FILE" -k "$LOGIN_KEYCHAIN" -P "$SIGNING_PASSWORD" -T /usr/bin/codesign >/dev/null
fi

echo "▶ 使用稳定本机签名：$SIGNING_IDENTITY"
codesign --force --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify --verbose "$APP" || true

if [ "${1:-}" = "--pkg" ]; then
  echo "▶ 制作安装包 ..."
  rm -f "$PKG"
  pkgbuild \
    --identifier "${BUNDLE_ID}.installer" \
    --version "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" \
    --install-location /Applications \
    --component "$APP" \
    "$PKG"
  echo "✅ 安装包完成：$PWD/$PKG"
fi

echo ""
echo "✅ 构建完成：$PWD/$APP"
echo ""
echo "首次使用："
echo "  1) 打开 app（双击，或运行 ./build.sh --run）"
echo "  2) 在弹窗或「系统设置 › 隐私与安全性 › 输入监控」里勾选「${APP_NAME}」"
echo "  3) 若授权后没开始统计，退出 app 再重新打开一次即可"
echo ""
echo "✅ 后续构建会复用同一个本机签名，通常无需重复授权。"

if [ "${1:-}" = "--run" ]; then
  echo "▶ 启动 app ..."
  open "$APP"
fi
