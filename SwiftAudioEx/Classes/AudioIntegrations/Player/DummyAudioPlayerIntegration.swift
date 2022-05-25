//
//  DummyAudioPlayerIntegration.swift
//  KeepTalkingFM
//
//  Created by Marina Gornostaeva on 03/05/2022.
//

import Foundation
import Combine

public final class DummyAudioPlayerIntegration: AudioPlayerIntegration {
    public weak var delegate: AudioPlayerIntegrationDelegate?
    
    public private(set) var playingItem: PlaybackItem?
    
    public private(set) var playingStatus: AudioPlayerPlayingStatus = .paused {
        didSet {
            delegate?.stateDidChange(.state, in: self)
        }
    }
    
    public private(set) var timeStatus: AudioPlayerTimeStatus?
    
    public var isPlaying: Bool {
        playingStatus == .playing
    }

    private var source: PlaybackQueueSource?
    
    private var playingIndex: Int? {
        didSet {
            playingItem = playingIndex.flatMap { source?.items[wrapping: $0] }
            timeStatus = AudioPlayerTimeStatus(duration: 3, position: 0)
            delegate?.stateDidChange(.all, in: self)
        }
    }
    
    private var timer: Timer? {
        didSet {
            oldValue?.invalidate()
        }
    }
    
    private var tickingTimer: Timer? {
        didSet {
            oldValue?.invalidate()
        }
    }

    public var timeUpdateFrequency: Seconds = 0
        
    public init() {
        
    }
    
    public func prepareToPlay(_ queue: PlaybackQueueSource, autoPlay: AutoPlayBehaviour) {
        stopTimer()
        source = queue
        playingIndex = 0
        
        if autoPlay.shouldAutoPlay(wasPlaying: playingStatus == .playing) {
            restartTimer()
        }
    }
    
    public func finishPlaying() {
        playingIndex = nil
        stopTimer()
    }
    
    public func play() {
        playingStatus = .playing
        restartTimer()
    }
    
    public func pause() {
        playingStatus = .paused
        stopTimer()
    }
    
    public func togglePlayPause() {
        if playingStatus == .playing {
            pause()
        } else {
            play()
        }
    }
    
    public func moveToPreviousTrack() {
        playingIndex? -= 1
        restartTimer()
    }
    
    public func moveToNextTrack() {
        playingIndex? += 1
        restartTimer()
    }
    
    public func jumpToItemWithID(_ uuid: UUID) {
        if let indexInQueue = source?.items.firstIndex(where: { $0.metadata.id == uuid }) {
            playingIndex = indexInQueue
            restartTimer()
        }
    }
    
    // MARK: -
    
    private func restartTimer() {
        guard playingStatus == .playing else {
            return
        }
        
        // probably can be done cleverly with Combine but nobody ain't got time for that
        
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false, block: { _ in
            self.moveToNextTrack()
        })
        
        tickingTimer = Timer.scheduledTimer(withTimeInterval: 0.1,  repeats: true, block: { _ in
            if let timeStatus = self.timeStatus {
                self.timeStatus = AudioPlayerTimeStatus(duration: timeStatus.duration, position: timeStatus.position + 0.1)
                self.delegate?.stateDidChange([.timeStatus], in: self)
            }
        })
    }
    
    private func stopTimer() {
        tickingTimer = nil
        timer = nil
    }
}

extension Array {
    subscript(wrapping i: Int) -> Element {
        get { self[i % count] }
        set { self[i % count] = newValue }
    }
}
