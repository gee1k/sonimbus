#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
PROJECT_PATH="$PROJECT_DIR/Sonimbus.xcodeproj"

if ! BUILD_SETTINGS=$(xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme Sonimbus \
  -configuration Release \
  -destination "generic/platform=tvOS" \
  -showBuildSettings 2>/dev/null); then
  print -u2 "无法读取 Sonimbus Release 构建设置。"
  exit 3
fi

MARKETING_VERSION=$(print -r -- "$BUILD_SETTINGS" | \
  awk -F ' = ' '/^[[:space:]]*MARKETING_VERSION = / { print $2; exit }')
BUILD_NUMBER=$(print -r -- "$BUILD_SETTINGS" | \
  awk -F ' = ' '/^[[:space:]]*CURRENT_PROJECT_VERSION = / { print $2; exit }')

if [[ -z "$MARKETING_VERSION" || -z "$BUILD_NUMBER" ]]; then
  print -u2 "无法从 Sonimbus Release 构建设置中读取版本号。"
  exit 3
fi

print -r -- "$MARKETING_VERSION $BUILD_NUMBER"
