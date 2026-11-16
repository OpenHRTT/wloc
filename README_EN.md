<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/1024.png" width="112" alt="OpenHRTT WLoc icon">
</p>

<h1 align="center">OpenHRTT WLoc</h1>

[中文](README.md) · [Try it online](https://wloc8.com/) · [Telegram group](https://t.me/wloc88)

OpenHRTT WLoc is an open-source location tool for iOS and macOS, written in Swift. Pick a point on the map, lock the location, and restore it when you're done.

## Location modes

- **Simulated Location** uses macOS Location Services to simulate the selected location. Turn on Location Services, select **Simulated Location** (虚拟定位), pick a point, and click **Lock Location** (锁定位置). The first use requires administrator authorization. When finished, click **Restore Location** (还原定位). The app refreshes Location Services when locking or restoring, so you can request your current location again in Apple Maps or the target app.
- **WLoc** uses a local HTTPS proxy on iOS and macOS to modify responses from `gs-loc.apple.com` and `gs-loc-cn.apple.com`. Install the local root certificate and enable full trust. Then make sure the iOS VPN (Packet Tunnel) is connected or macOS Automatic Proxy Configuration (PAC) is enabled.

The web version is known to work through iOS 27.0 beta 5. WLoc mode is limited on iOS devices that show Trusted Asset Version `1014` or `33` under Certificate Trust Settings. The project provides an [iOS DNS configuration profile](Resources/iOS/wloc-dns-ios.mobileconfig) that blocks the relevant update domains.

## Build from source

```bash
git clone https://github.com/OpenHRTT/wloc.git
cd wloc
pod install
./generate_apple_wloc_p12.sh                  # iOS
./generate_apple_wloc_p12.sh --platform macos # macOS
```

Run the certificate script for your target platform to generate `AppWLocProxy.p12` and `AppWLocRootCA.cer` for the build. The output goes to `app_wloc_certs/ios` or `app_wloc_certs/macos`. If you change the default `.p12` password of `1`, update `AppWLocConfig.proxyIdentityPassword` as well. After regenerating the certificates, reinstall the app. To use WLoc mode, also install and trust the new root certificate.

Open `WLocApp.xcworkspace`, choose a signing team for each target, and configure the bundle identifiers. The iOS Tunnel identifier is the main app identifier plus `.tunnel`. Replace `group.com.wlocapp.shared` with your own App Group in these files.

- `Resources/iOS/WLocApp-iOS.entitlements`
- `Resources/Tunnel/WLocTunnel-iOS.entitlements`
- `WLocApp/WLocCore/AppWLocConfig.swift`

A Debug Run with the `WLocApp-macOS` scheme installs and launches `/Applications/WLoc8.com.app` and requires write access to that directory. For a build-only run, set `WLOC_SKIP_DEBUG_INSTALL=1` to skip installation.

## Location import links

Import a location with `wlocapp://<encoded JSON>` or `wlocapp://?payload=<encoded JSON>`. Percent-encode the JSON below for use in the URL. Supported coordinate systems are `wgs84`, `gcj02`, `bd09`, and `apple`.

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

## License

Project-owned code uses the [MIT License](LICENSE). Third-party code retains its own licenses.
