import Foundation

/// Turns parsed records into concrete changes against the current library: which books are new,
/// which existing books get filled in, and which annotations/journal entries are added.
/// Re-importing the same file is safe — matches and duplicates are detected.
struct ImportPlan {
    struct BookChange { var book: Book; var changes: [String] }
    var newBooks: [Book] = []
    var updatedBooks: [BookChange] = []
    var annotations: [Annotation] = []
    var journal: [JournalEntry] = []
    var duplicatesSkipped = 0
    var unchangedBooks = 0
    var isEmpty: Bool { newBooks.isEmpty && updatedBooks.isEmpty && annotations.isEmpty && journal.isEmpty }
}

struct ImportResult {
    var booksAdded = 0
    var booksUpdated = 0
    var annotationsAdded = 0
    var journalAdded = 0
    var booksSkippedForLimit = 0
    var annotationsSkippedForLimit = 0
}

enum ImportPlanner {
    // MARK: Matching

    static func titleKey(_ title: String) -> String {
        var t = title.lowercased().trimmingCharacters(in: .whitespaces)
        if let r = t.range(of: ":") { t = String(t[..<r.lowerBound]) }          // drop subtitle
        if let r = t.range(of: " (") { t = String(t[..<r.lowerBound]) }         // drop "(Series, #1)"
        for article in ["the ", "a ", "an "] where t.hasPrefix(article) { t = String(t.dropFirst(article.count)); break }
        t = t.replacingOccurrences(of: "&", with: "and")
        let kept = t.folding(options: .diacriticInsensitive, locale: nil).unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(kept))
    }

    static func authorKey(_ author: String) -> String {
        let first = author.split(separator: ",").first.map(String.init) ?? author
        let last = first.split(separator: " ").last.map(String.init) ?? first
        return String(String.UnicodeScalarView(last.lowercased().unicodeScalars.filter { CharacterSet.letters.contains($0) }))
    }

    struct Index {
        var byISBN: [String: UUID] = [:]
        var byTitle: [String: [(UUID, String)]] = [:]   // title key -> (id, author key)

        init(_ books: [Book]) { books.forEach { add($0) } }

        mutating func add(_ b: Book) {
            if !b.isbn.isEmpty { byISBN[b.isbn] = b.id }
            byTitle[ImportPlanner.titleKey(b.title), default: []].append((b.id, ImportPlanner.authorKey(b.author)))
        }

        func match(title: String, author: String, isbn: String = "") -> UUID? {
            if !isbn.isEmpty, let id = byISBN[isbn] { return id }
            guard let candidates = byTitle[ImportPlanner.titleKey(title)] else { return nil }
            let a = ImportPlanner.authorKey(author)
            return candidates.first { a.isEmpty || $0.1.isEmpty || $0.1 == a }?.0
        }
    }

    // MARK: Goodreads / StoryGraph

    struct ShelfOptions {
        var importTags = true
        var reviewsAsJournal = true
    }

    static func plan(shelf items: [ImportedBook], source: ShelfImporter.Source, into data: LibraryData, options: ShelfOptions) -> ImportPlan {
        var plan = ImportPlan()
        var index = Index(data.books)
        var books = Dictionary(uniqueKeysWithValues: data.books.map { ($0.id, $0) })
        var pendingNew: [UUID: Int] = [:]   // id -> index in plan.newBooks

        for item in items {
            let targetID: UUID
            if let id = index.match(title: item.title, author: item.author, isbn: item.isbn) {
                targetID = id
                if pendingNew[id] != nil { plan.duplicatesSkipped += 1; continue }   // listed twice in the file
                guard var b = books[id] else { continue }
                var changes: [String] = []
                if b.rating == 0, item.rating > 0 { b.rating = item.rating; changes.append("rating") }
                if b.pageCount == 0, item.pages > 0 { b.pageCount = item.pages; changes.append("pages") }
                if b.isbn.isEmpty, !item.isbn.isEmpty { b.isbn = item.isbn; changes.append("ISBN") }
                if b.year == nil, let y = item.year { b.year = y; changes.append("year") }
                if b.publisher.isEmpty, !item.publisher.isEmpty { b.publisher = item.publisher; changes.append("publisher") }
                if rank(item.status) > rank(b.status) {
                    b.status = item.status; changes.append("status → \(item.status.label)")
                    if item.status == .finished { b.currentPage = max(b.currentPage, b.pageCount) }
                }
                if b.status == .finished, b.dateFinished == nil, let d = item.dateRead { b.dateFinished = d; changes.append("date read") }
                if b.status == .reading, let p = item.progress, b.pageCount > 0, Int(p * Double(b.pageCount)) > b.currentPage {
                    b.currentPage = Int(p * Double(b.pageCount)); changes.append("progress")
                }
                if options.importTags {
                    let newTags = item.tags.filter { !b.tags.contains($0) }
                    if !newTags.isEmpty { b.tags += newTags; changes.append("tags") }
                }
                if changes.isEmpty { plan.unchangedBooks += 1 } else {
                    books[id] = b
                    if let i = plan.updatedBooks.firstIndex(where: { $0.book.id == id }) { plan.updatedBooks[i] = .init(book: b, changes: plan.updatedBooks[i].changes + changes) }
                    else { plan.updatedBooks.append(.init(book: b, changes: changes)) }
                }
            } else {
                var b = Book(title: item.title, author: item.author)
                b.isbn = item.isbn
                b.rating = item.rating
                b.pageCount = item.pages
                b.year = item.year
                b.publisher = item.publisher
                b.status = item.status
                b.tags = options.importTags ? item.tags : []
                b.dateAdded = item.dateAdded ?? Date()
                if item.status == .finished {
                    b.dateFinished = item.dateRead
                    b.currentPage = item.pages
                }
                if item.status == .reading {
                    b.dateStarted = item.dateAdded
                    if let p = item.progress, item.pages > 0 { b.currentPage = Int(p * Double(item.pages)) }
                }
                targetID = b.id
                index.add(b)
                books[b.id] = b
                pendingNew[b.id] = plan.newBooks.count
                plan.newBooks.append(b)
            }

            if options.reviewsAsJournal, !item.review.isEmpty {
                let title = "Review: \(item.title)"
                if data.journal.contains(where: { $0.title == title && $0.bookIDs.contains(targetID) }) { plan.duplicatesSkipped += 1 }
                else { plan.journal.append(JournalEntry(date: item.dateRead ?? item.dateAdded ?? Date(), title: title, body: item.review, bookIDs: [targetID])) }
            }
            if !item.privateNotes.isEmpty {
                let existing = data.annotations.contains { $0.bookID == targetID && $0.comment == item.privateNotes }
                if existing { plan.duplicatesSkipped += 1 }
                else { plan.annotations.append(Annotation(bookID: targetID, kind: .note, comment: item.privateNotes, tags: [source.rawValue.lowercased()], created: item.dateRead ?? item.dateAdded ?? Date())) }
            }
        }
        return plan
    }

    private static func rank(_ s: ReadingStatus) -> Int {
        switch s { case .wantToRead: 0; case .abandoned: 1; case .reading: 2; case .finished: 3 }
    }

    // MARK: Highlights (Kindle, Apple Books)

    static func plan(kindle clips: [Clipping], into data: LibraryData, now: Date = Date()) -> ImportPlan {
        plan(highlights: clips, sourceTag: "kindle", into: data, now: now)
    }

    /// Apple Books gives real book metadata, so books are planned first (status, progress, dates, genre),
    /// then highlights are attached to them.
    static func plan(appleBooks export: AppleBooksImporter.Export, includeBooksWithoutHighlights: Bool, into data: LibraryData, now: Date = Date()) -> ImportPlan {
        var books = includeBooksWithoutHighlights ? export.allBooks : export.books
        for i in books.indices where !books[i].tags.contains("apple-books") { books[i].tags.append("apple-books") }
        var plan = self.plan(shelf: books, source: .appleBooks, into: data, options: .init(importTags: true, reviewsAsJournal: false))
        var virtual = data
        _ = apply(plan, to: &virtual, maxNewBooks: nil)
        let h = self.plan(highlights: export.clips, sourceTag: "apple-books", into: virtual, now: now)
        plan.newBooks += h.newBooks          // only if a highlight's book was somehow unmatched
        plan.annotations += h.annotations
        plan.duplicatesSkipped += h.duplicatesSkipped
        return plan
    }

    static func plan(highlights clips: [Clipping], sourceTag: String, into data: LibraryData, now: Date = Date()) -> ImportPlan {
        var plan = ImportPlan()
        var index = Index(data.books)
        var newByKey: [String: Int] = [:]
        // Existing passages, normalised, to make re-imports idempotent.
        func norm(_ s: String) -> String { String(s.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(120)) }
        var seen = Set(data.annotations.map { "\($0.bookID)|\(norm($0.quote.isEmpty ? $0.comment : $0.quote))" })

        // Group so each new book is created once, with a sensible status guess.
        let lastDate = Dictionary(clips.map { ($0.title, $0.date ?? .distantPast) }, uniquingKeysWith: max)

        for c in clips {
            var bookID: UUID
            if let id = index.match(title: c.title, author: c.author) {
                bookID = id
            } else {
                let key = titleKey(c.title) + "|" + authorKey(c.author)
                if let i = newByKey[key] { bookID = plan.newBooks[i].id } else {
                    var b = Book(title: c.title, author: c.author)
                    let recent = (lastDate[c.title] ?? .distantPast) > now.addingTimeInterval(-90 * 86400)
                    b.status = recent ? .reading : .finished
                    b.tags = [sourceTag]
                    b.dateAdded = clips.filter { $0.title == c.title }.compactMap(\.date).min() ?? now
                    b.dateStarted = b.dateAdded
                    if !recent { b.dateFinished = lastDate[c.title].flatMap { $0 == .distantPast ? nil : $0 } }
                    newByKey[key] = plan.newBooks.count
                    plan.newBooks.append(b)
                    index.add(b)
                    bookID = b.id
                }
            }
            let key = "\(bookID)|\(norm(c.text))"
            if seen.contains(key) { plan.duplicatesSkipped += 1; continue }
            seen.insert(key)
            var a = Annotation(bookID: bookID, kind: c.kind, page: c.page, created: c.date ?? now)
            if c.kind == .highlight { a.quote = c.text; a.comment = c.note } else { a.comment = c.text }
            a.location = c.location
            a.chapter = c.chapter
            a.order = c.order
            a.tags = c.tags
            plan.annotations.append(a)
        }
        return plan
    }

    // MARK: Apply

    /// `maxNewBooks` enforces the free-tier cap; annotations/journal for books that didn't fit are dropped.
    static func apply(_ plan: ImportPlan, to data: inout LibraryData, maxNewBooks: Int?) -> ImportResult {
        var r = ImportResult()
        let allowed = maxNewBooks.map { max(0, $0) } ?? plan.newBooks.count
        let kept = Array(plan.newBooks.prefix(allowed))
        let dropped = Set(plan.newBooks.dropFirst(allowed).map(\.id))
        r.booksSkippedForLimit = dropped.count
        data.books += kept
        r.booksAdded = kept.count
        for change in plan.updatedBooks {
            if let i = data.books.firstIndex(where: { $0.id == change.book.id }) { data.books[i] = change.book; r.booksUpdated += 1 }
        }
        for a in plan.annotations {
            if dropped.contains(a.bookID) { r.annotationsSkippedForLimit += 1 } else { data.annotations.append(a); r.annotationsAdded += 1 }
        }
        for e in plan.journal where !e.bookIDs.contains(where: dropped.contains) {
            data.journal.append(e); r.journalAdded += 1
        }
        return r
    }
}
