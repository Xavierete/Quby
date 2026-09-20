import Foundation

enum QRType: String, CaseIterable, Identifiable {
    case website
    case contact
    case wifi
    case email
    case sms
    case location

    var id: String { rawValue }

    var title: String {
        switch self {
        case .website: return "Website"
        case .contact: return "Contact"
        case .wifi: return "Wi-Fi"
        case .email: return "Email"
        case .sms: return "SMS"
        case .location: return "Location"
        }
    }

    var icon: String {
        switch self {
        case .website: return "globe"
        case .contact: return "person.crop.circle"
        case .wifi: return "wifi"
        case .email: return "envelope"
        case .sms: return "message"
        case .location: return "mappin.and.ellipse"
        }
    }
}
