import SwiftUI

struct BookDetailView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState
    let bookID: UUID

    enum Tab: String, CaseIterable, Identifiable { case annotations = "Annotations", sessions = "Sessions", connections = "Connections", journal = "Journal"; var id: String { rawValue } }
    @State private var tab: Tab = .annotations
    @State private var editingBook: Book?
    @State private var editingAnnotation: Annotation?
    @State private var logging = false
    @State private var connecting = false

    var body: some View {
        if let book = store.book(bookID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header(book)
                    Picker("", selection: $tab) { ForEach(Tab.allCases) { t in Text(label(t)).tag(t) } }
                        .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 520)
                    switch tab {
                    case .annotations: annotations(book)
                    case .sessions: sessions(book)
                    case .connections: connections(book)
                    case .journal: journal(book)
                    }
                }
                .padding(28)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(book.title)
            .toolbar {
                ToolbarItemGroup {
                    Button { logging = true } label: { Label("Log Reading", systemImage: "plus.circle") }
                    Button { editingAnnotation = Annotation(bookID: book.id, page: book.currentPage > 0 ? book.currentPage : nil) } label: { Label("Annotate", systemImage: "highlighter") }
                    Button { connecting = true } label: { Label("Connect", systemImage: "link") }
                    Button { editingBook = book } label: { Label("Edit Details", systemImage: "info.circle") }
                }
            }
            .sheet(item: $editingBook) { BookEditor(book: $0) }
            .sheet(item: $editingAnnotation) { AnnotationEditor(annotation: $0) }
            .sheet(isPresented: $logging) { LogSessionSheet(book: book) }
            .sheet(isPresented: $connecting) { ConnectSheet(source: book) }
        } else {
            EmptyState(symbol: "book", title: "Book not found", message: "It may have been deleted.")
        }
    }

    private func label(_ t: Tab) -> String {
        let n: Int
        switch t {
        case .annotations: n = store.annotations(for: bookID).count
        case .sessions: n = store.sessions(for: bookID).count
        case .connections: n = store.links(for: bookID).count
        case .journal: n = store.journal(for: bookID).count
        }
        return n > 0 ? "\(t.rawValue) (\(n))" : t.rawValue
    }

    // MARK: Header

    private func header(_ book: Book) -> some View {
        HStack(alignment: .top, spacing: 26) {
            CoverView(book: book, width: 150)
            VStack(alignment: .leading, spacing: 10) {
                Text(book.title).font(.system(size: 28, weight: .bold, design: .serif)).textSelection(.enabled)
                Text(book.author).font(.title3).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Picker("Status", selection: Binding(get: { book.status }, set: { s in var b = book; b.status = s; store.update(b) })) {
                        ForEach(ReadingStatus.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    StarRating(rating: Binding(get: { book.rating }, set: { r in var b = book; b.rating = r; store.update(b) }), size: 16)
                }
                if book.pageCount > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressBar(value: book.progress, color: book.status.color).frame(maxWidth: 360)
                        Text("Page \(book.currentPage) of \(book.pageCount) · \(Int(book.progress * 100))%\(pace(book))")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                metaLine(book)
                if !book.tags.isEmpty {
                    FlowLayout { ForEach(book.tags, id: \.self) { t in Button { state.selection = .tag(t) } label: { TagChip(text: t) }.buttonStyle(.plain) } }
                }
                if !book.summary.isEmpty {
                    Text(book.summary).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 4)
                }
            }
        }
    }

    private func metaLine(_ b: Book) -> some View {
        let parts: [String] = [
            b.year.map { "Published \($0)" },
            b.publisher.isEmpty ? nil : b.publisher,
            b.dateStarted.map { "Started \($0.short)" },
            b.dateFinished.map { "Finished \($0.short)" },
        ].compactMap { $0 }
        return Text(parts.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
    }

    private func pace(_ b: Book) -> String {
        let s = store.sessions(for: b.id)
        let pages = s.reduce(0) { $0 + $1.pagesRead }
        let minutes = s.reduce(0) { $0 + $1.minutes }
        guard b.status == .reading, pages > 0, minutes > 0, b.pageCount > b.currentPage else { return "" }
        let left = Double(b.pageCount - b.currentPage) * Double(minutes) / Double(pages)
        return " · about \(left >= 90 ? "\(Int((left / 60).rounded())) h" : "\(Int(left)) min") left"
    }

    // MARK: Tabs

    @ViewBuilder private func annotations(_ book: Book) -> some View {
        let list = store.annotations(for: book.id)
        if list.isEmpty {
            hint("No annotations yet", "Capture highlights, notes, questions and ideas as you read.", "Add Annotation") {
                editingAnnotation = Annotation(bookID: book.id)
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(list) { a in
                    AnnotationCard(annotation: a, showBook: false)
                        .onTapGesture(count: 2) { editingAnnotation = a }
                        .contextMenu {
                            Button("Edit…") { editingAnnotation = a }
                            Button("Delete", role: .destructive) { store.delete(annotationID: a.id) }
                        }
                }
            }
        }
    }

    @ViewBuilder private func sessions(_ book: Book) -> some View {
        let list = store.sessions(for: book.id)
        if list.isEmpty {
            hint("No reading sessions", "Log each sitting to track progress, pace and streaks.", "Log Reading") { logging = true }
        } else {
            VStack(spacing: 0) {
                ForEach(list) { s in
                    HStack {
                        Text(s.date.short).frame(width: 110, alignment: .leading)
                        Text(s.pagesRead > 0 ? "pp. \(s.startPage)–\(s.endPage)" : "—").frame(width: 110, alignment: .leading).monospacedDigit()
                        Text(s.pagesRead > 0 ? "\(s.pagesRead) pages" : "").foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                        Text(s.minutes > 0 ? "\(s.minutes) min" : "").foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                        Text(s.note).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button { store.delete(sessionID: s.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help("Delete session")
                    }
                    .font(.callout)
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder private func connections(_ book: Book) -> some View {
        let links = store.links(for: book.id)
        if links.isEmpty {
            hint("Not connected yet", "Link books that build on, contradict or inspire each other. Connections appear in the reading graph.", "Connect a Book") { connecting = true }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(links) { l in
                    let otherID = l.from == book.id ? l.to : l.from
                    if let other = store.book(otherID) {
                        HStack(spacing: 12) {
                            CoverView(book: other, width: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.from == book.id ? "This book \(l.kind.label.lowercased())" : "\(l.kind.label) this book")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text(other.title).font(.callout.weight(.medium))
                                if !l.note.isEmpty { Text(l.note).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Button("Open") { state.path.append(other.id) }
                            Button { store.delete(linkID: l.id) } label: { Image(systemName: "link.badge.plus").symbolVariant(.slash) }
                                .buttonStyle(.borderless).help("Remove connection")
                        }
                        .padding(10)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                Button("Connect Another Book…") { connecting = true }
            }
        }
    }

    @ViewBuilder private func journal(_ book: Book) -> some View {
        let entries = store.journal(for: book.id)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(entries) { e in
                VStack(alignment: .leading, spacing: 4) {
                    Text(e.date.short).font(.caption).foregroundStyle(.secondary)
                    Text(e.title).font(.headline)
                    Text(e.body).foregroundStyle(.secondary).lineLimit(4)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
            }
            Button("New Journal Entry About This Book") {
                store.upsert(JournalEntry(title: "Thoughts on \(book.title)", bookIDs: [book.id]))
                state.selection = .journal
            }
        }
    }

    private func hint(_ title: String, _ text: String, _ action: String, _ run: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).foregroundStyle(.secondary)
            Button(action, action: run).padding(.top, 4)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Annotation card & editor

struct AnnotationCard: View {
    @EnvironmentObject var store: LibraryStore
    let annotation: Annotation
    var showBook = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: annotation.kind.symbol).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 6) {
                if !annotation.quote.isEmpty {
                    Text("“\(annotation.quote)”").font(.system(.body, design: .serif)).italic()
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(Palette.series[3]).frame(width: 3) }
                }
                if !annotation.comment.isEmpty { Text(annotation.comment) }
                HStack(spacing: 8) {
                    if showBook, let b = store.book(annotation.bookID) { Text(b.title).fontWeight(.medium) }
                    if let ch = annotation.chapter { Text(ch).lineLimit(1) }
                    if let p = annotation.page { Text("p. \(p)") } else if let l = annotation.location { Text("loc. \(l)") }
                    Text(annotation.created.short)
                    ForEach(annotation.tags, id: \.self) { Text("#\($0)") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct AnnotationEditor: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State var annotation: Annotation

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Type", selection: $annotation.kind) {
                    ForEach(AnnotationKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                TextField("Page", value: $annotation.page, format: .number)
                Section("Passage (optional)") { TextEditor(text: $annotation.quote).font(.system(.body, design: .serif)).frame(minHeight: 70) }
                Section("Your thoughts") { TextEditor(text: $annotation.comment).frame(minHeight: 90) }
                Section("Tags") { TagEditor(tags: $annotation.tags, suggestions: store.allTags) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { store.upsert(annotation); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(annotation.quote.isEmpty && annotation.comment.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 520, height: 560)
    }
}

// MARK: - Log session

struct LogSessionSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let book: Book
    @State private var date = Date()
    @State private var endPage: Int
    @State private var minutes = 30
    @State private var note = ""

    init(book: Book) {
        self.book = book
        _endPage = State(initialValue: book.currentPage)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                LabeledContent("Book", value: book.title)
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                LabeledContent("Pages") {
                    HStack {
                        Text("from \(book.currentPage) to").foregroundStyle(.secondary)
                        TextField("", value: $endPage, format: .number).frame(width: 70)
                        if book.pageCount > 0 { Text("of \(book.pageCount)").foregroundStyle(.secondary) }
                    }
                }
                Stepper("Minutes: \(minutes)", value: $minutes, in: 0...600, step: 5)
                TextField("Note (optional)", text: $note)
                if book.pageCount > 0, endPage >= book.pageCount {
                    Label("This marks the book as finished.", systemImage: "checkmark.seal").foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Log") {
                    let end = book.pageCount > 0 ? min(endPage, book.pageCount) : endPage
                    store.log(ReadingSession(bookID: book.id, date: date, startPage: book.currentPage, endPage: max(book.currentPage, end), minutes: minutes, note: note))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(endPage < book.currentPage && minutes == 0)
            }
            .padding(14)
        }
        .frame(width: 440, height: 340)
    }
}

// MARK: - Connect books

struct ConnectSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let source: Book
    @State private var target: UUID?
    @State private var kind: LinkKind = .related
    @State private var note = ""
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Connect “\(source.title)”").font(.headline)
                Picker("Relationship", selection: $kind) { ForEach(LinkKind.allCases) { Text($0.label).tag($0) } }
                TextField("Search books", text: $search).textFieldStyle(.roundedBorder)
            }
            .padding(16)
            List(store.data.books.filter { $0.id != source.id && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.author.localizedCaseInsensitiveContains(search)) }, selection: $target) { b in
                HStack { CoverView(book: b, width: 24); VStack(alignment: .leading) { Text(b.title); Text(b.author).font(.caption).foregroundStyle(.secondary) } }
                    .tag(b.id)
            }
            TextField("Why are they connected? (optional)", text: $note).textFieldStyle(.roundedBorder).padding(16)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Connect") {
                    if let target { store.connect(source.id, target, kind: kind, note: note) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction).disabled(target == nil)
            }
            .padding(14)
        }
        .frame(width: 460, height: 560)
    }
}
