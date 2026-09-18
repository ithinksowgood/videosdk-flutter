/// Defines all event types emitted by the VideoSDK.
///
/// - The [Events] enum represents the complete list of events that can be
/// emitted by the SDK during the lifecycle of a meeting, participant,
/// media stream, or device interaction.
///
/// - These events can be listened to using the `on()` method
/// available on [Room], [Participant], or [VideoSDK] instances.
///
/// ---
///
/// ### Usage
///
/// Events can be subscribed to using the `on` method:
///
/// ```dart
/// room.on(Events.roomJoined, () {
///   print('Room joined successfully');
/// });
/// ```
///
/// Some events provide callback parameters:
///
/// ```dart
/// room.on(Events.participantJoined, (participant) {
///   print('Participant joined: ${participant.displayName}');
/// });
/// ```
///
/// ---
///
/// ### Notes
///
/// - Event callback parameters vary depending on the event type.
/// - Some events are room-level, while others are participant- or stream-level.
/// - Certain events may only be available on specific platforms or SDK versions.
/// - Deprecated events are retained for backward compatibility and may be
///   removed in future releases.
///
/// Refer to the documentation of each individual event for
/// details about parameters and usage.
///
/// ---
// ignore_for_file: unintended_html_in_doc_comment, dangling_library_doc_comments

enum Events {
  /// Emitted when the local participant successfully joins the room
  ///
  /// ### **Example**
  /// ```dart
  /// room.on(Events.roomJoined, () {
  ///   print('Successfully joined the room!');
  /// });
  /// ```
  roomJoined,

  /// Emitted when the local participant leaves the room.
  ///
  /// - This event is triggered whenever the local participant exits the meeting,
  /// either voluntarily or due to an error or system action.
  ///
  /// - The event callback provides an optional [LeaveReason] parameter that
  /// describes why the participant left the room.
  ///
  /// ### Event handler parameters
  ///
  /// - reason *(LeaveReason?)*:
  ///   Indicates the reason for leaving the room. Possible values include:
  ///
  ///   - `LeaveReason.websocketDisconnected`
  ///     Socket disconnected.
  ///
  ///   - `LeaveReason.removePeer`
  ///     Participant was removed from the meeting.
  ///
  ///   - `LeaveReason.removePeerViewerModeChanged`
  ///     Participant was removed because viewer mode was changed.
  ///
  ///   - `LeaveReason.removePeerMediaRelayStop`
  ///     Participant was removed because media relay was stopped.
  ///
  ///   - `LeaveReason.switchRoom`
  ///     Participant switched to a different room.
  ///
  ///   - `LeaveReason.roomClose`
  ///     The meeting has been closed.
  ///
  ///   - `LeaveReason.unknown`
  ///     Participant disconnected due to an unknown reason.
  ///
  ///   - `LeaveReason.removeAll`
  ///     All participants were removed from the meeting.
  ///
  ///   - `LeaveReason.meetingEndApi`
  ///     Meeting was ended using the Meeting End API.
  ///
  ///   - `LeaveReason.removePeerApi`
  ///     Participant was removed using the Remove Participant API.
  ///
  ///   - `LeaveReason.manualLeaveCalled`
  ///     Participant manually called the `leave()` method.
  ///
  ///   - `LeaveReason.websocketConnectionAttemptsExhausted`
  ///     Meeting left after multiple failed WebSocket connection attempts.
  ///
  ///   - `LeaveReason.joinRoomFailed`
  ///     Meeting left due to an error while joining the room.
  ///
  ///   - `LeaveReason.switchRoomFailed`
  ///     Meeting left due to an error while switching rooms.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.roomLeft, (LeaveReason? reason) {
  ///   if (reason != null) {
  ///     print(
  ///       'Left room due to ${reason.name} '
  ///       '(code: ${reason.code}, message: ${reason.message})',
  ///     );
  ///   } else {
  ///     print('Left room');
  ///   }
  /// });
  /// ```

  roomLeft,

  /// Emitted whenever the room’s connection state changes.
  ///
  /// - This event is triggered on any change in the room’s lifecycle state,
  /// such as connecting, connected, disconnected, or reconnecting.
  ///
  /// - The current [RoomState] is passed as a callback parameter.
  ///
  /// ### Event callback parameters
  ///
  /// - state *(RoomState)*:
  ///   Represents the current connection state of the room. Possible values:
  ///   - `RoomState.connecting`
  ///   - `RoomState.connected`
  ///   - `RoomState.disconnected`
  ///   - `RoomState.reconnecting`
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.roomStateChanged, (RoomState state) {
  ///   switch (state) {
  ///     case RoomState.connecting:
  ///       print('Meeting is connecting');
  ///       break;
  ///     case RoomState.connected:
  ///       print('Meeting is connected');
  ///       break;
  ///     case RoomState.disconnected:
  ///       print('Meeting disconnected abruptly');
  ///       break;
  ///     case RoomState.reconnecting:
  ///       print('Meeting is reconnecting');
  ///       break;
  ///   }
  /// });
  /// ```
  roomStateChanged,

  /// Emitted when a participant requests permission to join the room.
  ///
  /// - This event is triggered when a new participant attempts to join the room
  /// with the `ask_join` permission enabled in their token.
  ///
  /// - The event is emitted **only** to participants who have the `allow_join`
  /// permission in their token.
  ///
  /// - The event callback provides a [Map<String, dynamic>] containing the
  /// participant details along with `allow()` and `deny()` actions to either
  /// approve or reject the entry request.
  ///
  /// ### Event callback parameters
  ///
  /// - data *(Map<String, dynamic>)*:
  ///   A map containing the following keys:
  ///
  ///   - `participantId` *(String)*:
  ///     The unique ID of the participant requesting to join.
  ///
  ///   - `name` *(String)*:
  ///     The display name of the participant requesting to join.
  ///
  ///   - `allow` *(Function)*:
  ///     Call this function to approve the participant’s entry request.
  ///
  ///   - `deny` *(Function)*:
  ///     Call this function to reject the participant’s entry request.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.entryRequested, (Map<String, dynamic> data) {
  ///   final String participantId = data['participantId'];
  ///   final String name = data['name'];
  ///
  ///   final Function allow = data['allow'];
  ///   final Function deny = data['deny'];
  ///
  ///   print('$name requested to join the room');
  ///
  ///   // Allow the participant to join
  ///   allow();
  ///
  ///   // Or deny the participant's entry request
  ///   // deny();
  /// });
  /// ```
  entryRequested,

  /// Emitted when a participant’s entry request receives a response.
  ///
  /// - This event is triggered after a `join()` request is either
  /// approved or denied.
  ///
  /// The event is emitted to:
  /// - All participants who have the `allow_join` permission in their token
  /// - The participant who originally requested to join the room
  ///
  /// ### Event callback parameters
  ///
  /// - participantId *(String)*:
  ///   The unique ID of the participant who requested to join the room.
  ///
  /// - decision *(String)*:
  ///   The decision taken on the entry request. Possible values are:
  ///   - `"allowed"`
  ///   - `"denied"`
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(
  ///   Events.entryResponded,
  ///   (String participantId, String decision) {
  ///     if (decision == 'allowed') {
  ///       print('Entry request allowed for participant: $participantId');
  ///     } else {
  ///       print('Entry request denied for participant: $participantId');
  ///     }
  ///   },
  /// );
  /// ```
  entryResponded,

  /// Emitted when a participant requests permission to enable the microphone
  /// of another participant.
  ///
  /// - This event is emitted to participant **B** when another participant **A**
  /// requests to enable participant **B**’s microphone.
  ///
  /// - If the request is accepted, the microphone of participant **B**
  /// will be enabled.
  ///
  /// ### Event callback parameters
  ///
  /// - data *(Map<String, dynamic>)*:
  ///   A map containing the following keys:
  ///
  ///   - `accept` *(Function)*:
  ///     Call this function to approve the microphone enable request.
  ///
  ///   - `reject` *(Function)*:
  ///     Call this function to reject the microphone enable request.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.micRequested, (Map<String, dynamic> data) {
  ///   final Function accept = data['accept'];
  ///   final Function reject = data['reject'];
  ///
  ///   // Accept the microphone enable request
  ///   accept();
  ///
  ///   // Or reject the request
  ///   // reject();
  /// });
  /// ```
  micRequested,

  /// Emitted when a participant requests permission to enable the camera
  /// of another participant.
  ///
  /// - This event is emitted to participant **B** when another participant **A**
  /// requests to enable participant **B**’s camera.
  ///
  /// - If the request is accepted, the camera of participant **B**
  /// will be enabled.
  ///
  /// ### Event callback parameters
  ///
  /// - data *(Map<String, dynamic>)*:
  ///   A map containing the following keys:
  ///
  ///   - `accept` *(Function)*:
  ///     Call this function to approve the camera enable request.
  ///
  ///   - `reject` *(Function)*:
  ///     Call this function to reject the camera enable request.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.cameraRequested, (Map<String, dynamic> data) {
  ///   final Function accept = data['accept'];
  ///   final Function reject = data['reject'];
  ///
  ///   // Accept the camera enable request
  ///   accept();
  ///
  ///   // Or reject the request
  ///   // reject();
  /// });
  /// ```
  cameraRequested,

  /// Emitted when a new participant joins the room.
  ///
  /// - This event is triggered whenever a remote participant successfully
  /// joins the meeting. The newly joined participant is provided as
  /// a [Participant] object in the event callback.
  ///
  /// ### Event callback parameters
  ///
  /// - participant *(Participant)*:
  ///   The participant who has joined the room.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.participantJoined, (Participant participant) {
  ///   print('Participant joined: ${participant.displayName}');
  /// });
  /// ```
  participantJoined,

  /// Emitted when a remote participant leaves the room.
  ///
  /// - This event is triggered whenever a participant who had joined
  /// the meeting exits the room, either voluntarily or due to an error
  /// or system action.
  ///
  /// - The event callback provides the participant’s ID along with a
  /// [LeaveReason] describing why the participant left.
  ///
  /// ### Event callback parameters
  ///
  /// - participantId *(String)*:
  ///   The unique ID of the participant who left the room.
  ///
  /// - reason *(LeaveReason)*:
  ///   Indicates the reason why the participant left the room. Possible values
  ///   include:
  ///
  ///   - `LeaveReason.websocketDisconnected`
  ///   - `LeaveReason.removePeer`
  ///   - `LeaveReason.removePeerViewerModeChanged`
  ///   - `LeaveReason.removePeerMediaRelayStop`
  ///   - `LeaveReason.switchRoom`
  ///   - `LeaveReason.roomClose`
  ///   - `LeaveReason.unknown`
  ///   - `LeaveReason.removeAll`
  ///   - `LeaveReason.meetingEndApi`
  ///   - `LeaveReason.removePeerApi`
  ///   - `LeaveReason.manualLeaveCalled`
  ///   - `LeaveReason.websocketConnectionAttemptsExhausted`
  ///   - `LeaveReason.joinRoomFailed`
  ///   - `LeaveReason.switchRoomFailed`
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(
  ///   Events.participantLeft,
  ///   (String participantId, LeaveReason reason) {
  ///     print(
  ///       'Participant $participantId left the room '
  ///       '(code: ${reason.code}, message: ${reason.message})',
  ///     );
  ///   },
  /// );
  /// ```
  participantLeft,

  /// Emitted when a participant’s pin state changes.
  ///
  /// - This event is triggered whenever a participant is pinned or unpinned
  /// in the room, either for camera, screen share, or both.
  ///
  /// - The event callback receives a `Map<String, dynamic>` containing details
  /// about the pin state change.
  ///
  /// ### Event callback parameters
  ///
  /// - **data** *(Map<String, dynamic>)*:
  ///   - `participantId` *(String)*:
  ///     The ID of the participant whose pin state has changed.
  ///
  ///   - `state` *(Map<String, dynamic>)*:
  ///     Represents the updated pin state. It contains boolean values for:
  ///     - `cam` – Indicates whether the participant’s camera is pinned
  ///     - `share` – Indicates whether the participant’s screen share is pinned
  ///
  ///   - `pinnedBy` *(String)*:
  ///     The participant ID of the user who performed the pin or unpin action.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.pinStateChanged, (Map<String, dynamic> data) {
  ///   final String participantId = data['participantId'];
  ///   final Map<String, dynamic> state = data['state'];
  ///   final String pinnedBy = data['pinnedBy'];
  ///
  ///   final bool camPinned = state['cam'] ?? false;
  ///   final bool sharePinned = state['share'] ?? false;
  ///
  ///   print(
  ///     'Participant $participantId pin state changed '
  ///     '(cam: $camPinned, share: $sharePinned) by $pinnedBy',
  ///   );
  /// });
  /// ```
  pinStateChanged,

  /// Emitted when a participant’s mode changes.
  ///
  /// - This event is triggered whenever a participant switches their mode,
  /// such as moving between sending/receiving media, signaling-only,
  /// or receive-only mode.
  ///
  /// **Note:**
  /// This event is supported in the Flutter SDK starting from version **v1.3.0**.
  ///
  /// ### Event callback parameters
  ///
  /// - **data** *(Map<String, dynamic>)*:
  ///   - `participantId` *(String)*:
  ///     The ID of the participant whose mode has changed.
  ///   - `mode` *(String)*:
  ///     The updated mode of the participant.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.participantModeChanged, (Map<String, dynamic> data) {
  ///   final String participantId = data['participantId'];
  ///   final String mode = data['mode'];
  ///
  ///   print('Participant $participantId changed mode to $mode');
  /// });
  /// ```
  participantModeChanged,

  /// Emitted when the active speaker in the room changes.
  ///
  /// - This event is triggered whenever the currently active speaker changes.
  /// It can be used to track which participant is speaking at any given time.
  ///
  /// - If no participant is actively speaking, the callback parameter
  /// will be `null`.
  ///
  /// ### Event callback parameters
  ///
  /// - **activeSpeakerId** *(String?)*:
  ///   The participant ID of the currently active speaker, or `null`
  ///   if no participant is speaking.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.speakerChanged, (String? activeSpeakerId) {
  ///   if (activeSpeakerId != null) {
  ///     print('Active speaker ID: $activeSpeakerId');
  ///   } else {
  ///     print('No active speaker');
  ///   }
  /// });
  /// ```
  speakerChanged,

  /// Emitted when the active presenter (screen-sharing participant) changes.
  ///
  /// - This event is triggered when a participant starts or stops screen sharing.
  /// It provides the participant ID of the active presenter.
  ///
  /// - If screen sharing is stopped and no participant is presenting,
  /// the callback parameter will be `null`.
  ///
  /// ### Event callback parameters
  ///
  /// - **activePresenterId** *(String?)*:
  ///   The participant ID of the active presenter, or `null` if
  ///   no participant is currently sharing their screen.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.presenterChanged, (String? activePresenterId) {
  ///   if (activePresenterId != null) {
  ///     print('Active presenter ID: $activePresenterId');
  ///   } else {
  ///     print('No active presenter');
  ///   }
  /// });
  /// ```
  presenterChanged,

  /// Emitted when a media stream is enabled for a participant.
  ///
  /// This event is triggered when a participant starts producing or
  /// consuming a media stream of any type, such as:
  /// - audio
  /// - video
  /// - screen share
  ///
  /// - The enabled [Stream] object is passed as the callback parameter.
  ///
  /// ### Event callback parameters
  ///
  /// - **stream** *(Stream)*:
  ///   The media stream that has been enabled.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.participant.on(Events.streamEnabled, (Stream stream) {
  ///   print('Stream enabled of kind: ${stream.kind}');
  /// });
  /// ```
  streamEnabled,

  /// Emitted when a media stream is disabled for a participant.
  ///
  /// This event is triggered when a participant stops producing or
  /// consuming a media stream of any type, such as:
  /// - audio
  /// - video
  /// - screen share
  ///
  /// - The disabled [Stream] object is passed as the callback parameter.
  ///
  /// ### Event callback parameters
  ///
  /// - **stream** *(Stream)*:
  ///   The media stream that has been disabled.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.participant.on(Events.streamDisabled, (Stream stream) {
  ///   print('Stream disabled of kind: ${stream.kind}');
  /// });
  /// ```
  streamDisabled,

  /// Emitted when a media stream is paused for a participant.
  ///
  /// This event is triggered when a participant temporarily pauses
  /// producing or consuming a media stream of any type, including:
  /// - audio
  /// - video
  /// - screen share
  ///
  /// -  The paused [Stream] object is passed as the callback parameter.
  ///
  /// ### Event callback parameters
  ///
  /// - **stream** *(Stream)*:
  ///   The media stream that has been paused.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.participant.on(Events.streamPaused, (Stream stream) {
  ///   print('Stream paused of kind: ${stream.kind}');
  /// });
  /// ```
  streamPaused,

  /// Emitted when a paused media stream is resumed for a participant.
  ///
  /// -This event is triggered when a participant resumes producing
  /// or consuming a previously paused media stream of any type.
  ///
  /// -The resumed [Stream] object is passed as the callback parameter.
  ///
  /// ### Event callback parameters
  ///
  /// - **stream** *(Stream)*:
  ///   The media stream that has been resumed.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.participant.on(Events.streamResumed, (Stream stream) {
  ///   print('Stream resumed of kind: ${stream.kind}');
  /// });
  /// ```
  streamResumed,

  /// Emitted when the state of a **remote participant’s**
  /// video or screen-share stream changes.
  ///
  /// - This event helps track stream health and lifecycle.
  ///
  /// - This event is emitted **only for remote participants**.
  ///
  /// ### Callback Parameters
  /// - `state` (`String`)
  ///   - `"active"` – Stream is working normally
  ///   - `"stuck"` – Stream is not progressing
  ///   - `"freeze-detected"` – Video freeze detected
  ///   - `"freeze-resolved"` – Video freeze resolved
  ///   - `"ended"` – Stream has ended
  ///
  /// - `timestamp` (`int`)
  ///   - Time (in milliseconds since epoch) when the change occurred
  ///
  /// ### **Example**
  /// ```dart
  /// stream.on(Events.streamStateChanged, (state, timestamp) {
  ///   print('Stream state: $state at $timestamp');
  /// });
  /// ```
  streamStateChanged,

  /// Emitted when a participant’s video quality changes.
  ///
  /// - This event is triggered whenever the SDK automatically adjusts
  /// the video quality of a participant based on network conditions
  /// or adaptive subscription logic.
  ///
  /// - The callback receives a `Map<String, dynamic>` containing the
  /// previous and current video quality values.
  ///
  /// ### Possible quality values
  ///
  /// - `HIGH`
  /// - `MEDIUM`
  /// - `LOW`
  ///
  /// ### Event callback parameters
  ///
  /// - **data** *(MapString, dynamic>)*:
  ///   - `currentQuality` *(String)*:
  ///     The updated video quality.
  ///   - `prevQuality` *(String)*:
  ///     The previous video quality.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// participant.on(Events.videoQualityChanged, (Map<String, dynamic> data) {
  ///   final String currentQuality = data['currentQuality'];
  ///   final String prevQuality = data['prevQuality'];
  ///
  ///   print(
  ///     'Video quality changed from $prevQuality to $currentQuality',
  ///   );
  /// });
  /// ```
  videoQualityChanged,

  /// - Triggered when the meeting's active media codec changes because a newly
  /// joined participant does not support the current codec.
  ///
  /// - The meeting automatically negotiates and switches to a mutually
  /// compatible codec to maintain connectivity for all participants.
  ///
  /// ### Event callback parameters
  ///
  /// - **data** *([CodecChangeInfo])*:
  ///   - `unsupportedRemoteCodec` *(VideoCodec)*:
  ///     The codec that the newly joined participant did not support,
  ///     which triggered the switch.
  ///   - `currentCodec` *(VideoCodec)*:
  ///     The new codec that the meeting switched to after the change.
  ///   - `previousCodec` *(VideoCodec)*:
  ///     The codec that was in use before the change.
  ///   - `kind` *(String)*:
  ///     The media type for which the codec changed.
  ///   - `causedBy` *(Participant?)*:
  ///     The [Participant] instance of the participant whose joining
  ///     triggered the codec change.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.codecChanged, (CodecChangeInfo data) {
  ///   final unsupportedRemoteCodec = data.unsupportedRemoteCodec;
  ///   final currentCodec = data.currentCodec;
  ///   final previousCodec = data.previousCodec;
  ///   final kind = data.kind;
  ///   final causedBy = data.causedBy;
  /// });
  /// ```
  codecChanged,

  /// Emitted when a quality limitation is detected or resolved during the meeting.
  ///
  /// - This event is triggered when the SDK applies or removes limitations
  /// on media quality due to factors such as network conditions or device
  /// performance.
  ///
  /// ### Limitation types
  ///
  /// - `congestion`: Network congestion detected.
  /// - `bandwidth`: Insufficient available bandwidth.
  /// - `cpu`: High CPU usage on the device.
  ///
  /// ### Limitation states
  ///
  /// - `detected`: A quality limitation has been detected.
  /// - `resolved`: The previously detected limitation has been resolved.
  ///
  /// ### Event callback parameters
  ///
  /// - **type** *(String)*:
  ///   The type of quality limitation (`congestion`, `bandwidth`, or `cpu`).
  ///
  /// - **state** *(String)*:
  ///   The current state of the limitation (`detected` or `resolved`).
  ///
  /// - **timestamp** *(int)*:
  ///   The time (in milliseconds since epoch) when the event occurred.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(
  ///   Events.qualityLimitation,
  ///   (String type, String state, int timestamp) {
  ///     print(
  ///       'Quality limitation [$type] was $state at $timestamp',
  ///     );
  ///   },
  /// );
  /// ```
  qualityLimitation,

  /// Emitted when room recording starts.
  ///
  /// **Deprecated:**
  /// - This event will be deprecated in a future release.
  /// - Consider using the newer recording state or lifecycle events
  /// when available.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.recordingStarted, () {
  ///   print('Recording has started');
  /// });
  /// ```
  recordingStarted,

  /// Emitted when room recording stops.
  ///
  /// **Deprecated:**
  /// - This event will be deprecated in a future release.
  /// - Consider using the newer recording state or lifecycle events
  /// when available.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.recordingStopped, () {
  ///   print('Recording has stopped');
  /// });
  /// ```
  recordingStopped,

  /// Emitted when the meeting’s recording state changes.
  ///
  /// -This event is triggered whenever the recording lifecycle
  /// transitions between different states, such as starting,
  /// started, stopping, or stopped.
  ///
  /// ### Possible recording states
  ///
  /// - `RECORDING_STARTING`:
  ///   Recording is initializing and has not started yet.
  ///
  /// - `RECORDING_STARTED`:
  ///   Recording has started successfully.
  ///
  /// - `RECORDING_STOPPING`:
  ///   Recording is in the process of stopping.
  ///
  /// - `RECORDING_STOPPED`:
  ///   Recording has stopped successfully.
  ///
  /// ### Event callback parameters
  ///
  /// - **status** *(String)*:
  ///   The current recording state.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.recordingStateChanged, (String status) {
  ///   print('Meeting recording state: $status');
  /// });
  /// ```
  recordingStateChanged,

  /// Emitted when RTMP live streaming starts.
  ///
  /// **Deprecated:**
  /// - This event will be deprecated in a future release.
  /// - Use [Events.liveStreamStateChanged] to track livestream lifecycle updates.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.liveStreamStarted, () {
  ///   print('Live streaming has started');
  /// });
  /// ```
  liveStreamStarted,

  /// Emitted when RTMP live streaming stops.
  ///
  /// **Deprecated:**
  /// - This event will be deprecated in a future release.
  /// - Use [Events.liveStreamStateChanged] to track livestream lifecycle updates.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.liveStreamStopped, () {
  ///   print('Live streaming has stopped');
  /// });
  /// ```
  liveStreamStopped,

  /// Emitted when the meeting’s livestream state changes.
  ///
  /// - This event is triggered whenever the livestream lifecycle
  /// transitions between different states.
  ///
  /// ### Possible livestream states
  ///
  /// - `LIVESTREAM_STARTING`:
  ///   Livestream is initializing and has not started yet.
  ///
  /// - `LIVESTREAM_STARTED`:
  ///   Livestream has started successfully.
  ///
  /// - `LIVESTREAM_STOPPING`:
  ///   Livestream is in the process of stopping.
  ///
  /// - `LIVESTREAM_STOPPED`:
  ///   Livestream has stopped successfully.
  ///
  /// ### Event callback parameters
  ///
  /// - **status** *(String)*:
  ///   The current livestream state.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.liveStreamStateChanged, (String status) {
  ///   print('Meeting livestream state: $status');
  /// });
  /// ```
  liveStreamStateChanged,

  // HLS Events
  /// Emitted when HLS (HTTP Live Streaming) starts.
  ///
  /// **Deprecated:**
  /// - This event will be deprecated in a future release.
  /// - Use [Events.hlsStateChanged] to track the full HLS lifecycle.
  ///
  /// ### Event callback parameters
  ///
  /// - **playbackHlsUrl** *(String)*
  /// - **livestreamUrl** *(String)*
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(
  ///   Events.hlsStarted,
  ///   (String playbackHlsUrl, String livestreamUrl) {
  ///     print('HLS started');
  ///     print('Playback URL: $playbackHlsUrl');
  ///     print('Live URL: $livestreamUrl');
  ///   },
  /// );
  /// ```
  hlsStarted,

  /// Emitted when HLS (HTTP Live Streaming) stops.
  ///
  /// **Deprecated:**
  /// - This event will be deprecated in a future release.
  /// - Use [Events.hlsStateChanged] instead.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.hlsStopped, () {
  ///   print('HLS streaming has stopped');
  /// });
  /// ```
  hlsStopped,

  /// Emitted when the meeting’s HLS (HTTP Live Streaming) state changes.
  ///
  /// - This event is triggered whenever the HLS lifecycle transitions
  /// between different states such as starting, playable, or stopped.
  ///
  /// ### Possible HLS states
  ///
  /// - `HLS_STARTING`:
  ///   HLS is initializing and has not started yet.
  ///
  /// - `HLS_STARTED`:
  ///   HLS has started successfully.
  ///
  /// - `HLS_PLAYABLE`:
  ///   HLS is live and playable.
  ///   The callback will include `playbackHlsUrl` and `livestreamUrl`.
  ///
  /// - `HLS_STOPPING`:
  ///   HLS is in the process of stopping.
  ///
  /// - `HLS_STOPPED`:
  ///   HLS has stopped successfully.
  ///
  /// ### Event callback parameters
  ///
  /// - **data** *(Map<String, dynamic>)*:
  ///   - `status` *(String)*:
  ///     Current HLS state.
  ///   - `playbackHlsUrl` *(String?)*:
  ///     Available only when the state is `HLS_PLAYABLE`.
  ///     This URL supports playback controls.
  ///   - `livestreamUrl` *(String?)*:
  ///     Available only when the state is `HLS_PLAYABLE`.
  ///     This URL provides a live stream without playback.
  ///
  /// **Note:**
  /// `downstreamUrl` is deprecated.
  /// Use `playbackHlsUrl` or `livestreamUrl` instead.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.hlsStateChanged, (Map<String, dynamic> data) {
  ///   final String status = data['status'];
  ///
  ///   print('Meeting HLS status: $status');
  ///
  ///   if (status == 'HLS_PLAYABLE') {
  ///     print('Playback URL: ${data['playbackHlsUrl']}');
  ///     print('Live URL: ${data['livestreamUrl']}');
  ///   }
  /// });
  /// ```
  hlsStateChanged,

  /// Emitted when the realtime transcription state changes.
  ///
  /// - This event is triggered whenever the lifecycle state of
  /// - realtime transcription is updated.
  ///
  /// ### Possible transcription states
  ///
  /// - `TRANSCRIPTION_STARTING`:
  ///   Realtime transcription is initializing and has not started yet.
  ///
  /// - `TRANSCRIPTION_STARTED`:
  ///   Realtime transcription has started successfully.
  ///
  /// - `TRANSCRIPTION_STOPPING`:
  ///   Realtime transcription is in the process of stopping.
  ///
  /// - `TRANSCRIPTION_STOPPED`:
  ///   Realtime transcription has stopped successfully.
  ///
  /// ### Event callback parameters
  ///
  /// - **data** *(Map<String, dynamic>)*:
  ///   - `status` *(String)*:
  ///     The current transcription state.
  ///   - `id` *(String)*:
  ///     The unique ID of the transcription session.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(
  ///   Events.transcriptionStateChanged,
  ///   (Map<String, dynamic> data) {
  ///     print(
  ///       'Meeting transcription status: ${data['status']}',
  ///     );
  ///   },
  /// );
  /// ```
  transcriptionStateChanged,

  /// Emitted when realtime transcription text is received.
  ///
  /// - This event is triggered whenever new transcription text
  /// is generated during an active realtime transcription session.
  ///
  /// - The callback receives a [TranscriptionText] object containing
  /// details about the transcribed speech.
  ///
  /// ### Event callback parameters
  ///
  /// - **data** *(TranscriptionText)*:
  ///   - `participantId` *(String)*:
  ///     ID of the participant whose speech was transcribed.
  ///   - `participantName` *(String)*:
  ///     Display name of the participant.
  ///   - `text` *(String)*:
  ///     Transcribed text.
  ///   - `timestamp` *(int)*:
  ///     Time (in milliseconds since epoch) when the text was generated.
  ///   - `type` *(String)*:
  ///     Type of transcription update.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.transcriptionText, (TranscriptionText data) {
  ///   print(
  ///     'Transcription from ${data.participantName}: ${data.text}',
  ///   );
  /// });
  /// ```
  transcriptionText,

  /// Emitted when an error occurs in the room.
  ///
  /// - This event is triggered whenever the SDK encounters an error
  /// related to signaling, media handling, permissions, or internal
  /// processing during the meeting lifecycle.
  ///
  /// ### Event callback parameters
  ///
  /// - **error** *(Map<String, dynamic>)*:
  ///   - `code` *(int)*:
  ///     Numeric error code identifying the error.
  ///   - `name` *(String)*:
  ///     Short error name.
  ///   - `message` *(String)*:
  ///     Human-readable description of the error.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.error, (Map<String, dynamic> error) {
  ///   print(
  ///     'VIDEOSDK ERROR :: '
  ///     '${error['code']} :: '
  ///     '${error['name']} :: '
  ///     '${error['message']}',
  ///   );
  /// });
  /// ```
  error,

  /// Emitted when available media devices change.
  ///
  /// - This event is triggered whenever a media device such as a camera,
  /// microphone, or speaker is connected to or removed from the system.
  ///
  /// The callback receives the updated list of available devices.
  ///
  /// **Note:**
  /// - This event is **not supported on macOS applications**.
  /// - Media permissions must be granted; otherwise, the device list
  ///   may be empty or unavailable.
  ///
  /// ### Event callback parameters
  ///
  /// - **devices** *(List<DeviceInfo>)*:
  ///   The updated list of available media devices.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// VideoSDK.on(Events.deviceChanged, (List<DeviceInfo> devices) {
  ///   print('Media devices changed: $devices');
  /// });
  /// ```
  deviceChanged,

  // Character Events (AI/Bot)
  /// @nodoc
  characterJoined,

  /// @nodoc
  characterLeft,

  /// @nodoc
  characterMessage,

  /// @nodoc
  userMessage,

  /// @nodoc
  characterStateChanged,

  // Whiteboard Events
  /// Emitted when whiteboard sharing starts.
  /// ### **Example**
  /// ```dart
  /// room.on(Events.whiteboardStarted, () {
  ///   print('Whiteboard sharing has started');
  /// });
  /// ```
  whiteboardStarted,

  /// Emitted when whiteboard sharing stops.
  /// ### **Example**
  /// ```dart
  /// room.on(Events.whiteboardStopped, () {
  ///   print('Whiteboard sharing has stopped');
  /// });
  /// ```
  whiteboardStopped,

  /// Emitted when the end-to-end encryption (E2EE) state changes
  /// for a participant’s media stream.
  ///
  /// - This event is triggered whenever encryption or decryption
  /// state updates occur for a specific media stream.
  ///
  /// ### Event callback parameters
  ///
  /// - **state** *(E2EEState)*:
  ///   The current encryption or decryption state.
  ///
  /// - **stream** *(Stream)*:
  ///   The media stream associated with the encryption state change.
  ///
  /// ### Possible E2EE states
  ///
  /// - `EncryptionSucessed`:
  ///   Media encryption has been successfully applied.
  ///
  /// - `DecryptionSucessed`:
  ///   Incoming media has been successfully decrypted.
  ///
  /// - `EncryptionFailed`:
  ///   An error occurred while encrypting the media.
  ///
  /// - `DecryptionFailed`:
  ///   An error occurred while decrypting the media.
  ///
  /// - `InternalError`:
  ///   An internal encryption-related error occurred.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// widget.participant.on(
  ///   Events.e2eeStateChanged,
  ///   (E2EEState state, Stream stream) {
  ///     print('$state is for the ${stream.kind}');
  ///   },
  /// );
  /// ```
  e2eeStateChanged,

  /// Emitted when all or specific media streams are paused.
  ///
  /// - This event is triggered after media streams within the meeting
  /// are successfully paused, either globally or for a specific type.
  ///
  /// ### Event callback parameters
  ///
  /// - **kind** *(String)*:
  ///   Specifies which type of media stream was paused.
  ///   Possible values:
  ///   - `audio` – Audio streams were paused.
  ///   - `video` – Video streams were paused.
  ///   - `share` – Screen-sharing video streams were paused.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.pausedAllStreams, (String kind) {
  ///   print('Paused $kind streams');
  /// });
  /// ```
  pausedAllStreams,

  /// Emitted when all or specific media streams are resumed.
  ///
  /// - This event is triggered after paused media streams within
  /// the meeting are successfully resumed.
  ///
  /// ### Event callback parameters
  ///
  /// - **kind** *(String)*:
  ///   Specifies which type of media stream was resumed.
  ///   Possible values:
  ///   - `audio` – Audio streams were resumed.
  ///   - `video` – Video streams were resumed.
  ///   - `share` – Screen-sharing video streams were resumed.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.resumedAllStreams, (String kind) {
  ///   print('Resumed $kind streams');
  /// });
  /// ```
  resumedAllStreams,

  /// Emitted when a media relay request is received in the destination meeting.
  ///
  /// - This event is triggered when a participant from another meeting
  /// requests to relay media streams into the current meeting.
  ///
  /// ### Event callback parameters
  ///
  /// - **meetingId** *(String)*:
  ///   The ID of the source meeting from which the relay request was made.
  ///
  /// - **peerId** *(String)*:
  ///   The participant ID who requested the media relay.
  ///
  /// - **displayName** *(String)*:
  ///   Display name of the participant who requested the relay.
  ///
  /// - **accept** *(Function)*:
  ///   Call this function to accept the media relay request.
  ///
  /// - **reject** *(Function)*:
  ///   Call this function to reject the media relay request.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(
  ///   Events.mediaRelayRequestReceived,
  ///   (
  ///     String meetingId,
  ///     String peerId,
  ///     String displayName,
  ///     Function accept,
  ///     Function reject,
  ///   ) {
  ///     print('Media relay request from $displayName');
  ///
  ///     // Accept the relay request
  ///     accept();
  ///
  ///     // Or reject it
  ///     // reject();
  ///   },
  /// );
  /// ```
  mediaRelayRequestReceived,

  /// Emitted when media relay to a destination meeting
  /// starts successfully.
  ///
  /// ### Event callback parameters
  ///
  /// - **meetingId** *(String)*:
  ///   The destination meeting ID where media relay has started.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(Events.mediaRelayStarted, (String meetingId) {
  ///   print('Media relay started for meeting: $meetingId');
  /// });
  /// ```
  mediaRelayStarted,

  /// Emitted when media relay to a destination meeting stops.
  ///
  /// - This event may be triggered due to user action,
  /// connection issues, or other termination reasons.
  ///
  /// ### Event callback parameters
  ///
  /// - **meetingId** *(String)*:
  ///   The meeting ID where media relay was stopped.
  ///
  /// - **reason** *(String)*:
  ///   Reason for stopping the relay.
  ///   Common values include:
  ///   - `user_stopped`
  ///   - `connection_lost`
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(
  ///   Events.mediaRelayStopped,
  ///   (String meetingId, String reason) {
  ///     print(
  ///       'Media relay stopped for meeting $meetingId. '
  ///       'Reason: $reason',
  ///     );
  ///   },
  /// );
  /// ```
  mediaRelayStopped,

  /// Emitted when an error occurs during media relay.
  ///
  /// - This event is triggered if the relay fails due to
  /// network issues, signaling errors, or internal failures.
  ///
  /// ### Event callback parameters
  ///
  /// - **meetingId** *(String)*:
  ///   The meeting ID where the error occurred.
  ///
  /// - **reason** *(String)*:
  ///   Description of the error.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(
  ///   Events.mediaRelayError,
  ///   (String meetingId, String reason) {
  ///     print(
  ///       'Media relay error for meeting $meetingId: $reason',
  ///     );
  ///   },
  /// );
  /// ```
  mediaRelayError,

  /// Emitted when a response to a media relay request is received
  /// in the source meeting.
  ///
  /// - This event notifies the requester whether their relay
  /// request was accepted or rejected.
  ///
  /// ### Event callback parameters
  ///
  /// - **decidedBy** *(String)*:
  ///   The participant ID who responded to the relay request.
  ///
  /// - **decision** *(String)*:
  ///   The decision for the request.
  ///   Possible values: `accepted`, `rejected`.
  ///
  /// - **meetingId** *(String)*:
  ///   The destination meeting ID for which the relay was requested.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// room.on(
  ///   Events.mediaRelayRequestResponse,
  ///   (String decidedBy, String decision, String meetingId) {
  ///     print(
  ///       'Media relay response by $decidedBy '
  ///       'for meeting $meetingId: $decision',
  ///     );
  ///   },
  /// );
  /// ```
  mediaRelayRequestResponse,

  // Translation Events
  /// @nodoc
  translationStateChanged,

  /// @nodoc
  translationText,

  /// @nodoc
  translationLanguageChanged,

  /// Emitted when an [AgentParticipant]'s operational state changes.
  ///
  /// This event is fired any time the agent transitions between
  /// `idle`, `listening`, `thinking`, and `speaking` states.
  ///
  /// ### Event callback parameters
  ///
  /// - **state** *([AgentState])*:
  ///   The new operational state of the agent.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// agent.on(Events.agentStateChanged, (AgentState state) {
  ///   print('Agent is now: \${state.name}');
  /// });
  /// ```
  agentStateChanged,

  /// Emitted when a transcription segment is received from an [AgentParticipant].
  ///
  /// ### Event callback parameters
  ///
  /// - **data** *([TranscriptionSegment])*:
  ///   Contains the transcription segment (text + timestamp).
  //
  /// - **participant** *([Participant])*:
  ///   The participant associated with this transcription segment.
  ///

  ///
  /// ### **Example**
  ///
  /// ```dart
  /// agent.on(Events.agentTranscriptionReceived, (TranscriptionSegment segment, Participant participant) {
  ///   print('Participant: ${participant.displayName}');
  ///   print('Transcription: ${segment.text}');
  /// });
  /// ```
  agentTranscriptionReceived,

  /// Emitted when metrics data is received from an [AgentParticipant].
  ///
  /// ### Event callback parameters
  ///
  /// - **data** *(`Map<String, dynamic>`)*:
  ///   The metrics payload received from the agent.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// agent.on(Events.agentMetrics, (Map<String, dynamic> data) {
  ///   print('Agent metrics: $data');
  /// });
  /// ```
  agentMetrics,
}

/// @nodoc
/// Internal mapping of Events enum to their string representations.
Map<Events, String> eventsMap = {
  Events.roomJoined: 'meeting-joined',
  Events.roomLeft: 'meeting-left',
  Events.entryRequested: 'entry-requested',
  Events.entryResponded: 'entry-responded',
  Events.micRequested: 'mic-requested',
  Events.cameraRequested: 'webcam-requested',
  Events.participantJoined: 'participant-joined',
  Events.participantLeft: 'participant-left',
  Events.participantModeChanged: 'participant-mode-changed',
  Events.speakerChanged: 'speaker-changed',
  Events.presenterChanged: 'presenter-changed',
  Events.pinStateChanged: 'pin-state-changed',
  Events.streamEnabled: 'stream-enabled',
  Events.streamDisabled: 'stream-disabled',
  Events.streamPaused: 'stream-paused',
  Events.streamResumed: 'stream-resumed',
  Events.videoQualityChanged: 'video-quality-changed',
  Events.codecChanged: 'codec-changed',
  Events.recordingStarted: 'recording-started',
  Events.recordingStopped: 'recording-stopped',
  Events.recordingStateChanged: 'recording-state-changed',
  Events.liveStreamStarted: 'livestream-started',
  Events.liveStreamStopped: 'livestream-stopped',
  Events.liveStreamStateChanged: 'livestream-state-changed',
  Events.hlsStarted: 'hls-started',
  Events.hlsStopped: 'hls-stopped',
  Events.hlsStateChanged: 'hls-state-changed',
  Events.transcriptionStateChanged: 'transcription-state-changed',
  Events.transcriptionText: 'transcription-text',
  Events.error: 'error',
  Events.deviceChanged: 'device-changed',
  Events.characterJoined: 'character-joined',
  Events.characterLeft: 'character-left',
  Events.characterMessage: 'character-message',
  Events.userMessage: 'user-message',
  Events.characterStateChanged: 'character-state-changed',
  Events.whiteboardStarted: 'whiteboard-started',
  Events.whiteboardStopped: 'whiteboard-stopped',
  Events.e2eeStateChanged: 'e2ee-state-changed',
  Events.roomStateChanged: 'meeting-state-changed',
  Events.pausedAllStreams: 'paused-all-stream',
  Events.resumedAllStreams: 'resumed-all-stream',
  Events.mediaRelayRequestReceived: 'media-relay-request-received',
  Events.mediaRelayStarted: 'media-relay-started',
  Events.mediaRelayStopped: 'media-relay-stopped',
  Events.mediaRelayError: 'media-relay-error',
  Events.mediaRelayRequestResponse: 'media-relay-request-response',
  Events.translationStateChanged: 'translation-state-changed',
  Events.translationText: 'translation-text',
  Events.translationLanguageChanged: 'translation-language-changed',
  Events.qualityLimitation: 'quality-limitation',
  Events.streamStateChanged: 'stream-state-changed',
  Events.agentStateChanged: 'agent-state-changed',
  Events.agentTranscriptionReceived: 'agent-transcription-received',
  Events.agentMetrics: 'agent-metrics',
};

/// @nodoc
/// Extension to convert Events enum to their string representation.
extension ParseToString on Events {
  /// @nodoc
  String parseToString() => eventsMap[this] ?? 'unknown';
}
