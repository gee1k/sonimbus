#!/bin/zsh
set -euo pipefail

print_usage() {
  print "用法：./Scripts/package-ipa.sh --team-id TeamID [选项]"
  print ""
  print "默认使用 Xcode 自动签名，归档、导出 IPA，并上传到 App Store Connect。"
  print "  --team-id TeamID               Apple Developer Team ID（必填）"
  print "  --build-number Build           覆盖工程中的 Build Number"
  print "  --signing automatic|manual     签名模式，默认为 automatic"
  print "  --profile Profile名称          手动签名使用的 Profile；省略时自动查找"
  print "  --certificate 证书名称         手动签名使用的证书；省略时自动查找"
  print "  --no-upload                    只归档并导出 IPA，不上传 App Store Connect"
}

TEAM_ID=""
BUILD_NUMBER_OVERRIDE=""
SIGNING_STYLE="automatic"
PROVISIONING_PROFILE_SPECIFIER=""
DISTRIBUTION_SIGNING_CERTIFICATE=""
SHOULD_UPLOAD=1

while (( $# > 0 )); do
  case "$1" in
    --team-id)
      if (( $# < 2 )); then
        print -u2 -- "--team-id 需要 Team ID 参数。"
        exit 2
      fi
      TEAM_ID=$2
      shift 2
      ;;
    --build-number)
      if (( $# < 2 )); then
        print -u2 -- "--build-number 需要 Build Number 参数。"
        exit 2
      fi
      BUILD_NUMBER_OVERRIDE=$2
      shift 2
      ;;
    --signing)
      if (( $# < 2 )); then
        print -u2 -- "--signing 需要 automatic 或 manual 参数。"
        exit 2
      fi
      SIGNING_STYLE=$2
      shift 2
      ;;
    --profile)
      if (( $# < 2 )); then
        print -u2 -- "--profile 需要 Profile 名称参数。"
        exit 2
      fi
      PROVISIONING_PROFILE_SPECIFIER=$2
      shift 2
      ;;
    --certificate)
      if (( $# < 2 )); then
        print -u2 -- "--certificate 需要证书名称参数。"
        exit 2
      fi
      DISTRIBUTION_SIGNING_CERTIFICATE=$2
      shift 2
      ;;
    --no-upload)
      SHOULD_UPLOAD=0
      shift
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

if [[ -z "$TEAM_ID" ]]; then
  print -u2 "请通过 --team-id 传入 Apple Developer Team ID。"
  print -u2 "示例：./Scripts/package-ipa.sh --team-id ABCDE12345"
  exit 2
fi

SIGNING_STYLE=${(L)SIGNING_STYLE}
if [[ "$SIGNING_STYLE" != "automatic" && "$SIGNING_STYLE" != "manual" ]]; then
  print -u2 "不支持的签名模式：$SIGNING_STYLE"
  print -u2 "请使用 automatic 或 manual。"
  exit 2
fi

if [[ "$SIGNING_STYLE" == "automatic" && \
  ( -n "$PROVISIONING_PROFILE_SPECIFIER" || -n "$DISTRIBUTION_SIGNING_CERTIFICATE" ) ]]; then
  print -u2 -- "--profile 和 --certificate 只适用于 --signing manual。"
  exit 2
fi

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
PROJECT_PATH="$PROJECT_DIR/Sonimbus.xcodeproj"
EXPORT_OPTIONS_TEMPLATE="$SCRIPT_DIR/TestFlightExportOptions.plist"
BUNDLE_ID="com.svend.sonimbus"
BUNDLE_ID_KEY=${BUNDLE_ID//./\\.}

read -r MARKETING_VERSION PROJECT_BUILD_NUMBER < <("$SCRIPT_DIR/project-version.sh")
BUILD_NUMBER=${BUILD_NUMBER_OVERRIDE:-$PROJECT_BUILD_NUMBER}
BUILD_NUMBER_PATTERN='^[0-9]+([.][0-9]+){0,2}$'

if [[ ! "$BUILD_NUMBER" =~ $BUILD_NUMBER_PATTERN ]]; then
  print -u2 "无效的 Build Number：$BUILD_NUMBER"
  print -u2 "Build Number 必须由一至三段非负整数组成。"
  exit 2
fi

if [[ ! -f "$EXPORT_OPTIONS_TEMPLATE" ]]; then
  print -u2 "缺少导出配置：$EXPORT_OPTIONS_TEMPLATE"
  exit 3
fi

find_matching_distribution_profile() {
  local directory candidate profile_xml profile_team application_identifier
  local profile_name expiration expiration_epoch beta_reports_active
  local now_epoch selected_name selected_expiration_epoch
  local -a profile_directories

  profile_directories=(
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
    "$HOME/Library/MobileDevice/Provisioning Profiles"
  )
  now_epoch=$(date +%s)
  selected_name=""
  selected_expiration_epoch=0

  for directory in "${profile_directories[@]}"; do
    [[ -d "$directory" ]] || continue

    for candidate in "$directory"/*.mobileprovision(N); do
      grep -a -q -F "$BUNDLE_ID" "$candidate" || continue
      profile_xml=$(security cms -D -i "$candidate" 2>/dev/null) || continue

      profile_team=$(print -r -- "$profile_xml" | \
        plutil -extract TeamIdentifier.0 raw -o - - 2>/dev/null) || continue
      [[ "$profile_team" == "$TEAM_ID" ]] || continue

      application_identifier=$(print -r -- "$profile_xml" | \
        plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null) || continue
      [[ "$application_identifier" == "$TEAM_ID.$BUNDLE_ID" ]] || continue

      beta_reports_active=$(print -r -- "$profile_xml" | \
        plutil -extract Entitlements.beta-reports-active raw -o - - 2>/dev/null) || continue
      [[ "$beta_reports_active" == "true" ]] || continue

      if print -r -- "$profile_xml" | \
        plutil -extract ProvisionedDevices xml1 -o - - >/dev/null 2>&1; then
        continue
      fi

      expiration=$(print -r -- "$profile_xml" | \
        plutil -extract ExpirationDate raw -o - - 2>/dev/null) || continue
      expiration_epoch=$(date -j -f '%Y-%m-%dT%H:%M:%SZ' "$expiration" '+%s' 2>/dev/null) || continue
      (( expiration_epoch > now_epoch )) || continue

      profile_name=$(print -r -- "$profile_xml" | \
        plutil -extract Name raw -o - - 2>/dev/null) || continue
      if (( expiration_epoch > selected_expiration_epoch )); then
        selected_name=$profile_name
        selected_expiration_epoch=$expiration_epoch
      fi
    done
  done

  [[ -n "$selected_name" ]] || return 1
  print -r -- "$selected_name"
}

XCODE_SIGNING_STYLE="Automatic"
ARCHIVE_SIGNING_ARGUMENTS=("CODE_SIGN_STYLE=$XCODE_SIGNING_STYLE")

if [[ "$SIGNING_STYLE" == "manual" ]]; then
  XCODE_SIGNING_STYLE="Manual"

  if [[ -z "$DISTRIBUTION_SIGNING_CERTIFICATE" ]]; then
    while IFS= read -r identity; do
      if [[ "$identity" == *"Distribution:"* && "$identity" == *"($TEAM_ID)"* ]]; then
        DISTRIBUTION_SIGNING_CERTIFICATE=${identity#*\"}
        DISTRIBUTION_SIGNING_CERTIFICATE=${DISTRIBUTION_SIGNING_CERTIFICATE%\"*}
        break
      fi
    done < <(security find-identity -v -p codesigning 2>/dev/null)
  fi

  if [[ -z "$DISTRIBUTION_SIGNING_CERTIFICATE" ]]; then
    print -u2 "未找到 Team $TEAM_ID 对应的 Apple Distribution/iPhone Distribution 签名证书。"
    print -u2 "可以通过 --certificate 显式指定证书名称。"
    exit 4
  fi

  if [[ -z "$PROVISIONING_PROFILE_SPECIFIER" ]]; then
    if ! PROVISIONING_PROFILE_SPECIFIER=$(find_matching_distribution_profile); then
      print -u2 "未找到 Team $TEAM_ID 与 $BUNDLE_ID 匹配的未过期 App Store Profile。"
      print -u2 "请安装 Profile，或通过 --profile 显式指定。"
      exit 5
    fi
    print "手动签名：已自动选择匹配的 Profile。"
  fi

  ARCHIVE_SIGNING_ARGUMENTS=(
    "CODE_SIGN_STYLE=$XCODE_SIGNING_STYLE"
    "CODE_SIGN_IDENTITY=$DISTRIBUTION_SIGNING_CERTIFICATE"
    "PROVISIONING_PROFILE_SPECIFIER=$PROVISIONING_PROFILE_SPECIFIER"
  )
fi

RELEASE_DIR="$PROJECT_DIR/build/testflight/$MARKETING_VERSION/$BUILD_NUMBER"
ARCHIVE_PATH="$RELEASE_DIR/Sonimbus.xcarchive"
IPA_EXPORT_DIR="$RELEASE_DIR/ipa"
UPLOAD_EXPORT_DIR="$RELEASE_DIR/upload"

if [[ -e "$RELEASE_DIR" ]]; then
  print -u2 "构建目录已存在：$RELEASE_DIR"
  print -u2 "请提高工程 Build Number，或通过 --build-number 指定新值。"
  exit 6
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

for export_options in "$LOCAL_EXPORT_OPTIONS" "$UPLOAD_EXPORT_OPTIONS"; do
  plutil -replace signingStyle -string "$SIGNING_STYLE" "$export_options"
  plutil -insert teamID -string "$TEAM_ID" "$export_options"

  if [[ "$SIGNING_STYLE" == "manual" ]]; then
    plutil -insert signingCertificate -string "$DISTRIBUTION_SIGNING_CERTIFICATE" "$export_options"
    plutil -insert provisioningProfiles -dictionary "$export_options"
    plutil -insert "provisioningProfiles.$BUNDLE_ID_KEY" \
      -string "$PROVISIONING_PROFILE_SPECIFIER" \
      "$export_options"
  fi
done

print "正在使用 $SIGNING_STYLE 签名归档 Sonimbus $MARKETING_VERSION（Build $BUILD_NUMBER）…"
xcodebuild \
  -quiet \
  -project "$PROJECT_PATH" \
  -scheme Sonimbus \
  -configuration Release \
  -destination "generic/platform=tvOS" \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  "${ARCHIVE_SIGNING_ARGUMENTS[@]}" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

print "正在导出 TestFlight IPA…"
xcodebuild \
  -quiet \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$IPA_EXPORT_DIR" \
  -exportOptionsPlist "$LOCAL_EXPORT_OPTIONS" \
  -allowProvisioningUpdates

IPA_FILES=("$IPA_EXPORT_DIR"/*.ipa(N))
if (( ${#IPA_FILES[@]} != 1 )); then
  print -u2 "预期导出 1 个 IPA，实际找到 ${#IPA_FILES[@]} 个：$IPA_EXPORT_DIR"
  exit 7
fi

IPA_OUTPUT_PATH="$IPA_EXPORT_DIR/Sonimbus-tvOS-${MARKETING_VERSION}-build.${BUILD_NUMBER}.ipa"
if [[ "${IPA_FILES[1]}" != "$IPA_OUTPUT_PATH" ]]; then
  mv "${IPA_FILES[1]}" "$IPA_OUTPUT_PATH"
fi
print "已生成：$IPA_OUTPUT_PATH"

if (( SHOULD_UPLOAD == 0 )); then
  print "已按 --no-upload 跳过 App Store Connect 上传。"
  exit 0
fi

mkdir -p "$UPLOAD_EXPORT_DIR"
print "正在上传 App Store Connect…"
xcodebuild \
  -quiet \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$UPLOAD_EXPORT_DIR" \
  -exportOptionsPlist "$UPLOAD_EXPORT_OPTIONS" \
  -allowProvisioningUpdates

print "上传已完成。构建通过 App Store Connect 处理后会出现在 TestFlight 中。"
