import AppKit

struct ClipboardSnapshot {
    private let items: [Item]

    static func capture(from pasteboard: NSPasteboard = .general) -> ClipboardSnapshot {
        let items = pasteboard.pasteboardItems?.map { item in
            Item(dataByType: item.types.compactMap { type in
                guard let data = item.data(forType: type) else { return nil }
                return (type, data)
            })
        } ?? []

        return ClipboardSnapshot(items: items)
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()

        let restoredItems = items.map { item -> NSPasteboardItem in
            let restoredItem = NSPasteboardItem()
            for (type, data) in item.dataByType {
                restoredItem.setData(data, forType: type)
            }
            return restoredItem
        }

        pasteboard.writeObjects(restoredItems)
    }

    private struct Item {
        let dataByType: [(NSPasteboard.PasteboardType, Data)]
    }
}
