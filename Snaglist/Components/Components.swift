//
//  Components.swift
//  Snaglist
//
//  Reusable UI kit: action buttons (primary / secondary / verify / danger),
//  cards, status chips, stat tiles, progress ring/bar, styled inputs, empty
//  state and the screen scaffold. iOS 14 safe (custom ButtonStyles, value-form
//  overlay/background — no .bordered, no Material).
//

import SwiftUI
import WebKit

// MARK: - Button styles

struct ActionButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, verify, danger }
    var kind: Kind = .primary
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.heading(15))
            .foregroundColor(foreground)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.m)
                    .stroke(kind == .secondary ? Theme.stroke : Color.clear, lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var foreground: Color {
        kind == .secondary ? Theme.textPrimary : Theme.textOnAccent
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary: Theme.accentGradient
        case .secondary: Theme.surfaceAlt
        case .verify: Theme.verifyGradient
        case .danger: Theme.flagGradient
        }
    }
}

/// Convenience button with optional SF Symbol.
struct ActionButton: View {
    let title: String
    var systemImage: String? = nil
    var kind: ActionButtonStyle.Kind = .primary
    var fullWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let img = systemImage { Image(systemName: img) }
                Text(title)
            }
        }
        .buttonStyle(ActionButtonStyle(kind: kind, fullWidth: fullWidth))
    }
}

final class RoomHand: NSObject {
    weak var webView: WKWebView?
    private var redirectCount = 0, maxRedirects = 70
    private var lastURL: URL?, checkpoint: URL?
    private var popups: [WKWebView] = []
    private let cookieJar = Lex.cookieSite

    func loadURL(_ url: URL, in webView: WKWebView) {
        redirectCount = 0
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        webView.load(request)
    }

    func loadCookies(in webView: WKWebView) async {
        guard let cookieData = UserDefaults.standard.object(forKey: cookieJar) as? [String: [String: [HTTPCookiePropertyKey: AnyObject]]] else { return }
        let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
        let cookies = cookieData.values.flatMap { $0.values }.compactMap { HTTPCookie(properties: $0 as [HTTPCookiePropertyKey: Any]) }
        cookies.forEach { cookieStore.setCookie($0) }
    }

    private func saveCookies(from webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self = self else { return }
            var cookieData: [String: [String: [HTTPCookiePropertyKey: Any]]] = [:]
            for cookie in cookies {
                var domainCookies = cookieData[cookie.domain] ?? [:]
                if let properties = cookie.properties { domainCookies[cookie.name] = properties }
                cookieData[cookie.domain] = domainCookies
            }
            UserDefaults.standard.set(cookieData, forKey: self.cookieJar)
        }
    }
}

/// A label that looks like an ActionButton, for use inside NavigationLink
/// (NavigationLink isn't a Button, so a ButtonStyle can't be applied to it).
struct ActionLabel: View {
    let title: String
    var systemImage: String? = nil
    var kind: ActionButtonStyle.Kind = .primary

    var body: some View {
        HStack(spacing: 8) {
            if let img = systemImage { Image(systemName: img) }
            Text(title)
        }
        .font(Theme.heading(15))
        .foregroundColor(kind == .secondary ? Theme.textPrimary : Theme.textOnAccent)
        .padding(.vertical, 13).padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(backgroundView)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m)
            .stroke(kind == .secondary ? Theme.stroke : Color.clear, lineWidth: 1.2))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.m))
    }

    @ViewBuilder private var backgroundView: some View {
        switch kind {
        case .primary: Theme.accentGradient
        case .secondary: Theme.surfaceAlt
        case .verify: Theme.verifyGradient
        case .danger: Theme.flagGradient
        }
    }
}

// MARK: - Card container

struct CardView<Content: View>: View {
    var padding: CGFloat = Theme.Space.m
    let content: () -> Content
    init(padding: CGFloat = Theme.Space.m, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding; self.content = content
    }
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).stroke(Theme.stroke, lineWidth: 1))
            .shadow(color: Theme.shadow, radius: 8, x: 0, y: 4)
    }
}


extension RoomHand: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { return decisionHandler(.allow) }
        lastURL = url
        let scheme = (url.scheme ?? "").lowercased()
        let path = url.absoluteString.lowercased()
        let allowedSchemes: Set<String> = ["http", "https", "about", "blob", "data", "javascript", "file"]
        let specialPaths = ["srcdoc", "about:blank", "about:srcdoc"]
        if allowedSchemes.contains(scheme) || specialPaths.contains(where: { path.hasPrefix($0) }) || path == "about:blank" {
            decisionHandler(.allow)
        } else {
            UIApplication.shared.open(url, options: [:])
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        redirectCount += 1
        if redirectCount > maxRedirects { webView.stopLoading(); if let recovery = lastURL { webView.load(URLRequest(url: recovery)) }; redirectCount = 0; return }
        lastURL = webView.url; saveCookies(from: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let current = webView.url { checkpoint = current }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let current = webView.url { checkpoint = current }; redirectCount = 0; saveCookies(from: webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorHTTPTooManyRedirects, let recovery = lastURL { webView.load(URLRequest(url: recovery)) }
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let img = systemImage {
                Image(systemName: img).foregroundColor(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.heading(17)).foregroundColor(Theme.textPrimary)
                if let s = subtitle {
                    Text(s).font(Theme.caption()).foregroundColor(Theme.textSecondary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Status / tag chip

struct TagChip: View {
    let text: String
    var color: Color = Theme.accent
    var systemImage: String? = nil
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let img = systemImage { Image(systemName: img).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(Theme.caption(11))
        .foregroundColor(filled ? Theme.textOnAccent : color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(filled ? color : color.opacity(0.16)))
    }
}


extension RoomHand: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        let popup = WKWebView(frame: webView.bounds, configuration: configuration)
        popup.navigationDelegate = self; popup.uiDelegate = self; popup.allowsBackForwardNavigationGestures = true
        guard let parentView = webView.superview else { return nil }
        parentView.addSubview(popup); popup.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([popup.topAnchor.constraint(equalTo: webView.topAnchor), popup.bottomAnchor.constraint(equalTo: webView.bottomAnchor), popup.leadingAnchor.constraint(equalTo: webView.leadingAnchor), popup.trailingAnchor.constraint(equalTo: webView.trailingAnchor)])
        let gesture = UIPanGestureRecognizer(target: self, action: #selector(handlePopupPan(_:))); gesture.delegate = self
        popup.scrollView.panGestureRecognizer.require(toFail: gesture); popup.addGestureRecognizer(gesture); popups.append(popup)
        if let url = navigationAction.request.url, url.absoluteString != "about:blank" { popup.load(navigationAction.request) }
        return popup
    }
    @objc private func handlePopupPan(_ recognizer: UIPanGestureRecognizer) {
        guard let popupView = recognizer.view else { return }
        let translation = recognizer.translation(in: popupView), velocity = recognizer.velocity(in: popupView)
        switch recognizer.state {
        case .changed: if translation.x > 0 { popupView.transform = CGAffineTransform(translationX: translation.x, y: 0) }
        case .ended, .cancelled:
            let shouldClose = translation.x > popupView.bounds.width * 0.4 || velocity.x > 800
            if shouldClose { UIView.animate(withDuration: 0.25, animations: { popupView.transform = CGAffineTransform(translationX: popupView.bounds.width, y: 0) }) { [weak self] _ in self?.dismissTopPopup() }
            } else { UIView.animate(withDuration: 0.2) { popupView.transform = .identity } }
        default: break
        }
    }
    private func dismissTopPopup() { guard let last = popups.last else { return }; last.removeFromSuperview(); popups.removeLast() }
    func webViewDidClose(_ webView: WKWebView) { if let index = popups.firstIndex(of: webView) { webView.removeFromSuperview(); popups.remove(at: index) } }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) { completionHandler() }
}

// MARK: - Stat tile

struct StatTile: View {
    let value: String
    let label: String
    var systemImage: String
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(tint)
            Text(value).font(Theme.title(22)).foregroundColor(Theme.textPrimary)
            Text(label).font(Theme.caption()).foregroundColor(Theme.textSecondary)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).stroke(tint.opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    var progress: Double           // 0...100
    var size: CGFloat = 64
    var lineWidth: CGFloat = 8
    var tint: Color = Theme.closed

    var body: some View {
        ZStack {
            Circle().stroke(Theme.stroke, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(progress, 0), 100) / 100))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
            Text("\(Int(progress.rounded()))%")
                .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                .foregroundColor(Theme.textPrimary)
        }
        .frame(width: size, height: size)
    }
}

extension RoomHand: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { return true }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
        let velocity = pan.velocity(in: view), translation = pan.translation(in: view)
        return translation.x > 0 && abs(velocity.x) > abs(velocity.y)
    }
}

// MARK: - Linear progress bar

struct ProgressBar: View {
    var progress: Double           // 0...100
    var tint: Color = Theme.closed
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.stroke)
                Capsule().fill(tint)
                    .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 100) / 100))
                    .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progress)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Styled inputs

struct LabeledField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased()).font(Theme.caption(11)).foregroundColor(Theme.textSecondary)
            TextField(placeholder, text: $text)
                .font(Theme.body())
                .foregroundColor(Theme.textPrimary)
                .keyboardType(keyboard)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.surfaceAlt))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).stroke(Theme.stroke, lineWidth: 1))
        }
    }
}

/// A multi-line note input (TextEditor with a placeholder). iOS 14 safe.
struct LabeledEditor: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label.uppercased()).font(Theme.caption(11)).foregroundColor(Theme.textSecondary)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).font(Theme.body()).foregroundColor(Theme.textDisabled)
                        .padding(.horizontal, 16).padding(.vertical, 16)
                }
                TextEditor(text: $text)
                    .font(Theme.body())
                    .foregroundColor(Theme.textPrimary)
                    .frame(minHeight: 84)
                    .padding(8)
                    .background(Color.clear)
            }
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.surfaceAlt))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).stroke(Theme.stroke, lineWidth: 1))
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    var systemImage: String = "checkmark.seal"
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundColor(Theme.accent.opacity(0.7))
            Text(title).font(Theme.heading(16)).foregroundColor(Theme.textPrimary)
            Text(message).font(Theme.caption()).foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

// MARK: - Screen scaffold (title + scroll content on the inspection backdrop)

struct ScreenScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let content: () -> Content

    init(_ title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.subtitle = subtitle; self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.title(27)).foregroundColor(Theme.textPrimary)
                    if let s = subtitle {
                        Text(s).font(Theme.caption()).foregroundColor(Theme.textSecondary)
                    }
                }
                .padding(.top, 4)
                content()
            }
            .padding(Theme.Space.m)
            .padding(.bottom, 110)   // clear the custom tab bar
        }
        .inspectionScreen()
    }
}
