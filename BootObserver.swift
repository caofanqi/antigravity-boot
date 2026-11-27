import AppKit
import MachO

// launchd runs this helper only while a target has opted in.
let launcherID = "io.github.bozi.antigravity-boot"
let preferences = Bundle.main.bundleIdentifier == launcherID ? UserDefaults.standard : UserDefaults(suiteName: launcherID) ?? .standard
let workspace = NSWorkspace.shared
var length: UInt32 = 0
_NSGetExecutablePath(nil, &length)
var path = [CChar](repeating: 0, count: Int(length))
guard _NSGetExecutablePath(&path, &length) == 0 else { exit(1) }
let launcher = URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let observer = workspace.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                                        object: nil, queue: .main) { note in
    guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
          let id = app.bundleIdentifier, ["com.google.antigravity", "com.google.GeminiMacOS"].contains(id),
          preferences.bool(forKey: "original." + id) else { return }
    // An active launcher already handles the launch it initiated.
    guard NSRunningApplication.runningApplications(withBundleIdentifier: launcherID).isEmpty else { return }
    let options = NSWorkspace.OpenConfiguration()
    options.arguments = ["--handoff", String(app.processIdentifier)]
    workspace.openApplication(at: launcher, configuration: options) { _, error in
        if let error { NSLog("Antigravity Boot: %@", error.localizedDescription) }
    }
}
RunLoop.main.run()
