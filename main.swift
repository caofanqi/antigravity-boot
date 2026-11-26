import AppKit
import AVFoundation
import CoreImage
import UniformTypeIdentifiers

final class PlayerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
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
        ("星轨", "orbit")
    ].filter { Bundle.main.url(forResource: $0.1, withExtension: "mp4") != nil }
    let movieMenu = NSPopUpButton()
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
        NSApp.activate(ignoringOtherApps: true)
        let saved = preferences.string(forKey: "target").map(URL.init(fileURLWithPath:))
        if let legacy = preferences.string(forKey: "movie"),
           let saved, validApp(saved), let id = Bundle(url: saved)?.bundleIdentifier {
            let key = "movie." + id
            if preferences.string(forKey: key) == nil { preferences.set(legacy, forKey: key) }
            preferences.removeObject(forKey: "movie")
        }
        let configure = NSEvent.modifierFlags.contains(.option)
        if preferences.bool(forKey: "remember"), !configure, let saved, validApp(saved) {
            start(saved)
        } else {
            settings(saved)
        }
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
        let controls = NSStackView(views: [
            NSTextField(labelWithString: "目标应用"), appMenu,
            NSTextField(labelWithString: "启动动画"), movieMenu, remember
        ])
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 6
        controls.frame = NSRect(x: 0, y: 0, width: 300, height: 150)
        for menu in [appMenu, movieMenu] { menu.widthAnchor.constraint(equalToConstant: 295).isActive = true }
        alert.accessoryView = controls
        while alert.runModal() == .alertFirstButtonReturn {
            let chosen = apps[appMenu.indexOfSelectedItem]
            guard validApp(chosen) else { message("所选应用已不可用，请重新打开启动器。"); break }
            guard let id = appMenu.selectedItem?.representedObject as? String,
                  var selection = movieMenu.selectedItem?.representedObject as? String else { continue }
            if selection == "browse" {
                guard let file = pickMovie() else { continue }
                selection = file.path
            }
            preferences.set(selection, forKey: "movie." + id)
            preferences.set(chosen.path, forKey: "target")
            preferences.set(remember.state == .on, forKey: "remember")
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
        let selection = movieSelection(for: id)
        let movie = selection.hasPrefix("/")
            ? URL(fileURLWithPath: selection)
            : Bundle.main.url(forResource: selection, withExtension: "mp4")
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
        guard let movie else { finish(); return }
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
