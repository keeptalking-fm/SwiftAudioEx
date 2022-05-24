//
//  AVPlayerWrapper.swift
//  SwiftAudio
//
//  Created by Jørgen Henrichsen on 06/03/2018.
//  Copyright © 2018 Jørgen Henrichsen. All rights reserved.
//

import Foundation
import AVFoundation
import MediaPlayer

public enum PlaybackEndedReason: String {
    case playedUntilEnd
    case playerStopped
    case skippedToNext
    case skippedToPrevious
    case jumpedToIndex
}

protocol AVPlayerWrapperDelegate: AnyObject {
    
    func AVWrapper(didChangeState state: AVPlayerWrapperState)
    func AVWrapper(didChangeEffectiveRate effectiveRate: Double, rate: Double)
    func AVWrapper(secondsElapsed seconds: Double)
    func AVWrapper(failedWithError error: Error?)
    func AVWrapper(seekTo seconds: Int, didFinish: Bool)
    func AVWrapper(didUpdateDuration duration: Double)
    func AVWrapper(didReceiveMetadata metadata: [AVTimedMetadataGroup])
    func AVWrapperItemDidPlayToEndTime()
    func AVWrapperDidRecreateAVPlayer()
}

class AVPlayerWrapper {
    
    struct Constants {
        static let assetPlayableKey = "playable"
    }
    
    // MARK: - Properties
    
    fileprivate var avPlayer = AVPlayer()
    private let playerObserver = AVPlayerObserver()
    internal let playerTimeObserver: AVPlayerTimeObserver
    private let playerItemNotificationObserver = AVPlayerItemNotificationObserver()
    private let playerItemObserver = AVPlayerItemObserver()

    fileprivate var initialTime: TimeInterval?
    fileprivate var pendingAsset: AVAsset? = nil

    /// True when the track was paused for the purpose of switching tracks
    fileprivate var pausedForLoad: Bool = false
    
    init() {
        playerTimeObserver = AVPlayerTimeObserver(periodicObserverTimeInterval: timeEventFrequency.getTime())
        playerTimeObserver.player = avPlayer

        playerObserver.player = avPlayer
        playerObserver.delegate = self
        playerTimeObserver.delegate = self
        playerItemNotificationObserver.delegate = self
        playerItemObserver.delegate = self

        // disabled since we're not making use of video playback
        avPlayer.allowsExternalPlayback = false;
        
        playerTimeObserver.registerForPeriodicTimeEvents()
    }
    
    // MARK: - AVPlayerWrapperProtocol

    fileprivate(set) var state: AVPlayerWrapperState = AVPlayerWrapperState.idle {
        didSet {
            if oldValue != state {
                delegate?.AVWrapper(didChangeState: state)
            }
        }
    }

    /**
     True if the last call to load(from:playWhenReady) had playWhenReady=true.
     */
    fileprivate(set) var playWhenReady: Bool = true
    
    var currentItem: AVPlayerItem? {
        avPlayer.currentItem
    }
    
    var currentTime: TimeInterval {
        let seconds = avPlayer.currentTime().seconds
        return seconds.isNaN ? 0 : seconds
    }
    
    var duration: TimeInterval {
        if let seconds = currentItem?.asset.duration.seconds, !seconds.isNaN {
            return seconds
        }
        else if let seconds = currentItem?.duration.seconds, !seconds.isNaN {
            return seconds
        }
        else if let seconds = currentItem?.seekableTimeRanges.last?.timeRangeValue.duration.seconds,
                !seconds.isNaN {
            return seconds
        }
        return 0.0
    }
    
    var bufferedPosition: TimeInterval {
        currentItem?.loadedTimeRanges.last?.timeRangeValue.end.seconds ?? 0
    }

    var reasonForWaitingToPlay: AVPlayer.WaitingReason? {
        avPlayer.reasonForWaitingToPlay
    }

    /// Desired rate to play at (non-0 if buffering)
    var rate: Float {
        get { avPlayer.rate }
        set { avPlayer.rate = newValue }
    }
    
    /// The actual rate the player plays at
    var realRate: Float {
        avPlayer.currentItem?.timebase.map({ Float($0.rate) }) ?? 0
    }

    weak var delegate: AVPlayerWrapperDelegate? = nil
    
    var bufferDuration: TimeInterval = 0

    var timeEventFrequency: TimeEventFrequency = .everySecond {
        didSet {
            playerTimeObserver.periodicObserverTimeInterval = timeEventFrequency.getTime()
        }
    }
    
    var volume: Float {
        get { avPlayer.volume }
        set { avPlayer.volume = newValue }
    }
    
    var isMuted: Bool {
        get { avPlayer.isMuted }
        set { avPlayer.isMuted = newValue }
    }

    var automaticallyWaitsToMinimizeStalling: Bool {
        get { avPlayer.automaticallyWaitsToMinimizeStalling }
        set { avPlayer.automaticallyWaitsToMinimizeStalling = newValue }
    }
    
    func play() {
        playWhenReady = true
        avPlayer.play()
    }
    
    func pause() {
        playWhenReady = false
        avPlayer.pause()
    }
    
    func togglePlaying() {
        switch avPlayer.timeControlStatus {
        case .playing, .waitingToPlayAtSpecifiedRate:
            pause()
        case .paused:
            play()
        @unknown default:
            fatalError("Unknown AVPlayer.timeControlStatus")
        }
    }
    
    func stop() {
        pause()
        reset(soft: false)
    }
    
    func seek(to seconds: TimeInterval) {
       // if the player is loading then we need to defer seeking until it's ready.
       if (state == AVPlayerWrapperState.loading) {
         initialTime = seconds
       } else {
         avPlayer.seek(to: CMTimeMakeWithSeconds(seconds, preferredTimescale: 1000)) { (finished) in
             if let _ = self.initialTime {
                 self.initialTime = nil
                 if self.playWhenReady {
                     self.play()
                 }
             }
             self.delegate?.AVWrapper(seekTo: Int(seconds), didFinish: finished)
         }
       }
     }
    
    
    
    func load(from url: URL, forceRecreateAVPlayer: Bool, playWhenReady: Bool, initialTime: TimeInterval? = nil, options: [String: Any]? = nil) {
        self.initialTime = initialTime

        pausedForLoad = true
        pause()
        
        reset(soft: true)
        self.playWhenReady = playWhenReady

        if currentItem?.status == .failed || forceRecreateAVPlayer {
            recreateAVPlayer()
        }

        pendingAsset = AVURLAsset(url: url, options: options)
        
        if let pendingAsset = pendingAsset {
            state = .loading
            pendingAsset.loadValuesAsynchronously(forKeys: [Constants.assetPlayableKey], completionHandler: { [weak self] in
                guard let self = self else { return }
                
                var error: NSError? = nil
                let status = pendingAsset.statusOfValue(forKey: Constants.assetPlayableKey, error: &error)
                
                DispatchQueue.main.async {
                    let isPendingAsset = (self.pendingAsset != nil && pendingAsset.isEqual(self.pendingAsset))
                    switch status {
                    case .loaded:
                        if isPendingAsset {
                            let currentItem = AVPlayerItem(asset: pendingAsset, automaticallyLoadedAssetKeys: [Constants.assetPlayableKey])
                            currentItem.preferredForwardBufferDuration = self.bufferDuration
                            self.avPlayer.replaceCurrentItem(with: currentItem)
                            
                            // Register for events
                            self.playerTimeObserver.registerForBoundaryTimeEvents()
                            self.playerObserver.startObserving()
                            self.playerItemNotificationObserver.startObserving()
                            self.playerItemObserver.startObserving(item: currentItem)

                            if pendingAsset.availableChapterLocales.count > 0 {
                                for locale in pendingAsset.availableChapterLocales {
                                    let chapters = pendingAsset.chapterMetadataGroups(withTitleLocale: locale, containingItemsWithCommonKeys: nil)
                                    self.delegate?.AVWrapper(didReceiveMetadata: chapters)
                                }
                            } else {
                                for format in pendingAsset.availableMetadataFormats {
                                    let timeRange = CMTimeRange(start: CMTime(seconds: 0, preferredTimescale: 1000), end: pendingAsset.duration)
                                    let group = AVTimedMetadataGroup(items: pendingAsset.metadata(forFormat: format), timeRange: timeRange)
                                    self.delegate?.AVWrapper(didReceiveMetadata: [group])
                                }
                            }
                        }
                        break
                        
                    case .failed:
                        if isPendingAsset {
                            self.delegate?.AVWrapper(failedWithError: error)
                            self.pendingAsset = nil
                        }
                        break
                        
                    case .cancelled:
                        break
                        
                    default:
                        break
                    }
                }
            })
        }
    }
    
    // MARK: - Util
    
    private func reset(soft: Bool) {
        playerItemObserver.stopObservingCurrentItem()
        playerTimeObserver.unregisterForBoundaryTimeEvents()
        playerItemNotificationObserver.stopObservingCurrentItem()

        pendingAsset?.cancelLoading()
        pendingAsset = nil
        
        if !soft {
            avPlayer.replaceCurrentItem(with: nil)
        }
    }
    
    /// Will recreate the AVPlayer instance. Used when the current one fails.
    private func recreateAVPlayer() {
        let player = AVPlayer()
        playerObserver.player = player
        playerTimeObserver.player = player
        playerTimeObserver.registerForPeriodicTimeEvents()
        avPlayer = player
        delegate?.AVWrapperDidRecreateAVPlayer()
    }
    
}

extension AVPlayerWrapper: AVPlayerObserverDelegate {
    
    // MARK: - AVPlayerObserverDelegate
    
    func player(didChangeTimeControlStatus status: AVPlayer.TimeControlStatus) {
        switch status {
        case .paused:
            if currentItem == nil {
                state = .idle
            }
            else if pausedForLoad != true {
                state = .paused
            }
        case .waitingToPlayAtSpecifiedRate:
            state = .buffering
        case .playing:
            state = .playing
        @unknown default:
            break
        }
    }
    
    func player(statusDidChange status: AVPlayer.Status) {
        switch status {
        case .readyToPlay:
            state = .ready
            pausedForLoad = false
            if playWhenReady && (initialTime ?? 0) == 0 {
                play()
            }
            else if let initialTime = initialTime {
                seek(to: initialTime)
            }
            break
            
        case .failed:
            delegate?.AVWrapper(failedWithError: avPlayer.error)
            break
            
        case .unknown:
            break
        @unknown default:
            break
        }
    }
    
    func player(didChangeRate rate: Float) {
        // don't react to player.rate changing - the corresponding changes are done in observation for timeControlStatus. 
    }
    
    func player(currentItemDidChange item: AVPlayerItem?) {
        
    }
    
    func player(currentItemStatusDidChange status: AVPlayerItem.Status) {
        
    }
    
    func player(currentItemDurationDidChange duration: CMTime?) {
        
    }
    
    func player(currentItemEffectiveRateDidChange effectiveRate: Double, rate: Double) {
    }
}

extension AVPlayerWrapper: AVPlayerTimeObserverDelegate {
    
    // MARK: - AVPlayerTimeObserverDelegate
    
    func audioDidStart() {
        state = .playing
    }
    
    func timeEvent(time: CMTime) {
        delegate?.AVWrapper(secondsElapsed: time.seconds)
    }
    
}

extension AVPlayerWrapper: AVPlayerItemNotificationObserverDelegate {
    
    // MARK: - AVPlayerItemNotificationObserverDelegate
    
    func itemDidPlayToEndTime(_ item: AVPlayerItem) {
        guard item == avPlayer.currentItem else {
            return
        }
        delegate?.AVWrapperItemDidPlayToEndTime()
    }
    
}

extension AVPlayerWrapper: AVPlayerItemObserverDelegate {
    
    // MARK: - AVPlayerItemObserverDelegate
    
    func item(didUpdateDuration duration: Double) {
        delegate?.AVWrapper(didUpdateDuration: duration)
    }
    
    func item(didReceiveMetadata metadata: [AVTimedMetadataGroup]) {
        delegate?.AVWrapper(didReceiveMetadata: metadata)
    }
     
    func item(didUpdateEffectiveRate effectiveRate: Double, rate: Double) {
        delegate?.AVWrapper(didChangeEffectiveRate: effectiveRate, rate: rate)
    }
}
