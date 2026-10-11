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
                    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true
                    else { return }
                    Task {
                        do {
                            _ = try await Wearables.shared.handleUrl(url)
                        } catch {
                            NSLog("[DIVISA SHOPPER] Error retorno Meta AI: \\(error)")
                        }
                    }
                }
        }
    }
}
