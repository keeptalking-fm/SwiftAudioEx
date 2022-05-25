//
//  AVPlayerWrapperState.swift
//  SwiftAudio
//
//  Created by Jørgen Henrichsen on 10/03/2018.
//  Copyright © 2018 Jørgen Henrichsen. All rights reserved.
//

import Foundation


/**
 The current state of the AudioPlayer.
 */
public enum AVPlayerWrapperState: Equatable {
    
    /// An asset is being loaded for playback.
    case loading
    
    /// The current item is loaded, and the player is ready to start playing.
    case ready
    
    /// The current item is playing, but are currently buffering.
    case buffering
    
    /// The player is paused.
    case paused
    
    /// The player is playing.
    case playing(rate: Float)
    
    /// No item loaded, the player is stopped.
    case idle
    
    var rate: Float {
        switch self {
            case .loading:
                return 0
            case .ready:
                return 0
            case .buffering:
                return 0
            case .paused:
                return 0
            case .playing(let rate):
                return rate
            case .idle:
                return 0
        }
    }
    
    var isBufferingOrPlaying: Bool {
        switch self {
            case .loading:
                return false
            case .ready:
                return false
            case .buffering:
                return true
            case .paused:
                return false
            case .playing:
                return true
            case .idle:
                return false
        }
    }
}
