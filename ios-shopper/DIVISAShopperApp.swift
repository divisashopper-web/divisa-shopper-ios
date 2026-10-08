import SwiftUI

@main
struct DIVISAShopperApp: App {
    @StateObject private var session = ShopperSessionModel()

    var body: some Scene {
        WindowGroup {
            ShopperSessionView()
                .environmentObject(session)
        }
    }
}
