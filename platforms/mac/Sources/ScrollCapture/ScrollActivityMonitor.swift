import AppKit
import ApplicationServices

let automaticScrollCaptureEventTag: Int64 = 0x5858534E41505354

enum AutomaticScrollCaptureEventPolicy {
    static func shouldBlock(
        type: CGEventType,
        sourceTag: Int64,
        blocksPointerButtons: Bool
    ) -> Bool {
        switch type {
        case .scrollWheel:
            return sourceTag != automaticScrollCaptureEventTag
        case .leftMouseDown, .leftMouseUp:
            return blocksPointerButtons && sourceTag != automaticScrollCaptureEventTag
        default:
            return false
        }
    }
}

struct OuterScrollbarThumbObservation: Equatable {
    let pixelX: CGFloat
    let thumbStart: CGFloat
    let thumbEnd: CGFloat
    let pixelWidth: CGFloat
    let pixelHeight: CGFloat

    var thumbLength: CGFloat { thumbEnd - thumbStart }
}

enum OuterScrollbarThumbDetector {
    private struct Candidate {
        let x: Int
        let start: Int
        let end: Int
    }

    static func detect(in image: NSImage) -> OuterScrollbarThumbObservation? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard image.size.width > 0,
              image.size.height > 0,
              let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        else { return nil }

        let scaleX = CGFloat(cgImage.width) / image.size.width
        let stripWidth = min(cgImage.width, max(8, Int(ceil(16 * scaleX))))
        guard stripWidth > 0,
              let strip = cgImage.cropping(to: CGRect(
                  x: cgImage.width - stripWidth,
                  y: 0,
                  width: stripWidth,
                  height: cgImage.height
              ))
        else { return nil }

        let bytesPerRow = stripWidth * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * cgImage.height)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: stripWidth,
                height: cgImage.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(strip, in: CGRect(x: 0, y: 0, width: stripWidth, height: cgImage.height))
            return true
        }
        guard rendered else { return nil }

        func colorKey(x: Int, y: Int) -> UInt32 {
            let offset = y * bytesPerRow + x * 4
            return UInt32(pixels[offset]) << 16
                | UInt32(pixels[offset + 1]) << 8
                | UInt32(pixels[offset + 2])
        }
        func luminance(_ key: UInt32) -> Double {
            let red = Double((key >> 16) & 0xff)
            let green = Double((key >> 8) & 0xff)
            let blue = Double(key & 0xff)
            return red * 0.2126 + green * 0.7152 + blue * 0.0722
        }

        var candidates: [Candidate] = []
        for x in 0..<stripWidth {
            var counts: [UInt32: Int] = [:]
            counts.reserveCapacity(8)
            for y in 0..<cgImage.height {
                counts[colorKey(x: x, y: y), default: 0] += 1
            }
            let minimumTrackRows = max(4, Int(Double(cgImage.height) * 0.05))
            guard let track = counts
                .filter({ $0.value >= minimumTrackRows })
                .max(by: { luminance($0.key) < luminance($1.key) }),
                  Double(track.value) / Double(cgImage.height) >= 0.35
            else { continue }
            let trackLuminance = luminance(track.key)

            var longestStart = -1
            var longestEnd = -1
            var currentStart = -1
            for y in 0...cgImage.height {
                let isContrasting: Bool
                if y < cgImage.height {
                    isContrasting = luminance(colorKey(x: x, y: y)) <= trackLuminance - 12
                } else {
                    isContrasting = false
                }
                if isContrasting {
                    if currentStart < 0 { currentStart = y }
                } else if currentStart >= 0 {
                    if y - currentStart > longestEnd - longestStart {
                        longestStart = currentStart
                        longestEnd = y
                    }
                    currentStart = -1
                }
            }
            let contrastCount = longestEnd - longestStart
            guard contrastCount >= 8,
                  contrastCount <= Int(Double(cgImage.height) * 0.60)
            else { continue }
            candidates.append(Candidate(
                x: x,
                start: longestStart,
                end: longestEnd
            ))
        }

        var groups: [[Candidate]] = []
        for candidate in candidates {
            if let last = groups.last?.last,
               candidate.x == last.x + 1,
               abs(candidate.start - last.start) <= 2,
               abs(candidate.end - last.end) <= 2 {
                groups[groups.count - 1].append(candidate)
            } else {
                groups.append([candidate])
            }
        }
        guard let group = groups
            .filter({ $0.count >= 3 })
            .max(by: { $0.count < $1.count })
        else { return nil }
        let divisor = CGFloat(group.count)
        let localX = group.reduce(CGFloat.zero) { $0 + CGFloat($1.x) } / divisor
        let start = group.reduce(CGFloat.zero) { $0 + CGFloat($1.start) } / divisor
        let end = group.reduce(CGFloat.zero) { $0 + CGFloat($1.end) } / divisor
        return OuterScrollbarThumbObservation(
            pixelX: CGFloat(cgImage.width - stripWidth) + localX,
            thumbStart: start,
            thumbEnd: end,
            pixelWidth: CGFloat(cgImage.width),
            pixelHeight: CGFloat(cgImage.height)
        )
    }
}

private final class AutomaticScrollCaptureEventFilter: @unchecked Sendable {
    private let lock = NSLock()
    private var pointerButtonsBlocked = false

    var blocksPointerButtons: Bool {
        get { lock.withLock { pointerButtonsBlocked } }
        set { lock.withLock { pointerButtonsBlocked = newValue } }
    }
}

private func automaticScrollCaptureEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let filter = userInfo.map {
        Unmanaged<AutomaticScrollCaptureEventFilter>.fromOpaque($0).takeUnretainedValue()
    }
    if AutomaticScrollCaptureEventPolicy.shouldBlock(
        type: type,
        sourceTag: event.getIntegerValueField(.eventSourceUserData),
        blocksPointerButtons: filter?.blocksPointerButtons ?? false
    ) {
        return nil
    }
    return Unmanaged.passUnretained(event)
}

enum AutomaticScrollCaptureStepError: Error {
    case accessibilityPermissionRequired
    case eventTapUnavailable
    case eventCreationFailed
}

@MainActor
final class AutomaticScrollCaptureStepController: ScrollCaptureStepControlling {
    typealias EventDispatcher = (CGEvent, pid_t?) -> Void
    typealias BoundaryStateResolver = (ScrollCaptureDirection, NSPoint) -> ScrollCaptureBoundaryState
    typealias TargetApplicationActivator = (pid_t) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let eventDispatcher: EventDispatcher
    private let pointerLocationProvider: () -> CGPoint?
    private let pointerWarper: (CGPoint) -> Void
    private let targetProcessIdentifierProvider: () -> pid_t?
    private let targetApplicationActivator: TargetApplicationActivator
    private let boundaryStateResolver: BoundaryStateResolver?
    private let eventFilter = AutomaticScrollCaptureEventFilter()

    init(
        eventDispatcher: @escaping EventDispatcher = { event, processIdentifier in
            if let processIdentifier {
                event.postToPid(processIdentifier)
            } else {
                event.post(tap: .cghidEventTap)
            }
        },
        pointerLocationProvider: @escaping () -> CGPoint? = {
            CGEvent(source: nil)?.location
        },
        pointerWarper: @escaping (CGPoint) -> Void = { point in
            CGWarpMouseCursorPosition(point)
        },
        targetProcessIdentifierProvider: @escaping () -> pid_t? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        targetApplicationActivator: @escaping TargetApplicationActivator = { processIdentifier in
            _ = NSRunningApplication(processIdentifier: processIdentifier)?.activate(options: [])
        },
        boundaryStateResolver: BoundaryStateResolver? = nil
    ) {
        self.eventDispatcher = eventDispatcher
        self.pointerLocationProvider = pointerLocationProvider
        self.pointerWarper = pointerWarper
        self.targetProcessIdentifierProvider = targetProcessIdentifierProvider
        self.targetApplicationActivator = targetApplicationActivator
        self.boundaryStateResolver = boundaryStateResolver
    }

    static func wheelDelta(direction: ScrollCaptureDirection, distance: CGFloat) -> CGFloat {
        switch direction {
        case .down: return -abs(distance)
        case .up: return abs(distance)
        case .unknown: return 0
        @unknown default: return 0
        }
    }

    func boundaryState(
        direction: ScrollCaptureDirection,
        at point: NSPoint
    ) -> ScrollCaptureBoundaryState {
        if let boundaryStateResolver {
            return boundaryStateResolver(direction, point)
        }
        guard let processIdentifier = targetProcessIdentifierProvider() else {
            return .unavailable
        }
        let application = AXUIElementCreateApplication(processIdentifier)
        let quartzPoint = Self.quartzPoint(fromAppKitPoint: point)
        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            application,
            Float(quartzPoint.x),
            Float(quartzPoint.y),
            &hitElement
        ) == .success, var element = hitElement else {
            return .unavailable
        }

        for _ in 0..<16 {
            if let state = Self.scrollBarBoundaryState(from: element, direction: direction) {
                return state
            }
            guard let parent = Self.elementAttribute(kAXParentAttribute as CFString, from: element) else {
                break
            }
            element = parent
        }
        return .unavailable
    }

    static func boundaryState(
        direction: ScrollCaptureDirection,
        value: Double,
        minimum: Double,
        maximum: Double
    ) -> ScrollCaptureBoundaryState {
        guard value.isFinite, minimum.isFinite, maximum.isFinite, maximum > minimum else {
            return .unavailable
        }
        let tolerance = max((maximum - minimum) * 0.005, 0.0001)
        switch direction {
        case .up:
            return value <= minimum + tolerance ? .atBoundary : .notAtBoundary
        case .down:
            return value >= maximum - tolerance ? .atBoundary : .notAtBoundary
        case .unknown:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func startBlockingPhysicalScroll() throws {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            throw AutomaticScrollCaptureStepError.accessibilityPermissionRequired
        }
        let mask = [CGEventType.scrollWheel, .leftMouseDown, .leftMouseUp].reduce(CGEventMask(0)) {
            $0 | (CGEventMask(1) << $1.rawValue)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: automaticScrollCaptureEventTapCallback,
            userInfo: Unmanaged.passUnretained(eventFilter).toOpaque()
        ) else {
            throw AutomaticScrollCaptureStepError.eventTapUnavailable
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw AutomaticScrollCaptureStepError.eventTapUnavailable
        }
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func performStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat,
        at point: NSPoint
    ) async throws {
        if let processIdentifier = targetProcessIdentifierProvider() {
            targetApplicationActivator(processIdentifier)
            try await Task.sleep(for: .milliseconds(80))
        }
        try await deliverWheelStep(
            direction: direction,
            distance: distance,
            at: point,
            to: nil
        )
    }

    func performTargetedStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat,
        at point: NSPoint
    ) async throws -> Bool {
        guard let processIdentifier = targetProcessIdentifierProvider() else { return false }
        targetApplicationActivator(processIdentifier)
        try await Task.sleep(for: .milliseconds(80))
        try await deliverWheelStep(
            direction: direction,
            distance: distance,
            at: point,
            to: processIdentifier
        )
        return true
    }

    func performScrollbarStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat,
        in viewport: NSRect,
        capturedImage: NSImage
    ) async throws -> Bool {
        guard direction == .down || direction == .up,
              viewport.width > 0,
              viewport.height > 0,
              let observation = OuterScrollbarThumbDetector.detect(in: capturedImage),
              let processIdentifier = targetProcessIdentifierProvider()
        else { return false }

        let thumbHeight = observation.thumbLength / observation.pixelHeight * viewport.height
        let requestedDrag = max(4, distance / viewport.height * thumbHeight)
        let centerY = viewport.minY
            + (observation.thumbStart + observation.thumbEnd) / 2
                / observation.pixelHeight * viewport.height
        let startPoint = NSPoint(
            x: viewport.minX
                + (observation.pixelX + 0.5) / observation.pixelWidth * viewport.width,
            y: centerY
        )
        let minimumY = viewport.minY + thumbHeight / 2 + 2
        let maximumY = viewport.maxY - thumbHeight / 2 - 2
        let proposedEndY = direction == .down
            ? startPoint.y - requestedDrag
            : startPoint.y + requestedDrag
        let endPoint = NSPoint(
            x: startPoint.x,
            y: min(max(proposedEndY, minimumY), maximumY)
        )
        guard abs(endPoint.y - startPoint.y) >= 2,
              let originalPointerLocation = pointerLocationProvider()
        else { return false }

        targetApplicationActivator(processIdentifier)
        try await Task.sleep(for: .milliseconds(80))
        let source = CGEventSource(stateID: .combinedSessionState)
        let quartzStart = Self.quartzPoint(fromAppKitPoint: startPoint)
        let quartzEnd = Self.quartzPoint(fromAppKitPoint: endPoint)
        NSLog(
            "xxsnap automatic scrollbar drag direction=%@ start=(%.1f, %.1f) end=(%.1f, %.1f)",
            String(describing: direction),
            quartzStart.x,
            quartzStart.y,
            quartzEnd.x,
            quartzEnd.y
        )
        eventFilter.blocksPointerButtons = true
        defer {
            pointerWarper(originalPointerLocation)
            eventFilter.blocksPointerButtons = false
        }

        func makeMouseEvent(_ type: CGEventType, at point: CGPoint) -> CGEvent? {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else { return nil }
            event.location = point
            event.setIntegerValueField(.eventSourceUserData, value: automaticScrollCaptureEventTag)
            return event
        }
        pointerWarper(quartzStart)
        guard let move = makeMouseEvent(.mouseMoved, at: quartzStart),
              let down = makeMouseEvent(.leftMouseDown, at: quartzStart)
        else { throw AutomaticScrollCaptureStepError.eventCreationFailed }
        eventDispatcher(move, nil)
        try await Task.sleep(for: .milliseconds(24))
        eventDispatcher(down, nil)
        for step in 1...4 {
            let progress = CGFloat(step) / 4
            let point = CGPoint(
                x: quartzStart.x + (quartzEnd.x - quartzStart.x) * progress,
                y: quartzStart.y + (quartzEnd.y - quartzStart.y) * progress
            )
            pointerWarper(point)
            guard let drag = makeMouseEvent(.leftMouseDragged, at: point) else {
                throw AutomaticScrollCaptureStepError.eventCreationFailed
            }
            eventDispatcher(drag, nil)
            try await Task.sleep(for: .milliseconds(16))
        }
        guard let up = makeMouseEvent(.leftMouseUp, at: quartzEnd) else {
            throw AutomaticScrollCaptureStepError.eventCreationFailed
        }
        eventDispatcher(up, nil)
        try await Task.sleep(for: .milliseconds(140))
        return true
    }

    private func deliverWheelStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat,
        at point: NSPoint,
        to processIdentifier: pid_t?
    ) async throws {
        let totalDelta = Self.wheelDelta(direction: direction, distance: distance)
        guard totalDelta != 0 else { return }
        guard let originalPointerLocation = pointerLocationProvider() else {
            throw AutomaticScrollCaptureStepError.eventCreationFailed
        }
        let wheelTickCount = max(1, min(64, Int((abs(totalDelta) / 40).rounded())))
        let maximumTicksPerPulse = 3
        let pulseCount = Int(ceil(Double(wheelTickCount) / Double(maximumTicksPerPulse)))
        let tickSign: Int32 = totalDelta < 0 ? -1 : 1
        let quartzPoint = Self.quartzPoint(fromAppKitPoint: point)
        NSLog(
            "xxsnap automatic scroll direction=%@ delta=%.1f ticks=%ld pulses=%ld target=(%.1f, %.1f)",
            String(describing: direction),
            totalDelta,
            wheelTickCount,
            pulseCount,
            quartzPoint.x,
            quartzPoint.y
        )
        eventFilter.blocksPointerButtons = true
        defer {
            pointerWarper(originalPointerLocation)
            eventFilter.blocksPointerButtons = false
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let activationPoint = CGPoint(x: quartzPoint.x - 1, y: quartzPoint.y)
        for targetPoint in [activationPoint, quartzPoint] {
            pointerWarper(targetPoint)
            guard let moveEvent = CGEvent(
                mouseEventSource: source,
                mouseType: .mouseMoved,
                mouseCursorPosition: targetPoint,
                mouseButton: .left
            ) else {
                throw AutomaticScrollCaptureStepError.eventCreationFailed
            }
            moveEvent.location = targetPoint
            eventDispatcher(moveEvent, processIdentifier)
            try await Task.sleep(for: .milliseconds(16))
        }
        try await Task.sleep(for: .milliseconds(24))
        var remainingTicks = wheelTickCount
        for _ in 0..<pulseCount {
            let ticks = min(maximumTicksPerPulse, remainingTicks)
            guard let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .line,
                wheelCount: 1,
                wheel1: tickSign * Int32(ticks),
                wheel2: 0,
                wheel3: 0
            ) else {
                throw AutomaticScrollCaptureStepError.eventCreationFailed
            }
            event.setIntegerValueField(.eventSourceUserData, value: automaticScrollCaptureEventTag)
            event.location = quartzPoint
            eventDispatcher(event, processIdentifier)
            remainingTicks -= ticks
            try await Task.sleep(for: .milliseconds(16))
        }
        try await Task.sleep(for: .milliseconds(120))
    }

    func performKeyboardStep(
        direction: ScrollCaptureDirection,
        distance: CGFloat
    ) async throws -> Bool {
        let keyCode: CGKeyCode
        switch direction {
        case .down: keyCode = 125
        case .up: keyCode = 126
        case .unknown: return false
        @unknown default: return false
        }
        let pressCount = max(1, min(64, Int((abs(distance) / 40).rounded())))
        let source = CGEventSource(stateID: .combinedSessionState)
        let targetProcessIdentifier = targetProcessIdentifierProvider()
        if let targetProcessIdentifier {
            targetApplicationActivator(targetProcessIdentifier)
            try await Task.sleep(for: .milliseconds(80))
        }
        NSLog(
            "xxsnap automatic keyboard scroll direction=%@ presses=%ld",
            String(describing: direction),
            pressCount
        )
        for _ in 0..<pressCount {
            guard let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: true
            ), let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: keyCode,
                keyDown: false
            ) else {
                throw AutomaticScrollCaptureStepError.eventCreationFailed
            }
            keyDown.setIntegerValueField(.eventSourceUserData, value: automaticScrollCaptureEventTag)
            keyUp.setIntegerValueField(.eventSourceUserData, value: automaticScrollCaptureEventTag)
            eventDispatcher(keyDown, targetProcessIdentifier)
            eventDispatcher(keyUp, targetProcessIdentifier)
            try await Task.sleep(for: .milliseconds(24))
        }
        try await Task.sleep(for: .milliseconds(120))
        return true
    }

    func stop() {
        eventFilter.blocksPointerButtons = false
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private static func quartzPoint(fromAppKitPoint point: NSPoint) -> CGPoint {
        let desktopFrame = NSScreen.screens.reduce(NSRect.null) { partial, screen in
            partial.union(screen.frame)
        }
        return CGPoint(x: point.x, y: desktopFrame.maxY - point.y)
    }

    private static func scrollBarBoundaryState(
        from element: AXUIElement,
        direction: ScrollCaptureDirection
    ) -> ScrollCaptureBoundaryState? {
        let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
        let scrollBar: AXUIElement?
        if role == (kAXScrollBarRole as String) {
            scrollBar = element
        } else {
            scrollBar = elementAttribute(kAXVerticalScrollBarAttribute as CFString, from: element)
        }
        guard let scrollBar,
              let value = numberAttribute(kAXValueAttribute as CFString, from: scrollBar)
        else {
            return nil
        }
        let minimum = numberAttribute(kAXMinValueAttribute as CFString, from: scrollBar)
        let maximum = numberAttribute(kAXMaxValueAttribute as CFString, from: scrollBar)
        if let minimum, let maximum {
            return boundaryState(
                direction: direction,
                value: value,
                minimum: minimum,
                maximum: maximum
            )
        }
        guard (0...1).contains(value) else { return nil }
        return boundaryState(direction: direction, value: value, minimum: 0, maximum: 1)
    }

    private static func copiedAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value
    }

    private static func elementAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> AXUIElement? {
        guard let value = copiedAttribute(attribute, from: element),
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func stringAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> String? {
        copiedAttribute(attribute, from: element) as? String
    }

    private static func numberAttribute(
        _ attribute: CFString,
        from element: AXUIElement
    ) -> Double? {
        (copiedAttribute(attribute, from: element) as? NSNumber)?.doubleValue
    }
}

protocol ScrollEventMonitorRegistering: AnyObject {
    func addLocal(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any
    func addGlobal(_ handler: @escaping (NSEvent) -> Void) -> Any?
    func addGlobalKeyDown(_ handler: @escaping (NSEvent) -> Void) -> Any?
    func remove(_ monitor: Any)
}

private final class AppKitScrollEventMonitorRegistrar: ScrollEventMonitorRegistering {
    func addLocal(_ handler: @escaping (NSEvent) -> NSEvent?) -> Any {
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: handler)!
    }

    func addGlobal(_ handler: @escaping (NSEvent) -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: handler)
    }

    func addGlobalKeyDown(_ handler: @escaping (NSEvent) -> Void) -> Any? {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
    }

    func remove(_ monitor: Any) { NSEvent.removeMonitor(monitor) }
}

@MainActor
protocol ScrollActivityMonitoring: AnyObject {
    func start(_ callback: @escaping @MainActor () -> Void)
    func start(
        onScrollActivity: @escaping @MainActor () -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    )
    func start(
        onDirectionalScrollActivity: @escaping @MainActor (ScrollCaptureDirection) -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    )
    func start(
        onScrollActivity: @escaping @MainActor (ScrollCaptureScrollActivity) -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    )
    func stop()
}

extension ScrollActivityMonitoring {
    func start(
        onScrollActivity: @escaping @MainActor (ScrollCaptureScrollActivity) -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    ) {
        start(
            onDirectionalScrollActivity: {
                onScrollActivity(ScrollCaptureScrollActivity(direction: $0, distance: 0))
            },
            onTerminalCommand: onTerminalCommand
        )
    }

    func start(
        onDirectionalScrollActivity: @escaping @MainActor (ScrollCaptureDirection) -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    ) {
        start(
            onScrollActivity: { onDirectionalScrollActivity(.unknown) },
            onTerminalCommand: onTerminalCommand
        )
    }

    func start(
        onScrollActivity: @escaping @MainActor () -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    ) {
        start(onScrollActivity)
    }
}

@MainActor
final class ScrollActivityMonitor: ScrollActivityMonitoring {
    private let registrar: any ScrollEventMonitorRegistering
    private let isAccessibilityTrusted: () -> Bool
    private let log: (String) -> Void
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var globalKeyMonitor: Any?

    init(
        registrar: any ScrollEventMonitorRegistering = AppKitScrollEventMonitorRegistrar(),
        isAccessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
        log: @escaping (String) -> Void = { NSLog("%@", $0) }
    ) {
        self.registrar = registrar
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.log = log
    }

    func start(_ callback: @escaping @MainActor () -> Void) {
        start(onScrollActivity: callback, onTerminalCommand: { _ in })
    }

    func start(
        onScrollActivity: @escaping @MainActor () -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    ) {
        start(
            onDirectionalScrollActivity: { _ in onScrollActivity() },
            onTerminalCommand: onTerminalCommand
        )
    }

    func start(
        onDirectionalScrollActivity: @escaping @MainActor (ScrollCaptureDirection) -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    ) {
        start(
            onScrollActivity: { onDirectionalScrollActivity($0.direction) },
            onTerminalCommand: onTerminalCommand
        )
    }

    func start(
        onScrollActivity: @escaping @MainActor (ScrollCaptureScrollActivity) -> Void,
        onTerminalCommand: @escaping @MainActor (ScrollCaptureTerminalCommand) -> Void
    ) {
        guard localMonitor == nil, globalMonitor == nil, globalKeyMonitor == nil else { return }

        localMonitor = registrar.addLocal { event in
            let activity = Self.activity(for: event)
            Task { @MainActor in onScrollActivity(activity) }
            return event
        }
        globalMonitor = registrar.addGlobal { event in
            let activity = Self.activity(for: event)
            Task { @MainActor in onScrollActivity(activity) }
        }
        globalKeyMonitor = registrar.addGlobalKeyDown { event in
            guard !event.isARepeat,
                  let command = Self.terminalCommand(for: event.keyCode) else { return }
            Task { @MainActor in onTerminalCommand(command) }
        }
        if !isAccessibilityTrusted() {
            log("xxsnap global scroll-capture keys require Accessibility permission; toolbar controls remain available")
        }
    }

    static func direction(
        forScrollingDeltaY deltaY: CGFloat,
        isDirectionInvertedFromDevice: Bool = true
    ) -> ScrollCaptureDirection {
        activity(
            forScrollingDeltaY: deltaY,
            isDirectionInvertedFromDevice: isDirectionInvertedFromDevice
        ).direction
    }

    static func activity(
        forScrollingDeltaY deltaY: CGFloat,
        isDirectionInvertedFromDevice: Bool = true,
        isPreciseScrollingDelta: Bool = true
    ) -> ScrollCaptureScrollActivity {
        // AppKit has already applied the user's scrolling preference. The matcher
        // follows the pixels moving across the screen, while the preview indicator
        // follows the viewport through the document, so their directions oppose.
        _ = isDirectionInvertedFromDevice
        let distanceScale: CGFloat = isPreciseScrollingDelta ? 1 : 24
        let viewportDirection: ScrollCaptureDirection
        if deltaY < 0 {
            viewportDirection = .down
        } else if deltaY > 0 {
            viewportDirection = .up
        } else {
            viewportDirection = .unknown
        }
        let matcherDirection: ScrollCaptureDirection
        switch viewportDirection {
        case .down: matcherDirection = .up
        case .up: matcherDirection = .down
        case .unknown: matcherDirection = .unknown
        @unknown default: matcherDirection = .unknown
        }
        return ScrollCaptureScrollActivity(
            direction: matcherDirection,
            distance: abs(deltaY) * distanceScale,
            viewportDirection: viewportDirection
        )
    }

    private static func activity(for event: NSEvent) -> ScrollCaptureScrollActivity {
        guard event.type == .scrollWheel else {
            return ScrollCaptureScrollActivity(direction: .unknown, distance: 0)
        }
        return activity(
            forScrollingDeltaY: event.scrollingDeltaY,
            isDirectionInvertedFromDevice: event.isDirectionInvertedFromDevice,
            isPreciseScrollingDelta: event.hasPreciseScrollingDeltas
        )
    }

    private static func terminalCommand(for keyCode: UInt16) -> ScrollCaptureTerminalCommand? {
        switch keyCode {
        case 36, 76: return .finish
        case 53: return .cancel
        default: return nil
        }
    }

    func stop() {
        if let localMonitor {
            registrar.remove(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            registrar.remove(globalMonitor)
            self.globalMonitor = nil
        }
        if let globalKeyMonitor {
            registrar.remove(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    isolated deinit {
        if let localMonitor { registrar.remove(localMonitor) }
        if let globalMonitor { registrar.remove(globalMonitor) }
        if let globalKeyMonitor { registrar.remove(globalKeyMonitor) }
    }
}
