//
//  AVQueuePlayerWrapper.swift
//  
//
//  Created by Marina Gornostaeva on 25/05/2022.
//

import Foundation
import AVFoundation

protocol AVQueuePlayerWrapperDelegate: AnyObject {
    func stateDidChange(in wrapper: AVQueuePlayerWrapper)
    func rateDidChange(in wrapper: AVQueuePlayerWrapper)
    func currentItemDidChange(in wrapper: AVQueuePlayerWrapper)
    func timeDidChange(in wrapper: AVQueuePlayerWrapper)
}

class AVQueuePlayerWrapper {

    class Item {
        let sourceItem: AudioItem
        let asset: AVURLAsset
        
        init(audioItem: AudioItem) {
            sourceItem = audioItem
            asset = AVURLAsset(url: audioItem.sourceURL)
        }
    }
    
    private var avPlayer: AVQueuePlayer? {
        willSet {
            observer.player = nil
        }
        didSet {
            observer.player = avPlayer
            observer.startObserving()
        }
    }
    let observer: AVPlayerObserver
    
    weak var delegate: AVQueuePlayerWrapperDelegate?
    
    private(set) var items: [Item] = []
    
    init() {
        avPlayer = AVQueuePlayer()
        observer = AVPlayerObserver()
        
        observer.player = avPlayer
        observer.delegate = self
        observer.startObserving()
    }
    
    var currentTime: Seconds {
        guard let seconds = avPlayer?.currentTime().seconds else { return 0 }
        return seconds.isNaN ? 0 : seconds
    }
    
    var duration: Seconds {
        if let seconds = avPlayer?.currentItem?.duration.seconds, !seconds.isNaN {
            return seconds
        }
        return 0.0
    }
    
    var playerState: AVPlayerWrapperState {
        guard let avPlayer = avPlayer else { return .idle }

        switch avPlayer.status {
            case .unknown:
                return .idle
            case .readyToPlay:
                switch avPlayer.timeControlStatus {
                    case .paused:
                        return .paused
                    case .waitingToPlayAtSpecifiedRate:
                        return .buffering
                    case .playing:
                        return .playing
                    @unknown default:
                        return .paused
                }
            case .failed:
                return .loading
            @unknown default:
                return .idle
        }
    }
    
    var currentItem: AudioItem? {
        guard let currentItem = avPlayer?.currentItem else { return nil }
        
        let item = items.first(where: { $0.asset === currentItem.asset })
        return item?.sourceItem
    }
    
    func load(_ items: [AudioItem]) {
        print("LOAD")
        
        // When AVPlayerItem deallocates, it can sometimes freeze the main thread, if KVO observations are attached to it still.
        // Stop observing to let the stuff deallocate, and restart observation below.
        // UPD: seems to work fine without it now. If any freezes occur, enable this back.
//        observer.player = nil
        
        pause()
        
        self.items = items.map { Item(audioItem: $0) }
        // automaticallyLoadedAssetKeys is required here. Without it, the player will sometimes freeze the main thread forever
        let playerItems = self.items.map({ AVPlayerItem(asset:$0.asset, automaticallyLoadedAssetKeys: ["playable"]) })
        
//        self.observer.player = self.avPlayer
//        self.observer.startObserving()
        
        
        self.avPlayer?.removeAllItems()
        for playerItems in playerItems {
            if self.avPlayer?.canInsert(playerItems, after: nil) == true {
                self.avPlayer?.insert(playerItems, after: nil)
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
    
    func pause() {
        avPlayer?.rate = 0.0
    }
    
    func play() {
        avPlayer?.rate = 1.0
    }
    
    func stop() {
        pause()
        avPlayer?.removeAllItems()
    }
    
    func next() {
        avPlayer?.advanceToNextItem()
    }
    
    func previous() {
        // TODO: insert an item
    }
    
    func jumpToItem(id: UUID, playWhenReady: Bool) {
//        guard let matchingItem = items
//                .first(where: { $0.element.metadata.id == id })
    }
    
    var realRate: Float {
        switch playerState {
            case .idle, .loading, .ready, .buffering, .paused:
                return 0.0
            case .playing:
                return avPlayer?.rate ?? 0.0
        }
    }
}

extension AVQueuePlayerWrapper: AVPlayerObserverDelegate {
    func player(statusDidChange status: AVPlayer.Status) {
//        print(status, status.rawValue)
        delegate?.stateDidChange(in: self)
    }
    
    func player(didChangeTimeControlStatus status: AVPlayer.TimeControlStatus) {
//        print(status, status.rawValue)
        delegate?.stateDidChange(in: self)
    }
    
    func player(didChangeRate rate: Float) {
        delegate?.rateDidChange(in: self)
    }
    
    func player(currentItemDidChange item: AVPlayerItem?) {
        delegate?.currentItemDidChange(in: self)
    }
    
    func player(currentItemStatusDidChange status: AVPlayerItem.Status) {
        delegate?.stateDidChange(in: self)
    }
    
    func player(currentItemDurationDidChange duration: CMTime?) {
        delegate?.timeDidChange(in: self)
    }
}

func print(_ items: Any...) {
    let newItems: [Any] = [Date().timeIntervalSince1970] + items
    for item in newItems {
        Swift.print(item, terminator: " ")
    }
    Swift.print()
}
