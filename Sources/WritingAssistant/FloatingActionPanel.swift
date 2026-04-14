import AppKit

private final class FloatingPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FloatingActionPanel: NSObject {
    private let panel: NSPanel
    private let draftField = NSTextField()
    private var displayedActions: [RewriteAction] = []

    var onAction: ((RewriteAction) -> Void)?
    var onDraftRequest: ((String) -> Void)?
    var onDraftEditingBegan: (() -> Void)?
    var isVisible: Bool { panel.isVisible }

    override init() {
        panel = FloatingPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 196, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        super.init()

        configurePanel()
    }

    func show(near point: NSPoint, focusDraftField: Bool = false) {
        configureContent()

        let tuning = AppSettings.shared.popupTuning
        let size = panel.frame.size
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)

        let gap = 8.0 * tuning.popupScale
        var x: CGFloat
        var y: CGFloat

        switch tuning.popupPosition {
        case .above:
            x = point.x - size.width / 2
            y = point.y + gap
            if y + size.height > visibleFrame.maxY {
                y = point.y - size.height - gap
            }
        case .below:
            x = point.x - size.width / 2
            y = point.y - size.height - gap
            if y < visibleFrame.minY {
                y = point.y + gap
            }
        case .left:
            x = point.x - size.width - gap
            y = point.y - size.height / 2
            if x < visibleFrame.minX {
                x = point.x + gap
            }
        case .right:
            x = point.x + gap
            y = point.y - size.height / 2
            if x + size.width > visibleFrame.maxX {
                x = point.x - size.width - gap
            }
        }

        x += tuning.popupOffsetX
        y += tuning.popupOffsetY

        x = min(max(x, visibleFrame.minX + 8), visibleFrame.maxX - size.width - 8)
        y = min(max(y, visibleFrame.minY + 8), visibleFrame.maxY - size.height - 8)

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        panel.orderFrontRegardless()
        if focusDraftField {
            panel.makeKey()
            panel.makeFirstResponder(draftField)
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
    }

    private func configureContent() {
        let tuning = AppSettings.shared.popupTuning
        let scale = tuning.popupScale
        let actions = AppSettings.shared.rewriteActions
        displayedActions = actions
        let buttonWidth = 44.0 * scale
        let buttonHeight = 24.0 * scale
        let padding = 5.0 * scale
        let spacing = 4.0 * scale
        let buttonRowWidth = (buttonWidth * Double(actions.count)) + (spacing * Double(max(0, actions.count - 1)))
        let width = max(260.0 * scale, buttonRowWidth + (padding * 2))
        let draftHeight = 26.0 * scale
        let height = draftHeight + buttonHeight + (padding * 3) + spacing

        panel.setContentSize(NSSize(width: width, height: height))

        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 8
        effectView.layer?.masksToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false

        let buttons = actions.enumerated().map { index, action in
            let button = NSButton(title: action.shortTitle, target: self, action: #selector(runAction(_:)))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tag = index
            button.toolTip = action.tooltip
            configureButton(button)
            button.widthAnchor.constraint(equalToConstant: buttonWidth).isActive = true
            button.heightAnchor.constraint(equalToConstant: buttonHeight).isActive = true
            return button
        }

        let stackView = NSStackView(views: buttons)
        stackView.orientation = .horizontal
        stackView.spacing = spacing
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let draftButton = NSButton(title: "", target: self, action: #selector(runDraft))
        draftButton.translatesAutoresizingMaskIntoConstraints = false
        if let sendImage = NSImage(systemSymbolName: "paperplane.fill", accessibilityDescription: "Send draft request") {
            draftButton.image = sendImage
            draftButton.imagePosition = .imageOnly
        } else {
            draftButton.title = "Send"
        }
        draftButton.toolTip = "Generate and insert draft"
        configureButton(draftButton)
        draftButton.widthAnchor.constraint(equalToConstant: max(34.0, 36.0 * scale)).isActive = true
        draftButton.heightAnchor.constraint(equalToConstant: draftHeight).isActive = true

        configureDraftField(scale: scale)

        let draftRow = NSStackView(views: [draftField, draftButton])
        draftRow.orientation = .horizontal
        draftRow.spacing = spacing
        draftRow.alignment = .centerY
        draftRow.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView(views: [draftRow, stackView])
        contentStack.orientation = .vertical
        contentStack.spacing = spacing
        contentStack.alignment = .centerX
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        panel.contentView = effectView
        effectView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: padding),
            contentStack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -padding),
            contentStack.topAnchor.constraint(equalTo: effectView.topAnchor, constant: padding),
            contentStack.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -padding),
            draftRow.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            stackView.centerXAnchor.constraint(equalTo: contentStack.centerXAnchor),
            draftField.heightAnchor.constraint(equalToConstant: draftHeight)
        ])
    }

    private func configureButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.font = .systemFont(ofSize: max(10.0, 11.0 * AppSettings.shared.popupTuning.popupScale), weight: .medium)
    }

    private func configureDraftField(scale: Double) {
        draftField.placeholderString = "Write anything..."
        draftField.font = .systemFont(ofSize: max(11.0, 12.0 * scale))
        draftField.lineBreakMode = .byTruncatingTail
        draftField.delegate = self
        draftField.target = self
        draftField.action = #selector(runDraft)
        draftField.bezelStyle = .roundedBezel
        draftField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    @objc private func runAction(_ sender: NSButton) {
        guard displayedActions.indices.contains(sender.tag) else { return }
        onAction?(displayedActions[sender.tag])
    }

    @objc private func runDraft() {
        let request = draftField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        draftField.stringValue = ""
        onDraftRequest?(request)
    }
}

extension FloatingActionPanel: NSTextFieldDelegate {
    func controlTextDidBeginEditing(_ notification: Notification) {
        onDraftEditingBegan?()
    }
}
