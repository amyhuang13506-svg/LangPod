import AVFoundation

class WordSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = WordSpeaker()
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ word: String) {
        // Ensure audio session allows speech
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: word)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.4
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Restore normal audio session
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {}
    }
}
