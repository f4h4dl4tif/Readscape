import AppKit

// Renders Readscape's icon: an open book on a deep-blue squircle, with a small constellation
// of connected nodes rising from its pages (reading + graph).
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let inset = s * 0.098
    let r = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowBlurRadius = s * 0.025; sh.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    sh.shadowColor = NSColor.black.withAlphaComponent(0.35); sh.set()
    NSColor.black.setFill(); bg.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(srgbRed: 0.11, green: 0.36, blue: 0.67, alpha: 1), NSColor(srgbRed: 0.05, green: 0.16, blue: 0.36, alpha: 1)])!
        .draw(in: bg, angle: -90)

    let u = r.width / 100
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: r.minX + x * u, y: r.minY + y * u) }

    // Open book
    let cream = NSColor(srgbRed: 0.99, green: 0.97, blue: 0.92, alpha: 1)
    for side in [-1.0, 1.0] {
        let page = NSBezierPath()
        page.move(to: p(50, 22))
        page.curve(to: p(50 + side * 34, 26), controlPoint1: p(50 + side * 12, 27), controlPoint2: p(50 + side * 24, 22))
        page.line(to: p(50 + side * 34, 50))
        page.curve(to: p(50, 46), controlPoint1: p(50 + side * 24, 46), controlPoint2: p(50 + side * 12, 51))
        page.close()
        NSGraphicsContext.saveGraphicsState()
        let ps = NSShadow(); ps.shadowBlurRadius = 2 * u; ps.shadowOffset = NSSize(width: 0, height: -u); ps.shadowColor = NSColor.black.withAlphaComponent(0.3); ps.set()
        cream.setFill(); page.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor(srgbRed: 0.16, green: 0.47, blue: 0.84, alpha: 0.35).setStroke()
        for i in 0..<3 {
            let y = CGFloat(41 - i * 6)
            let line = NSBezierPath()
            line.move(to: p(50 + side * 7, y)); line.line(to: p(50 + side * 27, y + 1.5))
            line.lineWidth = 1.6 * u; line.lineCapStyle = .round; line.stroke()
        }
    }

    // Constellation
    let nodes = [p(50, 58), p(30, 70), p(68, 72), p(44, 82), p(76, 86)]
    let edges = [(0, 1), (0, 2), (1, 3), (2, 3), (2, 4)]
    NSColor.white.withAlphaComponent(0.55).setStroke()
    for (a, b) in edges {
        let l = NSBezierPath(); l.move(to: nodes[a]); l.line(to: nodes[b]); l.lineWidth = 1.4 * u; l.stroke()
    }
    let colors = [NSColor(srgbRed: 0.93, green: 0.63, blue: 0.0, alpha: 1), NSColor(srgbRed: 0.11, green: 0.69, blue: 0.48, alpha: 1),
                  NSColor(srgbRed: 0.92, green: 0.41, blue: 0.20, alpha: 1), NSColor(srgbRed: 0.53, green: 0.71, blue: 0.94, alpha: 1), NSColor.white]
    for (i, n) in nodes.enumerated() {
        let rad = (i == 0 ? 5.0 : 3.6) * u
        let dot = NSBezierPath(ovalIn: NSRect(x: n.x - rad, y: n.y - rad, width: rad * 2, height: rad * 2))
        colors[i].setFill(); dot.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
