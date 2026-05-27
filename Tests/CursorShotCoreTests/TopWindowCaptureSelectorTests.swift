import CoreGraphics
import CursorShotCore
import XCTest

final class TopWindowCaptureSelectorTests: XCTestCase {
    func testSelectsFirstCandidateContainingCursor() {
        let selector = TopWindowCaptureSelector()
        let lowerWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 0, y: 0, width: 500, height: 500),
            windowID: 10,
            ownerPID: 100
        )
        let topWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 100, y: 100, width: 200, height: 200),
            windowID: 20,
            ownerPID: 200
        )

        let selection = selector.selection(
            at: CGPoint(x: 150, y: 150),
            candidates: [topWindow, lowerWindow]
        )

        XCTAssertEqual(selection, .window(topWindow.frame, windowID: topWindow.windowID))
    }

    func testReturnsNilWhenCursorIsNotInsideAnyCandidate() {
        let selector = TopWindowCaptureSelector()
        let candidate = TopWindowCaptureCandidate(
            frame: CGRect(x: 0, y: 0, width: 100, height: 100),
            windowID: 1,
            ownerPID: 100
        )

        let selection = selector.selection(
            at: CGPoint(x: 200, y: 200),
            candidates: [candidate]
        )

        XCTAssertNil(selection)
    }

    func testSelectsFirstCandidateOwnedByCurrentAppForCurrentAppTarget() {
        let selector = TopWindowCaptureSelector()
        let otherAppWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 0, y: 0, width: 300, height: 300),
            windowID: 10,
            ownerPID: 100
        )
        let currentAppTopWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 40, y: 40, width: 200, height: 200),
            windowID: 20,
            ownerPID: 200
        )
        let currentAppLowerWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 80, y: 80, width: 160, height: 160),
            windowID: 30,
            ownerPID: 200
        )

        let selection = selector.selection(
            for: 200,
            target: .currentApp,
            candidates: [otherAppWindow, currentAppTopWindow, currentAppLowerWindow]
        )

        XCTAssertEqual(selection, .window(currentAppTopWindow.frame, windowID: currentAppTopWindow.windowID))
    }

    func testSelectsFirstWindowNotOwnedByCurrentAppForNextAppTarget() {
        let selector = TopWindowCaptureSelector()
        let currentAppTopWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 0, y: 0, width: 300, height: 300),
            windowID: 10,
            ownerPID: 200
        )
        let currentAppLowerWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 30, y: 30, width: 260, height: 260),
            windowID: 20,
            ownerPID: 200
        )
        let nextAppTopWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 60, y: 60, width: 220, height: 220),
            windowID: 30,
            ownerPID: 300
        )

        let selection = selector.selection(
            forPreferredOwnerPIDs: [300],
            candidates: [currentAppTopWindow, currentAppLowerWindow, nextAppTopWindow]
        )

        XCTAssertEqual(selection, .window(nextAppTopWindow.frame, windowID: nextAppTopWindow.windowID))
    }

    func testSelectsPreferredNextAppWindowOverVisibleStackOrder() {
        let selector = TopWindowCaptureSelector()
        let currentAppWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 0, y: 0, width: 300, height: 300),
            windowID: 10,
            ownerPID: 200
        )
        let visibleButNotNextAppWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 20, y: 20, width: 260, height: 260),
            windowID: 20,
            ownerPID: 300
        )
        let cmdTabNextAppWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 40, y: 40, width: 220, height: 220),
            windowID: 30,
            ownerPID: 400
        )

        let selection = selector.selection(
            forPreferredOwnerPIDs: [400],
            candidates: [currentAppWindow, visibleButNotNextAppWindow, cmdTabNextAppWindow],
        )

        XCTAssertEqual(selection, .window(cmdTabNextAppWindow.frame, windowID: cmdTabNextAppWindow.windowID))
    }

    func testReturnsNilForPreferredNextAppPIDWithNoVisibleWindow() {
        let selector = TopWindowCaptureSelector()
        let currentAppWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 0, y: 0, width: 300, height: 300),
            windowID: 10,
            ownerPID: 200
        )
        let fallbackNextAppWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 20, y: 20, width: 260, height: 260),
            windowID: 20,
            ownerPID: 300
        )

        let selection = selector.selection(
            forPreferredOwnerPIDs: [999],
            candidates: [currentAppWindow, fallbackNextAppWindow],
        )

        XCTAssertNil(selection)
    }

    func testSelectsFirstWindowNotOwnedByCurrentAppForTopAppCurrentSpaceTarget() {
        let selector = TopWindowCaptureSelector()
        let currentAppWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 0, y: 0, width: 300, height: 300),
            windowID: 10,
            ownerPID: 200
        )
        let topOtherAppWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 40, y: 40, width: 220, height: 220),
            windowID: 20,
            ownerPID: 300
        )

        let selection = selector.selection(
            for: 200,
            target: .topApp,
            candidates: [currentAppWindow, topOtherAppWindow]
        )

        XCTAssertEqual(selection, .window(topOtherAppWindow.frame, windowID: topOtherAppWindow.windowID))
    }

    func testReturnsNilForTopAppCurrentSpaceTargetWhenOnlyCurrentAppIsVisible() {
        let selector = TopWindowCaptureSelector()
        let currentAppWindow = TopWindowCaptureCandidate(
            frame: CGRect(x: 0, y: 0, width: 300, height: 300),
            windowID: 10,
            ownerPID: 200
        )

        let selection = selector.selection(
            for: 200,
            target: .topApp,
            candidates: [currentAppWindow]
        )

        XCTAssertNil(selection)
    }
}
