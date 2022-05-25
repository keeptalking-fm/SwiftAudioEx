//
//  AudioPlayerObserver.swift
//  SwiftAudio
//
//  Created by Jørgen Henrichsen on 09/03/2018.
//  Copyright © 2018 Jørgen Henrichsen. All rights reserved.
//

import Foundation
import AVFoundation

protocol AVPlayerObserverDelegate: AnyObject {
    
    /**
     Called when the AVPlayer.status changes.
     */
    func player(statusDidChange status: AVPlayer.Status)
    
    /**
     Called when the AVPlayer.timeControlStatus changes.
     */
    func player(didChangeTimeControlStatus status: AVPlayer.TimeControlStatus)
    
    /**
     Called when the AVPlayer.rate changes.
     */
    func player(didChangeRate rate: Float)
    
    /**
     Called when the AVPlayer.currentItem changes.
     */
    func player(currentItemDidChange item: AVPlayerItem?)
    
    /**
     Called when the AVPlayer.currentItem.status changes.
     */
    func player(currentItemStatusDidChange status: AVPlayerItem.Status)
    
    /**
     Called when the AVPlayer.currentItem.duration changes.
     */
    func player(currentItemDurationDidChange duration: CMTime?)
}

/**
 Observing an AVPlayers status changes.
 */
class AVPlayerObserver {

    private(set) var isObserving: Bool = false
    
    private var keyPathObservations: [NSObjectProtocol] = []

    weak var delegate: AVPlayerObserverDelegate?
    weak var player: AVPlayer? {
        willSet {
            stopObserving()
        }
    }

    deinit {
        stopObserving()
    }
    
    init() {
    }
    

    /**
     Start receiving events from this observer.
     */
    func startObserving() {
        guard let player = player else {
            return
        }
        stopObserving()
        isObserving = true
        
        player.observe(\.status, options: [.new, .initial]) { [weak self] p, change in
            self?.delegate?.player(statusDidChange: p.status)
        }.store(in: &keyPathObservations)
        
        player.observe(\.timeControlStatus, options: [.new], changeHandler: { [weak self] p, change in
            self?.delegate?.player(didChangeTimeControlStatus: p.timeControlStatus)
        }).store(in: &keyPathObservations)
        
        player.observe(\.rate, options: [.new]) { [weak self] p, change in
            self?.delegate?.player(didChangeRate: p.rate)
        }.store(in: &keyPathObservations)
        
        player.observe(\.currentItem, options: [.new], changeHandler: { [weak self] p, change in
            self?.delegate?.player(currentItemDidChange: p.currentItem)
        }).store(in: &keyPathObservations)
        
        player.observe(\.currentItem?.status, options: [.new], changeHandler: { [weak self] p, change in
            self?.delegate?.player(currentItemStatusDidChange: p.currentItem?.status ?? .unknown)
        }).store(in: &keyPathObservations)
        
        player.observe(\.currentItem?.duration, options: [.new]) { [weak self] p, change in
            self?.delegate?.player(currentItemDurationDidChange: p.currentItem?.duration)
        }.store(in: &keyPathObservations)
    }

    func stopObserving() {
        keyPathObservations = []
        isObserving = false
    }
}

private extension NSObjectProtocol {
    func store(in collection: inout [NSObjectProtocol]) {
        collection.append(self)
    }
}

/// Can't use `as?` with CoreFoundation types (CMTimebase is one)
/// https://stackoverflow.com/questions/43927167/trouble-retrieving-a-cgcolor-from-a-swift-dictionary
private func asCMTimebase<T>(_ value: T?) -> CMTimebase? {
    guard let value = value else { return nil }
    guard CFGetTypeID(value as CFTypeRef) == CMTimebase.typeID else { return nil }
    return (value as! CMTimebase)
}
