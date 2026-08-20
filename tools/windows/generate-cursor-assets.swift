#!/usr/bin/env swift

import AppKit
import Foundation

private let cursorSize = 32
private let macCursorSize = 24
private let macCursorInset = (cursorSize - macCursorSize) / 2
private let crosshairHotSpot = NSPoint(
    x: NSCursor.crosshair.hotSpot.x + CGFloat(macCursorInset),
    y: NSCursor.crosshair.hotSpot.y + CGFloat(macCursorInset)
)

private func littleEndian16(_ value: UInt16, into data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
}

private func littleEndian32(_ value: UInt32, into data: inout Data) {
    data.append(UInt8(truncatingIfNeeded: value))
    data.append(UInt8(truncatingIfNeeded: value >> 8))
    data.append(UInt8(truncatingIfNeeded: value >> 16))
    data.append(UInt8(truncatingIfNeeded: value >> 24))
}

private func renderedBitmap(
    for image: NSImage,
    tint: NSColor? = nil,
    destination: NSRect = NSRect(
        x: macCursorInset,
        y: macCursorInset,
        width: macCursorSize,
        height: macCursorSize
    )
) throws -> NSBitmapImageRep {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: cursorSize,
        pixelsHigh: cursorSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    bitmap.size = NSSize(width: cursorSize, height: cursorSize)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(
        in: destination,
        from: .zero,
        operation: .copy,
        fraction: 1.0
    )
    if let tint {
        tint.setFill()
        destination.fill(using: .sourceAtop)
    }
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return bitmap
}

private func cursorData(
    bitmap: NSBitmapImageRep,
    hotSpot: NSPoint,
    flipVertically: Bool = false
) -> Data {
    let xorRowBytes = cursorSize * 4
    let andRowBytes = ((cursorSize + 31) / 32) * 4
    let bitmapBytes = 40 + xorRowBytes * cursorSize + andRowBytes * cursorSize
    var cursor = Data()
    littleEndian16(0, into: &cursor)
    littleEndian16(2, into: &cursor)
    littleEndian16(1, into: &cursor)
    cursor.append(UInt8(cursorSize))
    cursor.append(UInt8(cursorSize))
    cursor.append(0)
    cursor.append(0)
    littleEndian16(UInt16(hotSpot.x), into: &cursor)
    littleEndian16(UInt16(hotSpot.y), into: &cursor)
    littleEndian32(UInt32(bitmapBytes), into: &cursor)
    littleEndian32(22, into: &cursor)

    littleEndian32(40, into: &cursor)
    littleEndian32(UInt32(cursorSize), into: &cursor)
    littleEndian32(UInt32(cursorSize * 2), into: &cursor)
    littleEndian16(1, into: &cursor)
    littleEndian16(32, into: &cursor)
    littleEndian32(0, into: &cursor)
    littleEndian32(UInt32(xorRowBytes * cursorSize), into: &cursor)
    littleEndian32(0, into: &cursor)
    littleEndian32(0, into: &cursor)
    littleEndian32(0, into: &cursor)
    littleEndian32(0, into: &cursor)

    for y in 0..<cursorSize {
        let sourceY = flipVertically ? cursorSize - 1 - y : y
        for x in 0..<cursorSize {
            let color = bitmap.colorAt(x: x, y: sourceY)?.usingColorSpace(.deviceRGB)
                ?? .clear
            cursor.append(UInt8(max(0, min(255, Int(color.blueComponent * 255.0 + 0.5)))))
            cursor.append(UInt8(max(0, min(255, Int(color.greenComponent * 255.0 + 0.5)))))
            cursor.append(UInt8(max(0, min(255, Int(color.redComponent * 255.0 + 0.5)))))
            cursor.append(UInt8(max(0, min(255, Int(color.alphaComponent * 255.0 + 0.5)))))
        }
    }
    for y in 0..<cursorSize {
        let sourceY = flipVertically ? cursorSize - 1 - y : y
        var row = [UInt8](repeating: 0, count: andRowBytes)
        for x in 0..<cursorSize {
            let alpha = bitmap.colorAt(x: x, y: sourceY)?.alphaComponent ?? 0
            if alpha < 0.5 {
                row[x / 8] |= UInt8(1 << (7 - x % 8))
            }
        }
        cursor.append(contentsOf: row)
    }
    return cursor
}

let scriptURL = URL(fileURLWithPath: #filePath)
let repository = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let outputDirectory = repository
    .appendingPathComponent("platforms/win/resources/cursors", isDirectory: true)
let output = outputDirectory.appendingPathComponent("xxsnap-crosshair.cur")
let rotationOutput = outputDirectory.appendingPathComponent("xxsnap-rotation.cur")

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)
let crosshairBitmap = try renderedBitmap(for: NSCursor.crosshair.image)
try cursorData(bitmap: crosshairBitmap, hotSpot: crosshairHotSpot)
    .write(to: output, options: .atomic)
print("Generated \(output.path) with the macOS crosshair centered in a 32x32 Win32 canvas.")

let rotationSource = repository
    .appendingPathComponent("platforms/mac/Resources/Icons/refresh (1).svg")
guard let rotationImage = NSImage(contentsOf: rotationSource) else {
    throw CocoaError(.fileReadCorruptFile)
}
let rotationBitmap = try renderedBitmap(
    for: rotationImage,
    destination: NSRect(
        x: macCursorInset + 3,
        y: macCursorInset + 3,
        width: 18,
        height: 18
    )
)
try cursorData(bitmap: rotationBitmap, hotSpot: NSPoint(x: 16, y: 16))
    .write(to: rotationOutput, options: .atomic)
print("Generated \(rotationOutput.path) from the macOS rotation cursor SVG.")

let eyedropperSource = repository
    .appendingPathComponent("platforms/mac/Resources/Icons/eyedropper.svg")
guard let eyedropperImage = NSImage(contentsOf: eyedropperSource) else {
    throw CocoaError(.fileReadCorruptFile)
}
let eyedropperRect = NSRect(
    x: macCursorInset + 3,
    y: macCursorInset + 3,
    width: 18,
    height: 18
)
let eyedropperHotSpot = NSPoint(
    x: CGFloat(macCursorInset) + 3.6,
    y: CGFloat(macCursorInset) + 20.4
)
for (name, tint) in [
    ("xxsnap-eyedropper.cur", nil),
    ("xxsnap-eyedropper-light.cur", NSColor.white),
] as [(String, NSColor?)] {
    let bitmap = try renderedBitmap(
        for: eyedropperImage,
        tint: tint,
        destination: eyedropperRect
    )
    let destination = outputDirectory.appendingPathComponent(name)
    try cursorData(
        bitmap: bitmap,
        hotSpot: eyedropperHotSpot,
        flipVertically: true
    )
        .write(to: destination, options: .atomic)
    print("Generated \(destination.path) from the macOS eyedropper cursor SVG.")
}

let brushSource = repository
    .appendingPathComponent(
        "platforms/win/resources/icons/black-outline-white-pencil.svg"
    )
guard let brushImage = NSImage(contentsOf: brushSource) else {
    throw CocoaError(.fileReadCorruptFile)
}
for name in ["xxsnap-brush.cur", "xxsnap-brush-light.cur"] {
    let brushBitmap = try renderedBitmap(
        for: brushImage,
        destination: NSRect(x: 7, y: 7, width: 18, height: 18)
    )
    let brushOutput = outputDirectory.appendingPathComponent(name)
    try cursorData(
        bitmap: brushBitmap,
        hotSpot: NSPoint(x: 10, y: 22),
        flipVertically: true
    ).write(to: brushOutput, options: .atomic)
    print("Generated \(brushOutput.path) from the Windows pencil cursor SVG.")
}

private func moveCursorImage(foreground: NSColor, outline: NSColor) -> NSImage {
    let size = NSSize(width: 28, height: 28)
    let image = NSImage(size: size)
    image.lockFocus()
    if let symbol = NSImage(
        systemSymbolName: "arrow.up.and.down.and.arrow.left.and.right",
        accessibilityDescription: "Move"
    )?.withSymbolConfiguration(
        NSImage.SymbolConfiguration(pointSize: 22, weight: .light)
    ) {
        symbol.draw(in: NSRect(x: 3, y: 3, width: 22, height: 22))
        foreground.setFill()
        NSRect(x: 3, y: 3, width: 22, height: 22).fill(using: .sourceAtop)
    } else {
        let drawPath = { () -> NSBezierPath in
            let path = NSBezierPath()
            let center = NSPoint(x: 14, y: 14)
            path.move(to: NSPoint(x: center.x, y: 4))
            path.line(to: NSPoint(x: center.x, y: 24))
            path.move(to: NSPoint(x: 4, y: center.y))
            path.line(to: NSPoint(x: 24, y: center.y))
            for (start, end) in [
                (NSPoint(x: 14, y: 24), NSPoint(x: 10, y: 20)),
                (NSPoint(x: 14, y: 24), NSPoint(x: 18, y: 20)),
                (NSPoint(x: 14, y: 4), NSPoint(x: 10, y: 8)),
                (NSPoint(x: 14, y: 4), NSPoint(x: 18, y: 8)),
                (NSPoint(x: 4, y: 14), NSPoint(x: 8, y: 10)),
                (NSPoint(x: 4, y: 14), NSPoint(x: 8, y: 18)),
                (NSPoint(x: 24, y: 14), NSPoint(x: 20, y: 10)),
                (NSPoint(x: 24, y: 14), NSPoint(x: 20, y: 18)),
            ] {
                path.move(to: start)
                path.line(to: end)
            }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            return path
        }
        let outlinePath = drawPath()
        outline.setStroke()
        outlinePath.lineWidth = 4
        outlinePath.stroke()
        let path = drawPath()
        foreground.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
    image.unlockFocus()
    return image
}

private func resizeCursorImage(
    angle: CGFloat,
    foreground: NSColor,
    drawsOutline: Bool = true
) -> NSImage {
    let size = NSSize(width: 24, height: 24)
    let center = NSPoint(x: 12, y: 12)
    let image = NSImage(size: size)
    image.lockFocus()
    if let context = NSGraphicsContext.current?.cgContext {
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: angle)
        context.translateBy(x: -center.x, y: -center.y)
    }
    let path = NSBezierPath()
    for (start, end) in [
        (NSPoint(x: 5, y: 12), NSPoint(x: 19, y: 12)),
        (NSPoint(x: 5, y: 12), NSPoint(x: 9, y: 8)),
        (NSPoint(x: 5, y: 12), NSPoint(x: 9, y: 16)),
        (NSPoint(x: 19, y: 12), NSPoint(x: 15, y: 8)),
        (NSPoint(x: 19, y: 12), NSPoint(x: 15, y: 16)),
    ] {
        path.move(to: start)
        path.line(to: end)
    }
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    if drawsOutline {
        NSColor.black.withAlphaComponent(0.75).setStroke()
        path.lineWidth = 5
        path.stroke()
    }
    foreground.setStroke()
    path.lineWidth = 2
    path.stroke()
    image.unlockFocus()
    return image
}

for (name, image) in [
    ("xxsnap-move.cur", moveCursorImage(
        foreground: .black, outline: NSColor.white.withAlphaComponent(0.9))),
    ("xxsnap-move-light.cur", moveCursorImage(
        foreground: .white, outline: NSColor.black.withAlphaComponent(0.75))),
    ("xxsnap-resize-left-right.cur", resizeCursorImage(
        angle: 0, foreground: .black)),
    ("xxsnap-resize-left-right-light.cur", resizeCursorImage(
        angle: 0, foreground: .white)),
    ("xxsnap-resize-up-down.cur", resizeCursorImage(
        angle: .pi / 2, foreground: .black)),
    ("xxsnap-resize-up-down-light.cur", resizeCursorImage(
        angle: .pi / 2, foreground: .white)),
    ("xxsnap-resize-top-left-bottom-right.cur", resizeCursorImage(
        angle: -.pi / 4, foreground: .black, drawsOutline: false)),
    ("xxsnap-resize-top-left-bottom-right-light.cur", resizeCursorImage(
        angle: -.pi / 4, foreground: .white, drawsOutline: false)),
    ("xxsnap-resize-top-right-bottom-left.cur", resizeCursorImage(
        angle: .pi / 4, foreground: .black, drawsOutline: false)),
    ("xxsnap-resize-top-right-bottom-left-light.cur", resizeCursorImage(
        angle: .pi / 4, foreground: .white, drawsOutline: false)),
] {
    let bitmap = try renderedBitmap(
        for: image,
        destination: NSRect(
            x: (CGFloat(cursorSize) - image.size.width) / 2,
            y: (CGFloat(cursorSize) - image.size.height) / 2,
            width: image.size.width,
            height: image.size.height
        )
    )
    let destination = outputDirectory.appendingPathComponent(name)
    try cursorData(
        bitmap: bitmap,
        hotSpot: NSPoint(x: 16, y: 16),
        flipVertically: true
    ).write(to: destination, options: .atomic)
    print("Generated \(destination.path) from the macOS cursor geometry.")
}

let eraserSource = repository
    .appendingPathComponent("platforms/mac/Resources/Icons/eraser.svg")
guard let eraserImage = NSImage(contentsOf: eraserSource) else {
    throw CocoaError(.fileReadCorruptFile)
}
let eraserHotSpot = NSPoint(
    x: 7 + CGFloat(macCursorInset),
    y: 17 + CGFloat(macCursorInset)
)
for (name, tint) in [
    ("xxsnap-eraser.cur", nil),
    ("xxsnap-eraser-light.cur", NSColor.white),
] as [(String, NSColor?)] {
    let bitmap = try renderedBitmap(
        for: eraserImage,
        tint: tint,
        destination: NSRect(x: 7, y: 7, width: 18, height: 18)
    )
    let destination = outputDirectory.appendingPathComponent(name)
    try cursorData(
        bitmap: bitmap,
        hotSpot: eraserHotSpot,
        flipVertically: true
    )
        .write(to: destination, options: .atomic)
    print("Generated \(destination.path) from the macOS eraser cursor SVG.")
}
