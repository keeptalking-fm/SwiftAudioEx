//
//  AudioSessionManager.swift
//  KeepTalkingFM
//
//  Created by Marina Gornostaeva on 12/05/2022.
//

import AVFoundation

protocol AudioSessionManagerDelegate: AnyObject {
    func audioSessionManager(_ audioSessionManager: AudioSessionManager, didReceiveInterruption type: AudioSessionManager.Interruption)
    func audioSessionManagerDidResetMediaServices(_ audioSessionManager: AudioSessionManager)
}

// Not using AudioSessionController because it's missing some of the needed functionality.
// It's missing ability to customize audio session category and options, and isn't observing media services reset
// Will soon remove AudioSessionController completely, and this comment will be deleted.
class AudioSessionManager {
        
    enum Interruption: Equatable {
        case began
        case ended(shouldResume: Bool)
    }
    
    private var notificationCenter: NotificationCenter { .default }
    private var audioSession: AVAudioSession { .sharedInstance() }
    
    weak var delegate: AudioSessionManagerDelegate?
    
    init() {
        registerForInterruptionNotification()
    }
    
    func activate(category: AVAudioSession.Category, mode: AVAudioSession.Mode, categoryOptions: AVAudioSession.CategoryOptions) throws {
        try audioSession.setCategory(category, mode: mode, options: categoryOptions)
        try audioSession.setActive(true, options: [])
    }
    
    func deactivate() throws {
        try audioSession.setActive(false, options: [])
    }
    
    // MARK: - Interruptions
    
    private func registerForInterruptionNotification() {
        notificationCenter.addObserver(self,
                                       selector: #selector(handleInterruption),
                                       name: AVAudioSession.interruptionNotification,
                                       object: nil)
        notificationCenter.addObserver(self,
                                       selector: #selector(handleMediaServicesWereReset),
                                       name: AVAudioSession.mediaServicesWereResetNotification,
                                       object: nil)
    }
    
    private func unregisterForInterruptionNotification() {
        notificationCenter.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        notificationCenter.removeObserver(self, name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }
    
    @objc private func handleInterruption(notification: Notification) {
        print("handleInterruption", notification.userInfo as Any)
        guard let userInfo = notification.userInfo,
            let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
        }
        
        switch type {
        case .began:
            delegate?.audioSessionManager(self, didReceiveInterruption: .began)
        case .ended:
            guard let typeValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                delegate?.audioSessionManager(self, didReceiveInterruption: .ended(shouldResume: false))
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: typeValue)
            delegate?.audioSessionManager(self, didReceiveInterruption: .ended(shouldResume: options.contains(.shouldResume)))
        @unknown default: return
        }
    }
    
    @objc private func handleMediaServicesWereReset(notification: Notification) {
        delegate?.audioSessionManagerDidResetMediaServices(self)
    }
}

extension AudioSessionManager {
    
    func activateForPlayingAndRecording() throws {
        try activate(category: .playAndRecord, mode: .spokenAudio, categoryOptions: [])
    }
}
