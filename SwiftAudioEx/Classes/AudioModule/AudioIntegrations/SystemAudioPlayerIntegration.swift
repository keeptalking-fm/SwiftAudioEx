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
// - handle errors on next() and previous()

// Known issues:
// - QueuedAudioPlayer manually manages the queue, not with AVQueuePlayer. There's no pre-loading and there's a 0,5s gap between files even on good network.

public final class SystemAudioPlayerIntegration {
    
    public weak var delegate: AudioPlayerIntegrationDelegate?
    
    private(set) var source: PlaybackQueueSource?
    
    private let player: QueuedAudioPlayer
    private let audioSession: AudioSessionManager
    private let nowPlayingInfo: NowPlayingInfoController
    private let appLifecycle: AppLifecycleObserver
    
    private let updateFrequency = CMTime(value: 1, timescale: 10) // 1/10s
    
    private var shouldBePlaying = false
    
    public init() {
        self.player = QueuedAudioPlayer()
        self.audioSession = AudioSessionManager()
        self.nowPlayingInfo = NowPlayingInfoController()
        self.appLifecycle = AppLifecycleObserver()
        
        player.timeEventFrequency = .custom(time: updateFrequency)
        
        setupRemoteCommands()
                
        player.event.stateChange.addListener(self, handleAudioPlayerStateChange)
        player.event.queueIndex.addListener(self, handleQueueIndexChange)
        player.event.secondElapse.addListener(self, handleSecondElapse)
        player.event.updateDuration.addListener(self, handleDurationChange)
        player.event.updateRealRate.addListener(self, handleRateChange)
        
        audioSession.delegate = self
        appLifecycle.delegate = self
        
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            print("alive")
        }
    }
    
    private func setupRemoteCommands() {
        player.remoteCommands = [
            .pause,
            .play,
            .togglePlayPause,
            .previous,
            .next
            ]
        
        player.remoteCommandController.handlePlayCommand = { [weak self] _ in
            print("REMOTE PLAY")
            guard let self = self, self.playingItem != nil else { return .noActionableNowPlayingItem }
            self.play()
            return .success
        }

        player.remoteCommandController.handlePauseCommand = { [weak self] _ in
            print("REMOTE PAUSE")
            guard let self = self, self.playingItem != nil else { return .noActionableNowPlayingItem }
            self.pause()
            return .success
        }
        
        player.remoteCommandController.handleTogglePlayPauseCommand = { [weak self] _ in
            print("REMOTE TOGGLE")
            guard let self = self, self.playingItem != nil else { return .noActionableNowPlayingItem }
            self.togglePlayPause()
            return .success
        }
    }
    
    private func activateAudioSessionForPlaying() {
        do {
            try audioSession.activateForPlayingAndRecording()
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
    
    private func handleAudioPlayerStateChange(state: AudioPlayerState) {
        print("⏯ stateChange ->", state, player.currentTime, "/", player.duration)
        checkBackgroundTasksOnStateChange()
        updateNowPlayingPlaybackMetadata()
        delegate?.stateDidChange(.all.subtracting(.playingItem), in: self)
    }
    
    private func handleQueueIndexChange(data: AudioPlayer.QueueIndexEventData) {
        print("⏯ queueIndex ->", data, player.currentTime, "/", player.duration, "state", player.playerState)
        updateStaticNowPlayingMetadata()
        updateNowPlayingPlaybackMetadata()
        delegate?.stateDidChange(.all, in: self)
    }
    
    private func handleSecondElapse(data: AudioPlayer.SecondElapseEventData) {
        print("⏯ secondElapse ->", player.currentTime, "/", player.duration)
        delegate?.stateDidChange([.timeStatus], in: self)
    }
    
    private func handleDurationChange(data: AudioPlayer.UpdateDurationEventData) {
        print("⏯ updateDuration ->", player.currentTime, "/", player.duration)
        updateNowPlayingPlaybackMetadata()
        delegate?.stateDidChange([.timeStatus], in: self)
    }
    
    func handleRateChange(data: AudioPlayer.UpdateRateEventData) {
        // Don't think we need to react here, because rate changes are accompanied by changes in player.playerState (buffering, playing, paused).
        // if we were to update Now Playing info here, would need to filter on data.rate
        // because data.effectiveRate changes very often, as it is extremely precise.
        print("✅ rate \(data.rate) | effective rate: \(data.effectiveRate)")
    }
    
    private func checkBackgroundTasksOnStateChange() {
        // If the player is buffering (waitingToPlay), background execution is not automatically provided.
        // A background task gives time for some media to buffer and for playback to actually start.
        switch player.playerState {
        case .loading, .ready, .buffering:
            appLifecycle.startNewBackgroundTask()
        case .playing, .paused:
            appLifecycle.finishAllBackgroundTasks()
        case .idle:
            break
        }
    }
    
    private func updateNowPlayingPlaybackMetadata() {
        let metadata = NowPlayableDynamicMetadata(rate: player.realRate,
                                                  position: Float(timeStatus?.position ?? 0),
                                                  duration: Float(timeStatus?.duration ?? 0))
        
        nowPlayingInfo.updateNowPlayingPlaybackInfo(metadata)
    }
    
    private func updateStaticNowPlayingMetadata() {
        guard let playingItem = player.currentItem as? PlaybackItem else { return }
        
        let metadata = NowPlayableStaticMetadata(assetURL: playingItem.audioURL,
                                                 mediaType: .audio, // podcast?
                                                 title: playingItem.getTitle() ?? "KeepTalkingFM",
                                                 artist: playingItem.getArtist() ?? "",
                                                 artwork: nil,
                                                 albumArtist: playingItem.getArtist(),
                                                 albumTitle: playingItem.getAlbumTitle())
        
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
        return player.currentItem as? PlaybackItem
    }
    
    public var playingStatus: AudioPlayerPlayingStatus {
        switch player.playerState {
            
        case .loading:
            return .pending
        case .ready:
            return .paused
        case .buffering:
            return .waitingToPlay
        case .paused:
            return .paused
        case .playing:
            return .playing
        case .idle:
            return .nothingToPlay
        }
    }
    
    public var isPlaying: Bool {
        switch player.playerState {
        case .loading, .ready, .buffering:
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
        case .idle:
            return false
        }
    }
    
    public var timeStatus: AudioPlayerTimeStatus? {
        switch player.playerState {
        case .loading:
            return nil
        case .ready, .buffering, .paused, .playing:
            return AudioPlayerTimeStatus(duration: player.duration, position: player.currentTime)
        case .idle:
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
        try? player.add(items: audioItems, forceRecreateAVPlayer: forceRecreateAVPlayer, playWhenReady: playWhenReady) // throws only on invalid urls, so it's ok not to handle errors
    }
    
    public func finishPlaying() {
        print("FINISH PLAYING")

        shouldBePlaying = false
        player.stop()
        deactivateAudioSession()
    }
    
    public func play() {
        print("PLAY")

        shouldBePlaying = true
        activateAudioSessionForPlaying()
        player.play()
    }
        
    public func pause() {
        print("PAUSE")

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
    
    public func moveToPreviousTrack() {
        try? player.previous()
    }
    
    public func moveToNextTrack() {
        try? player.next()
    }
    
    public func jumpToItemWithID(_ uuid: UUID) {
        guard let matchingItem = player.items
                .compactMap({ $0 as? PlaybackItem })
                .enumerated()
                .first(where: { $0.element.metadata.id == uuid })
        else {
            print("Can't jump to item \(uuid) - not in player queue")
            return
        }
        let playWhenReady = AutoPlayBehaviour.playIfAlreadyPlaying.shouldAutoPlay(wasPlaying: isPlaying)
        try? player.jumpToItem(atIndex: matchingItem.offset, playWhenReady: playWhenReady)
    }
}

// MARK: - PlaybackAudioItem -


extension PlaybackItem: AudioItem {
    public func getSourceUrl() -> String {
        audioURL.absoluteString
    }
    
    public func getSourceType() -> SourceType {
        .stream
    }
    
    // These metadata services below are not used.
    // For now they are required for protocol conformance.
    // This requirement will be removed soon when we clean up SwiftAudioEx from unused stuff.
    
    public func getArtist() -> String? {
        nil
    }
    
    public func getTitle() -> String? {
        metadata.authorName
    }
    
    public func getAlbumTitle() -> String? {
        metadata.albumTitle
    }
    
    public func getArtwork(_ handler: @escaping (UIImage?) -> Void) {
        handler(nil)
    }
}

