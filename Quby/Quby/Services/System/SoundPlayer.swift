import AudioToolbox

struct SoundPlayer {

    private let scanSoundID: SystemSoundID = 1057

    func playScanSound() {
        AudioServicesPlaySystemSound(scanSoundID)
    }
}
