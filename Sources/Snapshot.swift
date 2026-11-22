import AppKit
import SwiftUI

/// Developer aid: `Readscape --snapshot <dir>` loads the sample library, captures each main screen to PNG and quits.
/// Run with CFFIXED_USER_HOME pointing at a scratch folder so it never touches real data.
@MainActor
enum Snapshot {
    static var outputDir: String? {
        guard let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static func run(to dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let store = LibraryStore.shared
        if store.data.books.isEmpty { store.data = SampleData.make() }
        let state = AppState.shared
        let dark = CommandLine.arguments.contains("--dark")
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
        // Own window, so captures don't depend on SwiftUI scene restoration or another running instance.
        let root = ContentView().environmentObject(store).environmentObject(state).environmentObject(LicenseManager.shared)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: root)
        window.toolbarStyle = .unified
        window.center()
        window.orderFrontRegardless()
        wait(1.0)
        NSApp.windows.filter { $0 !== window && !($0 is NSPanel) }.forEach { $0.orderOut(nil) }
        window.setContentSize(NSSize(width: 1280, height: 820))

        let reading = store.data.books.first { $0.status == .reading }!.id
        let steps: [(String, () -> Void, Double)] = [
            ("library", { state.selection = .library(nil) }, 1.2),
            ("book", { state.path = [reading] }, 1.0),
            ("journal", { state.path = []; state.selection = .journal }, 1.0),
            ("annotations", { state.selection = .annotations }, 1.0),
            ("graph", { state.selection = .graph(nil) }, 6.0),
            ("map", { state.selection = .graph(store.data.maps.first?.id) }, 6.0),
            ("stats", { state.selection = .stats }, 1.5),
        ]
        for (name, action, delay) in steps {
            action()
            wait(delay)
            save(window, to: "\(dir)/\(name)\(dark ? "-dark" : "").png")
        }
        // Import sheet previews, when fixtures are passed: --fixtures <dir>
        if let i = CommandLine.arguments.firstIndex(of: "--fixtures"), i + 1 < CommandLine.arguments.count {
            let dirURL = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            for (name, kind, file) in [("import-goodreads", ImportKind.shelf, "goodreads_library_export.csv"), ("import-kindle", ImportKind.kindle, "My Clippings.txt"), ("import-applebooks", ImportKind.appleBooks, "AppleBooks/")] {
                let view = ImportSheet(kind: kind, initialURL: dirURL.appendingPathComponent(file, isDirectory: file.hasSuffix("/")))
                    .environmentObject(store).environmentObject(state).environmentObject(LicenseManager.shared)
                    .background(Color(nsColor: .windowBackgroundColor))
                let host = NSHostingView(rootView: view)
                host.frame.size = NSSize(width: 640, height: 600)
                let w = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                w.contentView = host
                w.orderFrontRegardless()
                wait(1.0)
                save(w, to: "\(dir)/\(name)\(dark ? "-dark" : "").png")
                w.orderOut(nil)
            }
        }
        exit(0)
    }

    private static func save(_ window: NSWindow, to path: String) {
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
