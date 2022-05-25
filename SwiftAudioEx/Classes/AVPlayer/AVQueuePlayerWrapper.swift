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
}

class AVQueuePlayerWrapper {

    struct State: Equatable {
        var currentItem: AudioItem?
        var playerState: AVPlayerWrapperState = .idle
        var duration: Seconds
        
        static func == (lhs: AVQueuePlayerWrapper.State, rhs: AVQueuePlayerWrapper.State) -> Bool {
            return lhs.playerState == rhs.playerState && lhs.currentItem?.id == rhs.currentItem?.id && lhs.duration == rhs.duration
        }
    }
    
    private class Item {
        let sourceItem: AudioItem
        let asset: AVURLAsset
        
        init(audioItem: AudioItem) {
            sourceItem = audioItem
            asset = AVURLAsset(url: audioItem.sourceURL)
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
    
    weak var delegate: AVQueuePlayerWrapperDelegate?
    
    private(set) var state: State
    
    var timeEventFrequency: TimeEventFrequency = .everySecond {
        didSet {
            timeObserver.periodicObserverTimeInterval = timeEventFrequency.getTime()
        }
    }

    init() {
        state = State(currentItem: nil, playerState: .idle, duration: 0)
        
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

    private func recalcState() {
        // Many KVO properties change at once.
        // To avoid too many callbacks (resulting in jumpy Now Playing info since it updates async)
        // making sure multiple callbacks are not called for partial changes
        // (hence always recalculating from actual state and not looking at which part changed in KVO)
        
        let currentItem: AudioItem?
        if let playingItem = avPlayer.currentItem,
           let item = items.first(where: { $0.asset === playingItem.asset })
        {
            currentItem = item.sourceItem
        } else {
            currentItem = nil
        }
        
        let playerState: AVPlayerWrapperState
        switch avPlayer.status {
            case .unknown:
                playerState = avPlayer.currentItem == nil ? .idle : .loading
            case .readyToPlay:
                switch avPlayer.timeControlStatus {
                    case .paused:
                        playerState = avPlayer.currentItem == nil ? .idle : .paused
                    case .waitingToPlayAtSpecifiedRate:
                        playerState = avPlayer.currentItem == nil ? .idle : .buffering
                    case .playing:
                        playerState = .playing(rate: avPlayer.rate)
                    @unknown default:
                        playerState = .paused
                }
            case .failed:
                playerState = .loading
            @unknown default:
                playerState = .idle
        }
        
        let duration: Seconds
        if let seconds = avPlayer.currentItem?.duration.seconds, !seconds.isNaN {
            duration = seconds
        } else {
            duration = 0
        }
        
        let prevState = state
        let newState = State(currentItem: currentItem, playerState: playerState, duration: duration)
        if prevState != newState {
            state = newState
            delegate?.newStateDidChange(in: self)
        }
    }
    
    // MARK: - API -

    func load(_ items: [AudioItem], playWhenReady: Bool, forceRecreateAVPlayer: Bool) {
        print("LOAD")
        
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
        let playerItems = self.items.map({ AVPlayerItem(asset:$0.asset, automaticallyLoadedAssetKeys: ["playable"]) })
        
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
        pause()
        avPlayer.removeAllItems()
    }
    
    func next() {
        avPlayer.advanceToNextItem()
    }
    
    func previous() {
        // TODO: insert an item
    }
    
    func jumpToItem(id: UUID, playWhenReady: Bool) {
//        guard let matchingItem = items
//                .first(where: { $0.element.metadata.id == id })
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

func print(_ items: Any...) {
    let newItems: [Any] = [String(format: "%.5f", Date().timeIntervalSince1970)] + items
    for item in newItems {
        Swift.print(item, terminator: " ")
    }
    Swift.print()
}
