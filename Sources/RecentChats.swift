import AppKit
import QuartzCore

enum ChatAttention: Equatable {
    case none, input, notified, combined

    init(chats: [RecentChat]) {
        let input = chats.contains { $0.state == "waiting for input" }
        let notified = chats.contains { $0.state == "notified" }
        self = input ? (notified ? .combined : .input) : (notified ? .notified : .none)
    }
    var description: String {
        switch self {
        case .none: return "Recent chats"
        case .input: return "Recent chats — waiting for input"
        case .notified: return "Recent chats — notified"
        case .combined: return "Recent chats — waiting for input and notified"
        }
    }
}

enum NotchTypography {
    static var scale: CGFloat = 1
    static var primary: NSFont { .systemFont(ofSize: 11 * scale, weight: .medium) }
    static var secondary: NSFont { .systemFont(ofSize: 10 * scale, weight: .regular) }
    static var caption: NSFont { .systemFont(ofSize: 9 * scale, weight: .regular) }
    static var chart: NSFont { .systemFont(ofSize: 8 * scale, weight: .regular) }
    static var number: NSFont { .monospacedDigitSystemFont(ofSize: 11 * scale, weight: .medium) }
}

enum DropdownMotion {
    static let duration: TimeInterval = 0.24

    static func animate(from initial: NSRect, to target: NSRect,
                        update: @escaping (NSRect) -> Void,
                        completion: @escaping () -> Void) -> Timer {
        let started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - started) / duration)
            let eased = progress * progress * (3 - 2 * progress)
            let width = initial.width + (target.width - initial.width) * eased
            let height = initial.height + (target.height - initial.height) * eased
            let x = initial.minX + (target.minX - initial.minX) * eased
            let top = initial.maxY + (target.maxY - initial.maxY) * eased
            update(NSRect(x: x, y: top - height, width: width, height: height))
            if progress >= 1 { timer.invalidate(); completion() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

struct RecentChat: Decodable {
    let id: String
    let title: String
    let state: String?
    let origin: String
    var hostId: String? = nil
    var hostName: String? = nil
    var kind: String? = nil
    var url: String? = nil
    var originLabel: String {
        guard origin == "Remote" else { return origin }
        if let name = hostName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        guard let hostId, hostId != "local", !hostId.isEmpty else { return "Remote computer" }
        if hostId.hasPrefix("remote-control:") { return "Remote · " + String(hostId.suffix(8)) }
        let identity = hostId.hasPrefix("ssh:") ? String(hostId.dropFirst(4)) : hostId
        return identity.count > 24 ? String(identity.prefix(21)) + "…" : identity
    }
    var pin: ChatPin { ChatPin(id: id,hostId: hostId ?? "local",kind: kind ?? (origin == "Cloud" ? "cloud" : "codex")) }
    var linkURL: URL? {
        if kind == "cloud" || id.hasPrefix("task_") {
            if let url, let value = URL(string: url), value.scheme == "https", value.host == "chatgpt.com", value.path.hasPrefix("/codex/tasks/") {
                var clean = URLComponents(); clean.scheme = "https"; clean.host = "chatgpt.com"; clean.path = value.path
                return clean.url
            }
            guard id.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else { return nil }
            return URL(string: "https://chatgpt.com/codex/tasks/" + id)
        }
        guard UUID(uuidString: id) != nil else { return nil }
        var components = URLComponents()
        components.scheme = "codex"; components.host = "threads"; components.path = "/" + id
        if let hostId, hostId != "local" { components.queryItems = [URLQueryItem(name: "hostId",value: hostId)] }
        return components.url
    }
}

struct RecentChatResponse: Decodable {
    var threads: [RecentChat]?
    var partial: Bool?
    var error: String?
    var cached: Bool?
}

final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class PinnedChatDragHandle: NSView {
    let pin: ChatPin
    weak var owner: RecentChatsView?
    private var initialPoint: NSPoint?
    init(pin: ChatPin, title: String) {
        self.pin = pin
        super.init(frame: .zero)
        toolTip = "Drag to reorder pinned chat"
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel("Reorder pinned chat: " + title)
        setAccessibilityHelp(toolTip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() { addCursorRect(bounds,cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.45).setFill()
        for x in [-2.5, 2.5] {
            for y in [-5.0, 0, 5.0] {
                NSBezierPath(ovalIn: NSRect(x: bounds.midX + x - 1,y: bounds.midY + y - 1,width: 2,height: 2)).fill()
            }
        }
    }
    override func mouseDown(with event: NSEvent) { initialPoint = event.locationInWindow }
    override func mouseDragged(with event: NSEvent) {
        guard let initialPoint, let owner, owner.pinnedChats.contains(pin) else { return }
        if !owner.isReordering {
            guard hypot(event.locationInWindow.x - initialPoint.x,event.locationInWindow.y - initialPoint.y) >= 4 else { return }
            owner.beginPinnedDrag(from: self,at: initialPoint)
        }
        owner.updatePinnedDrag(at: event.locationInWindow)
    }
    override func mouseUp(with event: NSEvent) {
        if initialPoint != nil { owner?.finishPinnedDrag(at: event.locationInWindow) }
        initialPoint = nil
    }
    func resetGesture() { initialPoint = nil }
}

private final class PinnedDragPreview: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class PinnedChatRowsView: NSView {
    weak var owner: RecentChatsView?
    private(set) var insertionY: CGFloat?
    func clearInsertion() { insertionY = nil; needsDisplay = true }
    // The document is unflipped: the topmost row has the largest Y coordinate.
    func insertion(at point: NSPoint) -> (before: ChatPin?, y: CGFloat)? {
        let pinned = subviews.compactMap { $0 as? ChatRow }.filter(\.pinned).sorted { $0.frame.maxY > $1.frame.maxY }
        guard let last = pinned.last else { return nil }
        if let row = pinned.first(where: { point.y >= $0.frame.midY }) { return (row.chat.pin,row.frame.maxY) }
        // A five-chat limit may hide pins: retain the unseen entries' order.
        let next = owner.flatMap { list in list.pinnedChats.firstIndex(of: last.chat.pin).flatMap { index in
            index + 1 < list.pinnedChats.count ? list.pinnedChats[index + 1] : nil
        } }
        return (next,last.frame.minY)
    }
    func updateInsertion(at windowPoint: NSPoint) {
        guard let scroll = enclosingScrollView else { return }
        var point = convert(windowPoint,from: nil)
        let visible = visibleRect
        let offset: CGFloat = point.y < visible.minY + 22 ? -8 : point.y > visible.maxY - 22 ? 8 : 0
        if offset != 0 {
            let y = min(max(0,visible.minY + offset),max(0,bounds.height - visible.height))
            scroll.contentView.scroll(to: NSPoint(x: 0,y: y)); scroll.reflectScrolledClipView(scroll.contentView)
            point = convert(windowPoint,from: nil)
        }
        insertionY = insertion(at: point)?.y; needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let insertionY else { return }
        NSColor.systemYellow.setFill()
        NSBezierPath(roundedRect: NSRect(x: 9,y: insertionY - 1,width: max(0,bounds.width - 18),height: 2),xRadius: 1,yRadius: 1).fill()
        NSBezierPath(ovalIn: NSRect(x: 7,y: insertionY - 3,width: 6,height: 6)).fill()
    }
}

final class RecentChatsView: NSView {
    override var isFlipped: Bool { true }
    static let rowHeight: CGFloat = 56
    let heading = NSTextField(labelWithString: "Recent chats")
    let caption = NSTextField(labelWithString: "Loading…")
    let scroll = NSScrollView()
    let rows = PinnedChatRowsView(frame: .zero)
    var onRefresh: (() -> Void)?
    var onClose: (() -> Void)?
    var onOpenChat: ((RecentChat) -> Void)?
    var onTogglePin: ((RecentChat) -> Void)?
    var onReorderPinned: ((ChatPin, ChatPin?) -> Bool)?
    private(set) var isReordering = false
    private var deferredUpdate: (RecentChatResponse?, Bool)?
    private var preserveDragScroll = false
    private weak var draggedHandle: PinnedChatDragHandle?
    private var dragPreview: PinnedDragPreview?
    private var dragOffset = NSPoint.zero
    private var dragPoint = NSPoint.zero
    private var dragTimer: Timer?
    private var dragEscapeMonitor: Any?
    func beginPinnedDrag() { isReordering = true }
    func beginPinnedDrag(from handle: PinnedChatDragHandle,at windowPoint: NSPoint) {
        guard !isReordering, handle.owner === self, pinnedChats.contains(handle.pin), let row = handle.superview as? ChatRow else { return }
        beginPinnedDrag(); draggedHandle = handle
        let frame = convert(row.bounds,from: row), point = convert(windowPoint,from: nil)
        dragOffset = NSPoint(x: point.x - frame.minX,y: point.y - frame.minY)
        let preview = PinnedDragPreview(frame: frame)
        let image = NSImage(size: row.bounds.size)
        if let bitmap = row.bitmapImageRepForCachingDisplay(in: row.bounds) {
            row.cacheDisplay(in: row.bounds,to: bitmap); image.addRepresentation(bitmap)
        }
        preview.setAccessibilityElement(false)
        preview.image = image; preview.imageScaling = .scaleAxesIndependently; preview.alphaValue = 0.9
        addSubview(preview); dragPreview = preview; row.alphaValue = 0.35
        NSCursor.closedHand.push()
        dragEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, let self, self.isReordering { self.endPinnedDrag(); return nil }
            return event
        }
        dragPoint = windowPoint
        let timer = Timer(timeInterval: 0.04,repeats: true) { [weak self] _ in
            guard let self, self.isReordering else { return }; self.updatePinnedDrag(at: self.dragPoint)
        }
        dragTimer = timer; RunLoop.main.add(timer,forMode: .common)
    }
    func updatePinnedDrag(at windowPoint: NSPoint) {
        guard isReordering else { return }
        dragPoint = windowPoint
        let point = convert(windowPoint,from: nil)
        dragPreview?.frame.origin = NSPoint(x: point.x - dragOffset.x,y: point.y - dragOffset.y)
        if scroll.bounds.contains(scroll.convert(windowPoint,from: nil)) { rows.updateInsertion(at: windowPoint) }
        else { rows.clearInsertion() }
    }
    func finishPinnedDrag(at windowPoint: NSPoint) {
        guard isReordering else { return }
        if let pin = draggedHandle?.pin, pinnedChats.contains(pin), scroll.bounds.contains(scroll.convert(windowPoint,from: nil)),
           let target = rows.insertion(at: rows.convert(windowPoint,from: nil)) {
            reorder(pin,before: target.before)
        }
        endPinnedDrag()
    }
    func endPinnedDrag() {
        dragTimer?.invalidate(); dragTimer = nil
        if let monitor = dragEscapeMonitor { NSEvent.removeMonitor(monitor); dragEscapeMonitor = nil }
        draggedHandle?.superview?.alphaValue = 1; draggedHandle?.resetGesture(); draggedHandle = nil
        if dragPreview != nil { NSCursor.pop() }
        dragPreview?.removeFromSuperview(); dragPreview = nil
        isReordering = false; rows.clearInsertion()
        if let pending = deferredUpdate {
            deferredUpdate = nil; preserveDragScroll = true; update(pending.0,loading: pending.1)
        }
    }
    @discardableResult func reorder(_ pin: ChatPin,before target: ChatPin?) -> Bool {
        guard PinnedChatOrder.moving(pin,before: target,in: pinnedChats) != nil else { return false }
        let success = onReorderPinned?(pin,target) ?? false
        if !success { caption.stringValue = "Could not save pinned order. Please retry." }
        return success
    }
    var pinnedChats: [ChatPin] = []
    var chatLimit = 10
    var refreshSeconds = 15
    private var displayedChatIDs: [String] = []
    private let refresh = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh chats")!, target: nil, action: nil)
    private let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close recent chats")!, target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        heading.font = NotchTypography.primary
        heading.textColor = .white
        caption.font = NotchTypography.caption
        caption.textColor = .secondaryLabelColor
        caption.lineBreakMode = .byTruncatingTail
        for button in [refresh, close] { button.isBordered = false; button.contentTintColor = .white; addSubview(button) }
        refresh.target = self; refresh.action = #selector(refreshClicked)
        close.target = self; close.action = #selector(closeClicked)
        refresh.toolTip = "Refresh chats"; close.toolTip = "Close (Esc)"
        addSubview(heading); addSubview(caption); addSubview(scroll)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        rows.owner = self
        scroll.documentView = rows
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func refreshClicked() { onRefresh?() }
    @objc private func closeClicked() { onClose?() }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() } else { super.keyDown(with: event) }
    }
    override func layout() {
        super.layout()
        heading.frame = NSRect(x: 14, y: 12, width: bounds.width - 88, height: 18)
        caption.frame = NSRect(x: 14, y: 33, width: bounds.width - 28, height: 15)
        refresh.frame = NSRect(x: bounds.width - 65, y: 10, width: 24, height: 24)
        close.frame = NSRect(x: bounds.width - 35, y: 10, width: 24, height: 24)
        scroll.frame = NSRect(x: 8, y: 56, width: bounds.width - 16, height: max(0, bounds.height - 64))
        rows.frame.size.width = scroll.contentSize.width
        for row in rows.subviews { row.frame.size.width = rows.bounds.width }
    }
    func update(_ response: RecentChatResponse?, loading: Bool) {
        if isReordering { deferredUpdate = (response,loading); return }
        heading.font = NotchTypography.primary; caption.font = NotchTypography.caption
        refresh.isEnabled = !loading
        let distanceFromTop = max(0, rows.bounds.height - scroll.contentView.bounds.maxY)
        rows.subviews.forEach { $0.removeFromSuperview() }
        let ranks = Dictionary(uniqueKeysWithValues: pinnedChats.enumerated().map { ($0.element,$0.offset) })
        let chats = Array((response?.threads ?? []).enumerated().sorted {
            let left = ranks[$0.element.pin] ?? Int.max, right = ranks[$1.element.pin] ?? Int.max
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element).prefix(chatLimit))
        let preservePosition = preserveDragScroll || displayedChatIDs == chats.map(\.id)
        preserveDragScroll = false
        displayedChatIDs = chats.map(\.id)
        caption.stringValue = loading ? "Updating…" : response?.error ?? (response?.partial == true ? "Some sources are unavailable" : response?.cached == true ? "\(chats.count) recent · remote: last read by Codex" : "Latest \(chats.count) chats · refresh every \(refreshSeconds) s")
        if !loading, response?.error == nil, !pinnedChats.isEmpty { caption.stringValue = "\(pinnedChats.count) pinned · " + caption.stringValue }
        caption.toolTip = response?.error ?? "Drag the dotted handle to reorder pinned chats. Refresh every \(refreshSeconds) seconds. Remote states reflect the last reading saved by Codex."
        if chats.isEmpty {
            let label = NSTextField(wrappingLabelWithString: loading ? "Loading chats…" : response?.error == nil ? "No recent chats" : "Open Codex and retry with ↻")
            label.textColor = .secondaryLabelColor
            label.font = NotchTypography.primary
            label.frame = NSRect(x: 8, y: 10, width: max(0, bounds.width - 40), height: 50)
            rows.addSubview(label)
        }
        rows.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(72, CGFloat(chats.count) * Self.rowHeight))
        for (index, chat) in chats.enumerated() {
            let row = ChatRow(chat: chat, pinned: pinnedChats.contains(chat.pin), onOpen: onOpenChat, onPin: onTogglePin)
            row.dragHandle?.owner = self
            // The document uses AppKit coordinates: newest chat is at the top.
            row.frame = NSRect(x: 0, y: rows.bounds.height - CGFloat(index + 1) * Self.rowHeight,
                               width: rows.bounds.width, height: Self.rowHeight)
            rows.addSubview(row)
        }
        let top = max(0, rows.bounds.height - scroll.contentSize.height)
        rows.scroll(NSPoint(x: 0, y: max(0, top - (preservePosition ? distanceFromTop : 0))))
        needsLayout = true
    }
}

final class ChatRow: NSView {
    let openButton = NSButton()
    let pinButton = NSButton()
    let pinned: Bool
    let dragHandle: PinnedChatDragHandle?
    private let onPin: ((RecentChat) -> Void)?
    override var isFlipped: Bool { false }
    let chat: RecentChat
    private let onOpen: ((RecentChat) -> Void)?
    private var hovered = false
    private var tracking: NSTrackingArea?
    private let spinner = CAShapeLayer()
    private var statusColor: NSColor {
        chat.state == "running" ? .systemGreen : chat.state == "waiting for input" ? .systemOrange : chat.state == "notified" ? .systemBlue : .systemGray
    }
    private var statusLabel: String {
        switch chat.state {
        case "running": return "Running"
        case "waiting for input": return "Waiting for input"
        case "stopped": return "Stopped"
        case "notified": return "Notified"
        default: return "Unavailable"
        }
    }
    init(chat: RecentChat, pinned: Bool, onOpen: ((RecentChat) -> Void)?, onPin: ((RecentChat) -> Void)?) {
        self.chat = chat; self.pinned = pinned; self.onOpen = onOpen; self.onPin = onPin
        dragHandle = pinned ? PinnedChatDragHandle(pin: chat.pin,title: chat.title) : nil
        super.init(frame: .zero)
        toolTip = "\(chat.title)\n\(statusLabel) · \(chat.originLabel)"
        setAccessibilityElement(false)
        openButton.isBordered = false; openButton.title = ""; openButton.isTransparent = true
        openButton.target = self; openButton.action = #selector(openChat)
        openButton.isEnabled = chat.linkURL != nil
        openButton.setAccessibilityRole(.link); openButton.setAccessibilityLabel(toolTip)
        pinButton.isBordered = false; pinButton.title = ""
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin",accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11,weight: .medium))
        pinButton.contentTintColor = pinned ? .systemYellow : .white.withAlphaComponent(0.5)
        pinButton.toolTip = (pinned ? "Unpin " : "Pin ") + chat.title
        pinButton.setAccessibilityLabel(pinButton.toolTip)
        pinButton.target = self; pinButton.action = #selector(togglePin)
        addSubview(openButton); addSubview(pinButton)
        if let dragHandle { addSubview(dragHandle) }
        if chat.state == "running" {
            wantsLayer = true
            spinner.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
            spinner.position = CGPoint(x: 22, y: 18)
            spinner.path = CGPath(ellipseIn: CGRect(x: 1, y: 1, width: 6, height: 6), transform: nil)
            spinner.fillColor = NSColor.clear.cgColor; spinner.strokeColor = statusColor.cgColor
            spinner.lineWidth = 1.5; spinner.lineCap = .round; spinner.strokeEnd = 0.72
            layer?.addSublayer(spinner)
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0; spin.toValue = -2 * Double.pi
            spin.duration = 0.9; spin.repeatCount = .infinity
            spinner.add(spin, forKey: "running")
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        openButton.frame = NSRect(x: 4,y: 3,width: max(0,bounds.width - 8),height: bounds.height - 6)
        pinButton.frame = NSRect(x: bounds.width - 33,y: 29,width: 25,height: 23)
        dragHandle?.frame = NSRect(x: bounds.width - 57,y: 29,width: 22,height: 23)
    }
    @objc private func openChat() { onOpen?(chat) }
    @objc private func togglePin() { onPin?(chat) }
    override func resetCursorRects() { if openButton.isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,options: [.activeAlways,.mouseEnteredAndExited,.inVisibleRect],owner: self,userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 4,dy: 3),xRadius: 10,yRadius: 10)
        NSColor.white.withAlphaComponent(hovered ? 0.075 : 0.035).setFill(); card.fill()
        NSColor.white.withAlphaComponent(hovered ? 0.12 : 0.045).setStroke(); card.lineWidth = 0.7; card.stroke()
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (chat.title.replacingOccurrences(of: "\n", with: " ") as NSString).draw(in: NSRect(x: 14,y: 30,width: bounds.width - (pinned ? 78 : 54),height: 17),withAttributes: [
            .font: NotchTypography.primary,.foregroundColor: NSColor.white.withAlphaComponent(openButton.isEnabled ? 0.95 : 0.5),.paragraphStyle: paragraph])
        let statusAttributes: [NSAttributedString.Key: Any] = [.font: NotchTypography.caption,.foregroundColor: statusColor]
        let statusWidth = ceil((statusLabel as NSString).size(withAttributes: statusAttributes).width) + 25
        statusColor.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: NSRect(x: 13,y: 10,width: statusWidth,height: 16),xRadius: 8,yRadius: 8).fill()
        if chat.state == "notified" {
            drawSymbol("bell.fill",in: NSRect(x: 17,y: 13,width: 10,height: 10),color: statusColor)
        } else if chat.state != "running" {
            statusColor.setFill(); NSBezierPath(ovalIn: NSRect(x: 19,y: 15,width: 6,height: 6)).fill()
        }
        (statusLabel as NSString).draw(at: NSPoint(x: 29,y: 12),withAttributes: statusAttributes)
        let hostAttributes: [NSAttributedString.Key: Any] = [.font: NotchTypography.caption,.foregroundColor: NSColor.white.withAlphaComponent(0.68),.paragraphStyle: paragraph]
        let availableHostWidth = max(0,bounds.width - statusWidth - 47)
        let hostWidth = min(availableHostWidth,ceil((chat.originLabel as NSString).size(withAttributes: hostAttributes).width) + 26)
        let hostX = bounds.width - 13 - hostWidth
        NSColor.white.withAlphaComponent(0.045).setFill()
        NSBezierPath(roundedRect: NSRect(x: hostX,y: 10,width: hostWidth,height: 16),xRadius: 8,yRadius: 8).fill()
        let symbol = chat.origin == "Mac" ? "laptopcomputer" : chat.origin == "Cloud" ? "cloud" : "desktopcomputer"
        drawSymbol(symbol,in: NSRect(x: hostX + 6,y: 13,width: 11,height: 10),color: .white.withAlphaComponent(0.6))
        (chat.originLabel as NSString).draw(in: NSRect(x: hostX + 21,y: 12,width: max(0,hostWidth - 26),height: 13),withAttributes: hostAttributes)
    }
    private func drawSymbol(_ name: String,in rect: NSRect,color: NSColor) {
        NSImage(systemSymbolName: name,accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))?.draw(in: rect)
    }
}

final class RecentChatsController {
    let list = RecentChatsView(frame: .zero)
    private(set) var isOpen = false
    private var timer: Timer?
    private var process: Process?
    private var deadline: Timer?
    private var response: RecentChatResponse?
    private var refreshAfterCurrent = false
    var onAttentionChange: ((ChatAttention) -> Void)?
    var testing = false
    var preferences = AppPreferences()

    func apply(_ value: AppPreferences) {
        let pinsChanged = preferences.pinnedChats != value.pinnedChats
        preferences = value
        list.pinnedChats = value.pinnedChats
        list.chatLimit = value.chatCount; list.refreshSeconds = value.chatInterval
        list.update(response, loading: process != nil)
        restartTimer()
        if pinsChanged && isOpen {
            if process != nil { refreshAfterCurrent = true }
            else { refresh() }
        }
    }
    func setVisible(_ visible: Bool) {
        guard visible != isOpen else { return }
        isOpen = visible
        if visible { refresh() }
        restartTimer()
    }
    private func restartTimer() {
        timer?.invalidate(); timer = nil
        if !testing {
            timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(isOpen ? preferences.chatInterval : max(30, preferences.chatInterval)), repeats: true) { [weak self] _ in self?.refresh() }
        }
    }
    func setPreview(_ chats: [RecentChat]) { finish(RecentChatResponse(threads: chats)) }
    func refresh() {
        if testing { return }
        guard process == nil else { return }
        let apps = ["/Applications/ChatGPT.app", NSHomeDirectory() + "/Applications/ChatGPT.app", "/Applications/Codex.app", NSHomeDirectory() + "/Applications/Codex.app"]
        guard let node = apps.map({ $0 + "/Contents/Resources/cua_node/bin/node" }).first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
              let helper = Bundle.main.url(forResource: "recent-chats", withExtension: "mjs") else {
            finish(RecentChatResponse(error: "Install or open the Codex app to read chats.")); return
        }
        list.update(response, loading: true)
        let proc = Process(), pipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: node); proc.arguments = [helper.path]
        proc.standardOutput = pipe; proc.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["NOTCHGPT_LOADED_THREADS"] = loadedThreadIDs()
        environment["NOTCHGPT_PINNED_CHATS"] = String(decoding: (try? JSONEncoder().encode(preferences.pinnedChats)) ?? Data("[]".utf8),as: UTF8.self)
        proc.environment = environment
        // Drain concurrently: never block the UI or the child on a full pipe.
        process = proc
        do {
            try proc.run()
            deadline = Timer.scheduledTimer(withTimeInterval: 28, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.process?.terminate()
                self.finish(RecentChatResponse(error: "Codex is not responding. Retry with ↻."))
            }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                proc.waitUntilExit()
                let result = data.count <= 256 * 1024 ? try? JSONDecoder().decode(RecentChatResponse.self,from: data) : nil
                DispatchQueue.main.async {
                    guard let self, self.process === proc else { return }
                    self.finish(result ?? RecentChatResponse(error: "Chats unavailable. Open Codex and retry."))
                }
            }
        } catch { finish(RecentChatResponse(error: "Could not connect to Codex.")) }
    }
    private func loadedThreadIDs() -> String {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? NSHomeDirectory() + "/.codex"
        let directory = home + "/thread-writer-locks"
        var loaded: [String] = []
        for name in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] where name.hasSuffix(".lock") && !name.hasPrefix(".") {
            let fd = open(directory + "/" + name, O_RDONLY)
            guard fd >= 0 else { continue }
            // Test the writer's advisory lock without writing the file.
            if flock(fd, LOCK_SH | LOCK_NB) != 0 {
                if errno == EWOULDBLOCK { loaded.append(String(name.dropLast(5))) }
            } else { flock(fd, LOCK_UN) }
            Darwin.close(fd)
        }
        let data = (try? JSONSerialization.data(withJSONObject: loaded)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }
    private func finish(_ result: RecentChatResponse) {
        process = nil; deadline?.invalidate(); deadline = nil
        if let chats = result.threads { onAttentionChange?(ChatAttention(chats: chats)) }
        response = result; list.update(result, loading: false)
        if refreshAfterCurrent {
            refreshAfterCurrent = false
            if isOpen { refresh() }
        }
    }
    func stop() {
        if list.isReordering { list.endPinnedDrag() }
        timer?.invalidate(); timer = nil; process?.terminate(); process = nil; deadline?.invalidate()
    }
}
