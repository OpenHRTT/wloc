import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
    private var mapController: WLocMacMapViewController?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = WLocMacMapViewController()
        mapController = controller
        let window = NSWindow(contentViewController: controller)
        window.title = AppWLocConfig.displayName
        window.setContentSize(NSSize(width: 1120, height: 760))
        window.minSize = NSSize(width: 920, height: 620)
        window.center()

        let windowController = NSWindowController(window: window)
        windowController.showWindow(nil)
        self.windowController = windowController
        NSApp.activate(ignoringOtherApps: true)

        pendingURLs.forEach { controller.handleDeepLink($0) }
        pendingURLs.removeAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
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
