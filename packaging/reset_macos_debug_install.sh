#!/usr/bin/env bash

set -euo pipefail

RESET_BTM=0
ASSUME_YES=0

for ARGUMENT in "$@"; do
  case "$ARGUMENT" in
    --reset-btm)
      RESET_BTM=1
      ;;
    --yes)
      ASSUME_YES=1
      ;;
    -h|--help)
      echo "用法: $0 [--reset-btm] [--yes]"
      echo "  --reset-btm  同时重置 macOS 后台项目授权记录，会影响本机所有后台项目"
      echo "  --yes        跳过 --reset-btm 的确认提示"
      exit 0
      ;;
    *)
      echo "未知参数: $ARGUMENT" >&2
      exit 1
      ;;
  esac
done

APP_PATH="/Applications/WLoc8.com.app"
BUNDLE_ID="com.hrtt.applocmac"
HELPER_LABEL="com.hrtt.applocmac.helper"
HELPER_NAME="WLocPrivilegedHelper"
PAC_MARKER="127.0.0.1:18089/wloc.pac"

echo "准备清理 WLoc8.com 开发安装状态..."

sudo /usr/bin/pkill -f "$HELPER_NAME" 2>/dev/null || true

if [[ -d "$APP_PATH" ]]; then
  sudo /bin/rm -rf "$APP_PATH"
  echo "已删除 $APP_PATH"
else
  echo "未发现 $APP_PATH"
fi

/usr/bin/defaults delete "$BUNDLE_ID" 2>/dev/null || true
echo "已清理 $BUNDLE_ID 偏好"

while IFS= read -r SERVICE; do
  [[ -n "$SERVICE" && "$SERVICE" != "An asterisk"* && "$SERVICE" != \** ]] || continue
  PROXY_INFO="$(/usr/sbin/networksetup -getautoproxyurl "$SERVICE" 2>/dev/null || true)"
  if [[ "$PROXY_INFO" == *"$PAC_MARKER"* ]]; then
    /usr/sbin/networksetup -setautoproxystate "$SERVICE" off 2>/dev/null || true
    echo "已关闭 $SERVICE 的 WLoc PAC"
  fi
done < <(/usr/sbin/networksetup -listallnetworkservices)

if [[ "$RESET_BTM" == "1" ]]; then
  if [[ "$ASSUME_YES" != "1" ]]; then
    echo
    echo "警告：resetbtm 会重置本机所有后台项目授权记录，不只影响 WLoc8.com。"
    read -r -p "确认继续？输入 YES: " CONFIRMATION
    [[ "$CONFIRMATION" == "YES" ]] || {
      echo "已跳过 resetbtm"
      exit 0
    }
  fi
  sudo /bin/launchctl bootout "system/$HELPER_LABEL" 2>/dev/null || true
  sudo /System/Library/PrivateFrameworks/BackgroundTaskManagement.framework/Resources/sfltool resetbtm
  echo "已重置后台项目授权记录"
fi

echo
echo "清理完成。现在可以回到 Xcode 执行 Build and Run，重现初次安装流程。"
