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

/// Estado del reproductor y control remoto del WebView vía JavaScript.
///
/// Lee de la página la metadata de la pista en curso (portada, título, artista)
/// y el estado de reproducción, y envía comandos de media (play/pausa,
/// siguiente, anterior). Es la fuente de verdad que alimenta el mini reproductor.
@MainActor
@Observable
final class WebPlayerController {
    /// Título de la canción actual.
    var title: String = ""
    /// Artista / línea secundaria de la canción actual.
    var artist: String = ""
    /// URL de la portada del álbum (la de mayor resolución disponible).
    var artworkURL: URL?
    /// `true` si hay reproducción en curso.
    var isPlaying: Bool = false
    /// Posición actual de reproducción, en segundos.
    var currentTime: Double = 0
    /// Duración total de la pista, en segundos.
    var duration: Double = 0
    /// Volumen actual (0…1).
    var volume: Double = 1

    /// WebView controlado. Débil: lo retiene SwiftUI mientras está montado.
    weak var webView: WKWebView?

    /// Alterna reproducción/pausa sobre el elemento `<video>` de la página.
    func togglePlayPause() {
        evaluate("(function(){var v=document.querySelector('video');if(!v)return;if(v.paused)v.play();else v.pause();})();")
    }

    /// Salta a la siguiente pista (botón del player bar de Music o del reproductor de vídeos).
    func next() {
        evaluate("(function(){var b=document.querySelector('ytmusic-player-bar .next-button, .ytp-next-button');if(b)b.click();})();")
    }

    /// Vuelve a la pista anterior.
    func previous() {
        evaluate("(function(){var b=document.querySelector('ytmusic-player-bar .previous-button, .ytp-prev-button');if(b)b.click();})();")
    }

    /// Salta a una posición de la pista (en segundos).
    func seek(to seconds: Double) {
        evaluate("(function(){var v=document.querySelector('video');if(v)v.currentTime=\(seconds);})();")
    }

    /// Ajusta el volumen (0…1) sobre el elemento `<video>`.
    func setVolume(_ value: Double) {
        let v = min(max(value, 0), 1)
        evaluate("(function(){var v=document.querySelector('video');if(v){v.volume=\(v);v.muted=false;}})();")
    }

    private func evaluate(_ js: String) {
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

    /// Actualiza el estado a partir del mensaje enviado por el JS inyectado.
    func update(with body: [String: Any]) {
        title = body["title"] as? String ?? ""
        artist = body["artist"] as? String ?? ""
        isPlaying = body["isPlaying"] as? Bool ?? false
        currentTime = body["currentTime"] as? Double ?? 0
        duration = body["duration"] as? Double ?? 0
        // El volumen NO se lee de vuelta: el slider de la app es la fuente de
        // verdad. YouTube Music reajusta `video.volume` por su cuenta, así que
        // leerlo haría que el control saltara a otro valor al reabrirlo.
        if let s = body["artwork"] as? String, !s.isEmpty, let url = URL(string: s) {
            artworkURL = url
        } else {
            artworkURL = nil
        }
    }
}

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

    /// Estado y control del reproductor (mini reproductor + comandos de media).
    let player: WebPlayerController

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

    // Reporta a Swift la metadata de la pista y el estado de reproducción, para
    // alimentar el mini reproductor. Usa la MediaSession API (título, artista y
    // portada) y el elemento <video> (play/pausa). Solo emite cuando algo cambia.
    private static let reportStateJS = """
    (function() {
        function pickArtwork(md) {
            if (!md || !md.artwork || !md.artwork.length) return '';
            var best = md.artwork[0], bestW = 0;
            for (var i = 0; i < md.artwork.length; i++) {
                var a = md.artwork[i], w = 0;
                if (a.sizes) { w = parseInt(a.sizes.split('x')[0], 10) || 0; }
                if (w >= bestW) { bestW = w; best = a; }
            }
            return best.src || '';
        }
        function state() {
            var md = navigator.mediaSession && navigator.mediaSession.metadata;
            var v = document.querySelector('video');
            return {
                title: md ? md.title : '',
                artist: md ? md.artist : '',
                artwork: pickArtwork(md),
                isPlaying: v ? !v.paused : false,
                currentTime: v ? v.currentTime : 0,
                duration: v ? (v.duration || 0) : 0,
                volume: v ? v.volume : 1
            };
        }
        var last = '';
        function report() {
            try {
                var s = state();
                var key = JSON.stringify(s);
                if (key !== last) {
                    last = key;
                    window.webkit.messageHandlers.player.postMessage(s);
                }
            } catch (e) {}
        }
        setInterval(report, 500);
        document.addEventListener('play', report, true);
        document.addEventListener('pause', report, true);
    })();
    """

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // cookies persistentes y compartidas
        config.mediaTypesRequiringUserActionForPlayback = [] // permite autoplay
        // Sin esto, YouTube muestra "Full screen is unavailable" en el botón de
        // pantalla completa (API Fullscreen de HTML5 / Element.requestFullscreen).
        config.preferences.isElementFullscreenEnabled = true

        // Inyecta las mejoras propias sobre la página.
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: Self.expandControlsJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: Self.reportStateJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        // Canal JS → Swift para la metadata y el estado de reproducción.
        controller.add(context.coordinator, name: "player")
        config.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = Self.safariUserAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.startObserving(webView)
        player.webView = webView
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: YouTubeWebView
        /// Reproductor a alimentar con los mensajes JS (referencia estable).
        let player: WebPlayerController
        /// Último servicio cargado; evita recargas innecesarias.
        var currentMode: ServiceMode?
        /// Observa el progreso real de la carga del WebView.
        private var progressObservation: NSKeyValueObservation?

        init(_ parent: YouTubeWebView) {
            self.parent = parent
            self.player = parent.player
        }

        // MARK: Canal JS → Swift

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "player",
                  let body = message.body as? [String: Any] else { return }
            let player = player
            Task { @MainActor in player.update(with: body) }
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
