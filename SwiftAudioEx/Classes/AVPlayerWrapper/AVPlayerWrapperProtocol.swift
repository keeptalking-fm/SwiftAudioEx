//
//  AVPlayerWrapperProtocol.swift
//  SwiftAudio
//
//  Created by Jørgen Henrichsen on 26/10/2018.
//

import Foundation
import AVFoundation


protocol AVPlayerWrapperProtocol: AnyObject {

    var state: AVPlayerWrapperState { get }

    var playWhenReady: Bool { get }
    
    var currentItem: AVPlayerItem? { get }
    
    var currentTime: TimeInterval { get }
    
    var duration: TimeInterval { get }
    
    var bufferedPosition: TimeInterval { get }
    
    var reasonForWaitingToPlay: AVPlayer.WaitingReason? { get }
    
    
    var rate: Float { get set }
    
    var realRate: Float { get }

    var delegate: AVPlayerWrapperDelegate? { get set }
    
    var bufferDuration: TimeInterval { get set }
    
    var timeEventFrequency: TimeEventFrequency { get set }
    
    var volume: Float { get set }
    
    var isMuted: Bool { get set }
    
    var automaticallyWaitsToMinimizeStalling: Bool { get set }
        
    
    func play()
    
    func pause()
    
    func togglePlaying()
    
    func stop()
    
    func seek(to seconds: TimeInterval)
    
    func load(from url: URL, forceRecreateAVPlayer: Bool, playWhenReady: Bool, options: [String: Any]?)
    
    func load(from url: URL, forceRecreateAVPlayer: Bool, playWhenReady: Bool, initialTime: TimeInterval?, options: [String: Any]?)
}
