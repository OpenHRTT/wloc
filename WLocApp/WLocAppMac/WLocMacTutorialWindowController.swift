import AppKit
import SnapKit

private final class WLocMacTutorialDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class WLocMacTutorialWindowController: NSWindowController {
    init() {
        let controller = WLocMacTutorialViewController()
        let window = NSWindow(contentViewController: controller)
        window.title = "\(AppWLocConfig.displayName) 教程"
        window.setContentSize(NSSize(width: 560, height: 620))
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }
}

final class WLocMacTutorialViewController: NSViewController {
    private let stack = NSStackView()
    private let linkField = NSTextField.wlocLabel("")

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildContent()
    }

    private func buildContent() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        let container = WLocMacTutorialDocumentView()
        scrollView.documentView = container
        container.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(scrollView.contentView)
        }

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        container.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
        }

        addTitle("一、先安装 DNS 配置")
        addStep("1. 点击“下载 DNS 配置”，打开下载的描述文件。")
        addDownloadButton("下载 DNS 配置", action: #selector(downloadDNSProfile))
        addStep("2. 打开“系统设置 → 通用 → 设备管理”，双击“\(AppWLocConfig.dnsProfileName)”并安装。也可在系统设置中搜索“描述文件”。")
        addStep("此配置用于屏蔽所列 Apple 更新域名。需要检查系统更新时，可先在系统设置中移除该描述文件。")

        addTitle("二、下载、安装并信任根证书")
        addStep("1. 安装 DNS 配置后，点击“下载证书”，下载 \(AppWLocConfig.displayName) 根证书文件。")
        addDownloadButton("下载证书", action: #selector(startCertificateServer))

        addStep("2. 下载完成后，请打开“钥匙串访问”，在左侧选择“系统”钥匙串，再从菜单栏选择“文件”→“导入项目…”，导入下载的证书。请勿双击证书直接安装，以免被导入到错误的钥匙串。")
        addStep("3. 在“系统”钥匙串中找到“WLoc8.com Root CA”，打开证书的“信任”设置，并选择“始终信任”。")

        linkField.font = NSFont(name: "Menlo", size: 12) ?? .systemFont(ofSize: 12)
        linkField.textColor = .secondaryLabelColor
        linkField.lineBreakMode = .byCharWrapping
        linkField.cell?.wraps = true
        linkField.cell?.isScrollable = false
        linkField.maximumNumberOfLines = 3
        linkField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        linkField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(linkField)
        linkField.snp.makeConstraints { make in
            make.width.equalTo(stack)
        }

        addTitle("三、锁定位置")
        addStep("1. 在主界面搜索地点，或拖动地图到目标位置。")
        addStep("2. 点击“锁定位置”，应用会启用本地定位代理，并配置系统 PAC。")
        addStep("如需设置海拔、水平精度和垂直精度，点击“高级锁定”；“查询海拔”可填入当前选点的海拔，也可手动修改。")
        addStep("3. 打开系统定位服务，关闭后等待两秒再打开。")

        let line = NSView()
        stack.addArrangedSubview(line)
        line.snp.makeConstraints { make in
            make.height.equalTo(10)
        }

        addTitle("四、恢复原始位置")
        addStep("1. 点击主界面的“还原定位”恢复原代理设置；若提示失败，请点击“重试恢复”。退出应用也会尝试恢复。如连接了 VPN，请先关闭。")
        addStep("2. 再次关开定位服务。如未恢复，重启电脑后再试。")

        addTitle("五、检查更新")
        addStep("点击版本旁的“检查更新”或应用菜单中的“检查更新…”。发现新版后点击“下载并安装”，应用会显示下载进度，安装完成后自动重启。应用目录不可写时，系统会请求管理员授权。")
    }

    private func addTitle(_ text: String) {
        let label = NSTextField.wlocLabel(text)
        label.font = .systemFont(ofSize: 20, weight: .bold)
        stack.addArrangedSubview(label)
    }

    private func addStep(_ text: String) {
        let label = NSTextField.wlocWrappingLabel(text)
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(label)
        label.snp.makeConstraints { make in
            make.width.equalTo(stack)
        }
    }

    private func addDownloadButton(_ title: String, action: Selector) {
        let button = NSButton.wlocButton(title)
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .regular
        stack.addArrangedSubview(button)
    }

    @objc private func downloadDNSProfile() {
        openBrowserDownload(CertificateDownloadServer.shared.startDNSProfile)
    }

    @objc private func startCertificateServer() {
        openBrowserDownload(CertificateDownloadServer.shared.start)
    }

    /// 两个下载入口共用本机服务和浏览器打开流程。
    private func openBrowserDownload(_ start: () throws -> String) {
        do {
            let url = try start()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
            guard let downloadURL = URL(string: url), NSWorkspace.shared.open(downloadURL) else {
                throw URLError(.unsupportedURL)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法下载文件"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好")
            alert.beginSheetModal(for: view.window ?? NSWindow()) { _ in }
        }
    }
}
