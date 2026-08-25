#!/bin/zsh
set -euo pipefail

print_usage() {
  print "用法：./Scripts/package-unsigned-ipa.sh [--build-number Build]"
  print ""
  print "生成可由用户自行签名安装的未签名 tvOS IPA。"
  print "  --build-number Build    覆盖工程中的 Build Number"
}

BUILD_NUMBER_OVERRIDE=""

while (( $# > 0 )); do
  case "$1" in
    --build-number)
      if (( $# < 2 )); then
        print -u2 -- "--build-number 需要 Build Number 参数。"
        exit 2
      fi
      BUILD_NUMBER_OVERRIDE=$2
      shift 2
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      print -u2 "未知参数：$1"
      print_usage >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
PROJECT_PATH="$PROJECT_DIR/Sonimbus.xcodeproj"

read -r MARKETING_VERSION PROJECT_BUILD_NUMBER < <("$SCRIPT_DIR/project-version.sh")
BUILD_NUMBER=${BUILD_NUMBER_OVERRIDE:-$PROJECT_BUILD_NUMBER}
BUILD_NUMBER_PATTERN='^[0-9]+([.][0-9]+){0,2}$'

if [[ ! "$BUILD_NUMBER" =~ $BUILD_NUMBER_PATTERN ]]; then
  print -u2 "无效的 Build Number：$BUILD_NUMBER"
  print -u2 "Build Number 必须由一至三段非负整数组成。"
  exit 2
fi

RELEASE_DIR="$PROJECT_DIR/build/unsigned/$MARKETING_VERSION/$BUILD_NUMBER"
OUTPUT_PATH="$RELEASE_DIR/Sonimbus-tvOS-${MARKETING_VERSION}-build.${BUILD_NUMBER}-unsigned.ipa"
DERIVED_DATA_DIR="$PROJECT_DIR/.build/UnsignedDerivedData"
APP_PATH="$DERIVED_DATA_DIR/Build/Products/Release-appletvos/Sonimbus.app"

if [[ -e "$OUTPUT_PATH" ]]; then
  print -u2 "未签名 IPA 已存在：$OUTPUT_PATH"
  exit 4
fi

print "正在编译 Sonimbus $MARKETING_VERSION（Build $BUILD_NUMBER）未签名 tvOS 构建…"
xcodebuild -quiet \
  -project "$PROJECT_PATH" \
  -scheme Sonimbus \
  -configuration Release \
  -destination "generic/platform=tvOS" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  print -u2 "未找到编译产物：$APP_PATH"
  exit 5
fi

TEMP_PACKAGE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sonimbus-unsigned.XXXXXX")
cleanup() {
  rm -rf "$TEMP_PACKAGE_DIR"
}
trap cleanup EXIT

mkdir -p "$TEMP_PACKAGE_DIR/Payload" "$RELEASE_DIR"
ditto --norsrc "$APP_PATH" "$TEMP_PACKAGE_DIR/Payload/Sonimbus.app"
cd "$TEMP_PACKAGE_DIR"
ditto -c -k --norsrc --keepParent Payload "$OUTPUT_PATH"

print "已生成：$OUTPUT_PATH"
print "此 IPA 未包含开发者签名，可使用支持 tvOS 的签名工具以用户自己的 Apple Account 签名安装。"
