import FirebaseCore
import FirebaseMessaging
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
                    model.showNotificationLane()
                    model.resume()
                }
                .onReceive(NotificationCenter.default.publisher(for: .littleSpudRemotePushReceived)) { _ in
                    model.resume()
                }
                .onReceive(NotificationCenter.default.publisher(for: .littleSpudRemotePushTokenUpdated)) { event in
                    if let token = event.object as? String {
                        model.handleRemotePushToken(token)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .littleSpudRemotePushRegistrationFailed)) { event in
                    model.handleRemotePushRegistrationFailure(event.object as? String)
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

final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LocalNotificationManager.shared.configure()
        configureFirebaseMessaging()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard FirebaseApp.app() != nil else { return }
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().isAutoInitEnabled = true
        Messaging.messaging().token { token, error in
            if let token {
                Self.postRemotePushToken(token)
            } else if let error {
                Self.postRemotePushRegistrationFailure(error.localizedDescription)
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .littleSpudRemotePushRegistrationFailed, object: error.localizedDescription)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .littleSpudRemotePushReceived, object: userInfo)
            completionHandler(.noData)
        }
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Self.postRemotePushToken(fcmToken)
    }

    private func configureFirebaseMessaging() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            print("Little Spud Firebase is not configured. Add GoogleService-Info.plist to enable FCM push.")
            return
        }
        FirebaseApp.configure()
        Messaging.messaging().delegate = self
    }

    private static func postRemotePushToken(_ token: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .littleSpudRemotePushTokenUpdated, object: token)
        }
    }

    private static func postRemotePushRegistrationFailure(_ message: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .littleSpudRemotePushRegistrationFailed, object: message)
        }
    }
}

extension Notification.Name {
    static let littleSpudNotificationOpened = Notification.Name("littleSpudNotificationOpened")
    static let littleSpudRemotePushReceived = Notification.Name("littleSpudRemotePushReceived")
    static let littleSpudRemotePushRegistrationFailed = Notification.Name("littleSpudRemotePushRegistrationFailed")
    static let littleSpudRemotePushTokenUpdated = Notification.Name("littleSpudRemotePushTokenUpdated")
}
