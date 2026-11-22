import SwiftUI

/// Real cover if we have one, otherwise a typeset cloth-style cover generated from the title.
struct CoverView: View {
    let book: Book
    var width: CGFloat = 120
    var height: CGFloat { width * 1.5 }

    var body: some View {
        Group {
            if let file = book.coverFile, let img = CoverCache.shared.image(file) {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                generated
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: max(3, width * 0.04)))
        .overlay(RoundedRectangle(cornerRadius: max(3, width * 0.04)).strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: width * 0.04, y: width * 0.02)
    }

    private var generated: some View {
        let base = Color(hue: book.coverHue, saturation: 0.42, brightness: 0.52)
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [base, Color(hue: book.coverHue, saturation: 0.5, brightness: 0.36)], startPoint: .top, endPoint: .bottom)
            Rectangle().fill(.black.opacity(0.16)).frame(width: width * 0.06)   // spine shadow
            VStack(alignment: .leading, spacing: width * 0.05) {
                Rectangle().fill(.white.opacity(0.5)).frame(width: width * 0.3, height: max(1, width * 0.012))
                Text(book.title)
                    .font(.system(size: max(8, width * 0.115), weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(5)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                Text(book.author)
                    .font(.system(size: max(6, width * 0.075), weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
            }
            .padding(.leading, width * 0.14).padding([.trailing, .vertical], width * 0.1)
        }
    }
}

struct StarRating: View {
    @Binding var rating: Int
    var size: CGFloat = 14
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= rating ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(i <= rating ? Color.orange : Color.secondary.opacity(0.5))
                    .onTapGesture { rating = (rating == i ? 0 : i) }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Rating \(rating) of 5")
        .accessibilityAdjustableAction { dir in
            if dir == .increment { rating = min(5, rating + 1) } else { rating = max(0, rating - 1) }
        }
    }
}

struct TagChip: View {
    let text: String
    var onRemove: (() -> Void)?
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            if let onRemove {
                Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }.buttonStyle(.plain)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(.quaternary, in: Capsule())
    }
}

struct TagEditor: View {
    @Binding var tags: [String]
    var suggestions: [String] = []
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { t in TagChip(text: t) { tags.removeAll { $0 == t } } }
                }
            }
            HStack {
                TextField("Add tag", text: $draft).textFieldStyle(.roundedBorder).onSubmit(commit)
                let matches = suggestions.filter { !tags.contains($0) && (draft.isEmpty || $0.localizedCaseInsensitiveContains(draft)) }.prefix(6)
                if !matches.isEmpty {
                    Menu("Suggestions") { ForEach(Array(matches), id: \.self) { s in Button(s) { tags.append(s); draft = "" } } }
                        .menuStyle(.borderlessButton).fixedSize()
                }
            }
        }
    }

    private func commit() {
        let t = draft.trimmingCharacters(in: .whitespaces).lowercased()
        if !t.isEmpty, !tags.contains(t) { tags.append(t) }
        draft = ""
    }
}

/// Wrapping horizontal layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let r = arrange(width: bounds.width, subviews: subviews)
        for (i, p) in r.points.enumerated() { subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified) }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var pts: [CGPoint] = []; var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0; var maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            pts.append(CGPoint(x: x, y: y))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
        }
        return (pts, CGSize(width: maxX, height: y + rowH))
    }
}

struct ProgressBar: View {
    let value: Double
    var color: Color = Palette.series[0]
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.empty)
                Capsule().fill(color).frame(width: max(value > 0 ? 4 : 0, g.size.width * value))
            }
        }
        .frame(height: 4)
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actions: AnyView?
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 44, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.title3.weight(.semibold))
            Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            if let actions { actions.padding(.top, 4) }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Date {
    var short: String { formatted(date: .abbreviated, time: .omitted) }
}
