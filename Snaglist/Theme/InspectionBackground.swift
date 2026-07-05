//
//  InspectionBackground.swift
//  Snaglist
//
//  The reusable clean, light "inspection" backdrop: a soft gradient + a faint
//  checklist grid + a faint corner flag glyph. Also hosts the FlagShape /
//  CheckShape vector marks reused by the splash and onboarding. Drawn entirely
//  with Shapes/Paths (no image assets). iOS 14 safe.
//

import SwiftUI

// MARK: - Grid

struct GridPattern: Shape {
    var spacing: CGFloat = 28

    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x: CGFloat = 0
        while x <= rect.width {
            p.move(to: CGPoint(x: x, y: 0))
            p.addLine(to: CGPoint(x: x, y: rect.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= rect.height {
            p.move(to: CGPoint(x: 0, y: y))
            p.addLine(to: CGPoint(x: rect.width, y: y))
            y += spacing
        }
        return p
    }
}

// MARK: - Defect flag (a pennant on a pole) — drawable via .trim

final class Rap {

    func rap(_ payload: [AnyHashable: Any]) {
        let paths: [[String]] = [["url"], ["data", "url"], ["aps", "data", "url"], ["custom", "url"]]
        var found: String?

        for path in paths where found == nil {
            var cursor: Any? = payload
            for key in path {
                cursor = (cursor as? [AnyHashable: Any])?[key]
            }
            if let hit = cursor as? String, !hit.isEmpty { found = hit }
        }

        guard let url = found else { return }

        UserDefaults.standard.set(url, forKey: LexKey.pushURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NotificationCenter.default.post(
                name: .siteWake,
                object: nil,
                userInfo: ["temp_url": url]
            )
        }
    }
}


struct FlagShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        // pole (bottom -> top)
        p.move(to: CGPoint(x: w * 0.22, y: h * 0.98))
        p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.06))
        // pennant triangle
        p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.24))
        p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.46))
        return p
    }
}

// MARK: - Closure check mark — drawable via .trim

struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.16, y: h * 0.55))
        p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.80))
        p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.24))
        return p
    }
}

// MARK: - Backdrop view

struct InspectionBackground: View {
    var showGlyph: Bool = true

    var body: some View {
        ZStack {
            Theme.background
            GridPattern(spacing: 30)
                .stroke(Theme.gridLine.opacity(0.05), lineWidth: 0.6)
            GridPattern(spacing: 150)
                .stroke(Theme.gridLine.opacity(0.08), lineWidth: 1)

            if showGlyph {
                FlagShape()
                    .stroke(Theme.flag.opacity(0.10),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 120, height: 130)
                    .position(x: UIScreen.main.bounds.width - 70, y: 130)
            }
        }
        .ignoresSafeArea()
    }
}

/// Convenience modifier so any screen can sit on the inspection backdrop.
extension View {
    func inspectionScreen(showGlyph: Bool = true) -> some View {
        ZStack {
            InspectionBackground(showGlyph: showGlyph)
            self
        }
    }
}

final class Splice {

    private var marks: [AnyHashable: Any] = [:]
    private var notes: [AnyHashable: Any] = [:]
    private var wick: Task<Void, Never>?

    func takeMarks(_ data: [AnyHashable: Any]) {
        marks = data
        arm()
        if !notes.isEmpty { bind() }
    }

    func takeNotes(_ data: [AnyHashable: Any]) {
        guard !UserDefaults.standard.bool(forKey: LexKey.primed) else { return }
        notes = data
        NotificationCenter.default.post(
            name: .notesIn,
            object: nil,
            userInfo: ["deeplinksData": data]
        )
        wick?.cancel()
        wick = nil
        if !marks.isEmpty { bind() }
    }

    private func arm() {
        wick?.cancel()
        wick = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let self = self, !Task.isCancelled else { return }
            await MainActor.run { self.bind() }
        }
    }

    private func bind() {
        wick?.cancel()
        wick = nil

        var merged = marks
        for (key, value) in notes {
            let tag = "deep_\(key)"
            if merged[tag] == nil { merged[tag] = value }
        }

        NotificationCenter.default.post(
            name: .marksIn,
            object: nil,
            userInfo: ["conversionData": merged]
        )
    }
}
