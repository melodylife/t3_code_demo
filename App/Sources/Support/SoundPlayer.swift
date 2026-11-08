import AVFAudio
import Foundation

/// Code-generated blips: no audio assets to ship and nothing to license.
/// Any failure leaves the game silent rather than broken.
final class SoundPlayer {
    static let shared = SoundPlayer()

    enum Clip: String {
        case match
        case special
        case error
        case win
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private var buffers: [Clip: AVAudioPCMBuffer] = [:]
    private var isReady = false
    private var didAttemptStart = false

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.4
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true
    }

    func play(_ clip: Clip) {
        guard isEnabled else { return }
        startIfNeeded()
        guard isReady else { return }
        guard let buffer = buffer(for: clip) else { return }
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func startIfNeeded() {
        guard !didAttemptStart else { return }
        didAttemptStart = true
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            player.play()
            isReady = true
        } catch {
            isReady = false
        }
    }

    private func buffer(for clip: Clip) -> AVAudioPCMBuffer? {
        if let cached = buffers[clip] { return cached }
        let tones: [(Double, Double)]
        let duration: Double
        switch clip {
        case .match:
            duration = 0.10
            tones = [(880, 0.45), (1320, 0.18)]
        case .special:
            duration = 0.24
            tones = [(660, 0.35), (990, 0.25), (1480, 0.15)]
        case .error:
            duration = 0.18
            tones = [(190, 0.45), (130, 0.30)]
        case .win:
            duration = 0.55
            tones = [(523, 0.30), (659, 0.26), (784, 0.24), (1046, 0.18)]
        }
        guard let generated = makeBuffer(duration: duration, tones: tones) else { return nil }
        buffers[clip] = generated
        return generated
    }

    private func makeBuffer(duration: Double, tones: [(frequency: Double, amplitude: Double)]) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frameCount
        let sampleRate = format.sampleRate

        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let progress = time / duration
            let envelope = (1 - progress) * (1 - progress)
            var sample = 0.0
            for tone in tones {
                sample += sin(2 * Double.pi * tone.frequency * time) * tone.amplitude
            }
            channel[frame] = Float(sample * envelope)
        }
        return buffer
    }
}
