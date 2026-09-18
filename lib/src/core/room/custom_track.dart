// ignore_for_file: constant_identifier_names, strict_top_level_inference

import 'dart:developer';

import 'package:videosdk/src/core/room/codec.dart';
import 'package:videosdk_webrtc/flutter_webrtc.dart';
import 'package:videosdk/src/core/room/open_telemetry/videosdk_log.dart';
import 'package:videosdk/videosdk.dart';

/// Represents a custom media track.
///
/// - This class encapsulates a media stream and its configuration, such as
/// encoder settings and optimization modes. It supports both audio and video tracks.
class CustomTrack {
  /// The underlying WebRTC media stream.
  late MediaStream mediaStream;

  /// Configuration for video encoding.
  late CustomVideoTrackConfig videoEncoderConfig;

  /// Configuration for audio encoding.
  late CustomAudioTrackConfig audioEncoderConfig;

  /// Configuration for noise cancellation.
  late Map<String, bool>? noiseConfig;

  /// The type of the track (audio, video, or share).
  late CustomTrackKind kind;

  /// Whether the track supports multi-stream (simulcast).
  late bool multiStream;

  /// Indicates if the track has ended.
  bool ended = false;

  /// The bitrate mode for the track.
  BitrateMode bitrateMode = BitrateMode.BALANCED;

  VideoCodec codec = VideoCodec.VP8;

  /// The facing mode the camera was created with (video only).
  FacingMode? facingMode;

  /// The ID of the camera used for this track (video only).
  String? cameraId;

  /// The maximum spatial layer for video.
  int maxLayer = 3;

  /// The ID of the microphone used for this track (audio only).
  String? microphoneId;
  // late String optimizationMode;

  /// @nodoc
  CustomTrack.videoTrack({
    required this.mediaStream,
    this.kind = CustomTrackKind.VIDEO,
    this.videoEncoderConfig = CustomVideoTrackConfig.h720p_w1280p,
    required this.bitrateMode,
    required this.maxLayer,
    required this.codec,
    this.facingMode,
    this.cameraId,
    this.multiStream = true,
    // this.optimizationMode = "motion",
  });

  /// @nodoc
  CustomTrack.audioTrack(
      {required this.mediaStream,
      this.audioEncoderConfig = CustomAudioTrackConfig.speech_standard,
      this.noiseConfig,
      this.kind = CustomTrackKind.AUDIO,
      this.microphoneId});

  /// Disposes of the track and releases resources.
  ///
  /// - This method stops all tracks in the media stream and marks the [CustomTrack] as ended.
  ///
  /// ### **Example**
  /// ```dart
  /// await customTrack.dispose();
  /// ```
  Future<void> dispose() => _dispose();
  Future<void> _dispose() async {
    try {
      mediaStream.getTracks().forEach((track) {
        track.onEnded = null;
        track.stop();
      });
      ended = true;
    } catch (error) {
      //
      VideoSDKLog.createLog(
          message: "error in dispose() \n ${error.toString()}",
          logLevel: "ERROR");
      //
      log("ERROR: Unable to dispose track :: $error");
    }
  }

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

  /// Converts this [CustomTrack] instance into a map.
  ///
  /// ### Returns
  ///
  /// - A `Map<String, String>` containing the track configuration.
  ///
  /// ### **Example**
  /// ```dart
  /// Map<String, String> trackConfig = customTrack.toMap();
  /// ```
  /// @nodoc
  Map<String, String> toMap() {
    return {
      'kind': kind.toString(),
      if (kind.name == CustomTrackKind.AUDIO.name)
        'audioConfig': audioEncoderConfig.name,
      if (kind.name == CustomTrackKind.AUDIO.name)
        'noiseConfig': noiseConfig.toString(),
      if (kind.name == CustomTrackKind.VIDEO.name)
        'videoConfig': videoEncoderConfig.name,
      if (kind.name == CustomTrackKind.VIDEO.name)
        'multiStream': multiStream.toString(),
    };
  }
}

/// Defines the type of custom track.
enum CustomTrackKind {
  /// Audio track
  AUDIO,

  /// Video track
  VIDEO,

  /// Screen share track
  SHARE
}
