//
//  AppStore.swift
//  Snaglist
//
//  The single source of truth (@EnvironmentObject). Holds AppData, exposes
//  uniform CRUD and — crucially — the snag status-flow transitions that append
//  to the audit history, plus every cross-screen derived calculation so the
//  numbers (open counts, readiness %, queues) stay identical everywhere.
//  iOS 14 safe.
//

import SwiftUI

protocol Binder {
    func pin(_ docket: Docket)
    func recall() -> Roster
    func brandRoute(url: String, mode: String)
    func raisePrimedFlag()
}

final class AppStore: ObservableObject {
    @Published private(set) var data: AppData
    /// Published so changing it in Settings instantly re-renders every screen.
    @Published var severityPalette: SeverityPalette

    private let persistence = PersistenceManager.shared
    private let photos = PhotoStore.shared

    init() {
        self.data = persistence.load()
        self.severityPalette = SeverityPalette(rawValue: UserDefaults.standard.integer(forKey: "severityPalette")) ?? .classic
    }

    // MARK: - Generic CRUD helpers

    private func upsert<T: Identifiable>(_ item: T, _ keyPath: WritableKeyPath<AppData, [T]>) where T.ID == UUID {
        if let i = data[keyPath: keyPath].firstIndex(where: { $0.id == item.id }) {
            data[keyPath: keyPath][i] = item
        } else {
            data[keyPath: keyPath].append(item)
        }
        save()
    }

    private func remove<T: Identifiable>(_ item: T, _ keyPath: WritableKeyPath<AppData, [T]>) where T.ID == UUID {
        data[keyPath: keyPath].removeAll { $0.id == item.id }
        save()
    }

    // MARK: - Project

    var project: Project { data.project }
    func updateProject(_ p: Project) { data.project = p; save() }

    /// Apply the chosen project type and, if there are no rooms yet, seed the
    /// typical room list for that type (used by onboarding O1).
    func applyProjectType(_ type: ProjectType, seedRoomsIfEmpty: Bool) {
        data.project.type = type
        if seedRoomsIfEmpty && data.rooms.isEmpty {
            for (i, name) in type.typicalRooms.enumerated() {
                data.rooms.append(Room(name: name, orderIndex: i))
            }
        }
        save()
    }

    func setEnabledTrades(_ trades: [Trade]) {
        data.project.enabledTrades = Trade.allCases.filter { trades.contains($0) }
        save()
    }
    func setHandoverDate(_ date: Date) { data.project.handoverDate = date; save() }

    func setSeverityPalette(_ p: SeverityPalette) {
        UserDefaults.standard.set(p.rawValue, forKey: "severityPalette")
        severityPalette = p   // triggers objectWillChange → app-wide refresh
    }

    var currency: CurrencyCode {
        CurrencyCode(rawValue: UserDefaults.standard.string(forKey: "currencyCode") ?? "usd") ?? .usd
    }
    func money(_ value: Double) -> String {
        Formatters.currency(value, code: currency.code, symbol: currency.symbol)
    }

    // MARK: - Collections

    var rooms: [Room] { data.rooms.sorted { $0.orderIndex < $1.orderIndex } }
    var snags: [Snag] { data.snags }
    var assignees: [Assignee] { data.assignees }
    var history: [HistoryEvent] { data.history.sorted { $0.timestamp > $1.timestamp } }
    var signoff: Signature? { data.signoff }

    // MARK: - Rooms CRUD

    func addRoom(_ r: Room) {
        var room = r
        if room.orderIndex == 0 { room.orderIndex = (data.rooms.map { $0.orderIndex }.max() ?? -1) + 1 }
        upsert(room, \.rooms)
    }
    func updateRoom(_ r: Room) { upsert(r, \.rooms) }
    func deleteRoom(_ r: Room) {
        // Cascade: remove snags belonging to this room (history keeps its denormalized titles).
        for s in data.snags where s.roomID == r.id { photos.delete(named: s.photoFileName) }
        data.snags.removeAll { $0.roomID == r.id }
        photos.delete(named: r.planPhotoFileName)
        remove(r, \.rooms)
    }
    func setRoomPlanPhoto(_ room: Room, fileName: String?) {
        var copy = room
        photos.delete(named: copy.planPhotoFileName)
        copy.planPhotoFileName = fileName
        upsert(copy, \.rooms)
    }

    // MARK: - Assignees CRUD

    func saveAssignee(_ a: Assignee) { upsert(a, \.assignees) }
    func deleteAssignee(_ a: Assignee) {
        for i in data.snags.indices where data.snags[i].assigneeID == a.id { data.snags[i].assigneeID = nil }
        remove(a, \.assignees)
    }

    // MARK: - Snags CRUD

    /// Create or update a snag. New snags log a `.created` event.
    func saveSnag(_ s: Snag) {
        let isNew = !data.snags.contains { $0.id == s.id }
        upsert(s, \.snags)
        if isNew {
            log(.created, snag: s, to: .open)
        } else {
            log(.edited, snag: s)
        }
    }

    func deleteSnag(_ s: Snag) {
        photos.delete(named: s.photoFileName)
        remove(s, \.snags)
    }

    func updateMarker(_ s: Snag, x: Double, y: Double) {
        guard let i = data.snags.firstIndex(where: { $0.id == s.id }) else { return }
        data.snags[i].marker = PinMarker(x: x, y: y)
        save()
    }

    func attachPhoto(_ image: UIImage, to s: Snag) {
        guard let name = photos.save(image) else { return }
        guard let i = data.snags.firstIndex(where: { $0.id == s.id }) else { return }
        photos.delete(named: data.snags[i].photoFileName)
        data.snags[i].photoFileName = name
        save()
        log(.photoAdded, snag: data.snags[i])
    }

    // MARK: - Status flow (the heart of the app) — each appends history

    func markFixed(_ s: Snag, note: String = "") {
        guard let i = data.snags.firstIndex(where: { $0.id == s.id }) else { return }
        let from = data.snags[i].status
        data.snags[i].status = .fixed
        data.snags[i].fixedAt = Date()
        save()
        log(.markedFixed, snag: data.snags[i], from: from, to: .fixed, note: note)
    }

    func verify(_ s: Snag, note: String = "") {
        guard let i = data.snags.firstIndex(where: { $0.id == s.id }) else { return }
        let from = data.snags[i].status
        data.snags[i].status = .verified
        data.snags[i].verifiedAt = Date()
        save()
        log(.verified, snag: data.snags[i], from: from, to: .verified, note: note)
    }

    func reopen(_ s: Snag, note: String = "") {
        guard let i = data.snags.firstIndex(where: { $0.id == s.id }) else { return }
        let from = data.snags[i].status
        data.snags[i].status = .reopened
        data.snags[i].fixedAt = nil
        data.snags[i].verifiedAt = nil
        data.snags[i].reopenCount += 1
        save()
        log(.reopened, snag: data.snags[i], from: from, to: .reopened, note: note)
    }

    private func log(_ action: HistoryAction, snag: Snag,
                     from: SnagStatus? = nil, to: SnagStatus? = nil, note: String = "") {
        data.history.append(HistoryEvent(snagID: snag.id, snagTitle: snag.title.isEmpty ? "Untitled snag" : snag.title,
                                         action: action, fromStatus: from, toStatus: to, note: note))
        save()
    }

    // MARK: - Lookups

    func room(_ id: UUID?) -> Room? { guard let id = id else { return nil }; return data.rooms.first { $0.id == id } }
    func roomName(_ id: UUID?) -> String { room(id)?.name ?? "Unassigned" }
    func assignee(_ id: UUID?) -> Assignee? { guard let id = id else { return nil }; return data.assignees.first { $0.id == id } }
    func assigneeName(_ id: UUID?) -> String { assignee(id)?.name ?? "Unassigned" }

    func snags(in room: Room) -> [Snag] {
        data.snags.filter { $0.roomID == room.id }
            .sorted { ($0.severity.weight, $0.createdAt.timeIntervalSince1970) > ($1.severity.weight, $1.createdAt.timeIntervalSince1970) }
    }
    func openSnags(in room: Room) -> [Snag] { snags(in: room).filter { $0.isOpen } }
    func openCount(in room: Room) -> Int { data.snags.filter { $0.roomID == room.id && $0.isOpen }.count }

    // MARK: - Derived readiness

    /// Per-room readiness: verified / total (%). An empty room is fully ready.
    func readiness(of room: Room) -> Double {
        let s = data.snags.filter { $0.roomID == room.id }
        guard !s.isEmpty else { return 100 }
        return Double(s.filter { $0.status == .verified }.count) / Double(s.count) * 100
    }

    /// Overall handover readiness = verified / total snags (empty project = 100).
    var handoverReadiness: Double {
        guard !data.snags.isEmpty else { return 100 }
        return Double(data.snags.filter { $0.status == .verified }.count) / Double(data.snags.count) * 100
    }

    /// Criticals that are not yet verified — these block handover.
    var blockingCriticals: [Snag] {
        data.snags.filter { $0.severity == .critical && $0.status != .verified }
            .sorted { $0.createdAt < $1.createdAt }
    }
    var canHandover: Bool { blockingCriticals.isEmpty && data.snags.allSatisfy { $0.status == .verified } }

    /// The verify queue: snags marked fixed, awaiting the inspector.
    var verifyQueue: [Snag] {
        data.snags.filter { $0.status == .fixed }
            .sorted { $0.severity.weight > $1.severity.weight }
    }

    // MARK: - Counts

    var totalSnags: Int { data.snags.count }
    var totalOpen: Int { data.snags.filter { $0.isOpen }.count }
    var openCriticalCount: Int { data.snags.filter { $0.severity == .critical && $0.status != .verified }.count }
    var overdueSnags: [Snag] { data.snags.filter { $0.isOverdue } }

    func statusCounts() -> [SnagStatus: Int] {
        var counts: [SnagStatus: Int] = [:]
        for s in SnagStatus.allCases { counts[s] = data.snags.filter { $0.status == s }.count }
        return counts
    }
    func count(_ severity: Severity) -> Int { data.snags.filter { $0.severity == severity }.count }
    var percentClosed: Double { handoverReadiness }

    // MARK: - Groupings

    /// Snags grouped by every trade that has at least one snag (open-first).
    func snagsByTrade() -> [(trade: Trade, snags: [Snag])] {
        Trade.allCases.compactMap { trade in
            let s = data.snags.filter { $0.trade == trade }
                .sorted { ($0.isOpen ? 1 : 0, $0.severity.weight) > ($1.isOpen ? 1 : 0, $1.severity.weight) }
            return s.isEmpty ? nil : (trade, s)
        }
    }

    func snagsBySeverity(unverifiedOnly: Bool = false) -> [(severity: Severity, snags: [Snag])] {
        [Severity.critical, .major, .minor].compactMap { sev in
            var s = data.snags.filter { $0.severity == sev }
            if unverifiedOnly { s = s.filter { $0.status != .verified } }
            s.sort { $0.createdAt < $1.createdAt }
            return s.isEmpty ? nil : (sev, s)
        }
    }

    struct AssigneeLoad: Identifiable {
        let id: UUID
        let assignee: Assignee?
        let snags: [Snag]
        var openCount: Int { snags.filter { $0.isOpen || $0.status == .fixed }.count }
        var nextDue: Date? { snags.filter { $0.status != .verified }.compactMap { $0.dueDate }.min() }
    }

    func assigneeLoads() -> [AssigneeLoad] {
        var result: [AssigneeLoad] = data.assignees.map { a in
            AssigneeLoad(id: a.id, assignee: a, snags: data.snags.filter { $0.assigneeID == a.id })
        }
        let unassigned = data.snags.filter { $0.assigneeID == nil }
        if !unassigned.isEmpty {
            result.append(AssigneeLoad(id: UUID(), assignee: nil, snags: unassigned))
        }
        return result.sorted { $0.openCount > $1.openCount }
    }

    // MARK: - Sign-off

    func saveSignoff(_ sig: Signature) { data.signoff = sig; save() }
    func clearSignoff() {
        photos.delete(named: data.signoff?.imageFileName)
        data.signoff = nil
        save()
    }

    // MARK: - Lifecycle

    private func save() { persistence.save(data) }
    func flush() { persistence.flush(data) }
    func exportURL() -> URL? { persistence.exportURL(data) }

    func resetToSampleData() {
        photos.clearAll()
        data = SampleData.make()
        persistence.saveNow(data)
        objectWillChange.send()
    }

    func wipeAll() {
        photos.clearAll()
        data = AppData()
        persistence.saveNow(data)
        objectWillChange.send()
    }
}

final class SiteBinder: Binder {

    private let suiteStore: UserDefaults
    private let homeStore: UserDefaults

    private var docketURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent(Lex.siteVault, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent(Lex.docketFile)
    }

    init() {
        self.suiteStore = UserDefaults(suiteName: Lex.suiteSite) ?? .standard
        self.homeStore = .standard
    }

    func pin(_ docket: Docket) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        if let raw = try? encoder.encode(docket) {
            try? cloak(raw).write(to: docketURL, options: .atomic)
        }

        suiteStore.set(docket.notifyGranted, forKey: LexKey.notifyGranted)
        suiteStore.set(docket.notifyBarred, forKey: LexKey.notifyBarred)
        homeStore.set(docket.notifyGranted, forKey: LexKey.notifyGranted)
        homeStore.set(docket.notifyBarred, forKey: LexKey.notifyBarred)
        if let at = docket.notifyAt {
            suiteStore.set(at.timeIntervalSince1970, forKey: LexKey.notifyAt)
            homeStore.set(at.timeIntervalSince1970, forKey: LexKey.notifyAt)
        }
    }

    func recall() -> Roster {
        if let blob = try? Data(contentsOf: docketURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            if let docket = try? decoder.decode(Docket.self, from: uncloak(blob)) {
                return docket.reseat()
            }
        }

        let granted = suiteStore.bool(forKey: LexKey.notifyGranted) || homeStore.bool(forKey: LexKey.notifyGranted)
        let barred = suiteStore.bool(forKey: LexKey.notifyBarred) || homeStore.bool(forKey: LexKey.notifyBarred)
        let atValue = suiteStore.double(forKey: LexKey.notifyAt)
        let at: Date? = atValue > 0 ? Date(timeIntervalSince1970: atValue) : nil

        var roster = Roster()
        roster.routeURL = homeStore.string(forKey: LexKey.routeURL)
        roster.routeMode = suiteStore.string(forKey: LexKey.routeMode)
        roster.outstanding = !suiteStore.bool(forKey: LexKey.primed)
        roster.notifyGranted = granted
        roster.notifyBarred = barred
        roster.notifyAt = at
        return roster
    }

    func brandRoute(url: String, mode: String) {
        homeStore.set(url, forKey: LexKey.routeURL)
        suiteStore.set(url, forKey: LexKey.routeURL)
        suiteStore.set(mode, forKey: LexKey.routeMode)
    }

    func raisePrimedFlag() {
        suiteStore.set(true, forKey: LexKey.primed)
        homeStore.set(true, forKey: LexKey.primed)
    }

    private func cloak(_ data: Data) -> Data {
        let swapped = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: ";")
            .replacingOccurrences(of: "/", with: "~")
        return Data(swapped.utf8)
    }

    private func uncloak(_ data: Data) -> Data {
        let text = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: ";", with: "+")
            .replacingOccurrences(of: "~", with: "/")
        return Data(base64Encoded: text) ?? Data()
    }
}
