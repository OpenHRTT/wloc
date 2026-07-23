# 排错指南

## CocoaPods 依赖错误

**现象：** `No such module 'SnapKit'`、`SwiftProtobuf` 或 `GCDWebServer` 找不到。

```bash
pod install
open WLocApp.xcworkspace
```

不要使用 `WLocApp.xcodeproj` 进行日常构建。

## 证书资源缺失

**现象：** Build Phases 提示 `AppWLocRootCA.cer` 或 `AppWLocProxy.p12` 不存在。

```bash
./generate_apple_wloc_p12.sh
```

运行后应当在 `Resources/iOS`、`Resources/macOS` 和 `Resources/Tunnel` 看到本地生成文件。它们被 Git 忽略是预期行为。

## `SecPKCS12Import` 失败

**现象：** Tunnel 日志出现 `errSecAuthFailed (-25293)` 或无法解析 `.p12`。

- 确认使用仓库脚本生成，脚本已为 OpenSSL 3 启用 legacy PBE/MAC。
- 确认脚本密码与 `AppWLocConfig.proxyIdentityPassword` 完全一致。
- 删除旧产物后重新生成，不要从其他开发者复制 `.p12`。

## 签名或 Provisioning Profile 错误

- 为四个 Target 选择同一个有效 Team。
- 开启 Automatically manage signing。
- 确认 App 和 Tunnel 的 Bundle Identifier 在你的账号下唯一。
- 确认 Tunnel Identifier 等于主 App Identifier 加 `.tunnel`。
- 确认 App Groups 和 Network Extensions 能力已开启。

## VPN 创建成功但启动失败

- 确认 `AppWLocConfig.tunnelProviderBundleIdentifier` 返回的标识与 Tunnel Target 一致。
- 在系统 VPN 设置中删除以前的测试配置，然后重新运行 App。
- 查看主 App 和 Packet Tunnel Extension 的设备日志。
- 确认 App Group 两端一致，否则 Extension 无法读取锁定坐标。

## macOS 提示 Privileged Helper 未启用

- 将完整的 `WLoc8.com.app` 放到 `/Applications`，不要只复制内部可执行文件。
- 首次锁定后，在“系统设置 > 通用 > 登录项与扩展”中允许 WLoc8.com 后台项目，再回到 App 重试。
- 确认 `WLocApp-macOS` 与 `WLocPrivilegedHelper` 使用同一个 Team，并且签名要求与实际 Bundle Identifier、Team ID 一致。
- 更新 App 后若 Helper 无法连接，退出旧版本，重新安装并启动新版本。

## 根证书已安装但代理仍失败

- iOS 安装描述文件后，还必须在“证书信任设置”中手动完全信任。
- macOS 需要在钥匙串中为当前生成的根证书设置信任。
- 重新生成证书后，旧根证书与新 `.p12` 不匹配，需删除旧证书并重新安装。

## 位置未更新

- 确认地图上已选择位置，并显示有效经纬度。
- 确认 VPN 处于已连接状态。
- 按 App 内教程刷新系统定位服务。
- 某些系统版本、设备型号或网络环境可能与当前实现不兼容。

## 恢复原始状态

1. 退出 App 并在系统中断开 WLoc VPN。
2. 重新刷新定位服务。
3. 不再测试时，删除 VPN 配置和受信任根证书。
4. 仍有异常时重启设备。

macOS 若 App 异常退出后 PAC 未恢复，重新打开 App 并再次锁定、解锁；应用会先恢复上次保存的 PAC 设置。
