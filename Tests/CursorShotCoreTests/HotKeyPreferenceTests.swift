import CursorShotCore
import XCTest

final class HotKeyPreferenceTests: XCTestCase {
    func testDefaultShortcutUsesOpenPickerPreset() {
        let hotKey = HotKeyRole.defaultCapture.defaultPreset.hotKey

        XCTAssertEqual(hotKey.keyCode, 1)
        XCTAssertEqual(hotKey.modifiers, HotKeyModifier.mask([.command, .shift]))
        XCTAssertEqual(hotKey.keyLabel, "S")
    }

    func testCustomHotKeyRoundTripsThroughPreferenceValue() {
        let hotKey = HotKey(
            keyCode: 8,
            modifiers: HotKeyModifier.mask([.control, .option, .command]),
            keyLabel: "C"
        )

        let restored = HotKey(preferenceValue: hotKey.preferenceValue)

        XCTAssertEqual(restored, hotKey)
    }

    func testResolverPrefersValidCustomHotKeyOverDefaultPreset() {
        let custom = HotKey(
            keyCode: 8,
            modifiers: HotKeyModifier.mask([.control, .option, .command]),
            keyLabel: "C"
        )

        XCTAssertEqual(
            HotKeyPreference.resolve(
                customHotKeyRaw: custom.preferenceValue,
                defaultPreset: .commandShiftS
            ),
            custom
        )
    }

    func testConflictValidatorFindsDuplicateAssignment() {
        let defaultHotKey = HotKeyRole.defaultCapture.defaultPreset.hotKey
        let assignments = [
            HotKeyAssignment(role: .defaultCapture, hotKey: defaultHotKey),
            HotKeyAssignment(role: .currentSpaceQuickCapture, hotKey: HotKeyRole.currentSpaceQuickCapture.defaultPreset.hotKey),
            HotKeyAssignment(role: .cmdTabQuickCapture, hotKey: defaultHotKey)
        ]

        let conflict = HotKeyConflictValidator.conflict(
            assigning: defaultHotKey,
            to: .cmdTabQuickCapture,
            among: assignments
        )

        XCTAssertEqual(conflict, HotKeyAssignment(role: .defaultCapture, hotKey: defaultHotKey))
    }
}
