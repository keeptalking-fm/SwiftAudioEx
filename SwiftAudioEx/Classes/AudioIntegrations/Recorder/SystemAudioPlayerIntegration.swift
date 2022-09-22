//
//  SystemAudioPlayerIntegration.swift
//  KeepTalkingFM
//
//  Created by Marina Gornostaeva on 05/05/2022.
//

import Foundation
import UIKit
import AVFoundation

// TODO:
// - handle loading of artwork
// - support starting from a specific comment, also after media services reset
// - test player failing

// Known issues:
// - QueuedAudioPlayer manually manages the queue, not with AVQueuePlayer. There's no pre-loading and there's a 0,5s gap between files even on good network.

public final class SystemAudioPlayerIntegration {
    
    public weak var delegate: AudioPlayerIntegrationDelegate?
    
    private(set) var source: PlaybackQueueSource? {
        didSet {
            print("XXX: SOURCE CHANGE")
            if let source {
                for item in source.items {
                    print("\(item.metadata.authorName) \(item.id == item.metadata.id ? "-" : "*") \(item.id)")
                }
            }
        }
    }
    
    private let player: AVQueuePlayerWrapper
    
    private let audioSession: AudioSessionManager
    private let nowPlayingInfo: NowPlayingInfoController
    private let appLifecycle: AppLifecycleObserver
    private let remoteCommandController: RemoteCommandController

    private let updateFrequency = CMTime(value: 1, timescale: 10) // 1/10s
    
    private var shouldBePlaying = false
    
    public init() {
        self.player = AVQueuePlayerWrapper()
        self.audioSession = AudioSessionManager()
        self.nowPlayingInfo = NowPlayingInfoController()
        self.appLifecycle = AppLifecycleObserver()
        self.remoteCommandController = RemoteCommandController()
        
        player.timeEventFrequency = .custom(time: updateFrequency)
        
        setupRemoteCommands()
                
        // Uncomment in case of switching back to QueuedAudioPlayer
//        player.event.stateChange.addListener(self, handleAudioPlayerStateChange)
//        player.event.queueIndex.addListener(self, handleQueueIndexChange)
//        player.event.secondElapse.addListener(self, handleSecondElapse)
//        player.event.updateDuration.addListener(self, handleDurationChange)
//        player.event.updateRealRate.addListener(self, handleRateChange)
        
        player.delegate = self
        
        audioSession.delegate = self
        appLifecycle.delegate = self
        
//        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
//            print("alive")
//        }
    }
    
    private func setupRemoteCommands() {
        remoteCommandController.audio = self
        remoteCommandController.enable(commands: [
            .pause,
            .play,
            .togglePlayPause,
            .previous,
            .next
        ])
    }
    
    private func activateAudioSessionForPlaying() {
        do {
            try audioSession.activateForPlaying()
        } catch {
            print("Error activating audio session: \(error)")
        }
    }
    
    private func deactivateAudioSession() {
        do {
            try audioSession.deactivate()
        } catch {
            print("Error deactivating audio session: \(error)")
        }
    }
    
    // MARK: -
    
    private func handleAudioPlayerStateChange() {
//        print("⏯ stateChange ->", player.state, player.elapsed, "/", player.state.duration)
        checkBackgroundTasksOnStateChange()
        updateStaticNowPlayingMetadata()
        updateNowPlayingPlaybackMetadata(onlyIfRateChanged: false)
        delegate?.stateDidChange(.all, in: self)
    }
    
    private func handleSecondElapse() {
//        print("⏯ secondElapse ->", player.elapsed, "/", player.state.duration)
        delegate?.stateDidChange([.timeStatus], in: self)
    }
    
    func handleRateChange() {
        // Mostly we don't need to react here, because rate changes are accompanied by changes in player.playerState (buffering, playing, paused).
        print("✅ rate \(player.state)")
        
        if case .playing = player.state.playerState {
            updateNowPlayingPlaybackMetadata(onlyIfRateChanged: true)
        }
    }
    
    private func checkBackgroundTasksOnStateChange() {
        // If the player is buffering (waitingToPlay), background execution is not automatically provided.
        // A background task gives time for some media to buffer and for playback to actually start.
        switch player.state.playerState {
        case .pending, .waitingToPlay:
            appLifecycle.startNewBackgroundTask()
        case .playing, .paused:
            appLifecycle.finishAllBackgroundTasks()
        case .nothingToPlay:
            break
        }
    }
    
    private func updateNowPlayingPlaybackMetadata(onlyIfRateChanged: Bool) {
        let metadata = NowPlayableDynamicMetadata(rate: player.state.playerState.rate,
                                                  position: Float(timeStatus?.position ?? 0),
                                                  duration: Float(timeStatus?.duration ?? 0))
        
        nowPlayingInfo.updateNowPlayingPlaybackInfo(metadata, onlyIfRateChanged: onlyIfRateChanged)
    }
    
    private func updateStaticNowPlayingMetadata() {
        guard let playingItem = player.state.currentAudioItem as? PlaybackItem else { return }
        
        let metadata = NowPlayableStaticMetadata(assetURL: playingItem.audioURL,
                                                 mediaType: .audio, // podcast?
                                                 title: playingItem.metadata.authorName,
                                                 artist: nil,
                                                 artwork: nil,
                                                 albumArtist: nil,
                                                 albumTitle: playingItem.metadata.albumTitle)
        
        nowPlayingInfo.updateNowPlayingMetadata(metadata)
    }
}

// MARK: - AudioSessionManagerDelegate -

extension SystemAudioPlayerIntegration: AudioSessionManagerDelegate {
    
    func audioSessionManager(_ audioSessionManager: AudioSessionManager, didReceiveInterruption type: AudioSessionManager.Interruption) {
        print("Interruption", type)
        
        // https://developer.apple.com/documentation/avfaudio/avaudiosession/responding_to_audio_session_interruptions
        switch type {
        case .began:
            // AVPlayer is already paused at this point
            break
        case .ended(let shouldResume):
            // .ended is not always called after .began
            if shouldBePlaying {
                if shouldResume {
                    play()
                } else {
                    pause()
                }
            }
        }
    }
    
    func audioSessionManagerDidResetMediaServices(_ audioSessionManager: AudioSessionManager) {
        // All audio-related objects have to be recreated after media services were reset
        // https://developer.apple.com/documentation/avfaudio/avaudiosession/1616540-mediaserviceswereresetnotificati

        print("Recreating the stack....")
        if let source = source {
            self.prepareToPlay(source, forceRecreateAVPlayer: true, autoPlay: .pause)
            // TODO: also move to the comment that was playing last
        }
    }
}

// MARK: - AppLifecycleObserverDelegate -

extension SystemAudioPlayerIntegration: AppLifecycleObserverDelegate {
    func applicationWillEnterForeground(_ observer: AppLifecycleObserver) {
        print("applicationWillEnterForeground")
    }
    
    func applicationDidBecomeActive(_ observer: AppLifecycleObserver) {
        print("applicationDidBecomeActive")
    }
    
    func applicationWillResignActive(_ observer: AppLifecycleObserver) {
        print("applicationWillResignActive")
    }
    
    func applicationWillTerminate(_ observer: AppLifecycleObserver) {
        print("applicationWillTerminate")
    }
    
    
    func applicationDidEnterBackground(_ observer: AppLifecycleObserver) {
        
        // per Apple's documentation, it's advised to deactivate the session upon going to the background, if we're not currently playing.
        // https://developer.apple.com/library/content/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/AudioGuidelinesByAppType/AudioGuidelinesByAppType.html#//apple_ref/doc/uid/TP40007875-CH11-SW1
        // If we don't do this, we'll get interruption began/ended upon return to foreground with "wasSupsended = true", because suspension is treated as interruption.
        if !shouldBePlaying {
            deactivateAudioSession()
        }
    }
}

// MARK: - AudioPlayerIntegration -

extension SystemAudioPlayerIntegration: AudioPlayerIntegration {
    
    public var playingItem: PlaybackItem? {
        return player.state.currentAudioItem as? PlaybackItem
    }
    
    public var playingStatus: AudioPlayerPlayingStatus {
        player.state.playerState
    }
    
    public var isPlaying: Bool {
        switch player.state.playerState {
        case .pending, .waitingToPlay:
            return shouldBePlaying
        case .paused:
            // during interruptions the player gets paused automatically
            // and we have shouldBePlaying=true
            // still, the player is paused - the user can see controls on the control center while in interruption
            // so matching that here so it's consistent across the app UI and system UI.
            // The same applies during .loading, but it's nicer that it doesn't flicker to paused/playing again in the UI, even though it does that on the control center.
            // This flickering of state might be gone when AVQueuePlayer is implemented, because there won't be a delay between items.
            return false
        case .playing:
            return true
        case .nothingToPlay:
            return false
        }
    }
    
    public var timeStatus: AudioPlayerTimeStatus? {
        switch player.state.playerState {
            case .pending:
                return nil
            case .waitingToPlay, .paused, .playing:
                return AudioPlayerTimeStatus(duration: player.state.duration, position: player.elapsed)
            case .nothingToPlay:
                return nil
        }
    }
    
    public var timeUpdateFrequency: Seconds {
        updateFrequency.seconds
    }
    
    public func prepareToPlay(_ queue: PlaybackQueueSource, autoPlay: AutoPlayBehaviour) {
        prepareToPlay(queue, forceRecreateAVPlayer: false, autoPlay: autoPlay)
    }
    
    private func prepareToPlay(_ queue: PlaybackQueueSource, forceRecreateAVPlayer: Bool, autoPlay: AutoPlayBehaviour) {
        let wasPlaying = isPlaying
        
        let audioItems = queue.items
        
        player.stop()
        
        source = queue
        
        let playWhenReady = autoPlay.shouldAutoPlay(wasPlaying: wasPlaying)
        if playWhenReady {
            activateAudioSessionForPlaying()
        }
        player.load(audioItems, playWhenReady: playWhenReady, forceRecreateAVPlayer: forceRecreateAVPlayer)
//        try? player.add(items: audioItems, forceRecreateAVPlayer: forceRecreateAVPlayer, playWhenReady: playWhenReady) // throws only on invalid urls, so it's ok not to handle errors
    }
    
    public func finishPlaying() {
        print("System audio: FINISH PLAYING")

        shouldBePlaying = false
        player.stop()
        deactivateAudioSession()
    }
    
    public func play() {
        print("System audio: PLAY")

        shouldBePlaying = true
        activateAudioSessionForPlaying()
        player.play()
    }
        
    public func pause() {
        print("System audio: PAUSE")

        shouldBePlaying = false
        player.pause()
    }
    
    public func togglePlayPause() {
        if shouldBePlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func moveToPreviousTrack() throws {
        player.previous()
    }
    
    public func moveToNextTrack() throws {
        player.next()
    }
    
    public func jumpToItemWithID(_ uuid: UUID) {
        let playWhenReady = AutoPlayBehaviour.playIfAlreadyPlaying.shouldAutoPlay(wasPlaying: isPlaying)
        player.jumpToItem(id: uuid, playWhenReady: playWhenReady)
    }
}

// MARK: - PlaybackAudioItem -


extension PlaybackItem: AudioItem {
    public var sourceURL: URL {
        audioURL
    }
    
    public var id: UUID {
        metadata.id
    }
}


extension SystemAudioPlayerIntegration: AVQueuePlayerWrapperDelegate {
    
    func elapsedDidChange(in wrapper: AVQueuePlayerWrapper) {
        handleSecondElapse()
    }
    
    func newStateDidChange(in wrapper: AVQueuePlayerWrapper) {
        handleAudioPlayerStateChange()
    }
    
    func queueFinished(in wrapper: AVQueuePlayerWrapper) {
        delegate?.didFinishPlaying(in: self)
    }
}
