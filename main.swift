import AppKit
import AVKit
import AVFoundation
import CoreImage
import UniformTypeIdentifiers

final class PlayerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class CreatorButton: NSButton {
    private let card = Bundle.main.url(forResource: "douyin", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    override var isFlipped: Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        let surface = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        NSColor.controlBackgroundColor.setFill()
        surface.fill()
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.12).setFill()
            surface.fill()
        }
        NSColor.separatorColor.setStroke()
        surface.stroke()

        let portrait = NSRect(x: 13, y: bounds.midY - 18, width: 36, height: 36)
        if let card {
            // The circular portrait at the centre of the official Douyin card.
            let size = card.size
            let source = NSRect(x: size.width * 0.375, y: size.height * 0.557,
                                width: size.width * 0.25, height: size.height * 0.1675)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(ovalIn: portrait).addClip()
            card.draw(in: portrait, from: source, operation: .sourceOver, fraction: 1,
                      respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
            NSGraphicsContext.restoreGraphicsState()
        }
        let nameStyle: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.labelColor]
        let actionStyle: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.controlAccentColor]
        let name = title as NSString
        let action = "去支持一下" as NSString
        let nameSize = name.size(withAttributes: nameStyle)
        let actionSize = action.size(withAttributes: actionStyle)
        name.draw(at: NSPoint(x: 59, y: (bounds.height - nameSize.height) / 2), withAttributes: nameStyle)
        action.draw(at: NSPoint(x: bounds.width - actionSize.width - 29,
                                y: (bounds.height - actionSize.height) / 2), withAttributes: actionStyle)
        let chevron = NSBezierPath()
        chevron.move(to: NSPoint(x: bounds.width - 20, y: bounds.midY - 4))
        chevron.line(to: NSPoint(x: bounds.width - 16, y: bounds.midY))
        chevron.line(to: NSPoint(x: bounds.width - 20, y: bounds.midY + 4))
        chevron.lineWidth = 1.6
        chevron.lineJoinStyle = .round
        NSColor.controlAccentColor.setStroke()
        chevron.stroke()
    }
}

final class Launcher: NSObject, NSApplicationDelegate {
    let supportedIDs = ["com.google.antigravity", "com.google.GeminiMacOS"]
    let preferences = UserDefaults.standard
    let workspace = NSWorkspace.shared
    let geminiID = "com.google.GeminiMacOS"
    let builtInMovies = [
        ("经典版", "gemini-classic"),
        ("水彩绘本", "gemini-watercolor"),
        ("霓虹都市", "gemini-neon"),
        ("换班", "gemini-switch-team"),
        ("星门回眸", "gemini-stargate"),
        ("星轨", "orbit")
    ].filter { Bundle.main.url(forResource: $0.1, withExtension: "mp4") != nil }
    let movieMenu = NSPopUpButton()
    let originalLaunch = NSButton(checkboxWithTitle: "从原 App 启动时播放动画", target: nil, action: nil)
    var window: NSWindow?
    var skipPanel: NSPanel?
    var player: AVPlayer?
    var target: NSRunningApplication?
    var monitor: Any?
    var watchdog: Timer?
    var transitionObserver: Any?
    var handoffFrame: CGRect?
    var finished = false
    var launchPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--handoff") {
            guard args.indices.contains(index + 1), let pid = Int32(args[index + 1]),
                  let app = NSRunningApplication(processIdentifier: pid),
                  let id = app.bundleIdentifier, supportedIDs.contains(id),
                  preferences.bool(forKey: "original." + id) else { NSApp.terminate(nil); return }
            NSApp.activate(ignoringOtherApps: true)
            target = app
            playMovie(for: id)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let saved = preferences.string(forKey: "target").map(URL.init(fileURLWithPath:))
        if let legacy = preferences.string(forKey: "movie"),
           let saved, validApp(saved), let id = Bundle(url: saved)?.bundleIdentifier {
            let key = "movie." + id
            if preferences.string(forKey: key) == nil { preferences.set(legacy, forKey: key) }
            preferences.removeObject(forKey: "movie")
        }
        let configure = NSEvent.modifierFlags.contains(.option) || args.contains("--settings")
        if preferences.bool(forKey: "remember"), !configure, let saved, validApp(saved) {
            start(saved)
        } else {
            settings(saved)
        }
    }

    func saveOriginalLaunch(_ enabled: Bool, for id: String) throws {
        let needsObserver = enabled || supportedIDs.contains { $0 != id && preferences.bool(forKey: "original." + $0) }
        let label = "io.github.bozi.antigravity-boot.observer"
        let domain = "gui/\(getuid())"
        let service = domain + "/" + label
        let fm = FileManager.default
        let folder = try fm.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
        let plist = folder.appendingPathComponent(label + ".plist")

        func launchctl(_ arguments: [String]) throws -> Int32 {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            task.arguments = arguments
            task.standardOutput = FileHandle.nullDevice
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        }

        if needsObserver {
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/BootObserver")
            let config: [String: Any] = ["Label": label, "ProgramArguments": [helper.path], "RunAtLoad": true,
                                        "LimitLoadToSessionType": "Aqua", "AssociatedBundleIdentifiers": [Bundle.main.bundleIdentifier!]]
            let data = try PropertyListSerialization.data(fromPropertyList: config, format: .xml, options: 0)
            let changed = (try? Data(contentsOf: plist)) != data
            let loaded = try launchctl(["print", service]) == 0
            if changed {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: plist, options: .atomic)
            }
            if changed && loaded { guard try launchctl(["bootout", service]) == 0 else { throw observerError() } }
            if changed || !loaded {
                guard try launchctl(["bootstrap", domain, plist.path]) == 0 else { throw observerError() }
            }
        } else if fm.fileExists(atPath: plist.path) {
            if try launchctl(["print", service]) == 0 {
                guard try launchctl(["bootout", service]) == 0 else { throw observerError() }
            }
            try fm.removeItem(at: plist)
        }
        preferences.set(enabled, forKey: "original." + id)
    }

    func observerError() -> NSError {
        NSError(domain: "AntigravityBoot", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "请确认启动器已安装，并在系统设置的「登录项」中允许后台运行，然后重试。"])
    }

    func validApp(_ url: URL) -> Bool {
        guard let bundle = Bundle(url: url), let executable = bundle.executableURL else { return false }
        return url.pathExtension.lowercased() == "app" &&
            supportedIDs.contains(bundle.bundleIdentifier ?? "") &&
            FileManager.default.isExecutableFile(atPath: executable.path)
    }

    func pickMovie() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        return panel.runModal() == .OK ? panel.url : nil
    }

    func settings(_ saved: URL?) {
        let apps = supportedIDs.compactMap { id -> URL? in
            if let saved, validApp(saved), Bundle(url: saved)?.bundleIdentifier == id { return saved }
            return workspace.urlForApplication(withBundleIdentifier: id)
        }.filter(validApp)
        guard !apps.isEmpty else {
            message("请先安装 Antigravity 或 Gemini，再打开启动器。")
            NSApp.terminate(nil)
            return
        }
        let alert = NSAlert()
        alert.messageText = "启动哪个应用？"
        alert.informativeText = "记住选择后，按住 ⌥ Option 打开启动器可更改设置。"
        alert.addButton(withTitle: "启动")
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "仅保存")
        let appMenu = NSPopUpButton()
        appMenu.addItems(withTitles: apps.map { $0.deletingPathExtension().lastPathComponent })
        if let saved, let index = apps.firstIndex(of: saved) { appMenu.selectItem(at: index) }
        for (item, url) in zip(appMenu.itemArray, apps) {
            item.representedObject = Bundle(url: url)?.bundleIdentifier
        }
        appMenu.target = self
        appMenu.action = #selector(refreshMovies(_:))
        refreshMovies(appMenu)
        let remember = NSButton(checkboxWithTitle: "以后直接启动选中的应用", target: nil, action: nil)
        remember.state = preferences.bool(forKey: "remember") ? .on : .off
        let preview = NSButton(title: "预览动画", target: self, action: #selector(previewMovie))
        originalLaunch.toolTip = "在所选 App 完全退出后，下次启动时播放。需要允许后台运行。"
        let creator = CreatorButton(title: "波子哥 开源", target: self, action: #selector(showCreator))
        creator.isBordered = false
        creator.setAccessibilityLabel("波子哥 开源")
        creator.toolTip = "查看抖音主页和二维码"
        creator.setAccessibilityHelp("去支持一下，查看波子哥的抖音名片")
        creator.heightAnchor.constraint(equalToConstant: 54).isActive = true
        let movieRow = NSStackView(views: [movieMenu, preview])
        movieRow.spacing = 8
        movieMenu.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let controls = NSStackView(views: [
            NSTextField(labelWithString: "目标应用"), appMenu,
            NSTextField(labelWithString: "启动动画"), movieRow, originalLaunch, remember, creator
        ])
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 6
        controls.setCustomSpacing(12, after: appMenu)
        controls.setCustomSpacing(12, after: movieRow)
        controls.setCustomSpacing(14, after: remember)
        let form = NSView(frame: NSRect(x: 0, y: 0, width: 396, height: 228))
        controls.translatesAutoresizingMaskIntoConstraints = false
        form.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: form.leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: form.trailingAnchor, constant: -12),
            controls.centerYAnchor.constraint(equalTo: form.centerYAnchor)
        ])
        for view in [appMenu as NSView, movieRow, creator] {
            view.widthAnchor.constraint(equalTo: controls.widthAnchor).isActive = true
        }
        alert.accessoryView = form
        while true {
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn || response == .alertThirdButtonReturn else { break }
            let chosen = apps[appMenu.indexOfSelectedItem]
            guard validApp(chosen) else { message("所选应用已不可用，请重新打开启动器。"); break }
            guard let id = appMenu.selectedItem?.representedObject as? String,
                  var selection = movieMenu.selectedItem?.representedObject as? String else { continue }
            if selection == "browse" {
                guard let file = pickMovie() else { continue }
                selection = file.path
            }
            do { try saveOriginalLaunch(originalLaunch.state == .on, for: id) }
            catch { message("无法更新后台启动设置：\(error.localizedDescription)"); continue }
            preferences.set(selection, forKey: "movie." + id)
            preferences.set(chosen.path, forKey: "target")
            preferences.set(remember.state == .on, forKey: "remember")
            if response == .alertThirdButtonReturn { break }
            start(chosen)
            return
        }
        NSApp.terminate(nil)
    }

    func movieSelection(for id: String) -> String {
        if let saved = preferences.string(forKey: "movie." + id),
           builtInMovies.contains(where: { $0.1 == saved }) ||
           (saved.hasPrefix("/") && FileManager.default.isReadableFile(atPath: saved)) {
            return saved
        }
        return builtInMovies.first?.1 ?? "browse"
    }

    @objc func refreshMovies(_ sender: NSPopUpButton) {
        guard let id = sender.selectedItem?.representedObject as? String else { return }
        originalLaunch.state = preferences.bool(forKey: "original." + id) ? .on : .off
        let selection = movieSelection(for: id)
        var choices = builtInMovies
        if selection.hasPrefix("/") {
            choices.append((URL(fileURLWithPath: selection).lastPathComponent, selection))
        }
        choices.append(("选择本地视频…", "browse"))
        movieMenu.removeAllItems()
        for (title, value) in choices {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.representedObject = value
            movieMenu.menu?.addItem(item)
        }
        movieMenu.selectItem(at: choices.firstIndex(where: { $0.1 == selection }) ?? 0)
    }

    func message(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.runModal()
    }

    func start(_ url: URL) {
        guard let id = Bundle(url: url)?.bundleIdentifier else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        launchPending = true
        workspace.openApplication(at: url, configuration: configuration) { app, error in
            DispatchQueue.main.async {
                self.launchPending = false
                guard let app else {
                    self.window?.orderOut(nil)
                    self.player?.pause()
                    self.preferences.set(false, forKey: "remember")
                    self.message(error?.localizedDescription ?? "应用启动失败，请重新选择。")
                    NSApp.terminate(nil)
                    return
                }
                self.target = app
                if self.finished { self.handoff() }
            }
        }
        playMovie(for: id)
    }

    func movieURL(_ selection: String) -> URL? {
        selection.hasPrefix("/") ? URL(fileURLWithPath: selection)
            : Bundle.main.url(forResource: selection, withExtension: "mp4")
    }

    @objc func showCreator() {
        let url = URL(string: "https://www.douyin.com/user/MS4wLjABAAAAqfTLdIWYEIvollbyqL6yeU2anTbgSXkD_2-N-FNuztk")!
        let alert = NSAlert()
        alert.messageText = "波子哥 开源"
        alert.informativeText = "开源不易，喜欢这个启动器的话，来抖音关注支持一下。\n抖音号：BobbyCao"
        if let file = Bundle.main.url(forResource: "douyin", withExtension: "png"),
           let image = NSImage(contentsOf: file) {
            let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 290, height: 390))
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            view.setAccessibilityLabel("波子哥的抖音主页二维码")
            alert.accessoryView = view
        }
        alert.addButton(withTitle: "打开抖音主页")
        alert.addButton(withTitle: "返回设置")
        if alert.runModal() == .alertFirstButtonReturn { workspace.open(url) }
    }

    @objc func previewMovie() {
        guard let item = movieMenu.selectedItem, let selection = item.representedObject as? String else { return }
        let url = selection == "browse" ? pickMovie() : movieURL(selection)
        guard let url else { return }
        let video = AVPlayer(url: url)
        let view = AVPlayerView(frame: NSRect(x: 0, y: 0, width: 512, height: 288))
        view.controlsStyle = .inline
        view.player = video
        let preview = NSAlert()
        preview.messageText = "预览 · " + (selection == "browse" ? url.lastPathComponent : item.title)
        preview.accessoryView = view
        preview.addButton(withTitle: "返回设置")
        video.play()
        preview.runModal()
        video.pause()
        view.player = nil
    }

    func playMovie(for id: String) {
        guard let movie = movieURL(movieSelection(for: id)) else { finish(); return }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let width = min(1024, area.width * 0.84, area.height * 0.84 * 16 / 9)
        let rect = NSRect(x: area.midX - width / 2, y: area.midY - width * 9 / 32,
                          width: width, height: width * 9 / 16)
        let overlay = PlayerWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        overlay.isReleasedWhenClosed = false
        overlay.backgroundColor = .black
        overlay.level = .floating
        overlay.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let video = AVPlayer(url: movie)
        player = video
        let layer = AVPlayerLayer(player: video)
        layer.videoGravity = .resizeAspect
        overlay.contentView?.wantsLayer = true
        overlay.contentView?.layer = layer
        window = overlay
        overlay.makeKeyAndOrderFront(nil)
        showSkipControl(in: rect)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            let cancelKey = event.type == .keyDown &&
                (event.keyCode == 53 || (event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "."))
            if cancelKey || (event.type == .leftMouseDown && event.window === overlay) {
                self.finish()
                return nil
            }
            return event
        }
        for name in [Notification.Name.AVPlayerItemDidPlayToEndTime, .AVPlayerItemFailedToPlayToEndTime] {
            NotificationCenter.default.addObserver(self, selector: #selector(finish), name: name, object: video.currentItem)
        }
        var lastTime = -1.0
        var stalled = 0
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let time = video.currentTime().seconds
            stalled = time.isFinite && time > lastTime ? 0 : stalled + 1
            lastTime = time
            if stalled >= 5 || video.currentItem?.status == .failed { self.finish() }
        }
        prepareWindowHandoff(video, overlay: overlay, shrinkToComposer: id == geminiID)
        video.play()
    }

    func showSkipControl(in frame: NSRect) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 34),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let button = NSButton(title: "跳过   Esc", target: self, action: #selector(finish))
        button.frame = NSRect(origin: .zero, size: panel.frame.size)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.88).cgColor
        button.layer?.cornerRadius = 17
        button.attributedTitle = NSAttributedString(string: button.title, attributes: [
            .foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 14, weight: .medium)
        ])
        button.setAccessibilityLabel("跳过启动动画")
        button.toolTip = "跳过启动动画（Esc 或 ⌘.）"
        panel.contentView?.addSubview(button)
        skipPanel = panel
        positionSkipControl(in: frame)
        panel.orderFrontRegardless()
    }

    func positionSkipControl(in frame: NSRect) {
        guard let panel = skipPanel else { return }
        let visible = NSScreen.screens.max {
            NSIntersectionRect($0.frame, frame).width * NSIntersectionRect($0.frame, frame).height <
                NSIntersectionRect($1.frame, frame).width * NSIntersectionRect($1.frame, frame).height
        }?.visibleFrame ?? frame
        let area = NSIntersectionRect(frame, visible)
        panel.setFrameTopLeftPoint(NSPoint(x: area.maxX - panel.frame.width - 16, y: area.maxY - 16))
    }

    // Quartz window bounds use a top-left origin on the primary display.
    func visibleWindow(of app: NSRunningApplication) -> CGRect? {
        guard let top = NSScreen.screens.first?.frame.maxY,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return nil }
        for item in windows {
            guard item[kCGWindowOwnerPID as String] as? Int32 == app.processIdentifier,
                  item[kCGWindowLayer as String] as? Int == 0,
                  let bounds = item[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"],
                  let h = bounds["Height"], w >= 320, h >= 180 else { continue }
            return CGRect(x: x, y: top - y - h, width: w, height: h)
        }
        return nil
    }

    // Fit the complete frame, then reflect only the exposed edges into the unused space.
    func fitMovie(_ item: AVPlayerItem, in size: CGSize) {
        let displayAspect = size.width / size.height
        item.videoComposition = AVVideoComposition(asset: item.asset) { request in
            let image = request.sourceImage
            let bounds = image.extent
            let ratio = displayAspect * bounds.height / bounds.width
            guard abs(ratio - 1) > 0.001 else {
                request.finish(with: image, context: nil)
                return
            }

            let wide = ratio > 1
            let sx = wide ? 1 / ratio : 1
            let sy = wide ? 1 : ratio
            let fit = CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
                                        tx: bounds.midX * (1 - sx), ty: bounds.midY * (1 - sy))
            let center = image.transformed(by: fit)
            let edges = center.extent
            func reflection(at position: CGFloat) -> CIImage {
                let transform = wide
                    ? CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 2 * position, ty: 0)
                    : CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 2 * position)
                return center.transformed(by: transform)
            }
            let first = reflection(at: wide ? edges.minX : edges.minY)
            let last = reflection(at: wide ? edges.maxX : edges.maxY)
            let extended = center.composited(over: first).composited(over: last)
            let backing = image.clampedToExtent().transformed(by: fit)
            request.finish(with: extended.composited(over: backing).cropped(to: bounds), context: nil)
        }
    }

    func prepareWindowHandoff(_ video: AVPlayer, overlay: NSWindow, shrinkToComposer: Bool) {
        guard let item = video.currentItem else { return }
        (overlay.contentView?.layer as? AVPlayerLayer)?.videoGravity = .resize
        var aspect = overlay.frame.width / overlay.frame.height
        fitMovie(item, in: overlay.frame.size)
        var nextLookup = 0.0
        var revealing = false
        transitionObserver = video.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 60),
                                                           queue: .main) { [weak self] time in
            guard let self, !self.finished, let target = self.target,
                  let duration = video.currentItem?.duration.seconds, duration.isFinite else { return }
            let now = time.seconds
            if !revealing, now >= nextLookup {
                nextLookup = now + 0.35
                if let frame = self.visibleWindow(of: target), frame != self.handoffFrame {
                    let newAspect = frame.width / frame.height
                    if abs(newAspect - aspect) > 0.001 {
                        self.fitMovie(item, in: frame.size)
                        aspect = newAspect
                    }
                    self.handoffFrame = frame
                    overlay.setFrame(frame, display: true)
                    self.positionSkipControl(in: frame)
                }
            }
            let span = min(2.25, duration * 0.25)
            guard let frame = self.handoffFrame, span > 0, now >= duration - span else { return }
            if !revealing {
                revealing = true
                if #available(macOS 14, *) { NSApp.yieldActivation(to: target) }
                target.activate(options: [])
                if shrinkToComposer {
                    NSApp.activate(ignoringOtherApps: true)
                    overlay.makeKeyAndOrderFront(nil)
                } else {
                    overlay.orderFrontRegardless()
                }
            }
            if !shrinkToComposer {
                let progress = min(1, max(0, (now - duration + span) / span))
                let smooth = progress * progress * (3 - 2 * progress)
                overlay.alphaValue = 1 - smooth
                self.skipPanel?.alphaValue = 1 - smooth
                return
            }
            // The screenshot's composer is centered at 56% across and halfway down the window.
            let t = min(1, max(0, (now - duration + span) / (span * 0.85)))
            let ease = t * t * (3 - 2 * t)
            let scale = 1 - 0.94 * ease
            let width = frame.width * scale, height = frame.height * scale
            let centerX = frame.midX + frame.width * 0.06 * ease
            overlay.setFrame(CGRect(x: centerX - width / 2, y: frame.midY - height / 2,
                                    width: width, height: height), display: true)
            overlay.alphaValue = 1 - ease * ease
        }
    }

    @objc func finish() {
        guard !finished else { return }
        finished = true
        skipPanel?.orderOut(nil)
        watchdog?.invalidate()
        if let transitionObserver { player?.removeTimeObserver(transitionObserver); self.transitionObserver = nil }
        if let monitor { NSEvent.removeMonitor(monitor) }
        player?.pause()
        if let window {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().alphaValue = 0
            } completionHandler: {
                window.orderOut(nil)
                if !self.launchPending { self.handoff() }
            }
        } else if !launchPending { handoff() }
    }

    func handoff() {
        if let target {
            if #available(macOS 14, *) { NSApp.yieldActivation(to: target) }
            target.activate(options: [.activateAllWindows])
        }
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let launcher = Launcher()
app.setActivationPolicy(.regular)
app.delegate = launcher
app.run()
