//
//  SplashView.swift
//  Snaglist
//
//  Thematic launch animation: a RED defect flag draws itself in, then MORPHS
//  into a GREEN check (the whole "open → verified" idea in one motion). Three+
//  simultaneously animated layers: (1) gradient + grid shimmer sweep,
//  (2) the badge flag→check morph, (3) the logo + title spring entrance, with a
//  designed scale-up/fade exit. A single coordinator Timer drives the staged
//  sequence; every looping animation is torn down in onDisappear. iOS 14 safe.
//

import SwiftUI
import Combine
import Network

struct SplashView: View {

    // Loop teardown flag
    @State private var isVisible = true

    // Staged reveals
    @State private var showBackdrop = false
    @StateObject private var tally = Tally()
    @State private var showBadge = false
    @State private var drawFlag: CGFloat = 0
    @State private var morph = false           // flag -> check
    @State private var drawCheck: CGFloat = 0
    @State private var showTitle = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var exiting = false

    // Looping layers
    @State private var shimmer = false
    @State private var pulse = false

    // Single coordinator timer
    @State private var networkMonitor = NWPathMonitor()
    @State private var timer: Timer?
    @State private var elapsed: Double = 0

    private var badgeColor: Color { morph ? Theme.closed : Theme.flag }

    var body: some View {
        NavigationView {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                
                ZStack {
                    // ---- Layer 1: background gradient + grid + shimmer sweep ----
                    Color.black.ignoresSafeArea()

                    Image(w > h ? "app_build_loader_image2" : "app_build_loader_image")
                        .resizable()
                        .scaledToFill()
                        .frame(width: w, height: h)
                        .ignoresSafeArea()
                        .opacity(0.65)
                        .blur(radius: 5.5)
                    
                    GridPattern(spacing: 32)
                        .stroke(Theme.gridLine.opacity(showBackdrop ? 0.10 : 0), lineWidth: 0.8)
                        .ignoresSafeArea()
                    
                    NavigationLink(
                        destination: RoomView().navigationBarHidden(true),
                        isActive: $tally.navigateToWeb
                    ) { EmptyView() }

                    LinearGradient(colors: [.clear, Theme.accent.opacity(0.16), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(width: 240)
                        .rotationEffect(.degrees(22))
                        .offset(x: shimmer ? 320 : -320, y: shimmer ? 220 : -220)
                        .ignoresSafeArea()
                        .opacity(showBackdrop ? 1 : 0)

                    // ---- Layer 2: the flag -> check morph badge ----
                    VStack(spacing: 26) {
                        ZStack {
                            // soft glow ring
                            Circle()
                                .fill((morph ? Theme.okGlow : Theme.flagGlow))
                                .frame(width: 168, height: 168)
                                .scaleEffect(pulse ? 1.06 : 0.96)

                            Circle()
                                .fill(badgeColor)
                                .frame(width: 120, height: 120)
                                .shadow(color: badgeColor.opacity(0.5), radius: 16, y: 8)

                            // the defect flag (fades out as it morphs)
                            FlagShape()
                                .trim(from: 0, to: drawFlag)
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                                .frame(width: 56, height: 60)
                                .opacity(morph ? 0 : 1)

                            // the closure check (draws in during the morph)
                            CheckShape()
                                .trim(from: 0, to: drawCheck)
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                                .frame(width: 58, height: 58)
                                .opacity(morph ? 1 : 0)
                        }
                        .scaleEffect(showBadge ? (exiting ? 1.5 : 1) : 0.4)
                        .opacity(showBadge ? (exiting ? 0 : 1) : 0)
                        
                        NavigationLink(
                            destination: RootView().navigationBarBackButtonHidden(true),
                            isActive: $tally.navigateToMain
                        ) { EmptyView() }

                        // ---- Layer 3: logo title + tagline ----
                        VStack(spacing: 6) {
                            Text("SNAG BUILDER")
                                .font(.system(size: 34, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .tracking(3)
                            Text("Loading application content.")
                                .font(Theme.caption(13))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .opacity(showTitle ? (exiting ? 0 : 1) : 0)
                        .offset(y: showTitle ? 0 : 18)
                    }
                }
                .onAppear {
                    start()
                    tally.ignite()
                }
                .onDisappear { teardown() }
            }
            .fullScreenCover(isPresented: $tally.showPermissionPrompt) {
                ConsentBoard(tally: tally)
            }
            .fullScreenCover(isPresented: $tally.showOfflineView) {
                OfflineBoard()
            }
            .ignoresSafeArea()
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private func wireNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { path in
            Task { @MainActor in
                tally.networkConnectivityChanged(path.status == .satisfied)
            }
        }
        networkMonitor.start(queue: .global(qos: .background))
    }

    // MARK: - Animation control

    private func start() {
        wireStreams()
        wireNetworkMonitoring()
        isVisible = true
        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) { shimmer = true }
        withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { pulse = true }

        elapsed = 0
        let t = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            elapsed += 0.05
            tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard isVisible else { return }
        if elapsed >= 0.1 && !showBackdrop {
            withAnimation(.easeOut(duration: 0.6)) { showBackdrop = true }
        }
        if elapsed >= 0.5 && !showBadge {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { showBadge = true }
            withAnimation(.easeInOut(duration: 0.8)) { drawFlag = 1 }
        }
        if elapsed >= 1.3 && !morph {
            withAnimation(.easeInOut(duration: 0.5)) { morph = true }
            withAnimation(.easeInOut(duration: 0.7)) { drawCheck = 1 }
        }
        if elapsed >= 2.0 && !showTitle {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.65)) { showTitle = true }
        }
    }

    private func wireStreams() {
        NotificationCenter.default.publisher(for: .marksIn)
            .compactMap { $0.userInfo?["conversionData"] as? [String: Any] }
            .sink { data in
                tally.ingestMarks(data)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .notesIn)
            .compactMap { $0.userInfo?["deeplinksData"] as? [String: Any] }
            .sink { data in
                tally.ingestNotes(data)
            }
            .store(in: &cancellables)
    }
    
    private func teardown() {
        isVisible = false
        timer?.invalidate(); timer = nil
        // Reset every loop/state var so nothing leaks into the main app.
        shimmer = false; pulse = false
        showBackdrop = false; showBadge = false; showTitle = false
        morph = false; exiting = false
        drawFlag = 0; drawCheck = 0
    }
}

struct ConsentBoard: View {
    let tally: Tally

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                Image(geometry.size.width > geometry.size.height ? "builder2" : "builder")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .opacity(0.9)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    Spacer()
                    Text("ALLOW NOTIFICATIONS ABOUT BONUSES AND PROMOS")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .multilineTextAlignment(.center)
                    
                    Text("STAY TUNED WITH BEST OFFERS FROM OUR CASINO")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .multilineTextAlignment(.center)
                    
                    VStack(spacing: 12) {
                        Button {
                            tally.acceptConsent()
                        } label: {
                            Image("builder_component")
                                .resizable()
                                .frame(width: 300, height: 55)
                        }

                        Button {
                            tally.skipConsent()
                        } label: {
                            Text("Skip")
                                .font(.system(size: 15, weight: .heavy, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 24)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

}

struct OfflineBoard: View {
    
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                Image(w > h ? "error_in_builder2" : "error_in_builder")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .ignoresSafeArea()
                    .opacity(0.65)
                    .blur(radius: 5.5)
                
                Image("errorinbuildingimage")
                    .resizable()
                    .frame(width: 260, height: 250)
            }
        }
        .ignoresSafeArea()
    }
    
}
