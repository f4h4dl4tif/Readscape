import SwiftUI

// MARK: - Force-directed layout

@MainActor
final class GraphSim: ObservableObject {
    @Published var pos: [UUID: CGPoint] = [:]
    @Published var settled = false
    private var vel: [UUID: CGVector] = [:]
    var pinned: Set<UUID> = []
    var nodes: [UUID] = []
    var edges: [(UUID, UUID, Double)] = []   // a, b, strength
    private var timer: Timer?
    private var ticks = 0

    func configure(nodes: [UUID], edges: [(UUID, UUID, Double)], saved: [UUID: CGPoint]) {
        self.nodes = nodes
        self.edges = edges
        var p: [UUID: CGPoint] = [:]
        for (i, id) in nodes.enumerated() {
            if let s = saved[id] { p[id] = s; pinned.insert(id) }
            else if let old = pos[id] { p[id] = old }
            else {
                // Golden-angle spiral gives a deterministic, even starting spread.
                let a = Double(i) * 2.39996, r = 40 * sqrt(Double(i + 1))
                p[id] = CGPoint(x: cos(a) * r, y: sin(a) * r)
            }
        }
        pos = p
        pinned = pinned.intersection(nodes)
        reheat()
    }

    func reheat() {
        ticks = 0
        settled = false
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.step() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil; settled = true }

    private func step() {
        ticks += 1
        let alpha = max(0.02, 1 - Double(ticks) / 300)
        var p = pos
        var force: [UUID: CGVector] = [:]
        let ids = nodes
        // Repulsion
        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                guard let a = p[ids[i]], let b = p[ids[j]] else { continue }
                var dx = a.x - b.x, dy = a.y - b.y
                var d2 = dx * dx + dy * dy
                if d2 < 1 { dx = Double.random(in: -1...1); dy = Double.random(in: -1...1); d2 = 1 }
                let f = 22000 / d2
                let d = sqrt(d2)
                force[ids[i], default: .zero].dx += dx / d * f; force[ids[i], default: .zero].dy += dy / d * f
                force[ids[j], default: .zero].dx -= dx / d * f; force[ids[j], default: .zero].dy -= dy / d * f
            }
        }
        // Springs
        for (a, b, s) in edges {
            guard let pa = p[a], let pb = p[b] else { continue }
            let dx = pb.x - pa.x, dy = pb.y - pa.y
            let d = max(1, sqrt(dx * dx + dy * dy))
            let f = (d - 170) * 0.04 * s
            force[a, default: .zero].dx += dx / d * f; force[a, default: .zero].dy += dy / d * f
            force[b, default: .zero].dx -= dx / d * f; force[b, default: .zero].dy -= dy / d * f
        }
        var energy = 0.0
        for id in ids where !pinned.contains(id) {
            guard var pt = p[id] else { continue }
            var v = vel[id] ?? .zero
            let f = force[id] ?? .zero
            v.dx = (v.dx + (f.dx - pt.x * 0.012) * alpha) * 0.6   // gravity toward centre
            v.dy = (v.dy + (f.dy - pt.y * 0.012) * alpha) * 0.6
            let speed = sqrt(v.dx * v.dx + v.dy * v.dy)
            if speed > 30 { v.dx *= 30 / speed; v.dy *= 30 / speed }
            pt.x += v.dx; pt.y += v.dy
            p[id] = pt; vel[id] = v
            energy += v.dx * v.dx + v.dy * v.dy
        }
        pos = p
        if ticks > 600 || (ticks > 60 && energy / Double(max(1, ids.count)) < 0.01) { stop() }
    }
}

// MARK: - Screen

struct GraphScreen: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var state: AppState
    let mapID: UUID?

    @StateObject private var sim = GraphSim()
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var panStart: CGSize?
    @State private var zoomStart: CGFloat?
    @State private var selected: UUID?
    @State private var hovered: UUID?
    @State private var dragStart: CGPoint?
    @State private var linkDrag: (from: UUID, to: CGPoint)?
    @State private var addingBooks = false
    @State private var connecting: Book?
    @State private var canvasSize = CGSize(width: 900, height: 620)
    @State private var didAutoFit = false
    @AppStorage("graphColorBy") private var colorBy = "status"
    @AppStorage("graphSharedTags") private var showSharedTags = false
    @AppStorage(GlassTheme.key) private var glass = false

    private var map: ReadingMap? { mapID.flatMap { id in store.data.maps.first { $0.id == id } } }
    private var books: [Book] {
        guard let map else { return store.data.books }
        return map.bookIDs.compactMap { store.book($0) }
    }
    private var nodeIDs: Set<UUID> { Set(books.map(\.id)) }
    private var links: [BookLink] { store.data.links.filter { nodeIDs.contains($0.from) && nodeIDs.contains($0.to) } }
    private var tagEdges: [(UUID, UUID, String)] {
        guard showSharedTags else { return [] }
        var out: [(UUID, UUID, String)] = []
        let bs = books
        let linked = Set(links.flatMap { [[$0.from, $0.to], [$0.to, $0.from]] }.map { "\($0[0])\($0[1])" })
        for i in 0..<bs.count { for j in (i + 1)..<bs.count {
            if let t = bs[i].tags.first(where: { bs[j].tags.contains($0) }), !linked.contains("\(bs[i].id)\(bs[j].id)") { out.append((bs[i].id, bs[j].id, t)) }
        } }
        return out
    }
    /// Tag slots are computed over the whole library so a map's subset never repaints them.
    private var topTags: [String] {
        let counts = Dictionary(store.data.books.flatMap(\.tags).map { ($0, 1) }, uniquingKeysWith: +)
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(7).map(\.key)
    }
    private func color(_ b: Book) -> Color {
        if colorBy == "tag" {
            if let t = b.tags.first(where: { topTags.contains($0) }), let i = topTags.firstIndex(of: t) { return Palette.series[i] }
            return .gray
        }
        return b.status.color
    }
    private var neighbors: Set<UUID> {
        guard let s = selected ?? hovered else { return [] }
        return Set(links.compactMap { $0.from == s ? $0.to : $0.to == s ? $0.from : nil } + [s])
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                if books.isEmpty {
                    EmptyState(symbol: map == nil ? "point.3.connected.trianglepath.dotted" : "map",
                               title: map == nil ? "Your reading graph is empty" : "This map has no books yet",
                               message: map == nil ? "Add books and connect them to see how your reading fits together." : "Add books to arrange them into a map of ideas. Drag books to pin their position.",
                               actions: map == nil ? nil : AnyView(Button("Add Books…") { addingBooks = true }.buttonStyle(.borderedProminent)))
                } else {
                    GeometryReader { geo in canvas(geo.size).onAppear { canvasSize = geo.size }.onChange(of: geo.size) { _, s in canvasSize = s } }
                    legend.padding(14)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            if let id = selected, let b = store.book(id) {
                Divider()
                inspector(b).frame(width: 290)
            }
        }
        .navigationTitle(map?.name ?? "Reading Graph")
        .navigationSubtitle("\(books.count) books · \(links.count) connections")
        .toolbar { toolbar }
        .onAppear(perform: rebuild)
        .onDisappear { sim.stop() }
        .onChange(of: sim.settled) { _, done in
            if done, !didAutoFit { didAutoFit = true; withAnimation(.easeInOut(duration: 0.4)) { fit() } }
        }
        .onChange(of: store.data.links) { _, _ in rebuild() }
        .onChange(of: store.data.books.map(\.id)) { _, _ in rebuild() }
        .onChange(of: map?.bookIDs) { _, _ in rebuild() }
        .onChange(of: showSharedTags) { _, _ in rebuild() }
        .sheet(isPresented: $addingBooks) { if let map { MapBookPicker(map: map) } }
        .sheet(item: $connecting) { ConnectSheet(source: $0) }
    }

    private func rebuild() {
        var saved: [UUID: CGPoint] = [:]
        if let map { for (k, v) in map.positions { if let id = UUID(uuidString: k) { saved[id] = CGPoint(x: v.x, y: v.y) } } }
        let e = links.map { ($0.from, $0.to, 1.0) } + tagEdges.map { ($0.0, $0.1, 0.25) }
        sim.configure(nodes: books.map(\.id), edges: e, saved: saved)
    }

    // MARK: Canvas

    private func toScreen(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: p.x * scale + offset.width + size.width / 2, y: p.y * scale + offset.height + size.height / 2)
    }
    private func toWorld(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: (p.x - offset.width - size.width / 2) / scale, y: (p.y - offset.height - size.height / 2) / scale)
    }
    private func nodeWidth(_ b: Book) -> CGFloat { 34 + CGFloat(min(10, store.annotations(for: b.id).count)) * 2.5 }

    private func canvas(_ size: CGSize) -> some View {
        let focus = neighbors
        let bookByID = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        return ZStack {
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        if panStart == nil { panStart = offset }
                        offset = CGSize(width: panStart!.width + v.translation.width, height: panStart!.height + v.translation.height)
                    }
                    .onEnded { _ in panStart = nil })
                .onTapGesture { selected = nil }

            Canvas { ctx, _ in
                let ink = Color.secondary
                for (a, b, tag) in tagEdges {
                    guard let pa = sim.pos[a], let pb = sim.pos[b] else { continue }
                    var path = Path(); path.move(to: toScreen(pa, size)); path.addLine(to: toScreen(pb, size))
                    ctx.stroke(path, with: .color(ink.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                    _ = tag
                }
                for l in links {
                    guard let pa = sim.pos[l.from], let pb = sim.pos[l.to] else { continue }
                    let a = toScreen(pa, size), b = toScreen(pb, size)
                    let lit = focus.isEmpty || (focus.contains(l.from) && focus.contains(l.to))
                    var path = Path(); path.move(to: a); path.addLine(to: b)
                    let dash: [CGFloat] = l.kind == .contradicts ? [6, 4] : []
                    let col: Color = l.kind == .contradicts ? Palette.series[7] : ink
                    ctx.stroke(path, with: .color(col.opacity(lit ? 0.75 : 0.12)), style: StrokeStyle(lineWidth: lit && !focus.isEmpty ? 2 : 1.5, lineCap: .round, dash: dash))
                    // Arrowhead for directional relationships, stopping at the target node's edge.
                    if l.kind != .related && l.kind != .contradicts, let tb = bookByID[l.to] {
                        let dx = b.x - a.x, dy = b.y - a.y, d = max(1, sqrt(dx * dx + dy * dy))
                        let back = nodeWidth(tb) * scale * 0.95 + 6
                        let tip = CGPoint(x: b.x - dx / d * back, y: b.y - dy / d * back)
                        let ang = atan2(dy, dx), len: CGFloat = 8
                        var head = Path()
                        head.move(to: tip)
                        head.addLine(to: CGPoint(x: tip.x - cos(ang - 0.45) * len, y: tip.y - sin(ang - 0.45) * len))
                        head.addLine(to: CGPoint(x: tip.x - cos(ang + 0.45) * len, y: tip.y - sin(ang + 0.45) * len))
                        head.closeSubpath()
                        ctx.fill(head, with: .color(col.opacity(lit ? 0.75 : 0.12)))
                    }
                    if lit, !focus.isEmpty {
                        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                        ctx.draw(Text(l.kind.label).font(.caption2.weight(.medium)).foregroundStyle(.secondary), at: CGPoint(x: mid.x, y: mid.y - 8))
                    }
                }
                if let ld = linkDrag, let pa = sim.pos[ld.from] {
                    var path = Path(); path.move(to: toScreen(pa, size)); path.addLine(to: ld.to)
                    ctx.stroke(path, with: .color(Palette.series[0]), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
                }
            }
            .allowsHitTesting(false)

            ForEach(books) { b in
                if let p = sim.pos[b.id] {
                    node(b, dim: !focus.isEmpty && !focus.contains(b.id))
                        .position(toScreen(p, size))
                        .gesture(nodeDrag(b, size))
                        .onTapGesture { selected = (selected == b.id ? nil : b.id) }
                        .onHover { hovered = $0 ? b.id : (hovered == b.id ? nil : hovered) }
                        .contextMenu { nodeMenu(b) }
                }
            }
        }
        .clipped()
        .gesture(MagnifyGesture()
            .onChanged { v in
                if zoomStart == nil { zoomStart = scale }
                scale = min(3, max(0.25, zoomStart! * v.magnification))
            }
            .onEnded { _ in zoomStart = nil })
    }

    private func node(_ b: Book, dim: Bool) -> some View {
        let w = nodeWidth(b) * scale
        let isSel = selected == b.id
        return VStack(spacing: 4) {
            CoverView(book: b, width: w)
                .overlay(RoundedRectangle(cornerRadius: max(3, w * 0.04)).strokeBorder(color(b), lineWidth: isSel ? 3 : 2))
                .overlay(alignment: .topTrailing) {
                    if map != nil, map?.positions[b.id.uuidString] != nil {
                        Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(.white).padding(3).background(Circle().fill(.black.opacity(0.45))).offset(x: 4, y: -4)
                    }
                }
            if scale > 0.6 || isSel || hovered == b.id {
                Text(b.title).font(.system(size: 10, weight: isSel ? .semibold : .medium)).lineLimit(2).multilineTextAlignment(.center)
                    .frame(width: max(90, w * 1.6))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .opacity(dim ? 0.25 : 1)
        .animation(.easeOut(duration: 0.15), value: dim)
        .help("\(b.title) — \(b.author)\nOption-drag onto another book to connect")
    }

    private func nodeDrag(_ b: Book, _ size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { v in
                if dragStart == nil {
                    dragStart = sim.pos[b.id]
                    if NSEvent.modifierFlags.contains(.option) { linkDrag = (b.id, .zero) }
                }
                if linkDrag != nil, let start = dragStart {
                    let s = toScreen(start, size)
                    linkDrag = (b.id, CGPoint(x: s.x + v.translation.width, y: s.y + v.translation.height))
                    return
                }
                guard let start = dragStart else { return }
                sim.pinned.insert(b.id)
                sim.pos[b.id] = CGPoint(x: start.x + v.translation.width / scale, y: start.y + v.translation.height / scale)
            }
            .onEnded { _ in
                defer { dragStart = nil; linkDrag = nil }
                if let ld = linkDrag {
                    let w = toWorld(ld.to, size)
                    if let target = books.first(where: { other in
                        guard other.id != b.id, let p = sim.pos[other.id] else { return false }
                        return hypot(p.x - w.x, p.y - w.y) < nodeWidth(other)
                    }) {
                        store.connect(b.id, target.id, kind: .related)
                        selected = b.id
                    }
                    return
                }
                if var m = map, let p = sim.pos[b.id] {
                    m.positions[b.id.uuidString] = MapPoint(x: p.x, y: p.y)
                    store.upsert(m)
                }
                sim.reheat()
            }
    }

    @ViewBuilder private func nodeMenu(_ b: Book) -> some View {
        Button("Open Book") { state.open(book: b.id) }
        Button("Connect to…") { connecting = b }
        if var m = map {
            if m.positions[b.id.uuidString] != nil {
                Button("Unpin") { m.positions[b.id.uuidString] = nil; store.upsert(m); sim.pinned.remove(b.id); sim.reheat() }
            }
            Button("Remove from Map") { m.bookIDs.removeAll { $0 == b.id }; m.positions[b.id.uuidString] = nil; store.upsert(m); if selected == b.id { selected = nil } }
        } else {
            Button("Release") { sim.pinned.remove(b.id); sim.reheat() }
        }
    }

    // MARK: Chrome

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Picker("Color", selection: $colorBy) {
                Text("By Status").tag("status")
                Text("By Tag").tag("tag")
            }
            .fixedSize()
            Toggle(isOn: $showSharedTags) { Label("Shared Tags", systemImage: "tag") }
                .help("Show dotted lines between books that share a tag")
            ControlGroup {
                Button { scale = max(0.25, scale / 1.25) } label: { Label("Zoom Out", systemImage: "minus.magnifyingglass") }
                Button { fit() } label: { Label("Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass") }
                Button { scale = min(3, scale * 1.25) } label: { Label("Zoom In", systemImage: "plus.magnifyingglass") }
            }
            Button {
                if var m = map { m.positions = [:]; store.upsert(m) }
                sim.pinned = []
                rebuild()
            } label: { Label("Re-layout", systemImage: "wand.and.rays") }
                .help(map == nil ? "Release all books and lay out again" : "Unpin all books and lay out again")
            if map != nil {
                Button { addingBooks = true } label: { Label("Add Books", systemImage: "plus") }
            }
        }
    }

    private func fit() {
        let pts = books.compactMap { sim.pos[$0.id] }
        guard let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(), let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else { return }
        let w = max(200, maxX - minX + 160), h = max(200, maxY - minY + 200)
        let avail = CGSize(width: canvasSize.width - 60, height: canvasSize.height - 60)
        scale = min(1.6, max(0.25, min(avail.width / w, avail.height / h)))
        offset = CGSize(width: -(minX + maxX) / 2 * scale, height: -(minY + maxY) / 2 * scale)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            if colorBy == "tag" {
                ForEach(Array(topTags.enumerated()), id: \.offset) { i, t in legendRow(Palette.series[i], t) }
                legendRow(.gray, "other")
            } else {
                ForEach(ReadingStatus.allCases) { legendRow($0.color, $0.label) }
            }
            Divider().frame(width: 120)
            HStack(spacing: 6) { Image(systemName: "arrow.right").font(.caption2); Text("builds on / cites / inspired by") }
            HStack(spacing: 6) { Rectangle().fill(Palette.series[7]).frame(width: 14, height: 2); Text("contradicts") }
            Text("Size = annotations · ⌥-drag to connect").foregroundStyle(.tertiary)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(10)
        .glassSurface(glass, in: RoundedRectangle(cornerRadius: 10)) { RoundedRectangle(cornerRadius: 10).fill(.regularMaterial) }
    }

    private func legendRow(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).strokeBorder(c, lineWidth: 2).frame(width: 10, height: 12); Text(t) }
    }

    // MARK: Inspector

    private func inspector(_ b: Book) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    CoverView(book: b, width: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(b.title).font(.headline)
                        Text(b.author).font(.caption).foregroundStyle(.secondary)
                        Label(b.status.label, systemImage: b.status.symbol).font(.caption).foregroundStyle(b.status.color)
                    }
                }
                HStack {
                    Button("Open Book") { state.open(book: b.id) }.glassButton(glass, prominent: true)
                    Button("Connect…") { connecting = b }.glassButton(glass)
                }
                Divider()
                Text("Connections").font(.subheadline.weight(.semibold))
                let ls = store.links(for: b.id)
                if ls.isEmpty { Text("None yet. ⌥-drag this book onto another to connect them.").font(.caption).foregroundStyle(.secondary) }
                ForEach(ls) { l in
                    let other = store.book(l.from == b.id ? l.to : l.from)
                    VStack(alignment: .leading, spacing: 3) {
                        Menu {
                            ForEach(LinkKind.allCases) { k in
                                Button(k.label) { if let i = store.data.links.firstIndex(where: { $0.id == l.id }) { store.data.links[i].kind = k } }
                            }
                            Divider()
                            Button("Swap Direction") {
                                if let i = store.data.links.firstIndex(where: { $0.id == l.id }) { store.data.links[i].swapDirection() }
                            }
                            Button("Remove Connection", role: .destructive) { store.delete(linkID: l.id) }
                        } label: {
                            Text(l.from == b.id ? "→ \(l.kind.label.lowercased())" : "← \(l.kind.label.lowercased()) this")
                        }
                        .menuStyle(.borderlessButton).font(.caption).fixedSize()
                        Button(other?.title ?? "?") { if let o = other { selected = o.id } }.buttonStyle(.plain).font(.callout.weight(.medium))
                        if !l.note.isEmpty { Text(l.note).font(.caption).foregroundStyle(.secondary) }
                    }
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                }
                let notes = store.annotations(for: b.id)
                if !notes.isEmpty {
                    Divider()
                    Text("Annotations (\(notes.count))").font(.subheadline.weight(.semibold))
                    ForEach(notes.prefix(4)) { a in
                        Text(a.quote.isEmpty ? a.comment : "“\(a.quote)”").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
            .padding(16)
        }
    }
}

// MARK: - Add books to a map

struct MapBookPicker: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State var map: ReadingMap
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search books", text: $search).textFieldStyle(.roundedBorder).padding(14)
            List(store.data.books.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.author.localizedCaseInsensitiveContains(search) || $0.tags.contains(search.lowercased()) }) { b in
                Toggle(isOn: Binding(get: { map.bookIDs.contains(b.id) }, set: { on in
                    if on { map.bookIDs.append(b.id) } else { map.bookIDs.removeAll { $0 == b.id } }
                })) {
                    HStack { CoverView(book: b, width: 22); VStack(alignment: .leading) { Text(b.title); Text(b.author).font(.caption).foregroundStyle(.secondary) } }
                }
                .toggleStyle(.checkbox)
            }
            Divider()
            HStack {
                Button("Add Connected Books") {
                    let ids = Set(map.bookIDs)
                    for l in store.data.links {
                        if ids.contains(l.from), !map.bookIDs.contains(l.to) { map.bookIDs.append(l.to) }
                        if ids.contains(l.to), !map.bookIDs.contains(l.from) { map.bookIDs.append(l.from) }
                    }
                }
                .help("Add every book directly connected to books already in this map")
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Done") { store.upsert(map); dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(width: 460, height: 560)
    }
}
