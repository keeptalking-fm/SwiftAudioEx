//
//  AVQueuePlayerWrapper.swift
//  
//
//  Created by Marina Gornostaeva on 25/05/2022.
//

import Foundation
import AVFoundation

protocol AVQueuePlayerWrapperDelegate: AnyObject {
    func elapsedDidChange(in wrapper: AVQueuePlayerWrapper)
    func newStateDidChange(in wrapper: AVQueuePlayerWrapper)
    func queueFinished(in wrapper: AVQueuePlayerWrapper)
}

class AVQueuePlayerWrapper {

    struct State: Equatable {
        var currentAudioItem: AudioItem?
        var playerState: AudioPlayerPlayingStatus = .nothingToPlay
        var duration: Seconds
        
        static func == (lhs: AVQueuePlayerWrapper.State, rhs: AVQueuePlayerWrapper.State) -> Bool {
            return lhs.playerState == rhs.playerState && lhs.currentAudioItem?.id == rhs.currentAudioItem?.id && lhs.duration == rhs.duration
        }
    }
    
    private class Item {
        let sourceItem: AudioItem
        let asset: AVURLAsset
        
        init(audioItem: AudioItem) {
            sourceItem = audioItem
            asset = AVURLAsset(url: audioItem.sourceURL)
        }
        
        func makeAVPlayerItem() -> AVPlayerItem {
            // automaticallyLoadedAssetKeys is required here. Without it, the player will sometimes freeze the main thread forever
            AVPlayerItem(asset: asset, automaticallyLoadedAssetKeys: ["playable"])
        }
    }
    
    private var avPlayer: AVQueuePlayer {
        willSet {
            observer.player = nil
            timeObserver.player = nil
        }
    }
    
    
    
    
    private let observer: AVPlayerObserver
    private let timeObserver: AVPlayerTimeObserver
    private var items: [Item] = []
    private var playWhenReadyOnce: Bool = false
    private var stopped: Bool = false
    
    weak var delegate: AVQueuePlayerWrapperDelegate?
    
    private(set) var state: State
    
    var timeEventFrequency: TimeEventFrequency = .everySecond {
        didSet {
            timeObserver.periodicObserverTimeInterval = timeEventFrequency.getTime()
        }
    }

    init() {
        state = State(duration: 0)
        
        avPlayer = AVQueuePlayer()
        observer = AVPlayerObserver()
        timeObserver = AVPlayerTimeObserver(periodicObserverTimeInterval: timeEventFrequency.getTime())
        
        observer.delegate = self
        timeObserver.delegate = self

        setupAVPlayerObservations()
    }
    
    var elapsed: Seconds {
        let seconds = avPlayer.currentTime().seconds
        return seconds.isNaN ? 0 : seconds
    }
    
    // MARK: - State -
    
    private var currentItem: Item? {
        guard let playingItem = avPlayer.currentItem,
              let item = items.first(where: { $0.asset === playingItem.asset }) else {
            return nil
        }
        return item
    }
    
    private func recalcState() {
        // Many KVO properties change at once.
        // To avoid too many callbacks (resulting in jumpy Now Playing info since it updates async)
        // making sure multiple callbacks are not called for partial changes
        // (hence always recalculating from actual state and not looking at which part changed in KVO)
        
        let currentItem: AudioItem? = currentItem?.sourceItem
        
        let playerState: AudioPlayerPlayingStatus
        switch avPlayer.status {
            case .unknown:
                playerState = avPlayer.currentItem == nil ? .nothingToPlay : .pending
            case .readyToPlay:
                switch avPlayer.timeControlStatus {
                    case .paused:
                        playerState = avPlayer.currentItem == nil ? .nothingToPlay : .paused
                    case .waitingToPlayAtSpecifiedRate:
                        playerState = avPlayer.currentItem == nil ? .nothingToPlay : .waitingToPlay
                    case .playing:
                        playerState = .playing(rate: avPlayer.rate)
                    @unknown default:
                        playerState = .paused
                }
            case .failed:
                playerState = .pending
            @unknown default:
                playerState = .nothingToPlay
        }
        
        let duration: Seconds
        if let seconds = avPlayer.currentItem?.duration.seconds, !seconds.isNaN {
            duration = seconds
        } else {
            duration = 0
        }
        
        let prevState = state
        let newState = State(currentAudioItem: currentItem, playerState: playerState, duration: duration)
        if prevState != newState {
            state = newState
            delegate?.newStateDidChange(in: self)
            
            if !stopped, prevState.currentAudioItem != nil && newState.currentAudioItem == nil {
                delegate?.queueFinished(in: self)
            }
        }
    }
    
    // MARK: - API -

    func load(_ items: [AudioItem], playWhenReady: Bool, forceRecreateAVPlayer: Bool) {
        print("LOAD")
        stopped = false
        
        // When AVPlayerItem deallocates, it can sometimes freeze the main thread, if KVO observations are attached to it still.
        // Stop observing to let the stuff deallocate, and restart observation below.
        // UPD: seems to work fine without it now. If any freezes occur, enable this back.
//        observer.player = nil
        
        pause()
        
        if avPlayer.status == .failed || forceRecreateAVPlayer {
            avPlayer = AVQueuePlayer()
            setupAVPlayerObservations()
        }
        
        playWhenReadyOnce = playWhenReady
        
        self.items = items.map { Item(audioItem: $0) }
        // automaticallyLoadedAssetKeys is required here. Without it, the player will sometimes freeze the main thread forever
        let playerItems = self.items.map({ $0.makeAVPlayerItem() })
        
//        self.observer.player = self.avPlayer
//        self.observer.startObserving()
        
        self.avPlayer.removeAllItems()
        for playerItems in playerItems {
            if self.avPlayer.canInsert(playerItems, after: nil) {
                self.avPlayer.insert(playerItems, after: nil)
            }
        }
        
        // Experimenting with how to create/set AVPlayerItem's :
        
//        var loadedAssets: [AVURLAsset] = []
//        let group = DispatchGroup()
//
//        for item in items {
//            group.enter()
//            let asset = AVURLAsset(url: item.sourceURL)
//            DispatchQueue.global(qos: .userInitiated).async {
//                asset.loadValuesAsynchronously(forKeys: ["playable", "duration"]) {
//                    var error: NSError?
//                    if asset.statusOfValue(forKey: "playable", error: &error) == .loaded {
//                        print("loaded", item.sourceURL)
//                            loadedAssets.append(asset)
//                    }
//                    group.leave()
//                }
//            }
//        }
//
//        group.notify(queue: .main) {
//            print("inserting...")
//            // experiment 1.1: create new assets without preloading (should also comment out loadValuesAsynchronously... block above)
////            let playerItems = items.map({ AVPlayerItem(asset: AVURLAsset(url: $0.sourceURL), automaticallyLoadedAssetKeys: ["playable"]) })
//
//            // experiment 1.2: only set assets when they're loaded
////            let playerItems = loadedAssets.map({ AVPlayerItem(asset: $0, automaticallyLoadedAssetKeys: [] )})
//
//            // experiment 2.1: insert assets to the existing player
////            self.avPlayer?.removeAllItems()
////            for playerItems in playerItems {
////                if self.avPlayer?.canInsert(playerItems, after: nil) == true {
////                    self.avPlayer?.insert(playerItems, after: nil)
////                }
////            }
//
//            // experiment 2.2: recreate the player every time
////            self.avPlayer = AVQueuePlayer(items: playerItems)
//
//            self.observer.player = self.avPlayer
//            self.observer.startObserving()
//        }
    }
    
    private func setupAVPlayerObservations() {
        observer.player = avPlayer
        observer.startObserving()
        
        timeObserver.player = avPlayer
        timeObserver.registerForPeriodicTimeEvents()
        timeObserver.registerForBoundaryTimeEvents()
    }
    
    func pause() {
        avPlayer.rate = 0.0
    }
    
    func play() {
        avPlayer.rate = 1.0
    }
    
    func stop() {
        stopped = true
        pause()
        avPlayer.removeAllItems()
    }
    
    func next() {
        avPlayer.advanceToNextItem()
    }
    
    func previous() {
        // fx the queue is: [current, a, b]
        // it will become: [previous, current, a, b]
        
        guard let current = state.currentAudioItem else { return }
        guard let currentIndex = items.firstIndex(where: { $0.sourceItem.id == current.id }) else { return }
        guard currentIndex != items.startIndex else { return }
        
        let previousIndex = items.index(before: currentIndex)
        
        let newPlayerItem = items[previousIndex].makeAVPlayerItem()
        let newCurrentPlayerItemCopy = items[currentIndex].makeAVPlayerItem()
        
        if avPlayer.canInsert(newPlayerItem, after: avPlayer.currentItem) {
            avPlayer.insert(newPlayerItem, after: avPlayer.currentItem)
            
            if avPlayer.canInsert(newCurrentPlayerItemCopy, after: newPlayerItem) {
                avPlayer.insert(newCurrentPlayerItemCopy, after: newPlayerItem)
            }
            avPlayer.advanceToNextItem()
        }
    }
    
    func jumpToItem(id idToJumpTo: UUID, playWhenReady: Bool) {
        guard let newItem = items.first(where: { $0.sourceItem.id == idToJumpTo }) else { return }

        if let indexInQueue = avPlayer.items().firstIndex(where: { $0.asset === newItem.asset }), indexInQueue != avPlayer.items().startIndex {

            // the item in question is ahead and not current

            let itemsToRemove = avPlayer.items()[0...indexInQueue - 1]
            itemsToRemove.forEach(avPlayer.remove)
        }
        else {
            // the item in question is not in the queue, insert it before
            // fx the queue is: [current, a, b]
            // it will become: [withID, current, a, b]
            
            guard let current = currentItem else { return }
            guard let newItem = items.first(where: { $0.sourceItem.id == idToJumpTo }) else { return }
            
            let newPlayerItem = newItem.makeAVPlayerItem()
            let newCurrentPlayerItemCopy = current.makeAVPlayerItem()
            
            if avPlayer.canInsert(newPlayerItem, after: avPlayer.currentItem) {
                avPlayer.insert(newPlayerItem, after: avPlayer.currentItem)
                
                if avPlayer.canInsert(newCurrentPlayerItemCopy, after: newPlayerItem) {
                    avPlayer.insert(newCurrentPlayerItemCopy, after: newPlayerItem)
                }
                avPlayer.advanceToNextItem()
            }
        }
    }
}

extension AVQueuePlayerWrapper: AVPlayerObserverDelegate {
    func player(statusDidChange status: AVPlayer.Status) {
        recalcState()
    }
    
    func player(didChangeTimeControlStatus status: AVPlayer.TimeControlStatus) {
        recalcState()
    }
    
    func player(didChangeRate rate: Float) {
        recalcState()
    }
    
    func player(currentItemDidChange item: AVPlayerItem?) {
        recalcState()
    }
    
    func player(currentItemStatusDidChange status: AVPlayerItem.Status) {
        recalcState()

        if status == .readyToPlay && playWhenReadyOnce {
            play()
            playWhenReadyOnce = false
        }
    }
    
    func player(currentItemDurationDidChange duration: CMTime?) {
        recalcState()
    }
}

extension AVQueuePlayerWrapper: AVPlayerTimeObserverDelegate {
    func audioDidStart() {
        print("audioDidStart")
    }
    
    func timeEvent(time: CMTime) {
        delegate?.elapsedDidChange(in: self)
    }
}

extension AudioPlayerPlayingStatus {
    var rate: Float {
        switch self {
            case .pending:
                return 0
            case .waitingToPlay:
                return 0
            case .paused:
                return 0
            case .playing(let rate):
                return rate
            case .nothingToPlay:
                return 0
        }
    }
    
    var isBufferingOrPlaying: Bool {
        switch self {
            case .pending:
                return false
            case .waitingToPlay:
                return true
            case .paused:
                return false
            case .playing:
                return true
            case .nothingToPlay:
                return false
        }
    }
}

// MARK: -

func print(_ items: Any...) {
    let newItems: [Any] = [String(format: "%.5f", Date().timeIntervalSince1970)] + items
    for item in newItems {
        Swift.print(item, terminator: " ")
    }
    Swift.print()
}
