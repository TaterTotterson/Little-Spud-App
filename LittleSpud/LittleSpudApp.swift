import SwiftUI

@main
struct LittleSpudApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = LittleSpudViewModel()

    var body: some Scene {
        WindowGroup {
            LittleSpudRootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .background(AppTheme.background.ignoresSafeArea())
                .onAppear {
                    model.start()
                }
                .onReceive(NotificationCenter.default.publisher(for: .littleSpudNotificationOpened)) { _ in
                    model.resume()
                }
                .onChange(of: scenePhase) { phase in
                    if phase == .active {
                        model.resume()
                    } else if phase == .background {
                        model.pauseForegroundWork()
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LocalNotificationManager.shared.configure()
        return true
    }
}

extension Notification.Name {
    static let littleSpudNotificationOpened = Notification.Name("littleSpudNotificationOpened")
}
