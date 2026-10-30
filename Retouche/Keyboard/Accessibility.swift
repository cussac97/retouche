import AppKit
import ApplicationServices

/// Reads the focused text field through the Accessibility API.
/// Every call is synchronous IPC to the target app: call these off the main thread.
enum Accessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds Retouche to Privacy & Security › Accessibility.
    static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    /// The text before the caret, or nil when it cannot be known (no AX support, selection, secure field).
    static func textBeforeCaret(limit: Int = 300) -> String? {
        guard let element = focusedElement(), !isSecure(element), let selection = selectedRange(element), selection.length == 0 else { return nil }
        let start = max(0, selection.location - limit)
        let range = CFRange(location: start, length: selection.location - start)
        if range.length == 0 { return "" }
        if let text = string(of: element, in: range) { return text }
        guard let value = copy(element, kAXValueAttribute) as? String else { return nil }
        let nsValue = value as NSString
        guard selection.location <= nsValue.length else { return nil }
        return nsValue.substring(with: NSRange(location: range.location, length: range.length))
    }

    /// Screen rectangle (top-left origin) of a span ending `offsetFromCaret` UTF-16 units before the caret.
    static func boundsOfText(length: Int, endingBeforeCaretBy offsetFromCaret: Int) -> CGRect? {
        guard let element = focusedElement(), let selection = selectedRange(element) else { return nil }
        var range = CFRange(location: selection.location - offsetFromCaret - length, length: length)
        guard range.location >= 0, let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &result) == .success,
              let result, CFGetTypeID(result) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(result as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0, rect.height < 400 else { return nil }
        return rect
    }

    /// Electron apps only expose their text to Accessibility when asked to.
    static func enableManualAccessibility(for application: NSRunningApplication) {
        guard let bundleURL = application.bundleURL,
              FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path) else { return }
        let element = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // MARK: - Helpers

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        guard let value = copy(system, kAXFocusedUIElementAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        let element = value as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)
        return element
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        let role = copy(element, kAXRoleAttribute) as? String
        let subrole = copy(element, kAXSubroleAttribute) as? String
        return subrole == (kAXSecureTextFieldSubrole as String) || role == "AXSecureTextField"
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = copy(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func string(of element: AXUIElement, in range: CFRange) -> String? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, rangeValue, &result) == .success else { return nil }
        return result as? String
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }
}
