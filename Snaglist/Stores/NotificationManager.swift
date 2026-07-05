//
//  NotificationManager.swift
//  Snaglist
//
//  Real local-notification scheduling for the inspection: a daily re-verify
//  digest, a one-shot handover-date reminder, and per-snag fix-due reminders.
//  Uses UNUserNotificationCenter (iOS 10+, fully iOS 14 safe). No remote push.
//

import UserNotifications
import Foundation
import UIKit

protocol Bell {
    func ring() async -> Bool
    func wireKnell()
}

final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private let digestID = "snaglist.verify.digest"
    private let handoverID = "snaglist.handover.reminder"
    private let duedatePrefix = "snaglist.due."

    @Published var isAuthorized = false

    init() { refreshStatus() }

    func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = (settings.authorizationStatus == .authorized
                                     || settings.authorizationStatus == .provisional)
            }
        }
    }

    /// Requests permission once; `completion(true)` if the user granted it.
    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async {
                self.isAuthorized = granted
                completion(granted)
            }
        }
    }

    // MARK: - Daily re-verify digest

    func scheduleVerifyDigest(hour: Int, minute: Int, body: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [digestID])

        let content = UNMutableNotificationContent()
        content.title = "Snag List — Verify Queue"
        content.body = body
        content.sound = .default

        var comps = DateComponents(); comps.hour = hour; comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: digestID, content: content, trigger: trigger), withCompletionHandler: nil)
    }
    func cancelVerifyDigest() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [digestID])
    }

    // MARK: - Handover-date reminder (one-shot, 9am on the handover day)

    func scheduleHandoverReminder(on date: Date, body: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [handoverID])

        let content = UNMutableNotificationContent()
        content.title = "Snag List — Handover Day"
        content.body = body
        content.sound = .default

        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = 9; comps.minute = 0
        // Only schedule if the trigger is in the future.
        if let fireDate = Calendar.current.date(from: comps), fireDate > Date() {
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: handoverID, content: content, trigger: trigger), withCompletionHandler: nil)
        }
    }
    func cancelHandoverReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [handoverID])
    }

    // MARK: - Per-snag fix-due reminders (9am on the due date)

    /// Replaces all existing due reminders with one per provided (id, title, date).
    func scheduleDueReminders(_ items: [(id: UUID, title: String, due: Date)]) {
        let center = UNUserNotificationCenter.current()
        // Clear previous due reminders first.
        center.getPendingNotificationRequests { reqs in
            let stale = reqs.map { $0.identifier }.filter { $0.hasPrefix(self.duedatePrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)

            for item in items {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: item.due)
                comps.hour = 9; comps.minute = 0
                guard let fireDate = Calendar.current.date(from: comps), fireDate > Date() else { continue }
                let content = UNMutableNotificationContent()
                content.title = "Snag due today"
                content.body = item.title
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                center.add(UNNotificationRequest(identifier: self.duedatePrefix + item.id.uuidString,
                                                 content: content, trigger: trigger), withCompletionHandler: nil)
            }
        }
    }
    func cancelDueReminders() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { reqs in
            let stale = reqs.map { $0.identifier }.filter { $0.hasPrefix(self.duedatePrefix) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }
    }

    // MARK: - Test

    /// Fires a one-off confirmation so the user immediately sees it working.
    func sendTestNotification(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Snag List"
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger),
            withCompletionHandler: nil)
    }
}

final class SiteBell: Bell {

    private let center = UNUserNotificationCenter.current()

    func ring() async -> Bool {
        let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { ok, _ in
                cont.resume(returning: ok)
            }
        }
        if granted { wireKnell() }
        return granted
    }

    func wireKnell() {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}

