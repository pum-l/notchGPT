import AppKit

// Package generated master artwork at a consistent macOS optical size.
// This only scales/pads the asset; it does not redraw or recolor the artwork.
let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let master = project.appendingPathComponent("Resources/AppIcon.png")
let destination = CommandLine.arguments.count > 1 ? URL(fileURLWithPath: CommandLine.arguments[1]) : project.appendingPathComponent("Resources/AppIcon.icns")
let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let iconset = output.appendingPathComponent("AppIcon.iconset")
defer { try? FileManager.default.removeItem(at: output) }
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
guard let image = NSImage(contentsOf: master) else { fatalError("Invalid master image") }
func render(_ pixels: Int) throws -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let inset = CGFloat(pixels) * 0.08
    image.draw(in: NSRect(x: inset, y: inset, width: CGFloat(pixels) - inset * 2, height: CGFloat(pixels) - inset * 2),
               from: .zero, operation: .copy, fraction: 1)
    context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for size in [16,32,128,256,512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size*2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("AppIcon.icns").path]
try task.run(); task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
try FileManager.default.copyItem(at: output.appendingPathComponent("AppIcon.icns"), to: destination)
// Keep the modern asset catalog in sync with the ICNS fallback.
if destination.standardizedFileURL == project.appendingPathComponent("Resources/AppIcon.icns").standardizedFileURL {
    let assets = project.appendingPathComponent("Resources/Assets.xcassets")
    let appicons = assets.appendingPathComponent("AppIcon.appiconset")
    try FileManager.default.createDirectory(at: appicons, withIntermediateDirectories: true)
    let info: [String: Any] = ["author": "xcode", "version": 1]
    var images: [[String: String]] = []
    for size in [16,32,128,256,512] {
        for (scale, suffix) in [("1x", ""), ("2x", "@2x")] {
            let name = "icon_\(size)x\(size)\(suffix).png"
            try Data(contentsOf: iconset.appendingPathComponent(name)).write(to: appicons.appendingPathComponent(name))
            images.append(["filename": name, "size": "\(size)x\(size)", "scale": scale, "idiom": "mac"])
        }
    }
    try JSONSerialization.data(withJSONObject: ["info": info]).write(to: assets.appendingPathComponent("Contents.json"))
    try JSONSerialization.data(withJSONObject: ["info": info, "images": images], options: .prettyPrinted).write(to: appicons.appendingPathComponent("Contents.json"))
    let compiled = output.appendingPathComponent("compiled")
    try FileManager.default.createDirectory(at: compiled, withIntermediateDirectories: true)
    let compiler = Process(); compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    compiler.arguments = ["actool", assets.path, "--compile", compiled.path, "--platform", "macosx", "--minimum-deployment-target", "14.0", "--app-icon", "AppIcon", "--output-partial-info-plist", compiled.appendingPathComponent("partial-info.plist").path]
    try compiler.run(); compiler.waitUntilExit()
    guard compiler.terminationStatus == 0 else { fatalError("actool failed") }
    try Data(contentsOf: compiled.appendingPathComponent("Assets.car")).write(to: project.appendingPathComponent("Resources/Assets.car"))
}
if CommandLine.arguments.count > 2 { try render(512).write(to: URL(fileURLWithPath: CommandLine.arguments[2])) }
print(destination.path)
