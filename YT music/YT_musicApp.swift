//
//  YT_musicApp.swift
//  YT music
//
//  Created by Marcelo on 4/8/26.
//

import SwiftUI

@main
struct YT_musicApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // La redimensionabilidad se deriva del contenido: SwiftUI toma como
        // mínimo Y máximo de la ventana los límites del .frame de ContentView.
        // Así, en modo mini (frame fijo a miniSize) la ventana queda bloqueada
        // en el cuadrado y no se puede redimensionar; en modo grande el máximo
        // es .infinity y sigue siendo libre. El valor por defecto (.contentMinSize)
        // no impone máximo, por eso la ventana crecía sin control.
        .windowResizability(.contentSize)
    }
}
