import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case library(ReadingStatus?)
    case tag(String)
    case journal
    case annotations
    case graph(UUID?)       // nil = whole library
    case stats
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var selection: SidebarItem? = .library(nil)
    @Published var path: [UUID] = []
    @Published var showAddBook = false
    @Published var upgradeReason: String?
    @Published var showUpgrade = false
    @Published var importKind: ImportKind?
    /// (done, total) while covers for imported books download in the background.
    @Published var coverFetch: (done: Int, total: Int)?
    private var coverQueue: [Book] = []

    /// Open Library allows ~100 ISBN cover lookups per 5 minutes, so go one at a time, ~3 s apart.
    func fetchCovers(for books: [Book]) {
        guard !books.isEmpty else { return }
        let running = coverFetch != nil
        coverQueue += books
        coverFetch = (coverFetch?.done ?? 0, (coverFetch?.total ?? 0) + books.count)
        guard !running else { return }
        Task { @MainActor in
            while !coverQueue.isEmpty {
                let b = coverQueue.removeFirst()
                if let data = await OpenLibrary.cover(isbn: b.isbn), LibraryStore.shared.book(b.id)?.coverFile == nil {
                    LibraryStore.shared.setCover(data, for: b.id)
                }
                coverFetch?.done += 1
                if !coverQueue.isEmpty { try? await Task.sleep(nanoseconds: 3_100_000_000) }
            }
            coverFetch = nil
        }
    }

    func open(book id: UUID) {
        selection = .library(nil)
        DispatchQueue.main.async { self.path = [id] }
    }

    func requestAddBook() {
        if LicenseManager.shared.canAddBook(currentCount: LibraryStore.shared.data.books.count) {
            showAddBook = true
        } else {
            upgrade("The free version holds up to \(LicenseManager.freeBookLimit) books.")
        }
    }

    func upgrade(_ reason: String?) {
        upgradeReason = reason
        showUpgrade = true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { LibraryStore.shared.saveNow() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = Snapshot.outputDir { MainActor.assumeIsolated { Snapshot.run(to: dir) } }
        if let dir = Snapshot.glassOutputDir { MainActor.assumeIsolated { Snapshot.runGlass(to: dir) } }
    }
}

@main
struct ReadscapeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = LibraryStore.shared
    @StateObject private var state = AppState.shared
    @StateObject private var license = LicenseManager.shared

    var body: some Scene {
        WindowGroup("Readscape") {
            ContentView()
                .environmentObject(store)
                .environmentObject(state)
                .environmentObject(license)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Book…") { state.requestAddBook() }.keyboardShortcut("n")
                Button("New Journal Entry") {
                    state.selection = .journal
                    store.upsert(JournalEntry(title: "Untitled entry"))
                }.keyboardShortcut("j", modifiers: [.command, .shift])
            }
            CommandGroup(after: .importExport) {
                Button("Import from Goodreads or StoryGraph…") { state.importKind = .shelf }
                Button("Import Kindle Highlights…") { state.importKind = .kindle }
                Button("Import from Apple Books…") { state.importKind = .appleBooks }
                Divider()
                Button("Export Library Backup…") { BackupPanels.export() }
                Button("Restore Library Backup…") { BackupPanels.restore() }
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Readscape") { NSApp.orderFrontStandardAboutPanel(nil) }
                Button(license.isLicensed ? "License…" : "Unlock Lifetime License…") { state.upgrade(nil) }
            }
            CommandMenu("Go") {
                Button("Library") { state.selection = .library(nil) }.keyboardShortcut("1")
                Button("Journal") { state.selection = .journal }.keyboardShortcut("2")
                Button("Annotations") { state.selection = .annotations }.keyboardShortcut("3")
                Button("Reading Graph") { state.selection = .graph(nil) }.keyboardShortcut("4")
                Button("Statistics") { state.selection = .stats }.keyboardShortcut("5")
            }
        }
        Settings {
            SettingsView().environmentObject(store).environmentObject(license)
        }
    }
}

@MainActor
enum BackupPanels {
    static func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "Readscape Backup \(f.string(from: Date())).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try LibraryStore.shared.exportBackup(to: url) } catch { alert("Export failed", error.localizedDescription) }
    }

    static func restore() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let a = NSAlert()
        a.messageText = "Replace your current library with this backup?"
        a.informativeText = "Your current library is saved alongside it first, so nothing is lost."
        a.addButton(withTitle: "Restore")
        a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        do { try LibraryStore.shared.importBackup(from: url) } catch { alert("Restore failed", "That file isn't a Readscape backup.") }
    }

    static func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var license: LicenseManager
    @AppStorage(GlassTheme.key) private var glass = false

    var body: some View {
        Form {
            Section("Appearance") {
                Toggle(isOn: $glass) {
                    Text("Liquid Glass theme")
                    Text(GlassTheme.supported ? "Floating panels, cards and buttons use Apple’s Liquid Glass." : "Requires macOS 26.")
                }
                .disabled(!GlassTheme.supported)
            }
            Section("Goals") {
                Stepper("Books per year: \(store.data.goals.booksPerYear)", value: $store.data.goals.booksPerYear, in: 1...365)
                Stepper("Pages per day: \(store.data.goals.pagesPerDay)", value: $store.data.goals.pagesPerDay, in: 1...500, step: 5)
            }
            Section("Data") {
                LabeledContent("Library folder") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.folder]) }
                }
                LabeledContent("Backup") {
                    HStack { Button("Export…") { BackupPanels.export() }; Button("Restore…") { BackupPanels.restore() } }
                }
            }
            Section("License") {
                LabeledContent("Status", value: license.isLicensed ? "Lifetime — \(license.licensee ?? "")" : "Free (\(LicenseManager.freeBookLimit) books, \(LicenseManager.freeMapLimit) map)")
                if !license.isLicensed { Button("Unlock…") { AppState.shared.upgrade(nil) } }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
    }
}
