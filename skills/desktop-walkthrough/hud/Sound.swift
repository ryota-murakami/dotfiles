// Sound effects of the HUD: the short sounds that answer reading (a block marked as read, a note
// understood, a page cleared, a feedback button). The files are rendered by `dw` from the skill's
// `sounds/synth.py` into the state folder; this file only plays them.
import AppKit
import AVFoundation

/// Folder of the rendered sounds (`<name>.wav`), filled by `dw` before it starts the HUD.
let soundsDir = "\(stateDir)/sounds"

/// Plays the HUD's sound effects by name.
///
/// Why it exists: a mark, an understood note and a cleared page each answer with a sound of their
/// own weight (quiet for what happens often, a fanfare only for a cleared page), and the same sound
/// may be asked for again before it has ended. Each call gets a player of its own, kept until it
/// finishes. Created and owned by {@link HUD}; called from Reading.swift and AskPrompt.swift. The
/// "feedback.sound" and "feedback.volume" settings switch and scale it.
final class SoundPlayer: NSObject, AVAudioPlayerDelegate {
    /// File contents by sound name, read on first use.
    private var files: [String: Data] = [:]
    /// Players still sounding: a player that is released stops.
    private var playing: [AVAudioPlayer] = []

    /// Play a sound.
    ///
    /// @param name - File name without extension (`tick`, `mark-1` … `mark-6`, `unmark`, `note`, `complete`, `next`).
    /// @param gain - Scales this one sound under the user's volume (a focus move is quieter than a mark).
    /// @param delay - Seconds to wait first: the sound of what a mark led to comes after the mark's own.
    func play(_ name: String, gain: Float = 1, after delay: TimeInterval = 0) {
        guard settings.isOn("feedback.sound") else { return }
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.play(name, gain: gain) }
            return
        }
        guard let data = data(for: name), let player = try? AVAudioPlayer(data: data) else { return }
        // The slider is how loud it feels; the player takes an amplitude
        let level = Float(settings.value("feedback.volume"))
        player.volume = level * level * gain
        player.delegate = self
        playing.append(player)
        player.play()
    }

    private func data(for name: String) -> Data? {
        if let known = files[name] { return known }
        // A missing file (the sounds were not rendered: no python3) stays silent, and is looked for again next time
        guard let data = FileManager.default.contents(atPath: "\(soundsDir)/\(name).wav") else { return nil }
        files[name] = data
        return data
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playing.removeAll { $0 === player }
    }
}
