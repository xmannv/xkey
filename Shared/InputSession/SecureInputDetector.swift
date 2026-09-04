import Cocoa
import Carbon
import IOKit

struct SecureInputObservation: Equatable, Sendable {
    let isEnabled: Bool
    let holderPID: pid_t
    let holderAppName: String

    static let inactive = SecureInputObservation(isEnabled: false,
                                                 holderPID: 0,
                                                 holderAppName: "Unknown")

    var statePID: pid_t {
        guard isEnabled else { return 0 }
        return holderPID == 0 ? -1 : holderPID
    }

    nonisolated static func == (
        lhs: SecureInputObservation,
        rhs: SecureInputObservation
    ) -> Bool {
        lhs.isEnabled == rhs.isEnabled
            && lhs.holderPID == rhs.holderPID
            && lhs.holderAppName == rhs.holderAppName
    }
}

protocol SecureInputDetecting {
    var observation: SecureInputObservation { get }
}

final class SystemSecureInputDetector: SecureInputDetecting {
    var observation: SecureInputObservation {
        let isEnabled = IsSecureEventInputEnabled()
        guard isEnabled else { return .inactive }

        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != IO_OBJECT_NULL else {
            return SecureInputObservation(isEnabled: true,
                                          holderPID: -1,
                                          holderAppName: "Unknown")
        }
        defer { IOObjectRelease(root) }

        guard let value = IORegistryEntryCreateCFProperty(
            root,
            "IOConsoleUsers" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue(),
        let users = value as? [[String: Any]]
        else {
            return SecureInputObservation(isEnabled: true,
                                          holderPID: -1,
                                          holderAppName: "Unknown")
        }

        for user in users {
            guard user["kCGSSessionOnConsoleKey"] as? Bool == true,
                  let value = user["kCGSSessionSecureInputPID"] as? Int,
                  value != 0
            else { continue }

            let pid = pid_t(value)
            let app = NSRunningApplication(processIdentifier: pid)
            return SecureInputObservation(
                isEnabled: true,
                holderPID: pid,
                holderAppName: app?.localizedName ?? app?.bundleIdentifier ?? "PID \(pid)"
            )
        }

        return SecureInputObservation(isEnabled: true,
                                      holderPID: -1,
                                      holderAppName: "Unknown")
    }

    static var isXKeyIMSelectedInputSource: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return false }
        let identifier = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        return identifier.hasPrefix("com.codetay.inputmethod.XKey")
    }
}
