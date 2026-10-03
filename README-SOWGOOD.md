# videosdk (Flutter) 3.12.1 + SowGood's Safari fixes

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

Found and fixed by ITHINKSOW LLC (SowGood) on 2026-09-18 (1, 2) and 2026-10-03 (3). The
`getRemoteStreams()` call exists in videosdk 4.0.1 too. Used via `dependency_overrides`
until an upstream release carries the fixes.
License: the package's own (see LICENSE).
