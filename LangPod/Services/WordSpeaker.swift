import AVFoundation

class WordSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = WordSpeaker()
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak a single word
    func speak(_ word: String) {
        speakText(word, rate: 0.45, usePhoneticsMap: true)
    }

    /// Speak a full sentence (clear, slightly slower than normal)
    func speakSentence(_ sentence: String) {
        speakText(sentence, rate: 0.48, usePhoneticsMap: false)
    }

    private func speakText(_ text: String, rate: Float, usePhoneticsMap: Bool = true) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {}

        synthesizer.stopSpeaking(at: .immediate)

        // Short function words get mispronounced in isolation by TTS:
        // "a" reads as /eɪ/ instead of /ə/, "I" as letter name, etc.
        // Fix: use IPA phonetic hint via AVSpeechUtterance
        // For single words in isolation, TTS mispronounces short function words
        // and reads single uppercase letters as "capital X".
        // Fix: map to phonetic spelling that TTS reads naturally.
        var spokenText = text
        if usePhoneticsMap {
            let lower = text.lowercased()
            let phonetics: [String: String] = [
                "a": "uh",
                "an": "uhn",
                "the": "thuh",
                "i": "eye",
                "to": "too",
                "of": "ov",
                "or": "ore",
            ]
            if let mapped = phonetics[lower] {
                spokenText = mapped
            } else if text.count == 1 && text.first?.isLetter == true {
                // Single letter like "C", "B" — just lowercase it so TTS
                // doesn't say "capital C", reads the letter sound naturally
                spokenText = lower
            }
        }

        let utterance = AVSpeechUtterance(string: spokenText)

        // Use a high-quality en-US voice if available
        if let enhanced = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Samantha")
            ?? AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.Samantha-premium") {
            utterance.voice = enhanced
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        utterance.rate = rate
        utterance.pitchMultiplier = 1.05  // slightly higher pitch sounds more natural
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0

        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {}
    }
}
