import SwiftUI

enum LibraryFilter: Hashable {
    case status(ReadingStatus?)
    case tag(String)
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent = "Recently Added", title = "Title", author = "Author", progress = "Progress", rating = "Rating"
    var id: String { rawValue }
}

struct LibraryView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState
    let filter: LibraryFilter
    @State private var search = ""
    @AppStorage("librarySort") private var sort: LibrarySort = .recent
    @AppStorage("libraryGrid") private var grid = true
    @State private var editing: Book?

    private var title: String {
        switch filter {
        case .status(let s): s?.label ?? "All Books"
        case .tag(let t): "#\(t)"
        }
    }

    private var books: [Book] {
        var list = store.data.books
        switch filter {
        case .status(let s): if let s { list = list.filter { $0.status == s } }
        case .tag(let t): list = list.filter { $0.tags.contains(t) }
        }
        if !search.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.author.localizedCaseInsensitiveContains(search) || $0.tags.contains { $0.localizedCaseInsensitiveContains(search) } }
        }
        switch sort {
        case .recent: list.sort { $0.dateAdded > $1.dateAdded }
        case .title: list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .author: list.sort { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
        case .progress: list.sort { $0.progress > $1.progress }
        case .rating: list.sort { $0.rating > $1.rating }
        }
        return list
    }

    var body: some View {
        Group {
            if store.data.books.isEmpty {
                EmptyState(symbol: "books.vertical", title: "Your library is empty",
                           message: "Add the books you're reading, want to read, or have finished. Bring your history from Goodreads, StoryGraph, Kindle or Apple Books, or load a sample library to explore first.",
                           actions: AnyView(HStack {
                               Button("Add a Book") { state.requestAddBook() }.buttonStyle(.borderedProminent)
                               importMenu.fixedSize()
                               Button("Load Sample Library") { store.data = SampleData.make() }
                           }))
            } else if books.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "No matches", message: "Try a different search or filter.")
            } else if grid {
                ScrollView {
                    if case .status(nil) = filter, search.isEmpty { currentlyReading }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 170), spacing: 22, alignment: .top)], spacing: 26) {
                        ForEach(books) { b in
                            NavigationLink(value: b.id) { BookTile(book: b) }
                                .buttonStyle(.plain)
                                .contextMenu { menu(for: b) }
                        }
                    }
                    .padding(24)
                }
            } else {
                Table(books) {
                    TableColumn("Title") { b in
                        HStack { CoverView(book: b, width: 22); Text(b.title).lineLimit(1) }
                    }
                    TableColumn("Author", value: \.author)
                    TableColumn("Status") { b in Label(b.status.label, systemImage: b.status.symbol).foregroundStyle(b.status.color).labelStyle(.titleAndIcon) }
                        .width(120)
                    TableColumn("Progress") { b in HStack { ProgressBar(value: b.progress, color: b.status.color); Text("\(Int(b.progress * 100))%").monospacedDigit().font(.caption) } }
                        .width(140)
                    TableColumn("Rating") { b in Text(b.rating > 0 ? String(repeating: "★", count: b.rating) : "—").foregroundStyle(.orange) }
                        .width(80)
                }
                .contextMenu(forSelectionType: Book.ID.self) { ids in
                    if let id = ids.first, let b = store.book(id) { menu(for: b) }
                } primaryAction: { ids in
                    if let id = ids.first { state.path = [id] }
                }
            }
        }
        .navigationTitle(title)
        .navigationSubtitle("\(books.count) books" + (state.coverFetch.map { " · downloading covers \($0.done)/\($0.total)" } ?? ""))
        .searchable(text: $search, prompt: "Title, author or tag")
        .toolbar {
            ToolbarItemGroup {
                Picker("View", selection: $grid) {
                    Image(systemName: "square.grid.2x2").tag(true)
                    Image(systemName: "list.bullet").tag(false)
                }
                .pickerStyle(.segmented)
                Menu {
                    Picker("Sort By", selection: $sort) { ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) } }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                importMenu
                Button { state.requestAddBook() } label: { Label("Add Book", systemImage: "plus") }
                    .help("Add Book (⌘N)")
            }
        }
        .sheet(item: $editing) { BookEditor(book: $0) }
    }

    private var importMenu: some View {
        Menu {
            Button("From Goodreads or StoryGraph…") { state.importKind = .shelf }
            Button("Kindle Highlights…") { state.importKind = .kindle }
            Button("Apple Books…") { state.importKind = .appleBooks }
        } label: { Label("Import", systemImage: "square.and.arrow.down") }
        .help("Import books and highlights")
    }

    @ViewBuilder private var currentlyReading: some View {
        let reading = store.data.books.filter { $0.status == .reading }
        if !reading.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Currently Reading").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(reading) { b in
                            NavigationLink(value: b.id) {
                                HStack(spacing: 14) {
                                    CoverView(book: b, width: 54)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(b.title).font(.callout.weight(.semibold)).lineLimit(2)
                                        Text(b.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        ProgressBar(value: b.progress)
                                        Text("Page \(b.currentPage) of \(b.pageCount)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                                    }
                                    .frame(width: 170, alignment: .leading)
                                }
                                .padding(12)
                                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding([.horizontal, .top], 24)
        }
    }

    @ViewBuilder private func menu(for b: Book) -> some View {
        Button("Edit…") { editing = b }
        Menu("Status") {
            ForEach(ReadingStatus.allCases) { s in
                Button(s.label) { var c = b; c.status = s; store.update(c) }
            }
        }
        Divider()
        Button("Delete", role: .destructive) { confirmDelete(b) }
    }

    private func confirmDelete(_ b: Book) {
        let a = NSAlert()
        a.messageText = "Delete “\(b.title)”?"
        a.informativeText = "Its reading sessions, annotations and connections are deleted too. This can't be undone."
        a.addButton(withTitle: "Delete"); a.addButton(withTitle: "Cancel")
        a.buttons[0].hasDestructiveAction = true
        if a.runModal() == .alertFirstButtonReturn { store.delete(bookID: b.id) }
    }
}

struct BookTile: View {
    let book: Book
    @State private var hover = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverView(book: book, width: 140)
                .scaleEffect(hover ? 1.03 : 1)
                .animation(.spring(duration: 0.25), value: hover)
            Text(book.title).font(.callout.weight(.medium)).lineLimit(2)
            Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if book.status == .reading {
                ProgressBar(value: book.progress).frame(width: 140)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: book.status.symbol).foregroundStyle(book.status.color)
                    Text(book.status.label).foregroundStyle(.secondary)
                    if book.rating > 0 { Spacer(); Text(String(repeating: "★", count: book.rating)).foregroundStyle(.orange) }
                }
                .font(.caption2)
                .frame(width: 140)
            }
        }
        .frame(width: 140)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}
