// Generates the Desk app icon: a warm paper tile with a ruled line and the "desk." wordmark.
// Usage: swift scripts/make-icon.swift Desk/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
func render(_ size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext
    let inset = size * 0.08
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = size * 0.2
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.01), blur: size * 0.04, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor(srgbRed: 0.98, green: 0.973, blue: 0.957, alpha: 1).cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(path); ctx.clip()
    // Faint ruled lines
    ctx.setStrokeColor(NSColor(srgbRed: 0.91, green: 0.894, blue: 0.867, alpha: 1).cgColor)
    ctx.setLineWidth(max(1, size * 0.006))
    var y = rect.minY + rect.height * 0.22
    while y < rect.maxY - rect.height * 0.3 {
        ctx.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: y)); ctx.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: y)); ctx.strokePath()
        y += rect.height * 0.13
    }
    // Colored time block
    let block = CGRect(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.22 + rect.height * 0.13 * 0.5,
                       width: rect.width * 0.5, height: rect.height * 0.13 * 1.6)
    ctx.addPath(CGPath(roundedRect: block, cornerWidth: size * 0.02, cornerHeight: size * 0.02, transform: nil))
    ctx.setFillColor(NSColor(srgbRed: 0.322, green: 0.498, blue: 0.788, alpha: 0.28).cgColor); ctx.fillPath()
    ctx.setFillColor(NSColor(srgbRed: 0.322, green: 0.498, blue: 0.788, alpha: 1).cgColor)
    ctx.fill(CGRect(x: block.minX, y: block.minY, width: max(2, size * 0.018), height: block.height))
    // Wordmark
    let font = NSFont(descriptor: NSFontDescriptor.preferredFontDescriptor(forTextStyle: .title1).withDesign(.serif)!.withSymbolicTraits(.italic), size: size * 0.3)
        ?? NSFont.systemFont(ofSize: size * 0.3)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(srgbRed: 0.141, green: 0.141, blue: 0.141, alpha: 1)]
    let text = NSAttributedString(string: "desk.", attributes: attrs)
    let ts = text.size()
    text.draw(at: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.maxY - rect.height * 0.2 - ts.height))
    img.unlockFocus()
    return img
}
func write(_ img: NSImage, _ px: Int, _ name: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}
for (pt, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let px = pt * scale
    write(render(CGFloat(px)), px, "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png")
}
print("icons written to \(outDir)")
