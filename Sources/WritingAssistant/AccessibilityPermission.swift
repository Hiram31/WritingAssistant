import ApplicationServices
import Foundation

enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestIfNeeded() {
        guard !isTrusted else { return }

        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        AXIsProcessTrustedWithOptions(options)
    }
}
