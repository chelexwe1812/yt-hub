//
//  LoadingView.swift
//  YT music
//
//  Pantalla de carga estilo YouTube: fondo oscuro con una barra roja fina y fija
//  arriba que se llena de izquierda a derecha según el progreso real, con un
//  "peg" luminoso en el borde de avance (el detalle característico de YouTube /
//  NProgress).
//

import SwiftUI

struct LoadingView: View {
    /// Progreso de carga, de 0 a 1.
    var progress: Double

    private let barHeight: CGFloat = 3
    private let red = Color(red: 1.0, green: 0.0, blue: 51/255) // #FF0033

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                bar
                Spacer(minLength: 0)
            }
        }
        .animation(.easeOut(duration: 0.25), value: progress)
    }

    private var bar: some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width * progress)

            ZStack(alignment: .leading) {
                // Relleno de la barra.
                Rectangle()
                    .fill(red)
                    .frame(width: width, height: barHeight)
                    .shadow(color: red.opacity(0.9), radius: 5)

                // "Peg" luminoso en el borde de avance (ligeramente inclinado).
                Rectangle()
                    .fill(red)
                    .frame(width: 22, height: barHeight)
                    .shadow(color: red, radius: 10)
                    .shadow(color: red, radius: 4)
                    .rotationEffect(.degrees(3))
                    .offset(x: width - 22)
                    .opacity(progress > 0.01 && progress < 0.999 ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: barHeight)
    }
}

#Preview {
    LoadingView(progress: 0.4)
        .frame(width: 500, height: 300)
}
