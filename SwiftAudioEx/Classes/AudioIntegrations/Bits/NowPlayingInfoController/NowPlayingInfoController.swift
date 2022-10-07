//
//  NowPlayingInfoController.swift
//  KeepTalkingFM
//
//  Created by Marina Gornostaeva on 10/05/2022.
//

import MediaPlayer

class NowPlayingInfoController {
    init() {
    }
}

extension NowPlayingInfoController {

    func updateNowPlayingMetadata(_ metadata: NowPlayableStaticMetadata) {
       
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo: [String: Any] = [:]
        
        print("📱 Set track meta: title \(metadata.title)")
        nowPlayingInfo[MPNowPlayingInfoPropertyAssetURL] = metadata.assetURL
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = metadata.mediaType.rawValue
        nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.podcast.rawValue
        nowPlayingInfo[MPMediaItemPropertyTitle] = metadata.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = metadata.artist
        nowPlayingInfo[MPMediaItemPropertyArtwork] = metadata.artwork
        nowPlayingInfo[MPMediaItemPropertyAlbumArtist] = metadata.albumArtist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = metadata.albumTitle
        
        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
    }
    
    func updateNowPlayingPlaybackInfo(_ metadata: NowPlayableDynamicMetadata, onlyIfRateChanged: Bool) {
        
        let nowPlayingInfoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = nowPlayingInfoCenter.nowPlayingInfo ?? [:]
        
        if onlyIfRateChanged, let alreadySetRate = nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] as? Float, alreadySetRate == metadata.rate {
            return
        }
        
        print("📱 Set playback info: rate \(metadata.rate), position \(metadata.position), duration \(metadata.duration)")
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = metadata.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = metadata.position
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = metadata.rate
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        
        nowPlayingInfoCenter.nowPlayingInfo = nowPlayingInfo
    }
}
