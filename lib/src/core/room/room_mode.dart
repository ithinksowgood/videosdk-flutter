// Mode
// ignore_for_file: provide_deprecation_message, constant_identifier_names, deprecated_member_use_from_same_package

/// Defines the media participation mode of a participant in the room.
///
/// - This enum controls whether a participant can send and/or receive
/// audio and video streams. The selected mode can be updated at runtime
/// using the `changeMode()` method.
///
/// - When a participant’s mode changes, the [Events.participantModeChanged]
/// event is emitted with the participantId and the updated mode.
///
/// ### **Example**
/// ```dart
/// room.changeMode(Mode.SEND_AND_RECV);
/// ```
enum Mode {
  /// **Deprecated**
  ///
  /// Conference mode is deprecated and will be removed in future versions.
  /// - Use [Mode.SEND_AND_RECV] instead.
  ///
  /// ### **Example**
  /// ```dart
  /// Mode.CONFERENCE
  /// ```
  @deprecated
  CONFERENCE,

  /// **Deprecated**
  ///
  /// Viewer mode is deprecated and will be removed in future versions.
  /// - Use [Mode.RECV_ONLY] instead.
  ///
  /// ### **Example**
  /// ```dart
  /// Mode.VIEWER
  /// ```
  @deprecated
  VIEWER,

  /// Enables both sending and receiving of audio and video streams.
  ///
  /// - This is the default and recommended mode for most participants.
  ///
  /// ### **Example**
  /// ```dart
  /// Mode.SEND_AND_RECV
  /// ```
  SEND_AND_RECV,

  /// Disables sending and receiving of audio and video streams.
  ///
  /// - This mode is used only for signaling purposes.
  ///
  /// ### **Example**
  /// ```dart
  /// Mode.SIGNALLING_ONLY
  /// ```
  SIGNALLING_ONLY,

  /// Enables receiving audio and video streams without producing any.
  ///
  /// - Useful for participants who only need to watch or listen.
  ///
  /// ### **Example**
  /// ```dart
  /// Mode.RECV_ONLY
  /// ```
  RECV_ONLY,
}

Map<Mode, String> modesMap = {
  Mode.CONFERENCE: 'CONFERENCE',
  Mode.VIEWER: 'VIEWER',
  Mode.SEND_AND_RECV: 'SEND_AND_RECV',
  Mode.SIGNALLING_ONLY: 'SIGNALLING_ONLY',
  Mode.RECV_ONLY: 'RECV_ONLY',
};

extension ModeExtension on Mode {
  String parseToString() => modesMap[this] ?? 'SEND_AND_RECV';
  static Mode parseToEnum(String mode) {
    return mode == "SEND_AND_RECV"
        ? Mode.SEND_AND_RECV
        : mode == "SIGNALLING_ONLY"
            ? Mode.SIGNALLING_ONLY
            : mode == "RECV_ONLY"
                ? Mode.RECV_ONLY
                : mode == "CONFERENCE"
                    ? Mode.CONFERENCE
                    : mode == "VIEWER"
                        ? Mode.VIEWER
                        : Mode.SEND_AND_RECV;
  }
}
