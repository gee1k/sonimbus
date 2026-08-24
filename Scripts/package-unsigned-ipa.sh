#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
BUILD_DIR="$PROJECT_DIR/build/unsigned"
PRODUCTS_DIR="$PROJECT_DIR/.build/UnsignedProducts"
OBJECTS_DIR="$PROJECT_DIR/.build/UnsignedIntermediates"
APP_PATH="$PRODUCTS_DIR/Release-appletvos/NetEaseTV.app"

xcodebuild -quiet \
  -project "$PROJECT_DIR/NetEaseTV.xcodeproj" \
  -target NetEaseTV \
  -configuration Release \
  -sdk appletvos \
  SYMROOT="$PRODUCTS_DIR" \
  OBJROOT="$OBJECTS_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build

rm -rf "$BUILD_DIR/Payload"
mkdir -p "$BUILD_DIR/Payload"
ditto --norsrc "$APP_PATH" "$BUILD_DIR/Payload/NetEaseTV.app"
cd "$BUILD_DIR"
ditto -c -k --norsrc --keepParent Payload NetEaseTV-unsigned.ipa
print "已生成：$BUILD_DIR/NetEaseTV-unsigned.ipa"
print "注意：此包仅用于验证 IPA 结构，安装前仍需使用你的开发证书和描述文件签名。"
