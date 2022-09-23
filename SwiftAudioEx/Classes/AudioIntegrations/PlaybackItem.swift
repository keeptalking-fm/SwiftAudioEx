//
//  PlaybackItem.swift
//  KeepTalkingFM
//
//  Created by Marina Gornostaeva on 03/05/2022.
//

import Foundation

public struct PlaybackQueueSource {
    public var metadata: Metadata
    public var items: [PlaybackItem]
    
    public init(metadata: PlaybackQueueSource.Metadata, items: [PlaybackItem]) {
        self.metadata = metadata
        self.items = items
    }

    public struct Metadata {
        public var id: UUID
        public var title: String
        
        public init(id: UUID, title: String) {
            self.id = id
            self.title = title
        }
    }
}

public struct PlaybackItem {
    public var metadata: PlaybackItem.Metadata
    public var audioURL: URL
    
    public init(metadata: PlaybackItem.Metadata, audioURL: URL) {
        self.metadata = metadata
        self.audioURL = audioURL
    }

    public struct Metadata {
        public var id: UUID
        public var authorName: String
        public var albumTitle: String
        
        public init(id: UUID, authorName: String, albumTitle: String) {
            self.id = id
            self.authorName = authorName
            self.albumTitle = albumTitle
        }
    }
}
