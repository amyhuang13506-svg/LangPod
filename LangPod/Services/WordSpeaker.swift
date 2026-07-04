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

    /// 按国家口音发音（词汇小课堂：英国课堂用英音、澳洲课堂用澳音）。
    /// accent 为 BCP-47 代码（en-US / en-GB / en-AU / en-SG），取不到该口音时回落 en-US。
    func speak(_ word: String, accent: String) {
        speakText(word, rate: 0.45, usePhoneticsMap: true, accent: accent)
    }

    /// 连词成句词块专用：动态挑选系统最高音质嗓音（premium > enhanced > default），
    /// 比默认 compact 自然。仅此方法启用高音质分支，不影响其它模块的发音。
    func speakToken(_ word: String) {
        speakText(word, rate: 0.45, usePhoneticsMap: true, preferHighQuality: true)
    }

    /// 缓存各语言的最高音质嗓音（枚举 speechVoices 一次）
    private var cachedBestVoice: [String: AVSpeechSynthesisVoice] = [:]

    private func bestQualityVoice(_ language: String) -> AVSpeechSynthesisVoice? {
        if let v = cachedBestVoice[language] { return v }
        func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int {
            switch q {
            case .premium: return 3
            case .enhanced: return 2
            default: return 1
            }
        }
        let best = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .max { rank($0.quality) < rank($1.quality) }
        if let best { cachedBestVoice[language] = best }
        return best
    }

    func speakSentence(_ sentence: String, accent: String) {
        speakText(sentence, rate: 0.48, usePhoneticsMap: false, accent: accent)
    }

    private func speakText(_ text: String, rate: Float, usePhoneticsMap: Bool = true, accent: String? = nil, preferHighQuality: Bool = false) {
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

        if preferHighQuality, let best = bestQualityVoice(accent ?? "en-US") {
            // 连词成句词块：系统最高音质嗓音（若设备装了 enhanced/premium 则用）
            utterance.voice = best
        } else if let accent, accent != "en-US", let voice = AVSpeechSynthesisVoice(language: accent) {
            utterance.voice = voice
        } else if let enhanced = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Samantha")
            ?? AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.Samantha-premium") {
            // Use a high-quality en-US voice if available
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
