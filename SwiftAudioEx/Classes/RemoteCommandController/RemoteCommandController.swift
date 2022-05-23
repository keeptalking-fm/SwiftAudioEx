//
//  File.swift
//  SwiftAudio
//
//  Created by Jørgen Henrichsen on 20/03/2018.
//

import Foundation
import MediaPlayer

public protocol RemoteCommandable {
    func getCommands() ->  [RemoteCommand]
}

public class RemoteCommandController {
        
    private let center: MPRemoteCommandCenter
    
    weak var audio: AudioPlayerIntegration?
    
    var commandTargetPointers: [String: Any] = [:]
    private var enabledCommands: [RemoteCommand] = []

    /**
     Create a new RemoteCommandController.
     
     - parameter remoteCommandCenter: The MPRemoteCommandCenter used. Default is `MPRemoteCommandCenter.shared()`
     */
    public init(remoteCommandCenter: MPRemoteCommandCenter = MPRemoteCommandCenter.shared()) {
        center = remoteCommandCenter
    }
    
    internal func enable(commands: [RemoteCommand]) {
        let commandsToDisable = enabledCommands.filter { command in
            !commands.contains(where: { $0.description == command.description })
        }

        enabledCommands = commands
        commands.forEach { self.enable(command: $0) }
        disable(commands: commandsToDisable)
    }
    
    internal func disable(commands: [RemoteCommand]) {
        commands.forEach { self.disable(command: $0) }
    }
    
    private func enableCommand<Command: RemoteCommandProtocol>(_ command: Command) {
        center[keyPath: command.commandKeyPath].isEnabled = true
        center[keyPath: command.commandKeyPath].removeTarget(commandTargetPointers[command.id])
        commandTargetPointers[command.id] = center[keyPath: command.commandKeyPath].addTarget(handler: self[keyPath: command.handlerKeyPath])
    }
    
    private func disableCommand<Command: RemoteCommandProtocol>(_ command: Command) {
        center[keyPath: command.commandKeyPath].isEnabled = false
        center[keyPath: command.commandKeyPath].removeTarget(commandTargetPointers[command.id])
        commandTargetPointers.removeValue(forKey: command.id)
    }
    
    private func enable(command: RemoteCommand) {
        switch command {
        case .play: self.enableCommand(PlayBackCommand.play)
        case .pause: self.enableCommand(PlayBackCommand.pause)
        case .stop: self.enableCommand(PlayBackCommand.stop)
        case .togglePlayPause: self.enableCommand(PlayBackCommand.togglePlayPause)
        case .next: self.enableCommand(PlayBackCommand.nextTrack)
        case .previous: self.enableCommand(PlayBackCommand.previousTrack)
        case .changePlaybackPosition: self.enableCommand(ChangePlaybackPositionCommand.changePlaybackPosition)
        case .skipForward(let preferredIntervals): self.enableCommand(SkipIntervalCommand.skipForward.set(preferredIntervals: preferredIntervals))
        case .skipBackward(let preferredIntervals): self.enableCommand(SkipIntervalCommand.skipBackward.set(preferredIntervals: preferredIntervals))
        case .like(let isActive, let localizedTitle, let localizedShortTitle):
            self.enableCommand(FeedbackCommand.like.set(isActive: isActive, localizedTitle: localizedTitle, localizedShortTitle: localizedShortTitle))
        case .dislike(let isActive, let localizedTitle, let localizedShortTitle):
            self.enableCommand(FeedbackCommand.dislike.set(isActive: isActive, localizedTitle: localizedTitle, localizedShortTitle: localizedShortTitle))
        case .bookmark(let isActive, let localizedTitle, let localizedShortTitle):
            self.enableCommand(FeedbackCommand.bookmark.set(isActive: isActive, localizedTitle: localizedTitle, localizedShortTitle: localizedShortTitle))
        }
    }
    
    private func disable(command: RemoteCommand) {
        switch command {
        case .play: self.disableCommand(PlayBackCommand.play)
        case .pause: self.disableCommand(PlayBackCommand.pause)
        case .stop: self.disableCommand(PlayBackCommand.stop)
        case .togglePlayPause: self.disableCommand(PlayBackCommand.togglePlayPause)
        case .next: self.disableCommand(PlayBackCommand.nextTrack)
        case .previous: self.disableCommand(PlayBackCommand.previousTrack)
        case .changePlaybackPosition: self.disableCommand(ChangePlaybackPositionCommand.changePlaybackPosition)
        case .skipForward(_): self.disableCommand(SkipIntervalCommand.skipForward)
        case .skipBackward(_): self.disableCommand(SkipIntervalCommand.skipBackward)
        case .like(_, _, _): self.disableCommand(FeedbackCommand.like)
        case .dislike(_, _, _): self.disableCommand(FeedbackCommand.dislike)
        case .bookmark(_, _, _): self.disableCommand(FeedbackCommand.bookmark)
        }
    }
    
    // MARK: - Handlers
    
    public lazy var handlePlayCommand: RemoteCommandHandler = handlePlayCommandDefault
    public lazy var handlePauseCommand: RemoteCommandHandler = handlePauseCommandDefault
    public lazy var handleStopCommand: RemoteCommandHandler = handleStopCommandDefault
    public lazy var handleTogglePlayPauseCommand: RemoteCommandHandler = handleTogglePlayPauseCommandDefault
    public lazy var handleSkipForwardCommand: RemoteCommandHandler  = handleSkipForwardCommandDefault
    public lazy var handleSkipBackwardCommand: RemoteCommandHandler = handleSkipBackwardDefault
    public lazy var handleChangePlaybackPositionCommand: RemoteCommandHandler  = handleChangePlaybackPositionCommandDefault
    public lazy var handleNextTrackCommand: RemoteCommandHandler = handleNextTrackCommandDefault
    public lazy var handlePreviousTrackCommand: RemoteCommandHandler = handlePreviousTrackCommandDefault
    public lazy var handleLikeCommand: RemoteCommandHandler = handleLikeCommandDefault
    public lazy var handleDislikeCommand: RemoteCommandHandler = handleDislikeCommandDefault
    public lazy var handleBookmarkCommand: RemoteCommandHandler = handleBookmarkCommandDefault
    
    private func handlePlayCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let audio = audio {
            audio.play()
            return MPRemoteCommandHandlerStatus.success
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handlePauseCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let audio = audio {
            audio.pause()
            return MPRemoteCommandHandlerStatus.success
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handleStopCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let audio = audio {
            audio.finishPlaying()
            return .success
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handleTogglePlayPauseCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let audio = audio {
            audio.togglePlayPause()
            return MPRemoteCommandHandlerStatus.success
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handleSkipForwardCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
//        if let command = event.command as? MPSkipIntervalCommand,
//            let interval = command.preferredIntervals.first,
//            let audioPlayer = audioPlayer {
//            audioPlayer.seek(to: audioPlayer.currentTime + Double(truncating: interval))
//            return MPRemoteCommandHandlerStatus.success
//        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handleSkipBackwardDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
//        if let command = event.command as? MPSkipIntervalCommand,
//            let interval = command.preferredIntervals.first,
//            let audioPlayer = audioPlayer {
//            audioPlayer.seek(to: audioPlayer.currentTime - Double(truncating: interval))
//            return MPRemoteCommandHandlerStatus.success
//        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handleChangePlaybackPositionCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
//        if let event = event as? MPChangePlaybackPositionCommandEvent,
//            let audioPlayer = audioPlayer {
//            audioPlayer.seek(to: event.positionTime)
//            return MPRemoteCommandHandlerStatus.success
//        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handleNextTrackCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let audio = audio {
            do {
                try audio.moveToNextTrack()
                return MPRemoteCommandHandlerStatus.success
            }
            catch let error {
                return getRemoteCommandHandlerStatus(forError: error)
            }
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handlePreviousTrackCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        if let audio = audio {
            do {
                try audio.moveToPreviousTrack()
                return MPRemoteCommandHandlerStatus.success
            }
            catch let error {
                return getRemoteCommandHandlerStatus(forError: error)
            }
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
    private func handleLikeCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        MPRemoteCommandHandlerStatus.success
    }
    
    private func handleDislikeCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        MPRemoteCommandHandlerStatus.success
    }
    
    private func handleBookmarkCommandDefault(event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        MPRemoteCommandHandlerStatus.success
    }
    
    private func getRemoteCommandHandlerStatus(forError error: Error) -> MPRemoteCommandHandlerStatus {
        if let error = error as? APError.LoadError {
            switch error {
            case .invalidSourceUrl(_):
                return MPRemoteCommandHandlerStatus.commandFailed
            }
        }
        else if let error = error as? APError.QueueError {
            switch error {
            case .noNextItem, .noPreviousItem, .invalidIndex(_, _), .noNextWhenRepeatModeTrack:
                return MPRemoteCommandHandlerStatus.noSuchContent
            }
        }
        return MPRemoteCommandHandlerStatus.commandFailed
    }
    
}
