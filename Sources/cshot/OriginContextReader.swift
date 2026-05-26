import AppKit
import ApplicationServices
import cshotCore
import Foundation

struct OriginContextReader {
    func capture() -> OriginContext {
        let app = NSWorkspace.shared.frontmostApplication
        let focusedElement = readFocusedElement()
        let selectedRange = focusedElement.flatMap(readSelectedRange)
        let title = focusedElement.flatMap(readWindowTitle) ?? app?.localizedName

        return OriginContext(
            pid: app?.processIdentifier ?? 0,
            bundleId: app?.bundleIdentifier,
            appName: app?.localizedName,
            windowTitle: title,
            focusedElement: focusedElement,
            selectedRange: selectedRange,
            mouseLocation: NSEvent.mouseLocation,
            capturedAt: Date()
        )
    }

    private func readFocusedElement() -> AXUIElement? {
        guard PermissionCenter.accessibilityGranted else {
            return nil
        }

        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )

        guard result == .success, let value else {
            return nil
        }

        return axElement(from: value)
    }

    private func readSelectedRange(from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard result == .success, let value else {
            return nil
        }

        guard let axValue = axValue(from: value) else {
            return nil
        }

        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private func readWindowTitle(from element: AXUIElement) -> String? {
        guard let window = readWindow(from: element) else {
            return readStringAttribute(kAXTitleAttribute, from: element)
        }

        return readStringAttribute(kAXTitleAttribute, from: window)
    }

    private func readWindow(from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXWindowAttribute as CFString,
            &value
        )

        guard result == .success, let value else {
            return nil
        }

        return axElement(from: value)
    }

    private func readStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value as? String
    }

    private func axElement(from value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private func axValue(from value: CFTypeRef) -> AXValue? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        return unsafeDowncast(value, to: AXValue.self)
    }
}
