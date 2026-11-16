<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/1024.png" width="112" alt="OpenHRTT WLoc icon">
</p>

<h1 align="center">OpenHRTT WLoc</h1>

[English](README_EN.md) · [网页体验](https://wloc8.com/) · [Telegram 群](https://t.me/wloc88)

OpenHRTT WLoc 是一款用 Swift 编写的开源 iOS 和 macOS 定位工具。可以在地图上选点、锁定位置，并在用完后还原定位。

## 定位方式

- **虚拟定位**：通过 macOS 定位服务模拟所选位置。
- **WLoc**：适用于 iOS 和 macOS，通过本地 HTTPS 代理修改 `gs-loc.apple.com` 和 `gs-loc-cn.apple.com` 的响应。由于苹果封禁此方式，可能需要还原出厂设置才有使用，具体操作查看频道：https://t.me/wloc8c。

网页定位的已知兼容范围截至 iOS 27.0 beta 5。iOS 的「证书信任设置」若显示受信任资产版本为 `1014` 或 `33` 及以上版本，WLoc 方式会受限。具体操作查看频道：https://t.me/wloc8c。

## 从源码构建

```bash
git clone https://github.com/OpenHRTT/wloc.git
cd wloc
pod install
./generate_apple_wloc_p12.sh                  # iOS
./generate_apple_wloc_p12.sh --platform macos # macOS
```

按目标平台运行证书脚本，生成构建所需的 `AppWLocProxy.p12` 和 `AppWLocRootCA.cer`。输出位于 `app_wloc_certs/ios` 或 `app_wloc_certs/macos`。如果修改默认的 `.p12` 密码 `1`，同步更新 `AppWLocConfig.proxyIdentityPassword`。重新生成证书后，请重新安装 App。使用 WLoc 时还需安装并信任新根证书。

打开 `WLocApp.xcworkspace`，为各 Target 选择签名 Team，并配置 Bundle Identifier。iOS Tunnel 使用主 App 标识加 `.tunnel`。将下列文件里的 `group.com.wlocapp.shared` 统一替换为自己的 App Group。

- `Resources/iOS/WLocApp-iOS.entitlements`
- `Resources/Tunnel/WLocTunnel-iOS.entitlements`
- `WLocApp/WLocCore/AppWLocConfig.swift`

`WLocApp-macOS` 的 Debug Run 会安装并启动 `/Applications/WLoc8.com.app`，需要该目录的写权限。仅构建时可设置 `WLOC_SKIP_DEBUG_INSTALL=1` 跳过安装。

## 位置导入链接

使用 `wlocapp://<编码后的 JSON>` 或 `wlocapp://?payload=<编码后的 JSON>` 导入位置。对下方 JSON 进行 URL 百分号编码。坐标系支持 `wgs84`、`gcj02`、`bd09` 和 `apple`。

```json
{
  "type": "location",
  "data": {
    "name": "Tiananmen Square",
    "latitude": 39.9087,
    "longitude": 116.3975,
    "coordinateSystem": "wgs84"
  }
}
```

## 许可证

项目自有代码采用 [MIT 许可证](LICENSE)。第三方代码沿用各自的许可证。
