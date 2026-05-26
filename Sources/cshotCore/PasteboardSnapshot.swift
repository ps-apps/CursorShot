import AppKit
import Foundation

public struct PasteboardSnapshot: Equatable {
    public struct Item: Equatable {
        public let values: [(type: NSPasteboard.PasteboardType, data: Data)]

        public init(values: [(type: NSPasteboard.PasteboardType, data: Data)]) {
            self.values = values
        }

        public static func == (lhs: Item, rhs: Item) -> Bool {
            guard lhs.values.count == rhs.values.count else {
                return false
            }

            return zip(lhs.values, rhs.values).allSatisfy { lhsValue, rhsValue in
                lhsValue.type == rhsValue.type && lhsValue.data == rhsValue.data
            }
        }
    }

    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    public static func capture(from pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        let items: [Item] = pasteboard.pasteboardItems?.map { item in
            let values = item.types.compactMap { type -> (type: NSPasteboard.PasteboardType, data: Data)? in
                guard let data = item.data(forType: type) else {
                    return nil
                }
                return (type, data)
            }
            return Item(values: values)
        } ?? []

        return PasteboardSnapshot(items: items)
    }

    public func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()

        let restoredItems = items.map { snapshotItem in
            let item = NSPasteboardItem()
            for value in snapshotItem.values {
                item.setData(value.data, forType: value.type)
            }
            return item
        }

        pasteboard.writeObjects(restoredItems)
    }
}
