import UIKit
import SnapKit

final class WLocTutorialViewController: UIViewController {
    private let stack = UIStackView()
    private let linkLabel = UILabel()
    private var downloadBackgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// 安装说明放在教程最前面，下载文件后仍由用户在系统设置中安装。
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "使用教程"
        view.backgroundColor = .white
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        buildContent()
        NotificationCenter.default.addObserver(self, selector: #selector(finishDownloadBackgroundTask),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if downloadBackgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(downloadBackgroundTask)
        }
    }

    /// 长文案可以滚动，DNS 提示和下载按钮优先展示。
    private func buildContent() {
        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        stack.axis = .vertical
        stack.spacing = 14
        scrollView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalTo(scrollView.contentLayoutGuide).inset(18)
            make.width.equalTo(scrollView.frameLayoutGuide).offset(-36)
        }

        addDNSNotice()
        addTitle("二、下载、安装并信任根证书")
        addStep("完成上方 DNS 配置后，再下载根证书。")
        addStep("1. 点击“下载证书”，在浏览器中允许下载 WLoc8.com iOS App Root CA。")
        addStep("2. 前往“设置 → 通用 → VPN 与设备管理”，安装 WLoc8.com iOS App Root CA。")
        addStep("3. 前往“设置 → 通用 → 关于本机 → 证书信任设置”，为 WLoc8.com iOS App Root CA 启用完全信任。")

        let button = UIButton(type: .system)
        button.setTitle("下载证书", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.backgroundColor = UIColor(red: 0.05, green: 0.32, blue: 0.82, alpha: 1.0)
        button.tintColor = .white
        button.layer.cornerRadius = 10
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        button.addTarget(self, action: #selector(startCertificateServer), for: .touchUpInside)
        stack.addArrangedSubview(button)

        linkLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        linkLabel.textColor = .darkGray
        linkLabel.numberOfLines = 0
        stack.addArrangedSubview(linkLabel)

        addTitle("三、锁定位置")
        addStep("1. 回到地图页，搜索地点或拖动地图到目标位置。")
        addStep("2. 点击“锁定位置”，系统会自动添加或启动 \(AppWLocConfig.displayName) VPN。")
        addStep("如需设置海拔、水平精度和垂直精度，点击锁定按钮右侧的滑杆图标（高级锁定）；“查询海拔”可填入当前选点的海拔，也可手动修改。")
        addStep("3. 进入系统定位服务，关闭后等待两秒再打开。")

        addTitle("四、恢复原始位置")
        addStep("1. 点击锁定按钮右侧的回转箭头图标（还原定位）查看操作指引，先关闭 VPN。")
        addStep("2. 再次关开系统定位服务。如未恢复，重启设备后再试。")
    }

    /// 在根证书下载入口前引导用户安装并启用 DNS 配置。
    private func addDNSNotice() {
        let card = UIView()
        card.backgroundColor = UIColor(red: 1, green: 0.96, blue: 0.89, alpha: 1)
        card.layer.cornerRadius = 16
        card.layer.borderWidth = 1.5
        card.layer.borderColor = UIColor(red: 0.85, green: 0.29, blue: 0.04, alpha: 1).cgColor

        let button = UIButton(type: .system)
        button.setTitle("下载 DNS 配置", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        button.backgroundColor = UIColor(red: 0.85, green: 0.29, blue: 0.04, alpha: 1)
        button.tintColor = .white
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 14, left: 16, bottom: 14, right: 16)
        button.accessibilityHint = "在浏览器中下载 DNS 描述文件，随后前往系统设置安装"
        button.addTarget(self, action: #selector(downloadDNSProfile), for: .touchUpInside)

        let notice = UIStackView(arrangedSubviews: [
            textLabel("一、先安装并启用 DNS 配置", font: .systemFont(ofSize: 21, weight: .bold), color: UIColor(red: 0.65, green: 0.19, blue: 0.02, alpha: 1)),
            textLabel("系统可能在后台静默更新证书库，影响 WLoc 定位。"),
            textLabel("版本提醒：受信任资产版本为 1014 或更高时，WLoc 方式可能无法使用。", font: .systemFont(ofSize: 16, weight: .bold)),
            textLabel("查看路径：设置 → 通用 → 关于本机 → 证书信任设置。"),
            button,
            textLabel("1. 点击按钮，在浏览器中允许下载。然后前往「设置 → 通用 → VPN 与设备管理」，安装“\(AppWLocConfig.dnsProfileName)”。"),
            textLabel("2. 安装后断开 Wi-Fi 和蜂窝数据，在「设置 → 通用 → VPN 与设备管理 → DNS」中选中："),
            textLabel(AppWLocConfig.dnsProfileName, font: .systemFont(ofSize: 17, weight: .bold), color: .black),
            textLabel("3. 确认选中后恢复联网，回到本页下载根证书。"),
            textLabel("此配置用于屏蔽所列 Apple 更新域名，降低后续静默更新风险；不会回退已更新的证书库，也不保证恢复已失效的定位功能。", font: .systemFont(ofSize: 13))
        ])
        notice.axis = .vertical
        notice.spacing = 12
        card.addSubview(notice)
        notice.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
        }
        stack.addArrangedSubview(card)
    }

    /// 提示和教程共用多行标签，窄屏也能完整阅读步骤。
    private func textLabel(_ text: String, font: UIFont = .systemFont(ofSize: 15), color: UIColor = .darkGray) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    /// 添加教程分节标题。
    private func addTitle(_ text: String) {
        stack.addArrangedSubview(textLabel(text, font: .systemFont(ofSize: 20, weight: .bold), color: .black))
    }

    /// 添加教程操作步骤。
    private func addStep(_ text: String) {
        stack.addArrangedSubview(textLabel(text))
    }

    /// DNS 和根证书共用浏览器下载流程。
    @objc private func downloadDNSProfile() {
        openBrowserDownload(CertificateDownloadServer.shared.startDNSProfile)
    }

    /// 保留原来的根证书下载入口。
    @objc private func startCertificateServer() {
        openBrowserDownload(CertificateDownloadServer.shared.start)
    }

    /// 切到浏览器时短暂保活本机服务，返回 App 后结束后台任务。
    private func openBrowserDownload(_ start: () throws -> String) {
        do {
            finishDownloadBackgroundTask()
            let url = try start()
            guard let downloadURL = URL(string: url) else { throw URLError(.badURL) }
            downloadBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "WLocProfileDownload") { [weak self] in
                self?.finishDownloadBackgroundTask()
            }
            UIApplication.shared.open(downloadURL, options: [:]) { [weak self] opened in
                guard !opened, let self else { return }
                self.finishDownloadBackgroundTask()
                self.showDownloadError(URLError(.unsupportedURL))
            }
        } catch {
            finishDownloadBackgroundTask()
            showDownloadError(error)
        }
    }

    /// 返回前台或后台时间用完后，释放下载保活任务。
    @objc private func finishDownloadBackgroundTask() {
        guard downloadBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(downloadBackgroundTask)
        downloadBackgroundTask = .invalid
    }

    /// 浏览器未打开时明确提示，避免把点击按钮当成下载成功。
    private func showDownloadError(_ error: Error) {
        let alert = UIAlertController(title: "无法下载文件", message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    /// 只关闭说明页，不检测或限制 App 使用。
    @objc private func close() {
        dismiss(animated: true)
    }
}
