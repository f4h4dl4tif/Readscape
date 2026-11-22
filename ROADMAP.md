# Readscape roadmap

The MVP (local library, journal, graph view) ships as a **$19–$29 lifetime** purchase. This roadmap keeps that promise: anything that runs locally stays in the lifetime license. Only features that cost you money to run every month (servers, sync, AI) become an optional add-on.

## 1.x: free updates for lifetime buyers (strengthens the core)

**Getting data in** (the biggest barrier to adoption)
- ~~Import from Goodreads and StoryGraph CSV~~ and ~~Kindle highlights (`My Clippings.txt`)~~: **done**.
- ~~Import Apple Books library and highlights~~: **done**.
- Import **Kobo** (`KoboReader.sqlite`), **Readwise** export, and **Libby / Hoopla** reading history.
- Barcode / ISBN scan with the Mac camera or Continuity Camera.
- Add from the browser: a share extension for Amazon, Goodreads and Open Library pages.

**Research tools** (for the researcher customer segment)
- Citation fields (DOI, edition, publisher, place) with **BibTeX / RIS / APA / Chicago export**, and Zotero import.
- PDF and EPUB attachments: highlight inside a built-in reader so annotations link back to their page.
- Backlinks: `[[Book Title]]` mentions in journal entries and annotations become graph edges automatically.
- **Concept nodes**: add ideas, people and topics as graph nodes alongside books, so a map becomes a real knowledge map.
- Obsidian / Logseq vault sync: one Markdown file per book, kept up to date.

**Smarter graph and maps**
- Graph filters: by year read, rating, tag or status, plus a timeline slider that replays how your reading graph grew.
- Cluster detection (community colors) and "bridge books" that connect separate clusters.
- **Reading paths**: an ordered route through a map ("start here → then → then"), with progress tracking.
- Export maps as PNG, SVG or PDF posters.

**Habits and reflection**
- Reading timer in the menu bar with automatic session logging.
- Goals by pages, minutes or books; challenges such as "12 classics this year".
- **Year in Review**: a shareable recap card each December, which also markets the app.
- Widgets (macOS desktop widgets for the current book, streak and goal).
- Spaced-repetition review of highlights (a daily review of five annotations).

## 2.0: Readscape Sync (optional subscription, about $2–3/month or $24/year)

Mobile sync costs you real money to run, so it's priced as a service while the Mac app stays lifetime.
- **iPhone and iPad companion**: log sessions, scan ISBNs, capture highlights by photo (on-device text recognition), and read your journal.
- **CloudKit sync** first: no server for you to run and private by default. That can make sync cheap enough to bundle into a higher lifetime tier instead (for example $39 "Lifetime + Sync").
- Conflict-free merging (per-record timestamps; the Codable/JSON model is already set up for this).
- Optional end-to-end encrypted web backup.

## 2.x: Reading communities (opt-in, privacy-first)

- **Shared maps**: publish a reading map as a read-only web page ("My path into Stoicism"). A good growth loop, since every shared map links back to Readscape.
- **Book clubs and study groups**: a shared reading list, a pace schedule, discussion threads tied to chapters, and a group graph made of everyone's connections.
- **Collaborative research maps** for labs and classes: shared annotations and a team graph. A per-seat **Team / Education** plan fits here.
- Follow readers whose maps you like, with discovery by topic.
- Community-sourced connections: "Readers who connected X also linked it to Y", aggregated anonymously and opt-in only.

## AI features (optional, bring-your-own-key or included with Sync)

- Suggest connections between books based on your annotations.
- Summarize everything you highlighted on a topic across several books.
- Ask your library: "What have I read that disagrees with Kahneman?"
- Recommendations based on gaps in your graph ("you have nothing that bridges these two clusters").
- On-device first (Apple Foundation Models where available), with cloud models opt-in.

## Suggested pricing summary

| Tier | Price | Includes |
|---|---|---|
| Free | $0 | 20 books, 1 map, every feature |
| Lifetime | $24 (launch at $19) | Unlimited, all 1.x updates |
| Lifetime + Sync | $39 one-time, or the Sync subscription | iPhone/iPad app and sync |
| Team / Education | per seat / year | Shared research maps and group graphs |
