import AppKit
import ApplicationServices

struct SelectionContext {
    let text: String
    let focusedElement: AXUIElement?
    let sourceApplication: NSRunningApplication?

    var applicationDescription: String {
        let name = sourceApplication?.localizedName ?? "unknown"
        let bundleID = sourceApplication?.bundleIdentifier ?? "unknown"
        let pid = sourceApplication?.processIdentifier ?? 0
        return "\(name) bundleID=\(bundleID) pid=\(pid)"
    }
}

final class SelectionReader {
    func currentContext() -> SelectionContext {
        SelectionContext(
            text: "",
            focusedElement: currentFocusedElement(),
            sourceApplication: NSWorkspace.shared.frontmostApplication
        )
    }

    func readSelectedText(completion: @escaping (SelectionContext?) -> Void) {
        let sourceApplication = NSWorkspace.shared.frontmostApplication
        let focusedElement = currentFocusedElement()
        let appName = sourceApplication?.localizedName ?? "unknown"
        let bundleID = sourceApplication?.bundleIdentifier ?? "unknown"
        AppLog.debug("Reading selected text from frontmost app=\(appName), bundleID=\(bundleID), focusedElement=\(focusedElement != nil)")

        if let focusedElement,
           let selectedText = accessibilitySelectedText(from: focusedElement),
           !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AppLog.info("Selected text read through Accessibility: \(AppLog.describeText(selectedText))")
            completion(SelectionContext(
                text: selectedText,
                focusedElement: focusedElement,
                sourceApplication: sourceApplication
            ))
            return
        }

        readSelectedTextFromClipboardFallback(focusedElement: focusedElement, sourceApplication: sourceApplication, completion: completion)
    }

    private func currentFocusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        )

        guard error == .success, let focusedObject else {
            AppLog.debug("No focused Accessibility element. axError=\(error.rawValue)")
            return nil
        }
        return (focusedObject as! AXUIElement)
    }

    private func accessibilitySelectedText(from element: AXUIElement) -> String? {
        var selectedObject: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedObject
        )

        guard error == .success else {
            AppLog.debug("Accessibility selected text unavailable. axError=\(error.rawValue)")
            return nil
        }
        return selectedObject as? String
    }

    private func readSelectedTextFromClipboardFallback(
        focusedElement: AXUIElement?,
        sourceApplication: NSRunningApplication?,
        completion: @escaping (SelectionContext?) -> Void
    ) {
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot.capture(from: pasteboard)
        AppLog.info("Trying clipboard fallback to read selected text.")

        pasteboard.clearContents()
        Keyboard.copy()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let selectedText = pasteboard.string(forType: .string)
            snapshot.restore(to: pasteboard)

            guard let selectedText,
                  !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                AppLog.info("Clipboard fallback found no selected text.")
                completion(nil)
                return
            }

            AppLog.info("Selected text read through clipboard fallback: \(AppLog.describeText(selectedText))")
            completion(SelectionContext(
                text: selectedText,
                focusedElement: focusedElement,
                sourceApplication: sourceApplication
            ))
        }
    }
}
