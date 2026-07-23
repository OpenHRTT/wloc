#!/usr/bin/env bash

set -euo pipefail

[[ "${CONFIGURATION:-}" == "Debug" ]] || exit 0
[[ "${WLOC_SKIP_DEBUG_INSTALL:-0}" != "1" ]] || exit 0

SOURCE_APP="${TARGET_BUILD_DIR:-}/${WRAPPER_NAME:-}"
DESTINATION_APP="/Applications/WLoc8.com.app"
STAGING_APP="/Applications/.WLoc8.com.app.installing"
BACKUP_APP="/Applications/.WLoc8.com.app.previous"

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "error: 未找到 Debug App：$SOURCE_APP" >&2
  exit 1
fi
if [[ ! -x "$SOURCE_APP/Contents/MacOS/WLocPrivilegedHelper" || \
      ! -f "$SOURCE_APP/Contents/Library/LaunchDaemons/com.hrtt.applocmac.helper.plist" ]]; then
  echo "error: Debug App 缺少 Privileged Helper 或 LaunchDaemon 配置" >&2
  exit 1
fi
if [[ ! -w /Applications ]]; then
  echo "error: 当前用户不能写入 /Applications，请确认使用管理员账户运行 Xcode" >&2
  exit 1
fi

/bin/rm -rf "/Applications/.WLoc8.com.app.installing"
/bin/rm -rf "/Applications/.WLoc8.com.app.previous"
/usr/bin/ditto "$SOURCE_APP" "$STAGING_APP"
/usr/bin/codesign --verify --deep --strict "$STAGING_APP"

if [[ -e "$DESTINATION_APP" ]]; then
  /bin/mv "$DESTINATION_APP" "$BACKUP_APP"
fi
if ! /bin/mv "$STAGING_APP" "$DESTINATION_APP"; then
  [[ ! -e "$BACKUP_APP" ]] || /bin/mv "$BACKUP_APP" "$DESTINATION_APP"
  exit 1
fi
/bin/rm -rf "$BACKUP_APP"

echo "已安装 Debug App：$DESTINATION_APP"
