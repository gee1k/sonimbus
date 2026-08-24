#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
BUILD_DIR="$PROJECT_DIR/build"
PRODUCTS_DIR="$BUILD_DIR/xcode-products"
OBJECTS_DIR="$BUILD_DIR/xcode-intermediates"
PAYLOAD_DIR="$BUILD_DIR/Payload"
TEAM_ID=${DEVELOPMENT_TEAM:-}

if [[ -z "$TEAM_ID" ]]; then
  print -u2 "请设置 DEVELOPMENT_TEAM，例如：DEVELOPMENT_TEAM=ABCDE12345 ./Scripts/package-ipa.sh"
  exit 2
fi

mkdir -p "$BUILD_DIR"

xcodebuild -quiet \
  -project "$PROJECT_DIR/NetEaseTV.xcodeproj" \
  -target NetEaseTV \
  -configuration Release \
  -sdk appletvos \
  SYMROOT="$PRODUCTS_DIR" \
  OBJROOT="$OBJECTS_DIR" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates \
  build

APP_PATH="$PRODUCTS_DIR/Release-appletvos/NetEaseTV.app"
if [[ ! -d "$APP_PATH" ]]; then
  print -u2 "构建输出中没有找到 NetEaseTV.app"
  exit 3
fi

rm -rf "$PAYLOAD_DIR"
mkdir -p "$PAYLOAD_DIR"
ditto --norsrc "$APP_PATH" "$PAYLOAD_DIR/NetEaseTV.app"

cd "$BUILD_DIR"
ditto -c -k --norsrc --keepParent Payload NetEaseTV.ipa
print "已生成：$BUILD_DIR/NetEaseTV.ipa"
