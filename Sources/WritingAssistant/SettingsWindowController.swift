import AppKit

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            close()
            return true
        }

        if routeStandardEditingShortcut(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    private func routeStandardEditingShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        if let textView = firstResponder as? NSTextView {
            return textView.performStandardEditingShortcut(event)
        }

        if let control = firstResponder as? NSControl,
           let editor = fieldEditor(false, for: control) as? NSTextView {
            return editor.performStandardEditingShortcut(event)
        }

        return false
    }
}

private extension NSTextView {
    func performStandardEditingShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers == .command || modifiers == [.command, .shift] else {
            return false
        }

        guard let key = event.charactersIgnoringModifiers?.lowercased() else {
            return false
        }

        switch key {
        case "a":
            setSelectedRange(NSRange(location: 0, length: (string as NSString).length))
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
            if modifiers.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default:
            return false
        }
    }
}

final class SettingsWindowController: NSWindowController {
    private let settings = AppSettings.shared

    private let providerPopup = NSPopUpButton()
    private let customAPIFormatPopup = NSPopUpButton()
    private let apiKeyField = NSSecureTextField()
    private let endpointField = NSTextField()
    private let deploymentField = NSTextField()
    private let apiVersionField = NSTextField()
    private let maxTokensField = NSTextField()
    private let baseURLHelpLabel = NSTextField(labelWithString: "")
    private var customAPIFormatRow: NSView?
    private var azureAPIVersionRow: NSView?

    private let selectionReadDelayField = NSTextField()
    private let panelShowDelayField = NSTextField()
    private let cooldownField = NSTextField()
    private let repeatSuppressionField = NSTextField()
    private let autoHideField = NSTextField()
    private let popupScaleField = NSTextField()
    private let popupPositionPopup = NSPopUpButton()
    private let popupOffsetXField = NSTextField()
    private let popupOffsetYField = NSTextField()
    private let minimumSelectionField = NSTextField()
    private let minimumSingleTokenField = NSTextField()
    private let maximumSelectionField = NSTextField()
    private let keyboardSelectionButton = NSButton(checkboxWithTitle: "Show after keyboard selection", target: nil, action: nil)

    private let hotkeysEnabledButton = NSButton(checkboxWithTitle: "Enable global hotkeys", target: nil, action: nil)
    private let draftComposerHotkeyField = ShortcutRecorderField()
    private let selectionPopupHotkeyField = ShortcutRecorderField()
    private let settingsHotkeyField = ShortcutRecorderField()

    private let replacementPopup = NSPopUpButton()
    private let pasteActivationDelayField = NSTextField()
    private let clipboardRestoreDelayField = NSTextField()

    private let debugLogsButton = NSButton(checkboxWithTitle: "Verbose monitor logs", target: nil, action: nil)
    private let logTextButton = NSButton(checkboxWithTitle: "Include selected text previews in logs", target: nil, action: nil)

    private let grammarPromptView = NSTextView()
    private let formalSupervisorPromptView = NSTextView()
    private let formalPartnersPromptView = NSTextView()
    private let fluencyPromptView = NSTextView()
    private let academicPromptView = NSTextView()
    private let englishToChinesePromptView = NSTextView()
    private let draftPromptView = NSTextView()
    private let grammarEnabledButton = NSButton(checkboxWithTitle: "Show in popup", target: nil, action: nil)
    private let formalSupervisorEnabledButton = NSButton(checkboxWithTitle: "Show in popup", target: nil, action: nil)
    private let formalPartnersEnabledButton = NSButton(checkboxWithTitle: "Show in popup", target: nil, action: nil)
    private let fluencyEnabledButton = NSButton(checkboxWithTitle: "Show in popup", target: nil, action: nil)
    private let academicEnabledButton = NSButton(checkboxWithTitle: "Show in popup", target: nil, action: nil)
    private let englishToChineseEnabledButton = NSButton(checkboxWithTitle: "Show in popup", target: nil, action: nil)
    private let customTuneStack = NSStackView()
    private var customTuneEditors: [CustomTuneEditor] = []
    private let statusLabel = NSTextField(labelWithString: "")

    init() {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 780),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WritingAssistant Settings"
        window.minSize = NSSize(width: 840, height: 640)
        window.center()

        super.init(window: window)

        window.contentView = makeContentView()
        loadSettings()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        loadSettings()
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeContentView() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let header = makeHeader()
        let tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.delegate = self
        tabView.addTabViewItem(makeTabItem(title: "AI", views: [makeProviderSection()]))
        tabView.addTabViewItem(makeTabItem(title: "Popup", views: [makePopupSection()]))
        tabView.addTabViewItem(makeTabItem(title: "Hotkeys", views: [makeHotkeysSection()]))
        tabView.addTabViewItem(makeTabItem(title: "Replacement", views: [makeReplacementSection()]))
        tabView.addTabViewItem(makeTabItem(title: "Logs", views: [makeLoggingSection()]))
        tabView.addTabViewItem(makeTabItem(title: "Prompts", views: [makePromptsSection()]))

        let footer = makeFooter()

        root.addSubview(header)
        root.addSubview(tabView)
        root.addSubview(footer)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),

            tabView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            tabView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            tabView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            tabView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        return root
    }

    private func makeTabItem(title: String, views: [NSView]) -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = title
        item.view = makeTabContentView(views: views)
        return item
    }

    private func makeTabContentView(views: [NSView]) -> NSView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

        let documentView = FlippedDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false

        let contentStack = NSStackView()
        contentStack.orientation = .vertical
        contentStack.spacing = 14
        contentStack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 24, right: 18)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        views.forEach { contentStack.addArrangedSubview($0) }

        documentView.addSubview(contentStack)
        scrollView.documentView = documentView

        NSLayoutConstraint.activate([
            documentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            contentStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: documentView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor)
        ])

        DispatchQueue.main.async { [weak scrollView] in
            scrollView?.scrollToTop()
        }

        return scrollView
    }

    private func makeHeader() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "WritingAssistant")
        title.font = .systemFont(ofSize: 28, weight: .semibold)
        title.textColor = .labelColor
        title.alignment = .center

        let subtitle = NSTextField(labelWithString: "Configure providers, popup timing, hotkeys, replacement, logs, and prompts without touching Terminal.")
        subtitle.font = .systemFont(ofSize: 13, weight: .regular)
        subtitle.textColor = .secondaryLabelColor
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2

        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -18)
        ])

        return container
    }

    private func makeProviderSection() -> NSView {
        providerPopup.removeAllItems()
        LLMProvider.selectableCases.forEach { providerPopup.addItem(withTitle: $0.displayName) }
        providerPopup.target = self
        providerPopup.action = #selector(providerChanged)

        customAPIFormatPopup.removeAllItems()
        CustomAPIFormat.allCases.forEach { customAPIFormatPopup.addItem(withTitle: $0.displayName) }
        customAPIFormatPopup.target = self
        customAPIFormatPopup.action = #selector(customAPIFormatChanged)

        configureTextField(endpointField, placeholder: "")
        configureTextField(deploymentField, placeholder: "gpt-4o-mini")
        configureTextField(apiVersionField, placeholder: "2024-10-21")
        configureTextField(maxTokensField, placeholder: "900")
        configureTextField(apiKeyField, placeholder: "Stored securely in Keychain. Optional for Ollama.")

        let testButton = NSButton(title: "Test Provider", target: self, action: #selector(testProvider))
        testButton.bezelStyle = .rounded

        let saveButton = NSButton(title: "Save Settings", target: self, action: #selector(saveSettingsFromButton))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let buttonRow = NSStackView(views: [testButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY
        buttonRow.setHuggingPriority(.defaultHigh, for: .horizontal)

        let azureRow = formRow("Azure API version", "Only used by Azure OpenAI.", apiVersionField)
        azureAPIVersionRow = azureRow
        let customFormatRow = formRow("API format", "Only used by Custom AI provider.", customAPIFormatPopup)
        customAPIFormatRow = customFormatRow

        return makeSection(
            title: "AI Provider",
            subtitle: "Choose Azure OpenAI, local Ollama, or a custom AI provider. API keys are saved in macOS Keychain.",
            views: [
                formRow("Provider", "Select which service handles rewrite and draft requests.", providerPopup),
                customFormatRow,
                formRow("API key", "Required except for local Ollama. Stored in Keychain.", apiKeyField),
                formRow("Base URL", baseURLHelpLabel, endpointField),
                formRow("Model / deployment", "Azure uses deployment name. Other providers use model name.", deploymentField),
                azureRow,
                formRow("Max output tokens", "Upper bound for generated text.", maxTokensField),
                trailingRow(buttonRow)
            ]
        )
    }

    private func makePopupSection() -> NSView {
        [
            selectionReadDelayField,
            panelShowDelayField,
            cooldownField,
            repeatSuppressionField,
            autoHideField,
            popupScaleField,
            popupOffsetXField,
            popupOffsetYField,
            minimumSelectionField,
            minimumSingleTokenField,
            maximumSelectionField
        ].forEach { configureTextField($0, placeholder: "") }

        popupPositionPopup.removeAllItems()
        PopupPosition.allCases.forEach { popupPositionPopup.addItem(withTitle: $0.displayName) }

        return makeSection(
            title: "Popup Behavior",
            subtitle: "These controls tune timing, noise level, size, and placement.",
            views: [
                formRow("Read delay", "Seconds to wait before reading the selection.", selectionReadDelayField),
                formRow("Show delay", "Seconds to wait after reading before showing the panel.", panelShowDelayField),
                formRow("Cooldown", "Minimum seconds between popups.", cooldownField),
                formRow("Repeat suppression", "Seconds to suppress the same selected text.", repeatSuppressionField),
                formRow("Auto-hide", "Seconds before the panel disappears.", autoHideField),
                formRow("Panel scale", "Compact by default. Try 0.75 to 1.20.", popupScaleField),
                formRow("Panel position", "Where the popup appears relative to selection.", popupPositionPopup),
                formRow("Offset X", "Fine tune horizontal placement in points.", popupOffsetXField),
                formRow("Offset Y", "Fine tune vertical placement in points.", popupOffsetYField),
                formRow("Minimum chars", "Ignore selections shorter than this.", minimumSelectionField),
                formRow("Single-word minimum", "Ignore short one-word selections.", minimumSingleTokenField),
                formRow("Maximum chars", "Ignore very long selections.", maximumSelectionField),
                checkboxRow("Keyboard selections", "Off by default to reduce interruptions.", keyboardSelectionButton)
            ]
        )
    }

    private func makeReplacementSection() -> NSView {
        replacementPopup.removeAllItems()
        ReplacementStrategy.allCases.forEach { replacementPopup.addItem(withTitle: $0.displayName) }
        replacementPopup.target = self
        replacementPopup.action = #selector(replacementChanged)

        configureTextField(pasteActivationDelayField, placeholder: "0.20")
        configureTextField(clipboardRestoreDelayField, placeholder: "0.80")

        return makeSection(
            title: "Replacement",
            subtitle: "Paste is the default because Slack and similar apps can report Accessibility replacement success without changing text.",
            views: [
                formRow("Strategy", "Choose how rewritten text replaces the selection.", replacementPopup),
                formRow("Paste delay", "Seconds to wait after activating the source app.", pasteActivationDelayField),
                formRow("Clipboard restore", "Seconds to wait before restoring your previous clipboard.", clipboardRestoreDelayField)
            ]
        )
    }

    private func makeHotkeysSection() -> NSView {
        configureShortcutRecorder(draftComposerHotkeyField)
        configureShortcutRecorder(selectionPopupHotkeyField)
        configureShortcutRecorder(settingsHotkeyField)

        return makeSection(
            title: "Hotkeys",
            subtitle: "Click a shortcut field, then press the keys you want. Press Delete while focused to clear it.",
            views: [
                checkboxRow("Global hotkeys", "Turn off if any shortcut conflicts with another app.", hotkeysEnabledButton),
                formRow("New draft", "Open the draft composer for the current app.", draftComposerHotkeyField),
                formRow("Selection popup", "Read current selection and show the rewrite popup.", selectionPopupHotkeyField),
                formRow("Settings", "Open the WritingAssistant settings window.", settingsHotkeyField)
            ]
        )
    }

    private func makeLoggingSection() -> NSView {
        let openLogButton = NSButton(title: "Open Log Folder", target: self, action: #selector(openLogFolder))
        openLogButton.bezelStyle = .rounded

        let tailHint = NSTextField(labelWithString: AppLog.logPath)
        tailHint.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tailHint.textColor = .secondaryLabelColor
        tailHint.lineBreakMode = .byTruncatingMiddle

        return makeSection(
            title: "Logs",
            subtitle: "Logs help debug selection, provider requests, and paste replacement.",
            views: [
                checkboxRow("Debug logging", "Adds verbose selection monitor messages.", debugLogsButton),
                checkboxRow("Text previews", "Includes a short selected-text preview in logs. Leave off for privacy.", logTextButton),
                formRow("Log file", "Written while the app runs.", tailHint),
                trailingRow(openLogButton)
            ]
        )
    }

    private func makePromptsSection() -> NSView {
        configurePromptView(grammarPromptView)
        configurePromptView(formalSupervisorPromptView)
        configurePromptView(formalPartnersPromptView)
        configurePromptView(fluencyPromptView)
        configurePromptView(academicPromptView)
        configurePromptView(englishToChinesePromptView)
        configurePromptView(draftPromptView)

        customTuneStack.orientation = .vertical
        customTuneStack.alignment = .centerX
        customTuneStack.spacing = 10
        customTuneStack.widthAnchor.constraint(equalToConstant: SettingsLayout.formWidth).isActive = true

        let addButton = NSButton(title: "+ Add Style", target: self, action: #selector(addCustomTune))
        addButton.bezelStyle = .rounded

        let resetButton = NSButton(title: "Reset Built-in Prompts", target: self, action: #selector(resetPrompts))
        resetButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [addButton, resetButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        return makeSection(
            title: "Prompts",
            subtitle: "Customize the instructions used by each popup action. The app still returns only replacement text.",
            views: [
                builtInPromptRow("Fix grammar", grammarPromptView, grammarEnabledButton),
                builtInPromptRow("Supervisor", formalSupervisorPromptView, formalSupervisorEnabledButton),
                builtInPromptRow("Partners", formalPartnersPromptView, formalPartnersEnabledButton),
                builtInPromptRow("Fluency", fluencyPromptView, fluencyEnabledButton),
                builtInPromptRow("Academic", academicPromptView, academicEnabledButton),
                builtInPromptRow("English to Chinese", englishToChinesePromptView, englishToChineseEnabledButton),
                promptRow("Draft composer", draftPromptView, help: "System instructions for generating new text from the draft field."),
                customTuneStack,
                trailingRow(buttonRow)
            ]
        )
    }

    private func makeFooter() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let resetButton = NSButton(title: "Reset Behavior", target: self, action: #selector(resetBehavior))
        resetButton.bezelStyle = .rounded

        let saveButton = NSButton(title: "Save Settings", target: self, action: #selector(saveSettingsFromButton))
        saveButton.bezelStyle = .rounded

        let buttons = NSStackView(views: [resetButton, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10

        let stack = NSStackView(views: [statusLabel, buttons])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttons.setContentHuggingPriority(.required, for: .horizontal)

        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        return container
    }

    private func makeSection(title: String, subtitle: String, views: [NSView]) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.70).cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.widthAnchor.constraint(equalToConstant: SettingsLayout.formWidth).isActive = true

        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.lineBreakMode = .byWordWrapping
        subtitleLabel.maximumNumberOfLines = 3
        subtitleLabel.widthAnchor.constraint(equalToConstant: SettingsLayout.formWidth).isActive = true

        let stack = NSStackView(views: [titleLabel, subtitleLabel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 7
        views.forEach { stack.addArrangedSubview($0) }
        stack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20)
        ])

        return container
    }

    private func formRow(_ title: String, _ help: String, _ control: NSView) -> NSView {
        formRow(title, NSTextField(labelWithString: help), control)
    }

    private func formRow(_ title: String, _ helpLabel: NSTextField, _ control: NSView) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.alignment = .right
        titleLabel.lineBreakMode = .byTruncatingTail

        helpLabel.font = .systemFont(ofSize: 11)
        helpLabel.textColor = .secondaryLabelColor
        helpLabel.alignment = .right
        helpLabel.lineBreakMode = .byWordWrapping
        helpLabel.maximumNumberOfLines = 3

        let labels = NSStackView(views: [titleLabel, helpLabel])
        labels.orientation = .vertical
        labels.alignment = .trailing
        labels.spacing = 3
        labels.widthAnchor.constraint(equalToConstant: SettingsLayout.labelColumnWidth).isActive = true

        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: SettingsLayout.controlColumnWidth).isActive = true

        let row = NSStackView(views: [labels, control])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = SettingsLayout.columnSpacing
        row.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 2, right: 0)
        row.widthAnchor.constraint(equalToConstant: SettingsLayout.formWidth).isActive = true

        return row
    }

    private func checkboxRow(_ title: String, _ help: String, _ button: NSButton) -> NSView {
        button.target = nil
        button.action = nil
        return formRow(title, help, button)
    }

    private func promptRow(_ title: String, _ textView: NSTextView, help: String = "System instructions for this action.") -> NSView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        scrollView.heightAnchor.constraint(equalToConstant: 104).isActive = true
        return formRow(title, help, scrollView)
    }

    private func builtInPromptRow(_ title: String, _ textView: NSTextView, _ enabledButton: NSButton) -> NSView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView
        scrollView.heightAnchor.constraint(equalToConstant: 104).isActive = true

        enabledButton.target = nil
        enabledButton.action = nil

        let controlStack = NSStackView(views: [enabledButton, scrollView])
        controlStack.orientation = .vertical
        controlStack.alignment = .leading
        controlStack.spacing = 8
        controlStack.widthAnchor.constraint(equalToConstant: SettingsLayout.controlColumnWidth).isActive = true

        return formRow(title, "Uncheck to remove this default tune from the popup.", controlStack)
    }

    private func trailingRow(_ view: NSView) -> NSView {
        let labelSpacer = NSView()
        labelSpacer.widthAnchor.constraint(equalToConstant: SettingsLayout.labelColumnWidth).isActive = true

        let controlArea = NSStackView()
        controlArea.orientation = .horizontal
        controlArea.alignment = .centerY
        controlArea.spacing = 0
        controlArea.widthAnchor.constraint(equalToConstant: SettingsLayout.controlColumnWidth).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        controlArea.addArrangedSubview(spacer)
        controlArea.addArrangedSubview(view)

        let row = NSStackView(views: [labelSpacer, controlArea])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = SettingsLayout.columnSpacing
        row.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        row.widthAnchor.constraint(equalToConstant: SettingsLayout.formWidth).isActive = true
        return row
    }

    private func configureTextField(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingTail
        field.controlSize = .large
        field.heightAnchor.constraint(equalToConstant: SettingsLayout.controlHeight).isActive = true
    }

    private func configureShortcutRecorder(_ field: ShortcutRecorderField) {
        field.controlSize = .large
        field.heightAnchor.constraint(equalToConstant: SettingsLayout.controlHeight).isActive = true
    }

    private func configurePromptView(_ textView: NSTextView) {
        textView.font = .systemFont(ofSize: 12)
        textView.isRichText = false
        textView.usesFindBar = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
    }

    private func loadSettings() {
        let provider = settings.llmProvider
        providerPopup.selectItem(withTitle: provider.displayName)
        customAPIFormatPopup.selectItem(withTitle: settings.customAPIFormat.displayName)
        apiKeyField.stringValue = settings.apiKey(for: provider)
        endpointField.stringValue = settings.baseURL(for: provider)
        deploymentField.stringValue = settings.modelName(for: provider)
        apiVersionField.stringValue = settings.azureAPIVersion
        maxTokensField.stringValue = "\(settings.maxCompletionTokens)"
        updateProviderSpecificRows(for: provider)

        selectionReadDelayField.stringValue = formatted(settings.selectionReadDelay)
        panelShowDelayField.stringValue = formatted(settings.panelShowDelay)
        cooldownField.stringValue = formatted(settings.popupCooldown)
        repeatSuppressionField.stringValue = formatted(settings.repeatSuppression)
        autoHideField.stringValue = formatted(settings.autoHideDelay)
        popupScaleField.stringValue = formatted(settings.popupScale)
        popupPositionPopup.selectItem(withTitle: settings.popupPosition.displayName)
        popupOffsetXField.stringValue = formatted(settings.popupOffsetX)
        popupOffsetYField.stringValue = formatted(settings.popupOffsetY)
        minimumSelectionField.stringValue = "\(settings.minimumSelectionCharacters)"
        minimumSingleTokenField.stringValue = "\(settings.minimumSingleTokenCharacters)"
        maximumSelectionField.stringValue = "\(settings.maximumSelectionCharacters)"
        keyboardSelectionButton.state = settings.showForKeyboardSelection ? .on : .off

        hotkeysEnabledButton.state = settings.hotkeysEnabled ? .on : .off
        draftComposerHotkeyField.shortcutString = displayShortcut(settings.draftComposerHotkey)
        selectionPopupHotkeyField.shortcutString = displayShortcut(settings.selectionPopupHotkey)
        settingsHotkeyField.shortcutString = displayShortcut(settings.settingsHotkey)

        let selectedStrategy = settings.replacementStrategy
        replacementPopup.selectItem(withTitle: selectedStrategy.displayName)
        pasteActivationDelayField.stringValue = formatted(settings.pasteActivationDelay)
        clipboardRestoreDelayField.stringValue = formatted(settings.clipboardRestoreDelay)

        debugLogsButton.state = settings.debugLogs ? .on : .off
        logTextButton.state = settings.logSelectedText ? .on : .off

        grammarPromptView.string = settings.grammarInstructions
        formalSupervisorPromptView.string = settings.formalSupervisorInstructions
        formalPartnersPromptView.string = settings.formalPartnersInstructions
        fluencyPromptView.string = settings.fluencyInstructions
        academicPromptView.string = settings.academicInstructions
        englishToChinesePromptView.string = settings.englishToChineseInstructions
        draftPromptView.string = settings.draftInstructions
        loadBuiltInTuneVisibility()
        reloadCustomTuneEditors(settings.customTunes)
        setStatus("Settings loaded.", isError: false)
    }

    @objc private func saveSettingsFromButton() {
        do {
            try saveSettings()
            setStatus("Saved. Changes apply immediately.", isError: false)
        } catch {
            setStatus(error.localizedDescription, isError: true)
        }
    }

    private func saveSettings() throws {
        let provider = selectedLLMProvider()
        settings.llmProvider = provider
        settings.customAPIFormat = selectedCustomAPIFormat()
        settings.setAPIKey(apiKeyField.stringValue, for: provider)
        settings.setBaseURL(endpointField.stringValue, for: provider)
        settings.setModelName(deploymentField.stringValue, for: provider)
        settings.azureAPIVersion = apiVersionField.stringValue
        settings.maxCompletionTokens = try intValue(maxTokensField, name: "Max output tokens")

        settings.selectionReadDelay = try doubleValue(selectionReadDelayField, name: "Read delay")
        settings.panelShowDelay = try doubleValue(panelShowDelayField, name: "Show delay")
        settings.popupCooldown = try doubleValue(cooldownField, name: "Cooldown")
        settings.repeatSuppression = try doubleValue(repeatSuppressionField, name: "Repeat suppression")
        settings.autoHideDelay = try doubleValue(autoHideField, name: "Auto-hide")
        settings.popupScale = try doubleValue(popupScaleField, name: "Panel scale")
        settings.popupPosition = selectedPopupPosition()
        settings.popupOffsetX = try doubleValue(popupOffsetXField, name: "Offset X")
        settings.popupOffsetY = try doubleValue(popupOffsetYField, name: "Offset Y")
        settings.minimumSelectionCharacters = try intValue(minimumSelectionField, name: "Minimum chars")
        settings.minimumSingleTokenCharacters = try intValue(minimumSingleTokenField, name: "Single-word minimum")
        settings.maximumSelectionCharacters = try intValue(maximumSelectionField, name: "Maximum chars")
        settings.showForKeyboardSelection = keyboardSelectionButton.state == .on

        let draftHotkey = try shortcutValue(draftComposerHotkeyField, name: "New draft hotkey")
        let popupHotkey = try shortcutValue(selectionPopupHotkeyField, name: "Selection popup hotkey")
        let settingsHotkey = try shortcutValue(settingsHotkeyField, name: "Settings hotkey")
        let nonEmptyHotkeys = [draftHotkey, popupHotkey, settingsHotkey].filter { !$0.isEmpty }
        if Set(nonEmptyHotkeys).count != nonEmptyHotkeys.count {
            throw SettingsValidationError.duplicateShortcut
        }
        settings.hotkeysEnabled = hotkeysEnabledButton.state == .on
        settings.draftComposerHotkey = draftHotkey
        settings.selectionPopupHotkey = popupHotkey
        settings.settingsHotkey = settingsHotkey

        settings.replacementStrategy = selectedReplacementStrategy()
        settings.pasteActivationDelay = try doubleValue(pasteActivationDelayField, name: "Paste delay")
        settings.clipboardRestoreDelay = try doubleValue(clipboardRestoreDelayField, name: "Clipboard restore")

        settings.debugLogs = debugLogsButton.state == .on
        settings.logSelectedText = logTextButton.state == .on
        settings.grammarInstructions = grammarPromptView.string
        settings.formalSupervisorInstructions = formalSupervisorPromptView.string
        settings.formalPartnersInstructions = formalPartnersPromptView.string
        settings.fluencyInstructions = fluencyPromptView.string
        settings.academicInstructions = academicPromptView.string
        settings.englishToChineseInstructions = englishToChinesePromptView.string
        settings.draftInstructions = draftPromptView.string
        settings.enabledBuiltInActionIDs = selectedBuiltInTuneIDs()
        settings.customTunes = customTuneEditors.map { customTuneValue(from: $0) }
        settings.notifyChanged()
    }

    @objc private func testProvider() {
        do {
            try saveSettings()
        } catch {
            setStatus(error.localizedDescription, isError: true)
            return
        }

        setStatus("Testing provider connection...", isError: false)
        Task {
            do {
                let output = try await OpenAIRewriter().process("This is a test sentence.", action: .grammar)
                await MainActor.run {
                    self.setStatus("Provider test passed: \(output)", isError: false)
                }
            } catch {
                await MainActor.run {
                    self.setStatus("Provider test failed: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }

    @objc private func openLogFolder() {
        let url = URL(fileURLWithPath: AppLog.logPath).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func resetBehavior() {
        settings.resetBehaviorDefaults()
        loadSettings()
        setStatus("Behavior, hotkey, replacement, and log settings reset.", isError: false)
    }

    @objc private func resetPrompts() {
        settings.resetPromptDefaults()
        loadSettings()
        setStatus("Built-in prompts reset. Custom styles were kept.", isError: false)
    }

    @objc private func addCustomTune() {
        appendCustomTuneEditor(CustomTune.makeDefault())
        setStatus("Custom style added. Edit it, then save settings.", isError: false)
    }

    @objc private func removeCustomTune(_ sender: NSButton) {
        guard customTuneEditors.indices.contains(sender.tag) else { return }
        let editor = customTuneEditors.remove(at: sender.tag)
        customTuneStack.removeArrangedSubview(editor.container)
        editor.container.removeFromSuperview()
        refreshCustomTuneRemoveButtonTags()
        setStatus("Custom style removed. Save settings to keep this change.", isError: false)
    }

    @objc private func replacementChanged() {
        let strategy = selectedReplacementStrategy()
        setStatus(strategy.helpText, isError: false)
    }

    @objc private func providerChanged() {
        let provider = selectedLLMProvider()
        apiKeyField.stringValue = settings.apiKey(for: provider)
        endpointField.stringValue = settings.baseURL(for: provider)
        deploymentField.stringValue = settings.modelName(for: provider)
        updateProviderSpecificRows(for: provider)
        setStatus("Selected \(provider.displayName). Configure the fields, then save settings.", isError: false)
    }

    @objc private func customAPIFormatChanged() {
        guard selectedLLMProvider() == .customOpenAICompatible else { return }
        let format = selectedCustomAPIFormat()
        let currentBaseURL = endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentModel = deploymentField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if currentBaseURL.isEmpty || CustomAPIFormat.allCases.map(\.defaultBaseURL).contains(currentBaseURL) {
            endpointField.stringValue = format.defaultBaseURL
        }
        if currentModel.isEmpty || CustomAPIFormat.allCases.map(\.defaultModel).contains(currentModel) {
            deploymentField.stringValue = format.defaultModel
        }

        updateProviderSpecificRows(for: .customOpenAICompatible)
        setStatus("Selected \(format.displayName). Save settings before testing.", isError: false)
    }

    private func updateProviderSpecificRows(for provider: LLMProvider) {
        azureAPIVersionRow?.isHidden = provider != .azureOpenAI
        customAPIFormatRow?.isHidden = provider != .customOpenAICompatible

        if provider == .customOpenAICompatible {
            let format = selectedCustomAPIFormat()
            endpointField.placeholderString = format.baseURLPlaceholder
            deploymentField.placeholderString = format.defaultModel
            baseURLHelpLabel.stringValue = format.baseURLHelpText
        } else {
            endpointField.placeholderString = provider.baseURLPlaceholder
            deploymentField.placeholderString = provider.defaultModel
            baseURLHelpLabel.stringValue = provider.baseURLHelpText
        }

        azureAPIVersionRow?.superview?.layoutSubtreeIfNeeded()
        customAPIFormatRow?.superview?.layoutSubtreeIfNeeded()
    }

    private func selectedLLMProvider() -> LLMProvider {
        let title = providerPopup.selectedItem?.title
        return LLMProvider.selectableCases.first { $0.displayName == title } ?? .azureOpenAI
    }

    private func selectedCustomAPIFormat() -> CustomAPIFormat {
        let title = customAPIFormatPopup.selectedItem?.title
        return CustomAPIFormat.allCases.first { $0.displayName == title } ?? .openAIChatCompletions
    }

    private func selectedReplacementStrategy() -> ReplacementStrategy {
        let title = replacementPopup.selectedItem?.title
        return ReplacementStrategy.allCases.first { $0.displayName == title } ?? .paste
    }

    private func selectedPopupPosition() -> PopupPosition {
        let title = popupPositionPopup.selectedItem?.title
        return PopupPosition.allCases.first { $0.displayName == title } ?? .above
    }

    private func loadBuiltInTuneVisibility() {
        let enabledIDs = Set(settings.enabledBuiltInActionIDs)
        grammarEnabledButton.state = enabledIDs.contains(BuiltInTune.grammar.id) ? .on : .off
        formalSupervisorEnabledButton.state = enabledIDs.contains(BuiltInTune.formalSupervisor.id) ? .on : .off
        formalPartnersEnabledButton.state = enabledIDs.contains(BuiltInTune.formalPartners.id) ? .on : .off
        fluencyEnabledButton.state = enabledIDs.contains(BuiltInTune.fluency.id) ? .on : .off
        academicEnabledButton.state = enabledIDs.contains(BuiltInTune.academic.id) ? .on : .off
        englishToChineseEnabledButton.state = enabledIDs.contains(BuiltInTune.englishToChinese.id) ? .on : .off
    }

    private func selectedBuiltInTuneIDs() -> [String] {
        var ids: [String] = []
        if grammarEnabledButton.state == .on { ids.append(BuiltInTune.grammar.id) }
        if formalSupervisorEnabledButton.state == .on { ids.append(BuiltInTune.formalSupervisor.id) }
        if formalPartnersEnabledButton.state == .on { ids.append(BuiltInTune.formalPartners.id) }
        if fluencyEnabledButton.state == .on { ids.append(BuiltInTune.fluency.id) }
        if academicEnabledButton.state == .on { ids.append(BuiltInTune.academic.id) }
        if englishToChineseEnabledButton.state == .on { ids.append(BuiltInTune.englishToChinese.id) }
        return ids
    }

    private func reloadCustomTuneEditors(_ tunes: [CustomTune]) {
        customTuneEditors.forEach { editor in
            customTuneStack.removeArrangedSubview(editor.container)
            editor.container.removeFromSuperview()
        }
        customTuneEditors.removeAll()
        tunes.forEach(appendCustomTuneEditor)
    }

    private func appendCustomTuneEditor(_ tune: CustomTune) {
        let nameField = NSTextField()
        configureTextField(nameField, placeholder: "Custom style name")
        nameField.stringValue = tune.name

        let shortLabelField = NSTextField()
        configureTextField(shortLabelField, placeholder: "3-5 chars")
        shortLabelField.stringValue = tune.shortLabel

        let promptView = NSTextView()
        configurePromptView(promptView)
        promptView.string = tune.instructions

        let removeButton = NSButton(title: "Remove Style", target: self, action: #selector(removeCustomTune(_:)))
        removeButton.bezelStyle = .rounded

        let customRows = NSStackView()
        customRows.orientation = .vertical
        customRows.alignment = .centerX
        customRows.spacing = 3
        customRows.translatesAutoresizingMaskIntoConstraints = false

        customRows.addArrangedSubview(formRow("Style name", "Shown in Settings and button tooltip.", nameField))
        customRows.addArrangedSubview(formRow("Popup label", "Short label shown in the floating popup.", shortLabelField))
        customRows.addArrangedSubview(promptRow("Prompt", promptView))
        customRows.addArrangedSubview(trailingRow(removeButton))

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
        container.addSubview(customRows)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: SettingsLayout.formWidth),
            customRows.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            customRows.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            customRows.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            customRows.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
        ])

        let editor = CustomTuneEditor(
            id: tune.id,
            container: container,
            nameField: nameField,
            shortLabelField: shortLabelField,
            promptView: promptView,
            removeButton: removeButton
        )
        customTuneEditors.append(editor)
        customTuneStack.addArrangedSubview(container)
        refreshCustomTuneRemoveButtonTags()
    }

    private func refreshCustomTuneRemoveButtonTags() {
        for (index, editor) in customTuneEditors.enumerated() {
            editor.removeButton.tag = index
        }
    }

    private func customTuneValue(from editor: CustomTuneEditor) -> CustomTune {
        let name = cleaned(editor.nameField.stringValue, fallback: "Custom")
        let shortLabel = cleanedShortLabel(editor.shortLabelField.stringValue, fallbackSource: name)
        let instructions = cleaned(editor.promptView.string, fallback: CustomTune.makeDefault().instructions)

        return CustomTune(
            id: editor.id,
            name: name,
            shortLabel: shortLabel,
            instructions: instructions
        )
    }

    private func cleaned(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func cleanedShortLabel(_ value: String, fallbackSource: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = trimmed.isEmpty ? fallbackSource : trimmed
        let lettersAndNumbers = source.filter { $0.isLetter || $0.isNumber }
        let label = String((lettersAndNumbers.isEmpty ? "Cus" : String(lettersAndNumbers)).prefix(5))
        return label.isEmpty ? "Cus" : label
    }

    private func setStatus(_ text: String, isError: Bool) {
        statusLabel.stringValue = text
        statusLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    private func doubleValue(_ field: NSTextField, name: String) throws -> Double {
        guard let value = Double(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SettingsValidationError.invalidNumber(name)
        }
        return value
    }

    private func intValue(_ field: NSTextField, name: String) throws -> Int {
        guard let value = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw SettingsValidationError.invalidNumber(name)
        }
        return value
    }

    private func shortcutValue(_ field: ShortcutRecorderField, name: String) throws -> String {
        let rawValue = field.shortcutString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else { return "" }
        guard let shortcut = KeyboardShortcut(rawValue) else {
            throw SettingsValidationError.invalidShortcut(name)
        }
        return shortcut.displayString
    }

    private func displayShortcut(_ value: String) -> String {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return KeyboardShortcut(value)?.displayString ?? value
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

private enum SettingsValidationError: LocalizedError {
    case invalidNumber(String)
    case invalidShortcut(String)
    case duplicateShortcut

    var errorDescription: String? {
        switch self {
        case .invalidNumber(let field):
            return "\(field) must be a number."
        case .invalidShortcut(let field):
            return "\(field) must look like Ctrl+Opt+Cmd+D. Use at least one of Cmd, Opt, or Ctrl plus one key."
        case .duplicateShortcut:
            return "Global hotkeys must be different."
        }
    }
}

private struct CustomTuneEditor {
    let id: String
    let container: NSView
    let nameField: NSTextField
    let shortLabelField: NSTextField
    let promptView: NSTextView
    let removeButton: NSButton
}

private enum SettingsLayout {
    static let labelColumnWidth: CGFloat = 220
    static let controlColumnWidth: CGFloat = 500
    static let columnSpacing: CGFloat = 20
    static let controlHeight: CGFloat = 30
    static let formWidth: CGFloat = labelColumnWidth + columnSpacing + controlColumnWidth
}

extension SettingsWindowController: NSTabViewDelegate {
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        DispatchQueue.main.async {
            tabViewItem?.view?.firstDescendantScrollView?.scrollToTop()
        }
    }
}

private extension NSView {
    var firstDescendantScrollView: NSScrollView? {
        if let scrollView = self as? NSScrollView {
            return scrollView
        }

        for subview in subviews {
            if let scrollView = subview.firstDescendantScrollView {
                return scrollView
            }
        }

        return nil
    }
}

private extension NSScrollView {
    func scrollToTop() {
        guard let documentView else { return }

        let targetY: CGFloat
        if documentView.isFlipped {
            targetY = 0
        } else {
            targetY = max(0, documentView.bounds.height - contentView.bounds.height)
        }

        contentView.scroll(to: NSPoint(x: 0, y: targetY))
        reflectScrolledClipView(contentView)
    }
}
