import 'package:flutter_test/flutter_test.dart';
import 'package:videosdk/src/core/room/mic_config.dart';
import 'package:videosdk/videosdk.dart';

void main() {
  group('MicConfig.defaults', () {
    test('resolves the shipped defaults', () {
      final config = MicConfig.defaults();

      expect(config.encoderConfig, CustomAudioTrackConfig.speech_standard);
      expect(config.microphoneId, isNull);
      expect(config.noiseConfig, isNull);
    });
  });

  group('MicConfig.copyWith', () {
    test('changing only microphoneId leaves encoderConfig and noiseConfig', () {
      final original = MicConfig(
        microphoneId: 'mic-1',
        encoderConfig: CustomAudioTrackConfig.high_quality_stereo,
        noiseConfig: const {'echoCancellation': false},
      );

      final updated = original.copyWith(microphoneId: 'mic-2');

      expect(updated.microphoneId, 'mic-2');
      expect(updated.encoderConfig, original.encoderConfig);
      expect(updated.noiseConfig, original.noiseConfig);
    });

    test('changing only encoderConfig leaves microphoneId and noiseConfig', () {
      final original = MicConfig(
        microphoneId: 'mic-1',
        encoderConfig: CustomAudioTrackConfig.speech_standard,
      );

      final updated = original.copyWith(
          encoderConfig: CustomAudioTrackConfig.music_standard);

      expect(updated.encoderConfig, CustomAudioTrackConfig.music_standard);
      expect(updated.microphoneId, original.microphoneId);
      expect(updated.noiseConfig, original.noiseConfig);
    });

    test('with no arguments returns an equivalent, independent snapshot', () {
      final original = MicConfig(
        microphoneId: 'mic-1',
        encoderConfig: CustomAudioTrackConfig.high_quality,
        noiseConfig: const {'noiseSuppression': true},
      );

      final copy = original.copyWith();

      expect(copy.microphoneId, original.microphoneId);
      expect(copy.encoderConfig, original.encoderConfig);
      expect(copy.noiseConfig, original.noiseConfig);
    });

    test('clearMicrophoneId un-pins the device without touching the rest', () {
      final original = MicConfig(
        microphoneId: 'mic-1',
        encoderConfig: CustomAudioTrackConfig.high_quality,
        noiseConfig: const {'noiseSuppression': true},
      );

      final updated = original.copyWith(clearMicrophoneId: true);

      expect(updated.microphoneId, isNull);
      expect(updated.encoderConfig, original.encoderConfig);
      expect(updated.noiseConfig, original.noiseConfig);
    });

    test('clearMicrophoneId wins over a value passed alongside it', () {
      final original = MicConfig(microphoneId: 'mic-1');

      final updated = original.copyWith(
        microphoneId: 'mic-2',
        clearMicrophoneId: true,
      );

      expect(updated.microphoneId, isNull);
    });

    test('clearNoiseConfig un-sets noiseConfig', () {
      final original = MicConfig(
        microphoneId: 'mic-1',
        noiseConfig: const {'noiseSuppression': true},
      );

      final updated = original.copyWith(clearNoiseConfig: true);

      expect(updated.noiseConfig, isNull);
      expect(updated.microphoneId, 'mic-1');
    });

    test('passing null for a nullable field still means "leave it alone"', () {
      final original = MicConfig(
        microphoneId: 'mic-1',
        noiseConfig: const {'noiseSuppression': true},
      );

      final updated = original.copyWith(microphoneId: null, noiseConfig: null);

      expect(updated.microphoneId, 'mic-1');
      expect(updated.noiseConfig, original.noiseConfig);
    });
  });

  test('camera and mic configs are independent typed namespaces', () {
    final mic = MicConfig.defaults();
    final updatedMic = mic.copyWith(microphoneId: 'mic-1');

    // Constructing/copying a MicConfig never touches WebcamConfig state —
    // there's no shared mutable state between the two by construction, since
    // both are immutable value types. This documents that intent.
    expect(updatedMic.microphoneId, 'mic-1');
    expect(mic.microphoneId, isNull);
  });
}
