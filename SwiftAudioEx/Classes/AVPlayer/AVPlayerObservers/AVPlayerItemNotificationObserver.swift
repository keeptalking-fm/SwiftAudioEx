//
//  AVPlayerItemNotificationObserver.swift
//  SwiftAudio
//
//  Created by Jørgen Henrichsen on 12/03/2018.
//

import Foundation
import AVFoundation

protocol AVPlayerItemNotificationObserverDelegate: AnyObject {
    func itemDidPlayToEndTime(_ item: AVPlayerItem)
}

/**
 Observes notifications posted by an AVPlayerItem.
 
 Currently only listening for the AVPlayerItemDidPlayToEndTime notification.
 */
class AVPlayerItemNotificationObserver {
    
    private let notificationCenter: NotificationCenter = NotificationCenter.default
    
    weak var delegate: AVPlayerItemNotificationObserverDelegate?
    
    private(set) var isObserving: Bool = false
    
    deinit {
        stopObservingCurrentItem()
    }
    
    /**
     Will start observing notifications from an item.
     
     - parameter item: The item to observe.
     - important: Cannot observe more than one item at a time.
     */
    func startObserving() {
        stopObservingCurrentItem()
        isObserving = true
        notificationCenter.addObserver(self, selector: #selector(itemDidPlayToEndTime(note:)), name: Notification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
    }
    
    /**
     Stop receiving notifications for the current item.
     */
    func stopObservingCurrentItem() {
        guard isObserving else {
            return
        }
        notificationCenter.removeObserver(self, name: Notification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
        isObserving = false
    }
    
    @objc private func itemDidPlayToEndTime(note: Notification) {
        guard let object = note.object as? AVPlayerItem else { return }
        delegate?.itemDidPlayToEndTime(object)
    }
}
