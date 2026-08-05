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

    var body: some View {
        ZStack(alignment: .topLeading) {
            YouTubeWebView(mode: mode, isLoading: $isLoading, progress: $progress)

            if isLoading {
                LoadingView(progress: progress)
                    .transition(.opacity)
            }

            // Switch de servicio con Liquid Glass. Se oculta durante la carga y
            // reaparece en distinta posición según el modo:
            //   · Videos: 220px desde el borde izquierdo.
            //   · Music:  240px desde el borde derecho.
            if !isLoading {
                ServiceSwitch(mode: $mode)
                    .padding(.top, mode == .videos ? 13 : 17)
                    .padding(mode == .videos ? .leading : .trailing,
                             mode == .videos ? 205 : 150)
                    .frame(maxWidth: .infinity,
                           alignment: mode == .videos ? .leading : .trailing)
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(TitleBarConfigurator())
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .onChange(of: mode) {
            progress = 0
            isLoading = true
        }
    }
}

/// Oculta el texto del título conservando la barra de título y sus botones.
private struct TitleBarConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            nsView.window?.titleVisibility = .hidden
        }
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
        .glassEffect(.regular.interactive())
    }
}

#Preview {
    ContentView()
}
