import Foundation
import SwiftUI

// MARK: - Core records. Everything is plain Codable so the library stays a portable JSON file
// (easy to back up today, easy to sync later).

enum ReadingStatus: String, Codable, CaseIterable, Identifiable {
    case reading, wantToRead, finished, abandoned
    var id: String { rawValue }
    var label: String {
        switch self {
        case .reading: "Reading"
        case .wantToRead: "Want to Read"
        case .finished: "Finished"
        case .abandoned: "Abandoned"
        }
    }
    var symbol: String {
        switch self {
        case .reading: "book"
        case .wantToRead: "bookmark"
        case .finished: "checkmark.seal"
        case .abandoned: "xmark.bin"
        }
    }
    /// Fixed categorical slot (never re-ordered by filtering).
    var color: Color { Palette.series[ReadingStatus.allCases.firstIndex(of: self)!] }
}

struct Book: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var author: String
    var isbn: String = ""
    var publisher: String = ""
    var year: Int?
    var pageCount: Int = 0
    var currentPage: Int = 0
    var status: ReadingStatus = .wantToRead
    var rating: Int = 0               // 0 = unrated, 1...5
    var tags: [String] = []
    var summary: String = ""
    var coverFile: String?            // file name inside the covers folder
    var dateAdded = Date()
    var dateStarted: Date?
    var dateFinished: Date?

    var progress: Double {
        if status == .finished { return 1 }
        guard pageCount > 0 else { return 0 }
        return min(1, Double(currentPage) / Double(pageCount))
    }
    /// Stable hue for generated covers.
    var coverHue: Double {
        let h = title.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return Double(h % 360) / 360
    }
}

struct ReadingSession: Identifiable, Codable, Hashable {
    var id = UUID()
    var bookID: UUID
    var date = Date()
    var startPage: Int
    var endPage: Int
    var minutes: Int = 0
    var note: String = ""
    var pagesRead: Int { max(0, endPage - startPage) }
}

enum AnnotationKind: String, Codable, CaseIterable, Identifiable {
    case highlight, note, question, idea
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .highlight: "highlighter"
        case .note: "note.text"
        case .question: "questionmark.bubble"
        case .idea: "lightbulb"
        }
    }
}

struct Annotation: Identifiable, Codable, Hashable {
    var id = UUID()
    var bookID: UUID
    var kind: AnnotationKind = .highlight
    var quote: String = ""            // passage from the book
    var comment: String = ""          // the reader's own thought
    var page: Int?
    var location: Int?                // e-reader location (Kindle), when there is no page
    var chapter: String?
    var order: Int?                   // source's reading-order key (Apple Books); sorting only, never shown
    var tags: [String] = []
    var created = Date()
}

struct JournalEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date = Date()
    var title: String = ""
    var body: String = ""
    var bookIDs: [UUID] = []
}

enum LinkKind: String, Codable, CaseIterable, Identifiable {
    case related, buildsOn, contradicts, inspiredBy, cites, sequel
    var id: String { rawValue }
    var label: String {
        switch self {
        case .related: "Related to"
        case .buildsOn: "Builds on"
        case .contradicts: "Contradicts"
        case .inspiredBy: "Inspired by"
        case .cites: "Cites"
        case .sequel: "Sequel to"
        }
    }
}

struct BookLink: Identifiable, Codable, Hashable {
    var id = UUID()
    var from: UUID
    var to: UUID
    var kind: LinkKind = .related
    var note: String = ""
    mutating func swapDirection() { (from, to) = (to, from) }
}

struct MapPoint: Codable, Hashable { var x: Double; var y: Double }

/// A named, hand-arranged subset of the library ("Stoicism research", "Books that shaped me").
struct ReadingMap: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var bookIDs: [UUID] = []
    var positions: [String: MapPoint] = [:]   // book UUID string -> pinned position
    var notes: String = ""
    var created = Date()
}

struct Goals: Codable, Hashable {
    var booksPerYear: Int = 24
    var pagesPerDay: Int = 20
}

struct LibraryData: Codable {
    var version = 1
    var books: [Book] = []
    var sessions: [ReadingSession] = []
    var annotations: [Annotation] = []
    var journal: [JournalEntry] = []
    var links: [BookLink] = []
    var maps: [ReadingMap] = []
    var goals = Goals()
}

// MARK: - Palette (validated categorical order; light/dark steps chosen per appearance)

enum Palette {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { ap in
            let v = ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                           blue: CGFloat(v & 0xff) / 255, alpha: 1)
        })
    }
    static let series: [Color] = [
        dyn(0x2a78d6, 0x3987e5), // blue
        dyn(0xeb6834, 0xd95926), // orange
        dyn(0x1baf7a, 0x199e70), // aqua
        dyn(0xeda100, 0xc98500), // yellow
        dyn(0xe87ba4, 0xd55181), // magenta
        dyn(0x008300, 0x0ca30c), // green
        dyn(0x6250d6, 0x9085e9), // violet
        dyn(0xe34948, 0xe66767), // red
    ]
    /// Sequential blue ramp for the reading heatmap (light -> dark on light surfaces).
    static let heat: [Color] = [
        dyn(0xcde2fb, 0x184f95), dyn(0x86b6ef, 0x256abf), dyn(0x3987e5, 0x3987e5), dyn(0x1c5cab, 0x6da7ec), dyn(0x0d366b, 0x9ec5f4),
    ]
    static let empty = dyn(0xf0efec, 0x2a2a28)
}
