// Usage: swift scripts/shot.swift <output.png> [appName]
// Captures the frontmost window of the named app (default "Desk").
import Cocoa
let args = CommandLine.arguments
let out = args.count > 1 ? args[1] : "shot.png"
let app = args.count > 2 ? args[2] : "Desk"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
guard let win = list.first(where: { ($0[kCGWindowOwnerName as String] as? String) == app && (($0[kCGWindowLayer as String] as? Int) ?? 0) == 0 && (($0[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double ?? 0) > 200 }),
      let id = win[kCGWindowNumber as String] as? Int else {
    print("no window for \(app)"); exit(1)
}
let task = Process()
task.launchPath = "/usr/sbin/screencapture"
task.arguments = ["-x", "-o", "-l", String(id), out]
task.launch(); task.waitUntilExit()
print("captured window \(id) -> \(out)")
