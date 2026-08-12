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

private func cursorData(bitmap: NSBitmapImageRep, hotSpot: NSPoint) -> Data {
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
        for x in 0..<cursorSize {
            let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                ?? .clear
            cursor.append(UInt8(max(0, min(255, Int(color.blueComponent * 255.0 + 0.5)))))
            cursor.append(UInt8(max(0, min(255, Int(color.greenComponent * 255.0 + 0.5)))))
            cursor.append(UInt8(max(0, min(255, Int(color.redComponent * 255.0 + 0.5)))))
            cursor.append(UInt8(max(0, min(255, Int(color.alphaComponent * 255.0 + 0.5)))))
        }
    }
    for y in 0..<cursorSize {
        var row = [UInt8](repeating: 0, count: andRowBytes)
        for x in 0..<cursorSize {
            let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
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
    try cursorData(bitmap: bitmap, hotSpot: eyedropperHotSpot)
        .write(to: destination, options: .atomic)
    print("Generated \(destination.path) from the macOS eyedropper cursor SVG.")
}

let eraserSource = repository
    .appendingPathComponent("platforms/mac/Resources/Icons/eraser-tool.svg")
guard let eraserImage = NSImage(contentsOf: eraserSource) else {
    throw CocoaError(.fileReadCorruptFile)
}
let eraserBitmap = try renderedBitmap(
    for: eraserImage,
    destination: NSRect(x: 7, y: 7, width: 18, height: 18)
)
let eraserOutput = outputDirectory.appendingPathComponent("xxsnap-eraser.cur")
let eraserHotSpot = NSPoint(
    x: 7 + CGFloat(macCursorInset),
    y: 17 + CGFloat(macCursorInset)
)
try cursorData(bitmap: eraserBitmap, hotSpot: eraserHotSpot)
    .write(to: eraserOutput, options: .atomic)
print("Generated \(eraserOutput.path) from the macOS eraser cursor SVG.")
