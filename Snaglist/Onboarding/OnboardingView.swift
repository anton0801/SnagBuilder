//
//  OnboardingView.swift
//  Snaglist
//
//  Four interactive setup screens, shown on first launch only. Each has a
//  distinct gesture: (1) tap-to-burst, (2) drag-to-paint-select trades,
//  (3) scroll-driven parallax, (4) long-press hold-to-lock. Choices persist into
//  the AppStore. iOS 14 safe (PageTabViewStyle, presentationMode, withAnimation).
//

import SwiftUI

// Scroll-offset preference for the parallax page.
private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct RoomView: View {
    @State private var targetURL: String? = ""
    @State private var isActive = false

    var body: some View {
        ZStack {
            if isActive, let urlString = targetURL, let url = URL(string: urlString) {
                RoomRig(url: url).ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { initialize() }
        .onReceive(NotificationCenter.default.publisher(for: .siteWake)) { _ in reload() }
    }

    private func initialize() {
        let temp = UserDefaults.standard.string(forKey: LexKey.pushURL)
        let stored = UserDefaults.standard.string(forKey: LexKey.routeURL) ?? ""
        targetURL = temp ?? stored
        isActive = true
        if temp != nil { UserDefaults.standard.removeObject(forKey: LexKey.pushURL) }
    }

    private func reload() {
        if let temp = UserDefaults.standard.string(forKey: LexKey.pushURL), !temp.isEmpty {
            isActive = false
            targetURL = temp
            UserDefaults.standard.removeObject(forKey: LexKey.pushURL)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isActive = true }
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    let onComplete: () -> Void

    @State private var page = 0
    @State private var projectType: ProjectType = .apartment
    @State private var selectedTrades: Set<Trade> = Set(Trade.allCases)
    @State private var palette: SeverityPalette = .classic
    @State private var handoverDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()

    var body: some View {
        ZStack {
            InspectionBackground(showGlyph: true)

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip") { finish() }
                        .font(Theme.caption(14))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.horizontal, Theme.Space.m)
                        .padding(.top, Theme.Space.m)
                }

                TabView(selection: $page) {
                    ProjectTypePage(selected: $projectType).tag(0)
                    TradesPage(selected: $selectedTrades).tag(1)
                    SeverityPage(palette: $palette).tag(2)
                    HandoverPage(handoverDate: $handoverDate).tag(3)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

                // Dots
                HStack(spacing: 8) {
                    ForEach(0..<4) { i in
                        Capsule()
                            .fill(i == page ? Theme.accent : Theme.stroke)
                            .frame(width: i == page ? 22 : 8, height: 8)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: page)
                    }
                }
                .padding(.vertical, 12)

                ActionButton(title: primaryTitle,
                             systemImage: page == 3 ? "play.fill" : "arrow.right") {
                    advance()
                }
                .disabled(page == 1 && selectedTrades.isEmpty)
                .opacity(page == 1 && selectedTrades.isEmpty ? 0.5 : 1)
                .padding(.horizontal, Theme.Space.l)
                .padding(.bottom, Theme.Space.l)
            }
        }
    }

    private var primaryTitle: String {
        switch page {
        case 0: return "Set Project"
        case 1: return "Set Trades"
        case 2: return "Set Severity"
        default: return "Start Inspection"
        }
    }

    private func advance() {
        if page < 3 {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { page += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        store.applyProjectType(projectType, seedRoomsIfEmpty: true)
        store.setEnabledTrades(Array(selectedTrades))
        store.setSeverityPalette(palette)
        store.setHandoverDate(handoverDate)
        onComplete()
    }
}

// MARK: - O1 · Project Type (tap-to-burst)

private struct ProjectTypePage: View {
    @Binding var selected: ProjectType
    @State private var bursts: [Burst] = []
    @State private var pulse = false

    struct Burst: Identifiable { let id = UUID(); let angle: Double; var go = false }

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            header("What are you handing over?", "Tap a type — we set up the typical rooms & checklist")

            ZStack {
                ForEach(bursts) { b in
                    Circle().fill(Theme.accent)
                        .frame(width: 8, height: 8)
                        .offset(x: b.go ? CGFloat(cos(b.angle)) * 90 : 0,
                                y: b.go ? CGFloat(sin(b.angle)) * 90 : 0)
                        .opacity(b.go ? 0 : 1)
                }
                Circle()
                    .fill(Theme.accentGradient)
                    .frame(width: 104, height: 104)
                    .scaleEffect(pulse ? 1.05 : 0.97)
                    .overlay(Image(systemName: selected.icon)
                        .font(.system(size: 42, weight: .bold)).foregroundColor(.white))
            }
            .onTapGesture { burst() }
            .frame(height: 120)

            VStack(spacing: 10) {
                ForEach(ProjectType.allCases) { type in
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { selected = type }
                        burst()
                    }) {
                        HStack {
                            Image(systemName: type.icon).foregroundColor(selected == type ? .white : Theme.accent).frame(width: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(type.displayName).font(Theme.heading(15))
                                    .foregroundColor(selected == type ? .white : Theme.textPrimary)
                                Text(type.subtitle).font(Theme.caption(11))
                                    .foregroundColor(selected == type ? .white.opacity(0.85) : Theme.textSecondary)
                            }
                            Spacer()
                            if selected == type { Image(systemName: "checkmark.circle.fill").foregroundColor(.white) }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(selected == type ? Theme.accent : Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).stroke(Theme.stroke, lineWidth: selected == type ? 0 : 1))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, Theme.Space.l)
            Spacer(minLength: 0)
        }
        .onAppear { withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true } }
        .onDisappear { pulse = false }
    }

    private func burst() {
        bursts = (0..<12).map { Burst(angle: Double($0) / 12 * 2 * .pi) }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.6)) { for i in bursts.indices { bursts[i].go = true } }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { bursts.removeAll() }
    }
}

// MARK: - O2 · Trades (drag-to-paint multiselect)

private struct TradesPage: View {
    @Binding var selected: Set<Trade>
    @State private var lastIndex: Int? = nil
    private let trades = Trade.allCases

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            header("Which trades are on site?", "Drag across the row to toggle several — these become your defect categories")

            GeometryReader { geo in
                let count = trades.count
                let cellW = geo.size.width / CGFloat(count)
                HStack(spacing: 0) {
                    ForEach(Array(trades.enumerated()), id: \.element) { _, trade in
                        chip(trade).frame(width: cellW)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let idx = Int(v.location.x / cellW)
                            guard idx >= 0 && idx < count else { return }
                            if idx != lastIndex { toggle(trades[idx]); lastIndex = idx }
                        }
                        .onEnded { _ in lastIndex = nil }
                )
            }
            .frame(height: 132)
            .padding(.horizontal, Theme.Space.m)

            CardView {
                HStack(spacing: 10) {
                    Image(systemName: "lightbulb.fill").foregroundColor(Theme.review)
                    Text(selected.isEmpty ? "Select at least one trade to continue."
                                           : "\(selected.count) trade\(selected.count == 1 ? "" : "s") enabled. You can change this later in Settings.")
                        .font(Theme.caption(12)).foregroundColor(Theme.textSecondary)
                }
            }
            .padding(.horizontal, Theme.Space.l)
            Spacer(minLength: 0)
        }
    }

    private func chip(_ trade: Trade) -> some View {
        let on = selected.contains(trade)
        return VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(on ? trade.color : Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? Color.clear : Theme.stroke, lineWidth: 1))
                    .frame(width: 52, height: 52)
                    .shadow(color: on ? trade.color.opacity(0.4) : .clear, radius: 6, y: 3)
                Image(systemName: trade.icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(on ? .white : trade.color)
            }
            .scaleEffect(on ? 1.06 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: on)
            Text(trade.displayName).font(Theme.caption(10))
                .foregroundColor(on ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .contentShape(Rectangle())
        .onTapGesture { toggle(trade) }
    }

    private func toggle(_ trade: Trade) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selected.contains(trade) { selected.remove(trade) } else { selected.insert(trade) }
        }
    }
}

// MARK: - O3 · Severity (scroll-driven parallax)

private struct SeverityPage: View {
    @Binding var palette: SeverityPalette
    @State private var offset: CGFloat = 0

    var body: some View {
        ScrollView {
            ZStack(alignment: .top) {
                // Parallax background glyphs
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 150, weight: .bold))
                    .foregroundColor(palette.color(for: .critical).opacity(0.10))
                    .offset(x: 90, y: -offset * 0.5 + 10)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 110, weight: .bold))
                    .foregroundColor(palette.color(for: .major).opacity(0.10))
                    .offset(x: -110, y: -offset * 0.3 + 60)

                VStack(spacing: Theme.Space.l) {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ScrollOffsetKey.self,
                                               value: proxy.frame(in: .named("sevscroll")).minY)
                    }.frame(height: 0)

                    header("Set the severity scale", "Three levels drive priority and color across the app")

                    // Live preview of the three severity chips
                    HStack(spacing: 10) {
                        ForEach(Severity.allCases) { sev in
                            VStack(spacing: 6) {
                                Image(systemName: sev.icon).font(.system(size: 22, weight: .bold))
                                    .foregroundColor(palette.color(for: sev))
                                Text(sev.displayName).font(Theme.caption(11)).foregroundColor(Theme.textPrimary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(palette.color(for: sev).opacity(0.14)))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).stroke(palette.color(for: sev).opacity(0.4), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, Theme.Space.l)

                    CardView {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: "Color palette", systemImage: "paintpalette.fill")
                            Picker("", selection: $palette) {
                                ForEach(SeverityPalette.allCases) { Text($0.displayName).tag($0) }
                            }.pickerStyle(SegmentedPickerStyle())
                        }
                    }
                    .padding(.horizontal, Theme.Space.l)

                    Spacer(minLength: 70)
                }
            }
        }
        .coordinateSpace(name: "sevscroll")
        .onPreferenceChange(ScrollOffsetKey.self) { offset = $0 }
    }
}

// MARK: - O4 · Handover date (long-press hold-to-lock)

private struct HandoverPage: View {
    @Binding var handoverDate: Date
    @State private var holdProgress: CGFloat = 0
    @State private var locked = false

    private let presets: [(String, Int)] = [("2 weeks", 14), ("1 month", 30), ("2 months", 60), ("3 months", 90)]

    var body: some View {
        VStack(spacing: Theme.Space.l) {
            header("When is handover?", "Sets the deadline for fixing every snag")

            CardView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    HStack {
                        Image(systemName: "calendar").foregroundColor(Theme.accent)
                        DatePicker("", selection: $handoverDate, in: Date()..., displayedComponents: .date)
                            .labelsHidden()
                            .accentColor(Theme.accent)
                            .onChange(of: handoverDate) { _ in locked = false }
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.0) { p in
                            Button(p.0) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    handoverDate = Calendar.current.date(byAdding: .day, value: p.1, to: Date()) ?? Date()
                                    locked = false
                                }
                            }
                            .font(Theme.caption(11))
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(Capsule().fill(Theme.accent.opacity(0.14)))
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.Space.l)

            // Hold-to-lock ring (the unique gesture for this page)
            VStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Theme.stroke, lineWidth: 8).frame(width: 96, height: 96)
                    Circle()
                        .trim(from: 0, to: locked ? 1 : holdProgress)
                        .stroke(locked ? Theme.closed : Theme.accent,
                                style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 96, height: 96)
                    Image(systemName: locked ? "lock.fill" : "hand.tap.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(locked ? Theme.closed : Theme.accent)
                }
                .onLongPressGesture(minimumDuration: 0.8, maximumDistance: 40, pressing: { pressing in
                    withAnimation(.linear(duration: pressing ? 0.8 : 0.2)) { holdProgress = pressing ? 1 : 0 }
                }, perform: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { locked = true }
                })

                Text(locked ? "Locked · \(Formatters.date(handoverDate))" : "Press & hold to lock the date")
                    .font(Theme.caption(12))
                    .foregroundColor(locked ? Theme.closed : Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Shared page header

private func header(_ title: String, _ subtitle: String) -> some View {
    VStack(spacing: 6) {
        Text(title).font(Theme.title(27)).multilineTextAlignment(.center)
            .foregroundColor(Theme.textPrimary)
        Text(subtitle).font(Theme.caption(13)).foregroundColor(Theme.textSecondary)
            .multilineTextAlignment(.center)
    }
    .padding(.horizontal, Theme.Space.l)
    .padding(.top, Theme.Space.l)
}
