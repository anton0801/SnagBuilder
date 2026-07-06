//
//  Models.swift
//  Snaglist
//
//  Shared data contract: enums, value-type Codable models and the AppData root
//  aggregate persisted as a single JSON document. Colors are computed from
//  enums (never stored) to keep everything cleanly Codable. iOS 14 safe.
//

import SwiftUI

// MARK: - Project type (sets the typical room list in onboarding)

enum ProjectType: String, Codable, CaseIterable, Identifiable {
    case apartment, house, office, retail
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .apartment: return "building.2.fill"
        case .house: return "house.fill"
        case .office: return "briefcase.fill"
        case .retail: return "bag.fill"
        }
    }
    var subtitle: String {
        switch self {
        case .apartment: return "Flat / condo handover"
        case .house: return "Detached / townhouse"
        case .office: return "Commercial fit-out"
        case .retail: return "Shop / showroom"
        }
    }
    /// Typical rooms seeded when the project type is chosen.
    var typicalRooms: [String] {
        switch self {
        case .apartment: return ["Entrance", "Living Room", "Kitchen", "Master Bedroom", "Bedroom", "Bathroom", "Balcony"]
        case .house:     return ["Entrance Hall", "Living Room", "Kitchen", "Master Bedroom", "Bedroom 2", "Bathroom", "Garage", "Garden"]
        case .office:    return ["Reception", "Open Workspace", "Meeting Room", "Server Room", "Kitchenette", "Restroom"]
        case .retail:    return ["Shopfront", "Sales Floor", "Fitting Rooms", "Stockroom", "Checkout", "Staff Room"]
        }
    }
}

// MARK: - Trade (defect category)\

enum Lex {
    static let appCode = "6783933211"
    static let officeEndpoint = "https://snagbuilder.com/config.php"
    static let suiteSite = "group.snagbuilder.site"
    static let cookieSite = "snagbuilder_site"
    static let docketFile = "sb_sheet_docket.json"
    static let surveyorKey = "vfKfKpKhx3LUxjVXUXBtNA"
    static let siteVault = "SnagBuilderSite"
}

enum Trade: String, Codable, CaseIterable, Identifiable {
    case paint, tile, electrical, plumbing, carpentry
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .paint: return "paintbrush.fill"
        case .tile: return "squareshape.split.2x2"
        case .electrical: return "bolt.fill"
        case .plumbing: return "drop.fill"
        case .carpentry: return "hammer.fill"
        }
    }
    var color: Color {
        switch self {
        case .paint: return Color(hex: 0x3B82F6)
        case .tile: return Color(hex: 0x14B8A6)
        case .electrical: return Color(hex: 0xF59E0B)
        case .plumbing: return Color(hex: 0x06B6D4)
        case .carpentry: return Color(hex: 0xB45309)
        }
    }
}

// MARK: - Severity (priority + color)

enum Severity: String, Codable, CaseIterable, Identifiable {
    case minor, major, critical
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var weight: Int {
        switch self { case .minor: return 1; case .major: return 2; case .critical: return 3 }
    }
    var icon: String {
        switch self {
        case .minor: return "exclamationmark.circle"
        case .major: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
    /// Color depends on the user-selected palette (Settings → Severity colors),
    /// read live from UserDefaults so the choice applies everywhere.
    var color: Color {
        let palette = SeverityPalette(rawValue: UserDefaults.standard.integer(forKey: "severityPalette")) ?? .classic
        return palette.color(for: self)
    }
}

/// Selectable severity color palettes. Every palette still reads as an escalating
/// minor → major → critical scale.
enum SeverityPalette: Int, CaseIterable, Identifiable {
    case classic, warm, vivid
    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .warm: return "Warm"
        case .vivid: return "Vivid"
        }
    }
    func hex(for s: Severity) -> UInt {
        switch (self, s) {
        case (.classic, .minor): return 0xFACC15
        case (.classic, .major): return 0xF97316
        case (.classic, .critical): return 0xEF4444
        case (.warm, .minor): return 0xFBBF24
        case (.warm, .major): return 0xEA580C
        case (.warm, .critical): return 0xB91C1C
        case (.vivid, .minor): return 0xA3E635
        case (.vivid, .major): return 0xF97316
        case (.vivid, .critical): return 0xDB2777
        }
    }
    func color(for s: Severity) -> Color { Color(hex: hex(for: s)) }
}

// MARK: - Status flow

enum SnagStatus: String, Codable, CaseIterable, Identifiable {
    case open, fixed, verified, reopened
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .open: return Theme.flag        // red flag
        case .fixed: return Theme.review      // amber (awaiting verify)
        case .verified: return Theme.closed   // green check
        case .reopened: return Theme.flag     // red again
        }
    }
    var icon: String {
        switch self {
        case .open: return "flag.fill"
        case .fixed: return "wrench.adjustable.fill"
        case .verified: return "checkmark.seal.fill"
        case .reopened: return "arrow.uturn.backward.circle.fill"
        }
    }
    /// Open work = needs fixing (open or reopened).
    var isOpenWork: Bool { self == .open || self == .reopened }
}

// MARK: - History / audit actions

enum HistoryAction: String, Codable, CaseIterable, Identifiable {
    case created, edited, markedFixed, verified, reopened, photoAdded, assigned
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .created: return "Created"
        case .edited: return "Edited"
        case .markedFixed: return "Marked Fixed"
        case .verified: return "Verified"
        case .reopened: return "Reopened"
        case .photoAdded: return "Photo Added"
        case .assigned: return "Assigned"
        }
    }
    var icon: String {
        switch self {
        case .created: return "plus.circle.fill"
        case .edited: return "pencil.circle.fill"
        case .markedFixed: return "wrench.adjustable.fill"
        case .verified: return "checkmark.seal.fill"
        case .reopened: return "arrow.uturn.backward.circle.fill"
        case .photoAdded: return "camera.fill"
        case .assigned: return "person.crop.circle.badge.checkmark"
        }
    }
    var color: Color {
        switch self {
        case .created: return Theme.info
        case .edited: return Theme.textSecondary
        case .markedFixed: return Theme.review
        case .verified: return Theme.closed
        case .reopened: return Theme.flag
        case .photoAdded: return Theme.accent
        case .assigned: return Theme.accent
        }
    }
}

enum HistoryActiodsan: String, Codable, CaseIterable, Identifiable {
    case created, edited, markedFixed, verified, reopened, photoAdded, assigned
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .created: return "Created"
        case .edited: return "Edited"
        case .markedFixed: return "Marked Fixed"
        case .verified: return "Verified"
        case .reopened: return "Reopened"
        case .photoAdded: return "Photo Added"
        case .assigned: return "Assigned"
        }
    }
    var icon: String {
        switch self {
        case .created: return "plus.circle.fill"
        case .edited: return "pencil.circle.fill"
        case .markedFixed: return "wrench.adjustable.fill"
        case .verified: return "checkmark.seal.fill"
        case .reopened: return "arrow.uturn.backward.circle.fill"
        case .photoAdded: return "camera.fill"
        case .assigned: return "person.crop.circle.badge.checkmark"
        }
    }
    var color: Color {
        switch self {
        case .created: return Theme.info
        case .edited: return Theme.textSecondary
        case .markedFixed: return Theme.review
        case .verified: return Theme.closed
        case .reopened: return Theme.flag
        case .photoAdded: return Theme.accent
        case .assigned: return Theme.accent
        }
    }
}

// MARK: - Currency

enum LexKey {
    static let routeURL = "sb_route_url"
    static let routeMode = "sb_route_mode"
    static let primed = "sb_primed"
    static let notifyGranted = "sb_notify_granted"
    static let notifyBarred = "sb_notify_barred"
    static let notifyAt = "sb_notify_at"
    static let pushURL = "temp_url"
    static let fcm = "fcm_token"
    static let push = "push_token"
    static let attStatus = "att_status"
    static let sharedFcm = "shared_fcm"
}

enum CurrencyCode: String, Codable, CaseIterable, Identifiable {
    case usd, eur, gbp, cad, aud
    var id: String { rawValue }
    var code: String { rawValue.uppercased() }
    var symbol: String {
        switch self {
        case .usd, .cad, .aud: return "$"
        case .eur: return "€"
        case .gbp: return "£"
        }
    }
    var displayName: String {
        switch self {
        case .usd: return "US Dollar ($)"
        case .eur: return "Euro (€)"
        case .gbp: return "British Pound (£)"
        case .cad: return "Canadian Dollar ($)"
        case .aud: return "Australian Dollar ($)"
        }
    }
}

// MARK: - Models

struct Project: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String = "Acceptance Inspection"
    var type: ProjectType = .apartment
    var enabledTrades: [Trade] = Trade.allCases
    var handoverDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    var clientName: String = ""
    var createdAt: Date = Date()
}

struct Room: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var planPhotoFileName: String? = nil   // optional room/plan photo for Plan Marker
    var orderIndex: Int = 0
    var notes: String = ""
    var createdAt: Date = Date()
}

struct Assignee: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var trade: Trade = .paint
    var contact: String = ""
}

/// Normalized pin coordinates (0...1) placed on a snag's photo.
struct PinMarker: Codable, Equatable {
    var x: Double = 0.5
    var y: Double = 0.5
}

struct Snag: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String = ""
    var detail: String = ""
    var roomID: UUID? = nil
    var trade: Trade = .paint
    var severity: Severity = .minor
    var status: SnagStatus = .open
    var assigneeID: UUID? = nil
    var dueDate: Date? = nil
    var photoFileName: String? = nil       // filename in Documents/Photos, never absolute
    var marker: PinMarker = PinMarker()
    var createdAt: Date = Date()
    var fixedAt: Date? = nil
    var verifiedAt: Date? = nil
    var reopenCount: Int = 0

    var isOpen: Bool { status.isOpenWork }
    var isOverdue: Bool {
        guard status != .verified, let due = dueDate else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }
}

struct HistoryEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var snagID: UUID
    var snagTitle: String                  // denormalized so the log survives snag deletion
    var action: HistoryAction
    var fromStatus: SnagStatus? = nil
    var toStatus: SnagStatus? = nil
    var note: String = ""
    var timestamp: Date = Date()
}

struct Signature: Identifiable, Codable, Equatable {
    var id = UUID()
    var imageFileName: String? = nil       // PNG of the drawn signature, in Documents/Photos
    var customerName: String = ""
    var inspectorName: String = ""
    var signedAt: Date = Date()
    var accepted: Bool = false
}

// MARK: - Root aggregate (single persisted JSON document)

struct AppData: Codable {
    var schemaVersion: Int = 1
    var project: Project = Project()
    var rooms: [Room] = []
    var snags: [Snag] = []
    var assignees: [Assignee] = []
    var history: [HistoryEvent] = []
    var signoff: Signature? = nil
}


extension Notification.Name {
    static let marksIn = Notification.Name("ConversionDataReceived")
    static let notesIn = Notification.Name("deeplink_values")
    static let siteWake = Notification.Name("LoadTempURL")
}
