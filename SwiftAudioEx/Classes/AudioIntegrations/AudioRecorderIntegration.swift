//
//  AudioRecorderIntegration.swift
//  KeepTalkingFM
//
//  Created by Marina Gornostaeva on 18/05/2022.
//

import Foundation

public struct AudioRecorderTimeStatus: Equatable {

    public var acceptedDurations: ClosedRange<Seconds>
    public var elapsed: Seconds
    
    public var isOverMinDuration: Bool {
        elapsed >= acceptedDurations.lowerBound
    }
    
    public var remaining: Seconds {
        max(0, acceptedDurations.upperBound - elapsed)
    }
    
    public static var zero: AudioRecorderTimeStatus {
        .init(acceptedDurations: 0...0, elapsed: 0)
    }
}

public enum AudioRecorderStatus {
    case idle
    case recording
    case saving(duration: Seconds)
    case saved(RecordedFile)
    case failed(AudioRecorderError)
    
    var isRecording: Bool {
        switch self {
            case .idle, .failed:
                return false
            case .recording:
                return true
            case .saving, .saved:
                return false
        }
    }
}

public struct AudioRecorderStateChange: OptionSet {
    public let rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    public static let recordingItem = AudioRecorderStateChange(rawValue: 1 << 0)
    public static let recordingStatus = AudioRecorderStateChange(rawValue: 1 << 1)
    public static let timeStatus = AudioRecorderStateChange(rawValue: 1 << 2)
    
    public static let all: AudioRecorderStateChange = [.recordingItem, .recordingStatus, .timeStatus]
}

// MARK: -

public struct RecordingItem: Equatable {
    public var fileID: UUID = UUID()
    public var directory: URL
    public var metadata: Metadata
    
    public init(fileID: UUID = UUID(), directory: URL, metadata: RecordingItem.Metadata) {
        self.fileID = fileID
        self.directory = directory
        self.metadata = metadata
    }
}

public extension RecordingItem {
    
    struct Metadata: Equatable {
        public var convoID: UUID
        
        public init(convoID: UUID) {
            self.convoID = convoID
        }
    }
}

public struct RecordedFile: Equatable {
    public var fileURL: URL
    public var duration: Double
}

// MARK: -

public protocol AudioRecorderIntegrationDelegate: AnyObject {
    func stateDidChange(_ stateChanges: AudioRecorderStateChange, in recorderIntegration: AudioRecorderIntegration)
}

public protocol AudioRecorderIntegration: AnyObject {
    
    var delegate: AudioRecorderIntegrationDelegate? { get set }
    var recordingItem: RecordingItem? { get }
    var status: AudioRecorderStatus { get }
    var timeStatus: AudioRecorderTimeStatus? { get }
    
    var timeUpdateFrequency: Seconds { get }
    
    func startNewRecording(_ item: RecordingItem, acceptedDurations: ClosedRange<Seconds>)
    func stop()
    func discard()
}
