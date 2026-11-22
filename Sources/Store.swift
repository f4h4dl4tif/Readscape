import AppKit
import Foundation
import SwiftUI

/// Single source of truth. Persists to ~/Library/Application Support/Readscape/library.json.
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published var data = LibraryData() { didSet { scheduleSave() } }
    @Published var lastError: String?

    let folder: URL
    let coversFolder: URL
    private var fileURL: URL { folder.appendingPathComponent("library.json") }
    private var saveWork: DispatchWorkItem?
    private var loading = false

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = base.appendingPathComponent("Readscape", isDirectory: true)
        coversFolder = folder.appendingPathComponent("covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: coversFolder, withIntermediateDirectories: true)
        load()
    }

    // MARK: Persistence

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func load() {
        guard let raw = try? Data(contentsOf: fileURL) else { return }
        do {
            loading = true
            data = try Self.decoder.decode(LibraryData.self, from: raw)
            loading = false
        } catch {
            loading = false
            // Keep the unreadable file aside instead of overwriting it.
            let bad = folder.appendingPathComponent("library-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: bad)
            lastError = "Your library file couldn't be read. A copy was kept at \(bad.path)."
        }
    }

    private func scheduleSave() {
        guard !loading else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        do {
            try Self.encoder.encode(data).write(to: fileURL, options: .atomic)
        } catch {
            lastError = "Couldn't save: \(error.localizedDescription)"
        }
    }

    func exportBackup(to url: URL) throws {
        try Self.encoder.encode(data).write(to: url, options: .atomic)
    }

    func importBackup(from url: URL) throws {
        let imported = try Self.decoder.decode(LibraryData.self, from: Data(contentsOf: url))
        saveNow()
        let safety = folder.appendingPathComponent("library-before-import-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: fileURL, to: safety)
        data = imported
    }

    // MARK: Lookups

    func book(_ id: UUID?) -> Book? { id.flatMap { id in data.books.first { $0.id == id } } }
    func sessions(for id: UUID) -> [ReadingSession] { data.sessions.filter { $0.bookID == id }.sorted { $0.date > $1.date } }
    func annotations(for id: UUID) -> [Annotation] { data.annotations.filter { $0.bookID == id }.sorted { ($0.page ?? 0, $0.location ?? $0.order ?? 0, $0.created) < ($1.page ?? 0, $1.location ?? $1.order ?? 0, $1.created) } }
    func links(for id: UUID) -> [BookLink] { data.links.filter { $0.from == id || $0.to == id } }
    func journal(for id: UUID) -> [JournalEntry] { data.journal.filter { $0.bookIDs.contains(id) }.sorted { $0.date > $1.date } }
    var allTags: [String] {
        Array(Set(data.books.flatMap(\.tags) + data.annotations.flatMap(\.tags))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: Books

    func add(_ book: Book) { data.books.append(book) }

    func update(_ book: Book) {
        guard let i = data.books.firstIndex(where: { $0.id == book.id }) else { return }
        var b = book
        if b.status == .reading, b.dateStarted == nil { b.dateStarted = Date() }
        if b.status == .finished {
            if b.dateFinished == nil { b.dateFinished = Date() }
            if b.pageCount > 0 { b.currentPage = b.pageCount }
        }
        data.books[i] = b
    }

    func delete(bookID: UUID) {
        if let file = book(bookID)?.coverFile { try? FileManager.default.removeItem(at: coversFolder.appendingPathComponent(file)) }
        var d = data
        d.books.removeAll { $0.id == bookID }
        d.sessions.removeAll { $0.bookID == bookID }
        d.annotations.removeAll { $0.bookID == bookID }
        d.links.removeAll { $0.from == bookID || $0.to == bookID }
        for i in d.journal.indices { d.journal[i].bookIDs.removeAll { $0 == bookID } }
        for i in d.maps.indices {
            d.maps[i].bookIDs.removeAll { $0 == bookID }
            d.maps[i].positions[bookID.uuidString] = nil
        }
        data = d
    }

    func setCover(_ imageData: Data, for bookID: UUID) {
        guard let image = NSImage(data: imageData), let i = data.books.firstIndex(where: { $0.id == bookID }) else { return }
        // Normalise to a modest JPEG so the library folder stays small.
        let target = NSSize(width: 400, height: 400 * image.size.height / max(1, image.size.width))
        let resized = NSImage(size: target)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: target))
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }
        let name = "\(bookID.uuidString)-\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            try jpg.write(to: coversFolder.appendingPathComponent(name))
            if let old = data.books[i].coverFile { try? FileManager.default.removeItem(at: coversFolder.appendingPathComponent(old)) }
            data.books[i].coverFile = name
            CoverCache.shared.forget(old: name)
        } catch { lastError = "Couldn't save cover: \(error.localizedDescription)" }
    }

    // MARK: Reading sessions

    func log(_ session: ReadingSession) {
        var d = data
        d.sessions.append(session)
        if let i = d.books.firstIndex(where: { $0.id == session.bookID }) {
            var b = d.books[i]
            b.currentPage = max(b.currentPage, session.endPage)
            if b.status == .wantToRead || b.status == .abandoned { b.status = .reading }
            if b.dateStarted == nil { b.dateStarted = session.date }
            if b.pageCount > 0, b.currentPage >= b.pageCount {
                b.status = .finished
                b.dateFinished = b.dateFinished ?? session.date
            }
            d.books[i] = b
        }
        data = d
    }

    func delete(sessionID: UUID) { data.sessions.removeAll { $0.id == sessionID } }

    // MARK: Annotations / journal / links / maps

    func upsert(_ a: Annotation) {
        if let i = data.annotations.firstIndex(where: { $0.id == a.id }) { data.annotations[i] = a } else { data.annotations.append(a) }
    }
    func delete(annotationID: UUID) { data.annotations.removeAll { $0.id == annotationID } }

    func upsert(_ e: JournalEntry) {
        if let i = data.journal.firstIndex(where: { $0.id == e.id }) { data.journal[i] = e } else { data.journal.append(e) }
    }
    func delete(journalID: UUID) { data.journal.removeAll { $0.id == journalID } }

    func connect(_ a: UUID, _ b: UUID, kind: LinkKind, note: String = "") {
        guard a != b, !data.links.contains(where: { (($0.from == a && $0.to == b) || ($0.from == b && $0.to == a)) && $0.kind == kind }) else { return }
        data.links.append(BookLink(from: a, to: b, kind: kind, note: note))
    }
    func delete(linkID: UUID) { data.links.removeAll { $0.id == linkID } }

    func upsert(_ m: ReadingMap) {
        if let i = data.maps.firstIndex(where: { $0.id == m.id }) { data.maps[i] = m } else { data.maps.append(m) }
    }
    func delete(mapID: UUID) { data.maps.removeAll { $0.id == mapID } }
}

/// Small in-memory cache so grids don't re-decode JPEGs on every redraw.
@MainActor
final class CoverCache {
    static let shared = CoverCache()
    private var images: [String: NSImage] = [:]
    func image(_ file: String) -> NSImage? {
        if let img = images[file] { return img }
        let img = NSImage(contentsOf: LibraryStore.shared.coversFolder.appendingPathComponent(file))
        images[file] = img
        return img
    }
    func forget(old file: String) { images[file] = nil }
}
