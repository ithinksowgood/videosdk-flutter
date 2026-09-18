import 'package:videosdk/videosdk.dart';

/// @nodoc
class WebcamConfig {
  final String? cameraId;
  final CustomVideoTrackConfig encoderConfig;
  final bool multiStream;
  final BitrateMode bitrateMode;
  final int maxLayer;
  final VideoCodec codec;
  final FacingMode facingMode;

  WebcamConfig({
    this.cameraId,
    this.encoderConfig = CustomVideoTrackConfig.h720p_w1280p,
    required this.multiStream,
    this.bitrateMode = BitrateMode.BALANCED,
    int maxLayer = 3,
    this.codec = VideoCodec.VP8,
    this.facingMode = FacingMode.user,
    //Lenient normalization: a stale value reaching a rebuild deep in a
    //reconnect must never crash the meeting, so clamp instead of throwing.
  }) : maxLayer = maxLayer < 1
            ? 1
            : maxLayer > 3
                ? 3
                : maxLayer;

  /// The shipped defaults. [multiStream] has no fixed default — it comes
  /// from the meeting's own `multiStream` option at seed time.
  factory WebcamConfig.defaults({required bool multiStream}) =>
      WebcamConfig(multiStream: multiStream);

  factory WebcamConfig.fromCustomTrack(CustomTrack track) => WebcamConfig(
        cameraId: track.cameraId,
        encoderConfig: track.videoEncoderConfig,
        multiStream: track.multiStream,
        bitrateMode: track.bitrateMode,
        maxLayer: track.maxLayer,
        codec: track.codec,
        facingMode: track.facingMode ?? FacingMode.user,
      );

  /// [clearCameraId] resets [cameraId] to `null`. Passing `null` cannot
  /// express "clear it" — it is indistinguishable from "leave it alone" — and
  /// clearing [cameraId] is what un-pins a device so a rebuild can fall back
  /// to the live selection again. The flag wins over a value passed with it.
  WebcamConfig copyWith({
    String? cameraId,
    bool clearCameraId = false,
    CustomVideoTrackConfig? encoderConfig,
    bool? multiStream,
    BitrateMode? bitrateMode,
    int? maxLayer,
    VideoCodec? codec,
    FacingMode? facingMode,
  }) =>
      WebcamConfig(
        cameraId: clearCameraId ? null : (cameraId ?? this.cameraId),
        encoderConfig: encoderConfig ?? this.encoderConfig,
        multiStream: multiStream ?? this.multiStream,
        bitrateMode: bitrateMode ?? this.bitrateMode,
        maxLayer: maxLayer ?? this.maxLayer,
        codec: codec ?? this.codec,
        facingMode: facingMode ?? this.facingMode,
      );
}
