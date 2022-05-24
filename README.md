![logo](Images/original-horizontal.png)

# SwiftAudio

SwiftAudio is an audio player written in Swift, making it simpler to work with audio playback from streams and files.

## Example

To see the audio player in action, run the example project!
To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements
iOS 13.0+

## Installation

### Swift Package Manager
[Swift Package Manager](https://swift.org/package-manager/) (SwiftPM) is a tool for managing the distribution of Swift code as well as C-family dependency. From Xcode 11, SwiftPM got natively integrated with Xcode.

SwiftAudio supports SwiftPM from version 0.12.0. To use SwiftPM, you should use Xcode 11 to open your project. Click `File` -> `Swift Packages` -> `Add Package Dependency`, enter [SwiftAudio repo's URL](https://github.com/DoubleSymmetry/SwiftAudio.git). Or you can login Xcode with your GitHub account and just type `SwiftAudio` to search.

After select the package, you can choose the dependency type (tagged version, branch or commit). Then Xcode will setup all the stuff for you.

If you're a framework author and use SwiftAudio as a dependency, update your `Package.swift` file:

```swift
let package = Package(
    // 0.12.0 ..< 1.0.0
    dependencies: [
        .package(url: "https://github.com/DoubleSymmetry/SwiftAudio.git", from: "0.12.0")
    ],
    // ...
)
```

## Usage

### AudioPlayer
To get started playing some audio:
```swift
let player = AudioPlayer()
let audioItem = DefaultAudioItem(audioUrl: "someUrl", sourceType: .stream)
player.load(item: audioItem, playWhenReady: true) // Load the item and start playing when the player is ready.
```

To listen for events in the `AudioPlayer`, subscribe to events found in the `event` property of the `AudioPlayer`.
To subscribe to an event:
```swift
class MyCustomViewController: UIViewController {

    let audioPlayer = AudioPlayer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        audioPlayer.event.stateChange.addListener(self, handleAudioPlayerStateChange)
    }
    
    func handleAudioPlayerStateChange(state: AudioPlayerState) {
        // Handle the event
    }
}
```

#### QueuedAudioPlayer
The `QueuedAudioPlayer` is a subclass of `AudioPlayer` that maintains a queue of audio tracks.
```swift
let player = QueuedAudioPlayer()
let audioItem = DefaultAudioItem(audioUrl: "someUrl", sourceType: .stream)
player.add(item: audioItem, playWhenReady: true) // Since this is the first item, we can supply playWhenReady: true to immedietaly start playing when the item is loaded.
```

When a track is done playing, the player will load the next track and update the queue.

##### Navigating the queue
All `AudioItem`s are stored in either `previousItems` or `nextItems`, which refers to items that come prior to the `currentItem` and after, respectively. The queue is navigated with:
```swift
player.next() // Increments the queue, and loads the next item.
player.previous() // Decrements the queue, and loads the previous item.
player.jumpToItem(atIndex:) // Jumps to a certain item and loads that item.
```

##### Manipulating the queue
```swift
 player.removeItem(at:) // Remove a specific item from the queue.
 player.removeUpcomingItems() // Remove all items in nextItems.
```

### Configuring the AudioPlayer
Current options for configuring the `AudioPlayer`:
- `bufferDuration`: The amount of seconds to be buffered by the player.
- `timeEventFrequency`: How often the player should call the delegate with time progress events.
- `automaticallyWaitsToMinimizeStalling`: Indicates whether the player should automatically delay playback in order to minimize stalling.
- `volume`
- `isMuted`
- `rate`
- `audioTimePitchAlgorithm`: This value decides the `AVAudioTimePitchAlgorithm` used for each `AudioItem`. Implement `TimePitching` in your `AudioItem`-subclass to override individually for each `AudioItem`.

Options particular to `QueuedAudioPlayer`:
- `repeatMode`: The repeat mode: off, track, queue

### Audio Session
Remember to activate an audio session with an appropriate category for your app. This can be done with `AudioSessionController`:
```swift
try? AudioSessionController.shared.set(category: .playback)
//...
// You should wait with activating the session until you actually start playback of audio.
// This is to avoid interrupting other audio without the need to do it.
try? AudioSessionController.shared.activateSession()
```

**Important**: If you want audio to continue playing when the app is inactive, remember to activate background audio:
App Settings -> Capabilities -> Background Modes -> Check 'Audio, AirPlay, and Picture in Picture'.

#### Interruptions
If you are using the `AudioSessionManager` for setting up the audio session, you can use it to handle interruptions too.
Implement `AudioSessionManagerDelegate` and you will be notified by `handleInterruption(type: AVAudioSessionInterruptionType)`.
If you are storing progress for playback time on items when the app quits, it can be a good idea to do it on interruptions as well.

### Remote Commands
To enable remote commands for the player you need to populate the RemoteCommands array for the player:
```swift
audioPlayer.remoteCommands = [
    .play,
    .pause,
    .skipForward(intervals: [30]),
    .skipBackward(intervals: [30]),
  ]
```

#### Custom handlers for remote commands
To supply custom handlers for your remote commands, just override the handlers contained in the player's `RemoteCommandController`:
```swift
let player = QueuedAudioPlayer()
player.remoteCommandController.handlePlayCommand = { (event) in
    // Handle remote command here.
}
```
All available overrides can be found by looking at `RemoteCommandController`.

### Start playback from a certain point in time
Make your `AudioItem`-subclass conform to `InitialTiming` to be able to start playback from a certain time.

## Author

Jørgen Henrichsen

## License

SwiftAudio is available under the MIT license. See the LICENSE file for more info.
