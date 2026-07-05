import UIKit
import FirebaseCore
import FirebaseMessaging
import AppTrackingTransparency
import UserNotifications
import AppsFlyerLib

final class AppDelegate: UIResponder, UIApplicationDelegate {

    private let splice = Splice()
    private let rap = Rap()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        ignite()

        if let remote = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            rap.rap(remote)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onActivation),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        return true
    }

    private func ignite() {
        let rungs: [Selector] = [
            #selector(bootHeat),
            #selector(bootTrack),
            #selector(bootSignal),
            #selector(bootWatch)
        ]
        rungs.forEach { _ = perform($0) }
    }

    @objc private func bootHeat() {
        FirebaseApp.configure()
    }
    
    @objc private func bootSignal() {
        Messaging.messaging().delegate = self
        UIApplication.shared.registerForRemoteNotifications()
    }

    @objc private func bootWatch() {
        UNUserNotificationCenter.current().delegate = self
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    @objc private func bootTrack() {
        let sdk = AppsFlyerLib.shared()
        sdk.appsFlyerDevKey = Lex.surveyorKey
        sdk.appleAppID = Lex.appCode
        sdk.delegate = self
        sdk.deepLinkDelegate = self
        sdk.isDebug = false
    }

    fileprivate func relayMarks(_ data: [AnyHashable: Any]) { splice.takeMarks(data) }
    fileprivate func relayNotes(_ data: [AnyHashable: Any]) { splice.takeNotes(data) }
    
    @objc private func onActivation() {
        if #available(iOS 14, *) {
            AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 60)
            ATTrackingManager.requestTrackingAuthorization { status in
                DispatchQueue.main.async {
                    AppsFlyerLib.shared().start()
                    UserDefaults.standard.set(status.rawValue, forKey: LexKey.attStatus)
                }
            }
        } else {
            AppsFlyerLib.shared().start()
        }
    }
    
    fileprivate func relayPush(_ data: [AnyHashable: Any]) { rap.rap(data) }
}

extension AppDelegate: MessagingDelegate {
    func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken fcmToken: String?
    ) {
        messaging.token { token, err in
            guard err == nil, let t = token else { return }
            UserDefaults.standard.set(t, forKey: LexKey.fcm)
            UserDefaults.standard.set(t, forKey: LexKey.push)
            UserDefaults(suiteName: Lex.suiteSite)?.set(t, forKey: LexKey.sharedFcm)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        relayPush(notification.request.content.userInfo)
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        relayPush(response.notification.request.content.userInfo)
        completionHandler()
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        relayPush(userInfo)
        completionHandler(.newData)
    }
}

extension AppDelegate: AppsFlyerLibDelegate, DeepLinkDelegate {
    func onConversionDataSuccess(_ data: [AnyHashable: Any]) {
        relayMarks(data)
    }

    func onConversionDataFail(_ error: Error) {
    }

    func didResolveDeepLink(_ result: DeepLinkResult) {
        guard case .found = result.status, let link = result.deepLink else { return }
        relayNotes(link.clickEvent)
    }
}
