import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState
    @EnvironmentObject var license: LicenseManager
    @State private var renamingMap: ReadingMap?

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            detail
        }
        .sheet(isPresented: $state.showAddBook) { BookEditor(book: nil) }
        .sheet(isPresented: $state.showUpgrade) { UpgradeView(reason: state.upgradeReason) }
        .sheet(item: $renamingMap) { m in MapEditor(map: m) }
        .sheet(item: $state.importKind) { ImportSheet(kind: $0) }
        .alert("Readscape", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("OK") { store.lastError = nil }
        } message: { Text(store.lastError ?? "") }
    }

    private func count(_ s: ReadingStatus?) -> Int { s.map { s in store.data.books.filter { $0.status == s }.count } ?? store.data.books.count }

    private var sidebar: some View {
        List(selection: $state.selection) {
            Section("Library") {
                row("All Books", "books.vertical", count(nil)).tag(SidebarItem.library(nil))
                ForEach(ReadingStatus.allCases) { s in
                    row(s.label, s.symbol, count(s)).tag(SidebarItem.library(s))
                }
            }
            Section("Thinking") {
                row("Journal", "book.closed", store.data.journal.count).tag(SidebarItem.journal)
                row("Annotations", "highlighter", store.data.annotations.count).tag(SidebarItem.annotations)
                row("Statistics", "chart.bar.xaxis", nil).tag(SidebarItem.stats)
            }
            Section {
                row("Whole Library", "point.3.connected.trianglepath.dotted", nil).tag(SidebarItem.graph(nil))
                ForEach(store.data.maps) { m in
                    row(m.name, "map", m.bookIDs.count).tag(SidebarItem.graph(m.id))
                        .contextMenu {
                            Button("Rename…") { renamingMap = m }
                            Button("Delete Map", role: .destructive) {
                                if state.selection == .graph(m.id) { state.selection = .graph(nil) }
                                store.delete(mapID: m.id)
                            }
                        }
                }
            } header: {
                HStack {
                    Text("Reading Maps")
                    Spacer()
                    Button { newMap() } label: { Image(systemName: "plus") }.buttonStyle(.borderless).help("New Reading Map")
                }
            }
            let tags = Array(Set(store.data.books.flatMap(\.tags))).sorted()
            if !tags.isEmpty {
                Section("Tags") {
                    ForEach(tags, id: \.self) { t in
                        row(t, "tag", store.data.books.filter { $0.tags.contains(t) }.count).tag(SidebarItem.tag(t))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !license.isLicensed {
                Button { state.upgrade(nil) } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Free version").font(.caption.bold())
                            Text("\(store.data.books.count) of \(LicenseManager.freeBookLimit) books · Unlock lifetime").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(10)
            }
        }
    }

    private func row(_ title: String, _ symbol: String, _ n: Int?) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if let n, n > 0 { Text("\(n)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
        }
    }

    private func newMap() {
        guard license.canAddMap(currentCount: store.data.maps.count) else {
            state.upgrade("The free version includes \(LicenseManager.freeMapLimit) reading map.")
            return
        }
        let m = ReadingMap(name: "New Map")
        store.upsert(m)
        state.selection = .graph(m.id)
        renamingMap = m
    }

    @ViewBuilder private var detail: some View {
        switch state.selection ?? .library(nil) {
        case .library(let s):
            NavigationStack(path: $state.path) {
                LibraryView(filter: .status(s))
                    .navigationDestination(for: UUID.self) { BookDetailView(bookID: $0) }
            }
        case .tag(let t):
            NavigationStack(path: $state.path) {
                LibraryView(filter: .tag(t))
                    .navigationDestination(for: UUID.self) { BookDetailView(bookID: $0) }
            }
        case .journal: JournalView()
        case .annotations: AnnotationsView()
        case .graph(let id): GraphScreen(mapID: id).id(id)
        case .stats: StatsView()
        }
    }
}

struct MapEditor: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State var map: ReadingMap
    var body: some View {
        Form {
            TextField("Name", text: $map.name)
            TextField("What is this map about?", text: $map.notes, axis: .vertical).lineLimit(3...6)
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { store.upsert(map); dismiss() } }
        }
    }
}
