import Foundation
#if os(iOS)
import NetworkExtension
#endif

struct WiFiJoiner {

    func join(ssid: String, password: String, security: String, isHidden: Bool) async -> String {
        #if os(iOS)
        guard !ssid.isEmpty else { return "This code has no network name." }

        let configuration: NEHotspotConfiguration
        switch security {
        case "Open":
            configuration = NEHotspotConfiguration(ssid: ssid)
        case "WEP":
            configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: true)
        default:
            configuration = NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
        }
        configuration.hidden = isHidden
        configuration.joinOnce = false

        do {
            try await NEHotspotConfigurationManager.shared.apply(configuration)
            return "Joining \(ssid)…"
        } catch {
            let nsError = error as NSError
            if nsError.domain == NEHotspotConfigurationErrorDomain,
               let hotspotError = NEHotspotConfigurationError(rawValue: nsError.code) {
                return message(for: hotspotError, ssid: ssid)
            }
            return "Could not join: \(error.localizedDescription)"
        }
        #else
        _ = (password, security, isHidden)
        guard !ssid.isEmpty else { return "This code has no network name." }
        return "Joining Wi-Fi from a code isn’t available on Mac. Copy the password instead."
        #endif
    }

    #if os(iOS)
    private func message(for error: NEHotspotConfigurationError, ssid: String) -> String {
        switch error {
        case .alreadyAssociated:
            return "Already connected to \(ssid)."
        case .userDenied:
            return "You declined the request to join."
        case .invalidWPAPassphrase, .invalidWEPPassphrase:
            return "The password in this code is not valid for that network."
        case .invalidSSID:
            return "The network name in this code is not valid."
        case .pending, .systemConfiguration, .internal, .unknown:
            return "Could not join the network."
        default:
            return "Could not join \(ssid)."
        }
    }
    #endif
}
