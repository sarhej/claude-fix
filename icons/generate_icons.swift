#!/usr/bin/env swift
// claude-fix profile icons.
//
//   swift generate_icons.swift
//       Regenerate the flat fallback icons in this folder from glyphs.json.
//
//   generate_icons --app /Applications/Claude.app --output applet.icns
//       [--symbol NAME | --letter L | --no-badge] [--color NAME | #RRGGBB]
//       [--assets-car Assets.car] [--symbols glyphs.json]
//       Recolor the app's own icon and add a badge. Because the icon is read from the
//       installed app, launchers follow Claude's icon when it changes. With --assets-car
//       and Xcode 26's actool available, also build a layered icon so macOS can draw its
//       Default, Dark, Clear and Tinted styles.
//
//   generate_icons --index N --letter L --output out.icns
//       Flat letter icon in palette color N.
import AppKit
import Foundation

// MARK: - glyphs.json

struct SymbolFile: Decodable {
    let colors: [String: [Double]]
    let palette: [String]
    let symbols: [Symbol]
}

struct Symbol: Decodable {
    let name: String
    let color: String
    let shapes: [Shape]
}

struct Shape: Decodable {
    let fill: Bool?
    let stroke: Double?
    let alpha: Double?
    let background: Bool?
    let parts: [Part]
}

struct Part: Decodable {
    let d: [[PathValue]]?
    let circle: [Double]?
    let ellipse: [Double]?
    let rrect: [Double]?
    let star: [Double]?
}

enum PathValue: Decodable {
    case op(String)
    case number(Double)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .op(try container.decode(String.self))
        }
    }

    var number: CGFloat {
        if case .number(let value) = self { return CGFloat(value) }
        return 0
    }

    var op: String {
        if case .op(let value) = self { return value }
        return ""
    }
}

struct RGB {
    var r: Double
    var g: Double
    var b: Double

    var color: NSColor { NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1) }
}

func fail(_ message: String) -> Never {
    fputs("generate_icons: \(message)\n", stderr)
    exit(1)
}

func loadSymbols(_ url: URL) -> SymbolFile {
    do {
        return try JSONDecoder().decode(SymbolFile.self, from: Data(contentsOf: url))
    } catch {
        fail("\(url.path): \(error.localizedDescription)")
    }
}

func namedColor(_ name: String, in file: SymbolFile) -> RGB? {
    guard let c = file.colors[name.lowercased()], c.count == 3 else { return nil }
    return RGB(r: c[0], g: c[1], b: c[2])
}

func parseColor(_ value: String, in file: SymbolFile) -> RGB? {
    if let named = namedColor(value, in: file) { return named }
    var hex = value
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard hex.count == 6, let n = UInt32(hex, radix: 16) else { return nil }
    return RGB(r: Double((n >> 16) & 0xff) / 255, g: Double((n >> 8) & 0xff) / 255, b: Double(n & 0xff) / 255)
}

// MARK: - Drawing

/// Builds a symbol's path. `map` places a point given in symbol units; `scale` converts lengths.
func symbolPath(_ parts: [Part], map: (CGFloat, CGFloat) -> NSPoint, scale: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    for part in parts {
        if let c = part.circle?.map({ CGFloat($0) }), c.count == 3 {
            let center = map(c[0], c[1])
            let r = c[2] * scale
            path.appendOval(in: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        } else if let e = part.ellipse?.map({ CGFloat($0) }), e.count == 4 {
            let center = map(e[0], e[1])
            path.appendOval(in: NSRect(x: center.x - e[2] * scale, y: center.y - e[3] * scale,
                                       width: e[2] * 2 * scale, height: e[3] * 2 * scale))
        } else if let r = part.rrect?.map({ CGFloat($0) }), r.count == 5 {
            let origin = map(r[0], r[1])
            path.appendRoundedRect(NSRect(x: origin.x, y: origin.y, width: r[2] * scale, height: r[3] * scale),
                                   xRadius: r[4] * scale, yRadius: r[4] * scale)
        } else if let s = part.star?.map({ CGFloat($0) }), s.count == 5 {
            let points = max(3, Int(s[4]))
            for i in 0..<(points * 2) {
                let angle = CGFloat.pi / 2 + CGFloat(i) * CGFloat.pi / CGFloat(points)
                let radius = i % 2 == 0 ? s[2] : s[3]
                let p = map(s[0] + radius * cos(angle), s[1] + radius * sin(angle))
                if i == 0 { path.move(to: p) } else { path.line(to: p) }
            }
            path.close()
        } else if let ops = part.d {
            for op in ops {
                let n = op.dropFirst().map { $0.number }
                switch op.first?.op ?? "" {
                case "M" where n.count >= 2: path.move(to: map(n[0], n[1]))
                case "L" where n.count >= 2: path.line(to: map(n[0], n[1]))
                case "C" where n.count >= 6:
                    path.curve(to: map(n[4], n[5]), controlPoint1: map(n[0], n[1]), controlPoint2: map(n[2], n[3]))
                case "Z": path.close()
                default: break
                }
            }
        }
    }
    return path
}

func drawSymbol(_ symbol: Symbol, map: (CGFloat, CGFloat) -> NSPoint, scale: CGFloat, ink: NSColor, background: NSColor) {
    for shape in symbol.shapes {
        let path = symbolPath(shape.parts, map: map, scale: scale)
        let color = shape.background == true ? background : ink.withAlphaComponent(CGFloat(shape.alpha ?? 1))
        if let width = shape.stroke {
            path.lineWidth = max(1, CGFloat(width) * scale)
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            color.setStroke()
            path.stroke()
        } else {
            path.windingRule = .evenOdd
            color.setFill()
            path.fill()
        }
    }
}

func drawLetter(_ letter: String, center: NSPoint, height: CGFloat, color: NSColor) {
    let font = NSFont.systemFont(ofSize: height, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let text = letter as NSString
    let width = text.size(withAttributes: attrs).width
    // Center the capitals: the draw origin sits at the descender line.
    text.draw(at: NSPoint(x: center.x - width / 2, y: center.y - font.capHeight / 2 + font.descender), withAttributes: attrs)
}

/// An RGBA bitmap with a drawing context; `draw` receives the size in points.
func canvas(_ size: Int, _ draw: (CGFloat) -> Void) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: size * 4, bitsPerPixel: 32),
          let context = NSGraphicsContext(bitmapImageRep: rep) else {
        fail("could not create a \(size)px bitmap")
    }
    rep.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    draw(CGFloat(size))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func pngData(_ rep: NSBitmapImageRep) -> Data {
    guard let data = rep.representation(using: .png, properties: [:]) else { fail("PNG encoding failed") }
    return data
}

func run(_ tool: String, _ arguments: [String]) -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: tool)
    task.arguments = arguments
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do { try task.run() } catch { return false }
    task.waitUntilExit()
    return task.terminationStatus == 0
}

let iconsetEntries: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("claude-fix-icon-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func writeIcns(to output: URL, draw: (CGFloat) -> Void) {
    let work = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: work) }
    let iconset = work.appendingPathComponent("icon.iconset")
    do {
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for entry in iconsetEntries {
            try pngData(canvas(entry.size, draw)).write(to: iconset.appendingPathComponent("\(entry.name).png"))
        }
    } catch {
        fail(error.localizedDescription)
    }
    try? FileManager.default.removeItem(at: output)
    if !run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", output.path]) {
        fail("iconutil failed for \(output.path)")
    }
}

// MARK: - Flat icons (fallback when an app icon can't be recolored)

func drawFlat(dim: CGFloat, color: RGB, symbol: Symbol?, letter: String?) {
    let inset = dim * 0.08
    let rect = NSRect(x: inset, y: inset, width: dim - inset * 2, height: dim - inset * 2)
    color.color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: dim * 0.22, yRadius: dim * 0.22).fill()

    let inner = rect.insetBy(dx: dim * 0.14, dy: dim * 0.14)
    let ring = NSBezierPath(roundedRect: inner, xRadius: inner.width * 0.18, yRadius: inner.width * 0.18)
    ring.lineWidth = max(1, dim * 0.045)
    NSColor(white: 1, alpha: 0.92).setStroke()
    ring.stroke()

    if let symbol = symbol {
        drawSymbol(symbol, map: { NSPoint(x: $0 * dim, y: $1 * dim) }, scale: dim, ink: .white, background: color.color)
    } else if let letter = letter {
        drawLetter(letter, center: NSPoint(x: rect.midX, y: rect.midY), height: dim * 0.40, color: .white)
    }
}

// MARK: - Recolored app icon

struct HSV {
    var h: Double
    var s: Double
    var v: Double
}

func toHSV(_ r: Double, _ g: Double, _ b: Double) -> HSV {
    let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
    var h = 0.0
    if d > 0 {
        if mx == r { h = (g - b) / d } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h /= 6
        if h < 0 { h += 1 }
    }
    return HSV(h: h, s: mx == 0 ? 0 : d / mx, v: mx)
}

func toRGB(_ c: HSV) -> (Double, Double, Double) {
    let h = (c.h - floor(c.h)) * 6
    let i = Int(floor(h)) % 6, f = h - floor(h)
    let p = c.v * (1 - c.s), q = c.v * (1 - c.s * f), t = c.v * (1 - c.s * (1 - f))
    switch i {
    case 0: return (c.v, t, p)
    case 1: return (q, c.v, p)
    case 2: return (p, c.v, t)
    case 3: return (p, q, c.v)
    case 4: return (t, p, c.v)
    default: return (c.v, p, q)
    }
}

func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = min(1, max(0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)
}

struct Pixels {
    let rep: NSBitmapImageRep
    let count: Int
    let data: UnsafeMutablePointer<UInt8>

    init(_ rep: NSBitmapImageRep) {
        guard let data = rep.bitmapData else { fail("bitmap has no data") }
        self.rep = rep
        self.count = rep.pixelsWide * rep.pixelsHigh
        self.data = data
    }

    /// Straight (not premultiplied) color and alpha, 0...1.
    func get(_ i: Int) -> (r: Double, g: Double, b: Double, a: Double) {
        let a = Double(data[i * 4 + 3]) / 255
        guard a > 0 else { return (0, 0, 0, 0) }
        return (min(1, Double(data[i * 4]) / 255 / a), min(1, Double(data[i * 4 + 1]) / 255 / a),
                min(1, Double(data[i * 4 + 2]) / 255 / a), a)
    }

    func set(_ i: Int, _ r: Double, _ g: Double, _ b: Double, _ a: Double) {
        func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (v * a * 255).rounded()))) }
        data[i * 4] = byte(r)
        data[i * 4 + 1] = byte(g)
        data[i * 4 + 2] = byte(b)
        data[i * 4 + 3] = UInt8(max(0, min(255, (a * 255).rounded())))
    }
}

/// The icon's brand color: the most common strongly saturated hue.
func dominantColor(_ px: Pixels) -> HSV? {
    var bins = [Double](repeating: 0, count: 36)
    var opaque = 0
    for i in 0..<px.count {
        let p = px.get(i)
        guard p.a > 0.5 else { continue }
        opaque += 1
        let c = toHSV(p.r, p.g, p.b)
        if c.s > 0.35 && c.v > 0.25 { bins[Int(c.h * 36) % 36] += c.s }
    }
    guard let best = bins.indices.max(by: { bins[$0] < bins[$1] }),
          bins.reduce(0, +) > Double(opaque) * 0.01 else { return nil }
    var x = 0.0, y = 0.0, s = 0.0, v = 0.0, n = 0.0
    for i in 0..<px.count {
        let p = px.get(i)
        guard p.a > 0.5 else { continue }
        let c = toHSV(p.r, p.g, p.b)
        guard c.s > 0.35 && c.v > 0.25 else { continue }
        let distance = abs(Int(c.h * 36) % 36 - best)
        guard min(distance, 36 - distance) <= 1 else { continue }
        x += cos(2 * .pi * c.h)
        y += sin(2 * .pi * c.h)
        s += c.s
        v += c.v
        n += 1
    }
    guard n > 0 else { return nil }
    var h = atan2(y, x) / (2 * .pi)
    if h < 0 { h += 1 }
    return HSV(h: h, s: s / n, v: v / n)
}

/// Moves the brand color to `target` and gives everything else the target's hue at its
/// own saturation, so cream stays a pale tint and shading survives. Returns, per pixel,
/// how much it belongs to the brand-colored foreground.
func recolor(_ px: Pixels, to target: RGB) -> [Double] {
    let t = toHSV(target.r, target.g, target.b)
    let source = dominantColor(px)
    var weights = [Double](repeating: 0, count: px.count)
    for i in 0..<px.count {
        let p = px.get(i)
        guard p.a > 0 else { continue }
        let c = toHSV(p.r, p.g, p.b)
        var out: HSV
        if let s0 = source {
            var d = abs(c.h - s0.h)
            d = min(d, 1 - d)
            let w = (1 - smoothstep(0.06, 0.14, d)) * smoothstep(0.15, 0.35, c.s)
            weights[i] = w
            let mapped = HSV(h: t.h + (c.h - s0.h), s: min(1, c.s * t.s / max(s0.s, 0.01)),
                             v: min(1, c.v * t.v / max(s0.v, 0.01)))
            out = HSV(h: w > 0.5 ? mapped.h : t.h, s: c.s * (1 - w) + mapped.s * w, v: c.v * (1 - w) + mapped.v * w)
        } else {
            out = HSV(h: t.h, s: max(c.s, t.s * 0.35), v: c.v)
        }
        let rgb = toRGB(out)
        px.set(i, rgb.0, rgb.1, rgb.2, p.a)
    }
    return weights
}

/// Bounds of the visible icon, in points with the origin at the bottom left.
func opaqueBounds(_ px: Pixels) -> NSRect {
    let w = px.rep.pixelsWide, h = px.rep.pixelsHigh
    var minX = w, minY = h, maxX = -1, maxY = -1
    for row in 0..<h {
        for col in 0..<w where px.data[(row * w + col) * 4 + 3] > 25 {
            minX = min(minX, col)
            maxX = max(maxX, col)
            minY = min(minY, h - 1 - row)
            maxY = max(maxY, h - 1 - row)
        }
    }
    guard maxX >= minX else { return NSRect(x: 0, y: 0, width: w, height: h) }
    return NSRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

enum Badge {
    case symbol(Symbol)
    case letter(String)
    case none
}

/// A white disc in the bottom-right corner of `bounds`, holding the symbol or letter in `color`.
func drawBadge(_ badge: Badge, color: RGB, in bounds: NSRect, canvasSize: CGFloat) {
    if case .none = badge { return }
    let diameter = bounds.width * 0.40
    let center = NSPoint(x: min(canvasSize - diameter / 2 - 2, bounds.maxX - diameter * 0.36),
                         y: max(diameter / 2 + 2, bounds.minY + diameter * 0.36))
    let disc = NSRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -diameter * 0.035)
    shadow.shadowBlurRadius = diameter * 0.09
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: disc).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Keep light colors readable on white.
    var ink = toHSV(color.r, color.g, color.b)
    if ink.v > 0.8 && ink.s < 0.5 { ink.v = 0.6 }
    let rgb = toRGB(ink)
    let inkColor = RGB(r: rgb.0, g: rgb.1, b: rgb.2).color

    switch badge {
    case .symbol(let symbol):
        let k = diameter * 1.62
        drawSymbol(symbol, map: { NSPoint(x: center.x + ($0 - 0.5) * k, y: center.y + ($1 - 0.5) * k) },
                   scale: k, ink: inkColor, background: .white)
    case .letter(let letter):
        drawLetter(letter, center: center, height: diameter * 0.56, color: inkColor)
    case .none:
        break
    }
}

func appIcon(_ path: String, size: Int) -> NSBitmapImageRep {
    guard FileManager.default.fileExists(atPath: path) else { fail("app not found: \(path)") }
    let icon = NSWorkspace.shared.icon(forFile: path)
    return canvas(size) { dim in
        icon.draw(in: NSRect(x: 0, y: 0, width: dim, height: dim), from: .zero, operation: .sourceOver, fraction: 1)
    }
}

/// Writes a layered Icon Composer file and compiles it with actool. macOS 26 draws the
/// Default, Dark, Clear and Tinted styles from the layers. Needs Xcode 26; returns false otherwise.
func buildAssetsCar(foreground: NSBitmapImageRep, fill: RGB, output: URL) -> Bool {
    guard run("/usr/bin/xcrun", ["--find", "actool"]) else { return false }
    let work = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: work) }
    let bundle = work.appendingPathComponent("AppIcon.icon")
    let assets = bundle.appendingPathComponent("Assets")
    let compiled = work.appendingPathComponent("compiled")
    let json = """
    {
      "fill" : { "solid" : "srgb:\(String(format: "%.5f,%.5f,%.5f", fill.r, fill.g, fill.b)),1.00000" },
      "groups" : [ { "layers" : [ { "image-name" : "foreground.png", "name" : "foreground" } ] } ],
      "supported-platforms" : { "squares" : "shared" }
    }
    """
    do {
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
        try pngData(foreground).write(to: assets.appendingPathComponent("foreground.png"))
        try json.write(to: bundle.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
    } catch {
        return false
    }
    let ok = run("/usr/bin/xcrun", [
        "actool", bundle.path, "--compile", compiled.path, "--platform", "macosx",
        "--minimum-deployment-target", "11.0", "--app-icon", "AppIcon", "--include-all-app-icons",
        "--output-partial-info-plist", work.appendingPathComponent("partial.plist").path,
    ])
    let car = compiled.appendingPathComponent("Assets.car")
    guard ok, FileManager.default.fileExists(atPath: car.path) else { return false }
    try? FileManager.default.removeItem(at: output)
    return (try? FileManager.default.copyItem(at: car, to: output)) != nil
}

func renderAppIcon(app: String, color: RGB, badge: Badge, output: URL, assetsCar: URL?) {
    let size = 1024
    let master = appIcon(app, size: size)
    let px = Pixels(master)
    let weights = recolor(px, to: color)
    let bounds = opaqueBounds(px)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(master)

    writeIcns(to: output) { dim in
        image.draw(in: NSRect(x: 0, y: 0, width: dim, height: dim), from: .zero, operation: .sourceOver, fraction: 1)
        let scale = dim / CGFloat(size)
        let scaled = NSRect(x: bounds.minX * scale, y: bounds.minY * scale,
                            width: bounds.width * scale, height: bounds.height * scale)
        drawBadge(badge, color: color, in: scaled, canvasSize: dim)
    }

    guard let assetsCar = assetsCar else { return }
    // Layered version: the brand-colored parts and the badge become the foreground, cropped
    // to the icon's own bounds because Icon Composer artwork fills the whole canvas.
    var fill = (r: 0.0, g: 0.0, b: 0.0, n: 0.0)
    for i in 0..<px.count where weights[i] < 0.05 {
        let p = px.get(i)
        guard p.a > 0.9 else { continue }
        fill = (fill.r + p.r, fill.g + p.g, fill.b + p.b, fill.n + 1)
    }
    let background = fill.n > 0 ? RGB(r: fill.r / fill.n, g: fill.g / fill.n, b: fill.b / fill.n) : color
    // Mask a fresh copy: the master may already be cached as an image from drawing the .icns.
    let masked = canvas(size) { dim in
        image.draw(in: NSRect(x: 0, y: 0, width: dim, height: dim), from: .zero, operation: .copy, fraction: 1)
    }
    let maskedPx = Pixels(masked)
    for i in 0..<maskedPx.count {
        let p = maskedPx.get(i)
        maskedPx.set(i, p.r, p.g, p.b, p.a * weights[i])
    }
    let layer = NSImage(size: NSSize(width: size, height: size))
    layer.addRepresentation(masked)
    // Crop to a square around the visible icon, so a shadow or odd shape doesn't shift it.
    let side = max(bounds.width, bounds.height)
    let crop = NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    let foreground = canvas(size) { dim in
        let k = dim / side
        layer.draw(in: NSRect(x: -crop.minX * k, y: -crop.minY * k, width: CGFloat(size) * k, height: CGFloat(size) * k),
                   from: .zero, operation: .sourceOver, fraction: 1)
        // Keep the badge inside the rounded mask macOS applies to layered icons.
        drawBadge(badge, color: color, in: NSRect(x: 0, y: 0, width: dim, height: dim).insetBy(dx: dim * 0.09, dy: dim * 0.09),
                  canvasSize: dim)
    }
    if !buildAssetsCar(foreground: foreground, fill: background, output: assetsCar) {
        fputs("generate_icons: skipped the layered icon (needs Xcode 26's actool)\n", stderr)
    }
}

// MARK: - Command line

var options: [String: String] = [:]
var flags = Set<String>()
var index = 1
let args = CommandLine.arguments
while index < args.count {
    let arg = args[index]
    if arg == "--no-badge" {
        flags.insert(arg)
        index += 1
    } else if arg.hasPrefix("--"), index + 1 < args.count {
        options[arg] = args[index + 1]
        index += 2
    } else {
        fail("unexpected argument: \(arg)")
    }
}

let here = URL(fileURLWithPath: args[0]).standardizedFileURL.deletingLastPathComponent()
let file = loadSymbols(options["--symbols"].map { URL(fileURLWithPath: $0) } ?? here.appendingPathComponent("glyphs.json"))

func symbolNamed(_ name: String) -> Symbol {
    guard let symbol = file.symbols.first(where: { $0.name == name.lowercased() }) else { fail("unknown symbol: \(name)") }
    return symbol
}

func paletteColor(_ index: Int) -> RGB {
    guard file.palette.indices.contains(index), let color = namedColor(file.palette[index], in: file) else {
        fail("palette index out of range: \(index)")
    }
    return color
}

if let app = options["--app"] {
    guard let output = options["--output"] else { fail("--output is required") }
    var badge = Badge.none
    var color: RGB?
    if let name = options["--symbol"] {
        let symbol = symbolNamed(name)
        badge = .symbol(symbol)
        color = namedColor(symbol.color, in: file)
    } else if let letter = options["--letter"] {
        badge = .letter(letter)
    }
    if flags.contains("--no-badge") { badge = .none }
    if let value = options["--color"] {
        guard let parsed = parseColor(value, in: file) else { fail("unknown color: \(value)") }
        color = parsed
    }
    guard let target = color else { fail("--color is required with --letter or --no-badge") }
    renderAppIcon(app: app, color: target, badge: badge, output: URL(fileURLWithPath: output),
                  assetsCar: options["--assets-car"].map { URL(fileURLWithPath: $0) })
    exit(0)
}

if let indexValue = options["--index"], let letter = options["--letter"], let output = options["--output"] {
    guard let paletteIndex = Int(indexValue) else { fail("bad --index: \(indexValue)") }
    let color = paletteColor(paletteIndex)
    writeIcns(to: URL(fileURLWithPath: output)) { drawFlat(dim: $0, color: color, symbol: nil, letter: letter) }
    exit(0)
}

// No arguments: regenerate the flat icons shipped in icons/.
for i in file.palette.indices {
    let symbol: Symbol? = i == 0 ? symbolNamed("work") : (i == 1 ? symbolNamed("personal") : nil)
    let color = paletteColor(i)
    writeIcns(to: here.appendingPathComponent("profile-\(i).icns")) { drawFlat(dim: $0, color: color, symbol: symbol, letter: nil) }
    print("Created profile-\(i).icns")
}
for symbol in file.symbols where symbol.name != "work" && symbol.name != "personal" {
    guard let color = namedColor(symbol.color, in: file) else { fail("unknown color for \(symbol.name)") }
    writeIcns(to: here.appendingPathComponent("\(symbol.name).icns")) { drawFlat(dim: $0, color: color, symbol: symbol, letter: nil) }
    print("Created \(symbol.name).icns")
}
