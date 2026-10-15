import SwiftUI
import MWDATCore

@main
struct DIVISAShopperApp: App {
    @StateObject private var session = ShopperSessionModel()

    init() {
        do {
            try Wearables.configure()
        } catch {
            NSLog("[DIVISA SHOPPER] Error configurando SDK Meta: \\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ShopperSessionView()
                .environmentObject(session)
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
