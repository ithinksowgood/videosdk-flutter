## v3.12.1

**Release Date**: 20th August 2026

**Change Log** :

**Bug Fixes:**

- **Android builds no longer need any manual setup.** Building an app for Android could fail in Gradle with a `compileSdkVersion` error, Android builds now work directly after `flutter pub get`, on developer machines and CI alike.

- **Prepared the Android build for Android Gradle Plugin 9.** The SDK now applies the Kotlin Gradle plugin only when AGP is not compiling Kotlin itself, so it keeps building on both current and upcoming AGP versions. No change is needed in your app.

> The SDK's own Android sources now compile against Java 17. Your app's `compileOptions` are unaffected — apps building at Java 11 or Java 8 continue to work unchanged.

## v3.12.0

**Release Date**: 18th August 2026

**Change Log** :

### Meeting actions now report an error instead of doing nothing

Calling a meeting action before the meeting is joined, or while it is reconnecting, is now rejected and reported through `Events.error`. This covers `Room`, `Participant`, `Stream`, `PubSub`, `RealtimeStore` and `Character`.

- Before the meeting is joined, and after it is left or ended: `ERROR_ACTION_PERFORMED_BEFORE_MEETING_JOINED` (`3022`)
- While reconnecting: `ERROR_MEETING_RECONNECTING` (`3027`)
- **`leave()` is never blocked** — it works while the meeting is still connecting and while it is reconnecting, so you can always get out. `end()` works while connecting, but not while reconnecting, because closing the meeting for everyone needs a working connection.

### New `RoomState.failed`

Delivered through `Events.roomStateChanged` when a join could not be set up at all — a rejected token, or meeting settings that could not be fetched. Unlike `reconnecting`, nothing retries it; call `join()` again to start a fresh attempt.

> Breaking: if you `switch` over `RoomState` without a `default` branch, add `case RoomState.failed:` when upgrading.

### Fixes

- **`leave()` no longer hangs when the connection drops.** Calling `leave()` while the meeting was reconnecting never finished — the camera and microphone stayed on and `Events.roomLeft` never fired, so the app was stuck on the meeting screen. Leaving now completes immediately, whatever the connection is doing.

- **Actions called before join no longer crash.** `participant.pin()`, `unpin()` and the `realtimeStore` methods report the error instead of throwing.

## v3.11.0

**Release Date**: 11th August 2026

**Change Log** :

### Your camera & microphone settings now stay applied for the whole meeting

Earlier, the settings you chose while creating a camera or microphone track were applied only the first time. Whenever the SDK needed to recreate the track, it went back to its own defaults (720p video, `speech_standard` audio, front camera, no noise settings). So a participant who joined at 1080p could end up sending 720p video after simply turning the camera off and on again.

Your chosen settings are now remembered and re-applied every time. This covers:

- **Camera**: selected camera, `encoderConfig` (resolution/quality), `multiStream`, `bitrateMode`, `maxLayer` and `facingMode`.
- **Microphone**: selected microphone, `encoderConfig` (audio quality) and `noiseConfig`.

`codec` is the one exception — it follows what the meeting can actually carry. If a participant joins who cannot decode your selected codec, the camera falls back to VP8 and stays there for the rest of the meeting, even if that participant leaves.

Settings are preserved across all of these:

- `disableCam()` → `enableCam()` and `muteMic()` → `unmuteMic()`
- `changeCam()` / `changeMic()` when switching to another device
- Automatic reconnection after a network drop
- Automatic recovery when a camera or microphone stops (device unplugged, or taken over by another app)
- `changeMode()` between `SEND_AND_RECV`, `RECV_ONLY`

If you pass a new `CustomTrack` to `enableCam()`, `unmuteMic()`, `changeCam()` or `changeMic()`, that track's settings become the remembered settings from that point on.

### Fixes

- **A new track no longer changes the quality of a track that is already being sent.** The selected `bitrateMode` was shared across tracks, so creating a second track with a different mode changed the quality of the video already going out. Each track now uses only the mode you set for it.

- **Your `multiStream` choice is no longer lost.** If the video codec in use could not send multiple quality layers, `multiStream` stayed switched off for the rest of the meeting. Your choice is now remembered and applied again automatically once the codec allows it.

- **Unmuting works even if the microphone was released earlier.** If something else had taken the microphone away — another app, or the participant changing mode — unmuting could fail to bring it back. The SDK now creates a fresh microphone with your saved settings.

- **The same codec warning is no longer repeated.** The warning about multiple quality layers not being supported by the selected codec was raised again on every camera on/off. It is now raised only when you supply a track yourself.

- **The camera and microphone no longer switch off on their own.** When the SDK replaces the camera or mic stream (codec change, device switch, reconnect), the old stream sends a "stopped" notice. That notice was treated as "the user's camera stopped", so the camera turned off right after turning on. Each notice is now matched to the stream it belongs to.

- **The camera no longer restarts twice.** The SDK turns the camera off and on again automatically when it must re-send video in a different codec. If two participants who need that change joined at nearly the same moment, this ran twice — other participants saw the video freeze for about twice as long. Only one restart now runs at a time.

- **Running more than one meeting in the same app shows the correct camera/mic state.** Camera and mic on/off state was shared between meetings, so one meeting could report the other's state. Each meeting now keeps its own — this also fixes wrong state when leaving and rejoining quickly.

- **A muted microphone or camera works again after a mode change.** If the mic (or camera) was off when `changeMode()` was called, the SDK released it but still held on to the released one and tried to reuse it. Unmuting afterwards showed the mic as ON while no one could hear the participant. A fresh microphone/camera is now always created.

- **Invalid `maxLayer` values are handled safely.** Values outside `1`–`3` are adjusted to the nearest valid value instead of producing a broken video configuration.


## v3.10.1

**Release Date**: 24th July 2026

**Change Log** :

- Removed the third-party dependency to resolve limitation of flutter sdk version.


## v3.10.0

**Release Date**: 7th July 2026

**Change Log** :

- Added support for **selectable video codecs** in `createCameraVideoTrack()`. The `codec` option supports `VP8`, `VP9`, `AV1`, and `H264` through `VideoCodec`.


## v3.9.1

**Release Date**: 12th May 2026

- Resolved an internal bug.

## v3.9.0

**Release Date**: 13th April 2026

**Change Log** :

- Added `Events.agentMetrics` event on `AgentParticipant` for receiving real-time agent metrics data.
- Improved room joining time.
- Improved performance by offloading heavy processing to background threads.

## v3.8.0

**Release Date**: 18th Mar 2026

**Change Log** :

- Introduced `AgentParticipant`, a dedicated participant type for AI agents within a room.
  - Agents can be identified using the `isAgent` property when they join.
- Added `AgentState` enum (`IDLE`, `LISTENING`, `THINKING`, `SPEAKING`) to represent the agent lifecycle.
- Added event listeners for agent updates:
  - `Events.agentStateChanged` to track state transitions.
  - `Events.agentTranscriptionReceived` to receive real-time transcription.
- Updated internal dependencies.

## v3.7.0

**Release Date**: 20th Feb 2026

**Change Log** :

- Introduced the `setLogLevel` method in `VideoSDK`, enabling developers to control log verbosity. This improves debugging efficiency during development.

## v3.6.1

**Release Date**: 9th Feb 2026

**Change Log** :

- Updated the official Dart API Reference for the Flutter VideoSDK package.

## v3.6.0

**Release Date**: 5th Feb 2026

**Change Log** :

- Introduced an autoConsume boolean parameter to the createRoom method. Also introduced methods in the `Participant` class to `start` and `stop` consuming participant streams.
- Updated the official Dart API Reference for the Flutter VideoSDK package.

**Bug Fix** :
- Resolved an audio distortion issue (chipmunk effect) occurring with Bluetooth output devices such as AirPods.
- Fixed a Windows build error affecting Flutter desktop builds.
- Resolved an issue related to switching external `Camera` and `Microphone` devices on the web.
- Updated Internal Dependencies.
- Fixed an issue that caused video streams to not render when multiple participants were present in a meeting on `macOS`.

## v3.5.1

**Release Date**: 20th Jan 2026

- Updated internal dependencies.

## v3.5.0

**Release Date**: 06th Jan 2026

- Added `Realtime Store functionality` to store, update, retrieve, and observe custom key-value data in real time during a meeting
- Fixed an iOS issue with switching audio output devices.

## v3.4.0

**Release Date**: 31st Dec 2025

- Updated the default encoderConfig value in `createCameraVideoTrack()` to `h720p_w1280p`.

- Introduces advanced video track optimization features, enabling greater flexibility and control over quality and bandwidth. Below are the new parameters added to `createCameraVideoTrack()`.
  -  `BitrateMode`
      - Added the `BitrateMode` parameter to manage video quality and bandwidth usage easily.
      - Developers can now select from three modes based on their requirements:
          - bandwidth_optimized
          - balanced (default)
          - high_quality

  - `maxLayer`
      - Introduced the `maxLayer` parameter to allow developers to specify the maximum number of simulcast layers published for a video track.

- Added a `quality-limitation` Event on the `Room`class, enabling detection and handling of quality constraints caused by bandwidth limitations, network congestion, or CPU pressure.

- Introduced a `stream-state` Event on the `Stream` class to track video and screen-share stream lifecycle states, including active, stuck, freeze-detected, and ended.

## v3.3.0

**Release Date**: 12th Dec 2025

- Introduced Adaptive Subscription Manager feature, allowing dynamic management of participant subscriptions based on network conditions and application requirements.

## v3.2.0

**Release Date** : 6th Nov 2025

**Change Log** :

- Introduced two new methods — `pause()` and `resume()` — enabling developers to pause and resume active streams.
- Added a new `LeaveReason` enum to show specific `reason`in roomLeft and participantLeft event.

**Bug Fix** :
- Resolved an issue where acknowledgment events were not properly handled in the Pin-State system.
- Fixed a bug causing random resolutions to be used after setting a custom track, ensuring consistent video quality as defined by the user.

## v3.1.0

**Release Date** : 17th Oct 2025

**Change Log** :

- On the web, the microphone will now be muted when the input audio device is disconnected. Users will need to unmute it to continue.

**Bug Fix** :
- Fixed issues in Multistream.

## v3.0.0

**Release Date** : 19th Sept 2025

**Change Log** :

- Updated internal dependencies.
- Enabled system audio sharing while screen sharing on Android.
- Added Reason map on `participantleft` event
- Enabled background camera access on iOS for Picture-in-Picture (PiP) mode.

**Bug Fix** :
- Fixed issues with room stats on Android, iOS, and macOS.


## v2.3.1

**Release Date** : 4th July 2025

**Change Log** :

- Enhanced the E2EE feature by introducing participant-wise encryption.


## v2.3.0

**Release Date** : 30th May 2025

**Change Log** :

- Added `captureImage` method in the `Participant` class to capture the image of the user from MediaStream.
- Added methods `uploadBase64File` and `fetchBase64File` in `Room` class to upload and download a temporary file.

## v2.2.0

**Release Date** : 16th May 2025

**Change Log** :

- Introduced two new features to enhance the Interactive Livestream (ILS) experience:
1. **Fast Channel Switching** – New Fast Channel Switching feature enables instant transitions between live streams with minimal latency.
2. **Media Relay Support** – Introducing Relay Media, enabling hosts to share their media (audio, video, screen) with other live streams. Perfect for creating engaging "PK battles" and collaborative broadcasts.

## v2.1.2

**Release Date** : 29th April 2025

**Bug Fix** :

- Fixed an issue where multiStream wasn’t working properly, making multiple streams work as expected.

## v2.1.1

**Release Date** : 17th April 2025

**Bug Fix** :

- Fixed End-to-End Encryption (E2EE) for web.

**Change Log** :

- Added `pauseAllStreams()`  and `resumeAllStreams()`  method to pause/resume all remote participant's media streams (audio, video, and screen share) or a specific stream type if provided.

## v2.1.0

**Release Date** : 11th April 2025

**Change Log** :

- Introduced **End-to-End Encryption (E2EE)** support to ensure secure media transmission, where media streams are fully encrypted between participants without any server-side access.


## v2.0.0

**Release Date** : 1st April 2025

**Change Log** :

1. Enhanced Room/Meeting Connection Flow: 
  - A `RECONNECTING` state has been introduced that activates if the network connection is lost during a meeting. The SDK will automatically try to rejoin, enhancing reliability. 
  - The `FAILED`, `CLOSING`, and `CLOSED` states have been eliminated. All disconnection scenarios will now be managed by the `DISCONNECTED` state for a more streamlined experience.

## v1.3.2+1

**Release Date** : 31st March 2025

**Change Log** :

1. Updated internal dependencies.

## v1.3.1

**Release Date** : 25th February 2025

**Change Log** :

1. Updated internal dependencies.

## v1.3.0

**Release Date** : 22nd January 2025

**Change Log** :

1. Deprecated Modes: Replaced `CONFERENCE` with `SEND_AND_RECV` and `VIEWER` with `SIGNALLING_ONLY`.
2. New Mode: Added `RECV_ONLY` for live streaming, allowing participants to receive media without sending it.
3. Role Switching: Enabled seamless role switching between `SEND_AND_RECV` (host) and `RECV_ONLY` (audience) using `changeMode()` method.

## v1.2.5

**Release Date** : 18th December 2024

**Bug Fix**:

1. Fixed issues related to Flutter version 3.27.

**Change Log** :

1. Updated internal dependencies.


## v1.2.4

**Release Date** : 17th December 2024

**Change Log** :

1. Added `roomStateChanged` Event.


## v1.2.3

**Release Date** : 24th October 2024

**Change Log** :

1. Dependencies updated to latest version.

2. Provided event `onUserMessage` in `Character` class.


## v1.2.2

**Release Date** : 23rd September 2024

**Change Log** :

1. Provided methods and events for Whiteboard Management.


## v1.2.1

**Release Date** : 13th August 2024

**Change Log** :

1. Added support for CharacterSDK.


## v1.2.0+1

**Release Date** : 8th August 2024

**Change Log** :

1. Removed support for facingMode in desktop based applications.

2. Changed value of facingMode enum from `front` to `user`.


## v1.2.0

**Release Date** : 7th August 2024

**Change Log** :

1. Removed methods `getMics`, `getCameras` and `getAudioOutputDevices` of the `Room` class.

2. Changed return type of `createMicrophoneAudioTrack()` and `createCameraVideoTrack()` methods from CustomTrack to CustomTrack?.

3. Changed parameter type of `changeMic()`, `changeCam()` and `switchAudioDevice()` methods.

4. Improved error handling and emitting more precise errors on the event.

5. Changed type of post transcription config parameter in `startRecording()`, `startHls()` and `startLivesStream()` methods.

6. Changed type of transcription config parameter in `startTranscription()` method.

7. Provided debugMode parameter in `createRoom()` method for enabling users to view detailed error logs directly on the VideoSDK's dashboard and changed parameter type of facingMode.


## v1.1.13

**Release Date** : 17th July 2024

**Change Log** :

1. Added support for Custom Video Processors in iOS and Android.


## v1.1.12

**Release Date** : 31st May 2024

**Change Log** :

1. Provided getter for selected Audio Output Device as `selectedSpeakerId`.

2. Provided Built-In Receiver(Earpiece) support for iOS Devices.

3. Provided `transcription` parameter in `startLivestream()` method of the `Room` class.


**Bug Fix** :

1. Fixed bugs in getters of selected Audio Input(`selectedMicId`) and Video (`selectedCamId`) Devices.

2. Triggered the `streamdisabled` event of the participant object when a participant leaves the meeting.

3. Fixed an issue where users were unable to join meetings without media permissions.

4. Disposed media tracks for the Firefox browser in `getVideoDevices()` and `getAudioDevices()` methods.

## v1.1.11+1

**Release Date** : 21th May 2024

**Bug Fix** :

1. Changed the default value of preferredProtocol

## v1.1.11

**Release Date** : 20th May 2024

**Change Log** :

1. Provide Pre-Call Screen's features.
2. Provide `signalingBaseUrl` parameter in `createRoom()` method of VideoSDK class to enable the usage of a proxy server with the VideoSDK.
3. Provide `preferredProtocol` parameter in `createRoom()` method of VideoSDK class to select protocol for media transportion.

**Bug Fix** :

1. Fixed an issue related to switch audio device for Web.
2. Fixed an issue related to micEnabled and camEnabled getters.

## v1.1.10

**Release Date** : 6th May 2024

**Change Log** :

1. Added support for post and realtime transcription feature

**Bug Fix** :

1. Fixed an issue related to video and screenShare for firefox browser

## v1.1.9

**Release Date** : 25th Apr 2024

**Bug Fix** :

1. Fixed voice coming from earpiece issue for iOS.
2. Fixed not able to start screenShare issue for android 14

**Change Log** :

1. Upgraded internal dependencies

## v1.1.8

**Release Date** : 5th Apr 2024

**Bug Fix** :

1. Fixed Rendering issue with Windows Platform.

## v1.1.7

**Release Date** : 27th Oct 2023

**Change Log** :

1. Added metaData property associated with Participant to pass additional information.
2. Added payload feature in PubSub to pass additional payload data.
3. Added sendOnly feature to PubSub to Publish data for only Participants mentioned.

## v1.1.6

**Release Date** : 18th Sep 2023

**Bug Fix** :

1.  Fixed issues with mediaConstraints on the arm64-v8a and x86_64 architectures.[below Android version 10]

## v1.1.5

**Release Date** : 8th Aug 2023

**Change Log** :

1. Internal improvements

**Bug Fix** :

1.  Fixed issues related to audio while toggling

## v1.1.4+1

**Release Date** : 27th July 2023

**Bug Fix** :

1. Fixed audio issue with some devices

## v1.1.4

**Release Date** : 17th July 2023

**Change Log** :

1. Upgraded internal dependencies

**Bug Fix** :

1. Fixed mic state issue
2. Fixed crash issue for below Android 10
3. Fixed issue with screen share foreground service

## v1.1.3

**Release Date** : 2nd June 2023

**Bug Fix** :

1. Fixed VideoSDK Stats issues with latest chrome browser

## v1.1.2

**Release Date** : 19th May 2023

**Change Log** :

1. Added `screenShare` feature support for flutter Windows
2. Added `getScreenShareSources()` method for Desktop Apps

## v1.1.1

**Release Date** : 17th May 2023

**Change Log** :

1. Added `screenShare` feature support for flutter web & macOS
2. Added error code for screenShare permission denied error

**Bug Fix** :

1. Fixed `onPresenterChanged `event on presenter-left

## v1.1.0

**Release Date** : 25th Apr 2023

**Change Log** :

1. Added **Beta** support for Mac and Windows Platforms
2. Added **Beta** support for Flutter Web Platform

## v1.0.13+1

**Release Date** : 14th Apr 2023

**Bug Fix** :

1. Improved Audio Quality
2. Improved SDK Performance

## v1.0.13

**Release Date** : 1st Apr 2023

**Change Log** :

1. `HLS_PLAYABLE` state added in the `hlsStateChanged`.
2. `hlsUrls` getter added in the `Room`.

## v1.0.12

**Release Date** : 24rd Mar 2023

**Change Log** :

1. `pin()` added to pin a participant.
2. `unpin()` added to unpin a participant.
3. `changeMode()` allows the participant to switch mode between `CONFERENCE` and `VIEWER`.

## v1.0.11

**Release Date** : 03rd Mar 2023

**Bug Fix** :

1. Fixed room not closing if `leave()` called before meeting is joined.
2. Internal dependencies updated.

## v1.0.10

**Release Date** : 03rd Jan 2023

**Change log** :

1. Added `getVideoStats()`, `getAudioStats()` and `getShareStats()` to get the statistics for the video, audio and share stream of a participant.

## 1.0.9

- Added support for custom audio and video tracks.
- Added events for recording, live streaming and HLS status.
- Added event for participant notifying the change in video quality.
- Added `startHls()` and `stopHls()` methods.
- Updated `startRecording()` and `startLiveStream()` to accept `config` values for the feed.
- Fixed `unable to start video or mic` after turning them off.

## 1.0.8

- Added new flag `multiStream` for `createRoom()`

## 1.0.7

- Updated Gradle Version for Android

## 1.0.6

- Added ErrorEvents for Room.

- Fixed crash on `end()`, when the room is not joined yet.

## 1.0.5

- Added support for iOS ScreenSharing.

## 1.0.4

- Added support for changing audio device.

- Fixed issue: PrintDevLog issue

## 1.0.3

- Fixed issue: VideoRenderer.onFirstFrameRendered implementation.

## 1.0.2

- Fixed issue on room ends.
- Provides reason on room left.

## 1.0.1

- Fixed change webcam issue

## 1.0.0

- Renamed `Meeting` class to `Room` class.
- Changed import file `package:videosdk/rtc.dart` to `package:videosdk/videosdk.dart`
- Changed events:

  - `Events.meetingJoined` to `Events.roomJoined`
  - `Events.meetingLeft` to `Events.roomLeft`
  - `Events.webcamRequested` to `Events.cameraRequested`
    Changed properties and methods for `Room` class
  - `selectedWebcamId` to `selectedCamId`
  - `enableWebcam()` to `enableCam()`
  - `disableWebcam()` to `disableCam()`
  - `changeWebcam()` to `changeCam()`
  - `getWebcams()` to `getCameras()`
    Changed methods for `Participant` class
  - `enableMic()` to `unmuteMic()`
  - `disableMic()` to `muteMic()`
  - `enableWebcam()` to `enableCam()`
  - `disableWebcam()` to `disableCam()`

- Added `VideoSDK.createRoom()` to create VideoSDK Rooms. Use `join()` to join VideoSDK Room.
- Added `defaultCameraIndex` option to select default camera for `Room` Class.
- Added `micEnabled` property for `Room` Class.
- Added `camEnabled` property for `Room` Class.
- Added `end()` method for `Room` Class.
- Removed `MeetingBuilder` Widget.
- Fixed the issue of joining room (meeting) multiple time.
- Fixed issues related to resource consumption.

## 0.0.14

- `setViewport()` added for participant webcam streams

## 0.0.13

- Added support for region wise baseUrls
- Added support for Android 12
- Added support for custom ice-servers
- Performance improvements

## 0.0.12

- iOS mic issue resolved
- entry request event handled

## 0.0.11

- Handle Entry Request

## 0.0.10

- PubSub Message
- custom participnatId

## 0.0.9

- Android Screen Share
- Events Enums

## 0.0.8

- Added fix for Mic / Webcam enable request

## 0.0.7

- Participant can pause or resume all video, audio and shareshare streams.
- Participant can set quality of video stream of other participant.

## 0.0.6

- Participant can request to turn on any participants' webcam or mic and can turn off the same
- Participant can remove another participant from meeting.

## 0.0.5

- livestream, recording, change webcam, active speaker and presenter indication, remote share streams and example code improved

## 0.0.4

- example app, pub description added.

## 0.0.3

- Installation steps added for android in `README` file.

## 0.0.2

- Exporting Meeting, Participant, Stream classes and MeetingBuilder widget.

## 0.0.1

- videosdk rtc meeting library initial release.
