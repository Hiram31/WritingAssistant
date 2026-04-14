import Foundation
import Security

final class KeychainStore {
    private let service: String
    private let account: String

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }

        return value
    }

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery()
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecSuccess {
            return
        }

        if status == errSecItemNotFound {
            var addQuery = baseQuery()
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(addStatus)
            }
            return
        }

        throw KeychainError.unhandledStatus(status)
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum KeychainError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain returned status \(status)."
        }
    }
}
