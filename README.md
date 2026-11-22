# Readscape

A visual reading intelligence app for macOS. Track books and progress, keep a reading journal and annotations, connect related books, arrange them into reading maps, and see your reading statistics. Everything stays on your Mac.

## Build & run

```bash
./build.sh            # builds build/Readscape.app (Apple Silicon, macOS 14+; needs Xcode installed)
open build/Readscape.app
./make_dmg.sh         # drag-to-install DMG in build/
```

On first launch, choose **Load Sample Library** to see every screen populated, or use **File › Import from Goodreads or StoryGraph… / Import Kindle Highlights… / Import from Apple Books…**.

```bash
./Tests/run_import_tests.sh   # parser + import planner tests against Tests/Fixtures
```

## MVP features

- **Library**: grid or table view, sorting, search, sidebar filters by status and tag, and a "Currently Reading" shelf. Look up books on Open Library by title, author or ISBN to fill in details and covers (only the search text is sent). Covers can also be dropped in or generated.
- **Progress**: log reading sessions (pages and minutes). Logging updates the current page, start and finish dates, and status, and shows an estimate of the time left.
- **Annotations**: highlights, notes, questions and ideas, each with page and tags. One view lists all annotations with search and type filters, and you can export them to Markdown (for Obsidian, papers and similar).
- **Reading journal**: dated entries grouped by month, with linked books and a word count.
- **Connections**: link books as *related to, builds on, contradicts, inspired by, cites* or *sequel to*, each with an optional note.
- **Graph view**: a force-directed graph of the whole library. Node size shows the number of annotations, color shows status or tag, arrows show direction and dashed red lines mark contradictions. You can show dotted lines between books that share a tag. Pan, zoom and fit; Option-drag one book onto another to connect them; click a book to open the inspector.
- **Reading maps**: named subsets of the library with pinned, hand-arranged layouts. Includes **Add Connected Books**, which adds every book directly linked to the ones already in the map.
- **Statistics**: books per year against your goal, pages and time read, current and best streak, daily average, pages and books per month, a 26-week activity heatmap, status breakdown, top tags, ratings and insights (fastest read, most-connected book, and more).
- **Import**: Goodreads and StoryGraph CSV exports (shelves, ratings, dates read, reviews into the journal, private notes) Kindle `My Clippings.txt` (extended highlights merged, notes attached to their highlight, bookmarks skipped), and the **Apple Books** library on this Mac (reading status and progress, finish dates, genres, highlights with their chapter, notes, and highlight colors as tags; iPhone and iPad highlights are included when iCloud is on for Books). Apple Books is read from a temporary copy of its databases and is never modified; macOS may ask permission to access another app's data. You see a preview before anything changes. Imported books are matched to ones already in your library, so importing the same file again only adds what's new. Covers download from Open Library in the background, about one every 3 seconds because of its rate limit.
- **Backup and restore**: export or restore the whole library as JSON. A restore saves your current library first.

Data lives in `~/Library/Application Support/Readscape/` (`library.json` plus `covers/`).

## Monetization: lifetime license ($19–$29)

The free version holds **20 books and 1 reading map**; everything else is fully usable. A license key unlocks unlimited use permanently.

Keys are Ed25519-signed and checked offline, so there's no server or account:

```bash
swift Tools/license_tool.swift issue "Buyer Name" order-123   # prints RS1-… key
```

- The signing key is in `Tools/keys/private.key`. **Back it up and never commit or ship it.** If you lose it, you can't issue keys that existing builds accept. `.gitignore` already excludes it.
- Set `LicenseManager.purchaseURL` in `Sources/License.swift` to your Gumroad, Lemon Squeezy or Paddle checkout. Most of these can run a webhook or script that calls `issue` and emails the key to the buyer.
- For the Mac App Store instead: replace the key check with a StoreKit 2 non-consumable (`Product.purchase()` / `Transaction.currentEntitlements`). The free-tier limits stay as they are.

Before selling, you'll want to sign with a Developer ID and notarize the build (`build.sh` currently signs ad-hoc).

## Project layout

| File | Purpose |
|---|---|
| `Sources/Models.swift` | Codable records (Book, ReadingSession, Annotation, JournalEntry, BookLink, ReadingMap) and the chart palette |
| `Sources/Store.swift` | JSON persistence, CRUD, covers, backup |
| `Sources/LibraryView.swift`, `BookEditor.swift`, `BookDetailView.swift` | Library, add/edit, book page, sessions, annotations, connections |
| `Sources/JournalView.swift` | Journal and the all-annotations view, plus Markdown export |
| `Sources/GraphView.swift` | Force layout, graph canvas, maps |
| `Sources/StatsView.swift` | Swift Charts statistics |
| `Sources/Importers.swift`, `AppleBooksImporter.swift`, `ImportPlanner.swift`, `ImportView.swift` | Goodreads/StoryGraph/Kindle parsers, Apple Books SQLite reader, matching and dedupe, import sheet |
| `Sources/License.swift` | Lifetime license and upgrade sheet |
| `Sources/Snapshot.swift` | `Readscape --snapshot <dir> [--dark] [--fixtures Tests/Fixtures]` renders each screen (and the import sheet) to PNG (run with `CFFIXED_USER_HOME` set to a scratch folder) |
