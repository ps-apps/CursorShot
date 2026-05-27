import AppKit
import Foundation

@MainActor
final class FeedbackSoundPlayer {
    private lazy var captureSound = sound(
        at: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif"
    ) ?? NSSound(named: NSSound.Name("Grab"))

    func playCapture() {
        play(captureSound)
    }

    private func sound(at path: String) -> NSSound? {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        return NSSound(contentsOf: url, byReference: true)
    }

    private func play(_ sound: NSSound?) {
        guard let sound else {
            return
        }

        sound.stop()
        sound.currentTime = 0
        sound.play()
    }
}
