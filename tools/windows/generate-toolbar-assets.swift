#!/usr/bin/env swift

import AppKit
import CryptoKit
import Foundation

struct AssetDefinition {
    let name: String
    let insetDip: Double
    let fixedColor: Bool
}

struct AssetManifest: Encodable {
    let assets: [AssetEntry]
    let scales: [Int]
    let version: Int
}

struct AssetEntry: Encodable {
    let fixedColor: Bool
    let generated: [String: String]
    let insetDip: Double
    let logicalSizeDip: Int
    let name: String
    let sha256: String
    let source: String
}

let definitions = [
    AssetDefinition(name: "settings-more", insetDip: 2, fixedColor: false),
    AssetDefinition(name: "screenshot", insetDip: -1, fixedColor: false),
    AssetDefinition(name: "arrow", insetDip: 0, fixedColor: false),
    AssetDefinition(name: "pencil-tool", insetDip: 2, fixedColor: false),
    AssetDefinition(name: "highlighter-tool", insetDip: 2, fixedColor: false),
    AssetDefinition(name: "straw-ranging", insetDip: 0, fixedColor: false),
    AssetDefinition(name: "masaike2", insetDip: 0, fixedColor: false),
    AssetDefinition(name: "text-tool", insetDip: 0, fixedColor: false),
    AssetDefinition(name: "number-sequence", insetDip: 3, fixedColor: false),
    AssetDefinition(name: "zoom-in-tool", insetDip: 2, fixedColor: false),
    AssetDefinition(name: "eraser-tool", insetDip: 2, fixedColor: false),
    AssetDefinition(name: "scroll-screen2", insetDip: 0, fixedColor: false),
    AssetDefinition(name: "undo-enabled", insetDip: 0, fixedColor: true),
    AssetDefinition(name: "undo-disabled", insetDip: 0, fixedColor: true),
    AssetDefinition(name: "redo-enabled", insetDip: 0, fixedColor: true),
    AssetDefinition(name: "redo-disabled", insetDip: 0, fixedColor: true),
    AssetDefinition(name: "cancel-capture", insetDip: 2, fixedColor: false),
    AssetDefinition(name: "pin-to-screen", insetDip: 2, fixedColor: false),
    AssetDefinition(name: "save-to-file", insetDip: 2, fixedColor: false),
    AssetDefinition(name: "copy-to-clipboard", insetDip: 2, fixedColor: false),
]

let logicalSizeDip = 20
let scales = [100, 125, 150, 200]
let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let repositoryRoot = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let sourceDirectory = repositoryRoot
    .appendingPathComponent("platforms/mac/Resources/Icons", isDirectory: true)
let outputDirectory = repositoryRoot
    .appendingPathComponent("platforms/win/resources/toolbar", isDirectory: true)

func relativePath(for url: URL) -> String {
    let root = repositoryRoot.path.hasSuffix("/")
        ? repositoryRoot.path
        : repositoryRoot.path + "/"
    guard url.path.hasPrefix(root) else {
        fatalError("Path is outside repository: \(url.path)")
    }
    return String(url.path.dropFirst(root.count))
}

func sha256(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func sourceURL(for name: String) throws -> (url: URL, isVector: Bool) {
    let svg = sourceDirectory.appendingPathComponent("\(name).svg")
    if fileManager.fileExists(atPath: svg.path) {
        return (svg, true)
    }
    let png = sourceDirectory.appendingPathComponent("\(name).png")
    if fileManager.fileExists(atPath: png.path) {
        return (png, false)
    }
    throw NSError(
        domain: "ToolbarAssetGenerator",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Missing source for \(name)"])
}

func renderPNG(source: URL, isVector: Bool, pixelEdge: Int) throws -> Data {
    guard let image = NSImage(contentsOf: source) else {
        throw NSError(
            domain: "ToolbarAssetGenerator",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Cannot decode \(source.path)"])
    }
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelEdge,
        pixelsHigh: pixelEdge,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0)
    else {
        throw NSError(
            domain: "ToolbarAssetGenerator",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Cannot allocate \(pixelEdge)x\(pixelEdge) bitmap"])
    }

    bitmap.size = NSSize(width: logicalSizeDip, height: logicalSizeDip)
    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        NSGraphicsContext.restoreGraphicsState()
        throw NSError(
            domain: "ToolbarAssetGenerator",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Cannot create bitmap context"])
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = isVector ? .high : .none
    context.shouldAntialias = true
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: logicalSizeDip, height: logicalSizeDip).fill(using: .copy)
    image.draw(
        in: NSRect(x: 0, y: 0, width: logicalSizeDip, height: logicalSizeDip),
        from: .zero,
        operation: .sourceOver,
        fraction: 1.0,
        respectFlipped: false,
        hints: nil)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "ToolbarAssetGenerator",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Cannot encode \(source.lastPathComponent)"])
    }
    return png
}

do {
    try fileManager.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true)

    var entries: [AssetEntry] = []
    for definition in definitions.sorted(by: { $0.name < $1.name }) {
        let source = try sourceURL(for: definition.name)
        let sourceData = try Data(contentsOf: source.url)
        var generated: [String: String] = [:]

        for scale in scales {
            let scaleDirectory = outputDirectory
                .appendingPathComponent(String(scale), isDirectory: true)
            try fileManager.createDirectory(
                at: scaleDirectory,
                withIntermediateDirectories: true)
            let output = scaleDirectory
                .appendingPathComponent("\(definition.name).png")
            let pixelEdge = Int(
                (Double(logicalSizeDip * scale) / 100.0).rounded(.toNearestOrAwayFromZero))
            let png = try renderPNG(
                source: source.url,
                isVector: source.isVector,
                pixelEdge: pixelEdge)
            try png.write(to: output, options: .atomic)
            generated[String(scale)] = relativePath(for: output)
        }

        entries.append(AssetEntry(
            fixedColor: definition.fixedColor,
            generated: generated,
            insetDip: definition.insetDip,
            logicalSizeDip: logicalSizeDip,
            name: definition.name,
            sha256: sha256(of: sourceData),
            source: relativePath(for: source.url)))
    }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let manifest = AssetManifest(assets: entries, scales: scales, version: 1)
    var manifestData = try encoder.encode(manifest)
    manifestData.append(0x0A)
    try manifestData.write(
        to: outputDirectory.appendingPathComponent("ToolbarAssets.json"),
        options: .atomic)
    print("Generated \(entries.count) toolbar assets at \(scales.count) scales.")
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(EXIT_FAILURE)
}
