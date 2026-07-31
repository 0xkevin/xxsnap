import CryptoKit
import Foundation
import IOKit

protocol CommercialDeviceIdentifying: AnyObject {
    func deviceHash() throws -> String
    func displayName() -> String
}

enum CommercialDeviceIdentityError: Error, Equatable {
    case platformUUIDUnavailable
}

final class CommercialDeviceIdentity: CommercialDeviceIdentifying {
    private let platformUUIDProvider: () -> String?
    private let hostNameProvider: () -> String?

    init(
        platformUUIDProvider: @escaping () -> String? = CommercialDeviceIdentity.readPlatformUUID,
        hostNameProvider: @escaping () -> String? = { Host.current().localizedName }
    ) {
        self.platformUUIDProvider = platformUUIDProvider
        self.hostNameProvider = hostNameProvider
    }

    func deviceHash() throws -> String {
        guard let raw = platformUUIDProvider()?.trimmingCharacters(in: .whitespacesAndNewlines),
              let uuid = UUID(uuidString: raw)
        else { throw CommercialDeviceIdentityError.platformUUIDUnavailable }
        let digest = SHA256.hash(data: Data("com.xxsnap.mac\0\(uuid.uuidString.lowercased())".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func displayName() -> String {
        let name = hostNameProvider()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String((name.isEmpty ? "Mac" : name).prefix(120))
    }

    private static func readPlatformUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformUUID" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String
    }
}
