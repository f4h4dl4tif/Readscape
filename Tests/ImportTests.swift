import Foundation

// Run with: ./Tests/run_import_tests.sh
// Exercises the Goodreads / StoryGraph / Kindle parsers and the import planner against the fixtures.

var failures = 0
func check(_ cond: Bool, _ msg: String, line: Int = #line) {
    if cond { print("  ✓ \(msg)") } else { failures += 1; print("  ✗ \(msg)  (line \(line))") }
}
func fixture(_ name: String) -> String {
    let dir = URL(fileURLWithPath: CommandLine.arguments[1])
    let data = try! Data(contentsOf: dir.appendingPathComponent(name))
    return String(data: data, encoding: .utf8)!
}

@main struct ImportTests {
    static func main() throws {
        print("CSV")
        let rows = CSV.parse("a,\"b, c\",\"say \"\"hi\"\"\"\r\n1,\"multi\nline\",3\n")
        check(rows.count == 2 && rows[0] == ["a", "b, c", "say \"hi\""], "quoted commas and escaped quotes")
        check(rows[1][1] == "multi\nline", "embedded newline")

        print("Goodreads")
        let (src, gr) = try ShelfImporter.parse(fixture("goodreads_library_export.csv"))
        check(src == .goodreads, "detected Goodreads")
        check(gr.count == 7, "7 rows parsed (got \(gr.count))")
        let med = gr[0]
        check(med.isbn == "9780812968255", "ISBN13 unwrapped from =\"…\"")
        check(med.rating == 5 && med.status == .finished && med.year == 180, "rating, status, original year")
        check(med.tags == ["philosophy", "stoicism"], "shelves → tags (\(med.tags))")
        check(med.review.contains("\n\nBook 2"), "review <br/> → newlines")
        let tfs = gr[1]
        check(tfs.status == .reading && tfs.tags == ["psychology"], "currently-reading shelf excluded from tags")
        check(tfs.privateNotes.hasPrefix("Check the replication"), "private notes")
        check(gr[2].isbn.isEmpty && gr[2].review.contains("\nSecond paragraph"), "empty ISBN and multi-line review")
        check(gr[4].status == .abandoned && gr[4].tags.isEmpty, "did-not-finish → Abandoned")
        check(gr[5].status == .wantToRead, "to-read → Want to Read")

        print("StoryGraph")
        let (src2, sg) = try ShelfImporter.parse(fixture("storygraph_export.csv"))
        check(src2 == .storygraph && sg.count == 3, "detected StoryGraph, 3 rows")
        check(sg[0].rating == 5 && sg[0].status == .finished && sg[0].isbn == "9781635575637", "4.75 stars rounds to 5, read, ISBN")
        check(sg[0].tags.contains("fantasy") && sg[0].tags.contains("mysterious"), "tags + moods")
        check(sg[1].status == .abandoned && sg[2].status == .wantToRead, "DNF and to-read statuses")

        print("Kindle")
        let clips = try KindleImporter.parse(fixture("My Clippings.txt"))
        check(clips.count == 4, "bookmark dropped, extended highlight merged → 4 clippings (got \(clips.count))")
        let k0 = clips[0]
        check(k0.title == "Thinking, Fast and Slow" && k0.author == "Daniel Kahneman", "BOM stripped, author “Last, First” flipped")
        check(k0.text.hasSuffix("distinguished from truth."), "kept the longest version of the extended highlight")
        check(k0.note.hasPrefix("Ties to Nudge"), "note attached to its highlight")
        check(k0.page == 20 && k0.location == 301, "page and location")
        check(k0.date != nil, "UK-style date parsed")
        check(clips[1].date != nil && clips[1].location == 1205, "US-style date and location-only clipping")
        check(clips[2].author == "David Thomas, Andrew Hunt", "multiple authors")
        check(clips[3].kind == .note && clips[3].note.isEmpty, "unattached note stays standalone")
        do { _ = try KindleImporter.parse("not a clippings file"); check(false, "rejects non-clippings text") }
        catch { check(true, "rejects non-clippings text") }

        print("Planner: Goodreads into the sample library")
        var lib = SampleData.make()
        let before = lib.books.count
        let plan = ImportPlanner.plan(shelf: gr, source: .goodreads, into: lib, options: .init())
        check(plan.newBooks.map(\.title) == ["How to Win Friends & Influence People", "The Hunger Games (The Hunger Games, #1)", "Project Hail Mary"], "3 new books (\(plan.newBooks.map(\.title)))")
        check(Set(plan.updatedBooks.map(\.book.title)) == ["Meditations", "Thinking, Fast and Slow", "Gödel, Escher, Bach"], "matched existing by title+author incl. subtitle/diacritics")
        check(plan.updatedBooks.first { $0.book.title == "Meditations" }?.book.isbn == "9780812968255", "fills missing ISBN on match")
        check(plan.updatedBooks.first { $0.book.title == "Gödel, Escher, Bach" }?.book.status == .abandoned, "keeps status when import isn't further along")
        check(plan.unchangedBooks == 1, "duplicate row in file is a no-op")
        check(plan.journal.count == 2 && plan.annotations.count == 1, "2 reviews → journal, 1 private note → annotation")

        let capped = ImportPlanner.apply(plan, to: &lib, maxNewBooks: 1)
        check(capped.booksAdded == 1 && capped.booksSkippedForLimit == 2, "free-tier cap keeps the first new book only")
        check(lib.books.count == before + 1, "library grew by 1")
        let again = ImportPlanner.plan(shelf: gr, source: .goodreads, into: lib, options: .init())
        check(again.newBooks.count == 2 && again.journal.isEmpty && again.annotations.isEmpty, "re-import after unlock adds only what was skipped")
        _ = ImportPlanner.apply(again, to: &lib, maxNewBooks: nil)
        let third = ImportPlanner.plan(shelf: gr, source: .goodreads, into: lib, options: .init())
        check(third.isEmpty, "third import is a complete no-op")

        print("Planner: Kindle")
        let kplan = ImportPlanner.plan(kindle: clips, into: lib, now: ISO8601DateFormatter().date(from: "2026-11-20T00:00:00Z")!)
        check(kplan.newBooks.map(\.title) == ["The Pragmatic Programmer"], "Project Hail Mary: A Novel matched the Goodreads book; only 1 new (\(kplan.newBooks.map(\.title)))")
        check(kplan.newBooks.first?.status == .finished, "old highlights → status guessed Finished")
        check(kplan.annotations.count == 4, "4 annotations")
        let tfsID = lib.books.first { $0.title == "Thinking, Fast and Slow" }!.id
        check(kplan.annotations.contains { $0.bookID == tfsID && $0.comment.hasPrefix("Ties to Nudge") && $0.location == 301 }, "highlight + note land on the existing book")
        _ = ImportPlanner.apply(kplan, to: &lib, maxNewBooks: nil)
        let kagain = ImportPlanner.plan(kindle: clips, into: lib)
        check(kagain.isEmpty && kagain.duplicatesSkipped == 4, "re-importing clippings adds nothing")

        print("Apple Books")
        let abDir = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppleBooks")
        let ab = try AppleBooksImporter.read(folder: abDir)
        check(ab.allBooks.count == 4, "4 library books, store sample skipped (got \(ab.allBooks.count))")
        check(Set(ab.books.map(\.title)) == ["Thinking, Fast and Slow", "Meditations", "Piranesi"], "3 books with highlights")
        check(ab.clips.count == 5, "5 highlights/notes: deleted, bookmark and orphan excluded (got \(ab.clips.count))")
        check(ab.orphanedHighlights == 1, "orphaned highlight counted")
        let abTFS = ab.clips.filter { $0.title == "Thinking, Fast and Slow" }
        check(abTFS.map(\.order) == [50, 100], "reading order from location range")
        check(abTFS[0].tags == ["green"] && abTFS[1].tags.isEmpty, "green tagged, default yellow not tagged")
        check(abTFS[1].note.hasPrefix("Relates to") && abTFS[1].chapter == "Part I: Two Systems", "note and chapter carried over")
        check(ab.clips.contains { $0.title == "Piranesi" && $0.tags == ["underline"] }, "underline style")
        check(ab.clips.contains { $0.title == "Piranesi" && $0.kind == .note && $0.text.hasPrefix("A note written") }, "note without highlighted text")
        let abMed = ab.allBooks.first { $0.title == "Meditations" }!
        check(abMed.status == .finished && abMed.dateRead == Date(timeIntervalSinceReferenceDate: 740000000), "finished + Core Data date")
        check(ab.allBooks.first { $0.title == "Piranesi" }?.status == .reading, "partial progress → Reading")
        check(ab.allBooks.first { $0.title == "The Odyssey" }?.status == .wantToRead, "no progress → Want to Read")
        do { _ = try AppleBooksImporter.read(folder: URL(fileURLWithPath: "/nonexistent")); check(false, "missing folder reports a clear error") }
        catch { check(error.localizedDescription.contains("wasn't found"), "missing folder reports a clear error") }

        print("Planner: Apple Books into the sample library")
        var lib2 = SampleData.make()
        let aplan = ImportPlanner.plan(appleBooks: ab, includeBooksWithoutHighlights: false, into: lib2)
        check(aplan.newBooks.map(\.title) == ["Piranesi"], "only Piranesi is new (\(aplan.newBooks.map(\.title)))")
        check(aplan.newBooks.first?.tags.contains("apple-books") == true && aplan.newBooks.first?.tags.contains("fantasy") == true, "genre and source tags")
        let tfsChange = aplan.updatedBooks.first { $0.book.title == "Thinking, Fast and Slow" }
        check(tfsChange?.book.currentPage == 399 && tfsChange?.changes.contains("progress") == true, "progress 80% of 499 → page 399")
        check(aplan.annotations.count == 5, "5 annotations planned")
        check(aplan.annotations.contains { $0.chapter == "Book Ten" && $0.tags == ["pink"] }, "chapter + color on annotation")
        _ = ImportPlanner.apply(aplan, to: &lib2, maxNewBooks: nil)
        let tfs2 = lib2.books.first { $0.title == "Thinking, Fast and Slow" }!.id
        let store = lib2.annotations.filter { $0.bookID == tfs2 }.sorted { ($0.page ?? 0, $0.location ?? $0.order ?? 0, $0.created) < ($1.page ?? 0, $1.location ?? $1.order ?? 0, $1.created) }
        check(store.first?.quote.hasPrefix("The idea of mental energy") == true, "annotations sort in reading order")
        check(ImportPlanner.plan(appleBooks: ab, includeBooksWithoutHighlights: false, into: lib2).isEmpty, "re-import is a no-op")
        let all = ImportPlanner.plan(appleBooks: ab, includeBooksWithoutHighlights: true, into: lib2)
        check(all.newBooks.map(\.title) == ["The Odyssey"] && all.annotations.isEmpty, "“include books without highlights” adds The Odyssey only")
        let fromKindle = ImportPlanner.plan(kindle: clips, into: lib2)
        check(!fromKindle.annotations.contains { $0.quote.contains("mental energy") }, "Kindle and Apple Books highlights share duplicate detection")

        print(failures == 0 ? "\nAll import tests passed." : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
