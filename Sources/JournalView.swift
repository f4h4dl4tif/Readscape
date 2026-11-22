import SwiftUI
import UniformTypeIdentifiers

struct JournalView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var selection: UUID?
    @State private var search = ""

    private var entries: [JournalEntry] {
        store.data.journal
            .filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.body.localizedCaseInsensitiveContains(search) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        HSplitView {
            List(selection: $selection) {
                ForEach(groupedByMonth, id: \.0) { month, items in
                    Section(month) {
                        ForEach(items) { e in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(e.title.isEmpty ? "Untitled" : e.title).font(.callout.weight(.medium)).lineLimit(1)
                                Text(e.body.isEmpty ? "No text" : e.body).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                Text(e.date.short).font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 3)
                            .tag(e.id)
                            .contextMenu { Button("Delete", role: .destructive) { store.delete(journalID: e.id) } }
                        }
                    }
                }
            }
            .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)

            Group {
                if let id = selection, store.data.journal.contains(where: { $0.id == id }) {
                    JournalEditor(entryID: id).id(id)
                } else {
                    EmptyState(symbol: "book.closed", title: store.data.journal.isEmpty ? "Start your reading journal" : "Select an entry",
                               message: "Write about what you're reading, how ideas connect, and what you want to explore next.",
                               actions: AnyView(Button("New Entry") { newEntry() }.buttonStyle(.borderedProminent)))
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Journal")
        .searchable(text: $search, prompt: "Search journal")
        .toolbar { Button { newEntry() } label: { Label("New Entry", systemImage: "square.and.pencil") } }
        .onAppear { if selection == nil { selection = entries.first?.id } }
    }

    private var groupedByMonth: [(String, [JournalEntry])] {
        let f = DateFormatter(); f.dateFormat = "LLLL yyyy"
        var order: [String] = []; var map: [String: [JournalEntry]] = [:]
        for e in entries {
            let k = f.string(from: e.date)
            if map[k] == nil { order.append(k) }
            map[k, default: []].append(e)
        }
        return order.map { ($0, map[$0]!) }
    }

    private func newEntry() {
        let e = JournalEntry(title: "")
        store.upsert(e)
        search = ""
        selection = e.id
    }
}

struct JournalEditor: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState
    let entryID: UUID
    @State private var picking = false

    private var binding: Binding<JournalEntry> {
        Binding(get: { store.data.journal.first { $0.id == entryID } ?? JournalEntry() },
                set: { store.upsert($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                DatePicker("", selection: binding.date, displayedComponents: .date).labelsHidden().fixedSize()
                Spacer()
                Text("\(binding.wrappedValue.body.split { $0.isWhitespace }.count) words").font(.caption).foregroundStyle(.secondary)
            }
            TextField("Title", text: binding.title).font(.system(size: 24, weight: .semibold, design: .serif)).textFieldStyle(.plain)
            HStack(spacing: 8) {
                ForEach(binding.wrappedValue.bookIDs, id: \.self) { id in
                    if let b = store.book(id) {
                        HStack(spacing: 6) {
                            CoverView(book: b, width: 14)
                            Button(b.title) { state.open(book: id) }.buttonStyle(.plain).lineLimit(1)
                            Button { binding.wrappedValue.bookIDs.removeAll { $0 == id } } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                                .buttonStyle(.plain)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                    }
                }
                Button { picking = true } label: { Label("Link Book", systemImage: "plus") }.controlSize(.small)
                    .popover(isPresented: $picking) { BookPicker(exclude: binding.wrappedValue.bookIDs) { binding.wrappedValue.bookIDs.append($0); picking = false } }
            }
            TextEditor(text: binding.body)
                .font(.system(size: 15, design: .serif))
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
        }
        .padding(28)
    }
}

struct BookPicker: View {
    @EnvironmentObject var store: LibraryStore
    let exclude: [UUID]
    let pick: (UUID) -> Void
    @State private var search = ""
    var body: some View {
        VStack(spacing: 8) {
            TextField("Search books", text: $search).textFieldStyle(.roundedBorder)
            List(store.data.books.filter { !exclude.contains($0.id) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }) { b in
                Button { pick(b.id) } label: {
                    HStack { CoverView(book: b, width: 18); Text(b.title).lineLimit(1); Spacer() }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .padding(10)
        .frame(width: 300, height: 340)
    }
}

// MARK: - All annotations

struct AnnotationsView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState
    @State private var search = ""
    @State private var kind: AnnotationKind?
    @State private var editing: Annotation?

    private var list: [Annotation] {
        store.data.annotations
            .filter { kind == nil || $0.kind == kind }
            .filter { a in
                search.isEmpty || a.quote.localizedCaseInsensitiveContains(search) || a.comment.localizedCaseInsensitiveContains(search)
                    || a.tags.contains { $0.localizedCaseInsensitiveContains(search) }
                    || (store.book(a.bookID)?.title.localizedCaseInsensitiveContains(search) ?? false)
            }
            .sorted { $0.created > $1.created }
    }

    var body: some View {
        Group {
            if store.data.annotations.isEmpty {
                EmptyState(symbol: "highlighter", title: "No annotations yet", message: "Open a book and choose Annotate to save highlights, notes, questions and ideas.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(list) { a in
                            AnnotationCard(annotation: a)
                                .onTapGesture(count: 2) { editing = a }
                                .contextMenu {
                                    Button("Open Book") { state.open(book: a.bookID) }
                                    Button("Edit…") { editing = a }
                                    Button("Delete", role: .destructive) { store.delete(annotationID: a.id) }
                                }
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 820)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Annotations")
        .navigationSubtitle("\(list.count) shown")
        .searchable(text: $search, prompt: "Search passages, notes, tags or books")
        .toolbar {
            Picker("Type", selection: $kind) {
                Text("All").tag(AnnotationKind?.none)
                ForEach(AnnotationKind.allCases) { Text($0.label).tag(AnnotationKind?.some($0)) }
            }
            .pickerStyle(.segmented)
            Button { exportMarkdown() } label: { Label("Export Markdown", systemImage: "square.and.arrow.up") }
                .help("Export annotations as Markdown (for Obsidian, notes apps, or papers)")
        }
        .sheet(item: $editing) { AnnotationEditor(annotation: $0) }
    }

    private func exportMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Readscape Annotations.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var md = "# Reading Annotations\n\n"
        let byBook = Dictionary(grouping: list, by: \.bookID)
        for b in store.data.books where byBook[b.id] != nil {
            md += "## \(b.title)\n*\(b.author)*\n\n"
            for a in byBook[b.id]!.sorted(by: { ($0.page ?? 0) < ($1.page ?? 0) }) {
                if !a.quote.isEmpty { md += "> \(a.quote.replacingOccurrences(of: "\n", with: "\n> "))\n" }
                if !a.comment.isEmpty { md += "\n\(a.comment)\n" }
                let meta = [a.page.map { "p. \($0)" }, a.kind.label] + a.tags.map { "#\($0)" }
                md += "\n<sub>\(meta.compactMap { $0 }.joined(separator: " · "))</sub>\n\n---\n\n"
            }
        }
        do { try md.write(to: url, atomically: true, encoding: .utf8) } catch { BackupPanels.alert("Export failed", error.localizedDescription) }
    }
}
