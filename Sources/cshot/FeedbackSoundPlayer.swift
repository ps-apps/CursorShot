import AppKit
import Foundation

@MainActor
final class FeedbackSoundPlayer {
    private lazy var captureSound = sound(
        at: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Grab.aif"
    ) ?? NSSound(named: NSSound.Name("Grab"))
    private lazy var handoffSound = NSSound(named: NSSound.Name("Pop")) ?? NSSound(named: NSSound.Name("Tink"))
    private lazy var pasteSound = NSSound(named: NSSound.Name("Tink")) ?? NSSound(named: NSSound.Name("Ping"))

    func playCapture() {
        play(captureSound)
    }

    func playHandoff() {
        play(handoffSound)
    }

    func playPaste() {
        play(pasteSound)
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
            NSSound.beep()
            return
        }

        sound.stop()
        sound.currentTime = 0
        sound.play()
    }
}
