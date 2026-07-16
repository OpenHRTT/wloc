import IQKeyboardManagerSwift
import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private weak var mapController: WLocMapViewController?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        IQKeyboardManager.shared.enable = true

        let window = UIWindow(frame: UIScreen.main.bounds)
        let controller = WLocMapViewController()
        mapController = controller
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
        self.window = window

        if let url = launchOptions?[.url] as? URL {
            controller.handleDeepLink(url)
        }
        return true
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        mapController?.handleDeepLink(url) ?? false
    }

    func applicationWillTerminate(_ application: UIApplication) {
        mapController?.disconnectVPNForAppTermination()
    }
}
