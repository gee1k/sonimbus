#!/bin/zsh
set -euo pipefail

print_usage() {
  print "用法：SONIMBUS_TEAM_ID=你的TeamID ./Scripts/package-ipa.sh [--no-upload]"
  print ""
  print "默认行为：归档、导出 IPA，并上传为 TestFlight Internal Only 构建。"
  print "  --no-upload    只归档并导出 IPA，不上传 App Store Connect"
}

SHOULD_UPLOAD=1
for argument in "$@"; do
  case "$argument" in
    --no-upload)
      SHOULD_UPLOAD=0
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      print -u2 "未知参数：$argument"
      print_usage >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
PROJECT_PATH="$PROJECT_DIR/Sonimbus.xcodeproj"
EXPORT_OPTIONS_TEMPLATE="$SCRIPT_DIR/TestFlightExportOptions.plist"
TEAM_ID=${SONIMBUS_TEAM_ID:-}
BUILD_NUMBER=${SONIMBUS_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}
MARKETING_VERSION_OVERRIDE=${SONIMBUS_MARKETING_VERSION:-}

if [[ -z "$TEAM_ID" ]]; then
  print -u2 "请通过 SONIMBUS_TEAM_ID 传入 Apple Developer Team ID。"
  print -u2 "示例：SONIMBUS_TEAM_ID=ABCDE12345 ./Scripts/package-ipa.sh"
  exit 2
fi

if [[ ! -f "$EXPORT_OPTIONS_TEMPLATE" ]]; then
  print -u2 "缺少导出配置：$EXPORT_OPTIONS_TEMPLATE"
  exit 3
fi

VERSION_ARGUMENTS=()
if [[ -n "$MARKETING_VERSION_OVERRIDE" ]]; then
  VERSION_ARGUMENTS=(MARKETING_VERSION="$MARKETING_VERSION_OVERRIDE")
fi

RELEASE_DIR="$PROJECT_DIR/build/testflight/$BUILD_NUMBER"
ARCHIVE_PATH="$RELEASE_DIR/Sonimbus.xcarchive"
IPA_EXPORT_DIR="$RELEASE_DIR/ipa"
UPLOAD_EXPORT_DIR="$RELEASE_DIR/upload"

if [[ -e "$RELEASE_DIR" ]]; then
  print -u2 "构建目录已存在：$RELEASE_DIR"
  print -u2 "请设置新的 SONIMBUS_BUILD_NUMBER 后重试。"
  exit 4
fi

mkdir -p "$IPA_EXPORT_DIR"

TEMP_EXPORT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/sonimbus-export.XXXXXX")
cleanup() {
  rm -rf "$TEMP_EXPORT_DIR"
}
trap cleanup EXIT

LOCAL_EXPORT_OPTIONS="$TEMP_EXPORT_DIR/export.plist"
UPLOAD_EXPORT_OPTIONS="$TEMP_EXPORT_DIR/upload.plist"
cp "$EXPORT_OPTIONS_TEMPLATE" "$LOCAL_EXPORT_OPTIONS"
cp "$EXPORT_OPTIONS_TEMPLATE" "$UPLOAD_EXPORT_OPTIONS"
plutil -replace destination -string export "$LOCAL_EXPORT_OPTIONS"
plutil -replace destination -string upload "$UPLOAD_EXPORT_OPTIONS"

print "正在归档 Sonimbus（版本号 $BUILD_NUMBER）…"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme Sonimbus \
  -configuration Release \
  -destination "generic/platform=tvOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  "${VERSION_ARGUMENTS[@]}" \
  archive

print "正在导出 TestFlight IPA…"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$IPA_EXPORT_DIR" \
  -exportOptionsPlist "$LOCAL_EXPORT_OPTIONS" \
  -allowProvisioningUpdates

IPA_FILES=("$IPA_EXPORT_DIR"/*.ipa(N))
if (( ${#IPA_FILES[@]} != 1 )); then
  print -u2 "预期导出 1 个 IPA，实际找到 ${#IPA_FILES[@]} 个：$IPA_EXPORT_DIR"
  exit 5
fi

print "已生成：${IPA_FILES[1]}"

if (( SHOULD_UPLOAD == 0 )); then
  print "已按 --no-upload 跳过 App Store Connect 上传。"
  exit 0
fi

mkdir -p "$UPLOAD_EXPORT_DIR"
print "正在上传 App Store Connect（TestFlight Internal Only）…"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$UPLOAD_EXPORT_DIR" \
  -exportOptionsPlist "$UPLOAD_EXPORT_OPTIONS" \
  -allowProvisioningUpdates

print "上传已完成。构建通过 App Store Connect 处理后会出现在 TestFlight 中。"
