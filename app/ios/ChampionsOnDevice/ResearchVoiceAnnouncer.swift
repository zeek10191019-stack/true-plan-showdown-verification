import Foundation
import AVFoundation

// R27.400: Frontmost, button-initiated device-local TTS demonstration only.
// The only phrase that this class can speak is the hard-coded, non-action test phrase.
// Background playback, game audio coexistence and real device behavior are UNVERIFIED.
@available(iOS 27.0, *)
final class ResearchVoiceAnnouncer {
    private let synth = AVSpeechSynthesizer() // Keep strongly retained until completion.

    func speakApprovedManualTest() throws {
        precondition(Thread.isMainThread)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
        try session.setActive(true)
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: ResearchVoiceGate.approvedPhrase)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.51
        synth.speak(utterance)
    }

    func stopImmediately() {
        precondition(Thread.isMainThread)
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
