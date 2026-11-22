import Foundation

/// A realistic starter library so new users (and screenshots) can see every view populated.
enum SampleData {
    static func make(now: Date = Date()) -> LibraryData {
        var d = LibraryData()
        let cal = Calendar.current
        func ago(_ days: Int) -> Date { cal.date(byAdding: .day, value: -days, to: now)! }

        let specs: [(String, String, Int, Int, ReadingStatus, Int, [String])] = [
            ("Meditations", "Marcus Aurelius", 180, 254, .finished, 5, ["philosophy", "stoicism"]),
            ("Letters from a Stoic", "Seneca", 254, 254, .finished, 4, ["philosophy", "stoicism"]),
            ("The Obstacle Is the Way", "Ryan Holiday", 201, 201, .finished, 3, ["stoicism", "self-help"]),
            ("Thinking, Fast and Slow", "Daniel Kahneman", 499, 320, .reading, 0, ["psychology", "decision-making"]),
            ("Predictably Irrational", "Dan Ariely", 280, 280, .finished, 4, ["psychology", "economics"]),
            ("Nudge", "Richard Thaler & Cass Sunstein", 312, 312, .finished, 4, ["economics", "decision-making"]),
            ("Sapiens", "Yuval Noah Harari", 443, 443, .finished, 5, ["history", "anthropology"]),
            ("Guns, Germs, and Steel", "Jared Diamond", 480, 140, .reading, 0, ["history", "anthropology"]),
            ("The Structure of Scientific Revolutions", "Thomas Kuhn", 264, 0, .wantToRead, 0, ["philosophy", "science"]),
            ("Gödel, Escher, Bach", "Douglas Hofstadter", 777, 210, .abandoned, 0, ["science", "mathematics"]),
            ("The Beginning of Infinity", "David Deutsch", 487, 0, .wantToRead, 0, ["science", "philosophy"]),
            ("Deep Work", "Cal Newport", 296, 296, .finished, 4, ["productivity", "self-help"]),
            ("Atomic Habits", "James Clear", 320, 320, .finished, 4, ["productivity", "psychology"]),
            ("Man's Search for Meaning", "Viktor Frankl", 165, 165, .finished, 5, ["psychology", "philosophy"]),
        ]
        var ids: [String: UUID] = [:]
        for (i, s) in specs.enumerated() {
            var b = Book(title: s.0, author: s.1, pageCount: s.2, currentPage: s.3, status: s.4, rating: s.5, tags: s.6)
            b.dateAdded = ago(330 - i * 8)
            if s.4 != .wantToRead { b.dateStarted = ago(300 - i * 20 + 10) }
            if s.4 == .finished { b.dateFinished = ago(max(3, 290 - i * 20)) }
            ids[s.0] = b.id
            d.books.append(b)
        }
        func id(_ t: String) -> UUID { ids[t]! }

        // Reading sessions: spread pages across the active period of each started book.
        var seed: UInt64 = 42
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        for b in d.books where b.status != .wantToRead {
            guard let start = b.dateStarted else { continue }
            let end = b.dateFinished ?? ago(0)
            let span = max(1, cal.dateComponents([.day], from: start, to: end).day!)
            var page = 0
            var day = 0
            while page < b.currentPage {
                let chunk = min(b.currentPage - page, 12 + rnd(30))
                let date = cal.date(byAdding: .day, value: min(day, span), to: start)!
                d.sessions.append(ReadingSession(bookID: b.id, date: date, startPage: page, endPage: page + chunk, minutes: chunk * 2 + rnd(15)))
                page += chunk
                day += 1 + rnd(max(1, span / max(1, b.currentPage / 25)))
            }
        }
        // A current streak for the books in progress.
        for back in 0..<9 {
            let t = back % 2 == 0 ? "Thinking, Fast and Slow" : "Guns, Germs, and Steel"
            let cp = d.books.first { $0.id == id(t) }!.currentPage
            let end = cp - (back / 2) * 16
            d.sessions.append(ReadingSession(bookID: id(t), date: ago(back), startPage: end - 16, endPage: end, minutes: 25 + rnd(20)))
        }

        d.annotations = [
            Annotation(bookID: id("Meditations"), kind: .highlight, quote: "You have power over your mind, not outside events.", comment: "Core idea of the whole book. Pairs with Frankl's 'last of the human freedoms'.", page: 42, tags: ["control"]),
            Annotation(bookID: id("Meditations"), kind: .idea, comment: "Morning reflection habit — write three things I can control today.", page: 88, tags: ["habits"]),
            Annotation(bookID: id("Letters from a Stoic"), kind: .note, comment: "Seneca on time: we waste it as if it were unlimited. Compare with Deep Work's attention argument.", page: 3, tags: ["time"]),
            Annotation(bookID: id("Thinking, Fast and Slow"), kind: .highlight, quote: "System 1 operates automatically and quickly, with little or no effort.", comment: "Two-systems model. Nudge is basically System 1 design.", page: 20, tags: ["cognition"]),
            Annotation(bookID: id("Thinking, Fast and Slow"), kind: .question, comment: "How much of the priming research survived the replication crisis?", page: 53, tags: ["research"]),
            Annotation(bookID: id("Sapiens"), kind: .note, comment: "Shared fictions (money, nations) as the basis of large-scale cooperation.", page: 27, tags: ["cooperation"]),
            Annotation(bookID: id("Man's Search for Meaning"), kind: .highlight, quote: "The last of the human freedoms: to choose one's attitude.", comment: "Stoicism, lived under the worst conditions.", page: 66, tags: ["control"]),
            Annotation(bookID: id("Atomic Habits"), kind: .idea, comment: "Identity-based habits — 'I am a reader' rather than 'I want to read more'.", page: 31, tags: ["habits"]),
        ]

        d.links = [
            BookLink(from: id("Letters from a Stoic"), to: id("Meditations"), kind: .related),
            BookLink(from: id("The Obstacle Is the Way"), to: id("Meditations"), kind: .buildsOn, note: "Modern retelling of Marcus's ideas."),
            BookLink(from: id("Man's Search for Meaning"), to: id("Meditations"), kind: .related, note: "Choosing one's attitude."),
            BookLink(from: id("Nudge"), to: id("Thinking, Fast and Slow"), kind: .buildsOn),
            BookLink(from: id("Predictably Irrational"), to: id("Thinking, Fast and Slow"), kind: .related),
            BookLink(from: id("Nudge"), to: id("Predictably Irrational"), kind: .related),
            BookLink(from: id("Sapiens"), to: id("Guns, Germs, and Steel"), kind: .inspiredBy),
            BookLink(from: id("Atomic Habits"), to: id("Deep Work"), kind: .related),
            BookLink(from: id("The Beginning of Infinity"), to: id("The Structure of Scientific Revolutions"), kind: .contradicts, note: "Deutsch argues against Kuhn's paradigm relativism."),
            BookLink(from: id("Gödel, Escher, Bach"), to: id("The Beginning of Infinity"), kind: .related),
            BookLink(from: id("Atomic Habits"), to: id("Thinking, Fast and Slow"), kind: .cites),
        ]

        d.journal = [
            JournalEntry(date: ago(2), title: "Two systems everywhere", body: "Noticing System 1 vs System 2 in my own shopping decisions. Want to reread Nudge's chapter on defaults next to this.", bookIDs: [id("Thinking, Fast and Slow"), id("Nudge")]),
            JournalEntry(date: ago(40), title: "Stoicism thread", body: "Marcus → Seneca → Frankl feels like one continuous argument about what is in our control. Building a map for it.", bookIDs: [id("Meditations"), id("Letters from a Stoic"), id("Man's Search for Meaning")]),
            JournalEntry(date: ago(95), title: "Put GEB down", body: "Too dense for now. Will come back after The Beginning of Infinity.", bookIDs: [id("Gödel, Escher, Bach")]),
        ]

        d.maps = [ReadingMap(name: "Stoicism & Meaning", bookIDs: ["Meditations", "Letters from a Stoic", "The Obstacle Is the Way", "Man's Search for Meaning", "Atomic Habits", "Deep Work"].map(id), notes: "How ancient Stoic ideas show up in modern psychology and productivity books.")]
        return d
    }
}
