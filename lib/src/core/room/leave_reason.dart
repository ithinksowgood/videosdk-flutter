/// Represents the reason why a participant left the meeting.
///
/// - This enum is provided in the [Events.roomLeft] event callback
/// when the local participant leaves the room. Each value contains
/// a unique reason code and a descriptive message explaining
/// why the participant was disconnected.
///
/// ### Possible Leave Reasons
///
/// - **websocketDisconnected** (`1001`)
///   Socket disconnected.
///
/// - **removePeer** (`1002`)
///   Participant was removed from the meeting.
///
/// - **removePeerViewerModeChanged** (`1003`)
///   Participant was removed because viewer mode was changed.
///
/// - **removePeerMediaRelayStop** (`1004`)
///   Participant was removed because media relay was stopped.
///
/// - **switchRoom** (`1005`)
///   Participant switched to a different room.
///
/// - **roomClose** (`1006`)
///   The meeting has been closed.
///
/// - **unknown** (`1007`)
///   Participant disconnected due to an unknown reason.
///
/// - **removeAll** (`1008`)
///   All participants were removed from the meeting.
///
/// - **meetingEndApi** (`1009`)
///   The meeting was ended using the Meeting End API.
///
/// - **removePeerApi** (`1010`)
///   Participant was removed using the Remove Participant API.
///
/// - **manualLeaveCalled** (`1101`)
///   Participant manually called the `leave()` method to exit the meeting.
///
/// - **websocketConnectionAttemptsExhausted** (`1102`)
///   Meeting left after multiple failed WebSocket connection attempts.
///
/// - **joinRoomFailed** (`1103`)
///   Meeting left due to an error while joining the room.
///
/// - **switchRoomFailed** (`1104`)
///   Meeting left due to an error while switching rooms.
///
/// ### **Example**
///
/// ```dart
/// room.on(Events.roomLeft, (LeaveReason? reason) {
///   if (reason != null) {
///     print(
///       'Left meeting due to ${reason.name} '
///       '(code: ${reason.code}, message: ${reason.message})',
///     );
///   }
/// });
/// ```
enum LeaveReason {
  websocketDisconnected(1001, "Socket disconnected"),
  removePeer(1002, "Participant was removed from the meeting"),
  removePeerViewerModeChanged(
      1003, "Participant Removed because viewer mode was changed"),
  removePeerMediaRelayStop(
      1004, "Participant Removed because media relay was stopped"),
  switchRoom(1005, "Participant switched to a different room"),
  roomClose(1006, "The meeting has been closed"),
  unknown(1007, "Participant disconnected due to an unknown reason"),
  removeAll(1008, "Remove All from the meeting"),
  meetingEndApi(1009, "Meeting Ended."),
  removePeerApi(1010, "Participant removed from the meeting"),
  manualLeaveCalled(1101,
      "Participant manually called the leave() method to exit the meeting"),
  websocketConnectionAttemptsExhausted(1102,
      "Meeting left after multiple failed websocket connection attempts."),
  joinRoomFailed(1103, "Meeting left due to an error while joining the room."),
  switchRoomFailed(1104, "Meeting left due to an error while switching rooms.");

  /// Numeric reason code associated with the leave event.
  final int code;

  /// Human-readable message describing the leave reason.
  final String message;

  const LeaveReason(this.code, this.message);

  /// @nodoc
  static LeaveReason fromCode(int code) {
    return LeaveReason.values.firstWhere(
      (e) => e.code == code,
      orElse: () => LeaveReason.unknown,
    );
  }
}
