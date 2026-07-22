<h1>现急需Mac系统做兼容性测试，如你有Mac电脑，请联系：<br />开发者：https://t.me/wloc8
  <br /> 群 组：https://t.me/wloc88</h1>

<p align="center">
  <img src="Resources/Assets.xcassets/AppIcon.appiconset/1024.png" width="112" alt="OpenHRTT WLoc icon">
</p>

<h1 align="center">OpenHRTT WLoc</h1>

<p>Online access: <a href="https://wloc8.com/">https://wloc8.com/</a>. Telegram group: https://t.me/wloc88</p>

<a href="https://t.me/wloc88/132">Usage tutorial &gt;&gt;&gt;</a>

<p align="center">
  An experimental location-response research tool for iOS and macOS
</p>

<p align="center">
  <a href="README.md">中文</a> |
  <a href="CONTRIBUTING.md">Contributing</a> |
  <a href="SECURITY.md">Security</a>
</p>

## About

OpenHRTT WLoc is a fully open-source experimental iOS/macOS project written in Swift. Users can search for or select a coordinate on a map. The app stores the selected location in a shared App Group and uses a Packet Tunnel together with a narrowly scoped local HTTPS proxy to process location responses on the device.

## How it works

```mermaid
flowchart LR
    A["Select a location on the map"] --> B["Write shared state to the App Group"]
    B --> C["Packet Tunnel Extension"]
    C --> D["Local HTTPS proxy"]
    D --> E["Match only target hosts such as gs-loc.apple.com"]
    E --> F["Parse and replace location-response coordinates"]
```

The proxy currently targets only `gs-loc.apple.com` and `gs-loc-cn.apple.com`. It must not be treated as a general-purpose VPN or HTTPS interception tool.

## Requirements

- A macOS development environment.
- Xcode 16 or newer; the project has currently been checked with Xcode 26.6.
- CocoaPods 1.16 or newer.
- OpenSSL 3.x.
- An Apple Developer account with the ability to sign Network Extensions.
- A physical device for complete certificate-trust, VPN, and system-location testing.

The project declares minimum deployment targets of iOS 12.0 and macOS 10.11, but older operating systems have not undergone complete regression testing.

## Quick start

### 1. Get the code and install dependencies

```bash
git clone https://github.com/OpenHRTT/wloc.git
cd wloc
pod install
```

From this point onward, always open `WLocApp.xcworkspace` instead of `WLocApp.xcodeproj`.

### 2. Generate your own local certificates

The repository does not include any reusable root-certificate private key or `.p12` file. Every developer must generate an independent set of certificates locally:

```bash
chmod +x generate_apple_wloc_p12.sh
./generate_apple_wloc_p12.sh
```

The script generates the certificates and automatically copies them into the App and Extension resource directories. The default `.p12` password is `app-wloc`, matching `AppWLocConfig.proxyIdentityPassword`. If you change the password in the script, update the app configuration as well.

> [!IMPORTANT]
> `app_wloc_certs/`, `*.key`, `*.p12`, and the generated certificate files under `Resources` are excluded by `.gitignore`. Never force-add them with `git add -f`.

### 3. Configure signing and unique identifiers

Open `WLocApp.xcworkspace` in Xcode and select your own Team for all four targets:

- `WLocApp-iOS`
- `WLocTunnel-iOS`
- `WLocApp-macOS`
- `WLocTunnel-macOS`

Change the Bundle Identifiers, making sure that the Tunnel identifier is the app identifier followed by `.tunnel`. For example:

```text
com.example.wloc
com.example.wloc.tunnel
```

The project also uses an App Group. Replace `group.com.wlocapp.shared` consistently in the following files with your own App Group:

- `Resources/iOS/WLocApp-iOS.entitlements`
- `Resources/Tunnel/WLocTunnel-iOS.entitlements`
- `Resources/macOS/WLocApp-macOS.entitlements`
- `Resources/Tunnel/WLocTunnel-macOS.entitlements`
- `WLocApp/WLocCore/AppWLocConfig.swift`

Under Signing & Capabilities, confirm that App Groups and Network Extensions are correctly enabled.


## External links （TODO）

The app supports importing locations through `wlocapp://`. The payload is URL-encoded JSON:

```json
{
  "type": "location",
  "data": {
    "name": "Tiananmen Square",
    "detail": "Beijing",
    "latitude": 39.9087,
    "longitude": 116.3975,
    "coordinateSystem": "wgs84"
  }
}
```

Supported `coordinateSystem` values are `wgs84`, `gcj02`, `bd09`, and `apple`. A complete URL can use either of these formats:

```text
wlocapp://<percent-encoded-json>
wlocapp://?payload=<percent-encoded-json>
```

## FAQ

**The build cannot find `AppWLocProxy.p12` or `AppWLocRootCA.cer`. What should I do?**

Run `./generate_apple_wloc_p12.sh` from the repository root.

**Signing or App Group configuration fails. What should I check?**

Make sure all four targets use your Team, every Bundle Identifier is unique, and the App and Tunnel use the same App Group.

**Lock Location does not take effect. What should I check?**

Confirm that the root certificate is installed and fully trusted, the VPN is connected, and the Tunnel Bundle Identifier matches the main app. Then refresh Location Services as instructed by the app.

For more diagnostic steps, see [Troubleshooting](docs/TROUBLESHOOTING.md).

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) first.

## Third-party dependencies

The project uses SwiftProtobuf, SnapKit, IQKeyboardManagerSwift, GCDWebServer, and the bundled LiquidGlassKit. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for versions, sources, and license information.

## License

Project-owned code is available under the [MIT License](LICENSE). Third-party code is not covered by the project's MIT License; see [NOTICE](NOTICE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for details.
