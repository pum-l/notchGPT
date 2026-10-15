import AppKit

// Reproducible original vector artwork, inspired by a blue/teal activity-tracking visual family.
// No account data, fonts, screenshots, downloaded artwork or remote services.
let destination = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/AppIcon.icns")
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let iconset = scratch.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: scratch) }

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let outer = NSBezierPath(roundedRect: NSRect(x: 24, y: 24, width: 976, height: 976), xRadius: 238, yRadius: 238)
    NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.14, blue: 0.32, alpha: 1),
               ending: NSColor(calibratedRed: 0.18, green: 0.44, blue: 0.69, alpha: 1))!.draw(in: outer, angle: 48)
    let center = NSPoint(x: 512, y: 512)
    let radius: CGFloat = 265
    let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    NSColor(calibratedRed: 0.54, green: 0.71, blue: 0.89, alpha: 0.42).setStroke()
    track.lineWidth = 35; track.stroke()
    let progress = NSBezierPath()
    progress.appendArc(withCenter: center, radius: radius, startAngle: 198, endAngle: 327, clockwise: false)
    NSColor(calibratedRed: 0.41, green: 0.91, blue: 0.84, alpha: 1).setStroke()
    progress.lineWidth = 44; progress.lineCapStyle = .round; progress.stroke()
    let markerAngle = CGFloat(50) * .pi / 180
    let marker = NSPoint(x: center.x + cos(markerAngle) * radius, y: center.y + sin(markerAngle) * radius)
    NSColor(calibratedRed: 1, green: 0.8, blue: 0.44, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: marker.x - 29, y: marker.y - 29, width: 58, height: 58)).fill()
    // The percent mark identifies allowance, using the reference family's soft strokes.
    let ink = NSColor(calibratedRed: 0.9, green: 0.95, blue: 1, alpha: 1)
    ink.setStroke()
    let slash = NSBezierPath()
    slash.move(to: NSPoint(x: 455, y: 410)); slash.line(to: NSPoint(x: 569, y: 614))
    slash.lineWidth = 35; slash.lineCapStyle = .round; slash.stroke()
    for position in [NSPoint(x: 440, y: 587), NSPoint(x: 584, y: 437)] {
        let dot = NSBezierPath(ovalIn: NSRect(x: position.x - 22, y: position.y - 22, width: 44, height: 44))
        ink.setFill(); dot.fill()
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try render(size: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", destination.path]
try process.run(); process.waitUntilExit()
guard process.terminationStatus == 0 else { fatalError("iconutil failed") }
if CommandLine.arguments.count > 2 { try render(size: 512).write(to: URL(fileURLWithPath: CommandLine.arguments[2])) }
print("Generated icon")
