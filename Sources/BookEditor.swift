import SwiftUI
import UniformTypeIdentifiers

struct BookEditor: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var book: Book
    @State private var yearText: String
    @State private var pendingCover: Data?
    @State private var query = ""
    @State private var results: [OpenLibraryResult] = []
    @State private var searching = false
    @State private var searchError: String?
    private let isNew: Bool

    init(book: Book?) {
        isNew = book == nil
        let b = book ?? Book(title: "", author: "")
        _book = State(initialValue: b)
        _yearText = State(initialValue: b.year.map(String.init) ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "Add Book" : "Edit Book").font(.headline).padding(.top, 16)
            HStack(alignment: .top, spacing: 0) {
                if isNew { lookup.frame(width: 300); Divider() }
                form
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add to Library" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(book.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
        }
        .frame(width: isNew ? 820 : 520, height: 600)
    }

    // MARK: Open Library lookup

    private var lookup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find a book").font(.subheadline.weight(.semibold))
            HStack {
                TextField("Title, author or ISBN", text: $query).textFieldStyle(.roundedBorder).onSubmit(runSearch)
                Button { runSearch() } label: { Image(systemName: "magnifyingglass") }.disabled(query.isEmpty)
            }
            Text("Looks up details and covers on Open Library. Only your search text is sent.")
                .font(.caption2).foregroundStyle(.secondary)
            if searching { ProgressView().frame(maxWidth: .infinity).padding() }
            if let searchError { Text(searchError).font(.caption).foregroundStyle(.red) }
            List(results) { r in
                Button { apply(r) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        AsyncImage(url: r.coverID.map { URL(string: "https://covers.openlibrary.org/b/id/\($0)-S.jpg")! }) { img in
                            img.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: { Rectangle().fill(.quaternary) }
                        .frame(width: 32, height: 48).clipShape(RoundedRectangle(cornerRadius: 3))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.callout.weight(.medium)).lineLimit(2)
                            Text(r.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text([r.year.map(String.init), r.pages.map { "\($0) pages" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .padding(16)
    }

    private func runSearch() {
        searching = true; searchError = nil
        Task {
            do { results = try await OpenLibrary.search(query) }
            catch { searchError = "Search failed. Check your connection, or enter the details by hand." }
            searching = false
        }
    }

    private func apply(_ r: OpenLibraryResult) {
        book.title = r.title
        book.author = r.author
        if let p = r.pages { book.pageCount = p }
        if let y = r.year { yearText = String(y) }
        if let i = r.isbn { book.isbn = i }
        for s in r.subjects where !book.tags.contains(s) && s.count < 24 { book.tags.append(s) }
        if let url = r.coverURL {
            Task { pendingCover = await OpenLibrary.cover(url) }
        }
    }

    // MARK: Fields

    private var form: some View {
        Form {
            HStack(alignment: .top, spacing: 16) {
                coverWell
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title", text: $book.title)
                    TextField("Author", text: $book.author)
                    Picker("Status", selection: $book.status) {
                        ForEach(ReadingStatus.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    LabeledContent("Rating") { StarRating(rating: $book.rating) }
                }
            }
            Section {
                TextField("Pages", value: $book.pageCount, format: .number)
                TextField("Current page", value: $book.currentPage, format: .number)
                TextField("Year", text: $yearText)
                TextField("Publisher", text: $book.publisher)
                TextField("ISBN", text: $book.isbn)
            }
            Section("Tags") { TagEditor(tags: $book.tags, suggestions: store.allTags) }
            Section("Summary") {
                TextEditor(text: $book.summary).frame(minHeight: 60).font(.body)
            }
        }
        .formStyle(.grouped)
    }

    private var coverWell: some View {
        let preview: Book = {
            var b = book
            if pendingCover != nil { b.coverFile = nil }
            return b
        }()
        return VStack(spacing: 6) {
            Group {
                if let data = pendingCover, let img = NSImage(data: data) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).frame(width: 90, height: 135).clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    CoverView(book: preview, width: 90)
                }
            }
            .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers in
                guard let p = providers.first else { return false }
                p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data { DispatchQueue.main.async { pendingCover = data } }
                }
                return true
            }
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                if panel.runModal() == .OK, let url = panel.url { pendingCover = try? Data(contentsOf: url) }
            }
            .controlSize(.small)
        }
        .help("Drop an image here or choose one")
    }

    private func save() {
        book.title = book.title.trimmingCharacters(in: .whitespaces)
        book.year = Int(yearText)
        book.currentPage = max(0, book.pageCount > 0 ? min(book.currentPage, book.pageCount) : book.currentPage)
        if isNew {
            if book.status == .reading { book.dateStarted = Date() }
            if book.status == .finished { book.dateFinished = Date(); book.currentPage = book.pageCount }
            store.add(book)
        } else {
            store.update(book)
        }
        if let pendingCover { store.setCover(pendingCover, for: book.id) }
        dismiss()
    }
}
