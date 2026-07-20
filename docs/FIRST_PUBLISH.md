# 首次发布到 GitHub

这份清单适合第一次使用 Git 和 GitHub 的维护者。在执行之前，请先确认项目可以在本机构建。

## 1. 发布前检查

在项目根目录运行：

```bash
find . -type f \( -name '*.key' -o -name '*.p12' -o -name '*.pfx' -o -name '*.mobileprovision' \) -print
```

找到本地文件是正常的，但它们必须被 `.gitignore` 排除。

## 2. 初始化 Git 仓库

当前目录如果还不是 Git 仓库，执行：

```bash
git init
git branch -M main
git check-ignore -v app_wloc_certs/AppWLocRootCA.key
git check-ignore -v Resources/Tunnel/AppWLocProxy.p12
git check-ignore -v WLocApp.xcodeproj/xcuserdata/admin.xcuserdatad/UserInterfaceState.xcuserstate
git add .
git status
```

三条 `git check-ignore` 命令都应输出命中的 `.gitignore` 规则。如果其中一条没有输出，先不要执行 `git add .`。

仔细检查 `git status`：

- 应当看到 `README.md`、`LICENSE`、源码、工程文件和 GitHub 模板。
- 不应当看到 `Pods/`、`xcuserdata/`、`app_wloc_certs/`、`*.key` 或 `*.p12`。

如果清单正确，创建首次提交：

```bash
git commit -m "Initial open source release"
```

## 3. 在 GitHub 创建空仓库

1. 登录 GitHub，点击右上角 `+` -> `New repository`。
2. Repository name 建议使用 `WLocApp` 或 `WLoc8`。
3. Description 可填：`Experimental iOS/macOS location response research tool built with Swift and Network Extension.`
4. 选择 `Public`。
5. **不要**勾选自动创建 README、`.gitignore` 或 License，因为本地已经有这些文件。
6. 点击 `Create repository`。

## 4. 连接 GitHub 并推送

将下方地址替换为你的 GitHub 用户名和仓库名：

```bash
git remote add origin https://github.com/<username>/<repository>.git
git push -u origin main
```

如果 GitHub 要求登录，HTTPS 不再接受账号密码，请使用 GitHub Desktop、SSH，或 Personal Access Token。

## 5. GitHub 页面设置

推送成功后，建议在仓库页面完成：

1. 在 `About` 中添加描述和 Topics：`ios`、`macos`、`swift`、`network-extension`、`mapkit`、`research`。
2. 在 `Settings -> General -> Features` 开启 Issues。
3. 在 `Settings -> Code security and analysis` 开启 Private vulnerability reporting。
4. 在 `Settings -> Branches` 为 `main` 添加保护规则，至少要求 PR 后才合并。
5. 在 `Releases` 创建 `v1.0.0`，发布说明可参考 `CHANGELOG.md`。

## 6. 最后复查

在 GitHub 网页上搜索以下文件名，确认没有结果：

```text
AppWLocRootCA.key
AppWLocProxy.key
AppWLocProxy.p12
*.mobileprovision
```

再用一个新目录重新 clone 仓库，按 README 执行 `pod install` 和证书生成，确认文档没有遗漏本机隐藏步骤。

## 重要提醒

一旦私钥进入首次提交，后续“删除文件”也不会将它从 Git 历史中消除。发现误提交时，请先停止推送；如已推送，立即替换证书，并使用 `git filter-repo` 或 GitHub 官方流程清理历史。
