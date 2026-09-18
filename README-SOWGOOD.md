# videosdk (Flutter) 3.12.1 + the Safari remote-stream fix

This is the published `videosdk` 3.12.1 package from pub.dev, unchanged except for:

1. `lib/src/core/webrtc/src/handlers/unified_plan.dart` `receive()`: the deprecated,
   Chrome-only `getRemoteStreams()` is tolerated when the browser has no such method
   (Safari), and the remote stream is built from the receiver's track. Without this a
   Safari viewer never gets a remote stream: the consume task throws
   `NoSuchMethodError: method not found: 'getRemoteStreams'`, the SDK's task queue
   swallows it, and the server's consumer stays orphaned (later pause/resume notices
   then hit the SDK's null-check in `consumerPaused` / `consumerResumed`).
2. `lib/src/core/webrtc/src/FlexQueue/flex_queue.dart`: a failing task is also
   `print()`ed (dart:developer's `log()` prints nothing on the web).

Found and fixed by ITHINKSOW LLC (SowGood) on 2026-09-18. The same call exists in
videosdk 4.0.1. Used via `dependency_overrides` until an upstream release carries the fix.
License: the package's own (see LICENSE).
