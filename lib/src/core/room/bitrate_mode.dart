/// Defines the video bitrate optimization mode.
///
/// - Use this enum to control how VideoSDK optimizes video quality versus bandwidth usage.
/// - Different modes provide different trade-offs between video quality and network bandwidth.
///
/// ## Usage
///
/// ```dart
/// final customConfig = CustomVideoTrackConfig(
///   bitrateMode: BitrateMode.HIGH_QUALITY,
/// );
/// ```
///
enum BitrateMode {
  /// Optimizes video streaming for minimal bandwidth usage.
  ///
  /// - This mode prioritizes network stability over video quality,
  /// making it suitable for poor or unstable network conditions.
  ///
  /// ### **Example**
  /// ```dart
  /// final videoTrack = await VideoSDK.createCameraVideoTrack(
  ///   bitrateMode: BitrateMode.BANDWIDTH_OPTIMIZED,
  /// );
  /// ```
  // ignore: constant_identifier_names
  BANDWIDTH_OPTIMIZED,

  /// Balances video quality and bandwidth usage.
  ///
  /// - This mode provides a good trade-off between quality and
  /// network efficiency and is recommended for most use cases.
  ///
  /// ### **Example**
  /// ```dart
  /// final videoTrack = await VideoSDK.createCameraVideoTrack(
  ///   bitrateMode: BitrateMode.BALANCED,
  /// );
  /// ```
  // ignore: constant_identifier_names
  BALANCED,

  /// Optimizes video streaming for maximum video quality.
  ///
  /// - This mode delivers the best visual quality and is suitable
  /// for high-speed and stable network connections.
  ///
  /// ### **Example**
  /// ```dart
  /// final videoTrack = await VideoSDK.createCameraVideoTrack(
  ///   bitrateMode: BitrateMode.HIGH_QUALITY,
  /// );
  /// ```
  // ignore: constant_identifier_names
  HIGH_QUALITY,
}

/// @nodoc
extension BitrateModeExtension on BitrateMode {
  /// @nodoc
  String parseToString() => name;

  /// @nodoc
  static BitrateMode parseToEnum(String mode) {
    switch (mode) {
      case 'BANDWIDTH_OPTIMIZED':
        return BitrateMode.BANDWIDTH_OPTIMIZED;
      case 'HIGH_QUALITY':
        return BitrateMode.HIGH_QUALITY;
      case 'BALANCED':
      default:
        return BitrateMode.BALANCED;
    }
  }
}
