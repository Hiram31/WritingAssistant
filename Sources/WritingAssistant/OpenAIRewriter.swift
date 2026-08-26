import Foundation

enum RewriteResultPresentation {
    case replaceSelection
    case displayInPanel
}

struct RewriteAction {
    let id: String
    let title: String
    let displayTitle: String
    let shortTitle: String
    let systemImageName: String?
    let tooltip: String
    let instructions: String
    let resultPresentation: RewriteResultPresentation

    static var grammar: RewriteAction {
        BuiltInTune.grammar.rewriteAction(settings: AppSettings.shared)
    }
}

final class OpenAIRewriter {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func process(_ text: String, action: RewriteAction) async throws -> String {
        AppLog.info("LLM request starting action=\(action.title), input \(AppLog.describeText(text))")
        let configuration = try AppSettings.shared.llmConfiguration()
        AppLog.info("LLM configuration loaded provider=\(configuration.provider.displayName), endpointHost=\(configuration.baseURL.host ?? "unknown"), model=\(configuration.model)")

        if configuration.provider == .ollama {
            return try await processOllama(text, action: action, configuration: configuration)
        }

        if configuration.provider == .customOpenAICompatible {
            switch configuration.customAPIFormat ?? .openAIChatCompletions {
            case .openAIChatCompletions:
                break
            case .anthropicMessages:
                return try await processAnthropic(text, action: action, configuration: configuration)
            case .geminiGenerateContent:
                return try await processGemini(text, action: action, configuration: configuration)
            case .cohereChat:
                return try await processCohere(text, action: action, configuration: configuration)
            }
        }

        var request = URLRequest(url: configuration.chatCompletionsURL)
        request.httpMethod = "POST"
        configuration.applyAuthentication(to: &request)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatCompletionsRequest(
            model: configuration.requestModel,
            messages: [
                ChatMessage(role: "system", content: action.instructions),
                ChatMessage(role: "user", content: text)
            ],
            maxTokens: configuration.maxTokens,
            tokenParameter: configuration.tokenParameter
        ))

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        AppLog.info("LLM response received provider=\(configuration.provider.displayName), status=\(statusCode), bytes=\(data.count)")

        guard (200..<300).contains(statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                AppLog.error("LLM API error status=\(statusCode), message=\(apiError.error.message)")
                throw RewriteError.api(apiError.error.message)
            }
            if let simpleError = try? JSONDecoder().decode(SimpleAPIErrorEnvelope.self, from: data) {
                AppLog.error("LLM API error status=\(statusCode), message=\(simpleError.error)")
                throw RewriteError.api(simpleError.error)
            }
            AppLog.error("LLM API error status=\(statusCode), undecodableBodyBytes=\(data.count)")
            throw RewriteError.api("\(configuration.provider.displayName) request failed with status \(statusCode).")
        }

        let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
        let output = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            AppLog.error("LLM response decoded but output text was empty.")
            throw RewriteError.emptyResponse
        }

        AppLog.info("LLM request finished provider=\(configuration.provider.displayName), action=\(action.title), output \(AppLog.describeText(output))")
        return output
    }

    private func processOllama(
        _ text: String,
        action: RewriteAction,
        configuration: LLMConfiguration
    ) async throws -> String {
        var request = URLRequest(url: configuration.ollamaGenerateURL)
        request.httpMethod = "POST"
        configuration.applyAuthentication(to: &request)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaGenerateRequest(
            model: configuration.model,
            prompt: text,
            system: action.instructions,
            stream: false,
            options: OllamaOptions(numPredict: configuration.maxTokens)
        ))

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        AppLog.info("Ollama response received status=\(statusCode), bytes=\(data.count)")

        guard (200..<300).contains(statusCode) else {
            if let apiError = try? JSONDecoder().decode(SimpleAPIErrorEnvelope.self, from: data) {
                AppLog.error("Ollama API error status=\(statusCode), message=\(apiError.error)")
                throw RewriteError.api(apiError.error)
            }

            AppLog.error("Ollama API error status=\(statusCode), undecodableBodyBytes=\(data.count)")
            throw RewriteError.api("Ollama request failed with status \(statusCode).")
        }

        let decoded = try JSONDecoder().decode(OllamaGenerateResponse.self, from: data)
        let output = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            AppLog.error("Ollama response decoded but output text was empty.")
            throw RewriteError.emptyResponse
        }

        AppLog.info("Ollama request finished action=\(action.title), output \(AppLog.describeText(output))")
        return output
    }

    private func processAnthropic(
        _ text: String,
        action: RewriteAction,
        configuration: LLMConfiguration
    ) async throws -> String {
        var request = URLRequest(url: configuration.anthropicMessagesURL)
        request.httpMethod = "POST"
        configuration.applyAnthropicAuthentication(to: &request)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AnthropicMessagesRequest(
            model: configuration.model,
            maxTokens: configuration.maxTokens,
            system: action.instructions,
            messages: [ChatMessage(role: "user", content: text)]
        ))

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        AppLog.info("Anthropic response received status=\(statusCode), bytes=\(data.count)")

        try validateSuccessfulResponse(data: data, statusCode: statusCode, providerName: "Anthropic")

        let decoded = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        let output = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            AppLog.error("Anthropic response decoded but output text was empty.")
            throw RewriteError.emptyResponse
        }

        AppLog.info("Anthropic request finished action=\(action.title), output \(AppLog.describeText(output))")
        return output
    }

    private func processGemini(
        _ text: String,
        action: RewriteAction,
        configuration: LLMConfiguration
    ) async throws -> String {
        var request = URLRequest(url: configuration.geminiGenerateContentURL)
        request.httpMethod = "POST"
        configuration.applyGeminiAuthentication(to: &request)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(GeminiGenerateContentRequest(
            systemInstruction: GeminiContent(parts: [GeminiPart(text: action.instructions)], role: nil),
            contents: [
                GeminiContent(parts: [GeminiPart(text: text)], role: "user")
            ],
            generationConfig: GeminiGenerationConfig(maxOutputTokens: configuration.maxTokens)
        ))

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        AppLog.info("Gemini response received status=\(statusCode), bytes=\(data.count)")

        try validateSuccessfulResponse(data: data, statusCode: statusCode, providerName: "Gemini")

        let decoded = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
        let output = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            AppLog.error("Gemini response decoded but output text was empty.")
            throw RewriteError.emptyResponse
        }

        AppLog.info("Gemini request finished action=\(action.title), output \(AppLog.describeText(output))")
        return output
    }

    private func processCohere(
        _ text: String,
        action: RewriteAction,
        configuration: LLMConfiguration
    ) async throws -> String {
        var request = URLRequest(url: configuration.cohereChatURL)
        request.httpMethod = "POST"
        configuration.applyAuthentication(to: &request)
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CohereChatRequest(
            model: configuration.model,
            messages: [
                ChatMessage(role: "system", content: action.instructions),
                ChatMessage(role: "user", content: text)
            ],
            maxTokens: configuration.maxTokens
        ))

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        AppLog.info("Cohere response received status=\(statusCode), bytes=\(data.count)")

        try validateSuccessfulResponse(data: data, statusCode: statusCode, providerName: "Cohere")

        let decoded = try JSONDecoder().decode(CohereChatResponse.self, from: data)
        let output = decoded.outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else {
            AppLog.error("Cohere response decoded but output text was empty.")
            throw RewriteError.emptyResponse
        }

        AppLog.info("Cohere request finished action=\(action.title), output \(AppLog.describeText(output))")
        return output
    }

    private func validateSuccessfulResponse(data: Data, statusCode: Int, providerName: String) throws {
        guard (200..<300).contains(statusCode) else {
            if let message = apiErrorMessage(from: data) {
                AppLog.error("\(providerName) API error status=\(statusCode), message=\(message)")
                throw RewriteError.api(message)
            }

            AppLog.error("\(providerName) API error status=\(statusCode), undecodableBodyBytes=\(data.count)")
            throw RewriteError.api("\(providerName) request failed with status \(statusCode).")
        }
    }

    private func apiErrorMessage(from data: Data) -> String? {
        if let apiError = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            return apiError.error.message
        }
        if let simpleError = try? JSONDecoder().decode(SimpleAPIErrorEnvelope.self, from: data) {
            return simpleError.error
        }
        if let messageError = try? JSONDecoder().decode(MessageAPIErrorEnvelope.self, from: data) {
            return messageError.message
        }
        return nil
    }

    func draft(for request: String) async throws -> String {
        let action = RewriteAction(
            id: "draft",
            title: "draft",
            displayTitle: "Draft",
            shortTitle: "Send",
            systemImageName: nil,
            tooltip: "Generate a new draft",
            instructions: AppSettings.shared.draftInstructions,
            resultPresentation: .replaceSelection
        )

        return try await process(request, action: action)
    }
}

enum RewriteError: LocalizedError {
    case missingAzureConfiguration(String)
    case missingProviderConfiguration(String)
    case api(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .missingAzureConfiguration(let name):
            return "Set \(name) before launching the app."
        case .missingProviderConfiguration(let name):
            return "Set \(name) in Settings before using the app."
        case .api(let message):
            return message
        case .emptyResponse:
            return "The model returned an empty response."
        }
    }
}

private struct ChatCompletionsRequest: Encodable {
    let model: String?
    let messages: [ChatMessage]
    let maxTokens: Int
    let tokenParameter: ChatTokenParameter

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxCompletionTokens = "max_completion_tokens"
        case maxTokens = "max_tokens"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encode(messages, forKey: .messages)

        switch tokenParameter {
        case .maxCompletionTokens:
            try container.encode(maxTokens, forKey: .maxCompletionTokens)
        case .maxTokens:
            try container.encode(maxTokens, forKey: .maxTokens)
        }
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatCompletionsResponse: Decodable {
    let choices: [Choice]

    var outputText: String {
        choices
            .compactMap(\.message.content)
            .joined(separator: "\n")
    }

    struct Choice: Decodable {
        let message: ChatMessage
    }
}

private struct APIErrorEnvelope: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}

private struct SimpleAPIErrorEnvelope: Decodable {
    let error: String
}

private struct MessageAPIErrorEnvelope: Decodable {
    let message: String
}

private struct AnthropicMessagesRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ChatMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }
}

private struct AnthropicMessagesResponse: Decodable {
    let content: [ContentBlock]

    var outputText: String {
        content
            .compactMap(\.text)
            .joined(separator: "\n")
    }

    struct ContentBlock: Decodable {
        let type: String?
        let text: String?
    }
}

private struct GeminiGenerateContentRequest: Encodable {
    let systemInstruction: GeminiContent
    let contents: [GeminiContent]
    let generationConfig: GeminiGenerationConfig

    enum CodingKeys: String, CodingKey {
        case systemInstruction = "system_instruction"
        case contents
        case generationConfig
    }
}

private struct GeminiContent: Codable {
    let parts: [GeminiPart]
    let role: String?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(parts, forKey: .parts)
        try container.encodeIfPresent(role, forKey: .role)
    }
}

private struct GeminiPart: Codable {
    let text: String?
}

private struct GeminiGenerationConfig: Encodable {
    let maxOutputTokens: Int
}

private struct GeminiGenerateContentResponse: Decodable {
    let candidates: [Candidate]?

    var outputText: String {
        candidates?
            .flatMap { $0.content?.parts ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n") ?? ""
    }

    struct Candidate: Decodable {
        let content: GeminiContent?
    }
}

private struct CohereChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int
    let stream = false

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case stream
    }
}

private struct CohereChatResponse: Decodable {
    let message: ResponseMessage?

    var outputText: String {
        message?.content?
            .compactMap(\.text)
            .joined(separator: "\n") ?? ""
    }

    struct ResponseMessage: Decodable {
        let content: [ContentBlock]?
    }

    struct ContentBlock: Decodable {
        let type: String?
        let text: String?
    }
}

private struct OllamaGenerateRequest: Encodable {
    let model: String
    let prompt: String
    let system: String
    let stream: Bool
    let options: OllamaOptions
}

private struct OllamaOptions: Encodable {
    let numPredict: Int

    enum CodingKeys: String, CodingKey {
        case numPredict = "num_predict"
    }
}

private struct OllamaGenerateResponse: Decodable {
    let response: String
}
