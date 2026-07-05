//
//  SampleData.swift
//  Snaglist
//
//  A realistic demo inspection used on first launch and by "Reset Sample Data".
//  Covers every status, severity and trade so all screens show real content.
//

import Foundation

enum SampleData {
    static func make() -> AppData {
        var data = AppData()

        let today = Calendar.current.startOfDay(for: Date())
        func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: today) ?? today }

        // Project
        data.project = Project(
            name: "Maple Court · Unit 4B",
            type: .apartment,
            enabledTrades: Trade.allCases,
            handoverDate: day(14),
            clientName: "J. Whitfield"
        )

        // Rooms
        let living   = Room(name: "Living Room", orderIndex: 0)
        let kitchen  = Room(name: "Kitchen", orderIndex: 1)
        let master   = Room(name: "Master Bedroom", orderIndex: 2)
        let bath     = Room(name: "Bathroom", orderIndex: 3)
        let balcony  = Room(name: "Balcony", orderIndex: 4)
        data.rooms = [living, kitchen, master, bath, balcony]

        // Assignees
        let mia   = Assignee(name: "Mia (Painter)", trade: .paint, contact: "555-0142")
        let tom   = Assignee(name: "Tom (Tiler)", trade: .tile, contact: "555-0188")
        let raj   = Assignee(name: "Raj (Electrician)", trade: .electrical, contact: "555-0207")
        let pete  = Assignee(name: "Pete (Plumber)", trade: .plumbing, contact: "555-0233")
        let cara  = Assignee(name: "Cara (Carpenter)", trade: .carpentry, contact: "555-0299")
        data.assignees = [mia, tom, raj, pete, cara]

        var snags: [Snag] = []
        var history: [HistoryEvent] = []

        func add(_ title: String, _ detail: String, room: Room, trade: Trade, severity: Severity,
                 status: SnagStatus, assignee: Assignee?, due: Int, created: Int,
                 mx: Double = 0.5, my: Double = 0.5) {
            var s = Snag(title: title, detail: detail, roomID: room.id, trade: trade,
                         severity: severity, status: status, assigneeID: assignee?.id,
                         dueDate: day(due), marker: PinMarker(x: mx, y: my), createdAt: day(created))
            if status == .fixed || status == .verified { s.fixedAt = day(created + 1) }
            if status == .verified { s.verifiedAt = day(created + 2) }
            if status == .reopened { s.fixedAt = nil; s.reopenCount = 1 }
            snags.append(s)

            history.append(HistoryEvent(snagID: s.id, snagTitle: s.title, action: .created,
                                        toStatus: .open, timestamp: day(created)))
            if status == .fixed || status == .verified {
                history.append(HistoryEvent(snagID: s.id, snagTitle: s.title, action: .markedFixed,
                                            fromStatus: .open, toStatus: .fixed, timestamp: day(created + 1)))
            }
            if status == .verified {
                history.append(HistoryEvent(snagID: s.id, snagTitle: s.title, action: .verified,
                                            fromStatus: .fixed, toStatus: .verified, timestamp: day(created + 2)))
            }
            if status == .reopened {
                history.append(HistoryEvent(snagID: s.id, snagTitle: s.title, action: .markedFixed,
                                            fromStatus: .open, toStatus: .fixed, timestamp: day(created + 1)))
                history.append(HistoryEvent(snagID: s.id, snagTitle: s.title, action: .reopened,
                                            fromStatus: .fixed, toStatus: .reopened,
                                            note: "Fix did not hold on re-check.", timestamp: day(created + 3)))
            }
        }

        // Living Room
        add("Scuff marks on feature wall", "Several scuffs near the TV unit need touch-up.",
            room: living, trade: .paint, severity: .minor, status: .open, assignee: mia, due: 5, created: -6, mx: 0.62, my: 0.4)
        add("Skirting board gap", "1cm gap at the corner joint by the window.",
            room: living, trade: .carpentry, severity: .major, status: .fixed, assignee: cara, due: 3, created: -8, mx: 0.2, my: 0.82)
        add("Socket not powered", "Double socket left of fireplace has no power.",
            room: living, trade: .electrical, severity: .critical, status: .open, assignee: raj, due: 1, created: -4, mx: 0.12, my: 0.55)

        // Kitchen
        add("Cracked splashback tile", "Hairline crack on the second tile above the hob.",
            room: kitchen, trade: .tile, severity: .major, status: .open, assignee: tom, due: 4, created: -7, mx: 0.55, my: 0.3)
        add("Leaking sink trap", "Slow drip under the sink — water staining the base unit.",
            room: kitchen, trade: .plumbing, severity: .critical, status: .fixed, assignee: pete, due: 2, created: -5, mx: 0.48, my: 0.7)
        add("Cabinet door misaligned", "Top-left cabinet door sits proud by ~3mm.",
            room: kitchen, trade: .carpentry, severity: .minor, status: .verified, assignee: cara, due: -1, created: -10, mx: 0.3, my: 0.25)

        // Master Bedroom
        add("Paint drips on ceiling", "Two visible drips near the light fitting.",
            room: master, trade: .paint, severity: .minor, status: .reopened, assignee: mia, due: 2, created: -9, mx: 0.5, my: 0.18)
        add("Wardrobe rail loose", "Hanging rail pulls out of the bracket.",
            room: master, trade: .carpentry, severity: .major, status: .open, assignee: cara, due: 6, created: -3, mx: 0.78, my: 0.5)

        // Bathroom
        add("Grout missing around bath", "Open grout line could let water through.",
            room: bath, trade: .tile, severity: .major, status: .open, assignee: tom, due: 3, created: -6, mx: 0.4, my: 0.62)
        add("Extractor fan silent", "Fan does not start with the light switch.",
            room: bath, trade: .electrical, severity: .major, status: .fixed, assignee: raj, due: 1, created: -5, mx: 0.66, my: 0.2)
        add("Toilet base sealant", "Sealant bead is uneven and peeling.",
            room: bath, trade: .plumbing, severity: .minor, status: .verified, assignee: pete, due: -2, created: -11, mx: 0.5, my: 0.85)

        // Balcony
        add("Door seal damaged", "Rubber seal on the balcony door is torn.",
            room: balcony, trade: .carpentry, severity: .minor, status: .open, assignee: cara, due: 7, created: -2, mx: 0.5, my: 0.5)

        data.snags = snags
        data.history = history.sorted { $0.timestamp < $1.timestamp }
        return data
    }
}

enum Fault: Error {
    case blankList(at: String)
    case crookedRef(at: String)
    case dropped(stage: String)
    case backlog(cooldown: TimeInterval)
    case boardedUp(httpCode: Int)
    case failedItem(reason: String)
    case illegible(at: String)

    var isSealed: Bool {
        switch self {
        case .boardedUp, .failedItem:
            return true
        default:
            return false
        }
    }
}
