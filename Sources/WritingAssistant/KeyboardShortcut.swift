import AppKit
import Carbon

struct KeyboardShortcut: Equatable {
    static let relevantModifiers: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    let key: String
    let modifiers: NSEvent.ModifierFlags

    init?(_ rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: " ", with: "+")

        guard !normalized.isEmpty else { return nil }

        var modifiers: NSEvent.ModifierFlags = []
        var keyParts: [String] = []

        for part in normalized.split(separator: "+").map(String.init) {
            switch part {
            case "cmd", "command":
                modifiers.insert(.command)
            case "opt", "option", "alt":
                modifiers.insert(.option)
            case "ctrl", "control":
                modifiers.insert(.control)
            case "shift":
                modifiers.insert(.shift)
            default:
                keyParts.append(part)
            }
        }

        guard keyParts.count == 1,
              let key = Self.normalizedKey(from: keyParts[0]),
              modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control) else {
            return nil
        }

        self.key = key
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
    }

    init?(event: NSEvent) {
        guard let key = Self.eventKey(from: event) else { return nil }
        let modifiers = event.modifierFlags.intersection(Self.relevantModifiers)

        guard modifiers.contains(.command) || modifiers.contains(.option) || modifiers.contains(.control) else {
            return nil
        }

        self.key = key
        self.modifiers = modifiers
    }

    var displayString: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Opt") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }
        parts.append(displayKey)
        return parts.joined(separator: "+")
    }

    var menuKeyEquivalent: String {
        switch key {
        case "\r":
            return "\r"
        case "\t":
            return "\t"
        case "\u{1B}":
            return "\u{1B}"
        default:
            return key.lowercased()
        }
    }

    var menuModifierMask: NSEvent.ModifierFlags {
        modifiers
    }

    func matches(_ event: NSEvent) -> Bool {
        guard let eventShortcut = KeyboardShortcut(event: event) else { return false }
        return eventShortcut == self
    }

    var carbonKeyCode: UInt32? {
        Self.keyCode(for: key)
    }

    var carbonModifierFlags: UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        return flags
    }

    private var displayKey: String {
        switch key {
        case " ":
            return "Space"
        case "\r":
            return "Return"
        case "\t":
            return "Tab"
        case "\u{1B}":
            return "Esc"
        case ",":
            return ","
        case ".":
            return "."
        case "/":
            return "/"
        case ";":
            return ";"
        case "'":
            return "'"
        case "[":
            return "["
        case "]":
            return "]"
        case "-":
            return "-"
        case "=":
            return "="
        default:
            return key
        }
    }

    private static func normalizedKey(from value: String) -> String? {
        switch value {
        case "space":
            return " "
        case "return", "enter":
            return "\r"
        case "tab":
            return "\t"
        case "esc", "escape":
            return "\u{1B}"
        case "comma", ",":
            return ","
        case "period", ".":
            return "."
        case "slash", "/":
            return "/"
        case "semicolon", ";":
            return ";"
        case "quote", "'":
            return "'"
        case "leftbracket", "[":
            return "["
        case "rightbracket", "]":
            return "]"
        case "minus", "-":
            return "-"
        case "equals", "=":
            return "="
        default:
            let uppercased = value.uppercased()
            guard uppercased.count == 1,
                  uppercased.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil else {
                return nil
            }
            return uppercased
        }
    }

    private static func eventKey(from event: NSEvent) -> String? {
        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            return nil
        }

        switch characters {
        case "\r":
            return "\r"
        case "\t":
            return "\t"
        case "\u{1B}":
            return "\u{1B}"
        case " ":
            return " "
        case ",", ".", "/", ";", "'", "[", "]", "-", "=":
            return characters
        default:
            let uppercased = characters.uppercased()
            guard uppercased.count == 1,
                  uppercased.rangeOfCharacter(from: CharacterSet.alphanumerics) != nil else {
                return nil
            }
            return uppercased
        }
    }

    private static func keyCode(for key: String) -> UInt32? {
        switch key {
        case "A": return 0
        case "S": return 1
        case "D": return 2
        case "F": return 3
        case "H": return 4
        case "G": return 5
        case "Z": return 6
        case "X": return 7
        case "C": return 8
        case "V": return 9
        case "B": return 11
        case "Q": return 12
        case "W": return 13
        case "E": return 14
        case "R": return 15
        case "Y": return 16
        case "T": return 17
        case "1": return 18
        case "2": return 19
        case "3": return 20
        case "4": return 21
        case "6": return 22
        case "5": return 23
        case "9": return 25
        case "7": return 26
        case "8": return 28
        case "0": return 29
        case "O": return 31
        case "U": return 32
        case "I": return 34
        case "P": return 35
        case "\r": return 36
        case "L": return 37
        case "J": return 38
        case "K": return 40
        case "N": return 45
        case "M": return 46
        case "\t": return 48
        case " ": return 49
        case "\u{1B}": return 53
        case ",": return 43
        case ".": return 47
        case "/": return 44
        case ";": return 41
        case "'": return 39
        case "[": return 33
        case "]": return 30
        case "-": return 27
        case "=": return 24
        default:
            return nil
        }
    }
}
