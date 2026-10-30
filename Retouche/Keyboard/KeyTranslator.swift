import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Turns raw key codes into the characters the active keyboard layout produces,
/// including dead keys (^ then e → ê), which an event tap otherwise sees uncomposed.
///
/// Not thread-safe; owned by `KeyboardController` and used under its lock.
final class KeyTranslator {
    private var layoutData: Data?
    private var deadKeyState: UInt32 = 0

    func update(layoutData: Data?) {
        self.layoutData = layoutData
        deadKeyState = 0
    }

    func reset() {
        deadKeyState = 0
    }

    /// Returns "" while a dead key is pending, nil if the layout cannot translate the key.
    func translate(keyCode: UInt16, flags: CGEventFlags, keyboardType: UInt32) -> String? {
        guard let layoutData else { return nil }
        var modifiers: UInt32 = 0
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey >> 8) }
        if flags.contains(.maskAlphaShift) { modifiers |= UInt32(alphaLock >> 8) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey >> 8) }

        var length = 0
        var characters = [UniChar](repeating: 0, count: 8)
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return OSStatus(paramErr) }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDown), modifiers, keyboardType, 0, &deadKeyState, characters.count, &length, &characters)
        }
        guard status == noErr else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
