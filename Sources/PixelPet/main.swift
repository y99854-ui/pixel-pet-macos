#if canImport(AppKit)
import AppKit
import CoreGraphics
import Foundation
import Darwin
import PixelPetCore

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PetView: NSView {
    let catalog: SpriteCatalog
    weak var owner: PetController?
    var style: PetStyle = .grayCat
    var pose: BottomPose = .none
    var tick = 0
    var scale: CGFloat = 1
    var angle: CGFloat = 0
    var heart: CGFloat = 0
    var magic: CGFloat = 0
    var offset: CGPoint {
        CGPoint(x: (bounds.width - PetModel.size.width) / 2,
                y: (bounds.height - PetModel.size.height) / 2)
    }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(catalog: SpriteCatalog) {
        self.catalog = catalog
        super.init(frame: CGRect(origin: .zero, size: PetModel.size))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func color(_ key: String) -> NSColor {
        if key.hasPrefix("#"), let value = UInt32(key.dropFirst(), radix: 16) {
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        }
        guard let c = catalog.palette[key], c.count == 4 else { return .clear }
        return NSColor(srgbRed: CGFloat(c[1]) / 255, green: CGFloat(c[2]) / 255,
                       blue: CGFloat(c[3]) / 255, alpha: CGFloat(c[0]) / 255)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        context.setShouldAntialias(false)
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: angle)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -PetModel.size.width / 2, y: -PetModel.size.height / 2)
        let blink = tick % 150 >= 145
        for pixel in catalog.rectangles(style: style, tail: (tick / 15) % 2,
                                        blink: blink, pose: pose, lookRight: tick % 100 >= 50) {
            color(pixel.color).setFill()
            context.fill(pixel.bounds)
        }
        context.restoreGState()
        if heart > 0 {
            color("Red").setFill()
            for r in [CGRect(x: 3,y: 0,width: 4,height: 3), CGRect(x: 10,y: 0,width: 4,height: 3),
                      CGRect(x: 1,y: 2,width: 15,height: 4), CGRect(x: 3,y: 6,width: 11,height: 2),
                      CGRect(x: 5,y: 8,width: 7,height: 2), CGRect(x: 7,y: 10,width: 3,height: 2)] {
                context.fill(CGRect(x: bounds.midX + (r.minX - 8.5) * 6 * heart,
                                    y: offset.y - 60 + r.minY * 6 * heart,
                                    width: r.width * 6 * heart, height: r.height * 6 * heart))
            }
        }
        if magic > 0 {
            let colors = ["#A855F7", "#67E8F9", "#FDE047", "#F472B6"]
            for i in 0..<12 {
                let radians = CGFloat(i) * .pi / 6 + CGFloat(tick) * 0.08
                color(colors[i % colors.count]).withAlphaComponent(magic).setFill()
                let x = bounds.midX + cos(radians) * 115 * magic
                let y = bounds.midY + sin(radians) * 115 * magic
                context.fill(CGRect(x: x - 9, y: y - 3, width: 18, height: 6))
                context.fill(CGRect(x: x - 3, y: y - 9, width: 6, height: 18))
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        if event.clickCount == 2 { owner?.jump(); return }
        owner?.beginDrag()
    }
    override func mouseDragged(with event: NSEvent) { owner?.drag() }
    override func mouseUp(with event: NSEvent) { owner?.endDrag() }
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = owner?.menu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class PetController: NSObject, NSApplicationDelegate {
    let catalog: SpriteCatalog
    // The application bundle identifier already owns the standard preferences domain.
    let defaults = UserDefaults.standard
    let panel: PetPanel
    let view: PetView
    var model: PetModel
    var statusItem: NSStatusItem?
    var timer: Timer?
    var dragging = false
    var dragMouse = CGPoint.zero
    var dragOrigin = CGPoint.zero
    var direction: CGFloat = 1
    var walking = true
    var alwaysOnTop = true
    var opacity: CGFloat = 1
    var lastTick = Date()
    var activeSession = true
    var displayAwake = true
    var schedule: HourlySchedule?
    var hourlyVisible = false
    var hasAppearedHourly = false
    var animation: Motion?
    let selfTest: Bool

    struct Motion {
        enum Kind { case jump, center, change }
        let kind: Kind
        let start: Date
        let origin: CGPoint
        let target: CGPoint
        let duration: TimeInterval
    }

    init(catalog: SpriteCatalog, hourly: Bool, selfTest: Bool) {
        self.catalog = catalog
        self.selfTest = selfTest
        let work = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        model = PetModel(position: CGPoint(x: work.maxX - 244, y: work.minY + 8), style: .grayCat)
        view = PetView(catalog: catalog)
        panel = PetPanel(contentRect: CGRect(origin: model.position, size: PetModel.size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        if !selfTest {
            walking = defaults.object(forKey: "walking") as? Bool ?? true
            alwaysOnTop = defaults.object(forKey: "alwaysOnTop") as? Bool ?? true
            opacity = clamp(CGFloat(defaults.object(forKey: "opacity") as? Double ?? 1), 0.2, 1)
            if let raw = defaults.string(forKey: "nextStyle"), let style = PetStyle(rawValue: raw) {
                model.style = style
            }
            if let x = defaults.object(forKey: "x") as? Double,
               let y = defaults.object(forKey: "y") as? Double, x.isFinite, y.isFinite {
                model.position = CGPoint(x: x, y: y)
            }
            model.clampTo(Self.screen(for: model.position).visibleFrame)
            defaults.set(model.style.next.rawValue, forKey: "nextStyle")
        }
        if hourly { schedule = HourlySchedule(now: Date()) }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = alwaysOnTop ? .floating : .normal
        panel.alphaValue = opacity
        panel.contentView = view
        view.owner = self
        syncWindow()
    }

    static func screen(for point: CGPoint) -> NSScreen {
        let center = CGPoint(x: point.x + PetModel.size.width / 2, y: point.y + PetModel.size.height / 2)
        return NSScreen.screens.min { a, b in
            func distance(_ frame: CGRect) -> CGFloat {
                let dx = center.x - clamp(center.x, frame.minX, frame.maxX)
                let dy = center.y - clamp(center.y, frame.minY, frame.maxY)
                return dx * dx + dy * dy
            }
            return distance(a.frame) < distance(b.frame)
        } ?? NSScreen.main!
    }
    var work: CGRect { Self.screen(for: model.position).visibleFrame }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if selfTest { runSelfTest(); return }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Pixel Pet")
        refreshMenu()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sessionOff), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(sessionOn), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(displayOff), name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(displayOn), name: NSWorkspace.screensDidWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        // NSWorkspace session notifications also cover fast user switching. These
        // distributed notifications cover screen locking without switching users.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(sessionOff), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(sessionOn), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
        if schedule == nil { panel.orderFrontRegardless() }
        let timer = Timer(timeInterval: 1.0 / 30, target: self, selector: #selector(update), userInfo: nil, repeats: true)
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func syncWindow() {
        let size = animation == nil ? PetModel.size : CGSize(width: 620, height: 620)
        let offset = CGPoint(x: (size.width - PetModel.size.width) / 2,
                             y: (size.height - PetModel.size.height) / 2)
        panel.setFrame(CGRect(x: model.position.x - offset.x, y: model.position.y - offset.y,
                             width: size.width, height: size.height), display: false)
        view.frame = CGRect(origin: .zero, size: size)
        view.style = model.style
        view.pose = model.pose
        view.needsDisplay = true
    }

    func save() {
        guard !selfTest else { return }
        defaults.set(Double(model.position.x), forKey: "x")
        defaults.set(Double(model.position.y), forKey: "y")
        defaults.set(walking, forKey: "walking")
        defaults.set(alwaysOnTop, forKey: "alwaysOnTop")
        defaults.set(Double(opacity), forKey: "opacity")
    }
    func beginDrag() {
        guard animation == nil else { return }
        dragging = true
        dragMouse = NSEvent.mouseLocation
        dragOrigin = model.position
    }
    func drag() {
        guard dragging else { return }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: dragOrigin.x + mouse.x - dragMouse.x, y: dragOrigin.y + mouse.y - dragMouse.y)
        model.drag(to: point, in: Self.screen(for: point).visibleFrame)
        syncWindow()
    }
    func endDrag() {
        guard dragging else { return }
        dragging = false
        let area = work
        switch model.drop(in: area) {
        case .settled: syncWindow(); save()
        case .switchPet: startMotion(.change, target: model.position, duration: 0.8)
        case .returnToCenter: startMotion(.center, target: PetModel.center(in: area), duration: 0.9)
        }
    }
    func startMotion(_ kind: Motion.Kind, target: CGPoint, duration: TimeInterval) {
        guard animation == nil else { return }
        dragging = false
        animation = Motion(kind: kind, start: Date(), origin: model.position, target: target, duration: duration)
        panel.ignoresMouseEvents = true
        syncWindow()
    }
    func jump() {
        startMotion(.jump, target: model.position, duration: 2.4)
    }
    func stopMotion() {
        if let motion = animation { model.position = motion.target }
        animation = nil
        changedDuringMotion = false
        view.scale = 1; view.angle = 0; view.heart = 0; view.magic = 0
        panel.ignoresMouseEvents = false
        syncWindow()
    }

    @objc func update() {
        let now = Date()
        let dt = min(max(now.timeIntervalSince(lastTick), 0), 0.1)
        lastTick = now
        if var s = schedule {
            let visible = s.update(now: now, interactive: activeSession && displayAwake)
            schedule = s
            if visible != hourlyVisible {
                hourlyVisible = visible
                if visible {
                    if hasAppearedHourly { model.style = model.style.next }
                    hasAppearedHourly = true
                    defaults.set(model.style.next.rawValue, forKey: "nextStyle")
                    panel.orderFrontRegardless()
                } else {
                    dragging = false
                    if let motion = animation { model.position = motion.target }
                    stopMotion()
                    panel.orderOut(nil)
                }
                refreshMenu()
            }
            if !visible { return }
        }
        if !displayAwake || !activeSession { return }
        view.tick += 1
        if let motion = animation {
            let t = CGFloat(min(1, now.timeIntervalSince(motion.start) / motion.duration))
            let eased = 1 - pow(1 - t, 3)
            switch motion.kind {
            case .jump:
                if t < 0.2 {
                    view.heart = min(1.2, t * 6)
                } else {
                    view.heart = 0
                    let phase = (t - 0.2) / 0.8
                    let height = max(0, work.maxY - motion.origin.y - PetModel.size.height * 1.5)
                    model.position.y = motion.origin.y + sin(.pi * phase) * height
                    view.scale = 1 + sin(.pi * phase)
                    view.angle = phase < 0.5 ? 0 : (phase - 0.5) * 4 * .pi
                }
            case .center:
                model.position.x = motion.origin.x + (motion.target.x - motion.origin.x) * eased
                model.position.y = motion.origin.y + (motion.target.y - motion.origin.y) * eased + sin(.pi * t) * 60
                view.angle = t * 2 * .pi
            case .change:
                view.magic = sin(.pi * t)
                view.scale = max(0.05, abs(2 * t - 1))
                if t >= 0.5 && !changedDuringMotion {
                    selectNextStyle(); changedDuringMotion = true
                }
            }
            if t >= 1 {
                model.position = motion.target
                changedDuringMotion = false
                stopMotion(); save()
            }
        } else if walking && !dragging && model.pose == .none {
            // Periodic pauses, blinking and tail wagging continue when movement pauses.
            if view.tick % 270 < 210 {
                model.position.x += direction * CGFloat(dt) * 24
                let area = work
                if model.position.x <= area.minX { direction = 1 }
                if model.position.x + PetModel.size.width >= area.maxX { direction = -1 }
                model.clampTo(area)
            }
        }
        syncWindow()
    }
    var changedDuringMotion = false
    func selectNextStyle() {
        model.style = model.style.next
        defaults.set(model.style.next.rawValue, forKey: "nextStyle")
        refreshMenu()
    }

    func menu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, _ action: Selector, checked: Bool = false, tag: Int = 0) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self; item.tag = tag; item.state = checked ? .on : .off
            return item
        }
        let title = NSMenuItem(title: "Pixel Pet · \(model.style.title)", action: nil, keyEquivalent: "")
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(item("散步", #selector(toggleWalking), checked: walking))
        menu.addItem(item("保持置顶", #selector(toggleTop), checked: alwaysOnTop))
        let styles = NSMenu()
        for (i, style) in PetStyle.allCases.enumerated() {
            styles.addItem(item(style.title, #selector(chooseStyle(_:)), checked: style == model.style, tag: i))
        }
        let styleItem = NSMenuItem(title: "切换宠物", action: nil, keyEquivalent: "")
        styleItem.submenu = styles; menu.addItem(styleItem)
        let transparency = NSMenu()
        for percent in [100, 80, 60, 40, 20] {
            transparency.addItem(item("\(percent)%", #selector(chooseOpacity(_:)),
                                      checked: abs(opacity * 100 - CGFloat(percent)) < 1, tag: percent))
        }
        let opacityItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        opacityItem.submenu = transparency; menu.addItem(opacityItem)
        menu.addItem(item("回到右下角", #selector(moveHome)))
        menu.addItem(item("每小时出现 30 秒", #selector(toggleHourly), checked: schedule != nil))
        menu.addItem(.separator())
        menu.addItem(item("退出", #selector(quit)))
        return menu
    }
    func refreshMenu() { statusItem?.menu = menu() }
    @objc func toggleWalking() { walking.toggle(); refreshMenu(); save() }
    @objc func toggleTop() {
        alwaysOnTop.toggle(); panel.level = alwaysOnTop ? .floating : .normal
        refreshMenu(); save()
    }
    @objc func chooseStyle(_ sender: NSMenuItem) {
        stopMotion(); model.style = PetStyle.allCases[sender.tag]
        defaults.set(model.style.next.rawValue, forKey: "nextStyle")
        refreshMenu(); syncWindow()
    }
    @objc func chooseOpacity(_ sender: NSMenuItem) {
        opacity = CGFloat(sender.tag) / 100; panel.alphaValue = opacity
        refreshMenu(); save()
    }
    @objc func moveHome() {
        stopMotion(); model.resetPose()
        let area = work
        model.position = CGPoint(x: area.maxX - PetModel.size.width - 28, y: area.minY + 8)
        model.clampTo(area); syncWindow(); save()
    }
    @objc func toggleHourly() {
        stopMotion(); dragging = false
        if schedule == nil {
            save(); schedule = HourlySchedule(now: Date()); hourlyVisible = false
            hasAppearedHourly = false; panel.orderOut(nil)
        } else {
            schedule = nil; hourlyVisible = false; panel.orderFrontRegardless()
        }
        refreshMenu()
    }
    @objc func sessionOff(_ note: Notification) { activeSession = false }
    @objc func sessionOn(_ note: Notification) { activeSession = true }
    @objc func displayOff(_ note: Notification) { displayAwake = false }
    @objc func displayOn(_ note: Notification) { displayAwake = true }
    @objc func screensChanged(_ note: Notification) {
        stopMotion(); model.clampTo(work); syncWindow()
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        if let motion = animation { model.position = motion.target }
        save(); timer?.invalidate()
    }

    func runSelfTest() {
        // macOS-only smoke test: actual AppKit windows and offscreen sprite rendering.
        do {
            panel.orderFrontRegardless()
            panel.displayIfNeeded()
            for style in PetStyle.allCases {
                for pose in [BottomPose.none, .rest, .peek] {
                    view.style = style; view.pose = pose
                    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                        throw CocoaError(.coderInvalidValue)
                    }
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    guard let pixels = bitmap.bitmapData,
                          (0..<bitmap.pixelsHigh).contains(where: { y in
                              (0..<bitmap.pixelsWide).contains { x in
                                  let p = pixels + y * bitmap.bytesPerRow + x * (bitmap.bitsPerPixel / 8)
                                  return p[0] != 0 || p[1] != 0 || p[2] != 0
                              }
                          }) else { throw CocoaError(.coderInvalidValue) }
                }
            }
            panel.orderOut(nil)
            panel.orderFrontRegardless()
            panel.close()
            print("PASS: 18 AppKit sprite renders and window show/hide/close")
            NSApp.terminate(nil)
        } catch {
            fputs("AppKit self-test failed: \(error)\n", stderr)
            exit(1)
        }
    }
}

let arguments = CommandLine.arguments
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let isSelfTest = arguments.contains("--self-test")
// flock survives process crashes safely: the kernel releases it when the FD closes.
var instanceLock: Int32 = -1
if !isSelfTest {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("PixelPetMac", isDirectory: true)
    do { try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true) }
    catch { fputs("Cannot create app settings directory: \(error)\n", stderr); exit(1) }
    instanceLock = open(support.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard instanceLock >= 0, flock(instanceLock, LOCK_EX | LOCK_NB) == 0 else {
        fputs("Pixel Pet is already running (or its lock file is inaccessible). Use its menu bar paw icon.\n", stderr)
        exit(1)
    }
}
do {
    let catalog = try SpriteCatalog.load()
    let controller = PetController(catalog: catalog, hourly: arguments.contains("--hourly"), selfTest: isSelfTest)
    app.delegate = controller
    withExtendedLifetime(controller) { app.run() }
} catch {
    fputs("Cannot load Pixel Pet sprites: \(error)\n", stderr)
    exit(1)
}
if instanceLock >= 0 { close(instanceLock) }
#else
import Foundation
fputs("Pixel Pet's desktop application requires macOS 12 or later. Core tests can run on Linux with swift test.\n", stderr)
exit(1)
#endif
