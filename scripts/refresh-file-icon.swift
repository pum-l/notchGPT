import AppKit

// A normal Finder icon customization refreshes the cached legacy rendition.
// It only changes folder icon metadata; it does not alter executable code.
let arguments = Array(CommandLine.arguments.dropFirst())
let clear = arguments.first == "--clear"
let paths = clear ? Array(arguments.dropFirst()) : arguments
for path in paths {
    let bundle = URL(fileURLWithPath: path)
    let image = clear ? nil : NSImage(contentsOf: bundle.appendingPathComponent("Contents/Resources/AppIcon.icns"))
    guard clear || image != nil else { fatalError("Missing icon in \(path)") }
    guard NSWorkspace.shared.setIcon(image, forFile: path, options: []) else { fatalError("Finder icon update failed: \(path)") }
    if clear {
        let icon = bundle.appendingPathComponent("Icon\r")
        if FileManager.default.fileExists(atPath: icon.path) { try FileManager.default.removeItem(at: icon) }
        for attribute in ["com.apple.FinderInfo", "com.apple.ResourceFork"] {
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            task.arguments = ["-d", attribute, path]; task.standardError = FileHandle.nullDevice
            try task.run(); task.waitUntilExit()
        }
    }
}
