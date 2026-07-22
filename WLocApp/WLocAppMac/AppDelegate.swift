import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
    private var mapController: WLocMacMapViewController?
    private var pendingURLs: [URL] = []
    private let windowSize = NSSize(width: 1180, height: 760)
    private let minimumWindowSize = NSSize(width: 900, height: 620)
    private let windowFrameName = "WLoc8.com.mainWindow"
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        configureMainMenu()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {

        NSApp.setActivationPolicy(.regular)
        showMainWindow()

        if let controller = mapController {
            pendingURLs.forEach { controller.handleDeepLink($0) }
            pendingURLs.removeAll()
        }
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        
        return .terminateNow
    }
    

    private func showMainWindow() {
        if let windowController {
            if let window = windowController.window {
                presentMainWindow(window)
            }
            return
        }
        let windowRect = NSRect(origin: .zero, size: windowSize)
        let controller = WLocMacMapViewController()
        mapController = controller
        controller.preferredContentSize = windowSize
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.title = AppWLocConfig.displayName
        window.titleVisibility = .hidden
        window.minSize = minimumWindowSize
        window.contentMinSize = minimumWindowSize
        window.setFrameAutosaveName(windowFrameName)
        window.tabbingMode = .disallowed
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unifiedCompact
        }

        let windowController = NSWindowController(window: window)
        self.windowController = windowController
        windowController.showWindow(nil)
        if !window.setFrameUsingName(windowFrameName) {
            window.center()
        }
        presentMainWindow(window)
    }

    private func presentMainWindow(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            window.contentView?.needsLayout = true
            window.layoutIfNeeded()
            window.makeKeyAndOrderFront(nil)
        }
    }
    

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
    
    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        false
    }
    
    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let mapController else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        urls.forEach { mapController.handleDeepLink($0) }
    }

    func applicationWillTerminate(_ notification: Notification) {
        mapController?.disconnectVPNForAppTermination()
    }

    @objc private func showAboutPanel() {
        if #available(macOS 10.13, *) {
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: AppWLocConfig.displayName,
                .applicationVersion: AppWLocConfig.currentVersion,
                .credits: NSAttributedString(string: "在地图上选择并锁定测试位置。\nGitHub 开源项目与版本更新")
            ])
        } else {
            NSApp.orderFrontStandardAboutPanel(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func checkForUpdates() {
        showMainWindow()
        mapController?.checkForUpdates(userInitiated: true)
    }

    @objc private func showTutorial() {
        showMainWindow()
        mapController?.openTutorial()
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(AppWLocConfig.githubRepositoryURL)
    }

    @objc private func openTelegram() {
        NSWorkspace.shared.open(URL(string: "https://t.me/wloc88")!)
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu(title: "MainMenu")
        NSApp.mainMenu = mainMenu

        let appMenuItem = NSMenuItem(title: AppWLocConfig.displayName, action: nil, keyEquivalent: "")
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: AppWLocConfig.displayName)
        appMenuItem.submenu = appMenu
        appMenu.addItem(menuItem("关于 \(AppWLocConfig.displayName)", action: #selector(showAboutPanel)))
        appMenu.addItem(menuItem("检查更新…", action: #selector(checkForUpdates)))
        appMenu.addItem(.separator())
        let servicesItem = NSMenuItem(title: "服务", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "服务")
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(servicesItem)
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("隐藏 \(AppWLocConfig.displayName)", action: #selector(NSApplication.hide(_:)), key: "h", target: NSApp))
        let hideOthers = menuItem("隐藏其他应用", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", target: NSApp)
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(menuItem("全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), target: NSApp))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("退出 \(AppWLocConfig.displayName)", action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))

        let fileMenu = addMenu("文件", to: mainMenu)
        fileMenu.addItem(responderMenuItem("关闭窗口", action: #selector(NSWindow.performClose(_:)), key: "w"))

        let editMenu = addMenu("编辑", to: mainMenu)
        editMenu.addItem(responderMenuItem("撤销", action: Selector(("undo:")), key: "z"))
        let redo = responderMenuItem("重做", action: Selector(("redo:")), key: "Z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(responderMenuItem("剪切", action: #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(responderMenuItem("复制", action: #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(responderMenuItem("粘贴", action: #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(responderMenuItem("全选", action: #selector(NSText.selectAll(_:)), key: "a"))

        let viewMenu = addMenu("显示", to: mainMenu)
        let fullScreen = responderMenuItem("进入全屏幕", action: #selector(NSWindow.toggleFullScreen(_:)), key: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullScreen)

        let windowMenu = addMenu("窗口", to: mainMenu)
        windowMenu.addItem(responderMenuItem("最小化", action: #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        windowMenu.addItem(responderMenuItem("缩放", action: #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(menuItem("前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), target: NSApp))
        NSApp.windowsMenu = windowMenu

        let helpMenu = addMenu("帮助", to: mainMenu)
        helpMenu.addItem(menuItem("教程与证书", action: #selector(showTutorial)))
        helpMenu.addItem(.separator())
        helpMenu.addItem(menuItem("在 GitHub 上查看", action: #selector(openGitHub)))
        helpMenu.addItem(menuItem("加入 Telegram", action: #selector(openTelegram)))
        NSApp.helpMenu = helpMenu
    }

    private func addMenu(_ title: String, to mainMenu: NSMenu) -> NSMenu {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        mainMenu.addItem(item)
        return menu
    }

    private func menuItem(
        _ title: String,
        action: Selector?,
        key: String = "",
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? self
        return item
    }

    private func responderMenuItem(_ title: String, action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = nil
        return item
    }
}
