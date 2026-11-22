import SwiftUI
import UniformTypeIdentifiers

enum ImportKind: String, Identifiable {
    case shelf, kindle, appleBooks
    var id: String { rawValue }
    var title: String {
        switch self {
        case .shelf: "Import from Goodreads or StoryGraph"
        case .kindle: "Import Kindle Highlights"
        case .appleBooks: "Import from Apple Books"
        }
    }
    var symbol: String {
        switch self {
        case .shelf: "tablecells"
        case .kindle: "highlighter"
        case .appleBooks: "book.pages"
        }
    }
    var hasHighlights: Bool { self != .shelf }
}

struct ImportSheet: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState
    @EnvironmentObject var license: LicenseManager
    @Environment(\.dismiss) private var dismiss
    let kind: ImportKind
    var initialURL: URL? = nil

    @State private var fileName = ""
    @State private var shelfItems: [ImportedBook] = []
    @State private var shelfSource: ShelfImporter.Source = .goodreads
    @State private var clips: [Clipping] = []
    @State private var appleExport: AppleBooksImporter.Export?
    @AppStorage("importAppleAllBooks") private var appleAllBooks = false
    @State private var plan: ImportPlan?
    @State private var result: ImportResult?
    @State private var error: String?
    @State private var dropTargeted = false
    @AppStorage("importTags") private var importTags = true
    @AppStorage("importReviews") private var importReviews = true
    @AppStorage("importCovers") private var fetchCovers = true

    private var remainingFree: Int? {
        license.isLicensed ? nil : max(0, LicenseManager.freeBookLimit - store.data.books.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: kind.symbol).font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(plan == nil || result != nil ? kind.title : "Import from \(kind == .kindle ? "Kindle" : kind == .appleBooks ? "Apple Books" : shelfSource.rawValue)").font(.headline)
                    if !fileName.isEmpty { Text(fileName).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
            }
            .padding(16)
            Divider()
            Group {
                if let result { done(result) }
                else if let plan { preview(plan) }
                else { intro }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer.padding(14)
        }
        .frame(width: 640, height: 600)
        .onAppear { if let initialURL, plan == nil { kind == .appleBooks ? loadApple(initialURL) : load(initialURL) } }
    }

    // MARK: Steps

    @ViewBuilder private var intro: some View {
        if kind == .appleBooks { appleIntro } else { fileIntro }
    }

    private var appleIntro: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Image(systemName: "book.pages").font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
                Text("Import books and highlights from the Books app").font(.title3.weight(.medium))
                Text("Readscape reads a copy of Books' library on this Mac. Nothing is changed in Books, and nothing leaves your Mac.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Read Apple Books Library") { loadApple(AppleBooksImporter.defaultFolder) }.buttonStyle(.borderedProminent)
                    Button("Choose Folder…") { chooseAppleFolder() }
                        .help("If macOS blocks access, choose Books' Documents folder to grant it")
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18).padding(.horizontal, 24)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 8) {
                Text("Good to know").font(.subheadline.weight(.semibold))
                step("iPhone & iPad", "Highlights made on other devices are included when iCloud is turned on for Books (Settings › Apple Account › iCloud › Books). Open Books on this Mac once so they sync.")
                step("Permission", "macOS may ask whether Readscape can access data from other apps. Allow it, or use Choose Folder… and pick ~/Library/Containers/com.apple.iBooksX/Data/Documents.")
                step("What comes in", "Reading status and progress, finish dates, genres as tags, highlights with their chapter, your notes, and highlight colors as tags (yellow is the default and isn't tagged).")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
    }

    private var fileIntro: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc").font(.system(size: 40, weight: .light)).foregroundStyle(dropTargeted ? Color.accentColor : .secondary)
                Text("Drop your export here, or choose the file").font(.title3.weight(.medium))
                Button("Choose File…") { choose() }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])).foregroundStyle(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4)))
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { load(url) } }
                }
                return true
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Where to find it").font(.subheadline.weight(.semibold))
                if kind == .shelf {
                    step("Goodreads", "My Books → Import and export (left sidebar) → Export Library. Download the .csv file when it's ready.")
                    step("StoryGraph", "Manage Account → Export StoryGraph Library → Generate export, then download the .csv file.")
                } else {
                    step("Kindle e-reader", "Connect your Kindle by USB and open its “documents” folder. The file is “My Clippings.txt”.")
                    step("Tip", "Highlights you extended are merged, and notes are attached to the highlight they belong to.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
    }

    private func step(_ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.callout.weight(.medium)).frame(width: 110, alignment: .leading)
            Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func preview(_ plan: ImportPlan) -> some View {
        let overLimit = remainingFree.map { plan.newBooks.count > $0 } ?? false
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                summary("\(plan.newBooks.count)", "new books")
                if kind != .kindle { summary("\(plan.updatedBooks.count)", "books updated") }
                summary("\(plan.annotations.count)", kind.hasHighlights ? "highlights & notes" : "notes")
                if kind == .shelf { summary("\(plan.journal.count)", "reviews") }
                if plan.duplicatesSkipped + plan.unchangedBooks > 0 { summary("\(plan.duplicatesSkipped + plan.unchangedBooks)", "already in library") }
            }
            if kind == .shelf {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Import shelves as tags", isOn: $importTags)
                    Toggle("Import reviews as journal entries", isOn: $importReviews)
                    Toggle("Download covers from Open Library (sends each book's ISBN)", isOn: $fetchCovers)
                }
                .onChange(of: importTags) { _, _ in replan() }
                .onChange(of: importReviews) { _, _ in replan() }
            }
            if kind == .appleBooks, let ex = appleExport {
                let others = ex.allBooks.count - ex.books.count
                Toggle(others == 1 ? "Also import the 1 book without highlights" : "Also import the \(others) books without highlights", isOn: $appleAllBooks)
                    .onChange(of: appleAllBooks) { _, _ in replan() }
                    .disabled(ex.allBooks.count == ex.books.count)
                if ex.orphanedHighlights > 0 {
                    Text(ex.orphanedHighlights == 1 ? "1 highlight belongs to a book no longer in your Apple Books library and was skipped." : "\(ex.orphanedHighlights) highlights belong to books no longer in your Apple Books library and were skipped.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if overLimit, let left = remainingFree {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The free version can add \(left) more book\(left == 1 ? "" : "s"). The first \(left) will be imported; unlock the lifetime license to import all \(plan.newBooks.count).")
                            .font(.callout)
                        Button("Unlock Lifetime License…") { state.upgrade("Import your whole library — no book limit.") }.controlSize(.small)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
            List {
                if !plan.newBooks.isEmpty {
                    Section("New books") {
                        ForEach(Array(plan.newBooks.enumerated()), id: \.element.id) { i, b in
                            row(b, detail: b.status.label + (kind == .kindle ? " (guessed)" : "") + (b.status == .reading && b.pageCount > 0 ? " · \(Int(b.progress * 100))%" : ""), muted: remainingFree.map { i >= $0 } ?? false,
                                count: plan.annotations.filter { $0.bookID == b.id }.count)
                        }
                    }
                }
                if !plan.updatedBooks.isEmpty {
                    Section("Books already in your library") {
                        ForEach(plan.updatedBooks, id: \.book.id) { c in row(c.book, detail: "Adds " + c.changes.joined(separator: ", "), muted: false, count: plan.annotations.filter { $0.bookID == c.book.id }.count) }
                    }
                }
                let existingWithNotes = Set(plan.annotations.map(\.bookID)).subtracting(plan.newBooks.map(\.id)).subtracting(plan.updatedBooks.map(\.book.id))
                if kind.hasHighlights, !existingWithNotes.isEmpty {
                    Section("Highlights added to books you already have") {
                        ForEach(Array(existingWithNotes), id: \.self) { id in
                            if let b = store.book(id) { row(b, detail: b.status.label, muted: false, count: plan.annotations.filter { $0.bookID == id }.count) }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(18)
    }

    private func summary(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ b: Book, detail: String, muted: Bool, count: Int) -> some View {
        HStack(spacing: 10) {
            CoverView(book: b, width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(b.title).lineLimit(1)
                Text([b.author, detail].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if count > 0 { Text("\(count) \(kind.hasHighlights ? (count == 1 ? "highlight" : "highlights") : (count == 1 ? "note" : "notes"))").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
            if muted { Text("Over free limit").font(.caption2).foregroundStyle(.secondary) }
        }
        .opacity(muted ? 0.45 : 1)
    }

    private func done(_ r: ImportResult) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle").font(.system(size: 44, weight: .light)).foregroundStyle(Palette.series[2])
            Text("Import complete").font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 4) {
                line(r.booksAdded, "book added", "books added")
                line(r.booksUpdated, "existing book updated", "existing books updated")
                line(r.annotationsAdded, kind.hasHighlights ? "highlight or note added" : "note added", kind.hasHighlights ? "highlights and notes added" : "notes added")
                line(r.journalAdded, "review added to the journal", "reviews added to the journal")
            }
            if r.booksSkippedForLimit > 0 {
                Text("\(r.booksSkippedForLimit) books weren't imported because of the free version's \(LicenseManager.freeBookLimit)-book limit. Unlock the lifetime license and import the same file again; nothing will be duplicated.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            }
            if state.coverFetch != nil {
                Label("Covers are downloading in the background.", systemImage: "photo.on.rectangle").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(30)
    }

    @ViewBuilder private func line(_ n: Int, _ one: String, _ many: String) -> some View {
        if n > 0 { Text("\(n) \(n == 1 ? one : many)") }
    }

    private var footer: some View {
        HStack {
            if plan != nil, result == nil {
                if kind == .appleBooks { Button("Reload") { loadApple(AppleBooksImporter.defaultFolder) } }
                else { Button("Choose Another File…") { choose() } }
            }
            Spacer()
            if result != nil {
                Button("Show Library") { state.selection = .library(nil); state.path = []; dismiss() }.keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if let plan {
                    Button("Import") { run(plan) }.keyboardShortcut(.defaultAction).disabled(plan.isEmpty)
                }
            }
        }
    }

    // MARK: Actions

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = kind == .shelf ? [.commaSeparatedText, .plainText] : [.plainText]
        panel.message = kind == .shelf ? "Choose your Goodreads or StoryGraph export (.csv)" : "Choose “My Clippings.txt” from your Kindle's documents folder"
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    private func load(_ url: URL) {
        error = nil
        do {
            let text = try Self.readText(url)
            fileName = url.lastPathComponent
            switch kind {
            case .shelf:
                (shelfSource, shelfItems) = try ShelfImporter.parse(text)
                if shelfItems.isEmpty { throw ImportError.unrecognized("No books found in that file.") }
            case .kindle:
                clips = try KindleImporter.parse(text)
                if clips.isEmpty { throw ImportError.unrecognized("No highlights or notes found in that file.") }
            case .appleBooks:
                loadApple(url.hasDirectoryPath ? url : url.deletingLastPathComponent()); return
            }
            replan()
        } catch {
            plan = nil
            self.error = error.localizedDescription
        }
    }

    private func chooseAppleFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = AppleBooksImporter.defaultFolder
        panel.message = "Choose Apple Books' “Documents” folder (it contains AEAnnotation and BKLibrary)"
        panel.prompt = "Use This Folder"
        if panel.runModal() == .OK, let url = panel.url { loadApple(url) }
    }

    private func loadApple(_ folder: URL) {
        error = nil
        do {
            let ex = try AppleBooksImporter.read(folder: folder)
            if ex.allBooks.isEmpty { throw ImportError.unrecognized("Your Apple Books library is empty.") }
            appleExport = ex
            fileName = "\(ex.allBooks.count) books · \(ex.clips.count) highlights and notes in Apple Books"
            replan()
        } catch {
            plan = nil
            self.error = error.localizedDescription
        }
    }

    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        for enc in [String.Encoding.utf8, .utf16, .windowsCP1252, .isoLatin1] {
            if let s = String(data: data, encoding: enc) { return s }
        }
        throw ImportError.unrecognized("Couldn't read that file as text.")
    }

    private func replan() {
        switch kind {
        case .shelf:
            plan = ImportPlanner.plan(shelf: shelfItems, source: shelfSource, into: store.data,
                                      options: .init(importTags: importTags, reviewsAsJournal: importReviews))
        case .kindle:
            plan = ImportPlanner.plan(kindle: clips, into: store.data)
        case .appleBooks:
            if let ex = appleExport { plan = ImportPlanner.plan(appleBooks: ex, includeBooksWithoutHighlights: appleAllBooks, into: store.data) }
        }
    }

    private func run(_ plan: ImportPlan) {
        var data = store.data
        let r = ImportPlanner.apply(plan, to: &data, maxNewBooks: remainingFree)
        store.data = data
        store.saveNow()
        if kind == .shelf, fetchCovers {
            let added = Set(data.books.suffix(r.booksAdded).map(\.id))
            state.fetchCovers(for: data.books.filter { added.contains($0.id) && !$0.isbn.isEmpty && $0.coverFile == nil })
        }
        result = r
    }
}
