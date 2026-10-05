import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: swift scripts/make-icon.swift <output.png>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]
let pixels = 1024

func color(_ hex: UInt32) -> NSColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255
    let g = CGFloat((hex >> 8) & 0xFF) / 255
    let b = CGFloat(hex & 0xFF) / 255
    return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
}

func symbol(named name: String, pointSize: CGFloat, tint: NSColor) -> NSImage? {
    let sized = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
    let colored = NSImage.SymbolConfiguration(paletteColors: [tint])
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(sized.applying(colored))
}

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixels,
    pixelsHigh: pixels,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bitmapFormat: .thirtyTwoBitLittleEndian,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fputs("make-icon: could not allocate bitmap\n", stderr)
    exit(1)
}
rep.size = NSSize(width: pixels, height: pixels)

NSGraphicsContext.saveGraphicsState()
guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else {
    fputs("make-icon: could not create graphics context\n", stderr)
    exit(1)
}
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high

let canvas = NSRect(x: 0, y: 0, width: pixels, height: pixels)
let gradient = NSGradient(colors: [color(0x1E6FD9), color(0x0B3D91)])!
gradient.draw(in: canvas, angle: -90)

guard let folder = symbol(named: "folder.fill", pointSize: 560, tint: .white),
      let link = symbol(named: "link", pointSize: 300, tint: color(0x7FD1FF)) else {
    fputs("make-icon: SF Symbol unavailable\n", stderr)
    exit(1)
}

let folderFrame = NSRect(
    x: (CGFloat(pixels) - folder.size.width) / 2,
    y: (CGFloat(pixels) - folder.size.height) / 2 + 40,
    width: folder.size.width,
    height: folder.size.height
)
folder.draw(in: folderFrame, from: .zero, operation: .sourceOver, fraction: 1)

let linkFrame = NSRect(
    x: folderFrame.maxX - link.size.width * 0.72,
    y: folderFrame.minY - link.size.height * 0.08,
    width: link.size.width,
    height: link.size.height
)
link.draw(in: linkFrame, from: .zero, operation: .sourceOver, fraction: 1)

graphics.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

// Fully opaque square: iOS masks the icon, and transparent corners are rejected.
if let data = rep.bitmapData {
    let alphaFirst = rep.bitmapFormat.contains(.alphaFirst)
    let alphaOffset = alphaFirst ? 0 : 3
    let samples = rep.samplesPerPixel
    for y in 0..<pixels {
        for x in 0..<pixels {
            data[y * rep.bytesPerRow + x * samples + alphaOffset] = 255
        }
    }
}

guard let png = rep.representation(using: .png, properties: [:]) else {
    fputs("make-icon: PNG encoding failed\n", stderr)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outputPath))
} catch {
    fputs("make-icon: \(error)\n", stderr)
    exit(1)
}
