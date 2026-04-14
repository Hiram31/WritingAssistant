import ApplicationServices

enum Keyboard {
    private static let cKeyCode: CGKeyCode = 8
    private static let vKeyCode: CGKeyCode = 9

    static func copy() {
        postCommandKey(cKeyCode)
    }

    static func paste() {
        postCommandKey(vKeyCode)
    }

    private static func postCommandKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let flags: CGEventFlags = [.maskCommand]

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cghidEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = flags
        keyUp?.post(tap: .cghidEventTap)
    }
}
