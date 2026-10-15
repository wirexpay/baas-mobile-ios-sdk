import UIKit

/// Scene-based, and that is not incidental to this example.
///
/// `UIScreen.main` is deprecated in favour of the window's own scene, and this SDK is the reason to
/// care: its capture gate asks which screen the ROW is on, because `isCaptured` is per-screen. A host
/// that builds its window from `UIScreen.main` is one step from reasoning about the wrong screen
/// everywhere else — on an external display, in Stage Manager, on CarPlay — and the gate is the one
/// place that has to be right. An example integrators copy should model the arrangement the SDK
/// assumes.
///
/// The scene manifest lives in `Info.plist`; this delegate only points at the configuration.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    }
}

/// Builds the window FROM ITS SCENE, which is the whole point of the file above.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Six tabs, the same set and order every platform's example carries. Config is first: a
        // per-field editor over `LiveConfig`, the single store the surfaces read. Reveal DISPLAYS a
        // card the user owns; collect CAPTURES one they type; they share credentials and appearance
        // through `LiveConfig`, and nothing else — the two SDKs are peers and neither imports the other.
        let config = ConfigViewController()
        config.tabBarItem = UITabBarItem(title: "Config", image: nil, tag: 0)
        let reveal = RevealViewController()
        reveal.tabBarItem = UITabBarItem(title: "Reveal", image: nil, tag: 1)
        let collect = CollectViewController()
        collect.tabBarItem = UITabBarItem(title: "Collect", image: nil, tag: 2)
        let threeDS = ThreeDSViewController()
        threeDS.tabBarItem = UITabBarItem(title: "3DS", image: nil, tag: 3)
        // Wallet top-up (Apple Pay / Google Pay). Part of the same SDK — resolves its own environment
        // from the one name this example is built for.
        let wallet = WalletViewController()
        wallet.tabBarItem = UITabBarItem(title: "Wallet", image: nil, tag: 4)
        // Styling is its own tab because it applies to every surface.
        let appearance = AppearanceViewController()
        appearance.tabBarItem = UITabBarItem(title: "Appearance", image: nil, tag: 5)

        let tabs = UITabBarController()
        tabs.viewControllers = [config, reveal, collect, threeDS, wallet, appearance]
        // `-wirexScreen collect` opens straight onto the entry screen, so a scripted run does not
        // have to synthesise a tap on the tab bar.
        switch LaunchArgs.screen {
        case "config": tabs.selectedIndex = 0
        case "reveal": tabs.selectedIndex = 1
        case "collect": tabs.selectedIndex = 2
        case "threeds": tabs.selectedIndex = 3
        case "wallet": tabs.selectedIndex = 4
        case "appearance": tabs.selectedIndex = 5
        default: break
        }

        // FROM THE SCENE, not from `UIScreen.main`. The window then knows which screen it is on, and
        // so does every SDK row inside it.
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        self.window = window
    }
}
