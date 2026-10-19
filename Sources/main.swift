import AppKit
import QuartzCore

// Passive client of the official Codex app-server. Never starts model turns.

private enum NotchLayout {
    static let compactWidth: CGFloat = 110
}

final class NotchView: NSView {
    private let compactWidth = NotchLayout.compactWidth
    private let textInset: CGFloat = 12
    var compactHeight: CGFloat = 38
    var readoutRect: NSRect { NSRect(x: 0, y: bounds.height - compactHeight, width: compactWidth, height: compactHeight) }
    var percent: Int? { didSet { needsDisplay = true } }
    var weeklyUsed: Double?
    var dailySpent: Double?
    var dailyPercent: Int? { didSet { needsDisplay = true } }
    var history: FourHourHistory? { didSet { needsDisplay = true } }
    var expanded = false { didSet { needsDisplay = true } }
    var menuAction: ((NSEvent) -> Void)?
    var hoverAction: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hoverAction?(true) }
    override func mouseExited(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if expanded && NSPointInRect(point, bounds) { return }
        hoverAction?(false)
    }

    override func draw(_ dirtyRect: NSRect) {
        // One material/tint and one header layout in every animation state.
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18)
        NSColor(calibratedWhite: 0.015, alpha: 0.10).setFill()
        card.fill()
        drawReadout()
        if expanded { drawExpanded() }
    }

    private func drawReadout() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let windowPercent = weeklyUsed.flatMap { history?.windowRemainingPercent(weeklyUsed: $0, at: Date()) }
        for (index, row) in [("chatGPT", percent), ("window", windowPercent)].enumerated() {
            let value = row.1.map { "\($0)%" } ?? "—%"
            let size = (value as NSString).size(withAttributes: attrs)
            let centerY = readoutRect.midY + (index == 0 ? 7.5 : -7.5)
            let labelStart = textInset
            (row.0 as NSString).draw(at: NSPoint(x: labelStart, y: centerY - size.height / 2), withAttributes: attrs)
            (value as NSString).draw(at: NSPoint(x: compactWidth - textInset - size.width, y: centerY - size.height / 2), withAttributes: attrs)
        }
    }

    private func drawExpanded() {
        let topOffset = bounds.height - compactHeight
        let now = Date()
        let block = history?.selected(at: now)
        let metricAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        // Keep a consistent 12 pt inset from the notch and card edges.
        let topMetricY = topOffset - 22
        var pace = "—"
        var projection = "—"
        if let block, let estimate = WindowEstimate(block, at: now) {
            pace = decimal(estimate.pace)
            projection = "\(decimal(estimate.projected))%"
        }
        drawCompactMetric("window", value: block.map { $0.startHour == 9 ? "09–13" : "14–18" } ?? "—", y: topMetricY, attrs: metricAttrs)
        drawCompactMetric("pace %/h", value: pace, y: topMetricY - 14, attrs: metricAttrs)
        drawCompactMetric("estimate", value: projection, y: topMetricY - 28, attrs: metricAttrs)
        drawRightMetric("weekly used", value: weeklyUsed.map { "\(decimal($0))%" } ?? "—", y: topMetricY, attrs: metricAttrs)
        drawRightMetric("window used", value: block.map { "\(decimal($0.used / FourHourHistory.windowAllowance * 100))%" } ?? "—", y: topMetricY - 14, attrs: metricAttrs)
        drawRightMetric("samples", value: block.map { "\($0.samples.count)" } ?? "0", y: topMetricY - 28, attrs: metricAttrs)

        let chartRect = NSRect(x: 32, y: 24, width: bounds.width - 44, height: 32)
        let windowTitle = "window usage · \(block.map { $0.startHour == 9 ? "09–13" : "14–18" } ?? "—")"
        drawRight(windowTitle, right: bounds.width - textInset, y: chartRect.maxY + 12,
                  attrs: [.font: NSFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: NSColor(calibratedWhite: 0.82, alpha: 1)])
        drawChart(points: block?.samples ?? [], startHour: block?.startHour ?? 9,
                  since: block?.trackingSince, plotRect: chartRect)
        drawChartAxisLabels(startHour: block?.startHour ?? 9, rect: chartRect)
    }

    private func decimal(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func drawCompactMetric(_ label: String, value: String, y: CGFloat,
                                   attrs: [NSAttributedString.Key: Any]) {
        let valueSize = (value as NSString).size(withAttributes: attrs)
        let labelStart = textInset
        (label as NSString).draw(at: NSPoint(x: labelStart, y: y), withAttributes: attrs)
        (value as NSString).draw(at: NSPoint(x: compactWidth - textInset - valueSize.width, y: y), withAttributes: attrs)
    }

    private func drawRightMetric(_ label: String, value: String, y: CGFloat,
                                 attrs: [NSAttributedString.Key: Any]) {
        (label as NSString).draw(at: NSPoint(x: compactWidth + textInset, y: y), withAttributes: attrs)
        drawRight(value, right: bounds.width - textInset, y: y, attrs: attrs)
    }

    private func muted(_ attrs: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var copy = attrs; copy[.foregroundColor] = NSColor(calibratedWhite: 0.72, alpha: 1); return copy
    }

    private func drawRight(_ string: String, right: CGFloat, y: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        let size = (string as NSString).size(withAttributes: attrs)
        (string as NSString).draw(at: NSPoint(x: right - size.width, y: y), withAttributes: attrs)
    }

    private func drawCentered(_ string: String, y: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        let size = (string as NSString).size(withAttributes: attrs)
        (string as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: y), withAttributes: attrs)
    }

    private func drawChart(points: [UsageSample], startHour: Int, since: Date?, plotRect rect: NSRect) {
        let grid = NSBezierPath()
        for y in [rect.minY, rect.midY, rect.maxY] {
            grid.move(to: NSPoint(x: rect.minX, y: y)); grid.line(to: NSPoint(x: rect.maxX, y: y))
        }
        for x in [rect.minX, rect.midX, rect.maxX] {
            grid.move(to: NSPoint(x: x, y: rect.minY)); grid.line(to: NSPoint(x: x, y: rect.maxY))
        }
        NSColor(calibratedRed: 0.34, green: 0.42, blue: 0.52, alpha: 0.2).setStroke(); grid.lineWidth = 0.7; grid.stroke()
        let axisAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 7, weight: .regular), .foregroundColor: NSColor(calibratedWhite: 0.58, alpha: 1)]
        let maxAxis = points.map(\.used).max() ?? 0
        let upperAxis = chartUpperBound(for: maxAxis)
        (String(format: "%.1f", upperAxis) as NSString).draw(at: NSPoint(x: textInset, y: rect.maxY - 3), withAttributes: axisAttrs)
        ("0" as NSString).draw(at: NSPoint(x: textInset, y: rect.minY - 3), withAttributes: axisAttrs)
        if let since {
            let caption = "samples since \(timeString(since))" as NSString
            let captionAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 7.5, weight: .medium), .foregroundColor: NSColor(calibratedWhite: 0.62, alpha: 1)]
            caption.draw(at: NSPoint(x: textInset, y: rect.maxY + 6), withAttributes: captionAttrs)
        }
        guard !points.isEmpty else {
            let label = "waiting for samples"
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor(calibratedWhite: 0.64, alpha: 1)]
            (label as NSString).draw(at: NSPoint(x: rect.minX, y: rect.midY), withAttributes: attrs)
            return
        }
        let localDay = Calendar.current.startOfDay(for: points[0].time)
        let blockStart = Calendar.current.date(bySettingHour: startHour, minute: 0, second: 0, of: localDay)!
        let blockEnd = Calendar.current.date(bySettingHour: startHour + 4, minute: 0, second: 0, of: localDay)!
        let observedMaximum = points.map(\.used).max() ?? 0
        let maxValue = chartUpperBound(for: observedMaximum)
        let coordinates = points.map { point -> NSPoint in
            let fraction = max(0, min(1, point.time.timeIntervalSince(blockStart) / blockEnd.timeIntervalSince(blockStart)))
            return NSPoint(x: rect.minX + CGFloat(fraction) * rect.width,
                           y: rect.minY + CGFloat(min(max(0, point.used), maxValue) / maxValue) * rect.height)
        }
        let curve = NSBezierPath()
        curve.move(to: coordinates[0])
        // One point per sample: never index a synthetic extra point against the input array.
        for i in coordinates.indices.dropFirst() {
            if points[i].time.timeIntervalSince(points[i - 1].time) > 180 {
                curve.move(to: coordinates[i])
            } else {
                // The quota is observed at discrete times; preserve its flat/step shape.
                curve.line(to: NSPoint(x: coordinates[i].x, y: coordinates[i - 1].y))
                curve.line(to: coordinates[i])
            }
        }
        NSColor(calibratedRed: 0.16, green: 0.72, blue: 0.96, alpha: 0.22).setStroke()
        curve.lineWidth = 5; curve.lineCapStyle = .round; curve.lineJoinStyle = .round; curve.stroke()
        NSColor(calibratedRed: 0.42, green: 0.84, blue: 1, alpha: 1).setStroke()
        curve.lineWidth = 2; curve.stroke()
        if let point = coordinates.last {
            NSColor(calibratedRed: 0.45, green: 0.86, blue: 1, alpha: 0.22).setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)).fill()
            NSColor(calibratedRed: 0.72, green: 0.93, blue: 1, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)).fill()
        }
    }

    private func chartUpperBound(for maximum: Double) -> Double {
        guard maximum.isFinite, maximum > 0 else { return 0.5 }
        return max(0.5, ceil(maximum * 1.2 * 2) / 2)
    }

    private func drawChartAxisLabels(startHour: Int, rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 8, weight: .medium), .foregroundColor: NSColor(calibratedWhite: 0.62, alpha: 1)]
        let startText = String(format: "%02d", startHour) as NSString
        let midText = String(format: "%02d", startHour + 2) as NSString
        let endText = String(format: "%02d", startHour + 4) as NSString
        startText.draw(at: NSPoint(x: rect.minX - startText.size(withAttributes: attrs).width / 2, y: rect.minY - 12), withAttributes: attrs)
        midText.draw(at: NSPoint(x: rect.midX - midText.size(withAttributes: attrs).width / 2, y: rect.minY - 12), withAttributes: attrs)
        endText.draw(at: NSPoint(x: rect.maxX - endText.size(withAttributes: attrs).width / 2, y: rect.minY - 12), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        menuAction?(event)
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
    let compactWidth = NotchLayout.compactWidth
    let expandedHeight: CGFloat = 190
    var isExpanded = false
    var frameAnimationTimer: Timer?
    var hoverTimer: Timer?
    var outsideSince: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        if let data = try? Data(contentsOf: dailyURL) {
            dailyBudget = try? JSONDecoder().decode(DailyBudget.self, from: data)
        }
        if let data = try? Data(contentsOf: historyURL) {
            fourHourHistory = (try? JSONDecoder().decode(FourHourHistory.self, from: data)) ?? FourHourHistory()
        }
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        glassView.material = .hudWindow
        glassView.blendingMode = .behindWindow
        glassView.state = .active
        glassView.appearance = NSAppearance(named: .vibrantDark)
        glassView.wantsLayer = true
        glassView.layer?.cornerRadius = 18
        glassView.layer?.masksToBounds = true
        glassView.layer?.borderWidth = 0
        glassView.autoresizingMask = [.width, .height]
        view.autoresizingMask = [.width, .height]
        glassView.addSubview(view)
        panel.contentView = glassView
        view.menuAction = { [weak self] event in self?.showMenu(event) }
        view.hoverAction = { [weak self] entered in self?.setExpanded(entered) }
        view.toolTip = "Remaining allowance shared by Codex and ChatGPT Work. Click to refresh or quit."
        NotificationCenter.default.addObserver(self, selector: #selector(position), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        position()
        refresh()
        hoverTimer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in self?.checkHover() }
        RunLoop.main.add(hoverTimer!, forMode: .common)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    @objc func position() {
        isExpanded = false
        view.expanded = false
        outsideSince = nil
        // Choose the notched display even when an external monitor is the main screen.
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }),
              let left = screen.auxiliaryTopLeftArea else {
            panel.orderOut(nil)
            return
        }
        frameAnimationTimer?.invalidate()
        // The compact extension must end at the physical notch's lower edge.
        let h = screen.safeAreaInsets.top
        view.compactHeight = h
        let width = compactWidth
        let height = h
        // Keep the compact percentage widget immediately left of the notch.
        let x = left.maxX - compactWidth
        let top = screen.frame.maxY
        panel.setFrame(NSRect(x: x, y: top - height, width: width, height: height), display: true)
        glassView.frame = NSRect(origin: .zero, size: panel.frame.size)
        view.frame = glassView.bounds
        panel.orderFrontRegardless()
        saveState()
    }

    @objc func wake() { position(); stopServer(); refresh() }

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
            send(["method": "initialize", "id": 0, "params": ["clientInfo": ["name": "notchgpt", "title": "notchGPT", "version": "1.0.3"]]])
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
                    view.dailySpent = budget.spent
                    view.dailyPercent = budget.remainingPercent(weekly: weekly, now: now)
                    do {
                        try JSONEncoder().encode(budget).write(to: dailyURL, options: .atomic)
                        dailyStorageError = false
                    } catch { dailyStorageError = true }
                } else { view.dailyPercent = nil; view.dailySpent = nil }
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

    private func panelFrame(expanded: Bool) -> NSRect? {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }),
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return nil }
        let x = left.maxX - compactWidth
        let height = expanded ? expandedHeight : screen.safeAreaInsets.top
        return NSRect(x: x, y: screen.frame.maxY - height,
                      width: expanded ? right.minX - x : compactWidth, height: height)
    }

    func setExpanded(_ expanded: Bool) { checkHover() }

    func checkHover(mouse suppliedMouse: NSPoint? = nil, now: Date = Date()) {
        guard let target = panelFrame(expanded: isExpanded) else { return }
        let mouse = suppliedMouse ?? NSEvent.mouseLocation
        if target.insetBy(dx: isExpanded ? -4 : 0, dy: isExpanded ? -6 : 0).contains(mouse) {
            outsideSince = nil
            if !isExpanded { animateExpanded(true) }
        } else if isExpanded {
            if outsideSince == nil { outsideSince = now }
            if now.timeIntervalSince(outsideSince!) >= 0.4 { animateExpanded(false) }
        }
    }

    func animateExpanded(_ expanded: Bool) {
        guard isExpanded != expanded, let frame = panelFrame(expanded: expanded) else { return }
        isExpanded = expanded
        outsideSince = nil
        view.expanded = expanded
        panel.orderFrontRegardless()
        frameAnimationTimer?.invalidate()
        let initial = panel.frame
        let started = ProcessInfo.processInfo.systemUptime
        let duration = 0.24
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - started) / duration)
            let eased = progress * progress * (3 - 2 * progress)
            let width = initial.width + (frame.width - initial.width) * eased
            let height = initial.height + (frame.height - initial.height) * eased
            // Explicit frames avoid scaling a cached window image during collapse.
            let current = NSRect(x: frame.minX, y: frame.maxY - height, width: width, height: height)
            self.panel.setFrame(current, display: false)
            self.glassView.frame = NSRect(origin: .zero, size: current.size)
            self.view.frame = self.glassView.bounds
            self.view.needsDisplay = true
            self.panel.displayIfNeeded()
            if progress >= 1 {
                timer.invalidate()
                self.frameAnimationTimer = nil
                self.saveState()
            }
        }
        frameAnimationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func fail(_ message: String) {
        timeout?.invalidate(); timeout = nil
        lastError = message
        view.percent = nil // Never present a stale number as current.
        view.dailyPercent = nil
        view.weeklyUsed = nil
        view.dailySpent = nil
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

    func showMenu(_ event: NSEvent) {
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
        let update = menu.addItem(withTitle: "Refresh Now", action: #selector(refresh), keyEquivalent: "r")
        update.target = self
        let quit = menu.addItem(withTitle: "Quit notchGPT", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        quitting = true
        frameAnimationTimer?.invalidate(); hoverTimer?.invalidate(); pollTimer?.invalidate(); timeout?.invalidate()
        stopServer()
    }
}

if CommandLine.arguments.contains("--test-hover") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    delegate.panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    delegate.panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
    delegate.glassView.addSubview(delegate.view)
    delegate.view.autoresizingMask = [.width, .height]
    delegate.panel.contentView = delegate.glassView
    delegate.position()
    let compact = delegate.panel.frame
    let notchHeight = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })!.safeAreaInsets.top
    // AppKit rounds a scaled display's fractional 37.5 pt notch to a 38 pt frame.
    precondition(abs(compact.height - notchHeight) <= 0.5, "compact extension taller than physical notch")
    print("PASS compact height matches the physical notch within AppKit frame rounding")
    let inside = NSPoint(x: compact.midX, y: compact.midY)
    let outside = NSPoint(x: compact.minX - 100, y: compact.minY - 300)
    func settleAndCheckAnchor() {
        for _ in 0..<18 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            let readout = delegate.view.readoutRect
            precondition(abs(delegate.panel.frame.minY + readout.minY - compact.minY) < 1, "header moved vertically during animation")
            precondition(abs(delegate.panel.frame.minX + readout.minX - compact.minX) < 1, "header moved horizontally during animation")
        }
    }
    for cycle in 1...10 {
        let day = FourHourHistory.dayKey(Date())
        let start = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
        delegate.view.history = FourHourHistory(blocks: [UsageBlock(day: day, startHour: 14,
            samples: (0..<cycle).map { UsageSample(time: start.addingTimeInterval(Double($0) * 60), used: Double($0) * 0.1) },
            baseline: 10, latest: 10 + Double(cycle - 1) * 0.1)])
        delegate.checkHover(mouse: inside)
        settleAndCheckAnchor()
        precondition(delegate.isExpanded && abs(delegate.panel.frame.maxY - compact.maxY) < 1)
        precondition(abs(delegate.view.bounds.height - delegate.expandedHeight) < 1)
        let now = Date()
        delegate.checkHover(mouse: outside, now: now)
        delegate.checkHover(mouse: outside, now: now.addingTimeInterval(0.5))
        settleAndCheckAnchor()
        precondition(!delegate.isExpanded && abs(delegate.panel.frame.height - compact.height) < 1)
        precondition(abs(delegate.view.bounds.height - compact.height) < 1)
        print("PASS hover cycle \(cycle): expand, retain top edge, collapse, restore content size")
    }
    delegate.panel.orderOut(nil)
} else if let index = CommandLine.arguments.firstIndex(of: "--preview"), CommandLine.arguments.count > index + 1 {
    _ = NSApplication.shared
    let height = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })?.safeAreaInsets.top ?? 32
    let view = NotchView(frame: NSRect(x: 0, y: 0, width: NotchLayout.compactWidth, height: height))
    view.compactHeight = height
    view.percent = 75
    view.dailyPercent = 55
    view.weeklyUsed = 25
    view.dailySpent = 9
    let now = Date()
    let hour = Calendar.current.component(.hour, from: now) < 14 ? 9 : 14
    view.history = FourHourHistory(blocks: [UsageBlock(day: FourHourHistory.dayKey(now), startHour: hour,
        samples: [UsageSample(time: now, used: 3)], baseline: 22, latest: 25)])
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
} else if let index = CommandLine.arguments.firstIndex(of: "--preview-expanded"), CommandLine.arguments.count > index + 1 {
    _ = NSApplication.shared
    let view = NotchView(frame: NSRect(x: 0, y: 0, width: 334, height: 190))
    view.compactHeight = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })?.safeAreaInsets.top ?? 32
    view.percent = 75
    view.dailyPercent = 55
    view.weeklyUsed = 25
    view.dailySpent = 9
    view.expanded = true
    let calendar = Calendar.current
    let now = Date()
    var dayParts = calendar.dateComponents([.year, .month, .day], from: now)
    dayParts.hour = 16; dayParts.minute = 0
    let plotEnd = calendar.date(from: dayParts) ?? now
    let sampleTimes = (0..<21).compactMap { calendar.date(byAdding: .minute, value: -6 * (20 - $0), to: plotEnd) }
    view.history = FourHourHistory(blocks: [UsageBlock(day: FourHourHistory.dayKey(now), startHour: 14,
        samples: sampleTimes.enumerated().map { UsageSample(time: $0.element, used: Double($0.offset) * 0.07) },
        baseline: 30, latest: 31.4)])
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
} else {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
