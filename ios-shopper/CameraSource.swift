import Foundation

enum CameraSource: String, CaseIterable, Identifiable {
    case rayBanMeta = "Ray-Ban Meta"
    case iPhoneBack = "iPhone trasera"
    case iPhoneFront = "iPhone frontal"

    var id: String { rawValue }
}
