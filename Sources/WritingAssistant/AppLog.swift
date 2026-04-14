import Foundation

enum AppLog {
    private static let queue = DispatchQueue(label: "WritingAssistant.AppLog")
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static var logURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("WritingAssistant", isDirectory: true)
            .appendingPathComponent("writing-assistant.log")
    }

    static var logPath: String {
        logURL.path
    }

    static func info(_ message: String) {
        write("INFO", message)
    }

    static func warning(_ message: String) {
        write("WARN", message)
    }

    static func error(_ message: String) {
        write("ERROR", message)
    }

    static func debug(_ message: String) {
        guard AppSettings.shared.debugLogs else {
            return
        }

        write("DEBUG", message)
    }

    static func describeText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var description = "chars=\(trimmed.count), words=\(trimmed.split(whereSeparator: { $0.isWhitespace }).count)"

        if AppSettings.shared.logSelectedText {
            description += ", preview=\"\(trimmed.prefix(120))\""
        }

        return description
    }

    private static func write(_ level: String, _ message: String) {
        let timestamp = timestampFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] \(message)\n"

        queue.async {
            if let data = line.data(using: .utf8) {
                FileHandle.standardError.write(data)
                append(data)
            }
        }
    }

    private static func append(_ data: Data) {
        let url = logURL
        let directoryURL = url.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }

            let fileHandle = try FileHandle(forWritingTo: url)
            defer {
                try? fileHandle.close()
            }

            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: data)
        } catch {
            FileHandle.standardError.write("[WritingAssistant] Failed to write log file: \(error.localizedDescription)\n".data(using: .utf8) ?? Data())
        }
    }
}
