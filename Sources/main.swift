import AppKit
import QuartzCore

// Passive client of the official Codex app-server. Never starts model turns.

private final class AllowanceRing: NSView {
    var tint: NSColor { didSet { needsDisplay = true } }
    let name: String
    var onPress: (() -> Void)?
    var selected = false { didSet { needsDisplay = true } }
    private var value: Int?
    private var animation: Timer?
    private(set) var displayedFraction: CGFloat = 0
    var isAnimating: Bool { animation != nil }

    init(name: String, tint: NSColor) {
        self.name = name; self.tint = tint
        super.init(frame: .zero)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        toolTip = name + ": unavailable"; setAccessibilityLabel(toolTip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(_ percent: Int?, animated: Bool) {
        let next = percent.map { min(100,max(0,$0)) }
        guard next != value else { return }
        value = next; animation?.invalidate(); animation = nil
        let description = name + (next.map { ": \($0)% remaining" } ?? ": unavailable")
        toolTip = description; setAccessibilityLabel(description)
        let target = CGFloat(next ?? 0) / 100
        guard next != nil, animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            displayedFraction = target; needsDisplay = true; return
        }
        let initial = displayedFraction, started = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60,repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1,(ProcessInfo.processInfo.systemUptime - started) / 0.35)
            let eased = progress * progress * (3 - 2 * progress)
            self.displayedFraction = initial + (target - initial) * eased
            self.needsDisplay = true
            if progress >= 1 { timer.invalidate(); self.animation = nil }
        }
        animation = timer; RunLoop.main.add(timer,forMode: .common)
    }
    override func draw(_ dirtyRect: NSRect) {
        if selected {
            tint.withAlphaComponent(0.18).setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 1,dy: 1)).fill()
        }
        let circle = bounds.insetBy(dx: 1.5,dy: 1.5)
        let track = NSBezierPath(ovalIn: circle); track.lineWidth = 2
        (value == nil ? NSColor.systemGray.withAlphaComponent(0.35) : tint.withAlphaComponent(0.22)).setStroke(); track.stroke()
        if value != nil, displayedFraction > 0 {
            NSGraphicsContext.saveGraphicsState()
            let glow = NSShadow(); glow.shadowColor = tint.withAlphaComponent(0.35); glow.shadowBlurRadius = 3; glow.set()
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: bounds.midX,y: bounds.midY),radius: circle.width / 2,
                          startAngle: 90,endAngle: 90 - 360 * displayedFraction,clockwise: true)
            arc.lineWidth = 2; arc.lineCapStyle = .round
            tint.setStroke(); arc.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
        let label = valueLabel, size = label.size()
        label.draw(at: NSPoint(x: bounds.midX - size.width / 2,y: bounds.midY - size.height / 2))
    }
    var valueLabel: NSAttributedString {
        func label(scale: CGFloat) -> NSAttributedString {
            let text = NSMutableAttributedString(string: value.map(String.init) ?? "—",attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10 * scale,weight: .semibold),
                .foregroundColor: NSColor.white])
            text.append(NSAttributedString(string: "%",attributes: [
                .font: NSFont.systemFont(ofSize: 7 * scale,weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.72)]))
            return text
        }
        let available = max(1,bounds.width - 8)
        var scale = NotchTypography.scale
        var result = label(scale: scale)
        // Native font metrics are hinted rather than perfectly linear with point size.
        for _ in 0..<4 where result.size().width > available {
            scale *= min(0.97,available / result.size().width)
            result = label(scale: scale)
        }
        return result
    }

    override func accessibilityPerformPress() -> Bool { onPress?(); return onPress != nil }
    override func resetCursorRects() { addCursorRect(bounds,cursor: .pointingHand) }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { superview?.mouseDown(with: event) }
        else { onPress?() }
    }
    override func rightMouseDown(with event: NSEvent) { superview?.rightMouseDown(with: event) }
}

final class RingIconButton: NSButton {
    var tint: NSColor { didSet { needsDisplay = true } }
    var attention: ChatAttention = .none {
        didSet {
            guard attention != oldValue else { return }
            toolTip = attention.description; setAccessibilityLabel(attention.description)
            blinkTimer?.invalidate(); blinkTimer = nil
            if attention != .none {
                let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.needsDisplay = true }
                RunLoop.main.add(timer, forMode: .common); blinkTimer = timer
            }
            needsDisplay = true
        }
    }
    private var blinkTimer: Timer?
    deinit { blinkTimer?.invalidate() }
    private let symbol: String
    private var hovered = false
    private var tracking: NSTrackingArea?
    var selected = false { didSet { needsDisplay = true } }
    var circleFrame: NSRect {
        let diameter = min(NotchLayout.ringDiameter,bounds.height - 4)
        return NSRect(x: bounds.midX - diameter / 2,y: bounds.midY - diameter / 2,width: diameter,height: diameter)
    }
    init(symbol: String,label: String,tint: NSColor) {
        self.symbol = symbol; self.tint = tint
        super.init(frame: .zero)
        isBordered = false; title = ""; toolTip = label
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() { addCursorRect(bounds,cursor: .pointingHand) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero,options: [.activeAlways,.mouseEnteredAndExited,.inVisibleRect],owner: self,userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let time = ProcessInfo.processInfo.systemUptime
        let cycle: TimeInterval = attention == .combined ? 6.0 : 3.6
        let phase = time.truncatingRemainder(dividingBy: cycle) / cycle
        let blinkPhase = attention == .notified ? time.truncatingRemainder(dividingBy: 2.8) / 2.8 : phase
        let pulse = reduceMotion ? 1.0 : 0.3 + 0.7 * pow(sin(.pi * blinkPhase), 2)
        let tint: NSColor
        switch attention {
        case .none: tint = self.tint
        case .input: tint = .systemOrange
        case .notified: tint = .systemBlue
        case .combined: tint = reduceMotion ? .systemOrange : (phase < 0.5 ? .systemOrange : .systemBlue)
        }
        let opacity = attention == .none ? 1.0 : pulse
        let circle = NSBezierPath(ovalIn: circleFrame.insetBy(dx: 1.5,dy: 1.5))
        tint.withAlphaComponent(isHighlighted ? 0.25 : selected ? 0.17 : hovered ? 0.10 : 0.035).setFill(); circle.fill()
        NSGraphicsContext.saveGraphicsState()
        if selected || hovered {
            let glow = NSShadow(); glow.shadowColor = tint.withAlphaComponent(0.3); glow.shadowBlurRadius = 3; glow.set()
        }
        tint.withAlphaComponent((selected ? 1 : hovered ? 0.95 : 0.72) * opacity).setStroke()
        circle.lineWidth = 2; circle.stroke()
        NSGraphicsContext.restoreGraphicsState()
        if attention == .combined && reduceMotion {
            NSColor.systemBlue.setStroke()
            let half = NSBezierPath()
            half.appendArc(withCenter: NSPoint(x: circleFrame.midX,y: circleFrame.midY),radius: circleFrame.width / 2 - 1.5,startAngle: 90,endAngle: 270)
            half.lineWidth = 2; half.stroke()
        }
        if let image = NSImage(systemSymbolName: symbol,accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15,weight: .medium))?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [(attention == .none ? NSColor.white : tint).withAlphaComponent((selected || hovered ? 1 : 0.84) * opacity)])) {
            let ratio = min(16 / image.size.width,16 / image.size.height)
            let size = NSSize(width: image.size.width * ratio,height: image.size.height * ratio)
            image.draw(in: NSRect(x: bounds.midX - size.width / 2,y: bounds.midY - size.height / 2,width: size.width,height: size.height))
        }
    }
}

private enum NotchLayout {
    static let compactWidth: CGFloat = 76
    static var rightButtonWidth: CGFloat { compactWidth / 2 }
    static let ringDiameter: CGFloat = 32
}

final class NotchView: NSView {
    private var compactWidth: CGFloat { NotchLayout.compactWidth }
    private let textInset: CGFloat = 12
    var compactHeight: CGFloat = 38
    var readoutRect: NSRect { NSRect(x: 0, y: bounds.height - compactHeight, width: compactWidth, height: compactHeight) }
    var percent: Int? { didSet { needsDisplay = true } }
    var weeklyUsed: Double?
    var dailyDay: String?
    var dailySpent: Double?
    var dailyPercent: Int? { didSet { needsDisplay = true } }
    var displayDate: Date?
    var accountWindows: [AccountQuotaWindow] = [] { didSet { needsDisplay = true } }
    var accountUpdated: Date?
    var statisticsPane = NotchPane.usage { didSet { needsDisplay = true } }
    var windowClickAction: (() -> Void)?
    func applyColors(_ preferences: AppPreferences) {
        quotaRing.tint = .dialColor(preferences.quotaColorHex)
        windowRing.tint = .dialColor(preferences.windowColorHex)
        needsDisplay = true
    }
    func selectDial(_ pane: NotchPane) {
        quotaRing.selected = pane == .usage
        windowRing.selected = pane == .windowUsage
    }
    private let accountTargets = (0..<2).map { _ in NSView(frame: .zero) }
    private let chartTargets = (0..<16).map { _ in NSView(frame: .zero) }
    private let quotaRing = AllowanceRing(name: "ChatGPT shared allowance",tint: .init(calibratedRed: 0.22,green: 0.8,blue: 1,alpha: 1))
    private let windowRing = AllowanceRing(name: "Four-hour window budget",tint: .init(calibratedRed: 0.75,green: 0.54,blue: 1,alpha: 1))
    var animateReadout = true
    var history: FourHourHistory? { didSet { needsDisplay = true } }
    var expanded = false { didSet { needsDisplay = true } }
    var menuAction: ((NSEvent) -> Void)?
    var clickAction: (() -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
        quotaRing.onPress = { [weak self] in self?.clickAction?() }
        windowRing.onPress = { [weak self] in self?.windowClickAction?() }
        addSubview(quotaRing); addSubview(windowRing)
        for target in chartTargets + accountTargets {
            target.isHidden = true
            target.setAccessibilityElement(true)
            target.setAccessibilityRole(.staticText)
            addSubview(target)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func accessibilityPerformPress() -> Bool {
        clickAction?()
        return clickAction != nil
    }

    override func draw(_ dirtyRect: NSRect) {
        // One material/tint and one header layout in every animation state.
        drawReadout()
        chartTargets.forEach { $0.isHidden = !expanded || statisticsPane != .windowUsage }
        accountTargets.forEach { $0.isHidden = !expanded || statisticsPane != .usage }
        if expanded {
            if statisticsPane == .windowUsage { drawExpanded() }
            else { drawAccountStatistics() }
        }
    }

    override func layout() {
        super.layout()
        let diameter = min(NotchLayout.ringDiameter,compactHeight - 4)
        for (index,ring) in [quotaRing,windowRing].enumerated() {
            let centerX = (CGFloat(index) + 0.5) * NotchLayout.rightButtonWidth
            ring.frame = NSRect(x: centerX - diameter / 2,y: readoutRect.midY - diameter / 2,
                                width: diameter,height: diameter)
        }
    }
    private func drawReadout() {
        let windowPercent = weeklyUsed.flatMap { history?.windowRemainingPercent(weeklyUsed: $0, at: displayDate ?? Date()) }
        for row in [(quotaRing,percent),(windowRing,windowPercent)] {
            row.0.update(row.1,animated: animateReadout)
            row.0.needsDisplay = true
        }
    }

    private func drawAccountStatistics() {
        let top = bounds.height - compactHeight
        let tint = quotaRing.tint
        drawText("ChatGPT allowance", x: textInset, y: top - 30, font: NotchTypography.primary)
        drawText("Shared account limits · Codex + ChatGPT Work", x: textInset, y: top - 48, font: NotchTypography.caption, color: .white.withAlphaComponent(0.78))
        drawText(percent.map { "\($0)%" } ?? "—%", x: textInset, y: top - 89,
                 font: .monospacedDigitSystemFont(ofSize: 28, weight: .semibold), color: tint)
        drawText("remaining · lower of the account limits", x: 103, y: top - 78, font: NotchTypography.caption, color: .white.withAlphaComponent(0.78))
        for index in 0..<2 {
            let card = NSRect(x: textInset, y: top - 193 - CGFloat(index) * 100, width: bounds.width - 2 * textInset, height: 88)
            let shape = NSBezierPath(roundedRect: card, xRadius: 10, yRadius: 10)
            tint.withAlphaComponent(0.075).setFill(); shape.fill()
            tint.withAlphaComponent(0.24).setStroke(); shape.lineWidth = 0.7; shape.stroke()
            let window = accountWindows.first { $0.key == (index == 0 ? "primary" : "secondary") }
            let title = window?.title ?? (index == 0 ? "Primary limit" : "Secondary limit")
            drawText(title, x: card.minX + 12, y: card.maxY - 23, font: NotchTypography.primary)
            drawRight(window.map { "\(decimal($0.remaining))% left" } ?? "Unavailable", right: card.maxX - 12, y: card.maxY - 23, font: NotchTypography.number, color: tint)
            let track = NSRect(x: card.minX + 12, y: card.maxY - 42, width: card.width - 24, height: 5)
            tint.withAlphaComponent(0.16).setFill(); NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()
            if let window, window.remaining > 0 {
                var fill = track; fill.size.width *= window.remaining / 100
                tint.setFill(); NSBezierPath(roundedRect: fill, xRadius: 2.5, yRadius: 2.5).fill()
            }
            let reset = window?.resetsAt.map { date -> String in
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "d MMM, HH:mm"
                return formatter.string(from: date)
            } ?? "—"
            drawText(window.map { "Used: \(decimal($0.used))%" } ?? "Used: —", x: card.minX + 12, y: card.minY + 13, font: NotchTypography.secondary, color: .white.withAlphaComponent(0.78))
            drawRight("Resets: " + reset, right: card.maxX - 12, y: card.minY + 13, font: NotchTypography.caption, color: .white.withAlphaComponent(0.78))
            accountTargets[index].frame = card
            accountTargets[index].setAccessibilityLabel("\(title), \(window.map { "\(decimal($0.remaining)) percent remaining, \(decimal($0.used)) percent used" } ?? "unavailable"), resets \(reset)")
        }
        let updated = accountUpdated.map { "Updated at " + timeString($0) } ?? "Waiting for account usage"
        drawText(updated, x: textInset, y: 27, font: NotchTypography.caption, color: .white.withAlphaComponent(0.78))
        drawText("Account resets follow the provider's limits.", x: textInset, y: 12, font: NotchTypography.caption, color: .white.withAlphaComponent(0.78))
    }

    private func drawExpanded() {
        let top = bounds.height - compactHeight
        let now = displayDate ?? Date()
        let block = history?.selected(at: now)
        let day = DailyUsageChart(history: history, at: now)
        let estimate = block.flatMap { WindowEstimate($0, at: now, weeklyUsed: weeklyUsed) }
        let spent = Calendar.current.isDateInWeekend(now) ? nil : (dailyDay == day.day ? dailySpent : nil) ?? (day.hasData ? day.totalUsed : nil)
        let dayLeft = spent.flatMap { used in
            weeklyUsed.flatMap { WorkUsage.remainingPercent(allowance: DailyBudget.allowance, spent: used, weeklyUsed: $0) }
        }
        let columns: [[(String, String)]] = [
            [("Window", block.map { $0.startHour == 9 ? "09–13" : "14–18" } ?? "—"),
             ("Pace/h", estimate.map { "\(decimal($0.pace)) pp" } ?? "—"),
             ("Forecast", estimate.map { "\(decimal($0.projected)) pp" } ?? "—")],
            [("Win. left", weeklyUsed.flatMap { history?.windowRemainingPercent(weeklyUsed: $0, at: now) }.map { "\($0)%" } ?? "—"),
             ("Win. used", block.map { "\(decimal($0.used / FourHourHistory.windowAllowance * 100))%" } ?? "—"),
             ("Samples", block.map { "\($0.samples.count)" } ?? "0")],
            [("Day used", spent.map { "\(decimal($0 / DailyBudget.allowance * 100))%" } ?? "—"),
             ("Day left", dayLeft.map { "\($0)%" } ?? "—"),
             ("Tracked", day.hasData ? duration(day.trackedSeconds) : "—")]
        ]
        let gap: CGFloat = 16
        let width = (bounds.width - textInset * 2 - gap * 2) / 3
        for (column, rows) in columns.enumerated() {
            let x = textInset + CGFloat(column) * (width + gap)
            for (row, metric) in rows.enumerated() {
                let y = top - 24 - CGFloat(row) * 18
                drawText(metric.0, x: x, y: y, font: NotchTypography.secondary, color: .init(calibratedWhite: 0.72, alpha: 1))
                drawRight(metric.1, right: x + width, y: y, font: NotchTypography.number)
            }
            if column < 2 {
                NSColor.white.withAlphaComponent(0.09).setFill()
                NSRect(x: x + width + gap / 2, y: top - 61, width: 0.5, height: 52).fill()
            }
        }
        NSColor.white.withAlphaComponent(0.1).setFill()
        NSRect(x: textInset, y: top - 72, width: bounds.width - textInset * 2, height: 0.5).fill()
        drawText("Window budget · daily usage", x: textInset, y: top - 95, font: NotchTypography.primary)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "EEE, d MMM"
        drawRight(formatter.string(from: now), right: bounds.width - textInset, y: top - 95, font: NotchTypography.caption, color: .white.withAlphaComponent(0.78))
        drawText("Weekly quota · percentage points per 30 min", x: textInset, y: top - 111, font: NotchTypography.caption, color: .init(calibratedWhite: 0.7, alpha: 1))
        drawDailyChart(day, rect: NSRect(x: 33, y: 65, width: bounds.width - 47, height: max(48, top - 198)))
        drawText("Hatched: partial / estimated   ·   —: no data", x: textInset, y: 24, font: NotchTypography.caption, color: .init(calibratedWhite: 0.7, alpha: 1))
        drawText("Day budget: 20 pp · window: 10 pp · local time", x: textInset, y: 10, font: NotchTypography.caption, color: .init(calibratedWhite: 0.56, alpha: 1))
    }

    private func decimal(_ value: Double) -> String { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value) }
    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }
    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    private func drawText(_ string: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor = .white) {
        (string as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
    }
    private func drawRight(_ string: String, right: CGFloat, y: CGFloat, font: NSFont, color: NSColor = .white) {
        let size = (string as NSString).size(withAttributes: [.font: font])
        drawText(string, x: right - size.width, y: y, font: font, color: color)
    }
    private func drawAtCenter(_ string: String, x: CGFloat, y: CGFloat, font: NSFont, color: NSColor) {
        let size = (string as NSString).size(withAttributes: [.font: font])
        drawText(string, x: x - size.width / 2, y: y, font: font, color: color)
    }

    private func drawDailyChart(_ day: DailyUsageChart, rect: NSRect) {
        let middleGap: CGFloat = 22
        let windowWidth = (rect.width - middleGap) / 2
        let slotWidth = windowWidth / 8
        let maximum = day.bars.compactMap(\.amount).max() ?? 0
        let upper = max(0.5, ceil(maximum * 1.15 * 2) / 2)
        let muted = NSColor(calibratedWhite: 0.62, alpha: 1)
        let cyan = windowRing.tint
        for step in 0...2 {
            let y = rect.minY + rect.height * CGFloat(step) / 2
            let path = NSBezierPath()
            for group in 0...1 {
                let x = rect.minX + CGFloat(group) * (windowWidth + middleGap)
                path.move(to: NSPoint(x: x, y: y)); path.line(to: NSPoint(x: x + windowWidth, y: y))
            }
            NSColor.white.withAlphaComponent(0.1).setStroke(); path.lineWidth = 0.5; path.stroke()
            drawRight(step == 0 ? "0" : String(format: "%.2f", upper * Double(step) / 2), right: rect.minX - 6, y: y - 4, font: NotchTypography.chart, color: muted)
        }
        for group in 0...1 {
            let x = rect.minX + CGFloat(group) * (windowWidth + middleGap)
            drawAtCenter(group == 0 ? "09:00–13:00" : "14:00–18:00", x: x + windowWidth / 2, y: rect.maxY + 8, font: NotchTypography.caption, color: .init(calibratedWhite: 0.8, alpha: 1))
            for tick in [0, 4, 8] {
                let hour = (group == 0 ? 9 : 14) + tick / 2
                drawAtCenter(String(format: "%02d", hour), x: x + CGFloat(tick) * slotWidth, y: rect.minY - 16, font: NotchTypography.chart, color: muted)
            }
        }
        for (index, bar) in day.bars.enumerated() {
            let group = index / 8, position = index % 8
            let x = rect.minX + CGFloat(group) * (windowWidth + middleGap) + CGFloat(position) * slotWidth + 3
            let barWidth = slotWidth - 6
            let target = chartTargets[index]
            target.frame = NSRect(x: x - 2, y: rect.minY, width: barWidth + 4, height: rect.height)
            var detail = "\(timeString(bar.start))–\(timeString(bar.end))"
            if let amount = bar.amount {
                let partial = bar.isPartial(at: day.now)
                detail += String(format: "\n%.2f pp of weekly quota", amount)
                detail += partial ? "\nPartial / estimated interval" : "\nObserved interval"
                let height = max(2, CGFloat(amount / upper) * rect.height)
                let shape = NSBezierPath(roundedRect: NSRect(x: x, y: rect.minY, width: barWidth, height: height), xRadius: 2, yRadius: 2)
                cyan.withAlphaComponent(partial ? 0.55 : 0.9).setFill(); shape.fill()
                if partial {
                    NSGraphicsContext.saveGraphicsState(); shape.addClip()
                    let stripes = NSBezierPath()
                    var y = rect.minY - barWidth
                    while y < rect.minY + height {
                        stripes.move(to: NSPoint(x: x, y: y)); stripes.line(to: NSPoint(x: x + barWidth, y: y + barWidth))
                        y += 6
                    }
                    NSColor.white.withAlphaComponent(0.4).setStroke(); stripes.lineWidth = 1; stripes.stroke()
                    NSGraphicsContext.restoreGraphicsState()
                }
            } else if bar.start < day.now {
                detail += "\nNo data"
                drawAtCenter("—", x: x + barWidth / 2, y: rect.minY + 5, font: NotchTypography.chart, color: muted)
            } else {
                detail += "\nUpcoming interval"
                NSColor.white.withAlphaComponent(0.14).setFill()
                NSRect(x: x, y: rect.minY, width: barWidth, height: 2).fill()
            }
            target.toolTip = detail; target.setAccessibilityLabel(detail.replacingOccurrences(of: "\n", with: ", "))
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { menuAction?(event); return }
        let point = convert(event.locationInWindow, from: nil)
        if readoutRect.contains(point) {
            if point.x < compactWidth / 2 { clickAction?() }
            else { windowClickAction?() }
        }
    }
    override func rightMouseDown(with event: NSEvent) { menuAction?(event) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NSPanel!
    let view = NotchView(frame: .zero)
    let glassView = NSVisualEffectView(frame: .zero)
    var server: Process?
    var input: FileHandle?
    var output: FileHandle?
    var buffer = Data()
    var pollTimer: Timer?
    var timeout: Timer?
    var generation = UUID()
    var lastUpdated: Date?
    var quitting = false
    var lastError: String?
    var dailyBudget: DailyBudget?
    var fourHourHistory = FourHourHistory()
    var dailyStorageError = false
    let dailyURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/notchGPT/daily-budget.json")
    let stateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/notchGPT/status.json")
    let historyURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/notchGPT/four-hour-history.json")
    var preferences = PreferencesStore()
    let recentChats = RecentChatsController()
    let settingsView = SettingsView(frame: .zero)
    let chatButton = RingIconButton(symbol: "text.bubble",label: "Recent chats",tint: .init(calibratedRed: 0.22,green: 0.8,blue: 1,alpha: 1))
    let settingsButton = RingIconButton(symbol: "slider.horizontal.3",label: "Settings",tint: .init(calibratedRed: 0.75,green: 0.54,blue: 1,alpha: 1))
    private(set) var selectedPane = NotchPane.none
    private var presentationPane = NotchPane.none
    var isExpanded: Bool { selectedPane == .usage || selectedPane == .windowUsage }
    var frameAnimationTimer: Timer?
    private var hoverTimer: Timer?
    private var hover = HoverActivation()
    var dismissMonitors: [Any] = []
    var testing = false
    private(set) var headerFrame = NSRect.zero
    private(set) var physicalNotchFrame = NSRect.zero
    var compactWidth: CGFloat { NotchLayout.compactWidth }
    // One compact body for all panes; the ten-chat document scrolls inside it.
    let expandedBodyHeight: CGFloat = 344

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        if let data = try? Data(contentsOf: dailyURL) { dailyBudget = try? JSONDecoder().decode(DailyBudget.self, from: data) }
        if let data = try? Data(contentsOf: historyURL) { fourHourHistory = (try? JSONDecoder().decode(FourHourHistory.self, from: data)) ?? FourHourHistory() }
        view.history = fourHourHistory
        buildInterface()
        NotificationCenter.default.addObserver(self, selector: #selector(position), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        installDismissMonitors(); refresh()
    }

    func buildInterface() {
        NotchTypography.scale = CGFloat(preferences.value.textSize) / 11
        view.animateReadout = !testing
        panel = ChatPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.isMovable = false
        // One material for the header and all three dropdowns, matching chats.
        glassView.material = .hudWindow; glassView.blendingMode = .behindWindow; glassView.state = .active
        glassView.appearance = NSAppearance(named: .vibrantDark)
        glassView.wantsLayer = true; glassView.layer?.cornerRadius = 18; glassView.layer?.masksToBounds = true
        glassView.layer?.borderWidth = 0
        panel.contentView = glassView
        glassView.addSubview(view)
        glassView.addSubview(recentChats.list); glassView.addSubview(settingsView)
        for button in [chatButton,settingsButton] {
            glassView.addSubview(button); button.target = self
        }
        chatButton.action = #selector(toggleChats); chatButton.toolTip = "Recent chats"
        settingsButton.action = #selector(toggleSettings); settingsButton.toolTip = "Settings"
        view.menuAction = { [weak self] event in self?.showMenu(event) }
        view.clickAction = { [weak self] in self?.toggleUsage() }
        view.windowClickAction = { [weak self] in self?.toggleWindowUsage() }
        view.toolTip = "Left dial: ChatGPT account statistics. Right dial: four-hour window budget. Click a dial to open its statistics; right-click for the menu."
        applyDialColors()
        recentChats.testing = testing
        recentChats.list.onClose = { [weak self] in self?.setPane(.none) }
        recentChats.list.onOpenChat = { [weak self] chat in
            guard let self, let url = chat.linkURL else { return }
            if NSWorkspace.shared.open(url) { self.setPane(.none) }
            else { self.recentChats.list.caption.stringValue = "Could not open the chat. Open Codex and retry." }
        }
        recentChats.list.onTogglePin = { [weak self] chat in
            guard let self else { return }
            var value = self.preferences.value
            if let index = value.pinnedChats.firstIndex(of: chat.pin) { value.pinnedChats.remove(at: index) }
            else if value.pinnedChats.count < 10 { value.pinnedChats.append(chat.pin) }
            self.applyPreferences(value)
        }
        recentChats.list.onReorderPinned = { [weak self] pin, target in
            guard let self, let order = PinnedChatOrder.moving(pin,before: target,in: self.preferences.value.pinnedChats) else { return false }
            if order == self.preferences.value.pinnedChats { return true }
            var value = self.preferences.value; value.pinnedChats = order
            self.applyPreferences(value)
            return self.preferences.value.pinnedChats == order
        }
        recentChats.onAttentionChange = { [weak self] attention in self?.chatButton.attention = attention }
        settingsView.onClose = { [weak self] in self?.setPane(.none) }
        settingsView.onChange = { [weak self] value in self?.applyPreferences(value) }
        settingsView.apply(preferences.value); recentChats.apply(preferences.value)
        position(); configureTimers()
        if !testing { recentChats.refresh() }
    }

    @objc func position() { relayout(reset: true) }
    private func relayout(reset: Bool) {
        frameAnimationTimer?.invalidate(); frameAnimationTimer = nil
        if reset { selectedPane = .none; presentationPane = .none; recentChats.setVisible(false) }
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { panel.orderOut(nil); return }
        // Both closed extensions use the same width measured from the physical notch.
        let x = left.maxX - compactWidth
        physicalNotchFrame = NSRect(x: left.maxX,y: screen.frame.maxY - screen.safeAreaInsets.top,
                                    width: right.minX - left.maxX,height: screen.safeAreaInsets.top)
        headerFrame = NSRect(x: x,y: (screen.frame.maxY - screen.safeAreaInsets.top).rounded(),
                             width: physicalNotchFrame.width + 2 * compactWidth,height: screen.safeAreaInsets.top.rounded())
        view.compactHeight = headerFrame.height
        present(frame(for: selectedPane)); updateVisibility()
        panel.orderFrontRegardless()
        if !testing { saveState() }
    }
    @objc func wake() { position(); stopServer(); refresh() }

    func bodyHeight(for pane: NotchPane) -> CGFloat {
        let available = (NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })?.visibleFrame.height ?? 800) - 12
        return pane == .none ? 0 : min(expandedBodyHeight,available)
    }
    func frame(for pane: NotchPane) -> NSRect {
        let height = headerFrame.height + bodyHeight(for: pane)
        return NSRect(x: headerFrame.minX,y: headerFrame.maxY - height,width: headerFrame.width,height: height)
    }
    var usageButtonFrame: NSRect { NSRect(x: headerFrame.minX,y: headerFrame.minY,width: compactWidth,height: headerFrame.height) }
    var quotaButtonFrame: NSRect { NSRect(x: headerFrame.minX,y: headerFrame.minY,width: compactWidth / 2,height: headerFrame.height) }
    var windowButtonFrame: NSRect { NSRect(x: headerFrame.minX + compactWidth / 2,y: headerFrame.minY,width: compactWidth / 2,height: headerFrame.height) }
    var chatButtonFrame: NSRect { NSRect(x: headerFrame.maxX - compactWidth,y: headerFrame.minY,width: NotchLayout.rightButtonWidth,height: headerFrame.height) }
    var settingsButtonFrame: NSRect { NSRect(x: headerFrame.maxX - NotchLayout.rightButtonWidth,y: headerFrame.minY,width: NotchLayout.rightButtonWidth,height: headerFrame.height) }

    func toggleUsage() { clicked(.usage) }
    func toggleWindowUsage() { clicked(.windowUsage) }
    @objc func toggleChats() { clicked(.chats) }
    @objc func toggleSettings() { clicked(.settings) }
    private func clicked(_ pane: NotchPane) {
        hover.clicked(pane)
        setPane(selectedPane == pane ? .none : pane)
    }
    func animateExpanded(_ expanded: Bool) { setPane(expanded ? .usage : .none) }

    func setPane(_ pane: NotchPane, animated: Bool? = nil) {
        guard selectedPane != pane else { return }
        if pane != .chats && recentChats.list.isReordering { recentChats.list.endPinnedDrag() }
        if selectedPane == .settings && pane != .settings {
            settingsView.quotaColor.deactivate(); settingsView.windowColor.deactivate()
            NSColorPanel.shared.orderOut(nil)
        }
        selectedPane = pane
        if pane != .none { presentationPane = pane }
        recentChats.setVisible(pane == .chats)
        updateVisibility()
        let target = frame(for: pane)
        frameAnimationTimer?.invalidate(); frameAnimationTimer = nil
        if pane != .none { panel.makeKeyAndOrderFront(nil) }
        if (animated ?? preferences.value.animateDropdowns) {
            frameAnimationTimer = DropdownMotion.animate(from: panel.frame,to: target,update: { [weak self] frame in
                self?.present(frame)
            },completion: { [weak self] in self?.finishTransition() })
        } else { present(target); finishTransition() }
    }
    private func finishTransition() {
        frameAnimationTimer = nil
        if selectedPane == .none { presentationPane = .none }
        updateVisibility()
        if !testing { saveState() }
    }
    private func updateVisibility() {
        view.expanded = presentationPane == .usage || presentationPane == .windowUsage
        view.statisticsPane = presentationPane
        view.selectDial(selectedPane)
        recentChats.list.isHidden = presentationPane != .chats
        settingsView.isHidden = presentationPane != .settings
        chatButton.selected = selectedPane == .chats
        settingsButton.selected = selectedPane == .settings
    }
    private func present(_ frame: NSRect) {
        let height = frame.height.rounded()
        panel.setFrame(NSRect(x: headerFrame.minX,y: headerFrame.maxY - height,width: headerFrame.width,height: height), display: false)
        glassView.frame = NSRect(origin: .zero,size: panel.frame.size)
        view.frame = glassView.bounds
        view.needsLayout = true; view.layoutSubtreeIfNeeded()
        let size = glassView.bounds.size
        chatButton.frame = NSRect(x: size.width - compactWidth,y: size.height - headerFrame.height,width: NotchLayout.rightButtonWidth,height: headerFrame.height)
        settingsButton.frame = NSRect(x: size.width - NotchLayout.rightButtonWidth,y: size.height - headerFrame.height,width: NotchLayout.rightButtonWidth,height: headerFrame.height)
        let chatHeight = bodyHeight(for: .chats), settingsHeight = bodyHeight(for: .settings)
        recentChats.list.frame = NSRect(x: 0,y: size.height - headerFrame.height - chatHeight,width: size.width,height: chatHeight)
        settingsView.frame = NSRect(x: 0,y: size.height - headerFrame.height - settingsHeight,width: size.width,height: settingsHeight)
        view.needsDisplay = true
        panel.displayIfNeeded()
    }

    func applyPreferences(_ value: AppPreferences) {
        let previous = preferences.value
        do {
            if value.startAtLogin != previous.startAtLogin && !testing { try LoginStartup.setEnabled(value.startAtLogin) }
            do { try preferences.save(value) }
            catch {
                if value.startAtLogin != previous.startAtLogin && !testing { try? LoginStartup.setEnabled(previous.startAtLogin) }
                throw error
            }
            NotchTypography.scale = CGFloat(preferences.value.textSize) / 11
            applyDialColors()
            settingsView.apply(preferences.value); recentChats.apply(preferences.value)
            relayout(reset: false); configureTimers()
        } catch {
            settingsView.apply(previous)
            settingsView.showError("Could not save the change. Previous settings have been kept.")
        }
    }
    private func applyDialColors() {
        view.applyColors(preferences.value)
        chatButton.tint = .dialColor(preferences.value.quotaColorHex)
        settingsButton.tint = .dialColor(preferences.value.windowColorHex)
    }
    private func configureTimers() {
        pollTimer?.invalidate(); pollTimer = nil
        hoverTimer?.invalidate(); hoverTimer = nil; hover.reset()
        if !testing {
            pollTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(preferences.value.usageInterval),repeats: true) { [weak self] _ in self?.refresh() }
            if preferences.value.hoverToOpen {
                hoverTimer = Timer(timeInterval: 0.08,repeats: true) { [weak self] _ in self?.checkHover() }
                RunLoop.main.add(hoverTimer!,forMode: .common)
            }
        }
    }
    func checkHover(mouse: NSPoint = NSEvent.mouseLocation, now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !recentChats.list.isReordering else { return }
        let target: NotchPane = quotaButtonFrame.contains(mouse) ? .usage : windowButtonFrame.contains(mouse) ? .windowUsage : chatButtonFrame.contains(mouse) ? .chats : settingsButtonFrame.contains(mouse) ? .settings : .none
        if let next = hover.update(target: target,now: now,enabled: preferences.value.hoverToOpen), selectedPane != next { setPane(next) }
    }
    func dismissUsageOutside(mouse: NSPoint = NSEvent.mouseLocation) {
        if selectedPane == .settings, NSColorPanel.shared.isVisible, NSColorPanel.shared.frame.contains(mouse) { return }
        if selectedPane != .none && !panel.frame.contains(mouse) { setPane(.none) }
    }
    func installDismissMonitors() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown,.rightMouseDown],handler: { [weak self] _ in self?.dismissUsageOutside() }) { dismissMonitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown,.rightMouseDown,.keyDown],handler: { [weak self] event in
            guard let self else { return event }
            // The native color panel belongs to Settings and has its own event handling.
            if self.selectedPane == .settings, event.window != nil, event.window !== self.panel { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 && self.recentChats.list.isReordering { return event }
                if event.keyCode == 53 && self.selectedPane != .none { self.setPane(.none); return nil }
            } else { self.dismissUsageOutside() }
            return event
        }) { dismissMonitors.append(monitor) }
    }

    func cliURL() -> URL? {
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        let paths = [
            ProcessInfo.processInfo.environment["CODEX_BIN"] ?? "",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            userApps + "/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            userApps + "/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ]
        return paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

    func startServer() {
        guard let executable = cliURL() else { fail("Codex CLI not found"); return }
        let proc = Process()
        let stdinPipe = Pipe(), stdoutPipe = Pipe()
        let connectionID = UUID()
        generation = connectionID
        buffer.removeAll()
        proc.executableURL = executable
        proc.arguments = ["app-server"]
        proc.currentDirectoryURL = stateURL.deletingLastPathComponent()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = FileHandle.nullDevice
        input = stdinPipe.fileHandleForWriting
        output = stdoutPipe.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                guard let self, self.generation == connectionID else { return }
                if data.isEmpty { self.fail("Usage connection closed"); return }
                self.receive(data)
            }
        }
        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == connectionID, !self.quitting else { return }
                self.fail("Usage service stopped")
            }
        }
        server = proc
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try proc.run()
            send(["method": "initialize", "id": 0, "params": ["clientInfo": ["name": "notchgpt", "title": "notchGPT", "version": "2.1.0"]]])
        } catch { fail("Could not start usage service") }
    }

    func send(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(10)
        do { try input?.write(contentsOf: data) }
        catch { fail("Usage connection unavailable") }
    }

    func receive(_ data: Data) {
        buffer.append(data)
        while let end = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: end)
            buffer.removeSubrange(...end)
            guard let obj = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            if (obj["id"] as? Int) == 0 {
                guard obj["error"] == nil else { fail("Initialization failed"); return }
                send(["method": "initialized", "params": [:]])
                requestLimits()
            } else if (obj["id"] as? Int) == 1 {
                timeout?.invalidate(); timeout = nil
                guard let result = obj["result"] as? [String: Any] else {
                    fail("Usage unavailable: check ChatGPT sign-in"); return
                }
                let buckets = result["rateLimitsByLimitId"] as? [String: Any]
                guard let snapshot = (buckets?["codex"] as? [String: Any]) ?? (result["rateLimits"] as? [String: Any]),
                      let percent = remaining(snapshot) else { fail("No percentage available"); return }
                view.accountWindows = AccountQuotaWindow.parse(snapshot)
                view.accountUpdated = Date()
                view.percent = percent
                view.weeklyUsed = WeeklyQuota(snapshot)?.used
                let now = Date()
                if let weekly = WeeklyQuota(snapshot) {
                    fourHourHistory.sample(used: weekly.used, resetsAt: weekly.resetsAt, at: now)
                    view.history = fourHourHistory
                    do {
                        try JSONEncoder().encode(fourHourHistory).write(to: historyURL, options: .atomic)
                    } catch { dailyStorageError = true }
                }
                if let weekly = WeeklyQuota(snapshot) {
                    var budget = DailyBudget.sample(previous: dailyBudget, quota: weekly, now: now)
                    budget.recoverObservedMinimum(fourHourHistory.observedMinimum(day: budget.day))
                    dailyBudget = budget
                    view.dailyDay = budget.day
                    view.dailySpent = budget.spent
                    view.dailyPercent = budget.remainingPercent(weekly: weekly, now: now)
                    do {
                        try JSONEncoder().encode(budget).write(to: dailyURL, options: .atomic)
                        dailyStorageError = false
                    } catch { dailyStorageError = true }
                } else { view.dailyPercent = nil; view.dailySpent = nil; view.dailyDay = nil }
                lastUpdated = now
                lastError = nil
                saveState()
            }
        }
    }

    @objc func refresh() {
        guard timeout == nil else { return }
        timeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in self?.fail("Usage request timed out") }
        if server?.isRunning == true { requestLimits() } else { startServer() }
    }

    func requestLimits() { send(["method": "account/rateLimits/read", "id": 1]) }

    func fail(_ message: String) {
        timeout?.invalidate(); timeout = nil
        lastError = message
        view.accountWindows = []; view.accountUpdated = nil
        view.percent = nil // Never present a stale number as current.
        view.dailyPercent = nil
        view.weeklyUsed = nil
        view.dailySpent = nil; view.dailyDay = nil
        stopServer()
        saveState()
    }

    func stopServer() {
        generation = UUID()
        output?.readabilityHandler = nil
        try? input?.close()
        input = nil
        if let proc = server, proc.isRunning { proc.terminate() }
        server = nil
        output = nil
        buffer.removeAll()
    }

    func saveState() {
        var state: [String: Any] = ["source": "account/rateLimits/read", "sharedWithChatGPTWork": true,
            "hoverToOpen": preferences.value.hoverToOpen, "pane": selectedPane.rawValue,
            "display": view.percent.map { "\($0)%" } ?? "—%", "visible": panel?.isVisible ?? false]
        if let percent = view.percent { state["remainingPercent"] = percent }
        if let percent = view.dailyPercent { state["dailyRemainingPercent"] = percent }
        if let weeklyUsed = view.weeklyUsed,
           let percent = fourHourHistory.windowRemainingPercent(weeklyUsed: weeklyUsed, at: Date()) {
            state["windowRemainingPercent"] = percent
        }
        state["windowAllowanceWeeklyPercent"] = FourHourHistory.windowAllowance
        state["dailyAllowanceWeeklyPercent"] = DailyBudget.allowance
        if let budget = dailyBudget {
            state["dailySpentWeeklyPercent"] = budget.spent
            state["dailyCompleteDay"] = budget.completeDay
        }
        state["fourHourEstimatedBlocks"] = fourHourHistory.blocks.count
        state["fourHourLastEstimate"] = fourHourHistory.blocks.last?.used
        if let date = lastUpdated { state["lastUpdated"] = ISO8601DateFormatter().string(from: date) }
        if let error = lastError { state["error"] = error }
        if let panel { state["frame"] = NSStringFromRect(panel.frame) }
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: stateURL, options: .atomic)
        }
    }

    func showMenu(_ event: NSEvent, for source: NSView? = nil) {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Codex and ChatGPT Work: shared allowance", action: nil, keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(withTitle: "Window: 10% of weekly allowance per 09–13 / 14–18 block", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Local estimate; no carry-over; weekends excluded", action: nil, keyEquivalent: "")
        if let block = fourHourHistory.selected(at: Date()), let since = block.trackingSince {
            let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
            menu.addItem(withTitle: "Window uses observed samples since \(formatter.string(from: since))", action: nil, keyEquivalent: "")
        }
        if dailyStorageError {
            menu.addItem(withTitle: "Could not save usage history; keep app running", action: nil, keyEquivalent: "")
        }
        if let date = lastUpdated {
            let formatter = DateFormatter(); formatter.timeStyle = .short
            menu.addItem(withTitle: "Updated at \(formatter.string(from: date))", action: nil, keyEquivalent: "")
        }
        if let error = lastError { menu.addItem(withTitle: error, action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        let settings = menu.addItem(withTitle: "Settings…", action: #selector(toggleSettings), keyEquivalent: ",")
        settings.target = self
        let update = menu.addItem(withTitle: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        update.target = self
        let quit = menu.addItem(withTitle: "Quit notchGPT", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        NSMenu.popUpContextMenu(menu, with: event, for: source ?? view)
    }

    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        quitting = true
        frameAnimationTimer?.invalidate(); pollTimer?.invalidate(); timeout?.invalidate()
        dismissMonitors.forEach(NSEvent.removeMonitor); dismissMonitors.removeAll()
        recentChats.stop()
        hoverTimer?.invalidate()
        stopServer()
    }
}

func sampleChats() -> [RecentChat] {
    let titles = ["Add recent chat list", "Manage remote host", "Check cloud environment", "Fix dashboard layout", "Update macOS application", "Analyze server logs", "Prepare weekly report", "Check build and tests", "Configure environment", "Project documentation"]
    return titles.enumerated().map { index,title in
        RecentChat(id: String(format: "00000000-0000-4000-8000-%012d", index + 1),title: title,
                   state: ["running","waiting for input","stopped","notified"][index % 4],origin: ["Mac","Remote","Cloud"][index % 3],
                   hostId: index % 3 == 1 ? "ssh:example" : "local",hostName: index % 3 == 1 ? (index == 1 ? "example-workstation" : "example-server") : nil,kind: "codex")
    }
}

let arguments = CommandLine.arguments
if let demo = arguments.firstIndex(of: "--demo-pinned-chats"), arguments.count > demo + 1 {
    let app = NSApplication.shared; app.setActivationPolicy(.accessory)
    let delegate = AppDelegate(); delegate.testing = true
    let demoURL = URL(fileURLWithPath: arguments[demo + 1])
    delegate.preferences = PreferencesStore(url: demoURL)
    if !FileManager.default.fileExists(atPath: demoURL.path) {
        var initial = AppPreferences(); initial.pinnedChats = Array(sampleChats().prefix(6).map(\.pin))
        try! delegate.preferences.save(initial)
    }
    delegate.buildInterface(); delegate.recentChats.setPreview(sampleChats())
    delegate.panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
    delegate.recentChats.list.onOpenChat = { _ in print("DEMO: chat open action"); fflush(stdout) }
    delegate.setPane(.chats,animated: false)
    app.run()
} else if arguments.contains("--test-live-chats") {
    _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
    let delegate = AppDelegate(); delegate.testing = true; delegate.preferences = PreferencesStore(url: nil)
    delegate.buildInterface(); delegate.recentChats.testing = false
    delegate.setPane(.chats,animated: false)
    let end = Date().addingTimeInterval(24)
    while delegate.recentChats.list.rows.subviews.count < 10 && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    let rows = delegate.recentChats.list.rows.subviews.compactMap { ($0 as? ChatRow)?.openButton }
    precondition(rows.count == 10 && rows.allSatisfy(\.isEnabled), "live metadata must produce ten valid chat links")
    print("PASS live metadata: ten recent chats with valid links and host identity")
    delegate.recentChats.stop(); delegate.panel.orderOut(nil)
} else if arguments.contains(where: { ["--test-ui","--test-settings","--test-click","--test-hover","--test-chats"].contains($0) }) {
    _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
    let delegate = AppDelegate(); delegate.testing = true; delegate.preferences = PreferencesStore(url: nil)
    delegate.buildInterface(); delegate.recentChats.setPreview(sampleChats())
    let fixtures = sampleChats()
    for (states, expected): ([String], ChatAttention) in [([], .none), (["waiting for input"], .input), (["notified"], .notified), (["waiting for input", "notified"], .combined), (["running", "stopped"], .none)] {
        let chats = fixtures.filter { states.contains($0.state ?? "") }
        precondition(ChatAttention(chats: chats) == expected, "chat attention aggregation")
        delegate.recentChats.setPreview(chats)
        precondition(delegate.chatButton.attention == expected, "header receives attention updates")
    }
    delegate.recentChats.setPreview(fixtures)
    func verifySymmetry() {
        let notch = delegate.physicalNotchFrame
        let left = notch.minX - delegate.panel.frame.minX
        let right = delegate.panel.frame.maxX - notch.maxX
        precondition(abs(left - right) < 0.01,"closed extensions must be equal on both sides of the physical notch")
        precondition(abs(left - 76) < 0.01,"both closed extensions must stay exactly 76 pt at every text size")
        let chats = delegate.panel.convertToScreen(delegate.chatButton.frame)
        let settings = delegate.panel.convertToScreen(delegate.settingsButton.frame)
        precondition(abs(chats.minX - notch.maxX) < 0.01 && abs(chats.maxX - settings.minX) < 0.01)
        precondition(abs(settings.maxX - delegate.panel.frame.maxX) < 0.01 && abs(chats.width - settings.width) < 0.01)
    }
    for textSize in [10,11,12] {
        var value = delegate.preferences.value; value.textSize = textSize
        delegate.applyPreferences(value)
        verifySymmetry()
        let rings = delegate.view.subviews.compactMap { $0 as? AllowanceRing }
        precondition(rings.count == 2 && abs(rings[0].frame.midY - rings[1].frame.midY) < 0.01,
                     "both allowance dials must be side by side")
        precondition(abs(rings[0].frame.midX - 19) < 0.01 && abs(rings[1].frame.midX - 57) < 0.01)
        precondition(rings.allSatisfy { delegate.view.readoutRect.contains($0.frame) })
        for (ring,button) in zip(rings,[delegate.chatButton,delegate.settingsButton]) {
            let leftCircle = delegate.view.convert(ring.frame,to: delegate.glassView)
            let rightCircle = button.convert(button.circleFrame,to: delegate.glassView)
            precondition(leftCircle.size == rightCircle.size && abs(leftCircle.midY - rightCircle.midY) < 0.01,
                         "right-hand controls must match the allowance circle size and vertical alignment")
        }
        let sample = AllowanceRing(name: "Fit check",tint: .systemCyan)
        sample.frame = rings[0].bounds; sample.update(100,animated: false)
        precondition(sample.valueLabel.string == "100%" && sample.valueLabel.size().width <= sample.bounds.width - 8 + 0.01,
                     "100% must fit inside the circle at every text size")
        precondition(Set([NotchPane.usage,.windowUsage,.chats,.settings].map { delegate.frame(for: $0).height }).count == 1,
                     "usage, chats and settings must have exactly the same expanded height")
        print("PASS closed-notch symmetry at text size \(textSize): left = right = \(delegate.compactWidth) pt")
    }
    let ring = AllowanceRing(name: "Test allowance",tint: .systemCyan)
    ring.update(20,animated: false); ring.update(80,animated: true)
    RunLoop.main.run(until: Date().addingTimeInterval(0.45))
    precondition(abs(ring.displayedFraction - 0.8) < 0.001 && !ring.isAnimating)
    ring.update(nil,animated: true)
    precondition(ring.displayedFraction == 0 && !ring.isAnimating,"unavailable readings must not animate or imply known usage")
    print("PASS animated allowance rings: settle on the real value and stop for unavailable readings")
    delegate.applyPreferences(AppPreferences())
    let header = delegate.headerFrame
    precondition(header.height > 0)
    precondition(!delegate.preferences.value.hoverToOpen)
    let hoverPoint = NSPoint(x: delegate.quotaButtonFrame.midX,y: header.midY)
    delegate.checkHover(mouse: hoverPoint,now: 10); delegate.checkHover(mouse: hoverPoint,now: 11)
    precondition(delegate.selectedPane == .none,"hover must be disabled by default")
    func settle() {
        for _ in 0..<18 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            precondition(abs(delegate.panel.frame.maxY - delegate.headerFrame.maxY) < 1)
            precondition(abs(delegate.panel.frame.maxX - delegate.settingsButtonFrame.maxX) < 1,"pane must reach right edge of settings")
            verifySymmetry()
            let button = delegate.panel.convertToScreen(delegate.settingsButton.frame)
            precondition(abs(button.minY - delegate.headerFrame.minY) < 1,"header button moved during animation")
        }
    }
    for cycle in 1...3 {
        let dials = delegate.view.subviews.compactMap { $0 as? AllowanceRing }
        precondition(dials[0].accessibilityPerformPress()); settle()
        precondition(delegate.selectedPane == .usage && delegate.view.statisticsPane == .usage)
        precondition(dials[1].accessibilityPerformPress()); settle()
        precondition(delegate.selectedPane == .windowUsage && delegate.view.statisticsPane == .windowUsage)
        delegate.chatButton.performClick(nil); settle()
        precondition(delegate.selectedPane == .chats && delegate.recentChats.list.rows.subviews.count == 10)
        let list = delegate.recentChats.list
        list.layoutSubtreeIfNeeded()
        precondition(list.rows.bounds.height > list.scroll.contentSize.height && list.scroll.hasVerticalScroller,
                     "the ten-chat document must scroll within the compact pane")
        let top = list.scroll.documentVisibleRect.origin
        precondition(list.rows.subviews[0].frame.intersects(list.scroll.documentVisibleRect))
        list.rows.scroll(.zero)
        precondition(list.rows.subviews[9].frame.intersects(list.scroll.documentVisibleRect),"the last chat must be reachable by scrolling")
        list.rows.scroll(top)
        delegate.settingsButton.performClick(nil); settle()
        precondition(delegate.selectedPane == .settings)
        precondition(delegate.settingsView.window === delegate.panel && delegate.recentChats.list.window === delegate.panel)
        delegate.dismissUsageOutside(mouse: NSPoint(x: header.minX - 100,y: header.minY - 700)); settle()
        precondition(delegate.selectedPane == .none && delegate.panel.frame.height == header.height)
        print("PASS unified pane cycle \(cycle): usage, chats, settings, one surface, full width, stable header")
    }
    delegate.toggleSettings(); settle()
    delegate.settingsView.hover.performClick(nil)
    precondition(delegate.preferences.value.hoverToOpen)
    delegate.setPane(.none,animated: false)
    delegate.checkHover(mouse: hoverPoint,now: 20); delegate.checkHover(mouse: hoverPoint,now: 20.4)
    precondition(delegate.selectedPane == .usage,"enabled hover must open usage after dwell")
    delegate.toggleUsage(); delegate.checkHover(mouse: hoverPoint,now: 21)
    precondition(delegate.selectedPane == .none,"a clicked close must stay closed under the pointer")
    delegate.toggleSettings(); settle()
    delegate.settingsView.hover.performClick(nil)
    precondition(!delegate.preferences.value.hoverToOpen)
    delegate.settingsView.textSize.selectItem(withTag: 12)
    delegate.settingsView.textSize.sendAction(delegate.settingsView.textSize.action!,to: delegate.settingsView.textSize.target)
    precondition(delegate.preferences.value.textSize == 12 && delegate.selectedPane == .settings)
    delegate.settingsView.chatCount.selectItem(withTag: 5)
    delegate.settingsView.chatCount.sendAction(delegate.settingsView.chatCount.action!,to: delegate.settingsView.chatCount.target)
    delegate.toggleChats(); settle()
    precondition(delegate.recentChats.list.rows.subviews.count == 5)
    precondition(Set([NotchPane.usage,.windowUsage,.chats,.settings].map { delegate.frame(for: $0).height }).count == 1,
                 "reducing the chat count must preserve the common dropdown height")
    delegate.setPane(.settings,animated: false)
    delegate.settingsView.quotaColor.showPicker()
    precondition(NSColorPanel.shared.isVisible && delegate.selectedPane == .settings)
    delegate.dismissUsageOutside(mouse: NSPoint(x: NSColorPanel.shared.frame.midX,y: NSColorPanel.shared.frame.midY))
    precondition(delegate.selectedPane == .settings,"the color panel belongs to Settings")
    delegate.settingsView.quotaColor.color = .dialColor("#B58A1B")
    delegate.settingsView.quotaColor.sendAction(delegate.settingsView.quotaColor.action!,to: delegate.settingsView.quotaColor.target)
    delegate.settingsView.windowColor.color = .dialColor("#7040A0")
    delegate.settingsView.windowColor.sendAction(delegate.settingsView.windowColor.action!,to: delegate.settingsView.windowColor.target)
    precondition(delegate.preferences.value.quotaColorHex == "#B58A1B" && delegate.preferences.value.windowColorHex == "#7040A0")
    let coloredDials = delegate.view.subviews.compactMap { $0 as? AllowanceRing }
    precondition(coloredDials[0].tint.dialHex == delegate.chatButton.tint.dialHex && coloredDials[1].tint.dialHex == delegate.settingsButton.tint.dialHex)
    precondition(delegate.chatButton.tint.dialHex == "#B58A1B" && delegate.settingsButton.tint.dialHex == "#7040A0")
    delegate.setPane(.none,animated: false)
    var hoverPreferences = delegate.preferences.value; hoverPreferences.hoverToOpen = true
    delegate.applyPreferences(hoverPreferences)
    let windowHover = NSPoint(x: delegate.windowButtonFrame.midX,y: header.midY)
    delegate.checkHover(mouse: windowHover,now: 30); delegate.checkHover(mouse: windowHover,now: 30.4)
    precondition(delegate.selectedPane == .windowUsage,"the second dial must hover-open its own statistics")
    delegate.toggleWindowUsage(); delegate.checkHover(mouse: windowHover,now: 31)
    precondition(delegate.selectedPane == .none,"the window dial must also suppress immediate hover reopen")
    print("PASS separate statistics: independent dial clicks, independent hover targets, persistent colors and matching right-hand buttons")
    print("PASS compact equal-height panes, ten-chat scrolling and centered percentages")
    var opened: String?
    delegate.recentChats.list.onOpenChat = { opened = $0.id }
    delegate.recentChats.setPreview(sampleChats())
    (delegate.recentChats.list.rows.subviews.first as? ChatRow)?.openButton.performClick(nil)
    precondition(opened == sampleChats()[0].id,"chat rows must activate their own chat link")
    let remote = sampleChats()[1].linkURL!
    precondition(URLComponents(url: remote,resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "ssh:example")
    let chatsBeforePin = delegate.recentChats.list.rows.subviews.compactMap { $0 as? ChatRow }
    let pinnedChat = chatsBeforePin.last!.chat
    opened = nil
    chatsBeforePin.last!.pinButton.performClick(nil)
    precondition(opened == nil && delegate.preferences.value.pinnedChats.contains(pinnedChat.pin),"pinning may not navigate")
    precondition((delegate.recentChats.list.rows.subviews.first as? ChatRow)?.chat.pin == pinnedChat.pin,"pinned chats must move to the top")
    (delegate.recentChats.list.rows.subviews.first as? ChatRow)?.pinButton.performClick(nil)
    precondition(!delegate.preferences.value.pinnedChats.contains(pinnedChat.pin),"unpin must restore recency order")
    print("PASS pinned chats: independent pin/link actions, immediate ordering and unpin")
    var dragPreferences = delegate.preferences.value
    dragPreferences.chatCount = 10; dragPreferences.pinnedChats = Array(sampleChats().prefix(6).map(\.pin))
    delegate.applyPreferences(dragPreferences)
    delegate.setPane(.chats,animated: false)
    let dragList = delegate.recentChats.list
    dragList.layoutSubtreeIfNeeded()
    let originalRows = dragList.rows.subviews.compactMap { $0 as? ChatRow }
    precondition(originalRows.prefix(6).allSatisfy { $0.dragHandle?.owner === dragList })
    precondition(originalRows.suffix(4).allSatisfy { $0.dragHandle == nil },"only pinned chats can be dragged")
    let firstPin = originalRows[0].chat.pin, sixthPin = originalRows[5].chat.pin
    let topDrop = dragList.rows.insertion(at: NSPoint(x: 20,y: originalRows[0].frame.maxY))!
    precondition(topDrop.before == firstPin)
    let boundaryDrop = dragList.rows.insertion(at: NSPoint(x: 20,y: originalRows[6].frame.midY))!
    precondition(boundaryDrop.before == nil && boundaryDrop.y == originalRows[5].frame.minY,
                 "dropping over recents must clamp to the end of the pinned group")
    opened = nil
    dragList.rows.scroll(NSPoint(x: 0,y: 80))
    let savedDragScroll = dragList.scroll.contentView.bounds.origin
    dragList.beginPinnedDrag()
    delegate.recentChats.setPreview(Array(sampleChats().reversed()))
    precondition(dragList.rows.subviews[0] === originalRows[0],"refresh may not remove the native drag source")
    precondition(dragList.reorder(sixthPin,before: firstPin))
    precondition(opened == nil && delegate.preferences.value.pinnedChats.first == sixthPin)
    precondition(dragList.rows.subviews[0] === originalRows[0],"drop must retain source until the session ends")
    dragList.endPinnedDrag()
    precondition((dragList.rows.subviews.first as? ChatRow)?.chat.pin == sixthPin)
    precondition(dragList.scroll.contentView.bounds.origin == savedDragScroll,"committing a reorder must preserve the user's scroll position")
    precondition(delegate.preferences.value.pinnedChats.count == 6,"reordering cannot pin or unpin another chat")
    dragList.beginPinnedDrag(); dragList.endPinnedDrag()
    precondition(delegate.preferences.value.pinnedChats.first == sixthPin,"cancelled drag does not change order")
    let sourceRow = dragList.rows.subviews.compactMap { $0 as? ChatRow }.first!
    dragList.layoutSubtreeIfNeeded(); sourceRow.layoutSubtreeIfNeeded()
    let handle = sourceRow.dragHandle!
    let grab = handle.convert(NSPoint(x: handle.bounds.midX,y: handle.bounds.midY),to: nil)
    let beforeScroll = dragList.rows.visibleRect.minY
    let edge = dragList.rows.convert(NSPoint(x: 40,y: beforeScroll + 1),to: nil)
    let beforeCancel = delegate.preferences.value.pinnedChats
    dragList.beginPinnedDrag(from: handle,at: grab)
    for _ in 0..<8 { dragList.updatePinnedDrag(at: edge) }
    precondition(dragList.rows.visibleRect.minY < beforeScroll && dragList.rows.insertionY != nil,
                 "dragging near the viewport edge must scroll and keep an insertion marker")
    dragList.finishPinnedDrag(at: NSPoint(x: -1000,y: -1000))
    precondition(!dragList.isReordering && delegate.preferences.value.pinnedChats == beforeCancel && opened == nil,
                 "release outside the list cancels without navigation or order changes")
    var fivePins = delegate.preferences.value; fivePins.chatCount = 5
    delegate.applyPreferences(fivePins)
    let visiblePins = dragList.rows.subviews.compactMap { $0 as? ChatRow }
    let lastVisible = visiblePins.last!
    let hiddenBoundary = dragList.rows.insertion(at: NSPoint(x: 20,y: lastVisible.frame.minY - 1))!
    precondition(hiddenBoundary.before == fivePins.pinnedChats[5],"five-chat mode must preserve the first hidden pin's relative position")
    print("PASS pinned drag/drop: insertion geometry, pinned-only handles, refresh deferral, no navigation, committed order, autoscroll, hidden pins and cancellation")
    print("PASS settings: default hover off, live toggles, dwell, no reopen, text scaling, chat count and chat links")
    delegate.recentChats.stop(); delegate.panel.orderOut(nil)
} else if let option = arguments.firstIndex(where: { ["--preview-account","--preview-settings","--preview-chats","--preview-expanded","--preview-large","--preview-empty","--preview-partial","--preview"].contains($0) }), arguments.count > option + 1 {
    _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
    let delegate = AppDelegate(); delegate.testing = true; delegate.preferences = PreferencesStore(url: nil)
    if arguments[option] == "--preview-large" || arguments.contains("--text-large") || arguments.contains("--text-compact") {
        var value = AppPreferences(); value.textSize = arguments.contains("--text-compact") ? 10 : 12
        try! delegate.preferences.save(value)
    }
    delegate.buildInterface(); delegate.recentChats.setPreview(sampleChats())
    let calendar = Calendar.current
    let today = Date()
    let now = calendar.date(bySettingHour: 18, minute: 1, second: 0, of: today)!
    delegate.view.displayDate = now
    delegate.view.percent = 58; delegate.view.weeklyUsed = 42
    delegate.view.accountWindows = AccountQuotaWindow.parse([
        "primary": ["usedPercent": 18, "windowDurationMins": 300, "resetsAt": now.addingTimeInterval(3600).timeIntervalSince1970],
        "secondary": ["usedPercent": 42, "windowDurationMins": 10080, "resetsAt": now.addingTimeInterval(172800).timeIntervalSince1970]])
    delegate.view.accountUpdated = now
    var previewHistory = FourHourHistory()
    if arguments[option] != "--preview-empty" {
        for hour in [9,14] {
            let opening = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now)!
            var samples = [UsageSample(time: opening,used: 0)]
            var used = 0.0
            for minute in 1...240 {
                if arguments[option] == "--preview-partial", hour == 9, minute <= 100 { continue }
                let start = opening.addingTimeInterval(Double(minute - 1) * 60)
                let amount = [0.010,0.025,0.006,0.040,0.018,0.0,0.028,0.013][(minute - 1) / 30]
                used += amount * (hour == 9 ? 1 : 0.8)
                samples.append(UsageSample(time: opening.addingTimeInterval(Double(minute) * 60),used: used,intervalStart: start))
            }
            previewHistory.blocks.append(UsageBlock(day: FourHourHistory.dayKey(now),startHour: hour,samples: samples,baseline: 34,latest: 34 + used))
        }
    }
    delegate.view.history = previewHistory
    if arguments.contains("--values-full") { delegate.view.percent = 100; delegate.view.weeklyUsed = 0; delegate.view.history = FourHourHistory(blocks: [UsageBlock(day: FourHourHistory.dayKey(now),startHour: 14,samples: [UsageSample(time: now.addingTimeInterval(-60),used: 0)],baseline: 0,latest: 0)]) }
    if arguments.contains("--values-zero") { delegate.view.percent = 0; delegate.view.weeklyUsed = 100 }
    if arguments.contains("--values-unavailable") { delegate.view.percent = nil; delegate.view.weeklyUsed = nil }
    let pane: NotchPane = arguments[option] == "--preview-settings" ? .settings : arguments[option] == "--preview-chats" ? .chats : arguments[option] == "--preview" ? .none : arguments[option] == "--preview-account" ? .usage : .windowUsage
    delegate.setPane(pane,animated: false)
    delegate.settingsView.layoutSubtreeIfNeeded(); delegate.recentChats.list.layoutSubtreeIfNeeded()
    // A fixed backing makes synthetic previews comparable across all panes.
    delegate.panel.backgroundColor = NSColor(calibratedWhite: 0.055,alpha: 1)
    delegate.glassView.blendingMode = .withinWindow
    let rep = delegate.glassView.bitmapImageRepForCachingDisplay(in: delegate.glassView.bounds)!
    delegate.glassView.cacheDisplay(in: delegate.glassView.bounds,to: rep)
    try rep.representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath: arguments[option + 1]))
    delegate.panel.orderOut(nil)
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate(); app.delegate = delegate; app.run()
}
