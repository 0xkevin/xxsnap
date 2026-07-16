import AppKit
import ApplicationServices

private let automaticScrollCaptureEventTag: Int64 = 0x5858534E41505354

private func automaticScrollCaptureEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard type == .scrollWheel else { return Unmanaged.passUnretained(event) }
    guard event.getIntegerValueField(.eventSourceUserData) == automaticScrollCaptureEventTag else {
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
    typealias EventDispatcher = (CGEvent) -> Void
    typealias BoundaryStateResolver = (ScrollCaptureDirection, NSPoint) -> ScrollCaptureBoundaryState

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let eventDispatcher: EventDispatcher
    private let pointerLocationProvider: () -> CGPoint?
    private let pointerWarper: (CGPoint) -> Void
    private let targetProcessIdentifierProvider: () -> pid_t?
    private let boundaryStateResolver: BoundaryStateResolver?

    init(
        eventDispatcher: @escaping EventDispatcher = { event in
            event.post(tap: .cghidEventTap)
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
        boundaryStateResolver: BoundaryStateResolver? = nil
    ) {
        self.eventDispatcher = eventDispatcher
        self.pointerLocationProvider = pointerLocationProvider
        self.pointerWarper = pointerWarper
        self.targetProcessIdentifierProvider = targetProcessIdentifierProvider
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
        let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: automaticScrollCaptureEventTapCallback,
            userInfo: nil
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
        let totalDelta = Self.wheelDelta(direction: direction, distance: distance)
        guard totalDelta != 0 else { return }
        guard let originalPointerLocation = pointerLocationProvider() else {
            throw AutomaticScrollCaptureStepError.eventCreationFailed
        }
        let pulseCount = 7
        let pulseDelta = Int32((totalDelta / CGFloat(pulseCount)).rounded())
        let quartzPoint = Self.quartzPoint(fromAppKitPoint: point)
        NSLog(
            "xxsnap automatic scroll direction=%@ delta=%.1f target=(%.1f, %.1f)",
            String(describing: direction),
            totalDelta,
            quartzPoint.x,
            quartzPoint.y
        )
        defer { pointerWarper(originalPointerLocation) }
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
            eventDispatcher(moveEvent)
            try await Task.sleep(for: .milliseconds(16))
        }
        try await Task.sleep(for: .milliseconds(24))
        for _ in 0..<pulseCount {
            guard let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .pixel,
                wheelCount: 1,
                wheel1: pulseDelta,
                wheel2: 0,
                wheel3: 0
            ) else {
                throw AutomaticScrollCaptureStepError.eventCreationFailed
            }
            event.setIntegerValueField(.eventSourceUserData, value: automaticScrollCaptureEventTag)
            event.location = quartzPoint
            eventDispatcher(event)
            try await Task.sleep(for: .milliseconds(24))
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
        let pressCount = max(1, min(12, Int((abs(distance) / 32).rounded())))
        let source = CGEventSource(stateID: .combinedSessionState)
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
            eventDispatcher(keyDown)
            eventDispatcher(keyUp)
            try await Task.sleep(for: .milliseconds(24))
        }
        try await Task.sleep(for: .milliseconds(120))
        return true
    }

    func stop() {
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
        let documentDeltaY = isDirectionInvertedFromDevice ? -deltaY : deltaY
        let direction: ScrollCaptureDirection
        if documentDeltaY < 0 {
            direction = .down
        } else if documentDeltaY > 0 {
            direction = .up
        } else {
            direction = .unknown
        }
        let distanceScale: CGFloat = isPreciseScrollingDelta ? 1 : 24
        let viewportDirection: ScrollCaptureDirection
        if deltaY < 0 {
            viewportDirection = .down
        } else if deltaY > 0 {
            viewportDirection = .up
        } else {
            viewportDirection = .unknown
        }
        return ScrollCaptureScrollActivity(
            direction: direction,
            distance: abs(documentDeltaY) * distanceScale,
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
