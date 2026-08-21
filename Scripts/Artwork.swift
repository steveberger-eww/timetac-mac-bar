// Draws the app icon and the disk image backdrop, so neither has to live in the repo as a binary
// blob nobody can diff. Run by `make artwork`; output lands in .build/artwork.
//
//   swiftc -O Scripts/Artwork.swift -o .build/artwork-gen && .build/artwork-gen .build/artwork
//
// The motif is the one the status item already uses: a ring counting round, and a filled dot for
// "a tracking is running".

import AppKit

// MARK: - Palette

enum Palette {
    static let slateTop = CGColor(red: 0.180, green: 0.239, blue: 0.318, alpha: 1)
    static let slateBottom = CGColor(red: 0.075, green: 0.110, blue: 0.157, alpha: 1)
    static let running = CGColor(red: 0.204, green: 0.780, blue: 0.349, alpha: 1)
    static let track = CGColor(red: 1, green: 1, blue: 1, alpha: 0.16)

    static let paperTop = CGColor(red: 0.984, green: 0.988, blue: 0.992, alpha: 1)
    static let paperBottom = CGColor(red: 0.925, green: 0.941, blue: 0.961, alpha: 1)
    static let ink = NSColor(calibratedRed: 0.114, green: 0.161, blue: 0.224, alpha: 1)
    static let inkSoft = NSColor(calibratedRed: 0.427, green: 0.475, blue: 0.541, alpha: 1)
    static let arrow = CGColor(red: 0.667, green: 0.706, blue: 0.769, alpha: 1)
}

// MARK: - Canvas

/// A pixel buffer to draw into, written out as PNG.
func render(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // AppKit text drawing needs the context to be the current one.
    let graphics = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    body(context)
    NSGraphicsContext.restoreGraphicsState()

    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: image.width, height: image.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw Failure("Couldn't encode \(url.lastPathComponent)")
    }
    try data.write(to: url)
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func gradient(_ context: CGContext, from top: CGColor, to bottom: CGColor, in rect: CGRect) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let gradient = CGGradient(
        colorsSpace: space, colors: [bottom, top] as CFArray, locations: [0, 1]
    ) else { return }
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.minY),
        end: CGPoint(x: rect.midX, y: rect.maxY),
        options: []
    )
}

// MARK: - App icon

/// One `size`×`size` rendering of the icon. Everything is expressed as a fraction of `size` so the
/// 16pt and the 1024pt version are the same drawing.
func drawIcon(_ context: CGContext, size: CGFloat) {
    context.setShouldAntialias(true)

    // macOS icons sit in a smaller square than their canvas; matching that keeps it from looking
    // oversized next to everything else in Finder.
    let inset = size * 0.086
    let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let corner = plate.width * 0.2237

    context.saveGState()
    context.addPath(CGPath(roundedRect: plate, cornerWidth: corner, cornerHeight: corner, transform: nil))
    context.clip()
    gradient(context, from: Palette.slateTop, to: Palette.slateBottom, in: plate)
    context.restoreGState()

    let centre = CGPoint(x: plate.midX, y: plate.midY)
    let radius = plate.width * 0.275
    let stroke = plate.width * 0.082

    context.setLineWidth(stroke)
    context.setLineCap(.round)

    // Full ring, dimmed: the part of the hour still to come.
    context.setStrokeColor(Palette.track)
    context.addArc(center: centre, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    context.strokePath()

    // Elapsed sweep, clockwise from twelve o'clock.
    context.setStrokeColor(Palette.running)
    context.addArc(
        center: centre,
        radius: radius,
        startAngle: .pi / 2,
        endAngle: .pi / 2 - .pi * 1.42,
        clockwise: true
    )
    context.strokePath()

    // The status dot itself.
    let dot = plate.width * 0.105
    context.setFillColor(Palette.running)
    context.fillEllipse(in: CGRect(x: centre.x - dot, y: centre.y - dot, width: dot * 2, height: dot * 2))
}

func writeIconset(to directory: URL) throws -> URL {
    let iconset = directory.appendingPathComponent("AppIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let pixels = points * scale
            guard let image = render(width: pixels, height: pixels, {
                drawIcon($0, size: CGFloat(pixels))
            }) else { throw Failure("Couldn't render the \(pixels)px icon") }

            let suffix = scale == 1 ? "" : "@2x"
            try write(image, to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        }
    }
    return iconset
}

// MARK: - Disk image backdrop

/// Window is 600×400pt; `scale` renders the same drawing for a retina representation.
func drawBackdrop(_ context: CGContext, scale: CGFloat) {
    let width = 600 * scale
    let height = 400 * scale
    gradient(context, from: Palette.paperTop, to: Palette.paperBottom,
             in: CGRect(x: 0, y: 0, width: width, height: height))

    // Sits level with the two icons, clear of both.
    let midY = height - 205 * scale
    let start = 246 * scale
    let end = 354 * scale

    context.setStrokeColor(Palette.arrow)
    context.setLineWidth(3 * scale)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: start, y: midY))
    context.addLine(to: CGPoint(x: end, y: midY))
    context.strokePath()

    let head = 11 * scale
    context.move(to: CGPoint(x: end - head, y: midY + head * 0.8))
    context.addLine(to: CGPoint(x: end, y: midY))
    context.addLine(to: CGPoint(x: end - head, y: midY - head * 0.8))
    context.strokePath()

    text("TimeTacBar", at: CGPoint(x: width / 2, y: height - 74 * scale),
         font: .systemFont(ofSize: 23 * scale, weight: .semibold), colour: Palette.ink)
    text("Drag it into your Applications folder", at: CGPoint(x: width / 2, y: height - 104 * scale),
         font: .systemFont(ofSize: 13 * scale, weight: .regular), colour: Palette.inkSoft)
}

/// Draws horizontally centred on `point`, which is the text's top edge.
func text(_ string: String, at point: CGPoint, font: NSFont, colour: NSColor) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
    let attributed = NSAttributedString(string: string, attributes: attributes)
    let size = attributed.size()
    attributed.draw(at: NSPoint(x: point.x - size.width / 2, y: point.y - size.height))
}

// MARK: - Entry point

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write("usage: artwork-gen <output-directory>\n".data(using: .utf8)!)
    exit(2)
}

let output = URL(fileURLWithPath: arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let iconset = try writeIconset(to: output)

for scale in [1, 2] {
    guard let image = render(width: 600 * scale, height: 400 * scale, {
        drawBackdrop($0, scale: CGFloat(scale))
    }) else { throw Failure("Couldn't render the backdrop at \(scale)x") }

    let suffix = scale == 1 ? "" : "@2x"
    try write(image, to: output.appendingPathComponent("dmg-background\(suffix).png"))
}

print("Wrote \(iconset.lastPathComponent) and dmg-background.png to \(output.path)")
