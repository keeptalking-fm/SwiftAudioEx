//
//  AudioRecorder.swift
//  KeepTalkingFM
//
//  Created by Marina Gornostaeva on 16/05/2022.
//

import Foundation
import AVFoundation

public final class SystemAudioRecorderIntegration: NSObject, AudioRecorderIntegration {
    
    private struct OngoingRecording {
        /// Describes what we were asked to record
        var item: RecordingItem
        
        /// The recorder instance itself
        var recorder: AVAudioRecorder
        
        /// A ticking (repeating) timer to update elapsed time of the recording
        var timeStatusUpdateTimer: Timer
        
        /// Fires once, after max recording length is reached
        var maxRecordingDurationTimer: Timer
        
        /// Describes minimum and maximum recording durations
        var acceptedDurations: ClosedRange<Seconds>
        
        func stopRecorderAndTimers(deleteFile: Bool) {
            timeStatusUpdateTimer.invalidate()
            maxRecordingDurationTimer.invalidate()
            recorder.stop()
            if deleteFile {
                let deleted = recorder.deleteRecording()
                print("tried to delete file \(recorder.url). Success: \(deleted)")
            }
        }
    }
    
    public  weak var delegate: AudioRecorderIntegrationDelegate?
    
    public private(set) var status: AudioRecorderStatus = .idle {
        didSet {
            print("SystemAudioRecorderIntegration STATUS \(status)")
        }
    }
    
    public var timeStatus: AudioRecorderTimeStatus? {
        guard let ongoingRecording = ongoingRecording else { return nil }
        switch status {
            case .idle, .failed:
                return nil
            case .recording:
                return AudioRecorderTimeStatus(acceptedDurations: ongoingRecording.acceptedDurations, elapsed: ongoingRecording.recorder.currentTime)
            case .saving(let duration):
                return AudioRecorderTimeStatus(acceptedDurations: ongoingRecording.acceptedDurations, elapsed: duration)
            case .saved(let recordedFile):
                return AudioRecorderTimeStatus(acceptedDurations: ongoingRecording.acceptedDurations, elapsed: recordedFile.duration)
        }
    }
    
    public var recordingItem: RecordingItem? {
        ongoingRecording?.item
    }
    
    public private(set) var timeUpdateFrequency: Seconds = 0.25

    private var ongoingRecording: OngoingRecording? {
        didSet {
            oldValue?.recorder.delegate = nil
            ongoingRecording?.recorder.delegate = self
        }
    }

    private let audioSession: AudioSessionManager

    public override init() {
        self.audioSession = AudioSessionManager()
        super.init()
        
        audioSession.delegate = self
    }
    
    public func startNewRecording(_ item: RecordingItem, acceptedDurations: ClosedRange<Seconds>) {
        AVAudioSession.sharedInstance().requestRecordPermission() { allowed in
            DispatchQueue.main.async {
                guard allowed else {
                    self.invalidateRecorder(error: .noMicrophonePermissionPermission)
                    return
                }
                self.continueWithNewRecording(item, acceptedDurations: acceptedDurations)
            }
        }
    }
    
    private func continueWithNewRecording(_ item: RecordingItem, acceptedDurations: ClosedRange<Seconds>) {
        if let ongoingRecording = ongoingRecording {
            ongoingRecording.stopRecorderAndTimers(deleteFile: true)
        }
        
        do {
            try audioSession.activateForPlayingAndRecording()
        } catch {
            invalidateRecorder(error: .cantActivateAudioSession)
        }
        
        do {
            let recorder = try AVAudioRecorder(directory: item.directory, filenameWithoutExtension: item.fileID.uuidString)
            
            let tickTimer = Timer(timeInterval: timeUpdateFrequency, repeats: true) { [weak self] _ in
                self?.recordingTimerTick()
            }
            let maxDurationTimer = Timer(timeInterval: acceptedDurations.upperBound, repeats: false) { [weak self] _ in
                self?.reachedMaxDuration()
            }
            
            ongoingRecording = OngoingRecording(
                item: item,
                recorder: recorder,
                timeStatusUpdateTimer: tickTimer,
                maxRecordingDurationTimer: maxDurationTimer,
                acceptedDurations: acceptedDurations
            )
            status = .recording
            
            // Not using recorder.record(forDuration:) because the audioRecorderDidFinishRecording callback comes after a few seconds after max duration is reached and I'm not sure why.
            // With a custom timer (maxDurationTimer) we stop the recording manually, and the callback comes right away.
            let startedRecording = recorder.record()
            if !startedRecording {
                print("didn't start recording")
                throw AudioRecorderError.cantRecord
            }
            
            print("STARTED RECORDING \(Date().timeIntervalSince1970)")

            RunLoop.main.add(tickTimer, forMode: .common)
            RunLoop.main.add(maxDurationTimer, forMode: .common)
        }
        catch {
            print(error, error.localizedDescription)
            if let recorderError = error as? AudioRecorderError {
                invalidateRecorder(error: recorderError)
            } else {
                invalidateRecorder(error: .other(error))
            }
        }
        delegate?.stateDidChange(.all, in: self)
    }
    
    public func discard() {
        invalidateRecorder(error: nil)
    }

    public func stop() {
        guard status.isRecording else { return }
        if let ongoingRecording = ongoingRecording {
            // recorder.currentTime is only available while the recording is active.
            // it won't be readable after the file is saved.
            // so capturing the value here for later use
            status = .saving(duration: ongoingRecording.recorder.currentTime)
            ongoingRecording.stopRecorderAndTimers(deleteFile: false)
        }
        // audioRecorderDidFinishRecording will be called asynchronously
    }
    
    // MARK: -
    
    private func recordingTimerTick() {
        guard status.isRecording else { return }
        delegate?.stateDidChange(.timeStatus, in: self)
    }
    
    private func reachedMaxDuration() {
        print("reachedMaxDuration \(Date().timeIntervalSince1970)")

        // If you're ok with ending up with a slightly shorter recording
        // (fx instead of 20s - 19.9s)
        // can remove this logic and just call stop() immediately
        
        guard let ongoingRecording = ongoingRecording else { return }
        let elapsed = ongoingRecording.recorder.currentTime
        let remaining = ongoingRecording.acceptedDurations.upperBound - elapsed
        if remaining > 0 {
            print("maxDuration timer fired a little too early, remaining: \(remaining)")
            DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
                self.stop()
            }
        } else {
            stop()
        }
    }
    
    private func invalidateRecorder(error: AudioRecorderError?) {
        if let ongoingRecording = ongoingRecording {
            ongoingRecording.stopRecorderAndTimers(deleteFile: true)
            self.ongoingRecording = nil // also stops receiving delegate calls from the recorder
        }
        if let error = error {
            status = .failed(error)
        } else {
            status = .idle
        }
        delegate?.stateDidChange(.recordingStatus, in: self)
    }
}

extension SystemAudioRecorderIntegration: AudioSessionManagerDelegate {
    func audioSessionManager(_ audioSessionManager: AudioSessionManager, didReceiveInterruption type: AudioSessionManager.Interruption) {
        switch type {
            case .began:
                self.stop()
            case .ended(_):
                // since we are recording only short clips of audio, resuming recording doesn't make sense
                break
        }
    }

    func audioSessionManagerDidResetMediaServices(_ audioSessionManager: AudioSessionManager) {
        // The existing recorder object is not usable anymore
        invalidateRecorder(error: .mediaServicesReset)
    }
}

extension SystemAudioRecorderIntegration: AVAudioRecorderDelegate {
    
    /* audioRecorderDidFinishRecording:successfully: is called when a recording has been finished or stopped. This method is NOT called if the recorder is stopped due to an interruption. */
    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard recorder == ongoingRecording?.recorder else { return }
        
        print("audioRecorderDidFinishRecording \(Date().timeIntervalSince1970), \(status), \(flag)")
        guard case .saving(let duration) = status, flag else {
            invalidateRecorder(error: .finishedUnexpectedly)
            return
        }
        status = .saved(RecordedFile(fileURL: recorder.url, duration: duration))
        delegate?.stateDidChange(.recordingStatus, in: self)
    }
    
    /* if an error occurs while encoding it will be reported to the delegate. */
    public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        guard recorder == ongoingRecording?.recorder else { return }

        print("audioRecorderEncodeErrorDidOccur", error as Any)
        invalidateRecorder(error: .encodingError(error))
        delegate?.stateDidChange(.recordingStatus, in: self)
    }
}

// MARK: -

public enum AudioRecorderError: Error {
    case cantActivateAudioSession
    case cantInit(Error)
    case cantPrepare
    case cantRecord
    case noMicrophonePermissionPermission
    case encodingError(Error?)
    case finishedUnexpectedly
    case mediaServicesReset
    case other(Error)
}

extension AVAudioRecorder {
    
    convenience init(directory: URL, filenameWithoutExtension: String) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        /// file extension has to match what's in AVFormatIDKey
        let url = directory.appendingPathComponent(filenameWithoutExtension + ".m4a")
        
        do {
            try self.init(url: url, settings: settings)
        } catch {
            throw AudioRecorderError.cantInit(error)
        }
                
        if !self.prepareToRecord() {
            throw AudioRecorderError.cantPrepare
        }
    }
}
