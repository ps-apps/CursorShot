import CoreGraphics
import cshotCore
import XCTest

final class CoordinateConverterTests: XCTestCase {
    func testConvertsBetweenAppKitAndQuartzCoordinates() {
        let converter = CoordinateConverter()
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800)]
        let appKitRect = CGRect(x: 10, y: 50, width: 200, height: 100)

        let quartz = converter.quartzRect(fromAppKitRect: appKitRect, screenFrames: screens)
        XCTAssertEqual(quartz, CGRect(x: 10, y: 650, width: 200, height: 100))

        let roundTrip = converter.appKitRect(fromQuartzRect: quartz, screenFrames: screens)
        XCTAssertEqual(roundTrip, appKitRect)
    }
}
