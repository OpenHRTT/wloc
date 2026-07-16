# 贡献指南

感谢你愿意改进 OpenHRTT WLoc。请将变更保持小而清晰，并优先保护使用者的设备、证书和位置数据。

## 开始之前

1. 搜索现有 Issue，避免重复工作。
2. 大功能、协议变更或安全边界变更请先建 Issue 讨论。
3. 安全漏洞不要发公开 Issue，请按 `SECURITY.md` 报告。

## 本地开发

```bash
pod install
./generate_apple_wloc_p12.sh
open WLocApp.xcworkspace
```

请使用你自己的 Team、Bundle Identifier、App Group 和本地证书。请勿提交：

- `*.key`、`*.p12`、`*.pfx`、`*.mobileprovision`。
- `app_wloc_certs/` 下的生成产物。
- Xcode `xcuserdata` 和个人断点。
- 真实位置数据、账号、证书或签名凭据。

## 代码要求

- 优先沿用当前 Swift/UIKit/AppKit 结构。
- 新增代理域名或放宽拦截范围必须在 PR 中说明安全原因。
- 不得将根证书私钥、通用代理能力或隐蔽远程控制引入项目。
- 只在逻辑不容易自解释时添加简短注释。
- 界面变更需同时检查小屏幕、深色内容可读性和文本截断。

## 提交 Pull Request

PR 请包含：

- 问题背景和实际行为变化。
- 测试环境（Xcode、iOS/macOS 版本和设备）。
- 已执行的验证命令或手工验证步骤。
- UI 变更的截图或录屏。
- 与证书、VPN、代理范围或用户数据有关的风险评估。

提交贡献即表示你有权提交该代码，并同意贡献内容按项目 MIT License 发布。
