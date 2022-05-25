//
//  AVPlayerItemObserver.swift
//  SwiftAudio
//
//  Created by Jørgen Henrichsen on 28/07/2018.
//

import Foundation
import AVFoundation

protocol AVPlayerItemObserverDelegate: AnyObject {
    
    /**
     Called when the observed item receives metadata
     */
    func item(didReceiveMetadata metadata: [AVTimedMetadataGroup])
}

/**
 Observing an AVPlayers status changes.
 */
class AVPlayerItemObserver: NSObject {
    
    private let metadataOutput: AVPlayerItemMetadataOutput

    private(set) var isObserving: Bool = false
    
    private(set) weak var observingItem: AVPlayerItem?
    weak var delegate: AVPlayerItemObserverDelegate?
    
    override init() {
        metadataOutput = AVPlayerItemMetadataOutput()
        super.init()
        
        metadataOutput.setDelegate(self, queue: .main)
    }
    
    deinit {
        stopObservingCurrentItem()
    }
    
    /**
     Start observing an item. Will remove self as observer from old item, if any.
     
     - parameter item: The player item to observe.
     */
    func startObserving(item: AVPlayerItem) {
        stopObservingCurrentItem()
        isObserving = true
        observingItem = item
        item.add(metadataOutput)
    }
    
    func stopObservingCurrentItem() {
        isObserving = false
        self.observingItem = nil
    }
}

extension AVPlayerItemObserver: AVPlayerItemMetadataOutputPushDelegate {
    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        delegate?.item(didReceiveMetadata: groups)
    }
}
