import AppKit

final class SelectionController {
    private let minimumMouseSelectionDragDistance: CGFloat = 8
    private let settings = AppSettings.shared
    private let panel = FloatingActionPanel()
    private let reader = SelectionReader()
    private let replacer = SelectionReplacer()
    private let rewriter = OpenAIRewriter()
    private let hotkeyRegistrar = GlobalHotkeyRegistrar()
    private var monitors: [Any] = []
    private var debounceWorkItem: DispatchWorkItem?
    private var pendingPanelWorkItem: DispatchWorkItem?
    private var autoHideWorkItem: DispatchWorkItem?
    private var currentContext: SelectionContext?
    private var lastExternalApplication: NSRunningApplication?
    private var workspaceObserver: NSObjectProtocol?
    private var lastPresentedSignature: String?
    private var lastPresentedAt = Date.distantPast
    private var lastHotkeyTriggeredAt = Date.distantPast
    private var mouseDownLocation: NSPoint?
    private var mouseSelectionCandidate = false

    var onStatusChange: ((AppStatus) -> Void)?
    var onSettingsHotkey: (() -> Void)?

    private var tuning: PopupTuning {
        settings.popupTuning
    }

    init() {
        panel.onAction = { [weak self] action in
            AppLog.info("Panel action clicked action=\(action.title)")
            self?.run(action)
        }
        panel.onDraftRequest = { [weak self] request in
            AppLog.info("Draft request submitted: \(AppLog.describeText(request))")
            self?.runDraft(request)
        }
        panel.onDraftEditingBegan = { [weak self] in
            AppLog.debug("Draft input focused; auto-hide cancelled.")
            self?.autoHideWorkItem?.cancel()
        }
    }

    func start() {
        AccessibilityPermission.requestIfNeeded()
        onStatusChange?(AccessibilityPermission.isTrusted ? .ready : .missingPermission)
        AppLog.info("Selection controller started accessibilityTrusted=\(AccessibilityPermission.isTrusted), logPath=\(AppLog.logPath)")
        rememberExternalApplication(NSWorkspace.shared.frontmostApplication, reason: "start")

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.rememberExternalApplication(application, reason: "activation")
        }

        if let localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            guard let self else { return event }
            if self.dismissPanelIfEscape(event, source: "local") {
                return nil
            }
            return event
        }) {
            monitors.append(localEscapeMonitor)
        }

        if let globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: { [weak self] event in
            _ = self?.dismissPanelIfEscape(event, source: "global")
        }) {
            monitors.append(globalEscapeMonitor)
        }

        if settings.hotkeysEnabled {
            registerGlobalHotkeys()
        } else if !settings.hotkeysEnabled {
            AppLog.info("Global hotkeys disabled.")
        }

        if let mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            guard let self else { return }
            let context = self.reader.currentContext()
            self.rememberExternalApplication(context.sourceApplication, reason: "mouseDown")
            self.currentContext = context
            self.mouseDownLocation = NSEvent.mouseLocation
            self.mouseSelectionCandidate = false
            self.cancelPendingPanelPresentation(reason: "mouseDown")
            self.panel.hide()
        }) {
            monitors.append(mouseDownMonitor)
        }

        if let mouseDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged], handler: { [weak self] _ in
            guard let self else { return }
            guard let mouseDownLocation = self.mouseDownLocation else { return }

            let currentLocation = NSEvent.mouseLocation
            let distance = hypot(currentLocation.x - mouseDownLocation.x, currentLocation.y - mouseDownLocation.y)
            guard distance >= self.minimumMouseSelectionDragDistance else {
                AppLog.debug("Ignoring tiny mouse drag distance=\(String(format: "%.1f", distance)), threshold=\(self.minimumMouseSelectionDragDistance)")
                return
            }

            self.mouseSelectionCandidate = true
            self.cancelPendingPanelPresentation(reason: "mouseDrag")
        }) {
            monitors.append(mouseDragMonitor)
        }

        if let mouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] event in
            guard let self else { return }
            if self.mouseSelectionCandidate || event.clickCount > 1 {
                self.scheduleSelectionCheck(trigger: .mouse)
            }
            self.mouseSelectionCandidate = false
            self.mouseDownLocation = nil
        }) {
            monitors.append(mouseUpMonitor)
        }

        if tuning.showForKeyboardSelection,
           let keyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp], handler: { [weak self] event in
            guard let self else { return }
            guard Date().timeIntervalSince(self.lastHotkeyTriggeredAt) > 0.75 else { return }
            if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command) {
                self.scheduleSelectionCheck(trigger: .keyboard)
            }
        }) {
            monitors.append(keyboardMonitor)
        }
    }

    func showDraftComposer() {
        cancelPendingPanelPresentation(reason: "manualDraftComposer")
        currentContext = contextForDraftInsertion()
        panel.show(near: NSEvent.mouseLocation, focusDraftField: true)
    }

    func showSelectionPopupForCurrentSelection() {
        cancelPendingPanelPresentation(reason: "manualSelectionPopup")
        panel.hide()
        checkSelection(trigger: .hotkey)
    }

    func stop() {
        AppLog.info("Selection controller stopping.")
        hotkeyRegistrar.unregisterAll()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        debounceWorkItem?.cancel()
        pendingPanelWorkItem?.cancel()
        autoHideWorkItem?.cancel()
    }

    func reloadSettings() {
        stop()
        start()
    }

    private func scheduleSelectionCheck(trigger: SelectionTrigger) {
        debounceWorkItem?.cancel()
        cancelPendingPanelPresentation(reason: "newSelectionCheck")
        AppLog.debug("Scheduling selection check trigger=\(trigger.title), delay=\(tuning.selectionReadDelay)")

        let item = DispatchWorkItem { [weak self] in
            self?.checkSelection(trigger: trigger)
        }
        debounceWorkItem = item

        DispatchQueue.main.asyncAfter(deadline: .now() + tuning.selectionReadDelay, execute: item)
    }

    private func checkSelection(trigger: SelectionTrigger) {
        guard AccessibilityPermission.isTrusted else {
            AppLog.warning("Selection check skipped because Accessibility permission is missing.")
            panel.hide()
            onStatusChange?(.missingPermission)
            return
        }

        let allowClipboardFallback = trigger == .hotkey
        reader.readSelectedText(allowClipboardFallback: allowClipboardFallback) { [weak self] context in
            guard let self else { return }

            guard let context else {
                AppLog.info("Selection check found no selected text trigger=\(trigger.title)")
                self.panel.hide()
                self.currentContext = nil
                self.onStatusChange?(.ready)
                return
            }

            self.currentContext = context
            if self.shouldShowPanel(for: context, trigger: trigger) {
                self.schedulePanelPresentation(for: context, trigger: trigger)
            } else if !self.isPresentableSelection(context.text) {
                AppLog.info("Hiding panel because selection is not presentable: \(self.notPresentableReason(context.text))")
                self.panel.hide()
            } else {
                AppLog.info("Panel suppressed trigger=\(trigger.title), selection \(AppLog.describeText(context.text))")
            }
            self.onStatusChange?(.ready)
        }
    }

    private func run(_ action: RewriteAction) {
        guard let context = currentContext else {
            AppLog.warning("Action ignored because there is no current selection context. action=\(action.title)")
            return
        }

        AppLog.info("Action starting action=\(action.title), app=\(context.applicationDescription), selection \(AppLog.describeText(context.text))")
        cancelPendingPanelPresentation(reason: "actionStarted")
        autoHideWorkItem?.cancel()
        panel.hide()
        onStatusChange?(.working)

        Task {
            do {
                let output = try await rewriter.process(context.text, action: action)
                await MainActor.run {
                    switch action.resultPresentation {
                    case .replaceSelection:
                        replacer.replaceSelection(with: output, context: context) { [weak self] in
                            AppLog.info("Action completed action=\(action.title), replacement \(AppLog.describeText(output))")
                            self?.onStatusChange?(.replaced)
                        }
                    case .displayInPanel:
                        AppLog.info("Action completed action=\(action.title), displayedResult \(AppLog.describeText(output))")
                        panel.showResult(output, title: action.displayTitle)
                        onStatusChange?(.ready)
                    }
                }
            } catch {
                await MainActor.run {
                    AppLog.error("Action failed action=\(action.title), error=\(error.localizedDescription)")
                    self.onStatusChange?(.failed(error.localizedDescription))
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = "Rewrite failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    private func runDraft(_ request: String) {
        let context = contextForDraftInsertion()
        let pasteContext = SelectionContext(
            text: "",
            focusedElement: nil,
            sourceApplication: context.sourceApplication
        )

        AppLog.info("Draft starting app=\(pasteContext.applicationDescription), request \(AppLog.describeText(request))")
        cancelPendingPanelPresentation(reason: "draftStarted")
        autoHideWorkItem?.cancel()
        panel.hide()
        onStatusChange?(.working)

        Task {
            do {
                let draft = try await rewriter.draft(for: request)
                await MainActor.run {
                    replacer.replaceSelection(with: draft, context: pasteContext) { [weak self] in
                        AppLog.info("Draft completed replacement \(AppLog.describeText(draft))")
                        self?.onStatusChange?(.replaced)
                    }
                }
            } catch {
                await MainActor.run {
                    AppLog.error("Draft failed error=\(error.localizedDescription)")
                    self.onStatusChange?(.failed(error.localizedDescription))
                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = "Draft failed"
                    alert.informativeText = error.localizedDescription
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        }
    }

    private func registerGlobalHotkeys() {
        var registeredHotkeys: [String] = []

        if let draftHotkey = KeyboardShortcut(settings.draftComposerHotkey),
           hotkeyRegistrar.register(shortcut: draftHotkey, id: 1, action: { [weak self] in
            self?.lastHotkeyTriggeredAt = Date()
            AppLog.info("Hotkey triggered action=draftComposer, shortcut=\(draftHotkey.displayString)")
            DispatchQueue.main.async {
                self?.showDraftComposer()
            }
        }) {
            registeredHotkeys.append("draft=\(draftHotkey.displayString)")
        }

        if let popupHotkey = KeyboardShortcut(settings.selectionPopupHotkey),
           hotkeyRegistrar.register(shortcut: popupHotkey, id: 2, action: { [weak self] in
            self?.lastHotkeyTriggeredAt = Date()
            AppLog.info("Hotkey triggered action=selectionPopup, shortcut=\(popupHotkey.displayString)")
            DispatchQueue.main.async {
                self?.showSelectionPopupForCurrentSelection()
            }
        }) {
            registeredHotkeys.append("selectionPopup=\(popupHotkey.displayString)")
        }

        if let settingsHotkey = KeyboardShortcut(settings.settingsHotkey),
           hotkeyRegistrar.register(shortcut: settingsHotkey, id: 3, action: { [weak self] in
            self?.lastHotkeyTriggeredAt = Date()
            AppLog.info("Hotkey triggered action=settings, shortcut=\(settingsHotkey.displayString)")
            DispatchQueue.main.async {
                self?.onSettingsHotkey?()
            }
        }) {
            registeredHotkeys.append("settings=\(settingsHotkey.displayString)")
        }

        AppLog.info("Global hotkeys enabled \(registeredHotkeys.isEmpty ? "noneRegistered" : registeredHotkeys.joined(separator: ", "))")
    }

    private func dismissPanelIfEscape(_ event: NSEvent, source: String) -> Bool {
        guard event.keyCode == 53,
              panel.isVisible else {
            return false
        }

        dismissPanel(reason: "escape-\(source)")
        return true
    }

    private func dismissPanel(reason: String) {
        AppLog.info("Panel dismissed reason=\(reason)")
        cancelPendingPanelPresentation(reason: reason)
        autoHideWorkItem?.cancel()
        panel.hide()
        onStatusChange?(.ready)
    }

    private func contextForDraftInsertion() -> SelectionContext {
        let liveContext = reader.currentContext()

        if isExternalApplication(liveContext.sourceApplication) {
            rememberExternalApplication(liveContext.sourceApplication, reason: "draftLiveContext")
            return liveContext
        }

        if let currentContext,
           isExternalApplication(currentContext.sourceApplication) {
            return currentContext
        }

        if let lastExternalApplication {
            AppLog.debug("Using last external app for draft insertion: \(lastExternalApplication.localizedName ?? "unknown")")
            return SelectionContext(text: "", focusedElement: nil, sourceApplication: lastExternalApplication)
        }

        AppLog.warning("No external app remembered for draft insertion; falling back to current context.")
        return liveContext
    }

    private func rememberExternalApplication(_ application: NSRunningApplication?, reason: String) {
        guard isExternalApplication(application) else { return }
        lastExternalApplication = application
        AppLog.debug("Remembered external app reason=\(reason), app=\(application?.localizedName ?? "unknown"), bundleID=\(application?.bundleIdentifier ?? "unknown")")
    }

    private func isExternalApplication(_ application: NSRunningApplication?) -> Bool {
        guard let application else { return false }
        return application.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    private func shouldShowPanel(for context: SelectionContext, trigger: SelectionTrigger) -> Bool {
        guard trigger == .mouse || trigger == .hotkey || tuning.showForKeyboardSelection else {
            return false
        }

        guard isPresentableSelection(context.text) else {
            return false
        }

        if trigger == .hotkey {
            return true
        }

        let now = Date()
        let signature = signature(for: context)
        let secondsSinceLastPresentation = now.timeIntervalSince(lastPresentedAt)

        if secondsSinceLastPresentation < tuning.popupCooldown {
            return false
        }

        if signature == lastPresentedSignature,
           secondsSinceLastPresentation < tuning.repeatSuppression {
            return false
        }

        return true
    }

    private func schedulePanelPresentation(for context: SelectionContext, trigger: SelectionTrigger) {
        pendingPanelWorkItem?.cancel()

        let signature = signature(for: context)
        let presentationPoint = NSEvent.mouseLocation
        let showDelay = trigger == .hotkey ? 0.0 : tuning.panelShowDelay
        AppLog.info("Panel queued trigger=\(trigger.title), delay=\(showDelay), app=\(context.applicationDescription), selection \(AppLog.describeText(context.text))")

        var item: DispatchWorkItem!
        item = DispatchWorkItem { [weak self] in
            guard let self,
                  !item.isCancelled,
                  self.pendingPanelWorkItem === item else { return }

            self.pendingPanelWorkItem = nil

            guard let currentContext = self.currentContext,
                  self.signature(for: currentContext) == signature else {
                AppLog.info("Panel queue cancelled because selection changed before display.")
                return
            }

            guard self.shouldShowPanel(for: currentContext, trigger: trigger) else {
                AppLog.info("Panel queue suppressed at display time trigger=\(trigger.title), selection \(AppLog.describeText(currentContext.text))")
                return
            }

            AppLog.info("Showing panel trigger=\(trigger.title), app=\(currentContext.applicationDescription), selection \(AppLog.describeText(currentContext.text))")
            self.lastPresentedSignature = signature
            self.lastPresentedAt = Date()
            self.panel.show(near: presentationPoint)
            self.scheduleAutoHide()
        }

        pendingPanelWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + showDelay, execute: item)
    }

    private func cancelPendingPanelPresentation(reason: String) {
        if pendingPanelWorkItem != nil {
            AppLog.debug("Pending panel presentation cancelled reason=\(reason)")
        }

        pendingPanelWorkItem?.cancel()
        pendingPanelWorkItem = nil
    }

    private func isPresentableSelection(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= tuning.minimumSelectionCharacters,
              trimmed.count <= tuning.maximumSelectionCharacters,
              trimmed.rangeOfCharacter(from: .letters) != nil else {
            return false
        }

        if trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return true
        }

        return trimmed.count >= tuning.minimumSingleTokenCharacters
    }

    private func notPresentableReason(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.count < tuning.minimumSelectionCharacters {
            return "tooShort chars=\(trimmed.count), min=\(tuning.minimumSelectionCharacters)"
        }

        if trimmed.count > tuning.maximumSelectionCharacters {
            return "tooLong chars=\(trimmed.count), max=\(tuning.maximumSelectionCharacters)"
        }

        if trimmed.rangeOfCharacter(from: .letters) == nil {
            return "noLetters chars=\(trimmed.count)"
        }

        if trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
           trimmed.count < tuning.minimumSingleTokenCharacters {
            return "singleTokenTooShort chars=\(trimmed.count), min=\(tuning.minimumSingleTokenCharacters)"
        }

        return "unknown"
    }

    private func signature(for context: SelectionContext) -> String {
        let processID = context.sourceApplication?.processIdentifier ?? 0
        return "\(processID):\(context.text)"
    }

    private func scheduleAutoHide() {
        autoHideWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            self?.panel.hide()
        }
        autoHideWorkItem = item

        DispatchQueue.main.asyncAfter(deadline: .now() + tuning.autoHideDelay, execute: item)
    }
}

private enum SelectionTrigger {
    case mouse
    case keyboard
    case hotkey

    var title: String {
        switch self {
        case .mouse:
            return "mouse"
        case .keyboard:
            return "keyboard"
        case .hotkey:
            return "hotkey"
        }
    }
}
