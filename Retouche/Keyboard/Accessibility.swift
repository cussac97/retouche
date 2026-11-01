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

    /// Removes Retouche's entry from Privacy & Security › Accessibility.
    /// An entry granted to an earlier build stays checked but no longer matches this one;
    /// removing it lets `requestTrust()` add the current build. Blocks until tccutil exits.
    @discardableResult
    static func resetTrust() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

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

    /// Where `word`, followed by `tail` up to the caret, is drawn. Tries the most precise source first:
    /// character ranges (native text views, web text fields), then text markers (web rich text),
    /// then the caret alone, then the text field itself.
    static func anchor(forWord word: String, followedBy tail: String) -> TextAnchor? {
        guard let element = focusedElement() else { return nil }
        if let rect = wordBoundsByRange(element, length: word.utf16.count, offset: tail.utf16.count) {
            return TextAnchor(rect: rect, precision: .word)
        }
        if let caret = caretMarker(element) {
            if let rect = wordBoundsByMarkers(element, caret: caret, length: word.count, offset: tail.count) {
                return TextAnchor(rect: rect, precision: .word)
            }
            if let rect = bounds(element, AXTextMarkerRangeCreate(nil, caret, caret), allowsZeroWidth: true) {
                return TextAnchor(rect: estimatedBounds(of: word, followedBy: tail, before: rect), precision: .caret)
            }
        }
        if let frame = frame(of: element), frame.height <= 200 {
            // Terminals built on xterm.js (Orca, VS Code, Hyper…) keep a one-cell text area under the cursor:
            // in a monospace grid, the word sits a known number of cells to its left.
            if (4...24).contains(frame.width), frame.height <= 40 {
                let cells = CGFloat(word.count + tail.count)
                let rect = CGRect(x: frame.minX - cells * frame.width, y: frame.minY, width: CGFloat(word.count) * frame.width, height: frame.height)
                return TextAnchor(rect: rect, precision: .word, isMonospaced: true)
            }
            if frame.width < 4 {
                return TextAnchor(rect: estimatedBounds(of: word, followedBy: tail, before: frame), precision: .caret)
            }
            return TextAnchor(rect: frame, precision: .field)
        }
        return nil
    }

    /// Half the line height approximates a character's width.
    private static func estimatedBounds(of word: String, followedBy tail: String, before caret: CGRect) -> CGRect {
        let advance = caret.height * 0.5
        let x = caret.minX - CGFloat(word.count + tail.count) * advance
        return CGRect(x: x, y: caret.minY, width: CGFloat(word.count) * advance, height: caret.height)
    }

    /// Chromium-based apps (Chrome, Electron…) only expose their text to Accessibility when asked to.
    /// Other apps ignore the attribute.
    static func enableManualAccessibility(for application: NSRunningApplication) {
        let element = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.15)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // MARK: - Geometry

    private static func wordBoundsByRange(_ element: AXUIElement, length: Int, offset: Int) -> CGRect? {
        guard let selection = selectedRange(element) else { return nil }
        var range = CFRange(location: selection.location - offset - length, length: length)
        guard range.location >= 0, let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        return rect(parameterized(element, kAXBoundsForRangeParameterizedAttribute, rangeValue))
    }

    private static func caretMarker(_ element: AXUIElement) -> AXTextMarker? {
        guard let selection = copy(element, "AXSelectedTextMarkerRange"), CFGetTypeID(selection) == AXTextMarkerRangeGetTypeID() else { return nil }
        return AXTextMarkerRangeCopyEndMarker(selection as! AXTextMarkerRange)
    }

    private static func wordBoundsByMarkers(_ element: AXUIElement, caret: AXTextMarker, length: Int, offset: Int) -> CGRect? {
        guard let end = marker(element, before: caret, by: offset), let start = marker(element, before: end, by: length) else { return nil }
        return bounds(element, AXTextMarkerRangeCreate(nil, start, end), allowsZeroWidth: false)
    }

    private static func marker(_ element: AXUIElement, before marker: AXTextMarker, by count: Int) -> AXTextMarker? {
        var marker = marker
        for _ in 0..<count {
            guard let previous = parameterized(element, "AXPreviousTextMarkerForTextMarker", marker),
                  CFGetTypeID(previous) == AXTextMarkerGetTypeID() else { return nil }
            marker = previous as! AXTextMarker
        }
        return marker
    }

    private static func bounds(_ element: AXUIElement, _ range: AXTextMarkerRange, allowsZeroWidth: Bool) -> CGRect? {
        rect(parameterized(element, "AXBoundsForTextMarkerRange", range), allowsZeroWidth: allowsZeroWidth)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = copy(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let extent = copy(element, kAXSizeAttribute), CFGetTypeID(extent) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin),
              AXValueGetValue(extent as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Apps answer an unknown position with an empty rect or one at the screen's origin.
    private static func rect(_ value: CFTypeRef?, allowsZeroWidth: Bool = false) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect),
              rect.width > 0 || allowsZeroWidth, rect.height > 0, rect.height < 400, rect.origin != .zero else { return nil }
        return rect
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
        return parameterized(element, kAXStringForRangeParameterizedAttribute, rangeValue) as? String
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func parameterized(_ element: AXUIElement, _ attribute: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &value) == .success else { return nil }
        return value
    }
}

#if DEBUG
extension Accessibility {
    /// Which geometry sources the focused field answers, for the `length` characters before the caret.
    /// With a pid, inspects the field focused inside that app even when it is in the background.
    static func diagnose(length: Int = 4, pid: pid_t? = nil) -> String {
        let focused: AXUIElement?
        if let pid {
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.5)
            AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            focused = copy(application, kAXFocusedUIElementAttribute).flatMap { CFGetTypeID($0) == AXUIElementGetTypeID() ? ($0 as! AXUIElement) : nil }
        } else {
            focused = focusedElement()
        }
        guard let element = focused else { return "focused element: none" }
        var lines = [
            "role: \(copy(element, kAXRoleAttribute) as? String ?? "-") / \(copy(element, kAXSubroleAttribute) as? String ?? "-")",
            "selected range: \(selectedRange(element).map { "\($0.location)+\($0.length)" } ?? "none")",
            "word by range: \(wordBoundsByRange(element, length: length, offset: 0).map { "\($0)" } ?? "none")",
        ]
        if let caret = caretMarker(element) {
            lines.append("word by markers: \(wordBoundsByMarkers(element, caret: caret, length: length, offset: 0).map { "\($0)" } ?? "none")")
            lines.append("caret: \(bounds(element, AXTextMarkerRangeCreate(nil, caret, caret), allowsZeroWidth: true).map { "\($0)" } ?? "none")")
        } else {
            lines.append("text markers: none")
        }
        lines.append("field: \(frame(of: element).map { "\($0)" } ?? "none")")
        return lines.joined(separator: "\n")
    }
}
#endif

/// Where a just-corrected word is drawn, in Accessibility coordinates (top-left origin).
struct TextAnchor: Sendable {
    enum Precision: String, Sendable {
        /// `rect` is the word's own bounds.
        case word
        /// `rect` is estimated from the insertion point after the word.
        case caret
        /// `rect` is the text field: only its frame is known.
        case field
    }

    var rect: CGRect
    var precision: Precision
    /// The word sits in a terminal's monospace grid.
    var isMonospaced = false
}
