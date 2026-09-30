import SwiftUI
import NetheriteCore

/// A `.base` file: filtered, sorted views (table / cards / list) over the vault's notes.
struct BaseView: View {
    let path: String
    @Environment(WindowState.self) private var window
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var base = BaseFile()
    @State private var selected = 0
    @State private var loaded = false
    @State private var showFilters = false
    @State private var showColumns = false
    @State private var loadError: String?
    @State private var confirmDeleteView = false

    private var model: VaultModel { window.model }

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView {
                    Label("Couldn't Open This Base", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(loadError)
                } actions: {
                    Button("Try Again", action: load)
                }
            } else {
                baseBody
            }
        }
        .onAppear(perform: load)
        .onChange(of: path) { load() }
    }

    @ViewBuilder private var baseBody: some View {
        let views = base.views.isEmpty ? [BaseViewConfig(name: String(localized: "Table"))] : base.views
        let view = views[min(selected, views.count - 1)]
        let rows = base.run(view, rows: BaseRow.all(from: model.index))
        let columns = view.order.isEmpty ? ["file.name"] : view.order
        VStack(spacing: 0) {
            header(views: views, view: view, count: rows.count)
            Divider()
            content(view: view, rows: rows, columns: columns)
                .overlay {
                    if rows.isEmpty {
                        ContentUnavailableView("No Results", systemImage: "line.3.horizontal.decrease.circle",
                                               description: Text("No files match this view's filters."))
                    }
                }
        }
    }

    // MARK: Header

    private func header(views: [BaseViewConfig], view: BaseViewConfig, count: Int) -> some View {
        let compact = sizeClass == .compact
        return HStack(spacing: compact ? 4 : 12) {
            Picker("View", selection: $selected) {
                ForEach(Array(views.enumerated()), id: \.offset) { i, v in
                    Label(v.name, systemImage: symbol(v.kind)).tag(i)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .labelStyle(.titleAndIcon)
            .fixedSize(horizontal: !compact, vertical: false)   // may truncate on iPhone instead of pushing controls off-screen
            .iosTarget()

            if sizeClass != .compact {
                Text("\(count) results").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)

            if sizeClass != .compact {
                layoutPicker(view)
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
            }

            sortMenu(view).iosTarget()

            Button("Filter", systemImage: "line.3.horizontal.decrease.circle") { showFilters = true }
                .symbolVariant(view.filters == nil ? .none : .fill)
                .keyboardShortcut("l", modifiers: [.command, .option])
                .help("Filter (⌥⌘L)")
                .accessibilityValue(view.filters == nil ? Text("Off") : Text("On"))
                .iosTarget()
                .popover(isPresented: $showFilters) { FilterEditor(filter: view.filters, keys: allProperties) { f in update { $0.filters = f } } }

            if !compact {
                Button("Properties", systemImage: "tablecells.badge.ellipsis") { showColumns = true }
                    .help("Choose properties")
                    .iosTarget()
                    .popover(isPresented: $showColumns) { columnPicker(view) }
            }

            Menu {
                if sizeClass == .compact {
                    layoutPicker(view).pickerStyle(.inline)
                    Button("Properties…", systemImage: "tablecells.badge.ellipsis") { showColumns = true }
                    Divider()
                }
                ForEach(BaseViewConfig.Kind.allCases, id: \.self) { k in
                    Button(newViewTitle(k), systemImage: symbol(k)) { addView(k) }
                }
                if base.views.count > 1 {
                    Divider()
                    Button("Delete View…", systemImage: "trash", role: .destructive) { confirmDeleteView = true }
                }
            } label: { Label("Views", systemImage: "plus.rectangle.on.rectangle") }
                .menuStyle(.button)
                .fixedSize()
                .iosTarget()
                .help("Add or delete views")
                .confirmationDialog("Delete this view?", isPresented: $confirmDeleteView, titleVisibility: .visible) {
                    Button("Delete View", role: .destructive) { deleteView() }
                } message: {
                    Text("Its filters, sort and columns will be removed from the base.")
                }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .padding(.horizontal, compact ? 8 : 16)
        .padding(.vertical, 8)
        // Compact width opens Properties from the Views menu, so anchor on the header there.
        .popover(isPresented: Binding(get: { compact && showColumns }, set: { showColumns = $0 }), arrowEdge: .top) { columnPicker(view) }
    }

    private func kindName(_ k: BaseViewConfig.Kind) -> String {
        switch k {
        case .table: String(localized: "Table")
        case .cards: String(localized: "Cards")
        case .list: String(localized: "List")
        }
    }

    private func newViewTitle(_ k: BaseViewConfig.Kind) -> LocalizedStringKey {
        switch k {
        case .table: "New Table View"
        case .cards: "New Cards View"
        case .list: "New List View"
        }
    }

    private func layoutPicker(_ view: BaseViewConfig) -> some View {
        Picker("Layout", selection: Binding(get: { view.kind }, set: { k in update { $0.type = k.rawValue } })) {
            ForEach(BaseViewConfig.Kind.allCases, id: \.self) { k in Label(kindName(k), systemImage: symbol(k)).tag(k) }
        }
    }

    private func sortMenu(_ view: BaseViewConfig) -> some View {
        Menu {
            ForEach(allProperties, id: \.self) { p in
                Button {
                    update { v in
                        let asc = v.sort.first?.property == p ? !(v.sort.first?.ascending ?? true) : true
                        v.sort = [BaseSort(property: p, ascending: asc)]
                    }
                } label: {
                    if let s = view.sort.first, s.property == p {
                        Label(base.displayName(p), systemImage: s.ascending ? "chevron.up" : "chevron.down")
                    } else {
                        Text(base.displayName(p))
                    }
                }
            }
            Divider()
            Menu("Group By") {
                Button("None") { update { $0.groupBy = nil } }
                ForEach(allProperties, id: \.self) { p in Button(base.displayName(p)) { update { $0.groupBy = BaseSort(property: p) } } }
            }
            if !view.sort.isEmpty { Button("Clear Sort") { update { $0.sort = [] } } }
        } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
        .help("Sort")
            .menuStyle(.button)
            .fixedSize()
    }

    private func columnPicker(_ view: BaseViewConfig) -> some View {
        ColumnPicker(order: view.order, all: allProperties, displayName: base.displayName, formulas: base.formulas.map(\.name)) { order in
            update { $0.order = order }
        } addFormula: { name, expr in
            base.formulas.removeAll { $0.name == name }
            base.formulas.append((name, expr))
            update { $0.order.append("formula.\(name)") }
        }
    }

    // MARK: Content

    @ViewBuilder private func content(view: BaseViewConfig, rows: [BaseRow], columns: [String]) -> some View {
        let groups = grouped(rows, by: view.groupBy)
        switch view.kind {
        case .table where sizeClass != .compact && view.groupBy == nil:
            BaseTable(base: base, rows: rows, columns: columns, sort: view.sort.first,
                      onSort: { s in update { $0.sort = [s] } }, cell: { cell($0, $1) })
        case .cards:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groups, id: \.title) { g in
                        if let t = g.title { Text(t).font(.headline).padding(.horizontal, 4) }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
                            ForEach(g.rows) { card($0, columns: columns) }
                        }
                    }
                }
                .padding(16)
            }
        default:
            List {
                ForEach(groups, id: \.title) { g in
                    Section(g.title ?? "") {
                        ForEach(g.rows) { r in listRow(r, columns: columns) }
                    }
                }
            }
        }
    }

    private func grouped(_ rows: [BaseRow], by g: BaseSort?) -> [(title: String?, rows: [BaseRow])] {
        guard let g else { return [(nil, rows)] }
        var order: [String] = [], map: [String: [BaseRow]] = [:]
        for r in rows {
            let key = base.value(of: g.property, row: r).description
            let k = key.isEmpty ? String(localized: "None") : key
            if map[k] == nil { order.append(k) }
            map[k, default: []].append(r)
        }
        return order.map { ($0, map[$0]!) }
    }

    private func listRow(_ r: BaseRow, columns: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            openButton(r).font(.headline)
            let props = columns.filter { $0 != "file.name" }.map { ($0, base.value(of: $0, row: r)) }.filter { !$0.1.isEmpty }
            if !props.isEmpty {
                Text(props.map { "\(base.displayName($0.0)): \($0.1)" }.joined(separator: " · "))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }

    private func card(_ r: BaseRow, columns: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let img = coverImage(r, columns: columns) {
                img.resizable().scaledToFill().frame(height: 120).frame(maxWidth: .infinity).clipped()
                    .clipShape(.rect(cornerRadius: 8)).accessibilityHidden(true)
            }
            openButton(r).font(.headline).lineLimit(2)
            ForEach(columns.filter { $0 != "file.name" }.prefix(4), id: \.self) { c in
                let v = base.value(of: c, row: r)
                if !v.isEmpty {
                    LabeledContent(base.displayName(c)) { Text(v.description).lineLimit(1) }.font(.caption)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }

    private func coverImage(_ r: BaseRow, columns: [String]) -> Image? {
        let exts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic"]
        if exts.contains(r.path.fileExtension) { return loadImage(r.path) }
        for c in columns {
            let s = base.value(of: c, row: r).description.trimmingCharacters(in: CharacterSet(charactersIn: "![]"))
            guard exts.contains(s.fileExtension), let p = model.index.resolver.resolve(s, from: r.path) else { continue }
            return loadImage(p)
        }
        return nil
    }

    /// Cached, so scrolling the card grid doesn't reread images from disk.
    private func loadImage(_ path: String) -> Image? {
        ImageCache.shared.image(at: model.vault.url(for: path)).map(Image.init(platformImage:))
    }

    private func openButton(_ r: BaseRow) -> some View {
        Button(base.value(of: "file.name", row: r).description) { window.open(path: r.path) }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
    }

    /// Table cell: file name opens the note; plain note properties are editable in place.
    @ViewBuilder private func cell(_ r: BaseRow, _ column: String) -> some View {
        let v = base.value(of: column, row: r)
        if column == "file.name" {
            openButton(r)
        } else if let key = editableKey(column), r.path.isMarkdown {
            if case .bool(let b) = v {
                Toggle(base.displayName(column), isOn: Binding(get: { b }, set: { setProperty(key, .bool($0), of: r.path) }))
                    .labelsHidden()
            } else {
                PropertyCell(label: base.displayName(column), value: v.description) { setProperty(key, typed($0, like: v), of: r.path) }
            }
        } else {
            Text(v.description).foregroundStyle(.secondary)
        }
    }

    private func editableKey(_ column: String) -> String? {
        if column.hasPrefix("file.") || column.hasPrefix("formula.") { return nil }
        return column.hasPrefix("note.") ? String(column.dropFirst(5)) : column
    }

    private func typed(_ s: String, like old: BaseValue) -> PropertyValue {
        switch old {
        case .number: Double(s).map { .number($0) } ?? .text(s)
        case .date: Frontmatter.parseDate(s).map { .date($0) } ?? .text(s)
        case .list: .list(s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        default: s.isEmpty ? .null : .text(s)
        }
    }

    private func setProperty(_ key: String, _ value: PropertyValue, of note: String) {
        let text = model.text(of: note)
        var props = model.index.notes[note]?.parsed.properties ?? []
        if let i = props.firstIndex(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) { props[i].value = value }
        else { props.append(Property(key: key, value: value)) }
        model.edit(note, text: Frontmatter.replacing(in: text, with: props))
    }

    // MARK: Data

    private var allProperties: [String] {
        let file = ["file.name", "file.path", "file.folder", "file.ext", "file.size", "file.ctime", "file.mtime", "file.tags", "file.links"]
        return file + model.index.propertyKeys.map(\.key) + base.formulas.map { "formula.\($0.name)" }
    }

    private func symbol(_ k: BaseViewConfig.Kind) -> String {
        switch k {
        case .table: "tablecells"
        case .cards: "square.grid.2x2"
        case .list: "list.bullet"
        }
    }

    private func load() {
        let text: String
        do { text = try model.vault.read(path) } catch { loadError = error.localizedDescription; return }
        loadError = nil
        base = BaseFile.parse(text)
        selected = min(selected, max(0, base.views.count - 1))
    }

    /// Mutates the current view and writes the `.base` file.
    private func update(_ change: (inout BaseViewConfig) -> Void) {
        if base.views.isEmpty { base.views = [BaseViewConfig(name: String(localized: "Table"))] }
        let i = min(selected, base.views.count - 1)
        change(&base.views[i])
        save()
    }

    private func addView(_ kind: BaseViewConfig.Kind) {
        let name = "\(kindName(kind)) \(base.views.count + 1)"
        base.views.append(BaseViewConfig(type: kind.rawValue, name: name, order: base.views.first?.order ?? ["file.name"]))
        selected = base.views.count - 1
        save()
    }

    private func deleteView() {
        base.views.remove(at: min(selected, base.views.count - 1))
        selected = 0
        save()
    }

    private func save() {
        guard loadError == nil else { return }   // never overwrite a file we failed to read
        // Written directly: `.base` files aren't Markdown notes, so they must stay out of the note index.
        do { try model.vault.write(base.yaml, to: path) } catch { model.lastError = error.localizedDescription }
    }
}

/// Text cell that commits on Return or when focus leaves.
private struct PropertyCell: View {
    let label: String
    let value: String
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(label, text: $text)
            .labelsHidden()
            .textFieldStyle(.plain)
            .focused($focused)
            .onAppear { text = value }
            .onChange(of: value) { if !focused { text = value } }
            .onSubmit { if text != value { commit(text) } }
            .onChange(of: focused) { if !focused && text != value { commit(text) } }
    }
}

// MARK: Table

private struct BaseTable<Cell: View>: View {
    let base: BaseFile
    let rows: [BaseRow]
    let columns: [String]
    let sort: BaseSort?
    let onSort: (BaseSort) -> Void
    @ViewBuilder let cell: (BaseRow, String) -> Cell

    struct Comparator: SortComparator {
        var property: String
        var order: SortOrder = .forward
        var base: BaseFile
        func compare(_ a: BaseRow, _ b: BaseRow) -> ComparisonResult {
            let c = BaseValue.compare(base.value(of: property, row: a), base.value(of: property, row: b))
            return order == .forward ? c : (c == .orderedAscending ? .orderedDescending : c == .orderedDescending ? .orderedAscending : c)
        }
        static func == (a: Self, b: Self) -> Bool { a.property == b.property && a.order == b.order }
        func hash(into h: inout Hasher) { h.combine(property); h.combine(order) }
    }

    var body: some View {
        let sortOrder = Binding<[Comparator]>(
            get: { sort.map { [Comparator(property: $0.property, order: $0.ascending ? .forward : .reverse, base: base)] } ?? [] },
            set: { if let f = $0.first { onSort(BaseSort(property: f.property, ascending: f.order == .forward)) } })
        Table(rows, sortOrder: sortOrder) {
            TableColumnForEach(columns, id: \.self) { c in
                TableColumn(base.displayName(c), sortUsing: Comparator(property: c, base: base)) { r in cell(r, c) }
            }
        }
    }
}

// MARK: Filters

/// Rule builder: each row is an expression; rows combine with all (and) / any (or).
private struct FilterEditor: View {
    let filter: BaseFilter?
    let keys: [String]
    let apply: (BaseFilter?) -> Void
    @State private var rules: [String] = []
    @State private var any = false
    @State private var property = "file.name"
    @State private var op = "contains"
    @State private var value = ""
    @Environment(\.dismiss) private var dismiss

    static let ops = ["==", "!=", "contains", "starts with", ">", "<", "is empty", "is not empty", "has tag", "in folder"]

    var body: some View {
        Form {
            Picker("Match", selection: $any) {
                Text("All rules").tag(false)
                Text("Any rule").tag(true)
            }
            .pickerStyle(.segmented)
            Section("Rules") {
                ForEach(Array(rules.enumerated()), id: \.offset) { i, _ in
                    HStack {
                        TextField("Expression", text: Binding(get: { rules.indices.contains(i) ? rules[i] : "" },
                                                              set: { if rules.indices.contains(i) { rules[i] = $0 } }))
                            .font(.body.monospaced())
                        Button("Remove Rule", systemImage: "minus.circle") { if rules.indices.contains(i) { rules.remove(at: i) } }
                            .iosTarget()
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
                if rules.isEmpty { Text("No filters — every file is included.").foregroundStyle(.secondary) }
            }
            Section("Add rule") {
                Picker("Property", selection: $property) { ForEach(keys, id: \.self) { Text($0).tag($0) } }
                Picker("Operator", selection: $op) { ForEach(Self.ops, id: \.self) { Text($0).tag($0) } }
                if !op.hasPrefix("is ") { TextField("Value", text: $value) }
                Button("Add Rule", systemImage: "plus") { rules.append(expression()); value = "" }
            }
            HStack {
                Button("Clear") { rules = [] ; commit() }
                Spacer()
                Button("Apply") { commit() }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 420)
        #endif
        .onAppear(perform: loadRules)
    }

    private func expression() -> String {
        let quoted = Double(value) != nil ? value : "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
        switch op {
        case "contains": return "\(property).contains(\(quoted))"
        case "starts with": return "\(property).startsWith(\(quoted))"
        case "is empty": return "\(property).isEmpty()"
        case "is not empty": return "!\(property).isEmpty()"
        case "has tag": return "file.hasTag(\"\(value)\")"
        case "in folder": return "file.inFolder(\"\(value)\")"
        default: return "\(property) \(op) \(quoted)"
        }
    }

    private func loadRules() {
        switch filter {
        case .and(let k): rules = k.map(describe); any = false
        case .or(let k): rules = k.map(describe); any = true
        case .expr(let s): rules = [s]
        case .not(let k): rules = k.map { "!(\(describe($0)))" }
        case nil: rules = []
        }
    }

    /// Nested trees are flattened to a single expression string.
    private func describe(_ f: BaseFilter) -> String {
        switch f {
        case .expr(let s): s
        case .and(let k): "(" + k.map(describe).joined(separator: " && ") + ")"
        case .or(let k): "(" + k.map(describe).joined(separator: " || ") + ")"
        case .not(let k): "!(" + k.map(describe).joined(separator: " || ") + ")"
        }
    }

    private func commit() {
        defer { dismiss() }
        let exprs = rules.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map(BaseFilter.expr)
        apply(exprs.isEmpty ? nil : (any ? .or(exprs) : .and(exprs)))
    }
}

// MARK: Columns

private struct ColumnPicker: View {
    let order: [String]
    let all: [String]
    let displayName: (String) -> String
    let formulas: [String]
    let apply: ([String]) -> Void
    let addFormula: (String, String) -> Void
    @State private var name = ""
    @State private var expr = ""

    var body: some View {
        Form {
            Section("Shown") {
                ForEach(order, id: \.self) { c in
                    Toggle(displayName(c), isOn: Binding(get: { true }, set: { if !$0 { apply(order.filter { $0 != c }) } }))
                }
                .onMove { var o = order; o.move(fromOffsets: $0, toOffset: $1); apply(o) }
            }
            #if os(iOS)
            .environment(\.editMode, .constant(.active))   // drag handles to reorder shown columns
            #endif
            Section("Available") {
                ForEach(all.filter { !order.contains($0) }, id: \.self) { c in
                    Toggle(displayName(c), isOn: Binding(get: { false }, set: { if $0 { apply(order + [c]) } }))
                }
            }
            Section("Add formula") {
                TextField("Name", text: $name)
                TextField("Expression, e.g. rating * 2", text: $expr).font(.body.monospaced())
                Button("Add Formula", systemImage: "function") {
                    addFormula(name.trimmingCharacters(in: .whitespaces), expr)
                    name = ""; expr = ""
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || BaseExpr.parse(expr) == nil)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 320, minHeight: 440)
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

private extension View {
    /// 44×44 pt minimum hit area for icon-only controls on iOS.
    @ViewBuilder func iosTarget() -> some View {
        #if os(iOS)
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        #else
        self
        #endif
    }
}
