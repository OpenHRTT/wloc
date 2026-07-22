import AppKit
import SnapKit

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
            make.edges.width.equalToSuperview()
        }

        let container = NSView()
        scrollView.documentView = container
        container.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
        }


        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        container.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(20)
            make.width.equalTo(scrollView).offset(-40)
        }

        addTitle("一、安装证书")
        addStep("1. 点击”下载证书“按钮，下载 \(AppWLocConfig.displayName) 根证书文件。")

        let button = NSButton.wlocButton("下载证书")
        button.target = self
        button.action = #selector(startCertificateServer)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        stack.addArrangedSubview(button)

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

        addTitle("二、锁定位置")
        addStep("1. 在主界面搜索地点，或拖动地图到目标位置。")
        addStep("2. 点击“锁定位置”，系统会自动添加或启动 \(AppWLocConfig.displayName) VPN。")
        addStep("3. 打开系统定位服务，关闭后等待两秒再打开。")

        let line = NSView()
        stack.addArrangedSubview(line)
        line.snp.makeConstraints { make in
            make.height.equalTo(10)
        }

        addTitle("三、恢复原始位置")
        addStep("1. 退出应用会自动断开 \(AppWLocConfig.displayName) VPN。")
        addStep("2. 再次刷新定位服务。如未恢复，重启电脑后再试。")
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

    @objc private func startCertificateServer() {
        do {
            let url = try CertificateDownloadServer.shared.start()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
            if let downloadURL = URL(string: url) {
                NSWorkspace.shared.open(downloadURL)
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "启动失败"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "好")
            alert.beginSheetModal(for: view.window ?? NSWindow()) { _ in }
        }
    }
}
