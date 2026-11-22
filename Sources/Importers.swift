import Foundation

// Pure parsers for third-party exports. No store access here, so they're easy to test.

struct ImportedBook: Hashable {
    var title: String
    var author: String
    var isbn = ""
    var rating = 0
    var pages = 0
    var year: Int?
    var publisher = ""
    var status: ReadingStatus = .wantToRead
    var dateRead: Date?
    var dateAdded: Date?
    var tags: [String] = []
    var review = ""
    var privateNotes = ""
    var progress: Double?          // 0...1 when the source knows it (Apple Books)
}

struct Clipping: Hashable {
    var title: String
    var author: String
    var kind: AnnotationKind
    var text: String
    var page: Int?
    var location: Int?
    var locationEnd: Int?
    var date: Date?
    var note = ""          // a note attached to this highlight
    var chapter: String?
    var order: Int?
    var tags: [String] = []
}

enum ImportError: LocalizedError {
    case unrecognized(String)
    var errorDescription: String? {
        switch self { case .unrecognized(let s): s }
    }
}

// MARK: - CSV (RFC 4180: quoted fields, "" escapes, embedded newlines, CRLF)

enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var it = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = nil
        func next() -> Unicode.Scalar? { if let p = pending { pending = nil; return p }; return it.next() }
        while let c = next() {
            if inQuotes {
                if c == "\"" {
                    if let n = it.next() {
                        if n == "\"" { field.unicodeScalars.append("\"") } else { inQuotes = false; pending = n }
                    } else { inQuotes = false }
                } else { field.unicodeScalars.append(c) }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\r": break
                case "\n": row.append(field); rows.append(row); row = []; field = ""
                default: field.unicodeScalars.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }
}

// MARK: - Goodreads & StoryGraph CSV

enum ShelfImporter {
    enum Source: String { case goodreads = "Goodreads", storygraph = "StoryGraph", appleBooks = "Apple Books" }

    static func parse(_ text: String) throws -> (Source, [ImportedBook]) {
        let rows = CSV.parse(text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text)
        guard let header = rows.first else { throw ImportError.unrecognized("The file is empty.") }
        var col: [String: Int] = [:]
        for (i, h) in header.enumerated() { col[h.trimmingCharacters(in: .whitespaces).lowercased()] = i }
        let source: Source
        if col["exclusive shelf"] != nil || col["book id"] != nil { source = .goodreads }
        else if col["read status"] != nil { source = .storygraph }
        else { throw ImportError.unrecognized("This doesn't look like a Goodreads or StoryGraph export. Expected columns such as “Title” and “Exclusive Shelf” or “Read Status”.") }
        guard col["title"] != nil else { throw ImportError.unrecognized("The export has no Title column.") }

        var books: [ImportedBook] = []
        for r in rows.dropFirst() {
            func v(_ name: String) -> String {
                guard let i = col[name], i < r.count else { return "" }
                return r[i].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let title = v("title")
            guard !title.isEmpty else { continue }
            var b = ImportedBook(title: title, author: "")
            switch source {
            case .goodreads:
                b.author = v("author")
                b.isbn = cleanISBN(v("isbn13")).isEmpty ? cleanISBN(v("isbn")) : cleanISBN(v("isbn13"))
                b.rating = Int(v("my rating")) ?? 0
                b.pages = Int(v("number of pages")) ?? 0
                b.year = Int(v("original publication year")) ?? Int(v("year published"))
                b.publisher = v("publisher")
                let shelf = v("exclusive shelf").lowercased()
                b.status = status(forShelf: shelf)
                b.dateRead = date(v("date read"))
                b.dateAdded = date(v("date added"))
                b.tags = v("bookshelves").split(separator: ",").map { normaliseTag(String($0)) }
                    .filter { !$0.isEmpty && !["read", "to-read", "currently-reading", shelf].contains($0) }
                b.review = cleanReview(v("my review"))
                b.privateNotes = v("private notes")
            case .appleBooks:
                break   // not a CSV source
            case .storygraph:
                b.author = v("authors")
                b.isbn = cleanISBN(v("isbn/uid"))
                b.rating = Int((Double(v("star rating")) ?? 0).rounded())
                b.status = status(forShelf: v("read status").lowercased())
                b.dateRead = date(v("last date read")) ?? date(v("dates read").components(separatedBy: "-").last ?? "")
                b.dateAdded = date(v("date added"))
                b.tags = (v("tags") + "," + v("moods")).split(separator: ",").map { normaliseTag(String($0)) }.filter { !$0.isEmpty }
                b.review = cleanReview(v("review"))
            }
            if b.status == .finished, b.dateRead == nil { b.dateRead = b.dateAdded }
            b.rating = min(5, max(0, b.rating))
            b.tags = Array(NSOrderedSet(array: b.tags)) as? [String] ?? b.tags
            books.append(b)
        }
        return (source, books)
    }

    static func status(forShelf s: String) -> ReadingStatus {
        switch s {
        case "read": .finished
        case "currently-reading", "currently reading", "reading": .reading
        case "did-not-finish", "dnf", "abandoned", "did not finish": .abandoned
        default: .wantToRead
        }
    }

    /// Goodreads writes ISBNs as ="0316769487" so spreadsheets keep leading zeros.
    static func cleanISBN(_ s: String) -> String {
        let t = s.filter { $0.isNumber || $0 == "X" || $0 == "x" }.uppercased()
        return (t.count == 10 || t.count == 13) ? t : ""
    }

    static func normaliseTag(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
    }

    static func cleanReview(_ s: String) -> String {
        var t = s
        for br in ["<br/>", "<br />", "<br>", "<BR/>", "<BR>"] { t = t.replacingOccurrences(of: br, with: "\n") }
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (e, r) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] { t = t.replacingOccurrences(of: e, with: r) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let dateFormats = ["yyyy/MM/dd", "yyyy-MM-dd", "yyyy/MM", "MM/dd/yyyy", "yyyy"]
    static func date(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for fmt in dateFormats { f.dateFormat = fmt; if let d = f.date(from: t) { return d } }
        return nil
    }
}

// MARK: - Kindle "My Clippings.txt"

enum KindleImporter {
    static func parse(_ text: String) throws -> [Clipping] {
        let chunks = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "==========")
        var raw: [Clipping] = []
        var sawEntry = false
        for chunk in chunks {
            let lines = chunk.split(separator: "\n", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let content = lines.drop { $0.replacingOccurrences(of: "\u{FEFF}", with: "").isEmpty }
            guard content.count >= 2 else { continue }
            let titleLine = content[content.startIndex].replacingOccurrences(of: "\u{FEFF}", with: "")
            let meta = content[content.startIndex + 1]
            guard meta.hasPrefix("-") else { continue }
            sawEntry = true
            let body = content.dropFirst(2).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = meta.lowercased()
            if lower.contains("bookmark") || lower.contains("clip this article") { continue }
            guard !body.isEmpty else { continue }
            let (title, author) = splitTitle(titleLine)
            let kind: AnnotationKind = lower.contains("your note") || lower.contains(" note ") ? .note : .highlight
            let loc = locationRange(lower)
            raw.append(Clipping(title: title, author: author, kind: kind, text: body,
                                page: firstInt(after: ["page "], in: lower),
                                location: loc?.0, locationEnd: loc?.1, date: date(from: meta)))
        }
        guard sawEntry else {
            throw ImportError.unrecognized("This doesn't look like a Kindle “My Clippings.txt” file. You'll find it in the documents folder when your Kindle is connected by USB.")
        }
        return consolidate(raw)
    }

    /// "Thinking, Fast and Slow (Kahneman, Daniel)" -> ("Thinking, Fast and Slow", "Daniel Kahneman")
    static func splitTitle(_ line: String) -> (String, String) {
        guard line.hasSuffix(")"), let open = line.range(of: " (", options: .backwards) else { return (line, "") }
        var title = String(line[..<open.lowerBound]).trimmingCharacters(in: .whitespaces)
        for suffix in [": A Novel", ": a novel", " (A Novel)", ": A Memoir"] where title.hasSuffix(suffix) { title = String(title.dropLast(suffix.count)) }
        var author = String(line[open.upperBound...].dropLast()).trimmingCharacters(in: .whitespaces)
        let parts = author.split(separator: ";").map { p -> String in
            let bits = p.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return bits.count == 2 ? "\(bits[1]) \(bits[0])" : p.trimmingCharacters(in: .whitespaces)
        }
        author = parts.joined(separator: ", ")
        return (title.isEmpty ? line : title, author)
    }

    private static func firstInt(after keys: [String], in s: String) -> Int? {
        for k in keys {
            if let r = s.range(of: k) {
                let digits = s[r.upperBound...].prefix { $0.isNumber }
                if let n = Int(digits) { return n }
            }
        }
        return nil
    }

    private static func locationRange(_ s: String) -> (Int, Int)? {
        for k in ["location ", "loc. ", "locations "] {
            if let r = s.range(of: k) {
                let rest = s[r.upperBound...]
                let a = rest.prefix { $0.isNumber }
                guard let start = Int(a) else { continue }
                var end = start
                let after = rest.dropFirst(a.count)
                if after.first == "-" { end = Int(after.dropFirst().prefix { $0.isNumber }) ?? start }
                return (start, max(start, end))
            }
        }
        return nil
    }

    private static let formats = [
        "EEEE, d MMMM yyyy HH:mm:ss", "EEEE, MMMM d, yyyy h:mm:ss a", "EEEE, MMMM d, yyyy, h:mm:ss a",
        "EEEE, d MMMM yyyy h:mm:ss a", "EEEE, MMMM dd, yyyy, hh:mm a", "EEEE, MMMM d, yyyy h:mm a",
    ]
    static func date(from meta: String) -> Date? {
        guard let r = meta.range(of: "Added on ", options: .caseInsensitive) else { return nil }
        let s = String(meta[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in formats { f.dateFormat = fmt; if let d = f.date(from: s) { return d } }
        return nil
    }

    /// Kindle appends a new clipping every time a highlight is extended, and stores notes separately.
    /// Keep the longest version of overlapping highlights and attach notes to the highlight they sit on.
    static func consolidate(_ clips: [Clipping]) -> [Clipping] {
        var out: [Clipping] = []
        for c in clips where c.kind == .highlight {
            if let i = out.lastIndex(where: { $0.title == c.title && overlaps($0, c) }) {
                if c.text.count >= out[i].text.count || c.text.contains(out[i].text) { out[i].text = c.text; out[i].location = c.location; out[i].locationEnd = c.locationEnd; out[i].date = c.date ?? out[i].date }
            } else if !out.contains(where: { $0.title == c.title && $0.text == c.text }) {
                out.append(c)
            }
        }
        for n in clips where n.kind == .note {
            if let loc = n.location, let i = out.lastIndex(where: { $0.title == n.title && ($0.location ?? -1) <= loc && loc <= ($0.locationEnd ?? $0.location ?? -1) + 1 }) {
                out[i].note = out[i].note.isEmpty ? n.text : out[i].note + "\n" + n.text
            } else {
                out.append(n)
            }
        }
        return out
    }

    private static func overlaps(_ a: Clipping, _ b: Clipping) -> Bool {
        guard let a0 = a.location, let b0 = b.location else { return false }
        let a1 = a.locationEnd ?? a0, b1 = b.locationEnd ?? b0
        return a0 <= b1 && b0 <= a1 && (a.text.contains(b.text) || b.text.contains(a.text) || a0 == b0)
    }
}
