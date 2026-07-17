import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
    private var mapController: WLocMacMapViewController?
    private var pendingURLs: [URL] = []
    private let windowSize = NSSize(width: 1180, height: 760)
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
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
        window.minSize = windowSize
        window.contentMinSize = windowSize
//        window.isReleasedWhenClosed = false
//        window.isRestorable = false
        if #available(macOS 10.12, *) {
            window.tabbingMode = .disallowed
        }
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unifiedCompact
        }

        let windowController = NSWindowController(window: window)
        self.windowController = windowController
        windowController.showWindow(nil)
        presentMainWindow(window)
    }

    private func presentMainWindow(_ window: NSWindow) {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            window.contentView?.needsLayout = true
            window.layoutIfNeeded()
            window.makeKeyAndOrderFront(nil)
        }
    }
    

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
}
