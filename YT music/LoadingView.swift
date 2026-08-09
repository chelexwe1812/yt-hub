//
//  LoadingView.swift
//  YT music
//
//  Transición entre servicios (YouTube Music ↔ YouTube). Sobre un fondo negro,
//  una tarjeta con el símbolo del servicio de DESTINO (nota / ▶) latiendo, y el
//  efecto "border beam" (paquete BorderBeamKit) recorriendo su borde redondeado.
//

import SwiftUI
import BorderBeamKit

struct LoadingView: View {
    /// Servicio de destino (hacia el que se está cargando).
    var mode: ServiceMode
    /// Progreso de carga, de 0 a 1 (reservado; el haz es indeterminado).
    var progress: Double

    /// Controla la entrada elástica del contenido.
    @State private var appear = false

    /// Lado de la tarjeta. El radio del borde es la mitad → círculo perfecto,
    /// y el haz sigue ese mismo radio para recorrer el borde redondo.
    private let side: CGFloat = 96
    private var cornerRadius: CGFloat { side / 2 }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                BorderBeam(size: .sm, colorVariant: .colorful, borderRadius: cornerRadius) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.04))
                        Image(systemName: mode == .music ? "music.note" : "play.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white)
                            .symbolEffect(.pulse, options: .repeating)
                    }
                    .frame(width: side, height: side)
                }

                Text(mode.label)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .scaleEffect(appear ? 1 : 0.92)
        }
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { appear = true }
        }
    }
}

#Preview {
    LoadingView(mode: .music, progress: 0.4)
        .frame(width: 500, height: 300)
}
