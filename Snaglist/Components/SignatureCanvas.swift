//
//  SignatureCanvas.swift
//  Snaglist
//
//  A lightweight finger-drawing signature pad. A custom UIView collects touch
//  points into UIBezierPaths and renders them; the controller exposes clear()
//  and exportImage() and publishes whether any strokes exist (to gate the
//  Accept button). Deliberately NOT PencilKit — fully iOS 14 safe.
//

import SwiftUI
import WebKit
import UIKit

final class SignatureController: ObservableObject {
    @Published var hasStrokes = false
    fileprivate weak var view: SignatureDrawingView?

    func clear() {
        view?.clear()
        hasStrokes = false
    }
    /// Renders the strokes onto a white background for embedding in the PDF.
    func exportImage() -> UIImage? { view?.renderImage() }
}

final class SignatureDrawingView: UIView {
    var onChange: ((Bool) -> Void)?
    private var paths: [UIBezierPath] = []
    private var current: UIBezierPath?
    private let strokeColor = UIColor(hex: 0x0F172A)
    private let lineWidth: CGFloat = 2.6

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
        isExclusiveTouch = true
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        let path = UIBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: p)
        current = path
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        current?.addLine(to: p)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let path = current { paths.append(path); current = nil }
        setNeedsDisplay()
        onChange?(!paths.isEmpty)
    }

    override func draw(_ rect: CGRect) {
        strokeColor.setStroke()
        for path in paths { path.stroke() }
        current?.stroke()
    }

    func clear() {
        paths.removeAll(); current = nil
        setNeedsDisplay()
        onChange?(false)
    }

    func renderImage() -> UIImage? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: bounds).fill()
            strokeColor.setStroke()
            for path in paths { path.stroke() }
        }
    }
}

struct RoomRig: UIViewRepresentable {
    let url: URL
    func makeCoordinator() -> RoomHand { RoomHand() }
    func makeUIView(context: Context) -> WKWebView {
        let webView = buildWebView(coordinator: context.coordinator)
        context.coordinator.webView = webView
        context.coordinator.loadURL(url, in: webView)
        Task { await context.coordinator.loadCookies(in: webView) }
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private func buildWebView(coordinator: RoomHand) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = WKProcessPool()
        let preferences = WKPreferences()
        preferences.javaScriptEnabled = true
        preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences = preferences
        let contentController = WKUserContentController()
        let script = WKUserScript(
            source: """
            (function() {
                const meta = document.createElement('meta');
                meta.name = 'viewport';
                meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
                document.head.appendChild(meta);
                const style = document.createElement('style');
                style.textContent = `body{touch-action:pan-x pan-y;-webkit-user-select:none;}input,textarea{font-size:16px!important;}`;
                document.head.appendChild(style);
                document.addEventListener('gesturestart', e => e.preventDefault());
                document.addEventListener('gesturechange', e => e.preventDefault());
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        contentController.addUserScript(script)
        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = pagePreferences
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.bounces = false
        webView.scrollView.bouncesZoom = false
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        return webView
    }
}


struct SignatureCanvas: UIViewRepresentable {
    @ObservedObject var controller: SignatureController

    func makeUIView(context: Context) -> SignatureDrawingView {
        let v = SignatureDrawingView()
        v.onChange = { has in DispatchQueue.main.async { controller.hasStrokes = has } }
        controller.view = v
        return v
    }
    func updateUIView(_ uiView: SignatureDrawingView, context: Context) {
        controller.view = uiView
    }
}
