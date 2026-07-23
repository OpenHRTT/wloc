#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INVOCATION_DIR="$(pwd -P)"
BACKGROUND_PATH="${BACKGROUND_PATH:-$INVOCATION_DIR/dmg-background.png}"
CONFIGURATION="Release"
OUTPUT_DIR="$INVOCATION_DIR"
APP_PATH="${APP_PATH:-}"
BUILD_APP=0
SKIP_LAYOUT=0

usage() {
  echo "用法: $0 [--app /path/WLocApp-macOS.app] [--background /path/dmg-background.png] [--output /path] [--build] [--configuration Release] [--skip-layout]"
  echo "默认从当前目录读取 WLocApp-macOS.app 和 dmg-background.png，并将 DMG 输出到当前目录。"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      APP_PATH="$2"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --background)
      BACKGROUND_PATH="$2"
      shift 2
      ;;
    --configuration)
      CONFIGURATION="$2"
      shift 2
      ;;
    --build)
      BUILD_APP=1
      shift
      ;;
    --skip-build)
      # 向后兼容：现在默认就不会自动构建。
      BUILD_APP=0
      shift
      ;;
    --skip-layout)
      SKIP_LAYOUT=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知参数: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$BACKGROUND_PATH" ]]; then
  echo "缺少 DMG 背景图: $BACKGROUND_PATH" >&2
  exit 1
fi

DERIVED_DATA="$PROJECT_ROOT/build/dmg-derived-data"
if [[ "$BUILD_APP" -eq 1 ]]; then
  xcodebuild \
    -workspace "$PROJECT_ROOT/WLocApp.xcworkspace" \
    -scheme "WLocApp-macOS" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    build
  APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/WLocApp-macOS.app"
fi

if [[ -z "$APP_PATH" ]]; then
  APP_PATH="$INVOCATION_DIR/WLocApp-macOS.app"
fi
if [[ ! -d "$APP_PATH" ]]; then
  echo "未找到 macOS App: $APP_PATH" >&2
  echo "请将 WLocApp-macOS.app 放到当前目录、通过 --app 指定路径，或使用 --build 构建。" >&2
  exit 1
fi

HELPER_PATH="$APP_PATH/Contents/MacOS/WLocPrivilegedHelper"
DAEMON_PLIST="$APP_PATH/Contents/Library/LaunchDaemons/com.hrtt.applocmac.helper.plist"
if [[ ! -x "$HELPER_PATH" || ! -f "$DAEMON_PLIST" ]]; then
  echo "App 缺少 Privileged Helper 或 LaunchDaemon 配置，请使用 WLocApp-macOS Scheme 重新构建。" >&2
  exit 1
fi
plutil -lint "$DAEMON_PLIST" >/dev/null

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "1.0")"
VOLUME_NAME="WLoc8.com"
DMG_NAME="WLoc8.com-${VERSION}.dmg"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DMG="$OUTPUT_DIR/$DMG_NAME"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wloc8-dmg.XXXXXX")"
RW_DMG="$STAGING_DIR/WLoc8.com-rw.dmg"
MOUNT_DEVICE=""
MOUNT_PATH=""
MOUNT_NAME=""

cleanup() {
  if [[ -n "$MOUNT_DEVICE" ]]; then
    hdiutil detach "$MOUNT_DEVICE" -quiet || true
  fi
  # 临时目录必须来自上面的专用 mktemp 模板，避免清理路径意外扩大。
  if [[ "$STAGING_DIR" == */wloc8-dmg.* ]]; then
    rm -rf "$STAGING_DIR"
  fi
}
trap cleanup EXIT

mkdir -p "$STAGING_DIR/source/.background"
ditto "$APP_PATH" "$STAGING_DIR/source/WLoc8.com.app"
cp "$BACKGROUND_PATH" "$STAGING_DIR/source/.background/background.png"
ln -s /Applications "$STAGING_DIR/source/Applications"

rm -f "$OUTPUT_DMG"
hdiutil create \
  -srcfolder "$STAGING_DIR/source" \
  -volname "$VOLUME_NAME" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_DMG" >/dev/null

if [[ "$SKIP_LAYOUT" -eq 0 ]]; then
  ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
  MOUNT_DEVICE="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS/ {print $1; exit}')"
  MOUNT_PATH="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS/ {sub(/^.*Apple_HFS[[:space:]]+/, ""); print; exit}')"
  if [[ -z "$MOUNT_DEVICE" || "$MOUNT_PATH" != /Volumes/* || ! -d "$MOUNT_PATH" ]]; then
    echo "无法确定 DMG 的实际挂载位置。" >&2
    exit 1
  fi
  MOUNT_NAME="${MOUNT_PATH##*/}"

  # Finder 会把图标位置和背景写入卷内的 .DS_Store；这是拖拽安装界面的关键步骤。
  osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$MOUNT_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {100, 100, 760, 542}
    set theViewOptions to icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 112
    set text size of theViewOptions to 13
    set background picture of theViewOptions to file ".background:background.png"
    set position of item "WLoc8.com.app" of container window to {160, 210}
    set position of item "Applications" of container window to {500, 210}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

  for _ in {1..30}; do
    [[ -f "$MOUNT_PATH/.DS_Store" ]] && break
    sleep 0.1
  done
  if [[ ! -f "$MOUNT_PATH/.DS_Store" ]]; then
    echo "Finder 未能写入 DMG 背景布局。" >&2
    exit 1
  fi

  # 挂载可写镜像时 macOS 可能自动创建这些运行期目录；它们不属于安装包内容。
  rm -rf "$MOUNT_PATH/.fseventsd" "$MOUNT_PATH/.Trashes"
  sync
  hdiutil detach "$MOUNT_DEVICE" -quiet
  MOUNT_DEVICE=""
  MOUNT_PATH=""
  MOUNT_NAME=""
fi

hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUTPUT_DMG" >/dev/null
echo "DMG 已生成: $OUTPUT_DMG"
