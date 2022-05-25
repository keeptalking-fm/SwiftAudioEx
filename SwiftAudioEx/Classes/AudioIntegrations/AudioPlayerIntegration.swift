//
//  AudioIntegration.swift
//  KeepTalkingFM
//
//  Created by Marina Gornostaeva on 03/05/2022.
//

import Foundation

public typealias Seconds = TimeInterval

public protocol AudioPlayerIntegrationDelegate: AnyObject {
    /// Multiple things can change at once.
    func stateDidChange(_ stateChanges: AudioPlayerStateChange, in audioIntegration: AudioPlayerIntegration)
    
    func didFinishPlaying(in audioIntegration: AudioPlayerIntegration)
}

/// Describes the interface of the system audio playback.
/// Can be implemented wrapping a third-party dependency, or our own implementation.
/// Includes handling of the audio session, now playing metadata, and lifecycle of AVPlayer.
public protocol AudioPlayerIntegration: AnyObject {
    
    var delegate: AudioPlayerIntegrationDelegate? { get set }
    
    var playingItem: PlaybackItem? { get }
    var playingStatus: AudioPlayerPlayingStatus { get }
    var timeStatus: AudioPlayerTimeStatus? { get }
    
    /// Always use this property to determine the UI-level state of playback
    var isPlaying: Bool { get }

    var timeUpdateFrequency: Seconds { get }
    
    func prepareToPlay(_ queue: PlaybackQueueSource, autoPlay: AutoPlayBehaviour)
    
    /// Tears down the audio stack
    func finishPlaying()
    
    func play()
    func pause()
    func togglePlayPause()
    func moveToPreviousTrack() throws
    func moveToNextTrack() throws
    func jumpToItemWithID(_ uuid: UUID)
}

// MARK: - Audio player state -

public struct AudioPlayerStateChange: OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let state = AudioPlayerStateChange(rawValue: 1 << 0)
    public static let timeStatus = AudioPlayerStateChange(rawValue: 1 << 2)
    
    public static let all: AudioPlayerStateChange = [.state, .timeStatus]
}

public enum AudioPlayerPlayingStatus: Equatable {
    case pending
    case nothingToPlay
    case paused
    case waitingToPlay
    case playing(rate: Float)
}

public struct AudioPlayerTimeStatus: Equatable {
    
    public let duration: Seconds
    public let position: Seconds
    
    init(duration: Seconds, position: Seconds) {
        self.duration = duration
        self.position = max(0, min(position, duration))
    }
}

// MARK: -

public enum AutoPlayBehaviour {
    case playIfAlreadyPlaying
    case pause
    case play
    
    func shouldAutoPlay(wasPlaying: Bool) -> Bool {
        switch self {
        case .playIfAlreadyPlaying:
            return wasPlaying
        case .pause:
            return false
        case .play:
            return true
        }
    }
}
