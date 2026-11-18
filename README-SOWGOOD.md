# videosdk (Flutter) 3.12.1 + SowGood's Safari and Firefox fixes

This is the published `videosdk` 3.12.1 package from pub.dev, unchanged except for:

1. `lib/src/core/webrtc/src/handlers/unified_plan.dart` `receive()`: the deprecated,
   Chrome-only `getRemoteStreams()` is tolerated when the browser has no such method
   (Safari), and the remote stream is built from the receiver's track. Without this a
   Safari viewer never gets a remote stream: the consume task throws
   `NoSuchMethodError: method not found: 'getRemoteStreams'`, the SDK's task queue
   swallows it, and the server's consumer stays orphaned (later pause/resume notices
   then hit the SDK's null-check in `consumerPaused` / `consumerResumed`).
2. `lib/src/core/webrtc/src/FlexQueue/flex_queue.dart`: a failing task is also
   `print()`ed (dart:developer's `log()` prints nothing on the web), and two hooks the
   app sets report a failed task (`sowgoodFlexTaskFailed`) or one still running after
   15 s (`sowgoodFlexTaskStalled`); exported from `lib/videosdk.dart` (2026-09-28).
3. `lib/src/core/webrtc/src/handlers/unified_plan.dart` `receive()`: the new
   transceiver is found with `transceiverWithMid()` (`transceiver_mid.dart`), which
   passes over a transceiver whose mid cannot be read, instead of `t.mid == localId`
   over the whole list; `stopReceiving()` / `stopSending()` close the media section by
   the `localId` they were given instead of reading `transceiver.mid` again. On the web
   dart_webrtc reads `mid` as `_jsTransceiver.mid!`, and Safari (iPhone 26.6.1, iPad
   18.5) threw there at the first remote mic-on after a remote mic had gone off: from
   then on every receive failed and no new remote sound reached that listener, while
   Chrome in the same room heard every cycle (2026-10-03). Test:
   `test/transceiver_mid_test.dart`.
4. `lib/src/core/webrtc/src/handlers/sdp/media_section.dart` `MediaObject.toMap()`:
   `a=extmap-allow-mixed` is written as the list sdp_transform's grammar expects (it is a
   PUSH attribute there: the parser stores a list, the writer calls `forEach` on it)
   instead of a bare `true`. Firefox puts the attribute in each media section, so the
   `send()` answer copied it, `write()` threw `forEach` on a bool, and a Firefox viewer
   who accepted the host's invitation to speak never sent mic or camera (2026-10-24,
   Firefox 158 on a Mac; Chrome puts it at the session level, which `SdpObject` drops).
   Test: `test/extmap_allow_mixed_test.dart`.
5. `lib/src/core/room/audio_html/providers/audio_html_web.dart` `startAudio()`: the
   element's `play()` is awaited inside the method, which never throws; it used to end
   in `return audioElement.play()`, the browser's own promise, and its caller does not
   await it. A rejected `play()` - Safari refusing a page's first sound without a tap
   (`NotAllowedError`), or an element stopped before it had started (`AbortError`) - was
   an unhandled promise rejection: an error with no user and no trail (2026-11-17). A
   failure goes to the hook `sowgoodAudioFailed` (`SowgoodAudioFailure`, in
   `sowgood_audio_failure.dart` - a file that imports nothing - exported from
   `lib/videosdk.dart`), or is logged when no hook is set. The failure's name is read
   from the JavaScript error object (`providers/js_error_name.dart`), with its text as
   the fallback; both readings were run in Chrome through dart2js (a refused play:
   `NotAllowedError`; one interrupted by a new source: `AbortError`). What a listener
   hears is unchanged. Test: `test/audio_failure_test.dart`.
6. The speaker (audio output) on the web: `setAudioOutputDevice()` handles the promise
   `setSinkId()` returns (same hook), and `room.dart` re-applies a speaker to each new
   remote audio element only once the member has picked one
   (`_sowgoodSpeakerChosenOnWeb`, set in `switchAudioDevice`, which on the web only the
   app calls). At join the SDK picks the first listed output for itself and re-applied
   it to every `<audio>` at every new speaker; outside a tap Safari refuses that ("A user
   gesture is required") and Chrome can abort it ("The operation could not be performed
   and was aborted"), each an unhandled rejection (2026-09-28, 2026-11-17). Unchanged, on
   purpose: screen-share audio still gets the SDK's first listed output, and after a
   device change the SDK still replaces the selection with the first listed one.

Found and fixed by ITHINKSOW LLC (SowGood) on 2026-09-18 (1, 2), 2026-10-03 (3), 2026-10-25 (4) and 2026-11-17 (5, 6). The
`getRemoteStreams()` call exists in videosdk 4.0.1 too. Used via `dependency_overrides`
until an upstream release carries the fixes.
License: the package's own (see LICENSE).
