//
//  DummyAudioRecorderIntegration.swift
//  KeepTalkingFM
//
//  Created by Marina Gornostaeva on 18/05/2022.
//

import Foundation

public class DummyAudioRecorderIntegration: AudioRecorderIntegration {
    
    public weak var delegate: AudioRecorderIntegrationDelegate?
    
    public private(set) var recordingItem: RecordingItem?
    public private(set) var status: AudioRecorderStatus
    public private(set) var timeStatus: AudioRecorderTimeStatus?
    
    public var timeUpdateFrequency: Seconds = 0
    
    public init() {
        status = .idle
    }
    
    public func startNewRecording(_ item: RecordingItem, acceptedDurations: ClosedRange<Seconds>) {
        recordingItem = item
        status = .recording
        timeStatus = AudioRecorderTimeStatus(acceptedDurations: acceptedDurations, elapsed: 0)
        // elapsed should tick
        
        delegate?.stateDidChange(.all, in: self)
    }
    
    public func stop() {
        guard let recordingItem = recordingItem else { return }
        status = .saved(RecordedFile(fileURL: recordingItem.directory.appendingPathComponent(recordingItem.fileID.uuidString), duration: 0))
        delegate?.stateDidChange(.recordingStatus, in: self)
    }
    
    public func discard() {
        status = .idle
        recordingItem = nil
        timeStatus = nil
        delegate?.stateDidChange(.all, in: self)
    }
}
