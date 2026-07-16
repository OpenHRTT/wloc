import IQKeyboardManagerSwift
import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        IQKeyboardManager.shared.enable = true

        let window = UIWindow(frame: UIScreen.main.bounds)
        let controller = WLocMapViewController()
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
