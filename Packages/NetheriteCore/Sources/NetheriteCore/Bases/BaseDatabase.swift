import Foundation

/// Notion-style databases on top of Bases: a folder of notes plus a `.base` listing them.
public extension BaseFile {
    /// `<folder>.base` content listing the notes in `folder` (a table, plus a board when `boardColumns` is given).
    static func database(folder: String, properties: [String] = ["status", "tags", "date"], boardColumns: [String]? = nil) -> BaseFile {
        var f = BaseFile()
        let quoted = folder.replacingOccurrences(of: "\"", with: "\\\"")
        f.filters = .and([.expr("file.inFolder(\"\(quoted)\")"), .expr("file.ext == \"md\"")])
        f.views = [BaseViewConfig(name: String(localized: "Table", bundle: .module), order: ["file.name"] + properties)]
        if let boardColumns {
            var board = BaseViewConfig(type: BaseViewConfig.Kind.board.rawValue, name: String(localized: "Board", bundle: .module), order: ["file.name"] + properties)
            board.groupBy = BaseSort(property: "status")
            board.columns = boardColumns
            f.views.append(board)
        }
        return f
    }

    /// Folder new entries go in: the global `file.inFolder("…")` filter, if any.
    var entryFolder: String? {
        func find(_ f: BaseFilter?) -> String? {
            switch f {
            case .expr(let s):
                guard case .method(.ident(let id), "inFolder", let args)? = BaseExpr.parse(s), id == ["file"],
                      case .literal(.string(let p))? = args.first else { return nil }
                return p.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            case .and(let k): return k.lazy.compactMap(find).first
            default: return nil
            }
        }
        return find(filters)
    }

    /// Board columns for `property`: "no value" (nil) first, then the view's stored columns, then other values as found.
    func board(_ view: BaseViewConfig, rows: [BaseRow], property: String) -> [(value: String?, rows: [BaseRow])] {
        var order: [String?] = [nil] + view.columns.map { Optional($0) }
        var map: [String?: [BaseRow]] = [:]
        for r in rows {
            let s = value(of: property, row: r).description
            let key: String? = s.isEmpty ? nil : s
            if !order.contains(key) { order.append(key) }
            map[key, default: []].append(r)
        }
        return order.map { ($0, map[$0] ?? []) }
    }
}

public extension BaseViewConfig {
    /// Property a board groups by.
    var boardProperty: String { groupBy?.property ?? "status" }
}

public extension PropertyValue {
    /// Value given to a newly added property: empty, except unchecked boxes and empty lists.
    static func empty(_ kind: Kind) -> PropertyValue {
        switch kind {
        case .checkbox: .bool(false)
        case .list: .list([])
        default: .null
        }
    }
}
