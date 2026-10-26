import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fputs("FAIL preferences: \(message)\n",stderr); exit(1) }
}
let defaults = AppPreferences()
check(!defaults.hoverToOpen,"hover disabled on first launch")
check(defaults.usageInterval == 60 && defaults.chatInterval == 15 && defaults.chatCount == 10,"existing refresh and chat defaults")
let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: directory) }
let url = directory.appendingPathComponent("preferences.json")
let store = PreferencesStore(url: url)
var changed = defaults
changed.hoverToOpen = true; changed.textSize = 12; changed.chatCount = 5; changed.chatInterval = 30
changed.pinnedChats = [ChatPin(id: "00000000-0000-4000-8000-000000000001",hostId: "local",kind: "codex")]
changed.quotaColorHex = "#204060"; changed.windowColorHex = "#804020"
changed.usageInterval = 120; changed.startAtLogin = false; changed.animateDropdowns = false
try store.save(changed)
check(PreferencesStore(url: url).value == changed,"settings survive a fresh store instance")
var duplicatePins = changed
let cloud = ChatPin(id: "task_test",hostId: "cloud",kind: "cloud")
duplicatePins.pinnedChats += [changed.pinnedChats[0],cloud,ChatPin(id: "invalid",hostId: "local",kind: "codex")]
try store.save(duplicatePins)
check(store.value.pinnedChats == [changed.pinnedChats[0],cloud],"pins are identity-specific, deduplicated and validated")
var invalid = changed
invalid.textSize = 500; invalid.chatCount = -1; invalid.usageInterval = 0; invalid.chatInterval = -50
try store.save(invalid)
check(store.value.textSize == 11 && store.value.chatCount == 10 && store.value.usageInterval == 60 && store.value.chatInterval == 15,"unsupported choices fall back safely")
var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(changed)) as! [String: Any]
legacy.removeValue(forKey: "pinnedChats"); legacy.removeValue(forKey: "quotaColorHex"); legacy.removeValue(forKey: "windowColorHex")
try JSONSerialization.data(withJSONObject: legacy).write(to: url)
var migrated = changed; migrated.pinnedChats = []
migrated.quotaColorHex = AppPreferences.defaultQuotaColor; migrated.windowColorHex = AppPreferences.defaultWindowColor
check(PreferencesStore(url: url).value == migrated, "adding color settings must preserve every legacy preference")
var colors = changed; colors.quotaColorHex = "abcdef"; colors.windowColorHex = "not-a-color"
try store.save(colors)
check(store.value.quotaColorHex == "#ABCDEF" && store.value.windowColorHex == AppPreferences.defaultWindowColor, "normalize RGB values and reject malformed colors")
check(AppPreferences.normalizedColor("#１２３４５６") == nil, "reject non-ASCII hex digits")
try Data("broken".utf8).write(to: url)
check(!PreferencesStore(url: url).value.hoverToOpen,"corrupt preferences preserve default hover-off")
var hover = HoverActivation()
check(hover.update(target: .usage,now: 0,enabled: false) == nil,"disabled hover")
check(hover.update(target: .usage,now: 1,enabled: true) == nil,"no instant hover opening")
check(hover.update(target: .usage,now: 1.31,enabled: true) == .usage,"dwell opens selected pane")
hover.clicked(.usage)
check(hover.update(target: .usage,now: 5,enabled: true) == nil,"click-close is not undone by hover")
_ = hover.update(target: .none,now: 6,enabled: true)
_ = hover.update(target: .usage,now: 7,enabled: true)
check(hover.update(target: .usage,now: 7.31,enabled: true) == .usage,"leaving and reentering re-arms hover")
_ = hover.update(target: .settings,now: 8,enabled: true)
check(hover.update(target: .settings,now: 8.31,enabled: true) == .settings,"hover supports settings button")
_ = hover.update(target: .windowUsage,now: 9,enabled: true)
check(hover.update(target: .windowUsage,now: 9.31,enabled: true) == .windowUsage,"hover distinguishes the window dial")
print("PASS preferences: defaults, persistence, validation, recovery, optional hover and click suppression")

let a = ChatPin(id: "00000000-0000-4000-8000-000000000001",hostId: "local",kind: "codex")
let b = ChatPin(id: a.id,hostId: "ssh:remote",kind: "codex")
let c = ChatPin(id: "task_cloud",hostId: "cloud",kind: "cloud")
let order = [a,b,c]
check(PinnedChatOrder.moving(c,before: a,in: order) == [c,a,b],"drag bottom pin to the top")
check(PinnedChatOrder.moving(a,before: nil,in: order) == [b,c,a],"drag top pin to the end")
check(PinnedChatOrder.moving(a,before: c,in: order) == [b,a,c],"downward insertion compensates for the removed source")
check(PinnedChatOrder.moving(b,before: a,in: order) == [b,a,c],"same chat ID on a different host remains a separate identity")
check(PinnedChatOrder.moving(a,before: a,in: order) == order,"drop on self preserves order")
check(PinnedChatOrder.moving(c,before: a,in: [a,b]) == nil,"reject an unpinned drag source")
check(PinnedChatOrder.moving(a,before: c,in: [a,b]) == nil,"reject an unknown insertion target")
var reordered = defaults; reordered.pinnedChats = PinnedChatOrder.moving(c,before: a,in: order)!
try store.save(reordered)
check(PreferencesStore(url: url).value.pinnedChats == [c,a,b],"manual pin order survives a fresh store and validation")
print("PASS pinned order: both directions, host-aware identities, no-op, invalid drops and disk persistence")
