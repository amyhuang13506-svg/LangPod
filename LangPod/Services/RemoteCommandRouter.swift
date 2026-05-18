import Foundation
import MediaPlayer

/// Anything that can respond to lock-screen / control-center remote commands.
/// Both `AudioPlayer` (Castlingo 学习集) and `RawAudioController` (硅谷原声) conform.
protocol RemoteControllable: AnyObject {
    func remoteTogglePlay()
    func remoteSkipForward()
    func remoteSkipBackward()
    func remoteNextTrack()
    func remotePreviousTrack()
    func remoteSeek(to seconds: Double)
}

extension RemoteControllable {
    func remoteNextTrack() {}
    func remotePreviousTrack() {}
}

/// Single global owner of MPRemoteCommandCenter handlers. Registers once at app
/// launch and forwards every command to whoever is currently `active`.
///
/// Why this exists: previously both `AudioPlayer` and `RawAudioController`
/// called `removeTarget(nil)` to clear handlers before adding their own.
/// That nuked each other's targets — once a user opened a raw podcast and
/// closed it, the lock-screen controls were dead app-wide until next launch.
/// The router solves the conflict: handlers stay registered for the whole
/// process lifetime, and the active player just sets `self` as `active`.
final class RemoteCommandRouter {
    static let shared = RemoteCommandRouter()

    /// Whoever is currently driving the lock screen. Weak so we don't keep a
    /// torn-down controller alive past its useful life.
    weak var active: RemoteControllable?

    private var didSetup = false

    func setup() {
        guard !didSetup else { return }
        didSetup = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let target = self?.active else { return .commandFailed }
            target.remoteTogglePlay()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let target = self?.active else { return .commandFailed }
            target.remoteTogglePlay()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let target = self?.active else { return .commandFailed }
            target.remoteTogglePlay()
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let target = self?.active else { return .commandFailed }
            target.remoteSkipForward()
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let target = self?.active else { return .commandFailed }
            target.remoteSkipBackward()
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            guard let target = self?.active else { return .commandFailed }
            target.remoteNextTrack()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            guard let target = self?.active else { return .commandFailed }
            target.remotePreviousTrack()
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let target = self?.active,
                  let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            target.remoteSeek(to: e.positionTime)
            return .success
        }
    }
}
