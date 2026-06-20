import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum Direction: String {
    case up = "U"
    case down = "D"
    case left = "L"
    case right = "R"
}

struct ShortcutAction: Codable {
    struct KeyStroke: Codable {
        let keyCode: Int
        let modifiers: [String]
    }

    let name: String
    let keys: [KeyStroke]
}

struct GestureConfig: Codable {
    struct GestureTemplate: Codable {
        let name: String
        let points: [Double]
        let action: ShortcutAction
    }

    var gestures: [String: ShortcutAction]
    var mouseButtons: [String: ShortcutAction]
    var templates: [GestureTemplate]?

    static let defaultConfig = GestureConfig(
        gestures: [
            "L": ShortcutAction(name: "Back", keys: [.init(keyCode: kVK_ANSI_LeftBracket, modifiers: ["command"])]),
            "R": ShortcutAction(name: "Forward", keys: [.init(keyCode: kVK_ANSI_RightBracket, modifiers: ["command"])]),
            "U": ShortcutAction(name: "New Tab", keys: [.init(keyCode: kVK_ANSI_T, modifiers: ["command"])]),
            "D": ShortcutAction(name: "Close Tab", keys: [.init(keyCode: kVK_ANSI_W, modifiers: ["command"])]),
            "UD": ShortcutAction(name: "Address Bar", keys: [.init(keyCode: kVK_ANSI_L, modifiers: ["command"])]),
            "DU": ShortcutAction(name: "Reload", keys: [.init(keyCode: kVK_ANSI_R, modifiers: ["command"])]),
            "LR": ShortcutAction(name: "Previous Tab", keys: [.init(keyCode: kVK_Tab, modifiers: ["control", "shift"])]),
            "RL": ShortcutAction(name: "Next Tab", keys: [.init(keyCode: kVK_Tab, modifiers: ["control"])]),
            "DR": ShortcutAction(name: "Hide App", keys: [.init(keyCode: kVK_ANSI_H, modifiers: ["command"])]),
            "DL": ShortcutAction(name: "Quit App", keys: [.init(keyCode: kVK_ANSI_Q, modifiers: ["command"])])
        ],
        mouseButtons: [
            "R+Left": ShortcutAction(name: "Close Tab", keys: [.init(keyCode: kVK_ANSI_W, modifiers: ["command"])]),
            "R+Middle": ShortcutAction(name: "New Tab", keys: [.init(keyCode: kVK_ANSI_T, modifiers: ["command"])]),
            "R+Mouse4": ShortcutAction(name: "Back", keys: [.init(keyCode: kVK_ANSI_LeftBracket, modifiers: ["command"])]),
            "R+Mouse5": ShortcutAction(name: "Forward", keys: [.init(keyCode: kVK_ANSI_RightBracket, modifiers: ["command"])])
        ],
        templates: []
    )
}

final class ConfigStore {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("WeGestureARM", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("gestures.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> GestureConfig {
        if !FileManager.default.fileExists(atPath: url.path) {
            if let bundledConfig = loadBundledDefault() {
                save(bundledConfig)
            } else {
                save(GestureConfig.defaultConfig)
            }
        }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(GestureConfig.self, from: data)
        } catch {
            NSLog("Failed to read config: \(error)")
            return GestureConfig.defaultConfig
        }
    }

    private func loadBundledDefault() -> GestureConfig? {
        guard let bundledURL = Bundle.main.url(forResource: "default-gestures", withExtension: "json") else {
            return nil
        }

        do {
            let data = try Data(contentsOf: bundledURL)
            return try decoder.decode(GestureConfig.self, from: data)
        } catch {
            NSLog("Failed to read bundled default config: \(error)")
            return nil
        }
    }

    func save(_ config: GestureConfig) {
        do {
            let data = try encoder.encode(config)
            try data.write(to: url, options: [.atomic])
        } catch {
            NSLog("Failed to write config: \(error)")
        }
    }
}

final class ShortcutSender {
    private let source = CGEventSource(stateID: .hidSystemState)

    func send(_ action: ShortcutAction) {
        for stroke in action.keys {
            let flags = eventFlags(for: stroke.modifiers)
            guard
                let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(stroke.keyCode), keyDown: true),
                let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(stroke.keyCode), keyDown: false)
            else { continue }

            down.flags = flags
            up.flags = flags
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            usleep(20_000)
        }
    }

    private func eventFlags(for names: [String]) -> CGEventFlags {
        var flags = CGEventFlags()
        for name in names {
            switch name.lowercased() {
            case "command", "cmd", "meta":
                flags.insert(.maskCommand)
            case "shift":
                flags.insert(.maskShift)
            case "option", "alt":
                flags.insert(.maskAlternate)
            case "control", "ctrl":
                flags.insert(.maskControl)
            default:
                break
            }
        }
        return flags
    }
}

final class GestureEngine {
    enum State {
        case stopped
        case running
        case permissionDenied
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var rightButtonDown = false
    private var performedMouseChord = false
    private var startPoint = CGPoint.zero
    private var lastPoint = CGPoint.zero
    private var rawPoints: [CGPoint] = []
    private var directions: [Direction] = []
    private let minSegmentDistance: CGFloat = 36
    private let sender = ShortcutSender()
    private var config: GestureConfig
    private(set) var state: State = .stopped

    init(config: GestureConfig) {
        self.config = config
    }

    func updateConfig(_ config: GestureConfig) {
        self.config = config
    }

    @discardableResult
    func start() -> Bool {
        state = .stopped
        let mask =
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<GestureEngine>.fromOpaque(refcon).takeUnretainedValue()
            return engine.handle(proxy: proxy, type: type, event: event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            state = .permissionDenied
            NSLog("WeGestureARM event tap creation failed. Accessibility/Input Monitoring permission is probably missing or stale.")
            showPermissionAlert()
            return false
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        state = .running
        NSLog("WeGestureARM event tap started.")
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        state = .stopped
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .rightMouseDown:
            rightButtonDown = true
            performedMouseChord = false
            startPoint = event.location
            lastPoint = startPoint
            rawPoints = [startPoint]
            directions.removeAll(keepingCapacity: true)
            return nil

        case .rightMouseDragged:
            guard rightButtonDown else { return Unmanaged.passUnretained(event) }
            rawPoints.append(event.location)
            appendDirection(from: lastPoint, to: event.location)
            return nil

        case .rightMouseUp:
            guard rightButtonDown else { return Unmanaged.passUnretained(event) }
            rightButtonDown = false
            defer { directions.removeAll(keepingCapacity: true) }
            if performedMouseChord {
                return nil
            }
            if let action = matchTemplate() {
                NSLog("WeGestureARM matched template: \(action.name)")
                sender.send(action)
                return nil
            }
            let code = directions.map(\.rawValue).joined()
            if let action = config.gestures[code] {
                NSLog("WeGestureARM matched gesture \(code): \(action.name)")
                sender.send(action)
                return nil
            }
            return nil

        case .leftMouseDown:
            guard rightButtonDown else { return Unmanaged.passUnretained(event) }
            performMouseChord("R+Left")
            return nil

        case .otherMouseDown:
            guard rightButtonDown else { return Unmanaged.passUnretained(event) }
            let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
            performMouseChord(chordName(for: buttonNumber))
            return nil

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func appendDirection(from oldPoint: CGPoint, to newPoint: CGPoint) {
        let dx = newPoint.x - oldPoint.x
        let dy = newPoint.y - oldPoint.y
        guard hypot(dx, dy) >= minSegmentDistance else { return }

        let direction: Direction
        if abs(dx) > abs(dy) {
            direction = dx > 0 ? .right : .left
        } else {
            direction = dy > 0 ? .up : .down
        }

        if directions.last != direction {
            directions.append(direction)
        }
        lastPoint = newPoint
    }

    private func performMouseChord(_ name: String) {
        performedMouseChord = true
        rawPoints.removeAll(keepingCapacity: true)
        directions.removeAll(keepingCapacity: true)
        if let action = config.mouseButtons[name] {
            NSLog("WeGestureARM matched mouse chord \(name): \(action.name)")
            sender.send(action)
        }
    }

    private func matchTemplate() -> ShortcutAction? {
        guard let templates = config.templates, !templates.isEmpty, rawPoints.count >= 2 else {
            return nil
        }

        let input = normalize(rawPoints)
        var bestAction: ShortcutAction?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for template in templates {
            let points = points(from: template.points)
            guard points.count >= 2 else { continue }
            let score = pathDistance(input, normalize(points))
            if score < bestScore {
                bestScore = score
                bestAction = template.action
            }
        }

        return bestScore <= 0.28 ? bestAction : nil
    }

    private func points(from values: [Double]) -> [CGPoint] {
        stride(from: 0, to: values.count - 1, by: 2).map {
            CGPoint(x: values[$0], y: values[$0 + 1])
        }
    }

    private func normalize(_ points: [CGPoint], targetCount: Int = 32) -> [CGPoint] {
        let sampled = resample(points, targetCount: targetCount)
        let minX = sampled.map(\.x).min() ?? 0
        let maxX = sampled.map(\.x).max() ?? 1
        let minY = sampled.map(\.y).min() ?? 0
        let maxY = sampled.map(\.y).max() ?? 1
        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        let scale = max(width, height)
        let centered = sampled.map { CGPoint(x: ($0.x - minX) / scale, y: ($0.y - minY) / scale) }
        let centroid = centered.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        let count = CGFloat(centered.count)
        return centered.map { CGPoint(x: $0.x - centroid.x / count, y: $0.y - centroid.y / count) }
    }

    private func resample(_ points: [CGPoint], targetCount: Int) -> [CGPoint] {
        guard points.count > 1 else { return points }
        let total = pathLength(points)
        guard total > 0 else { return Array(repeating: points[0], count: targetCount) }
        let interval = total / CGFloat(targetCount - 1)
        var result = [points[0]]
        var previous = points[0]
        var distanceRemainder: CGFloat = 0
        var index = 1

        while index < points.count {
            let current = points[index]
            let segment = hypot(current.x - previous.x, current.y - previous.y)
            if distanceRemainder + segment >= interval {
                let ratio = (interval - distanceRemainder) / segment
                let interpolated = CGPoint(
                    x: previous.x + ratio * (current.x - previous.x),
                    y: previous.y + ratio * (current.y - previous.y)
                )
                result.append(interpolated)
                previous = interpolated
                distanceRemainder = 0
            } else {
                distanceRemainder += segment
                previous = current
                index += 1
            }
        }

        while result.count < targetCount {
            result.append(points.last!)
        }
        return result
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count > 1 else { return 0 }
        return zip(points, points.dropFirst()).reduce(CGFloat(0)) { total, pair in
            total + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
    }

    private func pathDistance(_ lhs: [CGPoint], _ rhs: [CGPoint]) -> CGFloat {
        guard lhs.count == rhs.count else { return .greatestFiniteMagnitude }
        let total = zip(lhs, rhs).reduce(CGFloat(0)) { sum, pair in
            sum + hypot(pair.1.x - pair.0.x, pair.1.y - pair.0.y)
        }
        return total / CGFloat(lhs.count)
    }

    private func chordName(for buttonNumber: Int64) -> String {
        switch buttonNumber {
        case 2:
            return "R+Middle"
        case 3:
            return "R+Mouse4"
        case 4:
            return "R+Mouse5"
        default:
            return "R+Mouse\(buttonNumber + 1)"
        }
    }

    private func showPermissionAlert() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "WeGesture ARM 需要权限"
            alert.informativeText = "请在“系统设置 -> 隐私与安全性”里允许辅助功能和输入监控，然后重新打开 app。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configStore = ConfigStore()
    private var config: GestureConfig!
    private var engine: GestureEngine!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        config = configStore.load()
        engine = GestureEngine(config: config)
        setupStatusItem()
        requestAccessibilityIfNeeded()
        restartEngine()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "WG"
        statusItem.button?.toolTip = "WeGesture ARM"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "WeGesture ARM", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Restart Listener", action: #selector(restartListener), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Open Config", action: #selector(openConfig), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Open Permissions", action: #selector(openPermissions), keyEquivalent: "p"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func requestAccessibilityIfNeeded() {
        let promptKey = "AXTrustedCheckOptionPrompt"
        AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        if #available(macOS 10.15, *) {
            if !CGPreflightListenEventAccess() {
                CGRequestListenEventAccess()
            }
        }
    }

    @objc private func reloadConfig() {
        config = configStore.load()
        engine.updateConfig(config)
        restartEngine()
    }

    @objc private func restartListener() {
        restartEngine()
    }

    private func restartEngine() {
        engine.stop()
        let ok = engine.start()
        statusItem.button?.title = ok ? "WG" : "WG!"
        statusItem.button?.toolTip = ok ? "WeGesture ARM: listening" : "WeGesture ARM: listener failed, check permissions"
    }

    @objc private func openConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([configStore.url])
    }

    @objc private func openPermissions() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func quit() {
        engine.stop()
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
