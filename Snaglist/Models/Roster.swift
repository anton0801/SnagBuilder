import Foundation

struct Roster {
    var marks: [String: String] = [:]
    var notes: [String: String] = [:]
    var routeURL: String?
    var routeMode: String?
    var outstanding: Bool = true
    var closed: Bool = false
    var swept: Bool = false
    var notifyGranted: Bool = false
    var notifyBarred: Bool = false
    var notifyAt: Date?

    var hasMarks: Bool {
        !marks.isEmpty
    }

    var organicHaze: Bool {
        (marks["af_status"] ?? "").caseInsensitiveCompare("Organic") == .orderedSame
    }

    var notifyDue: Bool {
        guard !notifyGranted && !notifyBarred else { return false }
        if let at = notifyAt {
            return Date().timeIntervalSince(at) / 86_400 >= 3
        }
        return true
    }

    func docket() -> Docket {
        Docket(
            marks: marks,
            notes: notes,
            routeURL: routeURL,
            routeMode: routeMode,
            outstanding: outstanding,
            swept: swept,
            notifyGranted: notifyGranted,
            notifyBarred: notifyBarred,
            notifyAt: notifyAt
        )
    }
}

struct Docket: Codable {
    var marks: [String: String]
    var notes: [String: String]
    var routeURL: String?
    var routeMode: String?
    var outstanding: Bool
    var swept: Bool
    var notifyGranted: Bool
    var notifyBarred: Bool
    var notifyAt: Date?

    func reseat() -> Roster {
        var roster = Roster()
        roster.marks = marks
        roster.notes = notes
        roster.routeURL = routeURL
        roster.routeMode = routeMode
        roster.outstanding = outstanding
        roster.swept = swept
        roster.notifyGranted = notifyGranted
        roster.notifyBarred = notifyBarred
        roster.notifyAt = notifyAt
        return roster
    }
}

enum Stamp {
    case pending
    case notify
    case handover
    case reject
}

enum Chore {
    case sweep
    case patch
    case lodge
}
