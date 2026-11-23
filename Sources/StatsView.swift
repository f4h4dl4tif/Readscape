import Charts
import SwiftUI

struct StatsView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var hoverMonth: Date?

    private let cal = Calendar.current

    // MARK: Derived numbers

    private var sessions: [ReadingSession] { store.data.sessions }
    private var finished: [Book] { store.data.books.filter { $0.status == .finished && $0.dateFinished != nil } }
    private var finishedThisYear: [Book] { finished.filter { cal.component(.year, from: $0.dateFinished!) == year } }
    private var yearSessions: [ReadingSession] { sessions.filter { cal.component(.year, from: $0.date) == year } }
    private var years: [Int] {
        let ys = Set(sessions.map { cal.component(.year, from: $0.date) } + finished.map { cal.component(.year, from: $0.dateFinished!) } + [cal.component(.year, from: Date())])
        return ys.sorted(by: >)
    }

    private var pagesByDay: [Date: Int] {
        var d: [Date: Int] = [:]
        for s in sessions { d[cal.startOfDay(for: s.date), default: 0] += s.pagesRead }
        return d
    }
    private var activeDays: Set<Date> { Set(sessions.map { cal.startOfDay(for: $0.date) }) }

    private var streak: (current: Int, best: Int) {
        let days = activeDays
        var cur = 0
        var day = cal.startOfDay(for: Date())
        if !days.contains(day) { day = cal.date(byAdding: .day, value: -1, to: day)! }   // today not logged yet doesn't break it
        while days.contains(day) { cur += 1; day = cal.date(byAdding: .day, value: -1, to: day)! }
        var best = 0, run = 0
        var prev: Date?
        for d in days.sorted() {
            run = (prev.map { cal.dateComponents([.day], from: $0, to: d).day == 1 } ?? false) ? run + 1 : 1
            best = max(best, run); prev = d
        }
        return (cur, best)
    }

    private struct MonthValue: Identifiable { let month: Date; let pages: Int; let books: Int; var id: Date { month } }
    private var months: [MonthValue] {
        (1...12).map { m in
            let start = cal.date(from: DateComponents(year: year, month: m, day: 1))!
            let pages = yearSessions.filter { cal.component(.month, from: $0.date) == m }.reduce(0) { $0 + $1.pagesRead }
            let books = finishedThisYear.filter { cal.component(.month, from: $0.dateFinished!) == m }.count
            return MonthValue(month: start, pages: pages, books: books)
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            if store.data.books.isEmpty {
                EmptyState(symbol: "chart.bar.xaxis", title: "No statistics yet", message: "Add books and log reading sessions to see your reading patterns.")
            } else {
                VStack(alignment: .leading, spacing: 22) {
                    tiles
                    HStack(alignment: .top, spacing: 18) {
                        card("Pages read per month", subtitle: "\(year)") { pagesChart }
                        card("Books finished per month", subtitle: "\(year)") { booksChart }
                    }
                    card("Reading activity", subtitle: "Last 26 weeks · pages per day") { Heatmap(pagesByDay: pagesByDay) }
                    HStack(alignment: .top, spacing: 18) {
                        card("Library by status", subtitle: "\(store.data.books.count) books") { statusChart }
                        card("Top tags", subtitle: "Books per tag") { tagsChart }
                        card("Ratings", subtitle: "Finished books") { ratingsChart }
                    }
                    card("Insights", subtitle: nil) { insights }
                }
                .padding(24)
            }
        }
        .navigationTitle("Statistics")
        .toolbar {
            Picker("Year", selection: $year) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }.fixedSize()
        }
    }

    // MARK: Tiles

    private var tiles: some View {
        let goal = store.data.goals.booksPerYear
        let pages = yearSessions.reduce(0) { $0 + $1.pagesRead }
        let minutes = yearSessions.reduce(0) { $0 + $1.minutes }
        let last30 = sessions.filter { $0.date > cal.date(byAdding: .day, value: -30, to: Date())! }.reduce(0) { $0 + $1.pagesRead }
        let s = streak
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 14, alignment: .top)], spacing: 14) {
            StatTile(title: "Books finished", value: "\(finishedThisYear.count)", detail: "of \(goal) goal in \(String(year))", progress: Double(finishedThisYear.count) / Double(max(1, goal)))
            StatTile(title: "Pages read", value: pages.formatted(), detail: "in \(String(year))")
            StatTile(title: "Time reading", value: "\(minutes / 60) h", detail: "\(minutes % 60) min logged")
            StatTile(title: "Current streak", value: "\(s.current) day\(s.current == 1 ? "" : "s")", detail: "best \(s.best)")
            StatTile(title: "Daily average", value: "\(last30 / 30)", detail: "pages / day, last 30 days · goal \(store.data.goals.pagesPerDay)",
                     progress: Double(last30 / 30) / Double(max(1, store.data.goals.pagesPerDay)))
            StatTile(title: "Annotations", value: "\(store.data.annotations.count)", detail: "\(store.data.links.count) connections")
        }
    }

    // MARK: Charts

    private var pagesChart: some View {
        Chart {
            ForEach(months) { m in
                BarMark(x: .value("Month", m.month, unit: .month), y: .value("Pages", m.pages), width: .ratio(0.6))
                    .foregroundStyle(Palette.series[0])
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                    .opacity(hoverMonth == nil || cal.isDate(hoverMonth!, equalTo: m.month, toGranularity: .month) ? 1 : 0.4)
            }
            if let h = hoverMonth, let m = months.first(where: { cal.isDate($0.month, equalTo: h, toGranularity: .month) }) {
                RuleMark(x: .value("Month", m.month, unit: .month))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        Tooltip(title: m.month.formatted(.dateTime.month(.wide)), value: "\(m.pages) pages")
                    }
            }
        }
        .chartXSelection(value: $hoverMonth)
        .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.narrow), centered: true) } }
        .chartYAxis { AxisMarks { AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
        .frame(height: 190)
    }

    private var booksChart: some View {
        Chart(months) { m in
            BarMark(x: .value("Month", m.month, unit: .month), y: .value("Books", m.books), width: .ratio(0.6))
                .foregroundStyle(Palette.series[2])
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                .annotation(position: .top) {
                    if m.books > 0 { Text("\(m.books)").font(.caption2).foregroundStyle(.secondary) }
                }
        }
        .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.narrow), centered: true) } }
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
        .frame(height: 190)
    }

    private struct StatusCount: Identifiable { let status: ReadingStatus; let count: Int; var id: ReadingStatus { status } }

    private var statusChart: some View {
        let counts: [StatusCount] = ReadingStatus.allCases.map { s in StatusCount(status: s, count: store.data.books.filter { $0.status == s }.count) }
        return HStack(spacing: 16) {
            Chart(counts) { c in
                SectorMark(angle: .value("Books", c.count), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .foregroundStyle(c.status.color)
                    .cornerRadius(3)
            }
            .frame(width: 130, height: 130)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(counts) { c in
                    Button { state.selection = .library(c.status) } label: {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(c.status.color).frame(width: 10, height: 10)
                            Text(c.status.label).foregroundStyle(.primary)
                            Spacer()
                            Text("\(c.count)").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.caption)
        }
        .frame(height: 150)
    }

    private struct TagCount: Identifiable { let tag: String; let value: Int; var id: String { tag } }

    private var tagsChart: some View {
        var tally: [String: Int] = [:]
        for t in store.data.books.flatMap(\.tags) { tally[t, default: 0] += 1 }
        let counts: [TagCount] = tally.map { TagCount(tag: $0.key, value: $0.value) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.tag < $1.tag }
        return Chart(Array(counts.prefix(6))) { t in
            BarMark(x: .value("Books", t.value), y: .value("Tag", t.tag), height: .ratio(0.6))
                .foregroundStyle(Palette.series[0])
                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4))
                .annotation(position: .trailing) { Text("\(t.value)").font(.caption2).foregroundStyle(.secondary) }
        }
        .chartXAxis(.hidden)
        .frame(height: 150)
    }

    private var ratingsChart: some View {
        let rated = store.data.books.filter { $0.rating > 0 }
        return Chart(1...5, id: \.self) { r in
            BarMark(x: .value("Stars", "\(r)★"), y: .value("Books", rated.filter { $0.rating == r }.count), width: .ratio(0.6))
                .foregroundStyle(Palette.series[3])
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
        }
        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) { AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
        .frame(height: 150)
    }

    // MARK: Insights

    private var insights: some View {
        let durations = finished.compactMap { b -> (Book, Int)? in
            guard let s = b.dateStarted, let f = b.dateFinished else { return nil }
            return (b, max(1, cal.dateComponents([.day], from: s, to: f).day ?? 1))
        }
        let fastest = durations.min { $0.1 < $1.1 }
        let longest = finished.max { $0.pageCount < $1.pageCount }
        let degree = Dictionary(store.data.links.flatMap { [($0.from, 1), ($0.to, 1)] }, uniquingKeysWith: +)
        let hub = degree.max { $0.value < $1.value }.flatMap { store.book($0.key).map { b in (b, degree[b.id]!) } }
        let authors = Dictionary(finished.map { ($0.author, 1) }, uniquingKeysWith: +).max { $0.value < $1.value }
        let avgRating = finished.filter { $0.rating > 0 }.map(\.rating)
        let rows: [(String, String, String)] = [
            ("hare", "Fastest read", fastest.map { "\($0.0.title) in \($0.1) days" } ?? "—"),
            ("text.book.closed", "Longest book finished", longest.map { "\($0.title) · \($0.pageCount) pages" } ?? "—"),
            ("point.3.connected.trianglepath.dotted", "Most-connected book", hub.map { "\($0.0.title) · \($0.1) connections" } ?? "—"),
            ("person", "Most-read author", authors.map { "\($0.key) · \($0.value) book\($0.value == 1 ? "" : "s")" } ?? "—"),
            ("star", "Average rating", avgRating.isEmpty ? "—" : String(format: "%.1f ★", Double(avgRating.reduce(0, +)) / Double(avgRating.count))),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), alignment: .topLeading)], alignment: .leading, spacing: 14) {
            ForEach(rows, id: \.1) { icon, title, value in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.caption).foregroundStyle(.secondary)
                        Text(value).font(.callout.weight(.medium))
                    }
                }
            }
        }
    }

    private func card<C: View>(_ title: String, subtitle: String?, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let detail: String
    var progress: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
            if let progress { ProgressBar(value: min(1, progress)) }
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct Tooltip: View {
    @AppStorage(GlassTheme.key) private var glass = false
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .glassSurface(glass, in: RoundedRectangle(cornerRadius: 6)) { RoundedRectangle(cornerRadius: 6).fill(.regularMaterial) }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

/// GitHub-style calendar of pages read per day, single-hue sequential ramp.
struct Heatmap: View {
    let pagesByDay: [Date: Int]
    private let weeks = 26
    private let cal = Calendar.current

    var body: some View {
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) - cal.firstWeekday
        let start = cal.date(byAdding: .day, value: -(weeks - 1) * 7 - ((weekday + 7) % 7), to: today)!
        let maxPages = max(1, pagesByDay.filter { $0.key >= start }.values.max() ?? 1)
        return HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: w * 7 + d, to: start)!
                            let n = pagesByDay[day] ?? 0
                            RoundedRectangle(cornerRadius: 2)
                                .fill(day > today ? Color.clear : n == 0 ? Palette.empty : Palette.heat[min(4, Int(Double(n) / Double(maxPages) * 4.999))])
                                .frame(width: 13, height: 13)
                                .help(day > today ? "" : "\(day.short): \(n) pages")
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { i in RoundedRectangle(cornerRadius: 2).fill(Palette.heat[i]).frame(width: 11, height: 11) }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
