import 'package:videosdk/videosdk.dart';

/// @nodoc
class MicConfig {
  final String? microphoneId;
  final CustomAudioTrackConfig encoderConfig;
  final Map<String, bool>? noiseConfig;

  const MicConfig({
    this.microphoneId,
    this.encoderConfig = CustomAudioTrackConfig.speech_standard,
    this.noiseConfig,
  });

  factory MicConfig.defaults() => const MicConfig();

  factory MicConfig.fromCustomTrack(CustomTrack track) => MicConfig(
        microphoneId: track.microphoneId,
        encoderConfig: track.audioEncoderConfig,
        noiseConfig: track.noiseConfig,
      );

  /// [clearMicrophoneId] / [clearNoiseConfig] reset their field to `null`.
  /// Passing `null` for a nullable field cannot express "clear it" — it is
  /// indistinguishable from "leave it alone" — and clearing [microphoneId] is
  /// what un-pins a device so a rebuild can fall back to the live selection
  /// again. The explicit flag wins over any value passed alongside it.
  MicConfig copyWith({
    String? microphoneId,
    bool clearMicrophoneId = false,
    CustomAudioTrackConfig? encoderConfig,
    Map<String, bool>? noiseConfig,
    bool clearNoiseConfig = false,
  }) =>
      MicConfig(
        microphoneId:
            clearMicrophoneId ? null : (microphoneId ?? this.microphoneId),
        encoderConfig: encoderConfig ?? this.encoderConfig,
        noiseConfig:
            clearNoiseConfig ? null : (noiseConfig ?? this.noiseConfig),
      );
}
