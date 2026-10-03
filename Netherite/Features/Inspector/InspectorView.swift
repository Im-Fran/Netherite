import SwiftUI
import NetheriteCore

enum InspectorTab: String, CaseIterable, Identifiable {
    case backlinks, outgoing, outline, properties, footnotes
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .backlinks: "Backlinks"
        case .outgoing: "Outgoing links"
        case .outline: "Outline"
        case .properties: "Properties"
        case .footnotes: "Footnotes"
        }
    }
    var symbol: String {
        switch self {
        case .backlinks: "arrow.uturn.backward"
        case .outgoing: "arrow.up.right"
        case .outline: "list.bullet.indent"
        case .properties: "list.bullet.rectangle"
        case .footnotes: "textformat.superscript"
        }
    }
}

struct InspectorView: View {
    @Environment(WindowState.self) private var window
    @AppStorage("inspectorTab") private var tab: InspectorTab = .backlinks

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $tab) {
                ForEach(InspectorTab.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelStyle(.iconOnly)
            .labelsHidden()
            .padding(8)

            if let path = window.currentNote {
                switch tab {
                case .backlinks: BacklinksView(path: path)
                case .outgoing: OutgoingLinksView(path: path)
                case .outline: OutlineView(path: path)
                case .properties: PropertiesEditor(path: path)
                case .footnotes: FootnotesView(path: path)
                }
            } else {
                ContentUnavailableView("No Note Open", systemImage: "doc.text")
                    .frame(maxHeight: .infinity)
            }
        }
        // Fill the column so the tab picker stays pinned to the top.
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct BacklinksView: View {
    let path: String
    @Environment(WindowState.self) private var window
    @State private var showUnlinked = false

    var body: some View {
        let index = window.model.index
        let linked = index.backlinks(for: path)
        List {
            Section("Linked mentions (\(linked.count))") {
                ForEach(linked) { b in mention(b) }
            }
            Section(isExpanded: $showUnlinked) {
                if showUnlinked {
                    ForEach(index.unlinkedMentions(for: path)) { b in
                        mention(b, linkAction: { linkMentions(in: b.source) })
                    }
                }
            } header: {
                Text("Unlinked mentions")
            }
        }
        .listStyle(.sidebar)
    }

    private func mention(_ b: Backlink, linkAction: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button { window.open(path: b.source) } label: {
                    Label(b.source.noteName, systemImage: symbol(for: b.source)).font(.headline)
                }
                .buttonStyle(.plain)
                Spacer()
                if let linkAction { Button("Link", action: linkAction).controlSize(.small) }
            }
            ForEach(b.contexts, id: \.line) { ctx in
                Button { window.open(path: b.source, line: ctx.line) } label: {
                    Text(ctx.text.trimmingCharacters(in: .whitespaces)).font(.callout).foregroundStyle(.secondary).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    /// Turns plain mentions of this note's name into [[links]] in `source`.
    private func linkMentions(in source: String) {
        let model = window.model
        let name = path.noteName
        let text = model.text(of: source)
        let masked = NoteParser.maskedText(text) as NSString
        guard let re = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}\\[])\(NSRegularExpression.escapedPattern(for: name))(?![\\p{L}\\p{N}\\]])", options: .caseInsensitive) else { return }
        let links = NoteParser.parse(text).links.map(\.range)
        let out = NSMutableString(string: text)
        let target = model.index.resolver.linkText(for: path)
        for m in re.matches(in: masked as String, range: NSRange(location: 0, length: masked.length)).reversed()
        where !links.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) {
            let found = (text as NSString).substring(with: m.range)
            out.replaceCharacters(in: m.range, with: found == target ? "[[\(target)]]" : "[[\(target)|\(found)]]")
        }
        model.overwrite(source, with: out as String)
    }
}

struct OutgoingLinksView: View {
    let path: String
    @Environment(WindowState.self) private var window

    var body: some View {
        let index = window.model.index
        List {
            Section("Links") {
                ForEach(index.outgoing[path] ?? [], id: \.self) { p in
                    Button { window.open(path: p) } label: { Label(p.isMarkdown ? p.noteName : (p as NSString).lastPathComponent, systemImage: symbol(for: p)) }
                        .buttonStyle(.plain)
                }
            }
            let missing = index.unresolved[path] ?? []
            if !missing.isEmpty {
                Section("Unresolved") {
                    ForEach(missing, id: \.self) { t in
                        Button { window.follow(NoteParser.splitWiki(t, isEmbed: false), from: path) } label: {
                            Label(t, systemImage: "doc.badge.plus").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Create this note")
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}

struct OutlineView: View {
    let path: String
    @Environment(WindowState.self) private var window
    @ScaledMetric private var indent: CGFloat = 14

    var body: some View {
        let headings = window.model.index.notes[path]?.parsed.headings ?? []
        let minLevel = headings.map(\.level).min() ?? 1
        List(headings) { h in
            Button { window.pane.open(.note(path), line: h.line) } label: {
                Text(h.text)
                    .font(h.level == minLevel ? .body.weight(.semibold) : .body)
                    .padding(.leading, CGFloat(h.level - minLevel) * indent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { Button("Bookmark Heading", systemImage: "bookmark") { window.model.addBookmark(.heading(path, h.text)) } }
        }
        .listStyle(.sidebar)
        .overlay { if headings.isEmpty { ContentUnavailableView("No Headings", systemImage: "list.bullet.indent") } }
    }
}

struct FootnotesView: View {
    let path: String
    @Environment(WindowState.self) private var window

    var body: some View {
        let notes = window.model.index.notes[path]?.parsed.footnotes ?? []
        List(notes) { f in
            Button { window.pane.open(.note(path), line: f.line) } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(f.label).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(f.text).lineLimit(4)
                }
            }
            .buttonStyle(.plain)
        }
        .listStyle(.sidebar)
        .overlay { if notes.isEmpty { ContentUnavailableView("No Footnotes", systemImage: "textformat.superscript") } }
    }
}

/// Edits the note's YAML frontmatter as typed properties.
struct PropertiesEditor: View {
    let path: String
    /// Compact layout used in the note header (Live Preview) instead of a grouped form.
    var inline = false
    @Environment(WindowState.self) private var window
    @State private var newKey = ""
    @AppStorage("propertiesExpanded") private var expanded = true

    var body: some View {
        let props = window.model.index.notes[path]?.parsed.properties ?? []
        if inline {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(props) { p in
                        row(p, props)
                            .textFieldStyle(.plain)
                        Divider()
                    }
                    addField.textFieldStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            } label: {
                Label("Properties", systemImage: "list.bullet.rectangle").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            }
        } else {
            Form {
                ForEach(props) { p in row(p, props) }
                addField
            }
            .formStyle(.grouped)
        }
    }

    private var addField: some View {
        HStack {
            TextField("Add property", text: $newKey)
                .onSubmit(add)
            Button(action: add) { Label("Add Property", systemImage: "plus").labelStyle(.iconOnly).hitTarget() }
                .buttonStyle(.borderless)
                .help("Add Property")
                .disabled(newKey.isEmpty)
        }
    }

    private func row(_ p: Property, _ props: [Property]) -> some View {
                LabeledContent {
                    editor(for: p, all: props)
                } label: {
                    Label(p.key, systemImage: icon(p.value.kind))
                }
                .contextMenu {
                    Menu("Property Type") {
                        ForEach(PropertyValue.Kind.allCases, id: \.self) { k in
                            Button(k.label) { set(p.key, convert(p.value, to: k), in: props) }
                        }
                    }
                    Button("Remove", systemImage: "trash", role: .destructive) { save(props.filter { $0.key != p.key }) }
                }
    }

    @ViewBuilder private func editor(for p: Property, all: [Property]) -> some View {
        switch p.value {
        case .bool(let b):
            Toggle(p.key, isOn: Binding(get: { b }, set: { set(p.key, .bool($0), in: all) })).labelsHidden()
        case .date(let d):
            DatePicker(p.key, selection: Binding(get: { d }, set: { set(p.key, .date($0), in: all) }), displayedComponents: .date).labelsHidden()
        case .number(let n):
            TextField(p.key, value: Binding(get: { n }, set: { set(p.key, .number($0), in: all) }), format: .number)
                .labelsHidden().multilineTextAlignment(.trailing)
        case .list(let l):
            TextField(p.key, text: Binding(get: { l.joined(separator: ", ") },
                                        set: { set(p.key, .list($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }), in: all) }))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
        default:
            TextField(p.key, text: Binding(get: { p.value.displayString }, set: { set(p.key, .text($0), in: all) }))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
        }
    }

    private func icon(_ k: PropertyValue.Kind) -> String {
        switch k {
        case .text: "text.alignleft"
        case .number: "number"
        case .checkbox: "checkmark.square"
        case .date: "calendar"
        case .list: "list.bullet"
        }
    }

    private func convert(_ v: PropertyValue, to k: PropertyValue.Kind) -> PropertyValue {
        switch k {
        case .text: .text(v.displayString)
        case .number: .number(Double(v.displayString) ?? 0)
        case .checkbox: .bool(v.displayString == "true")
        case .date: .date(Frontmatter.parseDate(v.displayString) ?? .now)
        case .list: .list(v.strings.isEmpty ? [v.displayString].filter { !$0.isEmpty } : v.strings)
        }
    }

    private func set(_ key: String, _ value: PropertyValue, in props: [Property]) {
        save(props.map { $0.key == key ? Property(key: key, value: value) : $0 })
    }

    private func add() {
        let key = newKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        let props = window.model.index.notes[path]?.parsed.properties ?? []
        guard !props.contains(where: { $0.key == key }) else { return }
        let value: PropertyValue = ["tags", "aliases", "cssclasses"].contains(key) ? .list([]) : .text("")
        save(props + [Property(key: key, value: value)])
        newKey = ""
    }

    private func save(_ props: [Property]) {
        let text = window.model.text(of: path)
        window.model.edit(path, text: Frontmatter.replacing(in: text, with: props))
    }
}

private extension PropertyValue.Kind {
    var label: LocalizedStringKey {
        switch self {
        case .text: "Text"
        case .number: "Number"
        case .checkbox: "Checkbox"
        case .date: "Date"
        case .list: "List"
        }
    }
}
