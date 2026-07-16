# Changelog

本项目使用 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) 的基本格式，版本号遵循 [Semantic Versioning](https://semver.org/)。

## [Unreleased]

### Added

- 中英文项目介绍、安装、使用和排错文档。
- 贡献指南、安全策略、行为准则和 GitHub 模板。
- 共享 Xcode Scheme。

### Changed

- 使用 Xcode 自动签名，移除与原开发者绑定的 Team 和 Provisioning Profile。
- 扩展 `.gitignore`，防止证书私钥、构建产物和个人 Xcode 数据进入仓库。

## [1.0.0] - 2026-07-16

### Added

- iOS/macOS 地图位置选择与收藏。
- Packet Tunnel 和本地 HTTPS 代理。
- 本地证书生成与下载流程。
- `wlocapp://` 外部位置导入。
