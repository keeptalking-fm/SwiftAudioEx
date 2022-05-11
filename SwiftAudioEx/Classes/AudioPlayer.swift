//
//  AudioPlayer.swift
//  SwiftAudio
//
//  Created by Jørgen Henrichsen on 15/03/2018.
//

import Foundation
import MediaPlayer

public typealias AudioPlayerState = AVPlayerWrapperState

public class AudioPlayer: AVPlayerWrapperDelegate {

    /// The wrapper around the underlying AVPlayer
    let wrapper: AVPlayerWrapperProtocol = AVPlayerWrapper()
    
    public let nowPlayingInfoController: NowPlayingInfoControllerProtocol
    public let remoteCommandController: RemoteCommandController
    public let event = EventHolder()
    
    private(set) var currentItem: AudioItem?
    
    /**
     Set this to false to disable automatic updating of now playing info for control center and lock screen.
     */
    public var automaticallyUpdateNowPlayingInfo: Bool = true
    
    /**
     Controls the time pitch algorithm applied to each item loaded into the player.
     If the loaded `AudioItem` conforms to `TimePitcher`-protocol this will be overriden.
     */
    public var audioTimePitchAlgorithm: AVAudioTimePitchAlgorithm = AVAudioTimePitchAlgorithm.timeDomain
    
    /**
     Default remote commands to use for each playing item
     */
    public var remoteCommands: [RemoteCommand] = [] {
        didSet {
            if let item = currentItem {
                self.enableRemoteCommands(forItem: item)
            }
        }
    }
    
    
    // MARK: - Getters from AVPlayerWrapper

    internal var willPlayWhenReady: Bool {
        wrapper.playWhenReady
    }
    
    /**
     The elapsed playback time of the current item.
     */
    public var currentTime: Double {
        wrapper.currentTime
    }
    
    /**
     The duration of the current AudioItem.
     */
    public var duration: Double {
        wrapper.duration
    }
    
    /**
     The bufferedPosition of the current AudioItem.
     */
    public var bufferedPosition: Double {
        wrapper.bufferedPosition
    }
    
    /**
     The current state of the underlying `AudioPlayer`.
     */
    public var playerState: AudioPlayerState {
        wrapper.state
    }
    
    // MARK: - Setters for AVPlayerWrapper
    
    /**
     The amount of seconds to be buffered by the player. Default value is 0 seconds, this means the AVPlayer will choose an appropriate level of buffering.
     
     [Read more from Apple Documentation](https://developer.apple.com/documentation/avfoundation/avplayeritem/1643630-preferredforwardbufferduration)
     
     - Important: This setting will have no effect if `automaticallyWaitsToMinimizeStalling` is set to `true` in the AVPlayer
     */
    public var bufferDuration: TimeInterval {
        get { wrapper.bufferDuration }
        set { wrapper.bufferDuration = newValue }
    }
    
    /**
     Set this to decide how often the player should call the delegate with time progress events.
     */
    public var timeEventFrequency: TimeEventFrequency {
        get { wrapper.timeEventFrequency }
        set { wrapper.timeEventFrequency = newValue }
    }
    
    /**
     Indicates whether the player should automatically delay playback in order to minimize stalling
     */
    public var automaticallyWaitsToMinimizeStalling: Bool {
        get { wrapper.automaticallyWaitsToMinimizeStalling }
        set { wrapper.automaticallyWaitsToMinimizeStalling = newValue }
    }
    
    public var volume: Float {
        get { wrapper.volume }
        set { wrapper.volume = newValue }
    }
    
    public var isMuted: Bool {
        get { wrapper.isMuted }
        set { wrapper.isMuted = newValue }
    }

    private var _rate: Float = 1.0
    public var rate: Float {
        get { _rate }
        set {
            _rate = newValue

            // Only set the rate on the wrapper if it is already playing.
            if wrapper.rate > 0 {
                wrapper.rate = newValue
            }
        }
    }
    
    /// The real rate the player is at (0.0 when buffering)
    public var realRate: Float {
        wrapper.realRate
    }
    
    // MARK: - Init
    
    /**
     Create a new AudioPlayer.
     
     - parameter infoCenter: The InfoCenter to update. Default is `MPNowPlayingInfoCenter.default()`.
     */
    public init(nowPlayingInfoController: NowPlayingInfoControllerProtocol = NowPlayingInfoController(),
                remoteCommandController: RemoteCommandController = RemoteCommandController()) {
        self.nowPlayingInfoController = nowPlayingInfoController
        self.remoteCommandController = remoteCommandController
        
        wrapper.delegate = self
        self.remoteCommandController.audioPlayer = self
    }
    
    // MARK: - Player Actions
    
    /**
     Load an AudioItem into the manager.
     
     - parameter item: The AudioItem to load. The info given in this item is the one used for the InfoCenter.
     - parameter playWhenReady: Immediately start playback when the item is ready. Default is `true`. If you disable this you have to call play() or togglePlay() when the `state` switches to `ready`.
     */
    public func load(item: AudioItem, playWhenReady: Bool = true) throws {
        let url: URL
        switch item.getSourceType() {
        case .stream:
            if let itemUrl = URL(string: item.getSourceUrl()) {
                url = itemUrl
            }
            else {
                throw APError.LoadError.invalidSourceUrl(item.getSourceUrl())
            }
        case .file:
            url = URL(fileURLWithPath: item.getSourceUrl())
        }
        
        wrapper.load(from: url,
                     playWhenReady: playWhenReady,
                     initialTime: (item as? InitialTiming)?.getInitialTime(),
                     options:(item as? AssetOptionsProviding)?.getAssetOptions())
        
        currentItem = item
        
        if (automaticallyUpdateNowPlayingInfo) {
            loadNowPlayingMetaValues()
        }
        enableRemoteCommands(forItem: item)
    }
    
    /**
     Toggle playback status.
     */
    public func togglePlaying() {
        wrapper.togglePlaying()
    }
    
    /**
     Start playback
     */
    public func play() {
        wrapper.play()
    }
    
    /**
     Pause playback
     */
    public func pause() {
        wrapper.pause()
    }
    
    /**
     Stop playback, resetting the player.
     */
    public func stop() {
        reset()
        wrapper.stop()
        event.playbackEnd.emit(data: .playerStopped)
    }
    
    /**
     Seek to a specific time in the item.
     */
    public func seek(to seconds: TimeInterval) {
        if automaticallyUpdateNowPlayingInfo {
            updateNowPlayingCurrentTime(seconds)
        }
        wrapper.seek(to: seconds)
    }
    
    // MARK: - Remote Command Center
    
    func enableRemoteCommands(_ commands: [RemoteCommand]) {
        remoteCommandController.enable(commands: commands)
    }
    
    func enableRemoteCommands(forItem item: AudioItem) {
        if let item = item as? RemoteCommandable {
            self.enableRemoteCommands(item.getCommands())
        }
        else {
            self.enableRemoteCommands(remoteCommands)
        }
    }

    /**
     Syncs the current remoteCommands with the iOS command center.
     Can be used to update item states - e.g. like, dislike and bookmark.
     */
    @available(*, deprecated, message: "Directly set .remoteCommands instead")
    public func syncRemoteCommandsWithCommandCenter() {
        self.enableRemoteCommands(remoteCommands)
    }
    
    // MARK: - NowPlayingInfo
    
    /**
     Loads NowPlayingInfo-meta values with the values found in the current `AudioItem`. Use this if a change to the `AudioItem` is made and you want to update the `NowPlayingInfoController`s values.
     
     Reloads:
     - Artist
     - Title
     - Album title
     - Album artwork
     */
    public func loadNowPlayingMetaValues() {
        guard let item = currentItem else { return }
        
        nowPlayingInfoController.set(keyValues: [
            MediaItemProperty.artist(item.getArtist()),
            MediaItemProperty.title(item.getTitle()),
            MediaItemProperty.albumTitle(item.getAlbumTitle()),
        ])
        
        loadArtwork(forItem: item)
    }
    
    /**
     Resyncs the playbackvalues of the currently playing `AudioItem`.
     
     Will resync:
     - Current time
     - Duration
     - Playback rate
     */
    public func updateNowPlayingPlaybackValues() {
        updateNowPlayingCurrentTime(currentTime)
        updateNowPlayingDuration(duration)
        updateNowPlayingRate(rate)
    }
    
    private func updateNowPlayingDuration(_ duration: Double) {
        nowPlayingInfoController.set(keyValue: MediaItemProperty.duration(duration))
    }
    
    private func updateNowPlayingRate(_ rate: Float) {
        nowPlayingInfoController.set(keyValue: NowPlayingInfoProperty.playbackRate(Double(rate)))
    }
    
    private func updateNowPlayingCurrentTime(_ currentTime: Double) {
        nowPlayingInfoController.set(keyValue: NowPlayingInfoProperty.elapsedPlaybackTime(currentTime))
    }
    
    private func loadArtwork(forItem item: AudioItem) {
        item.getArtwork { (image) in
            if let image = image {
                let artwork = MPMediaItemArtwork(boundsSize: image.size, requestHandler: { _ in image })
                self.nowPlayingInfoController.set(keyValue: MediaItemProperty.artwork(artwork))
            } else {
                self.nowPlayingInfoController.set(keyValue: MediaItemProperty.artwork(nil))
            }
        }
    }
    
    // MARK: - Private
    
    func reset() {
        currentItem = nil
    }
    
    private func setTimePitchingAlgorithmForCurrentItem() {
        if let item = currentItem as? TimePitching {
            wrapper.currentItem?.audioTimePitchAlgorithm = item.getPitchAlgorithmType()
        }
        else {
            wrapper.currentItem?.audioTimePitchAlgorithm = audioTimePitchAlgorithm
        }
    }
    
    // MARK: - AVPlayerWrapperDelegate
    
    func AVWrapper(didChangeState state: AVPlayerWrapperState) {
        switch state {
        case .ready, .loading:
            if (automaticallyUpdateNowPlayingInfo) {
                updateNowPlayingPlaybackValues()
            }
            setTimePitchingAlgorithmForCurrentItem()
        case .playing:
            // When a track starts playing, reset the rate to the stored rate
            rate = _rate;
            fallthrough
        case .paused:
            if (automaticallyUpdateNowPlayingInfo) {
                updateNowPlayingPlaybackValues()
            }
        default: break
        }
        event.stateChange.emit(data: state)
    }
    
    func AVWrapper(didChangeEffectiveRate effectiveRate: Double, rate: Double) {
        event.updateRealRate.emit(data: (effectiveRate, rate))
    }
    
    func AVWrapper(secondsElapsed seconds: Double) {
        event.secondElapse.emit(data: seconds)
    }
    
    func AVWrapper(failedWithError error: Error?) {
        event.fail.emit(data: error)
    }
    
    func AVWrapper(seekTo seconds: Int, didFinish: Bool) {
        if !didFinish && automaticallyUpdateNowPlayingInfo {
            updateNowPlayingCurrentTime(currentTime)
        }
        event.seek.emit(data: (seconds, didFinish))
    }
    
    func AVWrapper(didUpdateDuration duration: Double) {
        event.updateDuration.emit(data: duration)
    }
    
    func AVWrapper(didReceiveMetadata metadata: [AVTimedMetadataGroup]) {
        event.receiveMetadata.emit(data: metadata)
    }
    
    func AVWrapperItemDidPlayToEndTime() {
        event.playbackEnd.emit(data: .playedUntilEnd)
    }
    
    func AVWrapperDidRecreateAVPlayer() {
        event.didRecreateAVPlayer.emit(data: ())
    }
}
