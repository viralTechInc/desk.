// Posts debug commands to a running DEBUG build of Desk.
// Build once:  swiftc -O scripts/desk-debug.swift -o build/desk-debug
// Usage:       build/desk-debug screenshot /tmp/shot.png
//              build/desk-debug action week | day | today | tomorrow | next | prev | addBlock | demo | help | escape | undo | redo | quit
//              build/desk-debug date 2026-11-02
//              build/desk-debug resize 1440 900
//              build/desk-debug type "some text"
//              build/desk-debug appearance dark|light|system
//              build/desk-debug task "Call mom" [done] [week]
import Foundation
let a = CommandLine.arguments
guard a.count >= 2 else { print("usage: desk-debug <cmd> [args]"); exit(1) }
var info: [String: String] = ["cmd": a[1]]
switch a[1] {
case "screenshot": info["path"] = a[2]
case "action": info["name"] = a[2]; if a.count > 3 { info["value"] = a[3] }
case "date", "type", "appearance": info["value"] = a[2]
case "block": info["value"] = a[2]; info["start"] = a[3]; info["end"] = a[4]
case "task": info["value"] = a[2]; if a.contains("done") { info["done"] = "1" }; if a.contains("week") { info["scope"] = "week" }
case "resize": info["w"] = a[2]; info["h"] = a[3]
case "click": info["x"] = a[2]; info["y"] = a[3]
case "key": info["value"] = a[2]; if a.count > 3 { info["cmd"] = a[3] }
case "dump", "responder": info["path"] = a[2]
default: break
}
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("com.desk.planner.debug"), object: nil, userInfo: info, deliverImmediately: true)
