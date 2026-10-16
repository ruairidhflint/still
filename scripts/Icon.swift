import AppKit
import CoreText

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var iconChunks = Data()
func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
let types = ["16@1": "icp4", "16@2": "ic11", "32@1": "icp5", "32@2": "ic12", "128@1": "ic07", "128@2": "ic13", "256@1": "ic08", "256@2": "ic14", "512@1": "ic09", "512@2": "ic10"]
let letterFont = CTFontCreateWithName("Charter-Roman" as CFString, 1000, nil)
var character = UniChar(83) // Capital S
var glyphID = CGGlyph()
precondition(CTFontGetGlyphsForCharacters(letterFont, &character, &glyphID, 1))
let letterPath = CTFontCreatePathForGlyph(letterFont, glyphID, nil)!
let letterBounds = letterPath.boundingBoxOfPath
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(srgbRed: 0.965, green: 0.951, blue: 0.916, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 62, y: 62, width: 900, height: 900), xRadius: 200, yRadius: 200).fill()
        // Centre the visible outline, not the font's line box and baseline. Each resolution
        // is drawn from curves directly, avoiding text-smoothing or a downscaled bitmap.
        let letterScale = 490 / letterBounds.height
        context.cgContext.saveGState()
        context.cgContext.translateBy(x: 512 - letterBounds.midX * letterScale, y: 512 - letterBounds.midY * letterScale)
        context.cgContext.scaleBy(x: letterScale, y: letterScale)
        context.cgContext.setFillColor(NSColor(srgbRed: 0.16, green: 0.18, blue: 0.15, alpha: 1).cgColor)
        context.cgContext.addPath(letterPath)
        context.cgContext.fillPath()
        context.cgContext.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let png = bitmap.representation(using: .png, properties: [:])!
        try png.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        iconChunks.append(contentsOf: types["\(size)@\(scale)"]!.utf8)
        iconChunks.append(bigEndian(png.count + 8))
        iconChunks.append(png)
    }
}
var icon = Data("icns".utf8)
icon.append(bigEndian(iconChunks.count + 8)); icon.append(iconChunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
