// Renders the app icon (white waveform on a blue rounded square) into an .iconset folder.
// Usage: swift Scripts/make-icon.swift <output.iconset>, then `iconutil -c icns <output.iconset>`.
import AppKit

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    // macOS icon grid: the shape fills 824 of 1024 points, corner radius about 22.5 %.
    let inset = size * 100 / 1024
    let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(
        starting: NSColor(red: 0.29, green: 0.56, blue: 1.0, alpha: 1),
        ending: NSColor(red: 0.07, green: 0.30, blue: 0.86, alpha: 1)
    )!.draw(in: shape, angle: -90)

    // Waveform: seven rounded bars, mirrored around the vertical centre.
    let heights: [CGFloat] = [0.22, 0.42, 0.66, 0.9, 0.66, 0.42, 0.22]
    let barWidth = rect.width * 0.068
    let gap = rect.width * 0.045
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = rect.midX - totalWidth / 2
    NSColor.white.setFill()
    for height in heights {
        let barHeight = rect.height * 0.52 * height
        let bar = NSRect(x: x, y: rect.midY - barHeight / 2, width: barWidth, height: barHeight)
        NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        x += barWidth + gap
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: outputDirectory.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: outputDirectory.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
