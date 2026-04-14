import Carbon
import Foundation

final class GlobalHotkeyRegistrar {
    private static let signature = fourCharCode("WrAs")

    private var eventHandler: EventHandlerRef?
    private var hotkeyRefs: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]

    init() {
        installEventHandler()
    }

    deinit {
        unregisterAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register(shortcut: KeyboardShortcut, id: UInt32, action: @escaping () -> Void) -> Bool {
        guard let keyCode = shortcut.carbonKeyCode else {
            AppLog.error("Global hotkey unsupported key shortcut=\(shortcut.displayString)")
            return false
        }

        let hotkeyID = EventHotKeyID(signature: Self.signature, id: id)
        var hotkeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            shortcut.carbonModifierFlags,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )

        guard status == noErr, let hotkeyRef else {
            AppLog.error("Global hotkey registration failed shortcut=\(shortcut.displayString), status=\(status)")
            return false
        }

        hotkeyRefs.append(hotkeyRef)
        actions[id] = action
        return true
    }

    func unregisterAll() {
        hotkeyRefs.forEach { hotkeyRef in
            UnregisterEventHotKey(hotkeyRef)
        }
        hotkeyRefs.removeAll()
        actions.removeAll()
    }

    private func handleHotkey(id: UInt32) {
        actions[id]?()
    }

    private func installEventHandler() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }

            var hotkeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )

            guard status == noErr,
                  hotkeyID.signature == GlobalHotkeyRegistrar.signature else {
                return status
            }

            let registrar = Unmanaged<GlobalHotkeyRegistrar>
                .fromOpaque(userData)
                .takeUnretainedValue()
            registrar.handleHotkey(id: hotkeyID.id)
            return noErr
        }

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        if status != noErr {
            AppLog.error("Global hotkey event handler installation failed status=\(status)")
        }
    }

    private static func fourCharCode(_ value: String) -> OSType {
        value.utf8.reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }
}
