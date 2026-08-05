//
//  YouTubeWebView.swift
//  YT music
//
//  WKWebView que envuelve YouTube. Puede mostrar YouTube Music o YouTube (videos)
//  según el `mode`. Ambos comparten la misma sesión de Google (mismo almacén de
//  cookies), así que alternar NO requiere volver a iniciar sesión.
//
//  Reporta `isLoading` y el `progress` real (0…1) de la carga para alimentar la
//  barra de progreso estilo YouTube.
//

import SwiftUI
import WebKit

/// Los dos servicios entre los que alterna la app.
enum ServiceMode: String, CaseIterable, Identifiable {
    case music
    case videos

    var id: String { rawValue }

    var url: URL {
        switch self {
        case .music:  return URL(string: "https://music.youtube.com")!
        case .videos: return URL(string: "https://www.youtube.com")!
        }
    }

    var label: String {
        switch self {
        case .music:  return "Music"
        case .videos: return "Youtube"
        }
    }
}

struct YouTubeWebView: NSViewRepresentable {

    /// Servicio actualmente mostrado. Al cambiarlo, el WebView navega al otro.
    let mode: ServiceMode

    /// `true` mientras carga una página; `false` al terminar.
    @Binding var isLoading: Bool

    /// Progreso real de la carga, de 0 a 1.
    @Binding var progress: Double

    // User-Agent de Safari en macOS: evita el bloqueo de login de Google y
    // sirve la versión completa (de escritorio) de ambos sitios.
    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 " +
        "(KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    // Funcionalidad especial (inyección de JS): en YouTube Music, hace clic en el
    // `.expand-button` del player bar para dejar los controles (volumen, etc.)
    // siempre extendidos. Reintenta hasta que el reproductor aparece (es un SPA).
    private static let expandControlsJS = """
    (function() {
        if (!location.hostname.includes('music.youtube.com')) return;
        var done = false;
        function tryExpand() {
            if (done) return true;
            var bar = document.querySelector('ytmusic-player-bar');
            if (!bar) return false;
            var btn = bar.querySelector('.expand-button');
            if (!btn) return false;
            btn.click();
            done = true;
            return true;
        }
        var tries = 0;
        var timer = setInterval(function() {
            tries += 1;
            if (tryExpand() || tries > 60) clearInterval(timer);
        }, 500);
    })();
    """

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // cookies persistentes y compartidas
        config.mediaTypesRequiringUserActionForPlayback = [] // permite autoplay

        // Inyecta las mejoras propias sobre la página.
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: Self.expandControlsJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.safariUserAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.startObserving(webView)
        webView.load(URLRequest(url: mode.url))
        context.coordinator.currentMode = mode
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        // Solo recarga cuando el usuario realmente cambió de servicio.
        guard context.coordinator.currentMode != mode else { return }
        context.coordinator.currentMode = mode
        webView.load(URLRequest(url: mode.url))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: YouTubeWebView
        /// Último servicio cargado; evita recargas innecesarias.
        var currentMode: ServiceMode?
        /// Observa el progreso real de la carga del WebView.
        private var progressObservation: NSKeyValueObservation?

        init(_ parent: YouTubeWebView) {
            self.parent = parent
        }

        /// Empieza a observar `estimatedProgress` para alimentar la barra.
        func startObserving(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
                guard let value = change.newValue else { return }
                Task { @MainActor in self?.parent.progress = value }
            }
        }

        // MARK: Estado de carga

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.progress = 1.0
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }

        // MARK: Popups

        // Enlaces con target="_blank" → cargarlos en la misma vista.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
    }
}
