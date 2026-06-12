#!/usr/bin/env swift
import AppKit
import Foundation

enum IconKind {
    case briefcase
    case person
    case letter(String)
    case plain
}

struct ProfileIcon {
    let name: String
    let kind: IconKind
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    var fillColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

// Avoid corporate / Word-like blues. Work = indigo, Personal = sage.
let palette: [ProfileIcon] = [
    ProfileIcon(name: "profile-0", kind: .briefcase, red: 0.38, green: 0.35, blue: 0.78),
    ProfileIcon(name: "profile-1", kind: .person, red: 0.45, green: 0.68, blue: 0.52),
    ProfileIcon(name: "profile-2", kind: .plain, red: 0.96, green: 0.55, blue: 0.28),
    ProfileIcon(name: "profile-3", kind: .plain, red: 0.58, green: 0.33, blue: 0.86),
    ProfileIcon(name: "profile-4", kind: .plain, red: 0.12, green: 0.68, blue: 0.74),
    ProfileIcon(name: "profile-5", kind: .plain, red: 0.86, green: 0.26, blue: 0.55),
    ProfileIcon(name: "profile-6", kind: .plain, red: 0.93, green: 0.42, blue: 0.31),
    ProfileIcon(name: "profile-7", kind: .plain, red: 0.45, green: 0.50, blue: 0.56),
]

let iconsetEntries: [(name: String, size: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

func repoIconsDir() -> URL {
    let scriptPath = CommandLine.arguments[0]
    let scriptURL = URL(fileURLWithPath: scriptPath).standardizedFileURL
    return scriptURL.deletingLastPathComponent()
}

func roundedRect(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawBackground(_ spec: ProfileIcon, in rect: NSRect, dim: CGFloat) {
    let radius = dim * 0.22
    spec.fillColor.setFill()
    roundedRect(rect, radius: radius).fill()
}

func drawInnerRing(in rect: NSRect, dim: CGFloat) {
    let inset = dim * 0.14
    let inner = rect.insetBy(dx: inset, dy: inset)
    let ringWidth = max(1.0, dim * 0.045)
    let path = roundedRect(inner, radius: inner.width * 0.18)
    path.lineWidth = ringWidth
    NSColor(white: 1.0, alpha: 0.92).setStroke()
    path.stroke()
}

func drawBriefcase(in rect: NSRect, dim: CGFloat) {
    let cx = rect.midX
    let cy = rect.midY - dim * 0.02
    let bodyW = dim * 0.34
    let bodyH = dim * 0.24
    let body = NSRect(x: cx - bodyW / 2, y: cy - bodyH / 2, width: bodyW, height: bodyH)
    let bodyPath = roundedRect(body, radius: dim * 0.04)
    NSColor.white.setFill()
    bodyPath.fill()

    let handleW = dim * 0.18
    let handleH = dim * 0.10
    let handleRect = NSRect(
        x: cx - handleW / 2,
        y: body.maxY - dim * 0.02,
        width: handleW,
        height: handleH
    )
    let handlePath = NSBezierPath()
    handlePath.lineWidth = max(1.2, dim * 0.035)
    handlePath.lineCapStyle = .round
    handlePath.move(to: NSPoint(x: handleRect.minX, y: handleRect.minY + handlePath.lineWidth / 2))
    handlePath.line(to: NSPoint(x: handleRect.minX, y: handleRect.midY))
    handlePath.curve(
        to: NSPoint(x: handleRect.maxX, y: handleRect.midY),
        controlPoint1: NSPoint(x: cx - handleW * 0.15, y: handleRect.maxY),
        controlPoint2: NSPoint(x: cx + handleW * 0.15, y: handleRect.maxY)
    )
    handlePath.line(to: NSPoint(x: handleRect.maxX, y: handleRect.minY + handlePath.lineWidth / 2))
    NSColor.white.setStroke()
    handlePath.stroke()

    let claspW = dim * 0.05
    let claspH = dim * 0.06
    let clasp = NSRect(x: cx - claspW / 2, y: body.midY - claspH / 2, width: claspW, height: claspH)
    NSColor(white: 1.0, alpha: 0.55).setFill()
    roundedRect(clasp, radius: dim * 0.012).fill()
}

func drawPerson(in rect: NSRect, dim: CGFloat) {
    let cx = rect.midX
    let headR = dim * 0.085
    let headY = rect.midY + dim * 0.10
    let head = NSBezierPath(ovalIn: NSRect(
        x: cx - headR,
        y: headY - headR,
        width: headR * 2,
        height: headR * 2
    ))
    NSColor.white.setFill()
    head.fill()

    let shoulderW = dim * 0.30
    let bodyH = dim * 0.18
    let bodyY = headY - headR - dim * 0.02
    let body = NSBezierPath()
    body.move(to: NSPoint(x: cx - shoulderW / 2, y: bodyY))
    body.line(to: NSPoint(x: cx - shoulderW / 2 + dim * 0.04, y: bodyY - bodyH))
    body.line(to: NSPoint(x: cx + shoulderW / 2 - dim * 0.04, y: bodyY - bodyH))
    body.line(to: NSPoint(x: cx + shoulderW / 2, y: bodyY))
    body.close()
    body.fill()
}

func drawLetter(_ letter: String, in rect: NSRect, dim: CGFloat) {
    let fontSize = dim * 0.40
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let stroke = max(0.8, dim * 0.025)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .strokeColor: NSColor(white: 1.0, alpha: 0.35),
        .strokeWidth: -stroke * 2,
    ]
    let text = letter as NSString
    let textSize = text.size(withAttributes: attrs)
    let point = NSPoint(
        x: rect.midX - textSize.width / 2,
        y: rect.midY - textSize.height / 2 - dim * 0.01
    )
    text.draw(at: point, withAttributes: attrs)
}

func drawIcon(_ spec: ProfileIcon, size: Int) -> NSImage {
    let dim = CGFloat(size)
    let image = NSImage(size: NSSize(width: dim, height: dim))
    image.lockFocus()

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: dim, height: dim).fill()

    let inset = dim * 0.08
    let rect = NSRect(x: inset, y: inset, width: dim - inset * 2, height: dim - inset * 2)

    drawBackground(spec, in: rect, dim: dim)
    drawInnerRing(in: rect, dim: dim)

    switch spec.kind {
    case .briefcase:
        drawBriefcase(in: rect, dim: dim)
    case .person:
        drawPerson(in: rect, dim: dim)
    case .letter(let letter):
        drawLetter(letter, in: rect, dim: dim)
    case .plain:
        break
    }

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "generate_icons", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encode failed"])
    }
    try png.write(to: url)
}

func buildIcns(spec: ProfileIcon, outputPath: URL, workDir: URL) throws {
    let fileManager = FileManager.default
    let iconset = workDir.appendingPathComponent("icon.iconset")
    try? fileManager.removeItem(at: iconset)
    try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

    for entry in iconsetEntries {
        let image = drawIcon(spec, size: entry.size)
        try writePNG(image, to: iconset.appendingPathComponent("\(entry.name).png"))
    }

    try? fileManager.removeItem(at: outputPath)

    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    task.arguments = ["-c", "icns", iconset.path, "-o", outputPath.path]
    try task.run()
    task.waitUntilExit()
    if task.terminationStatus != 0 {
        throw NSError(domain: "generate_icons", code: 2, userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
    }
    try? fileManager.removeItem(at: iconset)
}

func parseArgs(_ args: [String]) -> (index: Int?, letter: String?, output: String?) {
    var index: Int?
    var letter: String?
    var output: String?
    var i = 1
    while i < args.count {
        switch args[i] {
        case "--index" where i + 1 < args.count:
            index = Int(args[i + 1])
            i += 2
        case "--letter" where i + 1 < args.count:
            letter = args[i + 1]
            i += 2
        case "--output" where i + 1 < args.count:
            output = args[i + 1]
            i += 2
        default:
            i += 1
        }
    }
    return (index, letter, output)
}

let args = CommandLine.arguments
let (singleIndex, singleLetter, singleOutput) = parseArgs(args)

if let idx = singleIndex, let letter = singleLetter, let output = singleOutput {
    guard idx >= 0 && idx < palette.count else {
        fputs("index out of range: \(idx)\n", stderr)
        exit(1)
    }
    let base = palette[idx]
    let spec = ProfileIcon(
        name: "custom",
        kind: .letter(letter),
        red: base.red,
        green: base.green,
        blue: base.blue
    )
    let outputURL = URL(fileURLWithPath: output).standardizedFileURL
    let workDir = outputURL.deletingLastPathComponent()
    do {
        try buildIcns(spec: spec, outputPath: outputURL, workDir: workDir)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
    exit(0)
}

let iconsDir = repoIconsDir()
let fileManager = FileManager.default

for spec in palette {
    let icnsPath = iconsDir.appendingPathComponent("\(spec.name).icns")
    do {
        try buildIcns(spec: spec, outputPath: icnsPath, workDir: iconsDir)
        print("Created \(icnsPath.lastPathComponent)")
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}
