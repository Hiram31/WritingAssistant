import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var promptPermissionItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var stateItem: NSMenuItem!
    private var draftMenuItem: NSMenuItem!
    private var settingsMenuItem: NSMenuItem!
    private var selectionController: SelectionController!
    private var settingsWindowController: SettingsWindowController!
    private var permissionTimer: Timer?
    private var settingsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        configureMenuBar()
        settingsWindowController = SettingsWindowController()

        selectionController = SelectionController()
        selectionController.onStatusChange = { [weak self] status in
            self?.updateStatus(status)
        }
        selectionController.onSettingsHotkey = { [weak self] in
            self?.openSettings()
        }
        selectionController.start()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: AppSettings.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            AppLog.info("Settings changed; reloading selection monitors.")
            self?.selectionController.reloadSettings()
            self?.updateMenuShortcuts()
        }

        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshPermissionState()
        }

        if !AppSettings.shared.hasLLMConfiguration {
            settingsWindowController.showWindow(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        selectionController.stop()
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = MenuBarIcon.image(for: .ready)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "WritingAssistant"

        let menu = NSMenu()
        stateItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        permissionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        permissionItem.isEnabled = false
        menu.addItem(permissionItem)

        menu.addItem(.separator())
        draftMenuItem = NSMenuItem(
            title: "New Draft...",
            action: #selector(openDraftComposer),
            keyEquivalent: ""
        )
        menu.addItem(draftMenuItem)
        settingsMenuItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        menu.addItem(settingsMenuItem)
        menu.addItem(NSMenuItem(
            title: "Open Log Folder",
            action: #selector(openLogFolder),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        promptPermissionItem = NSMenuItem(
            title: "Request Accessibility Permission",
            action: #selector(promptForAccessibility),
            keyEquivalent: ""
        )
        menu.addItem(promptPermissionItem)
        menu.addItem(NSMenuItem(
            title: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        ))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit WritingAssistant",
            action: #selector(quit),
            keyEquivalent: "q"
        ))

        statusItem.menu = menu
        updateMenuShortcuts()
        refreshPermissionState()
    }

    private func updateMenuShortcuts() {
        let settings = AppSettings.shared
        applyMenuShortcut(settings.hotkeysEnabled ? KeyboardShortcut(settings.draftComposerHotkey) : nil, to: draftMenuItem)
        applyMenuShortcut(settings.hotkeysEnabled ? KeyboardShortcut(settings.settingsHotkey) : nil, to: settingsMenuItem)
    }

    private func applyMenuShortcut(_ shortcut: KeyboardShortcut?, to menuItem: NSMenuItem?) {
        guard let menuItem else { return }

        guard let shortcut else {
            menuItem.keyEquivalent = ""
            menuItem.keyEquivalentModifierMask = []
            return
        }

        menuItem.keyEquivalent = shortcut.menuKeyEquivalent
        menuItem.keyEquivalentModifierMask = shortcut.menuModifierMask
    }

    private func updateStatus(_ status: AppStatus) {
        stateItem.title = status.title
        statusItem.button?.image = MenuBarIcon.image(for: status)
        statusItem.button?.toolTip = "WritingAssistant - \(status.title)"
    }

    private func refreshPermissionState() {
        let isTrusted = AccessibilityPermission.isTrusted
        permissionItem.title = isTrusted ? "Accessibility: granted" : "Accessibility: missing"
        promptPermissionItem?.isEnabled = !isTrusted
    }

    @objc private func promptForAccessibility() {
        let wasTrusted = AccessibilityPermission.isTrusted
        AccessibilityPermission.requestIfNeeded()
        refreshPermissionState()

        let isTrusted = AccessibilityPermission.isTrusted
        if isTrusted {
            showPermissionAlert(
                title: "Accessibility is already enabled",
                message: "WritingAssistant can read selected text and paste replacements."
            )
        } else if wasTrusted {
            showPermissionAlert(
                title: "Accessibility is already enabled",
                message: "No additional permission prompt is needed."
            )
        } else {
            showPermissionAlert(
                title: "Permission request sent",
                message: "If macOS did not show a prompt, open Accessibility Settings and enable the app that launched WritingAssistant, such as Terminal, iTerm, VS Code, Xcode, or the built WritingAssistant executable."
            )
        }
    }

    @objc private func openSettings() {
        settingsWindowController.showWindow(nil)
    }

    @objc private func openDraftComposer() {
        selectionController.showDraftComposer()
    }

    @objc private func openLogFolder() {
        let url = URL(fileURLWithPath: AppLog.logPath).deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showPermissionAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Open Settings")

        if alert.runModal() == .alertSecondButtonReturn {
            openAccessibilitySettings()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

enum AppStatus {
    case ready
    case missingPermission
    case working
    case replaced
    case failed(String)

    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .missingPermission:
            return "Grant Accessibility permission"
        case .working:
            return "Generating text..."
        case .replaced:
            return "Selection replaced"
        case .failed(let message):
            return "Error: \(message)"
        }
    }

}
