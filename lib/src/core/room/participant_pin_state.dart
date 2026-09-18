// ignore_for_file: constant_identifier_names

/// Defines the pinning behavior for a participant's media streams.
///
/// - This enum is used with the `pin()` and `unpin()` methods to control
/// whether a participant’s camera stream, screen share stream,
/// or both should be pinned.
///
/// ### **Example**
/// ```dart
/// participant.pin(PinType.CAM);
/// ```
enum PinType {
  /// Pins both the camera and screen share streams.
  ///
  /// ### **Example**
  /// ```dart
  /// PinType.SHARE_AND_CAM
  /// ```
  SHARE_AND_CAM,

  /// Pins only the camera stream.
  ///
  /// ### **Example**
  /// ```dart
  /// PinType.CAM
  /// ```
  CAM,

  /// Pins only the screen share stream.
  ///
  /// ### **Example**
  /// ```dart
  /// PinType.SHARE
  /// ```
  SHARE,
}

/// Represents the pin state of a participant's media streams.
///
/// - This class holds the state indicating whether a participant's camera
/// and/or screen share streams are currently pinned.
class ParticipantPinState {
  /// @nodoc
  @override
  String toString() {
    return super.toString();
  }

  /// @nodoc
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }

  /// @nodoc
  @override
  bool operator ==(Object other) {
    return super == other;
  }

  /// @nodoc
  @override
  int get hashCode => super.hashCode;

  /// Indicates whether the participant's camera stream is pinned.
  /// ### Type
  ///
  /// - `bool`
  bool cam;

  /// Indicates whether the participant's screen share stream is pinned.
  /// ### Type
  ///
  /// - `bool`
  bool share;

  /// @nodoc
  ParticipantPinState({this.cam = false, this.share = false});

  /// @nodoc
  factory ParticipantPinState.fromJson(Map<String, dynamic> json) =>
      ParticipantPinState(
        cam: json["cam"],
        share: json["share"],
      );

  /// Converts this [ParticipantPinState] instance into a JSON-compatible map.
  ///
  /// This method serializes the pin state data into a key-value structure
  /// that can be used for JSON encoding or network transmission.
  ///
  /// ### Returns
  ///
  /// - A `Map<String, dynamic>` containing the pin state properties:
  ///   - `cam`: `bool`
  ///   - `share`: `bool`
  ///
  /// ### **Example**
  /// ```dart
  /// final pinState = ParticipantPinState(cam: true, share: false);
  /// final json = pinState.toJson();
  /// print(json);
  /// // Output:
  /// // {
  /// //   'cam': true,
  /// //   'share': false
  /// // }
  /// ```
  /// @nodoc
  Map<String, dynamic> toJson() => {
        "cam": cam,
        "share": share,
      };
}
