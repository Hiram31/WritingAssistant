import AppKit
import ApplicationServices

final class SelectionReplacer {
    private let settings = AppSettings.shared

    func replaceSelection(
        with replacement: String,
        context: SelectionContext,
        completion: @escaping () -> Void
    ) {
        let strategy = settings.replacementStrategy
        AppLog.info("Replacement strategy=\(strategy.rawValue), app=\(context.applicationDescription)")

        if strategy == .accessibilityThenPaste {
            if let focusedElement = context.focusedElement {
                let error = AXUIElementSetAttributeValue(
                    focusedElement,
                    kAXSelectedTextAttribute as CFString,
                    replacement as CFTypeRef
                )

                if error == .success {
                    AppLog.info("Selection replaced through Accessibility. app=\(context.applicationDescription), replacement \(AppLog.describeText(replacement))")
                    completion()
                    return
                }

                AppLog.info("Accessibility replacement returned axError=\(error.rawValue); using paste fallback.")
            } else {
                AppLog.info("No focused Accessibility element for replacement; using paste fallback.")
            }
        }

        AppLog.info("Using paste fallback for replacement. app=\(context.applicationDescription)")
        pasteReplacement(replacement, into: context.sourceApplication, completion: completion)
    }

    private func pasteReplacement(
        _ replacement: String,
        into sourceApplication: NSRunningApplication?,
        completion: @escaping () -> Void
    ) {
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        let activationDelay = settings.pasteActivationDelay
        let clipboardRestoreDelay = settings.clipboardRestoreDelay

        AppLog.info("Activating source app before paste fallback: \(sourceApplication?.localizedName ?? "unknown")")
        sourceApplication?.activate(options: [.activateIgnoringOtherApps])

        DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay) {
            let pastedReplacement = self.replacementWithTrailingNewline(replacement)
            pasteboard.clearContents()
            pasteboard.setString(pastedReplacement, forType: .string)
            AppLog.info("Posting paste event for replacement fallback. replacement \(AppLog.describeText(pastedReplacement))")
            Keyboard.paste()

            DispatchQueue.main.asyncAfter(deadline: .now() + clipboardRestoreDelay) {
                snapshot.restore(to: pasteboard)
                AppLog.info("Clipboard restored after paste fallback.")
                completion()
            }
        }
    }

    private func replacementWithTrailingNewline(_ replacement: String) -> String {
        replacement.hasSuffix("\n") ? replacement : "\(replacement)\n"
    }
}
