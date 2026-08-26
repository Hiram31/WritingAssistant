import Foundation

final class AppSettings {
    static let shared = AppSettings()
    static let didChangeNotification = Notification.Name("WritingAssistant.AppSettings.didChange")

    private let defaults: UserDefaults
    private let keychain = KeychainStore(service: "WritingAssistant.AzureOpenAI", account: "api-key")
    private let legacyKeychain = KeychainStore(service: "RewriteTool.AzureOpenAI", account: "api-key")
    private let providerKeychainService = "WritingAssistant.AIProviders"
    private let legacyProviderKeychainService = "RewriteTool.AIProviders"
    private let environment: [String: String]

    private init(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.defaults = defaults
        self.environment = environment
        defaults.register(defaults: Defaults.values)
        migrateLegacyDefaultsIfNeeded()
    }

    var azureAPIKey: String {
        get {
            keychain.read()
                ?? legacyKeychain.read()
                ?? environment.nonEmptyValue(for: "AZURE_OPENAI_KEY")
                ?? environment.nonEmptyValue(for: "AZURE_OPENAI_API_KEY")
                ?? ""
        }
        set {
            do {
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    try keychain.delete()
                } else {
                    try keychain.save(trimmed)
                }
            } catch {
                AppLog.error("Failed to update Azure API key in Keychain: \(error.localizedDescription)")
            }
        }
    }

    var azureEndpoint: String {
        get { string(for: Keys.azureEndpoint) ?? environment.nonEmptyValue(for: "AZURE_OPENAI_ENDPOINT") ?? "" }
        set { setString(newValue, for: Keys.azureEndpoint) }
    }

    var azureDeployment: String {
        get { string(for: Keys.azureDeployment) ?? environment.nonEmptyValue(for: "AZURE_GPT_DEPLOYMENT") ?? "" }
        set { setString(newValue, for: Keys.azureDeployment) }
    }

    var azureAPIVersion: String {
        get { string(for: Keys.azureAPIVersion) ?? environment.nonEmptyValue(for: "AZURE_OPENAI_API_VERSION") ?? "2024-10-21" }
        set { setString(newValue, for: Keys.azureAPIVersion) }
    }

    var llmProvider: LLMProvider {
        get {
            let rawValue = string(for: Keys.llmProvider) ?? LLMProvider.azureOpenAI.rawValue
            let provider = LLMProvider(rawValue: rawValue) ?? .azureOpenAI
            return LLMProvider.selectableCases.contains(provider) ? provider : .customOpenAICompatible
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.llmProvider) }
    }

    var customAPIFormat: CustomAPIFormat {
        get {
            let rawValue = string(for: Keys.customAPIFormat)
                ?? environment.nonEmptyValue(for: "WRITING_ASSISTANT_CUSTOM_API_FORMAT")
                ?? environment.nonEmptyValue(for: "REWRITE_CUSTOM_API_FORMAT")
                ?? CustomAPIFormat.openAIChatCompletions.rawValue
            return CustomAPIFormat(rawValue: rawValue) ?? .openAIChatCompletions
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.customAPIFormat) }
    }

    func apiKey(for provider: LLMProvider) -> String {
        switch provider {
        case .azureOpenAI:
            return azureAPIKey
        case .openAI:
            return providerKeychain(for: provider).read()
                ?? legacyProviderKeychain(for: provider).read()
                ?? environment.nonEmptyValue(for: "OPENAI_API_KEY")
                ?? ""
        case .openRouter:
            return providerKeychain(for: provider).read()
                ?? legacyProviderKeychain(for: provider).read()
                ?? environment.nonEmptyValue(for: "OPENROUTER_API_KEY")
                ?? ""
        case .gemini:
            return providerKeychain(for: provider).read()
                ?? legacyProviderKeychain(for: provider).read()
                ?? environment.nonEmptyValue(for: "GEMINI_API_KEY")
                ?? environment.nonEmptyValue(for: "GOOGLE_API_KEY")
                ?? ""
        case .ollama:
            return providerKeychain(for: provider).read()
                ?? legacyProviderKeychain(for: provider).read()
                ?? environment.nonEmptyValue(for: "OLLAMA_API_KEY")
                ?? ""
        case .customOpenAICompatible:
            return providerKeychain(for: provider).read()
                ?? legacyProviderKeychain(for: provider).read()
                ?? environment.nonEmptyValue(for: "WRITING_ASSISTANT_CUSTOM_API_KEY")
                ?? environment.nonEmptyValue(for: "REWRITE_CUSTOM_API_KEY")
                ?? environment.nonEmptyValue(for: "REWRITE_CUSTOM_OPENAI_API_KEY")
                ?? ""
        }
    }

    func setAPIKey(_ value: String, for provider: LLMProvider) {
        if provider == .azureOpenAI {
            azureAPIKey = value
            return
        }

        updateKeychain(providerKeychain(for: provider), value: value, label: provider.displayName)
    }

    func baseURL(for provider: LLMProvider) -> String {
        switch provider {
        case .azureOpenAI:
            return azureEndpoint
        case .openAI:
            return string(for: Keys.openAIBaseURL)
                ?? environment.nonEmptyValue(for: "OPENAI_BASE_URL")
                ?? provider.defaultBaseURL
        case .openRouter:
            return string(for: Keys.openRouterBaseURL) ?? provider.defaultBaseURL
        case .gemini:
            return string(for: Keys.geminiBaseURL) ?? provider.defaultBaseURL
        case .ollama:
            return normalizedOllamaBaseURL(
                string(for: Keys.ollamaBaseURL)
                ?? environment.nonEmptyValue(for: "OLLAMA_BASE_URL")
                ?? provider.defaultBaseURL
            )
        case .customOpenAICompatible:
            return string(for: Keys.customBaseURL)
                ?? environment.nonEmptyValue(for: "WRITING_ASSISTANT_CUSTOM_BASE_URL")
                ?? environment.nonEmptyValue(for: "REWRITE_CUSTOM_BASE_URL")
                ?? environment.nonEmptyValue(for: "REWRITE_CUSTOM_OPENAI_BASE_URL")
                ?? customAPIFormat.defaultBaseURL
        }
    }

    func setBaseURL(_ value: String, for provider: LLMProvider) {
        switch provider {
        case .azureOpenAI:
            azureEndpoint = value
        case .openAI:
            setString(value, for: Keys.openAIBaseURL, fallback: provider.defaultBaseURL)
        case .openRouter:
            setString(value, for: Keys.openRouterBaseURL, fallback: provider.defaultBaseURL)
        case .gemini:
            setString(value, for: Keys.geminiBaseURL, fallback: provider.defaultBaseURL)
        case .ollama:
            setString(value, for: Keys.ollamaBaseURL, fallback: provider.defaultBaseURL)
        case .customOpenAICompatible:
            setString(value, for: Keys.customBaseURL)
        }
    }

    func modelName(for provider: LLMProvider) -> String {
        switch provider {
        case .azureOpenAI:
            return azureDeployment
        case .openAI:
            return string(for: Keys.openAIModel)
                ?? environment.nonEmptyValue(for: "OPENAI_MODEL")
                ?? provider.defaultModel
        case .openRouter:
            return string(for: Keys.openRouterModel)
                ?? environment.nonEmptyValue(for: "OPENROUTER_MODEL")
                ?? provider.defaultModel
        case .gemini:
            return string(for: Keys.geminiModel)
                ?? environment.nonEmptyValue(for: "GEMINI_MODEL")
                ?? provider.defaultModel
        case .ollama:
            return string(for: Keys.ollamaModel)
                ?? environment.nonEmptyValue(for: "OLLAMA_MODEL")
                ?? provider.defaultModel
        case .customOpenAICompatible:
            return string(for: Keys.customModel)
                ?? environment.nonEmptyValue(for: "WRITING_ASSISTANT_CUSTOM_MODEL")
                ?? environment.nonEmptyValue(for: "REWRITE_CUSTOM_MODEL")
                ?? environment.nonEmptyValue(for: "REWRITE_CUSTOM_OPENAI_MODEL")
                ?? customAPIFormat.defaultModel
        }
    }

    func setModelName(_ value: String, for provider: LLMProvider) {
        switch provider {
        case .azureOpenAI:
            azureDeployment = value
        case .openAI:
            setString(value, for: Keys.openAIModel, fallback: provider.defaultModel)
        case .openRouter:
            setString(value, for: Keys.openRouterModel, fallback: provider.defaultModel)
        case .gemini:
            setString(value, for: Keys.geminiModel, fallback: provider.defaultModel)
        case .ollama:
            setString(value, for: Keys.ollamaModel, fallback: provider.defaultModel)
        case .customOpenAICompatible:
            setString(value, for: Keys.customModel)
        }
    }

    var maxCompletionTokens: Int {
        get { integer(for: Keys.maxCompletionTokens, defaultValue: 900) }
        set { defaults.set(clamp(newValue, min: 64, max: 8192), forKey: Keys.maxCompletionTokens) }
    }

    var selectionReadDelay: Double {
        get { double(for: Keys.selectionReadDelay, defaultValue: 0.40) }
        set { defaults.set(clamp(newValue, min: 0.05, max: 3.0), forKey: Keys.selectionReadDelay) }
    }

    var panelShowDelay: Double {
        get { double(for: Keys.panelShowDelay, defaultValue: 0.35) }
        set { defaults.set(clamp(newValue, min: 0.0, max: 3.0), forKey: Keys.panelShowDelay) }
    }

    var popupCooldown: Double {
        get { double(for: Keys.popupCooldown, defaultValue: 0.9) }
        set { defaults.set(clamp(newValue, min: 0.0, max: 10.0), forKey: Keys.popupCooldown) }
    }

    var repeatSuppression: Double {
        get { double(for: Keys.repeatSuppression, defaultValue: 8.0) }
        set { defaults.set(clamp(newValue, min: 0.0, max: 60.0), forKey: Keys.repeatSuppression) }
    }

    var autoHideDelay: Double {
        get { double(for: Keys.autoHideDelay, defaultValue: 5.0) }
        set { defaults.set(clamp(newValue, min: 0.5, max: 30.0), forKey: Keys.autoHideDelay) }
    }

    var popupScale: Double {
        get { double(for: Keys.popupScale, defaultValue: 0.86) }
        set { defaults.set(clamp(newValue, min: 0.65, max: 1.40), forKey: Keys.popupScale) }
    }

    var popupPosition: PopupPosition {
        get {
            let rawValue = string(for: Keys.popupPosition) ?? PopupPosition.above.rawValue
            return PopupPosition(rawValue: rawValue) ?? .above
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.popupPosition) }
    }

    var popupOffsetX: Double {
        get { double(for: Keys.popupOffsetX, defaultValue: 0.0) }
        set { defaults.set(clamp(newValue, min: -200.0, max: 200.0), forKey: Keys.popupOffsetX) }
    }

    var popupOffsetY: Double {
        get { double(for: Keys.popupOffsetY, defaultValue: 10.0) }
        set { defaults.set(clamp(newValue, min: -200.0, max: 200.0), forKey: Keys.popupOffsetY) }
    }

    var minimumSelectionCharacters: Int {
        get { integer(for: Keys.minimumSelectionCharacters, defaultValue: 8) }
        set { defaults.set(clamp(newValue, min: 1, max: 500), forKey: Keys.minimumSelectionCharacters) }
    }

    var minimumSingleTokenCharacters: Int {
        get { integer(for: Keys.minimumSingleTokenCharacters, defaultValue: 20) }
        set { defaults.set(clamp(newValue, min: 1, max: 500), forKey: Keys.minimumSingleTokenCharacters) }
    }

    var maximumSelectionCharacters: Int {
        get { integer(for: Keys.maximumSelectionCharacters, defaultValue: 4000) }
        set { defaults.set(clamp(newValue, min: 64, max: 50000), forKey: Keys.maximumSelectionCharacters) }
    }

    var showForKeyboardSelection: Bool {
        get { bool(for: Keys.showForKeyboardSelection, envKeys: ["WRITING_ASSISTANT_SHOW_FOR_KEYBOARD_SELECTION", "REWRITE_SHOW_FOR_KEYBOARD_SELECTION"]) }
        set { defaults.set(newValue, forKey: Keys.showForKeyboardSelection) }
    }

    var hotkeysEnabled: Bool {
        get { bool(for: Keys.hotkeysEnabled) }
        set { defaults.set(newValue, forKey: Keys.hotkeysEnabled) }
    }

    var draftComposerHotkey: String {
        get { defaults.string(forKey: Keys.draftComposerHotkey) ?? Defaults.draftComposerHotkey }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.draftComposerHotkey) }
    }

    var selectionPopupHotkey: String {
        get { defaults.string(forKey: Keys.selectionPopupHotkey) ?? Defaults.selectionPopupHotkey }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.selectionPopupHotkey) }
    }

    var settingsHotkey: String {
        get { defaults.string(forKey: Keys.settingsHotkey) ?? Defaults.settingsHotkey }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.settingsHotkey) }
    }

    var replacementStrategy: ReplacementStrategy {
        get {
            let rawValue = string(for: Keys.replacementStrategy)
                ?? environment.nonEmptyValue(for: "WRITING_ASSISTANT_REPLACE_STRATEGY")
                ?? environment.nonEmptyValue(for: "REWRITE_REPLACE_STRATEGY")
                ?? ReplacementStrategy.paste.rawValue
            return ReplacementStrategy(rawValue: rawValue) ?? .paste
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.replacementStrategy) }
    }

    var pasteActivationDelay: Double {
        get { double(for: Keys.pasteActivationDelay, envKeys: ["WRITING_ASSISTANT_PASTE_ACTIVATION_DELAY_SECONDS", "REWRITE_PASTE_ACTIVATION_DELAY_SECONDS"], defaultValue: 0.20) }
        set { defaults.set(clamp(newValue, min: 0.0, max: 3.0), forKey: Keys.pasteActivationDelay) }
    }

    var clipboardRestoreDelay: Double {
        get { double(for: Keys.clipboardRestoreDelay, envKeys: ["WRITING_ASSISTANT_CLIPBOARD_RESTORE_DELAY_SECONDS", "REWRITE_CLIPBOARD_RESTORE_DELAY_SECONDS"], defaultValue: 0.80) }
        set { defaults.set(clamp(newValue, min: 0.05, max: 10.0), forKey: Keys.clipboardRestoreDelay) }
    }

    var logSelectedText: Bool {
        get { bool(for: Keys.logSelectedText, envKeys: ["WRITING_ASSISTANT_LOG_TEXT", "REWRITE_LOG_TEXT"]) }
        set { defaults.set(newValue, forKey: Keys.logSelectedText) }
    }

    var debugLogs: Bool {
        get { bool(for: Keys.debugLogs, envKeys: ["WRITING_ASSISTANT_DEBUG_LOGS", "REWRITE_DEBUG_LOGS"]) }
        set { defaults.set(newValue, forKey: Keys.debugLogs) }
    }

    var grammarInstructions: String {
        get { string(for: Keys.grammarInstructions) ?? Defaults.grammarInstructions }
        set { setString(newValue, for: Keys.grammarInstructions, fallback: Defaults.grammarInstructions) }
    }

    var formalSupervisorInstructions: String {
        get { string(for: Keys.formalSupervisorInstructions) ?? Defaults.formalSupervisorInstructions }
        set { setString(newValue, for: Keys.formalSupervisorInstructions, fallback: Defaults.formalSupervisorInstructions) }
    }

    var formalPartnersInstructions: String {
        get { string(for: Keys.formalPartnersInstructions) ?? Defaults.formalPartnersInstructions }
        set { setString(newValue, for: Keys.formalPartnersInstructions, fallback: Defaults.formalPartnersInstructions) }
    }

    var fluencyInstructions: String {
        get { string(for: Keys.fluencyInstructions) ?? Defaults.fluencyInstructions }
        set { setString(newValue, for: Keys.fluencyInstructions, fallback: Defaults.fluencyInstructions) }
    }

    var academicInstructions: String {
        get { string(for: Keys.academicInstructions) ?? Defaults.academicInstructions }
        set { setString(newValue, for: Keys.academicInstructions, fallback: Defaults.academicInstructions) }
    }

    var englishToChineseInstructions: String {
        get { string(for: Keys.englishToChineseInstructions) ?? Defaults.englishToChineseInstructions }
        set { setString(newValue, for: Keys.englishToChineseInstructions, fallback: Defaults.englishToChineseInstructions) }
    }

    var draftInstructions: String {
        get { string(for: Keys.draftInstructions) ?? Defaults.draftInstructions }
        set { setString(newValue, for: Keys.draftInstructions, fallback: Defaults.draftInstructions) }
    }

    var enabledBuiltInActionIDs: [String] {
        get {
            guard let value = defaults.stringArray(forKey: Keys.enabledBuiltInActionIDs) else {
                return BuiltInTune.allCases.map(\.id)
            }
            let validIDs = Set(BuiltInTune.allCases.map(\.id))
            var filtered = value.filter { validIDs.contains($0) }
            if !defaults.bool(forKey: Keys.englishToChineseActionMigrated) {
                if !filtered.contains(BuiltInTune.englishToChinese.id) {
                    filtered.append(BuiltInTune.englishToChinese.id)
                }
                defaults.set(filtered, forKey: Keys.enabledBuiltInActionIDs)
                defaults.set(true, forKey: Keys.englishToChineseActionMigrated)
            }
            return filtered.isEmpty ? [BuiltInTune.grammar.id] : filtered
        }
        set {
            let validIDs = Set(BuiltInTune.allCases.map(\.id))
            var filtered = newValue.filter { validIDs.contains($0) }
            if filtered.isEmpty {
                filtered = [BuiltInTune.grammar.id]
            }
            defaults.set(filtered, forKey: Keys.enabledBuiltInActionIDs)
            defaults.set(true, forKey: Keys.englishToChineseActionMigrated)
        }
    }

    var customTunes: [CustomTune] {
        get {
            guard let data = defaults.data(forKey: Keys.customTunes),
                  let tunes = try? JSONDecoder().decode([CustomTune].self, from: data) else {
                return []
            }
            return tunes
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.customTunes)
            }
        }
    }

    var rewriteActions: [RewriteAction] {
        let enabledIDs = Set(enabledBuiltInActionIDs)
        let builtIns = BuiltInTune.allCases
            .filter { $0 != .englishToChinese && enabledIDs.contains($0.id) }
            .map { $0.rewriteAction(settings: self) }
        let translation = enabledIDs.contains(BuiltInTune.englishToChinese.id)
            ? [BuiltInTune.englishToChinese.rewriteAction(settings: self)]
            : []
        return builtIns + customTunes.map(\.rewriteAction) + translation
    }

    var hasAzureConfiguration: Bool {
        !azureAPIKey.isEmpty && !azureEndpoint.isEmpty && !azureDeployment.isEmpty
    }

    var hasLLMConfiguration: Bool {
        (try? llmConfiguration()) != nil
    }

    var popupTuning: PopupTuning {
        PopupTuning(
            selectionReadDelay: selectionReadDelay,
            panelShowDelay: panelShowDelay,
            popupCooldown: popupCooldown,
            repeatSuppression: repeatSuppression,
            autoHideDelay: autoHideDelay,
            popupScale: popupScale,
            popupPosition: popupPosition,
            popupOffsetX: popupOffsetX,
            popupOffsetY: popupOffsetY,
            minimumSelectionCharacters: minimumSelectionCharacters,
            minimumSingleTokenCharacters: minimumSingleTokenCharacters,
            maximumSelectionCharacters: maximumSelectionCharacters,
            showForKeyboardSelection: showForKeyboardSelection
        )
    }

    func azureConfiguration() throws -> AzureOpenAIConfiguration {
        guard !azureAPIKey.isEmpty else {
            throw RewriteError.missingAzureConfiguration("Azure API Key")
        }

        guard !azureEndpoint.isEmpty else {
            throw RewriteError.missingAzureConfiguration("Azure Endpoint")
        }

        guard let endpoint = URL(string: azureEndpoint), endpoint.scheme != nil, endpoint.host != nil else {
            throw RewriteError.api("Azure endpoint must be a full URL, for example https://your-resource.openai.azure.com/")
        }

        guard !azureDeployment.isEmpty else {
            throw RewriteError.missingAzureConfiguration("Azure GPT Deployment")
        }

        return AzureOpenAIConfiguration(
            apiKey: azureAPIKey,
            endpoint: endpoint,
            deployment: azureDeployment,
            apiVersion: azureAPIVersion
        )
    }

    func llmConfiguration() throws -> LLMConfiguration {
        let provider = llmProvider
        let apiKey = apiKey(for: provider)

        if provider.requiresAPIKey, apiKey.isEmpty {
            throw RewriteError.missingProviderConfiguration("\(provider.displayName) API Key")
        }

        let baseURLString = baseURL(for: provider)
        guard !baseURLString.isEmpty else {
            throw RewriteError.missingProviderConfiguration("\(provider.displayName) Base URL")
        }

        guard let baseURL = URL(string: baseURLString), baseURL.scheme != nil, baseURL.host != nil else {
            throw RewriteError.api("\(provider.displayName) base URL must be a full URL.")
        }

        let model = modelName(for: provider)
        guard !model.isEmpty else {
            let modelLabel = provider == .azureOpenAI ? "Azure deployment" : "\(provider.displayName) model"
            throw RewriteError.missingProviderConfiguration(modelLabel)
        }

        return LLMConfiguration(
            provider: provider,
            customAPIFormat: provider == .customOpenAICompatible ? customAPIFormat : nil,
            apiKey: apiKey,
            baseURL: baseURL,
            model: model,
            apiVersion: azureAPIVersion,
            maxTokens: maxCompletionTokens
        )
    }

    func resetBehaviorDefaults() {
        [
            Keys.selectionReadDelay,
            Keys.panelShowDelay,
            Keys.popupCooldown,
            Keys.repeatSuppression,
            Keys.autoHideDelay,
            Keys.popupScale,
            Keys.popupPosition,
            Keys.popupOffsetX,
            Keys.popupOffsetY,
            Keys.minimumSelectionCharacters,
            Keys.minimumSingleTokenCharacters,
            Keys.maximumSelectionCharacters,
            Keys.showForKeyboardSelection,
            Keys.hotkeysEnabled,
            Keys.draftComposerHotkey,
            Keys.selectionPopupHotkey,
            Keys.settingsHotkey,
            Keys.replacementStrategy,
            Keys.pasteActivationDelay,
            Keys.clipboardRestoreDelay,
            Keys.logSelectedText,
            Keys.debugLogs
        ].forEach(defaults.removeObject)
        notifyChanged()
    }

    func resetPromptDefaults() {
        defaults.removeObject(forKey: Keys.grammarInstructions)
        defaults.removeObject(forKey: Keys.formalSupervisorInstructions)
        defaults.removeObject(forKey: Keys.formalPartnersInstructions)
        defaults.removeObject(forKey: Keys.fluencyInstructions)
        defaults.removeObject(forKey: Keys.academicInstructions)
        defaults.removeObject(forKey: Keys.englishToChineseInstructions)
        defaults.removeObject(forKey: Keys.draftInstructions)
        defaults.removeObject(forKey: Keys.enabledBuiltInActionIDs)
        defaults.removeObject(forKey: Keys.englishToChineseActionMigrated)
        notifyChanged()
    }

    func notifyChanged() {
        defaults.synchronize()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func string(for key: String) -> String? {
        guard let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func setString(_ value: String, for key: String, fallback: String? = nil) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty, fallback == nil {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(trimmed.isEmpty ? fallback : trimmed, forKey: key)
        }
    }

    private func integer(for key: String, defaultValue: Int) -> Int {
        if defaults.object(forKey: key) != nil {
            return defaults.integer(forKey: key)
        }
        return defaultValue
    }

    private func double(for key: String, envKey: String? = nil, envKeys: [String] = [], defaultValue: Double) -> Double {
        if defaults.object(forKey: key) != nil {
            return defaults.double(forKey: key)
        }
        if let envKey, let value = environment.doubleValue(for: envKey) {
            return value
        }
        for envKey in envKeys {
            if let value = environment.doubleValue(for: envKey) {
                return value
            }
        }
        return defaultValue
    }

    private func bool(for key: String, envKey: String? = nil, envKeys: [String] = []) -> Bool {
        if defaults.object(forKey: key) != nil {
            return defaults.bool(forKey: key)
        }
        if let envKey {
            return environment.booleanValue(for: envKey)
        }
        for envKey in envKeys where environment.hasKey(envKey) {
            return environment.booleanValue(for: envKey)
        }
        return false
    }

    private func clamp<T: Comparable>(_ value: T, min minimum: T, max maximum: T) -> T {
        Swift.max(minimum, Swift.min(maximum, value))
    }

    private func providerKeychain(for provider: LLMProvider) -> KeychainStore {
        KeychainStore(service: providerKeychainService, account: "api-key.\(provider.rawValue)")
    }

    private func legacyProviderKeychain(for provider: LLMProvider) -> KeychainStore {
        KeychainStore(service: legacyProviderKeychainService, account: "api-key.\(provider.rawValue)")
    }

    private func migrateLegacyDefaultsIfNeeded() {
        guard let legacyDefaults = UserDefaults(suiteName: "RewriteTool") else { return }

        var migratedKeys: [String] = []
        for key in Keys.allUserDefaultKeys where defaults.object(forKey: key) == nil {
            guard let legacyValue = legacyDefaults.object(forKey: key) else { continue }
            defaults.set(legacyValue, forKey: key)
            migratedKeys.append(key)
        }

        if !migratedKeys.isEmpty {
            AppLog.info("Migrated legacy RewriteTool preferences count=\(migratedKeys.count)")
        }
    }

    private func updateKeychain(_ store: KeychainStore, value: String, label: String) {
        do {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try store.delete()
            } else {
                try store.save(trimmed)
            }
        } catch {
            AppLog.error("Failed to update \(label) API key in Keychain: \(error.localizedDescription)")
        }
    }

    private func normalizedOllamaBaseURL(_ value: String) -> String {
        var trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        if trimmed.hasSuffix("/v1") {
            trimmed.removeLast(3)
            return "\(trimmed)/api"
        }

        return trimmed
    }
}

struct PopupTuning {
    let selectionReadDelay: TimeInterval
    let panelShowDelay: TimeInterval
    let popupCooldown: TimeInterval
    let repeatSuppression: TimeInterval
    let autoHideDelay: TimeInterval
    let popupScale: Double
    let popupPosition: PopupPosition
    let popupOffsetX: Double
    let popupOffsetY: Double
    let minimumSelectionCharacters: Int
    let minimumSingleTokenCharacters: Int
    let maximumSelectionCharacters: Int
    let showForKeyboardSelection: Bool
}

enum PopupPosition: String, CaseIterable {
    case above
    case below
    case left
    case right

    var displayName: String {
        switch self {
        case .above:
            return "Above selection"
        case .below:
            return "Below selection"
        case .left:
            return "Left of selection"
        case .right:
            return "Right of selection"
        }
    }
}

enum BuiltInTune: String, CaseIterable {
    case grammar
    case formalSupervisor
    case formalPartners
    case fluency
    case academic
    case englishToChinese

    var id: String {
        switch self {
        case .grammar:
            return "grammar"
        case .formalSupervisor:
            return "formal-supervisor"
        case .formalPartners:
            return "formal-partners"
        case .fluency:
            return "fluency"
        case .academic:
            return "academic"
        case .englishToChinese:
            return "english-to-chinese"
        }
    }

    var displayTitle: String {
        switch self {
        case .grammar:
            return "Fix grammar"
        case .formalSupervisor:
            return "Supervisor"
        case .formalPartners:
            return "Partners"
        case .fluency:
            return "Fluency"
        case .academic:
            return "Academic"
        case .englishToChinese:
            return "English to Chinese"
        }
    }

    var shortTitle: String {
        switch self {
        case .grammar:
            return "Fix"
        case .formalSupervisor:
            return "Sup"
        case .formalPartners:
            return "Par"
        case .fluency:
            return "Flu"
        case .academic:
            return "Acd"
        case .englishToChinese:
            return "中"
        }
    }

    var systemImageName: String? {
        switch self {
        case .englishToChinese:
            return "character.book.closed.fill"
        default:
            return nil
        }
    }

    var tooltip: String {
        switch self {
        case .grammar:
            return "Fix grammar"
        case .formalSupervisor:
            return "Formal rewrite for a supervisor"
        case .formalPartners:
            return "Formal rewrite for partners or clients"
        case .fluency:
            return "Natural coworker chat"
        case .academic:
            return "Academic review or journal writing"
        case .englishToChinese:
            return "Translate English into Simplified Chinese"
        }
    }

    func instructions(settings: AppSettings) -> String {
        switch self {
        case .grammar:
            return settings.grammarInstructions
        case .formalSupervisor:
            return settings.formalSupervisorInstructions
        case .formalPartners:
            return settings.formalPartnersInstructions
        case .fluency:
            return settings.fluencyInstructions
        case .academic:
            return settings.academicInstructions
        case .englishToChinese:
            return settings.englishToChineseInstructions
        }
    }

    func rewriteAction(settings: AppSettings) -> RewriteAction {
        RewriteAction(
            id: id,
            title: id,
            displayTitle: displayTitle,
            shortTitle: shortTitle,
            systemImageName: systemImageName,
            tooltip: tooltip,
            instructions: instructions(settings: settings),
            resultPresentation: self == .englishToChinese ? .displayInPanel : .replaceSelection
        )
    }
}

struct CustomTune: Codable, Equatable {
    var id: String
    var name: String
    var shortLabel: String
    var instructions: String

    var rewriteAction: RewriteAction {
        RewriteAction(
            id: "custom-\(id)",
            title: "custom-\(id)",
            displayTitle: name,
            shortTitle: shortLabel,
            systemImageName: nil,
            tooltip: name,
            instructions: instructions,
            resultPresentation: .replaceSelection
        )
    }

    static func makeDefault() -> CustomTune {
        CustomTune(
            id: UUID().uuidString,
            name: "Custom",
            shortLabel: "Cus",
            instructions: Defaults.customTuneInstructions
        )
    }
}

struct AzureOpenAIConfiguration {
    let apiKey: String
    let endpoint: URL
    let deployment: String
    let apiVersion: String

    var chatCompletionsURL: URL {
        var endpointString = endpoint.absoluteString
        while endpointString.hasSuffix("/") {
            endpointString.removeLast()
        }

        let escapedDeployment = deployment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deployment
        return URL(string: "\(endpointString)/openai/deployments/\(escapedDeployment)/chat/completions?api-version=\(apiVersion)")!
    }
}

enum LLMProvider: String, CaseIterable {
    case azureOpenAI = "azure-openai"
    case openAI = "openai"
    case openRouter = "openrouter"
    case gemini = "gemini"
    case ollama = "ollama"
    case customOpenAICompatible = "custom-openai-compatible"

    static let selectableCases: [LLMProvider] = [
        .azureOpenAI,
        .ollama,
        .customOpenAICompatible
    ]

    var displayName: String {
        switch self {
        case .azureOpenAI:
            return "Azure OpenAI"
        case .openAI:
            return "OpenAI"
        case .openRouter:
            return "OpenRouter"
        case .gemini:
            return "Gemini"
        case .ollama:
            return "Ollama"
        case .customOpenAICompatible:
            return "Custom AI provider"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .azureOpenAI:
            return ""
        case .openAI:
            return "https://api.openai.com/v1"
        case .openRouter:
            return "https://openrouter.ai/api/v1"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .ollama:
            return "http://localhost:11434/api"
        case .customOpenAICompatible:
            return CustomAPIFormat.openAIChatCompletions.defaultBaseURL
        }
    }

    var baseURLPlaceholder: String {
        switch self {
        case .azureOpenAI:
            return "https://your-resource.openai.azure.com/"
        case .ollama:
            return "http://localhost:11434/api"
        case .customOpenAICompatible:
            return CustomAPIFormat.openAIChatCompletions.baseURLPlaceholder
        case .openAI:
            return "https://api.openai.com"
        case .openRouter:
            return "https://openrouter.ai/api/v1"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai"
        }
    }

    var baseURLHelpText: String {
        switch self {
        case .azureOpenAI:
            return "Azure resource endpoint, e.g. https://your-resource.openai.azure.com/"
        case .ollama:
            return "Native Ollama API base, e.g. http://localhost:11434/api"
        case .customOpenAICompatible:
            return CustomAPIFormat.openAIChatCompletions.baseURLHelpText
        case .openAI:
            return "OpenAI base URL, e.g. https://api.openai.com"
        case .openRouter:
            return "OpenRouter base URL, e.g. https://openrouter.ai/api/v1"
        case .gemini:
            return "Gemini OpenAI-compatible base, e.g. https://generativelanguage.googleapis.com/v1beta/openai"
        }
    }

    var defaultModel: String {
        switch self {
        case .azureOpenAI:
            return ""
        case .openAI:
            return "gpt-4o-mini"
        case .openRouter:
            return "openai/gpt-4o-mini"
        case .gemini:
            return "gemini-2.5-flash"
        case .ollama:
            return "llama3.2"
        case .customOpenAICompatible:
            return CustomAPIFormat.openAIChatCompletions.defaultModel
        }
    }

    var requiresAPIKey: Bool {
        self != .ollama
    }

    var tokenParameter: ChatTokenParameter {
        switch self {
        case .azureOpenAI, .openAI:
            return .maxCompletionTokens
        case .openRouter, .gemini, .ollama, .customOpenAICompatible:
            return .maxTokens
        }
    }
}

enum ChatTokenParameter {
    case maxCompletionTokens
    case maxTokens
}

enum CustomAPIFormat: String, CaseIterable {
    case openAIChatCompletions = "openai-chat-completions"
    case anthropicMessages = "anthropic-messages"
    case geminiGenerateContent = "gemini-generate-content"
    case cohereChat = "cohere-chat"

    var displayName: String {
        switch self {
        case .openAIChatCompletions:
            return "OpenAI-style Chat Completions"
        case .anthropicMessages:
            return "Anthropic Messages"
        case .geminiGenerateContent:
            return "Gemini GenerateContent"
        case .cohereChat:
            return "Cohere Chat"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .openAIChatCompletions:
            return "https://api.openai.com"
        case .anthropicMessages:
            return "https://api.anthropic.com"
        case .geminiGenerateContent:
            return "https://generativelanguage.googleapis.com"
        case .cohereChat:
            return "https://api.cohere.com"
        }
    }

    var baseURLPlaceholder: String {
        switch self {
        case .openAIChatCompletions:
            return "https://api.openai.com"
        case .anthropicMessages:
            return "https://api.anthropic.com"
        case .geminiGenerateContent:
            return "https://generativelanguage.googleapis.com"
        case .cohereChat:
            return "https://api.cohere.com"
        }
    }

    var baseURLHelpText: String {
        switch self {
        case .openAIChatCompletions:
            return "OpenAI-style base. Examples: https://api.openai.com, https://openrouter.ai/api/v1, https://api.groq.com/openai/v1"
        case .anthropicMessages:
            return "Anthropic native API base. The app calls /v1/messages and sends x-api-key plus anthropic-version."
        case .geminiGenerateContent:
            return "Gemini native API base. The app calls /v1beta/models/{model}:generateContent with x-goog-api-key."
        case .cohereChat:
            return "Cohere native API base. The app calls /v2/chat with Bearer authentication."
        }
    }

    var defaultModel: String {
        switch self {
        case .openAIChatCompletions:
            return "gpt-4o-mini"
        case .anthropicMessages:
            return "claude-sonnet-4-5"
        case .geminiGenerateContent:
            return "gemini-2.5-flash"
        case .cohereChat:
            return "command-r"
        }
    }
}

struct LLMConfiguration {
    let provider: LLMProvider
    let customAPIFormat: CustomAPIFormat?
    let apiKey: String
    let baseURL: URL
    let model: String
    let apiVersion: String
    let maxTokens: Int

    var chatCompletionsURL: URL {
        switch provider {
        case .azureOpenAI:
            let endpointString = trimmedBaseURLString

            let escapedDeployment = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            return URL(string: "\(endpointString)/openai/deployments/\(escapedDeployment)/chat/completions?api-version=\(apiVersion)")!
        case .openAI, .openRouter, .gemini, .ollama, .customOpenAICompatible:
            return openAIStyleChatCompletionsURL
        }
    }

    var anthropicMessagesURL: URL {
        let baseURLString = trimmedBaseURLString
        if baseURLString.hasSuffix("/v1/messages") {
            return URL(string: baseURLString)!
        }
        if baseURLString.hasSuffix("/v1") {
            return URL(string: "\(baseURLString)/messages")!
        }
        return URL(string: "\(baseURLString)/v1/messages")!
    }

    var geminiGenerateContentURL: URL {
        let baseURLString = trimmedBaseURLString
        if baseURLString.hasSuffix(":generateContent") {
            return URL(string: baseURLString)!
        }

        let modelPath = model.hasPrefix("models/") ? model : "models/\(model)"
        let escapedModelPath = modelPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelPath
        if baseURLString.hasSuffix("/v1beta") || baseURLString.hasSuffix("/v1") {
            return URL(string: "\(baseURLString)/\(escapedModelPath):generateContent")!
        }
        return URL(string: "\(baseURLString)/v1beta/\(escapedModelPath):generateContent")!
    }

    var cohereChatURL: URL {
        let baseURLString = trimmedBaseURLString
        if baseURLString.hasSuffix("/v2/chat") {
            return URL(string: baseURLString)!
        }
        if baseURLString.hasSuffix("/v2") {
            return URL(string: "\(baseURLString)/chat")!
        }
        return URL(string: "\(baseURLString)/v2/chat")!
    }

    private var openAIStyleChatCompletionsURL: URL {
        let baseURLString = trimmedBaseURLString
        if baseURLString.hasSuffix("/chat/completions") {
            return URL(string: baseURLString)!
        }

        if baseURL.host == "api.openai.com",
           baseURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty {
            return URL(string: "\(baseURLString)/v1/chat/completions")!
        }

        return URL(string: "\(baseURLString)/chat/completions")!
    }

    private var trimmedBaseURLString: String {
        var baseURLString = baseURL.absoluteString
        while baseURLString.hasSuffix("/") {
            baseURLString.removeLast()
        }
        return baseURLString
    }

    var ollamaGenerateURL: URL {
        var baseURLString = trimmedBaseURLString

        if baseURLString.hasSuffix("/api/generate") {
            return URL(string: baseURLString)!
        }

        if baseURLString.hasSuffix("/api") {
            return URL(string: "\(baseURLString)/generate")!
        }

        if baseURLString.hasSuffix("/v1") {
            baseURLString.removeLast(3)
        }

        return URL(string: "\(baseURLString)/api/generate")!
    }

    var requestModel: String? {
        provider == .azureOpenAI ? nil : model
    }

    var tokenParameter: ChatTokenParameter {
        if provider == .customOpenAICompatible,
           customAPIFormat == .openAIChatCompletions,
           baseURL.host == "api.openai.com" {
            return .maxCompletionTokens
        }

        return provider.tokenParameter
    }

    func applyAuthentication(to request: inout URLRequest) {
        guard !apiKey.isEmpty else { return }

        switch provider {
        case .azureOpenAI:
            request.addValue(apiKey, forHTTPHeaderField: "api-key")
        case .openAI, .openRouter, .gemini, .ollama, .customOpenAICompatible:
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
    }

    func applyAnthropicAuthentication(to request: inout URLRequest) {
        guard !apiKey.isEmpty else { return }
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    }

    func applyGeminiAuthentication(to request: inout URLRequest) {
        guard !apiKey.isEmpty else { return }
        request.addValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
    }
}

enum ReplacementStrategy: String, CaseIterable {
    case paste
    case accessibilityThenPaste = "accessibility-then-paste"

    var displayName: String {
        switch self {
        case .paste:
            return "Paste"
        case .accessibilityThenPaste:
            return "Accessibility, then paste"
        }
    }

    var helpText: String {
        switch self {
        case .paste:
            return "Most reliable for Slack, browsers, Electron apps, and text editors."
        case .accessibilityThenPaste:
            return "Tries direct Accessibility replacement first, then falls back to paste."
        }
    }
}

private enum Keys {
    static let llmProvider = "llm.provider"
    static let azureEndpoint = "azure.endpoint"
    static let azureDeployment = "azure.deployment"
    static let azureAPIVersion = "azure.apiVersion"
    static let openAIBaseURL = "providers.openai.baseURL"
    static let openAIModel = "providers.openai.model"
    static let openRouterBaseURL = "providers.openrouter.baseURL"
    static let openRouterModel = "providers.openrouter.model"
    static let geminiBaseURL = "providers.gemini.baseURL"
    static let geminiModel = "providers.gemini.model"
    static let ollamaBaseURL = "providers.ollama.baseURL"
    static let ollamaModel = "providers.ollama.model"
    static let customBaseURL = "providers.customOpenAICompatible.baseURL"
    static let customModel = "providers.customOpenAICompatible.model"
    static let customAPIFormat = "providers.custom.apiFormat"
    static let maxCompletionTokens = "azure.maxCompletionTokens"
    static let selectionReadDelay = "popup.selectionReadDelay"
    static let panelShowDelay = "popup.panelShowDelay"
    static let popupCooldown = "popup.cooldown"
    static let repeatSuppression = "popup.repeatSuppression"
    static let autoHideDelay = "popup.autoHideDelay"
    static let popupScale = "popup.scale"
    static let popupPosition = "popup.position"
    static let popupOffsetX = "popup.offsetX"
    static let popupOffsetY = "popup.offsetY"
    static let minimumSelectionCharacters = "popup.minimumSelectionCharacters"
    static let minimumSingleTokenCharacters = "popup.minimumSingleTokenCharacters"
    static let maximumSelectionCharacters = "popup.maximumSelectionCharacters"
    static let showForKeyboardSelection = "popup.showForKeyboardSelection"
    static let hotkeysEnabled = "hotkeys.enabled"
    static let draftComposerHotkey = "hotkeys.draftComposer"
    static let selectionPopupHotkey = "hotkeys.selectionPopup"
    static let settingsHotkey = "hotkeys.settings"
    static let replacementStrategy = "replacement.strategy"
    static let pasteActivationDelay = "replacement.pasteActivationDelay"
    static let clipboardRestoreDelay = "replacement.clipboardRestoreDelay"
    static let logSelectedText = "logs.selectedText"
    static let debugLogs = "logs.debug"
    static let grammarInstructions = "prompts.grammar"
    static let formalSupervisorInstructions = "prompts.formalSupervisor"
    static let formalPartnersInstructions = "prompts.formalPartners"
    static let fluencyInstructions = "prompts.fluency"
    static let academicInstructions = "prompts.academic"
    static let englishToChineseInstructions = "prompts.englishToChinese"
    static let draftInstructions = "prompts.draft"
    static let enabledBuiltInActionIDs = "prompts.enabledBuiltInActionIDs"
    static let englishToChineseActionMigrated = "prompts.englishToChineseActionMigrated"
    static let customTunes = "prompts.customTunes"

    static let allUserDefaultKeys = [
        llmProvider,
        azureEndpoint,
        azureDeployment,
        azureAPIVersion,
        openAIBaseURL,
        openAIModel,
        openRouterBaseURL,
        openRouterModel,
        geminiBaseURL,
        geminiModel,
        ollamaBaseURL,
        ollamaModel,
        customBaseURL,
        customModel,
        customAPIFormat,
        maxCompletionTokens,
        selectionReadDelay,
        panelShowDelay,
        popupCooldown,
        repeatSuppression,
        autoHideDelay,
        popupScale,
        popupPosition,
        popupOffsetX,
        popupOffsetY,
        minimumSelectionCharacters,
        minimumSingleTokenCharacters,
        maximumSelectionCharacters,
        showForKeyboardSelection,
        hotkeysEnabled,
        draftComposerHotkey,
        selectionPopupHotkey,
        settingsHotkey,
        replacementStrategy,
        pasteActivationDelay,
        clipboardRestoreDelay,
        logSelectedText,
        debugLogs,
        grammarInstructions,
        formalSupervisorInstructions,
        formalPartnersInstructions,
        fluencyInstructions,
        academicInstructions,
        englishToChineseInstructions,
        draftInstructions,
        enabledBuiltInActionIDs,
        englishToChineseActionMigrated,
        customTunes
    ]
}

private enum Defaults {
    static let draftComposerHotkey = "Ctrl+Opt+Cmd+D"
    static let selectionPopupHotkey = "Ctrl+Opt+Cmd+R"
    static let settingsHotkey = "Ctrl+Opt+Cmd+,"

    static let grammarInstructions = """
    You fix grammar, spelling, punctuation, and clarity without changing the author's meaning or tone.
    Return only the corrected text. Do not explain the changes.
    """

    static let formalSupervisorInstructions = """
    You rewrite selected text into a formal, professional message from an employee to their supervisor.
    Preserve the original meaning, make it concise, respectful, and clear, and keep the tone appropriate for reporting work progress, results, blockers, or requests upward.
    Return only the rewritten text. Do not explain the changes.
    """

    static let formalPartnersInstructions = """
    You rewrite selected text into a formal, professional message from a client or business contact to external partners.
    Preserve the original meaning, make it polished, courteous, and clear, and keep the tone appropriate for sharing information, requests, updates, or decisions with partners.
    Return only the rewritten text. Do not explain the changes.
    """

    static let fluencyInstructions = """
    You rewrite selected text to sound natural, fluent, and easy to read in daily coworker chat.
    Preserve the original meaning, keep it friendly and concise, and avoid making it overly formal.
    Return only the rewritten text. Do not explain the changes.
    """

    static let academicInstructions = """
    You rewrite selected text for an academic journal context.
    If the text is from a reviewer, make it professional, precise, constructive, and appropriate for review comments to editors or authors in applied AI, technology, engineering, or related journals.
    If the text is from a journal author, make it scholarly, clear, concise, and appropriate for manuscript, response letter, rebuttal, cover letter, or editorial communication.
    Preserve the original meaning and technical nuance. Return only the rewritten text. Do not explain the changes.
    """

    static let englishToChineseInstructions = """
    Translate the selected English text into natural, accurate Simplified Chinese.
    Preserve the original meaning, tone, formatting, paragraph breaks, names, numbers, and technical nuance. Keep product names and technical terms in English when that is clearer or conventional in Chinese.
    Return only the Chinese translation. Do not explain the translation and do not wrap it in quotes.
    """

    static let draftInstructions = """
    You write a polished, ready-to-send draft from the user's writing request.
    Infer the most appropriate format from the request, such as email, chat message, note, reply, or paragraph.
    Keep the draft clear, practical, and complete. Use a professional tone unless the request asks otherwise.
    Return only the draft text. Do not explain the changes. Do not wrap the answer in quotes.
    """

    static let customTuneInstructions = """
    Rewrite the selected text in this custom style.
    Preserve the original meaning and return only the rewritten text. Do not explain the changes.
    """

    static let values: [String: Any] = [
        Keys.llmProvider: LLMProvider.azureOpenAI.rawValue,
        Keys.azureAPIVersion: "2024-10-21",
        Keys.openAIBaseURL: LLMProvider.openAI.defaultBaseURL,
        Keys.openAIModel: LLMProvider.openAI.defaultModel,
        Keys.openRouterBaseURL: LLMProvider.openRouter.defaultBaseURL,
        Keys.openRouterModel: LLMProvider.openRouter.defaultModel,
        Keys.geminiBaseURL: LLMProvider.gemini.defaultBaseURL,
        Keys.geminiModel: LLMProvider.gemini.defaultModel,
        Keys.ollamaBaseURL: LLMProvider.ollama.defaultBaseURL,
        Keys.ollamaModel: LLMProvider.ollama.defaultModel,
        Keys.customAPIFormat: CustomAPIFormat.openAIChatCompletions.rawValue,
        Keys.maxCompletionTokens: 900,
        Keys.selectionReadDelay: 0.40,
        Keys.panelShowDelay: 0.35,
        Keys.popupCooldown: 0.9,
        Keys.repeatSuppression: 8.0,
        Keys.autoHideDelay: 5.0,
        Keys.popupScale: 0.86,
        Keys.popupPosition: PopupPosition.above.rawValue,
        Keys.popupOffsetX: 0.0,
        Keys.popupOffsetY: 10.0,
        Keys.minimumSelectionCharacters: 8,
        Keys.minimumSingleTokenCharacters: 20,
        Keys.maximumSelectionCharacters: 4000,
        Keys.showForKeyboardSelection: false,
        Keys.hotkeysEnabled: true,
        Keys.draftComposerHotkey: draftComposerHotkey,
        Keys.selectionPopupHotkey: selectionPopupHotkey,
        Keys.settingsHotkey: settingsHotkey,
        Keys.replacementStrategy: ReplacementStrategy.paste.rawValue,
        Keys.pasteActivationDelay: 0.20,
        Keys.clipboardRestoreDelay: 0.80,
        Keys.logSelectedText: false,
        Keys.debugLogs: false,
        Keys.grammarInstructions: grammarInstructions,
        Keys.formalSupervisorInstructions: formalSupervisorInstructions,
        Keys.formalPartnersInstructions: formalPartnersInstructions,
        Keys.fluencyInstructions: fluencyInstructions,
        Keys.academicInstructions: academicInstructions,
        Keys.englishToChineseInstructions: englishToChineseInstructions,
        Keys.draftInstructions: draftInstructions
    ]
}

private extension Dictionary where Key == String, Value == String {
    func nonEmptyValue(for key: String) -> String? {
        guard let value = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    func doubleValue(for key: String) -> Double? {
        guard let value = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        return Double(value)
    }

    func booleanValue(for key: String) -> Bool {
        guard let value = self[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }

        return ["1", "true", "yes", "on"].contains(value)
    }

    func hasKey(_ key: String) -> Bool {
        self[key] != nil
    }
}
