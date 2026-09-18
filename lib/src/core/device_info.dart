// ignore_for_file: constant_identifier_names

import 'package:videosdk_webrtc/flutter_webrtc.dart';

/// Defines the media permissions that can be requested by the application.
///
/// - This enum is used when checking or requesting permissions for
/// accessing audio and/or video devices.
///
/// ### **Example**
/// ```dart
/// final permissions = await VideoSDK.checkPermissions(Permissions.audio_video);
/// ```
enum Permissions {
  /// Permission to access audio input devices (microphone).
  ///
  /// ### **Example**
  /// ```dart
  /// Permissions.audio
  /// ```

  audio,

  /// Permission to access video input devices (camera).
  ///
  /// ### **Example**
  /// ```dart
  /// Permissions.video
  /// ```
  video,

  /// Permission to access both audio and video devices.
  ///
  /// ### **Example**
  /// ```dart
  /// Permissions.audio_video
  /// ```
  audio_video,
}

/// Base class for media device information.
/// @nodoc
class DeviceInfo extends MediaDeviceInfo {
  /// Creates a [DeviceInfo] instance.
  DeviceInfo({
    required super.deviceId,
    super.groupId,
    super.kind,
    required super.label,
  });
}

/// Represents information about a video input device (camera).
///
/// - This class extends [DeviceInfo] and provides metadata about
/// a camera device available on the system. Instances of this class
/// are returned by [VideoSDK.getVideoDevices()].
///
/// ### **Example**
/// ```dart
/// List<VideoDeviceInfo>? cameras = await VideoSDK.getVideoDevices();
///
/// if (cameras != null && cameras.isNotEmpty) {
///   for (final camera in cameras) {
///     print('Camera: ${camera.label} (${camera.deviceId})');
///   }
///
///   // Switch to a different camera
///   final VideoDeviceInfo deviceToSwitch = cameras.firstWhere(
///     (cam) => cam.deviceId != selectedCamId,
///   );
///
///   room.changeCam(deviceToSwitch);
/// }
/// ```
class VideoDeviceInfo extends DeviceInfo {
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

  /// @nodoc
  VideoDeviceInfo({
    required super.deviceId,
    super.groupId,
    super.kind,
    required super.label,
  });
}

/// Represents information about an audio input or output device.
///
/// - This class extends [DeviceInfo].
/// - It provides metadata about audio devices such as microphones and speakers.
/// - Instances of this class are returned by [VideoSDK.getAudioDevices()].
///
/// Depending on the value of [kind], an [AudioDeviceInfo] instance may represent:
/// - An audio input device (`audioinput`), such as a microphone.
/// - An audio output device (`audiooutput`), such as a speaker.
///
///
/// ### **Example**
/// ```dart
/// List<AudioDeviceInfo> mics = [];
/// List<AudioDeviceInfo> speakers = [];
///
/// final List<AudioDeviceInfo>? audioDevices =
///     await VideoSDK.getAudioDevices();
///
/// if (audioDevices != null) {
///   for (final device in audioDevices) {
///     if (device.kind == 'audioinput') {
///       mics.add(device);
///     } else if (device.kind == 'audiooutput') {
///       speakers.add(device);
///     }
///   }
///
///   print('Microphones: ${mics.length}');
///   print('Speakers: ${speakers.length}');
/// }
/// ```
class AudioDeviceInfo extends DeviceInfo {
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

  /// @nodoc
  AudioDeviceInfo({
    required super.deviceId,
    super.groupId,
    super.kind,
    required super.label,
  });
}
