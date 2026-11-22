import Foundation
import SQLite3

/// Reads Apple Books' local Core Data stores (read-only, from a temporary copy):
///   ~/Library/Containers/com.apple.iBooksX/Data/Documents/AEAnnotation/AEAnnotation*.sqlite  (highlights & notes)
///   ~/Library/Containers/com.apple.iBooksX/Data/Documents/BKLibrary/BKLibrary*.sqlite        (books)
/// Columns are discovered at runtime, so a missing optional column just means less metadata.
enum AppleBooksImporter {
    struct Export {
        var books: [ImportedBook] = []         // books that have highlights (or all, if requested)
        var allBooks: [ImportedBook] = []      // every book in the Apple Books library
        var clips: [Clipping] = []
        var orphanedHighlights = 0             // highlights whose book was removed from the library
    }

    static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.apple.iBooksX/Data/Documents", isDirectory: true)
    }

    static func read(folder: URL = defaultFolder) throws -> Export {
        let fm = FileManager.default
        func store(_ sub: String, _ prefix: String) throws -> URL {
            let dir = folder.appendingPathComponent(sub)
            let files: [String]
            do { files = try fm.contentsOfDirectory(atPath: dir.path) }
            catch let e as NSError where e.domain == NSCocoaErrorDomain && (e.code == NSFileReadNoPermissionError || e.code == 257) {
                throw ImportError.unrecognized("Readscape isn't allowed to read Apple Books' data. Choose the folder below to grant access, or allow Readscape under System Settings › Privacy & Security.")
            } catch {
                throw ImportError.unrecognized("Apple Books data wasn't found. Open the Books app at least once (and turn on iCloud for Books to include highlights from iPhone and iPad).")
            }
            guard let name = files.filter({ $0.hasPrefix(prefix) && $0.hasSuffix(".sqlite") }).sorted().last else {
                throw ImportError.unrecognized("Apple Books data wasn't found in \(dir.path).")
            }
            return dir.appendingPathComponent(name)
        }
        let annotationsDB = try store("AEAnnotation", "AEAnnotation")
        let libraryDB = try store("BKLibrary", "BKLibrary")
        return try read(annotationsDB: annotationsDB, libraryDB: libraryDB)
    }

    static func read(annotationsDB: URL, libraryDB: URL) throws -> Export {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("readscape-applebooks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let lib = try SQLite(copying: libraryDB, into: tmp)
        let ann = try SQLite(copying: annotationsDB, into: tmp)

        // Books
        let bcols = try lib.columns("ZBKLIBRARYASSET")
        guard bcols.contains("ZASSETID"), bcols.contains("ZTITLE") else { throw ImportError.unrecognized("Unexpected Apple Books library format.") }
        func bc(_ c: String, _ fallback: String = "NULL") -> String { bcols.contains(c) ? c : fallback }
        let bookRows = try lib.query("""
            SELECT ZASSETID, ZTITLE, \(bc("ZAUTHOR")), \(bc("ZGENRE")), \(bc("ZREADINGPROGRESS")), \(bc("ZISFINISHED")),
                   \(bc("ZDATEFINISHED")), \(bc("ZCREATIONDATE")), \(bc("ZLASTOPENDATE")), \(bc("ZPAGECOUNT")), \(bc("ZISSAMPLE", "0"))
            FROM ZBKLIBRARYASSET WHERE ZTITLE IS NOT NULL
            """)
        var byAsset: [String: ImportedBook] = [:]
        var export = Export()
        for r in bookRows {
            guard let asset = r[0].text, let title = r[1].text?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { continue }
            if (r[10].int ?? 0) != 0 { continue }   // store samples
            var b = ImportedBook(title: title, author: r[2].text ?? "")
            let progress = r[4].double ?? 0
            let finished = (r[5].int ?? 0) != 0 || progress >= 0.995
            b.status = finished ? .finished : progress > 0.005 ? .reading : .wantToRead
            b.dateRead = r[6].date ?? (finished ? r[8].date : nil)
            b.dateAdded = r[7].date
            b.pages = r[9].int ?? 0
            b.progress = progress
            if let g = r[3].text, !g.isEmpty { b.tags = [ShelfImporter.normaliseTag(g)] }
            byAsset[asset] = b
            export.allBooks.append(b)
        }

        // Highlights & notes
        let acols = try ann.columns("ZAEANNOTATION")
        guard acols.contains("ZANNOTATIONASSETID") else { throw ImportError.unrecognized("Unexpected Apple Books annotations format.") }
        func ac(_ c: String, _ fallback: String = "NULL") -> String { acols.contains(c) ? c : fallback }
        let rows = try ann.query("""
            SELECT ZANNOTATIONASSETID, \(ac("ZANNOTATIONSELECTEDTEXT")), \(ac("ZANNOTATIONNOTE")), \(ac("ZANNOTATIONCREATIONDATE")),
                   \(ac("ZANNOTATIONSTYLE")), \(ac("ZANNOTATIONISUNDERLINE", "0")), \(ac("ZPLLOCATIONRANGESTART")), \(ac("ZFUTUREPROOFING5"))
            FROM ZAEANNOTATION
            WHERE \(ac("ZANNOTATIONDELETED", "0")) = 0
            ORDER BY ZANNOTATIONASSETID, \(ac("ZPLLOCATIONRANGESTART", "0")), \(ac("ZANNOTATIONCREATIONDATE", "0"))
            """)
        var withHighlights = Set<String>()
        for r in rows {
            guard let asset = r[0].text else { continue }
            let text = (r[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let note = (r[2].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty || !note.isEmpty else { continue }   // bookmarks / reading positions
            guard let book = byAsset[asset] else { export.orphanedHighlights += 1; continue }
            withHighlights.insert(asset)
            var c = Clipping(title: book.title, author: book.author, kind: text.isEmpty ? .note : .highlight,
                             text: text.isEmpty ? note : text, page: nil, location: nil, locationEnd: nil, date: r[3].date)
            c.order = r[6].int
            if !text.isEmpty { c.note = note }
            if let ch = r[7].text?.trimmingCharacters(in: .whitespaces), !ch.isEmpty { c.chapter = ch }
            let underline = (r[5].int ?? 0) != 0
            if let color = colorName(style: r[4].int, underline: underline) { c.tags = [color] }
            export.clips.append(c)
        }
        export.books = byAsset.filter { withHighlights.contains($0.key) }.map(\.value).sorted { $0.title < $1.title }
        return export
    }

    /// Apple Books highlight styles. Yellow is the default, so it isn't tagged.
    static func colorName(style: Int?, underline: Bool) -> String? {
        if underline { return "underline" }
        switch style {
        case 0: return "underline"
        case 1: return "green"
        case 2: return "blue"
        case 4: return "pink"
        case 5: return "purple"
        default: return nil
        }
    }
}

// MARK: - Minimal read-only SQLite wrapper

final class SQLite {
    enum Value {
        case null, int(Int), double(Double), text(String)
        var text: String? { if case .text(let s) = self { return s }; return nil }
        var int: Int? {
            switch self { case .int(let i): i; case .double(let d): Int(d); case .text(let s): Int(s); default: nil }
        }
        var double: Double? {
            switch self { case .int(let i): Double(i); case .double(let d): d; case .text(let s): Double(s); default: nil }
        }
        /// Core Data stores dates as seconds since 2001-01-01.
        var date: Date? { double.flatMap { $0 > 0 ? Date(timeIntervalSinceReferenceDate: $0) : nil } }
    }

    private var db: OpaquePointer?

    /// Copies the database with its -wal/-shm files so recent, uncheckpointed changes are included
    /// and the live Books database is never opened directly.
    init(copying source: URL, into dir: URL) throws {
        let fm = FileManager.default
        let dest = dir.appendingPathComponent(source.lastPathComponent)
        for suffix in ["", "-wal", "-shm"] {
            let src = URL(fileURLWithPath: source.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            do { try fm.copyItem(at: src, to: URL(fileURLWithPath: dest.path + suffix)) }
            catch { throw ImportError.unrecognized("Couldn't read \(source.lastPathComponent): \(error.localizedDescription)") }
        }
        guard sqlite3_open_v2(dest.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            throw ImportError.unrecognized("Couldn't open \(source.lastPathComponent).")
        }
    }

    deinit { sqlite3_close(db) }

    func columns(_ table: String) throws -> Set<String> {
        Set(try query("PRAGMA table_info(\(table))").compactMap { $0[1].text })
    }

    func query(_ sql: String) throws -> [[Value]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ImportError.unrecognized("Apple Books data couldn't be read (\(String(cString: sqlite3_errmsg(db)))).")
        }
        defer { sqlite3_finalize(stmt) }
        var rows: [[Value]] = []
        let n = sqlite3_column_count(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append((0..<n).map { i in
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: .int(Int(sqlite3_column_int64(stmt, i)))
                case SQLITE_FLOAT: .double(sqlite3_column_double(stmt, i))
                case SQLITE_TEXT: .text(String(cString: sqlite3_column_text(stmt, i)))
                default: .null
                }
            })
        }
        return rows
    }
}
