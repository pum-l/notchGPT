import AppKit

extension NSColor {
    static func dialColor(_ hex: String) -> NSColor {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    var dialHex: String {
        let rgb = usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
    }
}


final class DialColorWell: NSColorWell {
    // Open the full native panel directly; the system quick-picker can run in a
    // separate process and look like an outside click to a notch utility.
    func showPicker() {
        activate(true)
        let picker = NSColorPanel.shared
        picker.showsAlpha = false
        picker.level = NSWindow.Level(rawValue: (window?.level.rawValue ?? 0) + 1)
        picker.hidesOnDeactivate = false
        NSApp.activate(ignoringOtherApps: true)
        picker.makeKeyAndOrderFront(nil)
    }
    override func mouseDown(with event: NSEvent) { showPicker() }
    override func accessibilityPerformPress() -> Bool { showPicker(); return true }
}

final class SettingsView: NSView {
    override var isFlipped: Bool { true }
    let heading = NSTextField(labelWithString: "Settings")
    let hover = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let animationToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let login = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    let usageInterval = NSPopUpButton()
    let chatInterval = NSPopUpButton()
    let chatCount = NSPopUpButton()
    let textSize = NSPopUpButton()
    let quotaColor = DialColorWell()
    let windowColor = DialColorWell()
    private let colorLabels = [NSTextField(labelWithString: "ChatGPT color"), NSTextField(labelWithString: "Window color")]
    let status = NSTextField(wrappingLabelWithString: "")
    var onChange: ((AppPreferences) -> Void)?
    var onClose: (() -> Void)?
    private var preferences = AppPreferences()
    private var labels: [NSTextField] = []
    private let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close settings")!, target: nil, action: nil)
    private let reset = NSButton(title: "Restore defaults", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(heading); addSubview(close); addSubview(status); addSubview(reset)
        close.isBordered = false; close.contentTintColor = .white
        close.target = self; close.action = #selector(closeClicked)
        reset.target = self; reset.action = #selector(resetClicked)
        let titles = ["Open on hover", "Dropdown animation", "Usage refresh", "Chat refresh", "Recent chats", "Text size", "Launch at login"]
        let controls: [NSControl] = [hover,animationToggle,usageInterval,chatInterval,chatCount,textSize,login]
        for (title, control) in zip(titles,controls) {
            let label = NSTextField(labelWithString: title)
            label.textColor = .white; labels.append(label); addSubview(label); addSubview(control)
            control.setAccessibilityLabel(title); control.target = self; control.action = #selector(changed)
        }
        for (popup, options) in [(usageInterval,[30,60,120,300]),(chatInterval,[5,15,30,60]),(chatCount,[5,10]),(textSize,[10,11,12])] {
            for option in options {
                let title = popup === textSize ? (option == 10 ? "Compact" : option == 11 ? "Normal" : "Large") : popup === chatCount ? "\(option) chats" : "\(option) seconds"
                popup.addItem(withTitle: title); popup.lastItem?.tag = option
            }
        }
        for (well, label) in zip([quotaColor, windowColor], colorLabels) {
            addSubview(well); addSubview(label); label.textColor = .white
            well.setAccessibilityLabel(label.stringValue)
            well.target = self; well.action = #selector(changed)
        }
        apply(AppPreferences())
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func apply(_ value: AppPreferences) {
        preferences = value
        quotaColor.color = .dialColor(value.quotaColorHex)
        windowColor.color = .dialColor(value.windowColorHex)
        colorLabels.forEach { $0.font = NotchTypography.secondary }
        hover.state = value.hoverToOpen ? .on : .off
        animationToggle.state = value.animateDropdowns ? .on : .off
        login.state = value.startAtLogin ? .on : .off
        usageInterval.selectItem(withTag: value.usageInterval)
        chatInterval.selectItem(withTag: value.chatInterval)
        chatCount.selectItem(withTag: value.chatCount)
        textSize.selectItem(withTag: value.textSize)
        for control in [heading,status] + labels { control.font = NotchTypography.primary }
        status.font = NotchTypography.caption; status.textColor = .secondaryLabelColor
        for control: NSControl in [hover,animationToggle,login,usageInterval,chatInterval,chatCount,textSize,reset] { control.font = NotchTypography.primary }
        heading.font = NotchTypography.primary
        status.stringValue = "Chat alerts refresh every 30–60s when closed. Hover opens after a short pause; click outside or press Esc to close."
        needsLayout = true
    }
    func showError(_ message: String) { status.stringValue = message; status.textColor = .systemOrange }
    override func layout() {
        super.layout()
        heading.frame = NSRect(x: 14,y: 12,width: bounds.width - 60,height: 20)
        close.frame = NSRect(x: bounds.width - 35,y: 10,width: 24,height: 24)
        let controls: [NSControl] = [hover,animationToggle,usageInterval,chatInterval,chatCount,textSize,login]
        let columnWidth = (bounds.width - 36) / 2
        for (index, well) in [quotaColor, windowColor].enumerated() {
            let x = 14 + CGFloat(index) * (columnWidth + 8)
            colorLabels[index].frame = NSRect(x: x, y: 47, width: columnWidth - 40, height: 20)
            well.frame = NSRect(x: x + columnWidth - 34, y: 42, width: 34, height: 27)
        }
        let rowSpacing = max(24,min(28,(bounds.height - 186) / 6))
        for (index,control) in controls.enumerated() {
            let y = 80 + CGFloat(index) * rowSpacing
            let checkbox = control is NSButton && !(control is NSPopUpButton)
            let width: CGFloat = checkbox ? 24 : 126
            labels[index].frame = NSRect(x: 14,y: y + 4,width: bounds.width - 158,height: 20)
            control.frame = NSRect(x: bounds.width - width - 14,y: y,width: width,height: 26)
        }
        status.frame = NSRect(x: 14,y: bounds.height - 66,width: bounds.width - 28,height: 32)
        reset.frame = NSRect(x: 14,y: bounds.height - 31,width: 172,height: 24)
    }
    @objc private func changed() {
        preferences.quotaColorHex = quotaColor.color.dialHex
        preferences.windowColorHex = windowColor.color.dialHex
        preferences.hoverToOpen = hover.state == .on
        preferences.animateDropdowns = animationToggle.state == .on
        preferences.startAtLogin = login.state == .on
        preferences.usageInterval = usageInterval.selectedTag()
        preferences.chatInterval = chatInterval.selectedTag()
        preferences.chatCount = chatCount.selectedTag()
        preferences.textSize = textSize.selectedTag()
        onChange?(preferences)
    }
    @objc private func resetClicked() {
        var defaults = AppPreferences(); defaults.pinnedChats = preferences.pinnedChats
        onChange?(defaults)
    }
    @objc private func closeClicked() { onClose?() }
}
