import SwiftUI
import MWDATCore

@main
struct DIVISAShopperApp: App {
    @StateObject private var session = ShopperSessionModel()
    @State private var metaConfigurationError: String?

    init() {
        do {
            try Wearables.configure()
            _metaConfigurationError = State(initialValue: nil)
        } catch {
            let message = error.localizedDescription
            NSLog("[DIVISA SHOPPER] Error configurando SDK Meta: \\(error)")
            _metaConfigurationError = State(initialValue: message)
        }
    }

    var body: some Scene {
        WindowGroup {
            ShopperSessionView()
                .environmentObject(session)
                .alert("Meta no pudo inicializarse", isPresented: Binding(
                    get: { metaConfigurationError != nil },
                    set: { if !$0 { metaConfigurationError = nil } }
                )) {
                    Button("Entendido") { metaConfigurationError = nil }
                } message: {
                    Text("Error al configurar el SDK de Meta: \\(metaConfigurationError ?? "desconocido"). La cámara del iPhone puede seguir funcionando.")
                }
                .onOpenURL { url in
                    // El SDK oficial decide si el enlace es un callback válido.
                    // No exigir parámetros concretos antes de entregárselo:
                    // Meta puede cambiar la forma del callback entre versiones.
                    guard url.scheme?.lowercased() == "divisa-shopper" else { return }
                    Task {
                        await session.metaWearables.handleRegistrationCallback(url)
                    }
                }
        }
    }
}
