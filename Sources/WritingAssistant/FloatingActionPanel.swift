import AppKit

private final class FloatingPanelWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class DraftInputTextView: NSTextView {
    var placeholderString: String = "Write anything..." {
        didSet { needsDisplay = true }
    }

    override var string: String {
        didSet { needsDisplay = true }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard string.isEmpty else { return }
        let font = self.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.placeholderTextColor,
            .paragraphStyle: paragraph
        ]
        let origin = NSPoint(x: textContainerInset.width + 2, y: textContainerInset.height + 1)
        (placeholderString as NSString).draw(at: origin, withAttributes: attributes)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command || flags == [.command, .shift] else {
            return super.performKeyEquivalent(with: event)
        }

        guard let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        let fullTextRange = NSRange(location: 0, length: (string as NSString).length)
        switch key {
        case "a":
            setSelectedRange(fullTextRange)
            return true
        case "c":
            copy(nil)
            return true
        case "x":
            cut(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "z":
            if flags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

final class FloatingActionPanel: NSObject {
    private let maxVisibleDraftLines: CGFloat = 4
    private let panel: NSPanel
    private let draftTextView = DraftInputTextView()
    private let draftScrollView = NSScrollView()
    private let resultTextView = NSTextView()
    private var displayedActions: [RewriteAction] = []
    private var lastAnchorPoint: NSPoint?
    private var panelPadding: CGFloat = 0
    private var panelSpacing: CGFloat = 0
    private var basePanelWidth: CGFloat = 0
    private var basePanelHeight: CGFloat = 0
    private var draftButtonWidth: CGFloat = 0
    private var minimumDraftFieldWidth: CGFloat = 0
    private var baseDraftFieldHeight: CGFloat = 0
    private var draftFieldHeightConstraint: NSLayoutConstraint?

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
        lastAnchorPoint = point
        configureContent()
        positionPanel(near: point)

        panel.orderFrontRegardless()
        if focusDraftField {
            panel.makeKey()
            panel.makeFirstResponder(draftTextView)
        }
    }

    func showResult(_ text: String, title: String) {
        configureResultContent(text: text, title: title)
        let anchor = lastAnchorPoint ?? NSPoint(x: panel.frame.midX, y: panel.frame.minY)
        positionPanel(near: anchor)
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(resultTextView)
    }

    private func positionPanel(near point: NSPoint) {

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
        let sendButtonWidth = max(34.0, 36.0 * scale)

        panelPadding = padding
        panelSpacing = spacing
        basePanelWidth = width
        basePanelHeight = height
        draftButtonWidth = sendButtonWidth
        minimumDraftFieldWidth = max(140.0 * scale, width - (padding * 2) - spacing - sendButtonWidth)
        baseDraftFieldHeight = draftHeight

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
            let button = NSButton(title: "", target: self, action: #selector(runAction(_:)))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.tag = index
            button.toolTip = action.tooltip
            button.setAccessibilityLabel(action.tooltip)
            if let systemImageName = action.systemImageName,
               let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: action.tooltip) {
                button.image = image
                button.imagePosition = .imageOnly
                button.imageScaling = .scaleProportionallyDown
            } else {
                button.title = action.shortTitle
            }
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
        draftButton.widthAnchor.constraint(equalToConstant: sendButtonWidth).isActive = true
        draftButton.heightAnchor.constraint(equalToConstant: draftHeight).isActive = true

        configureDraftField(scale: scale, height: draftHeight)

        let draftRow = NSStackView(views: [draftScrollView, draftButton])
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
            stackView.centerXAnchor.constraint(equalTo: contentStack.centerXAnchor)
        ])
        draftFieldHeightConstraint = draftScrollView.heightAnchor.constraint(equalToConstant: draftHeight)
        draftFieldHeightConstraint?.isActive = true

        updatePanelSizeForDraftText()
    }

    private func configureButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.font = .systemFont(ofSize: max(10.0, 11.0 * AppSettings.shared.popupTuning.popupScale), weight: .medium)
    }

    private func configureResultContent(text: String, title: String) {
        let scale = AppSettings.shared.popupTuning.popupScale
        let width = max(360.0, 420.0 * scale)
        let height = max(210.0, 240.0 * scale)
        let padding = max(10.0, 12.0 * scale)
        let buttonSize = max(26.0, 28.0 * scale)

        panel.setContentSize(NSSize(width: width, height: height))

        let effectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 10
        effectView.layer?.masksToBounds = true

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: max(12.0, 13.0 * scale), weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        let copyButton = resultButton(
            systemImageName: "doc.on.doc",
            fallbackTitle: "Copy",
            toolTip: "Copy translation",
            action: #selector(copyResult)
        )
        let closeButton = resultButton(
            systemImageName: "xmark",
            fallbackTitle: "Close",
            toolTip: "Close translation",
            action: #selector(closeResult)
        )

        resultTextView.string = text
        resultTextView.font = .systemFont(ofSize: max(13.0, 14.0 * scale))
        resultTextView.textColor = .labelColor
        resultTextView.drawsBackground = false
        resultTextView.isEditable = false
        resultTextView.isSelectable = true
        resultTextView.isRichText = false
        resultTextView.isHorizontallyResizable = false
        resultTextView.isVerticallyResizable = true
        resultTextView.autoresizingMask = [.width]
        resultTextView.frame = NSRect(
            x: 0,
            y: 0,
            width: width - (padding * 2),
            height: height - buttonSize - (padding * 3)
        )
        resultTextView.minSize = NSSize(width: 0, height: 0)
        resultTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        resultTextView.textContainerInset = NSSize(width: 7.0 * scale, height: 7.0 * scale)
        resultTextView.textContainer?.lineFragmentPadding = 0
        resultTextView.textContainer?.widthTracksTextView = true
        resultTextView.textContainer?.containerSize = NSSize(
            width: width - (padding * 2),
            height: CGFloat.greatestFiniteMagnitude
        )

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .controlBackgroundColor
        scrollView.documentView = resultTextView

        panel.contentView = effectView
        [titleLabel, copyButton, closeButton, scrollView].forEach(effectView.addSubview)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: padding),
            titleLabel.centerYAnchor.constraint(equalTo: copyButton.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: copyButton.leadingAnchor, constant: -8),

            closeButton.topAnchor.constraint(equalTo: effectView.topAnchor, constant: padding),
            closeButton.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -padding),
            closeButton.widthAnchor.constraint(equalToConstant: buttonSize),
            closeButton.heightAnchor.constraint(equalToConstant: buttonSize),

            copyButton.topAnchor.constraint(equalTo: closeButton.topAnchor),
            copyButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
            copyButton.widthAnchor.constraint(equalToConstant: buttonSize),
            copyButton.heightAnchor.constraint(equalToConstant: buttonSize),

            scrollView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: padding),
            scrollView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -padding),
            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor, constant: -padding)
        ])
    }

    private func resultButton(
        systemImageName: String,
        fallbackTitle: String,
        toolTip: String,
        action: Selector
    ) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.toolTip = toolTip
        button.setAccessibilityLabel(toolTip)
        if let image = NSImage(systemSymbolName: systemImageName, accessibilityDescription: toolTip) {
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.title = fallbackTitle
        }
        return button
    }

    @objc private func copyResult() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(resultTextView.string, forType: .string)
    }

    @objc private func closeResult() {
        hide()
    }

    private func configureDraftField(scale: Double, height: CGFloat) {
        draftTextView.placeholderString = "Write anything..."
        draftTextView.font = .systemFont(ofSize: max(11.0, 12.0 * scale))
        draftTextView.textColor = .labelColor
        draftTextView.drawsBackground = false
        draftTextView.isEditable = true
        draftTextView.isSelectable = true
        draftTextView.isRichText = false
        draftTextView.importsGraphics = false
        draftTextView.allowsUndo = true
        draftTextView.delegate = self
        draftTextView.isHorizontallyResizable = false
        draftTextView.isVerticallyResizable = true
        draftTextView.autoresizingMask = [.width]
        draftTextView.textContainerInset = NSSize(width: 4.0 * scale, height: 4.0 * scale)
        draftTextView.textContainer?.lineFragmentPadding = 0
        draftTextView.textContainer?.widthTracksTextView = true
        draftTextView.textContainer?.containerSize = NSSize(width: minimumDraftFieldWidth, height: .greatestFiniteMagnitude)
        draftTextView.minSize = NSSize(width: 0, height: height)
        draftTextView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        draftTextView.setContentHuggingPriority(.defaultLow, for: .horizontal)

        draftScrollView.translatesAutoresizingMaskIntoConstraints = false
        draftScrollView.borderType = .bezelBorder
        draftScrollView.hasVerticalScroller = false
        draftScrollView.hasHorizontalScroller = false
        draftScrollView.autohidesScrollers = true
        draftScrollView.scrollerStyle = .overlay
        draftScrollView.drawsBackground = true
        draftScrollView.backgroundColor = .controlBackgroundColor
        draftScrollView.documentView = draftTextView
    }

    @objc private func runAction(_ sender: NSButton) {
        guard displayedActions.indices.contains(sender.tag) else { return }
        onAction?(displayedActions[sender.tag])
    }

    @objc private func runDraft() {
        let request = draftTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        draftTextView.string = ""
        updatePanelSizeForDraftText()
        onDraftRequest?(request)
    }

    private func updatePanelSizeForDraftText() {
        guard panel.contentView != nil else { return }

        let scale = AppSettings.shared.popupTuning.popupScale
        let singleLineText = draftTextView.string
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayText = singleLineText.isEmpty ? draftTextView.placeholderString : singleLineText
        let font = draftTextView.font ?? .systemFont(ofSize: max(11.0, 12.0 * scale))
        let measuredTextWidth = ceil((displayText as NSString).size(withAttributes: [.font: font]).width)
        let desiredDraftFieldWidth = max(minimumDraftFieldWidth, measuredTextWidth + (18.0 * scale))

        let defaultMaxPanelWidth = max(basePanelWidth, 560.0 * scale)
        let screenMaxPanelWidth: CGFloat
        if let screen = panel.screen {
            screenMaxPanelWidth = max(basePanelWidth, screen.visibleFrame.width - 16)
        } else {
            screenMaxPanelWidth = defaultMaxPanelWidth
        }

        let desiredPanelWidth = min(
            max(basePanelWidth, desiredDraftFieldWidth + draftButtonWidth + panelSpacing + (panelPadding * 2)),
            min(screenMaxPanelWidth, defaultMaxPanelWidth)
        )

        let availableDraftWidth = max(
            minimumDraftFieldWidth,
            desiredPanelWidth - (panelPadding * 2) - panelSpacing - draftButtonWidth
        )
        let maxDraftHeight = preferredMaxDraftHeight(font: font, scale: scale)
        let desiredDraftHeight = preferredDraftHeight(width: availableDraftWidth, font: font, maxDraftHeight: maxDraftHeight)
        draftFieldHeightConstraint?.constant = desiredDraftHeight
        draftScrollView.hasVerticalScroller = desiredDraftHeight >= maxDraftHeight - 0.5
        draftTextView.scrollRangeToVisible(draftTextView.selectedRange())

        let desiredPanelHeight = basePanelHeight - baseDraftFieldHeight + desiredDraftHeight
        resizePanel(width: desiredPanelWidth, height: desiredPanelHeight)
    }

    private func preferredDraftHeight(width: CGFloat, font: NSFont, maxDraftHeight: CGFloat) -> CGFloat {
        let measurementText = draftTextView.string.isEmpty ? " " : draftTextView.string
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping

        let availableTextWidth = max(width - (draftTextView.textContainerInset.width * 2), 40)
        let bounds = (measurementText as NSString).boundingRect(
            with: NSSize(width: availableTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ]
        )

        let verticalInset = draftTextView.textContainerInset.height * 2
        let contentHeight = ceil(bounds.height) + verticalInset
        return min(max(contentHeight, baseDraftFieldHeight), maxDraftHeight)
    }

    private func preferredMaxDraftHeight(font: NSFont, scale: Double) -> CGFloat {
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let verticalInset = draftTextView.textContainerInset.height * 2
        return max(baseDraftFieldHeight, (lineHeight * maxVisibleDraftLines) + verticalInset + (2.0 * scale))
    }

    private func resizePanel(width: CGFloat, height: CGFloat) {
        let oldFrame = panel.frame
        guard oldFrame.width > 0, oldFrame.height > 0 else {
            panel.setContentSize(NSSize(width: width, height: height))
            return
        }

        guard abs(oldFrame.width - width) > 0.5 || abs(oldFrame.height - height) > 0.5 else {
            return
        }

        var newFrame = oldFrame
        newFrame.size = NSSize(width: width, height: height)
        newFrame.origin.x = oldFrame.midX - (width / 2)
        newFrame.origin.y = oldFrame.maxY - height

        if let screen = panel.screen ?? NSScreen.main {
            let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            newFrame.origin.x = min(max(newFrame.origin.x, visible.minX), visible.maxX - width)
            newFrame.origin.y = min(max(newFrame.origin.y, visible.minY), visible.maxY - height)
        }

        panel.setFrame(newFrame, display: true)
    }
}

extension FloatingActionPanel: NSTextViewDelegate {
    func textDidBeginEditing(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        onDraftEditingBegan?()
    }

    func textDidChange(_ notification: Notification) {
        updatePanelSizeForDraftText()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertText("\n", replacementRange: textView.selectedRange())
            } else {
                runDraft()
            }
            return true
        }

        return false
    }
}
