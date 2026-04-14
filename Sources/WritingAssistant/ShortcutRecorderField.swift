import AppKit

final class ShortcutRecorderField: NSButton {
    private var keyMonitor: Any?
    private var isRecording = false

    var shortcutString: String = "" {
        didSet {
            if !isRecording {
                updateTitle()
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        stopRecording()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        beginRecording()
        return true
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return true
    }

    override func keyDown(with event: NSEvent) {
        if record(event) {
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        record(event)
    }

    private func configure() {
        setButtonType(.momentaryPushIn)
        bezelStyle = .rounded
        isBordered = true
        alignment = .left
        font = .systemFont(ofSize: 13)
        focusRingType = .exterior
        toolTip = "Click here, then press a shortcut. Press Delete to clear."
        target = self
        action = #selector(clicked)
        updateTitle()
    }

    @objc private func clicked() {
        window?.makeFirstResponder(self)
    }

    private func beginRecording() {
        isRecording = true
        title = "Press shortcut..."
        contentTintColor = .controlAccentColor

        guard keyMonitor == nil else { return }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.window?.firstResponder === self else {
                return event
            }

            if event.type == .flagsChanged {
                return nil
            }

            _ = self.record(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        contentTintColor = nil
        updateTitle()

        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func updateTitle() {
        title = shortcutString.isEmpty ? "Click to record" : shortcutString
    }

    @discardableResult
    private func record(_ event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self, event.type == .keyDown else {
            return false
        }

        switch event.keyCode {
        case 51, 117:
            shortcutString = ""
            window?.makeFirstResponder(nil)
            return true
        case 53:
            window?.makeFirstResponder(nil)
            return true
        default:
            break
        }

        guard let shortcut = KeyboardShortcut(event: event) else {
            NSSound.beep()
            return true
        }

        shortcutString = shortcut.displayString
        window?.makeFirstResponder(nil)
        return true
    }
}
