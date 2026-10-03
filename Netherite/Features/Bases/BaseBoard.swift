import SwiftUI
import NetheriteCore

/// Kanban view of a base: a column per value of `property`. Cards move by drag and drop, or with the
/// context menu / VoiceOver actions.
struct BaseBoard: View {
    let base: BaseFile
    let groups: [(value: String?, rows: [BaseRow])]
    let property: String
    /// Properties shown on cards.
    let fields: [String]
    /// False when the board groups by a file or formula property, which can't be written.
    let editable: Bool
    let open: (String) -> Void
    let move: (BaseRow, String?) -> Void
    let add: (String?) -> Void
    let addColumn: () -> Void
    let removeColumn: (String) -> Void
    let trash: (String) -> Void
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var dropTarget: Int?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(groups.enumerated()), id: \.offset) { i, g in column(i, g) }
                if editable {
                    Button("New Column", systemImage: "plus", action: addColumn)
                        .buttonStyle(.bordered)
                        .padding(.top, 6)
                }
            }
            .padding(sizeClass == .compact ? 12 : 16)
        }
    }

    private func title(_ value: String?) -> String { value ?? String(localized: "No value") }

    private func column(_ i: Int, _ g: (value: String?, rows: [BaseRow])) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text(title(g.value)).font(.headline).lineLimit(1)
                    Text("\(g.rows.count)").foregroundStyle(.secondary).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if editable {
                    Button("Add Card to \(title(g.value))", systemImage: "plus") { add(g.value) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Add card")
                        #if os(iOS)
                        .frame(minWidth: 44, minHeight: 44)
                        #endif
                }
            }
            .contextMenu {
                if let v = g.value, g.rows.isEmpty, editable {
                    Button("Remove Column", systemImage: "minus.circle", role: .destructive) { removeColumn(v) }
                }
            }
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(g.rows) { card($0, in: g.value) }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(10)
        .frame(width: sizeClass == .compact ? 260 : 280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.fill.quaternary, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: dropTarget == i ? 2 : 0))
        .dropDestination(for: String.self) { paths, _ in
            guard editable else { return false }
            let rows = groups.flatMap(\.rows)
            for p in paths { if let r = rows.first(where: { $0.path == p }) { move(r, g.value) } }
            return true
        } isTargeted: { on in
            if on { dropTarget = i } else if dropTarget == i { dropTarget = nil }
        }
    }

    private func card(_ r: BaseRow, in current: String?) -> some View {
        let others = groups.map(\.value).filter { $0 != current }
        return Button { open(r.path) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(base.value(of: "file.name", row: r).description).fontWeight(.medium).lineLimit(3)
                ForEach(fields.filter { $0 != "file.name" && $0 != property }.prefix(3), id: \.self) { c in
                    let v = base.value(of: c, row: r)
                    if !v.isEmpty {
                        Text("\(base.displayName(c)): \(v.description)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .draggable(r.path)
        .contextMenu {
            Button("Open", systemImage: "doc.text") { open(r.path) }
            if editable {
                Menu("Move To", systemImage: "arrow.right") {
                    ForEach(others, id: \.self) { v in Button(title(v)) { move(r, v) } }
                }
            }
            Divider()
            Button("Move to Trash…", systemImage: "trash", role: .destructive) { trash(r.path) }
        }
        .accessibilityHint(Text("Opens the note"))
        .accessibilityActions {
            if editable {
                ForEach(others, id: \.self) { v in Button("Move to \(title(v))") { move(r, v) } }
            }
            Button("Move to Trash") { trash(r.path) }
        }
    }
}

/// Bases › New database: a name, then a folder for the entries and a base beside it.
struct NewDatabaseSheet: View {
    let folder: String
    @Environment(WindowState.self) private var window
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name).onSubmit(create)
                } footer: {
                    Text("Creates a folder for the entries and a base beside it with a table and a board.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Database")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: create).disabled(Templates.fileName(name).isEmpty) }
            }
        }
        .macOnly { $0.frame(minWidth: 380, minHeight: 200) }
    }

    private func create() {
        guard !Templates.fileName(name).isEmpty else { return }
        if let p = window.model.newDatabase(named: name, in: folder) { window.open(path: p) }
        dismiss()
    }
}
