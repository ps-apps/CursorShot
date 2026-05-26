import cshotCore
import XCTest

final class HotKeyPreferenceTests: XCTestCase {
    func testPresetHotKeyKeepsExistingDefault() {
        let hotKey = HotKeyPreset.controlOptionCommandS.hotKey

        XCTAssertEqual(hotKey.keyCode, 1)
        XCTAssertEqual(hotKey.modifiers, HotKeyModifier.mask([.control, .option, .command]))
        XCTAssertEqual(hotKey.keyLabel, "S")
        XCTAssertEqual(hotKey.label, "Control Option Command S")
        XCTAssertEqual(hotKey.validationResult, .valid)
    }

    func testCustomHotKeyRoundTripsThroughPreferenceValue() {
        let hotKey = HotKey(
            keyCode: 11,
            modifiers: HotKeyModifier.mask([.control, .option, .command]),
            keyLabel: "B"
        )

        let restored = HotKey(preferenceValue: hotKey.preferenceValue)

        XCTAssertEqual(restored, hotKey)
        XCTAssertEqual(restored?.label, "Control Option Command B")
    }

    func testResolverPrefersValidCustomHotKeyOverLegacyPreset() {
        let custom = HotKey(
            keyCode: 45,
            modifiers: HotKeyModifier.mask([.control, .option, .command]),
            keyLabel: "N"
        )

        XCTAssertEqual(
            HotKeyPreference.resolve(
                customHotKeyRaw: custom.preferenceValue,
                presetRaw: HotKeyPreset.controlOptionCommandTwo.rawValue
            ),
            custom
        )
    }

    func testResolverFallsBackToLegacyPresetWhenCustomHotKeyIsInvalid() {
        XCTAssertEqual(
            HotKeyPreference.resolve(
                customHotKeyRaw: "not-a-shortcut",
                presetRaw: HotKeyPreset.controlOptionCommandFive.rawValue
            ),
            HotKeyPreset.controlOptionCommandFive.hotKey
        )
    }

    func testValidationRejectsShortcutWithoutPrimaryModifier() {
        let hotKey = HotKey(
            keyCode: 1,
            modifiers: HotKeyModifier.mask([.shift]),
            keyLabel: "S"
        )

        XCTAssertEqual(hotKey.validationResult, .missingPrimaryModifier)
    }

    func testValidationRejectsModifierOnlyKey() {
        let hotKey = HotKey(
            keyCode: 55,
            modifiers: HotKeyModifier.mask([.command]),
            keyLabel: "Command"
        )

        XCTAssertEqual(hotKey.validationResult, .modifierOnly)
    }
}
