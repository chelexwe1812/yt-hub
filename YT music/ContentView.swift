//
//  ContentView.swift
//  YT music
//
//  Ventana raíz: reproductor de YouTube a pantalla completa (sin barra de
//  título, vía .windowStyle(.hiddenTitleBar) en la App). Arriba a la izquierda,
//  junto a los botones de la ventana, un switch con efecto Liquid Glass alterna
//  entre YouTube Music y YouTube (videos).
//

import SwiftUI

struct ContentView: View {
    @State private var mode: ServiceMode = .music
    @State private var isLoading = true
    @State private var progress: Double = 0
    /// Reproductor compartido: alimenta el mini reproductor y envía comandos.
    @State private var player = WebPlayerController()
    /// `true` cuando la interfaz está colapsada en el mini reproductor.
    @State private var isMini = false

    /// Lado del mini reproductor (ventana cuadrada con la portada).
    private let miniSize: CGFloat = 300
    /// Mínimo del contenido en modo Videos: la interfaz completa de YouTube
    /// necesita este ancho para que nuestros controles superpuestos no colisionen
    /// con los suyos.
    private let videosMinSize = CGSize(width: 1340, height: 860)
    /// Mínimo del contenido en modo Música, medido sobre la ventana de referencia.
    private let musicMinSize = CGSize(width: 1120, height: 770)
    /// Tamaño de apertura por defecto en modo grande (≥ mínimo activo).
    private let fullSize = CGSize(width: 1360, height: 880)

    /// Mínimo de ventana según el modo actual.
    private var activeMinSize: CGSize { mode == .videos ? videosMinSize : musicMinSize }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // El WebView vive siempre en la ventana principal. Al pasar al mini,
            // esta ventana se OCULTA (no se cierra), así el audio no se interrumpe.
            YouTubeWebView(mode: mode, player: player, isLoading: $isLoading, progress: $progress)

            if isLoading {
                LoadingView(progress: progress)
                    .transition(.opacity)
            } else {
                // Controles superpuestos sobre el contenido. El switch reaparece en
                // distinta posición según el modo para no chocar con la interfaz de YouTube.
                ServiceSwitch(mode: $mode)
                    .padding(.top, mode == .videos ? 13 : 17)
                    .padding(mode == .videos ? .leading : .trailing,
                             mode == .videos ? 205 : 150)
                    .frame(maxWidth: .infinity,
                           alignment: mode == .videos ? .leading : .trailing)
                    .transition(.opacity)

                // Botón para colapsar al mini reproductor, arriba a la derecha.
                if mode == .music {
                    collapseButton
                        .padding(.top, 17)
                        .padding(.trailing, 16)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.opacity)
                }
            }
        }
        .frame(minWidth: activeMinSize.width, maxWidth: .infinity,
               minHeight: activeMinSize.height, maxHeight: .infinity)
        // Gestiona la ventana principal y la ventana independiente del mini reproductor.
        .background(WindowManager(isMini: isMini, miniSize: miniSize, player: player,
                                  onExpand: { isMini = false },
                                  fullMinSize: activeMinSize, fullSize: fullSize))
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .onChange(of: mode) {
            progress = 0
            isLoading = true
        }
    }

    /// Botón de vidrio que abre el mini reproductor (oculta esta ventana).
    private var collapseButton: some View {
        Button {
            isMini = true
        } label: {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(3)
        .glassEffect(.clear.interactive())
    }
}

/// Gestiona las DOS ventanas de la app:
///
/// · **Principal** (la del `WindowGroup`): aloja el `WKWebView`. Oculta el texto
///   del título, aplica el tamaño mínimo según el modo y, al crecer por un cambio
///   de modo, se mantiene dentro de la pantalla.
/// · **Mini**: una ventana APARTE, sin barra de título (borderless), cuadrada, no
///   redimensionable, con esquinas redondeadas y sombra. Muestra la portada
///   (`MiniPlayerView`) y tiene su propia posición, independiente de la principal
///   (estilo Apple Music).
///
/// Al entrar en mini se oculta la principal (el WebView sigue vivo → el audio no
/// se corta) y se muestra la mini; al salir, a la inversa.
private struct WindowManager: NSViewRepresentable {
    var isMini: Bool
    var miniSize: CGFloat
    var player: WebPlayerController
    var onExpand: () -> Void
    var fullMinSize: CGSize
    var fullSize: CGSize

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let isMini = isMini
        let miniSize = miniSize
        let player = player
        let onExpand = onExpand
        let fullMinSize = fullMinSize
        let fullSize = fullSize
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let mainWindow = nsView.window else { return }

            // --- Ventana principal ---
            mainWindow.titleVisibility = .hidden
            mainWindow.level = .normal
            mainWindow.styleMask.remove(.fullSizeContentView)
            mainWindow.titlebarAppearsTransparent = false
            mainWindow.isMovableByWindowBackground = false
            mainWindow.styleMask.insert(.resizable)
            for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                mainWindow.standardWindowButton(button)?.isHidden = false
            }
            mainWindow.contentMinSize = NSSize(width: fullMinSize.width, height: fullMinSize.height)
            mainWindow.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                               height: CGFloat.greatestFiniteMagnitude)

            if coordinator.lastFullMinSize == nil {
                // Primer lanzamiento: tamaño por defecto, dentro de pantalla.
                coordinator.lastFullMinSize = fullMinSize
                let opened = frame(for: NSSize(width: fullSize.width, height: fullSize.height),
                                   anchoredTopLeftOf: mainWindow.frame, in: mainWindow)
                mainWindow.setFrame(clampedToScreen(opened, in: mainWindow), display: true)
            } else if coordinator.lastFullMinSize != fullMinSize {
                // Cambio de modo: si el mínimo crece, agranda anclando la esquina
                // superior izquierda y manténla dentro de la pantalla (no se sale).
                coordinator.lastFullMinSize = fullMinSize
                let content = mainWindow.contentRect(forFrameRect: mainWindow.frame).size
                if content.width < fullMinSize.width - 0.5 || content.height < fullMinSize.height - 0.5 {
                    let target = NSSize(width: max(content.width, fullMinSize.width),
                                        height: max(content.height, fullMinSize.height))
                    let grown = frame(for: target, anchoredTopLeftOf: mainWindow.frame, in: mainWindow)
                    mainWindow.setFrame(clampedToScreen(grown, in: mainWindow), display: true, animate: true)
                }
            }

            // --- Ventana mini (se crea la primera vez) ---
            let miniWindow: NSWindow
            if let existing = coordinator.miniWindow {
                miniWindow = existing
            } else {
                miniWindow = Self.makeMiniWindow(side: miniSize, player: player, onExpand: onExpand)
                coordinator.miniWindow = miniWindow
            }

            if isMini {
                // Coloca el mini la primera vez de la sesión (si el autosave no le
                // dio posición): cerca de la esquina superior izquierda de la
                // principal, dentro de la pantalla. Después conserva su posición.
                if !miniWindow.isVisible && !coordinator.miniPlacedOnce {
                    coordinator.miniPlacedOnce = true
                    if miniWindow.frame.origin == .zero {
                        let start = NSRect(x: mainWindow.frame.minX + 24,
                                           y: mainWindow.frame.maxY - miniSize - 24,
                                           width: miniSize, height: miniSize)
                        miniWindow.setFrame(clampedToScreen(start, in: mainWindow), display: false)
                    }
                }
                miniWindow.makeKeyAndOrderFront(nil)
                mainWindow.orderOut(nil)
            } else {
                if miniWindow.isVisible { miniWindow.orderOut(nil) }
                if !mainWindow.isVisible { mainWindow.makeKeyAndOrderFront(nil) }
            }
        }
    }

    /// Crea la ventana mini: borderless (sin barra de título), cuadrada, no
    /// redimensionable, con esquinas redondeadas y sombra, y arrastrable desde la
    /// portada. Aloja la `MiniPlayerView` compartiendo el mismo reproductor.
    private static func makeMiniWindow(side: CGFloat, player: WebPlayerController,
                                       onExpand: @escaping () -> Void) -> NSWindow {
        let window = MiniPanel(
            contentRect: NSRect(x: 0, y: 0, width: side, height: side),
            styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.fullScreenAuxiliary]

        // Contenido: la portada, recortada a esquinas redondeadas para que la
        // ventana borderless se vea como el mini de Apple Music.
        let root = MiniPlayerView(player: player, onExpand: onExpand)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: side, height: side)
        window.contentView = host
        window.setFrameAutosaveName("YTMusicMiniPlayer")
        return window
    }

    /// Frame que da a la ventana un contenido de `contentSize` manteniendo fija
    /// la esquina superior izquierda de `reference`.
    private func frame(for contentSize: NSSize, anchoredTopLeftOf reference: NSRect,
                       in window: NSWindow) -> NSRect {
        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        let origin = NSPoint(x: reference.origin.x, y: reference.maxY - frameSize.height)
        return NSRect(origin: origin, size: frameSize)
    }

    /// Desplaza `frame` lo mínimo necesario para que quede completamente dentro
    /// del área visible de la pantalla de la ventana (respetando menú y Dock).
    private func clampedToScreen(_ frame: NSRect, in window: NSWindow) -> NSRect {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return frame }
        var f = frame
        if f.width <= visible.width {
            if f.maxX > visible.maxX { f.origin.x = visible.maxX - f.width }
            if f.minX < visible.minX { f.origin.x = visible.minX }
        } else {
            f.origin.x = visible.minX
        }
        if f.height <= visible.height {
            if f.maxY > visible.maxY { f.origin.y = visible.maxY - f.height }
            if f.minY < visible.minY { f.origin.y = visible.minY }
        } else {
            f.origin.y = visible.maxY - f.height
        }
        return f
    }

    final class Coordinator {
        /// Ventana del mini reproductor (independiente de la principal).
        var miniWindow: NSWindow?
        /// Ya se colocó el mini al menos una vez en esta sesión.
        var miniPlacedOnce = false
        /// Último mínimo aplicado en la principal; detecta el cambio de modo.
        var lastFullMinSize: CGSize?
    }
}

/// Ventana sin borde que SÍ puede volverse key/main, para que los controles del
/// mini (botones, slider y el arrastre de la barra de progreso) reciban eventos.
private final class MiniPanel: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Mini reproductor: ventana cuadrada que muestra únicamente la portada del
/// álbum en reproducción. Al pasar el ratón por encima aparecen los controles
/// de media (anterior, play/pausa, siguiente) sobre vidrio, más un botón para
/// volver a la ventana completa.
private struct MiniPlayerView: View {
    var player: WebPlayerController
    var onExpand: () -> Void

    @State private var hovering = false
    /// Muestra el slider de volumen desplegable.
    @State private var showVolume = false
    /// Temporizador que cierra el slider de volumen tras unos segundos de inactividad.
    @State private var volumeAutoCloseTask: Task<Void, Never>?
    /// Fracción de arrastre en curso sobre la barra de progreso (nil si no se arrastra).
    @State private var dragFraction: Double?

    /// El panel de controles es visible al pasar el ratón o con el volumen abierto.
    private var overlayVisible: Bool { hovering || showVolume }

    var body: some View {
        ZStack {
            artwork

            // Oscurecido para dar legibilidad a la información y los controles.
            LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
                .opacity(overlayVisible ? 1 : 0)

            // Con el volumen desplegado, un click en cualquier otra parte lo cierra.
            if showVolume {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { dismissVolume() }
            }

            VStack(spacing: 0) {
                HStack {
                    volumeButton
                    Spacer()
                    expandButton
                }
                Spacer()
                controls
                Spacer()
                bottomInfo
            }
            .padding(12)
            .opacity(overlayVisible ? 1 : 0)
            .allowsHitTesting(overlayVisible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.2), value: hovering)
        .animation(.easeInOut(duration: 0.2), value: showVolume)
    }

    private var artwork: some View {
        Group {
            if let url = player.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            Color(white: 0.12)
            Image(systemName: "music.note")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    /// Título, artista y barra de progreso, anclados a la parte inferior.
    private var bottomInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(player.title.isEmpty ? "—" : player.title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !player.artist.isEmpty {
                Text(player.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            scrubBar
        }
        .foregroundStyle(.white)
    }

    /// Fracción reproducida (0…1), o la posición arrastrada si el usuario la mueve.
    private var fraction: Double {
        if let d = dragFraction { return d }
        guard player.duration > 0 else { return 0 }
        return min(max(player.currentTime / player.duration, 0), 1)
    }

    /// Barra de progreso arrastrable con los tiempos a ambos lados.
    private var scrubBar: some View {
        let shownTime = dragFraction.map { $0 * player.duration } ?? player.currentTime
        return HStack(spacing: 8) {
            Text(timeString(shownTime))
                .font(.system(size: 9, weight: .medium)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                    Capsule().fill(Color.red).frame(width: max(0, w * fraction), height: 4)
                    Circle().fill(.white)
                        .frame(width: 11, height: 11)
                        .offset(x: min(max(w * fraction - 5.5, -5.5), w - 5.5))
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            dismissVolume()
                            dragFraction = min(max(g.location.x / w, 0), 1)
                        }
                        .onEnded { g in
                            let f = min(max(g.location.x / w, 0), 1)
                            player.seek(to: f * player.duration)
                            dragFraction = nil
                        }
                )
            }
            .frame(height: 12)
            Text(timeString(player.duration))
                .font(.system(size: 9, weight: .medium)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    /// Tres botones de media separados, cada uno con su propio Liquid Glass,
    /// centrados en el recuadro.
    private var controls: some View {
        HStack(spacing: 18) {
            controlButton("backward.fill", size: 16) { dismissVolume(); player.previous() }
            controlButton(player.isPlaying ? "pause.fill" : "play.fill", size: 22) {
                dismissVolume(); player.togglePlayPause()
            }
            controlButton("forward.fill", size: 16) { dismissVolume(); player.next() }
        }
        .frame(maxWidth: .infinity)
        .offset(y: 12)
    }

    private var expandButton: some View {
        Button(action: onExpand) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(3)
        .glassEffect(.clear.interactive())
    }

    /// Botón de volumen que, al pulsarlo, se extiende en la misma cápsula de
    /// vidrio para mostrar la barra de volumen (sin desplegar nada aparte).
    private var volumeButton: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { showVolume.toggle() }
                if showVolume { scheduleVolumeAutoClose() }
                else { volumeAutoCloseTask?.cancel() }
            } label: {
                Image(systemName: volumeSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showVolume {
                Slider(value: volumeBinding, in: 0...1)
                    .controlSize(.mini)
                    .tint(.red)
                    .frame(width: 92)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, showVolume ? 10 : 3)
        .padding(.vertical, 3)
        .glassEffect(.clear.interactive())
    }

    /// Enlaza el slider al volumen del reproductor y lo aplica al WebView.
    private var volumeBinding: Binding<Double> {
        Binding(
            get: { player.volume },
            set: {
                player.volume = $0
                player.setVolume($0)
                scheduleVolumeAutoClose()
            }
        )
    }

    /// Cierra el slider de volumen (si está abierto) y cancela su temporizador.
    private func dismissVolume() {
        volumeAutoCloseTask?.cancel()
        if showVolume {
            withAnimation(.easeInOut(duration: 0.25)) { showVolume = false }
        }
    }

    /// Programa el cierre del slider de volumen tras unos segundos sin actividad.
    private func scheduleVolumeAutoClose() {
        volumeAutoCloseTask?.cancel()
        volumeAutoCloseTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) { showVolume = false }
        }
    }

    /// Icono de altavoz según el nivel de volumen.
    private var volumeSymbol: String {
        switch player.volume {
        case ..<0.001: return "speaker.slash.fill"
        case ..<0.4:   return "speaker.wave.1.fill"
        case ..<0.75:  return "speaker.wave.2.fill"
        default:       return "speaker.wave.3.fill"
        }
    }

    private func controlButton(_ symbol: String, size: CGFloat,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size + 16, height: size + 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(8)
        .glassEffect(.clear.interactive())
    }

    /// Formatea segundos como m:ss.
    private func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Selector Music/Videos con efecto Liquid Glass. La opción activa se resalta
/// con una cápsula roja; el conjunto flota sobre una cápsula de vidrio.
private struct ServiceSwitch: View {
    @Binding var mode: ServiceMode

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ServiceMode.allCases) { option in
                Text(option.label)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .foregroundStyle(mode == option ? Color.white : Color.primary)
                    .background {
                        if mode == option {
                            Capsule().fill(Color.red)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture {
                        if mode != option {
                            withAnimation(.easeInOut(duration: 0.2)) { mode = option }
                        }
                    }
            }
        }
        .padding(3)
        .glassEffect(.clear.interactive())
    }
}

#Preview {
    ContentView()
}
