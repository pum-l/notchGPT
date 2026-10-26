import Foundation

struct ChatPin: Codable, Equatable, Hashable {
    let id: String
    let hostId: String
    let kind: String
    var isValid: Bool {
        guard !hostId.isEmpty, hostId.count <= 256, !hostId.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        if kind == "codex" { return UUID(uuidString: id) != nil }
        return kind == "cloud" && id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil
    }
}

enum PinnedChatOrder {
    // Insert before an existing identity; nil means the end of the pinned group.
    static func moving(_ pin: ChatPin, before target: ChatPin?, in pins: [ChatPin]) -> [ChatPin]? {
        guard let original = pins.firstIndex(of: pin), target == nil || pins.contains(target!) else { return nil }
        if target == pin { return pins }
        var result = pins; result.remove(at: original)
        let insertion = target.flatMap { result.firstIndex(of: $0) } ?? result.count
        result.insert(pin, at: insertion)
        return result
    }
}

struct AppPreferences: Codable, Equatable {
    var hoverToOpen = false
    var animateDropdowns = true
    var usageInterval = 60
    var chatInterval = 15
    var chatCount = 10
    var textSize = 11
    var startAtLogin = true
    var pinnedChats: [ChatPin] = []

    static let defaultQuotaColor = "#B58A1B"
    static let defaultWindowColor = "#7040A0"
    var quotaColorHex = AppPreferences.defaultQuotaColor
    var windowColorHex = AppPreferences.defaultWindowColor

    init() {}
    enum CodingKeys: String, CodingKey {
        case pinnedChats, hoverToOpen, animateDropdowns, usageInterval, chatInterval, chatCount, textSize, startAtLogin, quotaColorHex, windowColorHex
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        pinnedChats = (try? values.decode([ChatPin].self, forKey: .pinnedChats)) ?? []
        hoverToOpen = try values.decodeIfPresent(Bool.self, forKey: .hoverToOpen) ?? false
        animateDropdowns = try values.decodeIfPresent(Bool.self, forKey: .animateDropdowns) ?? true
        usageInterval = try values.decodeIfPresent(Int.self, forKey: .usageInterval) ?? 60
        chatInterval = try values.decodeIfPresent(Int.self, forKey: .chatInterval) ?? 15
        chatCount = try values.decodeIfPresent(Int.self, forKey: .chatCount) ?? 10
        textSize = try values.decodeIfPresent(Int.self, forKey: .textSize) ?? 11
        startAtLogin = try values.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? true
        quotaColorHex = try values.decodeIfPresent(String.self, forKey: .quotaColorHex) ?? Self.defaultQuotaColor
        windowColorHex = try values.decodeIfPresent(String.self, forKey: .windowColorHex) ?? Self.defaultWindowColor
        validate()
    }
    static func normalizedColor(_ value: String) -> String? {
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6, hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        return "#" + hex.uppercased()
    }
    mutating func validate() {
        var seen = Set<ChatPin>()
        pinnedChats = Array(pinnedChats.filter { $0.isValid && seen.insert($0).inserted }.prefix(10))
        quotaColorHex = Self.normalizedColor(quotaColorHex) ?? Self.defaultQuotaColor
        windowColorHex = Self.normalizedColor(windowColorHex) ?? Self.defaultWindowColor
        if ![30,60,120,300].contains(usageInterval) { usageInterval = 60 }
        if ![5,15,30,60].contains(chatInterval) { chatInterval = 15 }
        if ![5,10].contains(chatCount) { chatCount = 10 }
        if ![10,11,12].contains(textSize) { textSize = 11 }
    }
}

final class PreferencesStore {
    static let defaultURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/notchGPT/preferences.json")
    private let url: URL?
    private(set) var value: AppPreferences
    init(url: URL? = PreferencesStore.defaultURL) {
        self.url = url
        value = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) } ?? AppPreferences()
        value.validate()
    }
    func save(_ preferences: AppPreferences) throws {
        var validated = preferences; validated.validate()
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(validated).write(to: url, options: .atomic)
        }
        value = validated
    }
}

enum NotchPane: Int { case none, usage, chats, settings, windowUsage }

struct HoverActivation {
    private var target = NotchPane.none
    private var enteredAt: TimeInterval = 0
    private var suppressed = NotchPane.none
    mutating func clicked(_ pane: NotchPane) { target = pane; suppressed = pane }
    mutating func reset() { self = HoverActivation() }
    mutating func update(target next: NotchPane, now: TimeInterval, enabled: Bool) -> NotchPane? {
        guard enabled else { reset(); return nil }
        if next != target {
            target = next; enteredAt = now; suppressed = .none
        }
        guard next != .none, suppressed != next, now - enteredAt >= 0.3 else { return nil }
        suppressed = next
        return next
    }
}

enum LoginStartup {
    static func setEnabled(_ enabled: Bool) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = [enabled ? "enable" : "disable", "gui/\(getuid())/dev.notchgpt.mac"]
        proc.standardOutput = FileHandle.nullDevice; proc.standardError = FileHandle.nullDevice
        try proc.run(); proc.waitUntilExit()
        if proc.terminationStatus != 0 { throw NSError(domain: "notchGPT.Login", code: Int(proc.terminationStatus)) }
    }
}
