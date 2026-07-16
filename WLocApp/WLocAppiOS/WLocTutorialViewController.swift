import UIKit
import SnapKit

final class WLocTutorialViewController: UIViewController {
    private let stack = UIStackView()
    private let linkLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "使用教程"
        view.backgroundColor = .white
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(close))
        buildContent()
    }

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
            make.edges.equalToSuperview().inset(18)
            make.width.equalTo(scrollView).offset(-36)
        }

        addTitle("一、安装证书")
        addStep("1. 点击下方按钮启动本机证书下载服务。")
        addStep("2. App 会跳转 Safari，通过Safari浏览器下载 \(AppWLocConfig.displayName) 根证书文件。")
        addStep("3. 到 设置 -> 通用 -> VPN与设备管理 -> 安装 HRTTOpen Root CA。")
        addStep("4. 到 设置 -> 通用 -> 关于本机 -> 证书信任设置，信任 HRTTOpen Root CA。")

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

        addTitle("二、锁定位置")
        addStep("1. 回到地图页，搜索地点或拖动地图到目标位置。")
        addStep("2. 点击“锁定位置”，系统会自动添加或启动 \(AppWLocConfig.displayName) VPN。")
        addStep("3. 进入系统定位服务，关闭后等待两秒再打开。")

        addTitle("三、恢复原始位置")
        addStep("1. 退出应用会自动断开 \(AppWLocConfig.displayName) VPN。")
        addStep("2. 再次刷新系统定位服务。如未恢复，重启设备后再试。")
    }

    private func addTitle(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.numberOfLines = 0
        stack.addArrangedSubview(label)
    }

    private func addStep(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15)
        label.textColor = .darkGray
        label.numberOfLines = 0
        stack.addArrangedSubview(label)
    }

    @objc private func startCertificateServer() {
        do {
            let url = try CertificateDownloadServer.shared.start()
//            linkLabel.text = url
            UIPasteboard.general.string = url
            if let downloadURL = URL(string: url) {
                UIApplication.shared.open(downloadURL, options: [:])
            }
        } catch {
            let alert = UIAlertController(title: "启动失败", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default))
            present(alert, animated: true)
        }
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}
