import 'package:flutter_test/flutter_test.dart';
import 'package:videosdk/src/core/room/webcam_config.dart';
import 'package:videosdk/videosdk.dart';

void main() {
  group('WebcamConfig.defaults', () {
    test('resolves the shipped defaults', () {
      final config = WebcamConfig.defaults(multiStream: true);

      expect(config.encoderConfig, CustomVideoTrackConfig.h720p_w1280p);
      expect(config.facingMode, FacingMode.user);
      expect(config.codec, VideoCodec.VP8);
      expect(config.bitrateMode, BitrateMode.BALANCED);
      expect(config.maxLayer, 3);
      expect(config.cameraId, isNull);
    });

    test('multiStream comes from the meeting option, not a fixed default', () {
      expect(WebcamConfig.defaults(multiStream: true).multiStream, isTrue);
      expect(WebcamConfig.defaults(multiStream: false).multiStream, isFalse);
    });
  });

  group('WebcamConfig.copyWith', () {
    test('changing only cameraId and facingMode leaves every other field', () {
      final original = WebcamConfig(
        cameraId: 'front-cam',
        encoderConfig: CustomVideoTrackConfig.h1080p_w1920p,
        multiStream: true,
        bitrateMode: BitrateMode.HIGH_QUALITY,
        maxLayer: 2,
        codec: VideoCodec.H264,
        facingMode: FacingMode.user,
      );

      final updated = original.copyWith(
        cameraId: 'back-cam',
        facingMode: FacingMode.environment,
      );

      expect(updated.cameraId, 'back-cam');
      expect(updated.facingMode, FacingMode.environment);
      // Everything else is carried over unchanged.
      expect(updated.encoderConfig, original.encoderConfig);
      expect(updated.multiStream, original.multiStream);
      expect(updated.bitrateMode, original.bitrateMode);
      expect(updated.maxLayer, original.maxLayer);
      expect(updated.codec, original.codec);
    });

    test('changing only codec leaves every other field untouched', () {
      final original = WebcamConfig(
        cameraId: 'cam-1',
        encoderConfig: CustomVideoTrackConfig.h480p_w640p,
        multiStream: true,
        bitrateMode: BitrateMode.BANDWIDTH_OPTIMIZED,
        maxLayer: 1,
        codec: VideoCodec.AV1,
        facingMode: FacingMode.environment,
      );

      final updated = original.copyWith(codec: VideoCodec.VP8);

      expect(updated.codec, VideoCodec.VP8);
      expect(updated.cameraId, original.cameraId);
      expect(updated.encoderConfig, original.encoderConfig);
      expect(updated.multiStream, original.multiStream);
      expect(updated.bitrateMode, original.bitrateMode);
      expect(updated.maxLayer, original.maxLayer);
      expect(updated.facingMode, original.facingMode);
    });

    test('with no arguments returns an equivalent, independent snapshot', () {
      final original = WebcamConfig.defaults(multiStream: true);
      final copy = original.copyWith();

      expect(copy.cameraId, original.cameraId);
      expect(copy.encoderConfig, original.encoderConfig);
      expect(copy.multiStream, original.multiStream);
      expect(copy.bitrateMode, original.bitrateMode);
      expect(copy.maxLayer, original.maxLayer);
      expect(copy.codec, original.codec);
      expect(copy.facingMode, original.facingMode);
    });

    test('clearCameraId un-pins the device without touching the rest', () {
      final original = WebcamConfig(
        cameraId: 'cam-1',
        multiStream: true,
        maxLayer: 2,
        codec: VideoCodec.VP9,
        facingMode: FacingMode.environment,
      );

      final updated = original.copyWith(clearCameraId: true);

      expect(updated.cameraId, isNull);
      expect(updated.multiStream, original.multiStream);
      expect(updated.maxLayer, original.maxLayer);
      expect(updated.codec, original.codec);
      expect(updated.facingMode, original.facingMode);
    });

    test('clearCameraId wins over a value passed alongside it', () {
      final original = WebcamConfig(cameraId: 'cam-1', multiStream: false);

      final updated = original.copyWith(
        cameraId: 'cam-2',
        clearCameraId: true,
      );

      expect(updated.cameraId, isNull);
    });

    test('passing null for cameraId still means "leave it alone"', () {
      final original = WebcamConfig(cameraId: 'cam-1', multiStream: false);

      expect(original.copyWith(cameraId: null).cameraId, 'cam-1');
    });
  });

  group('WebcamConfig maxLayer normalization', () {
    test('clamps out-of-range values into 1..3', () {
      expect(WebcamConfig(multiStream: true, maxLayer: 0).maxLayer, 1);
      expect(WebcamConfig(multiStream: true, maxLayer: -5).maxLayer, 1);
      expect(WebcamConfig(multiStream: true, maxLayer: 9).maxLayer, 3);
      expect(WebcamConfig(multiStream: true, maxLayer: 99).maxLayer, 3);
    });

    test('keeps in-range values untouched', () {
      for (final layer in [1, 2, 3]) {
        expect(
            WebcamConfig(multiStream: true, maxLayer: layer).maxLayer, layer);
      }
    });

    test('copyWith routes through the same clamp', () {
      final base = WebcamConfig.defaults(multiStream: true);
      expect(base.copyWith(maxLayer: 7).maxLayer, 3);
      expect(base.copyWith(maxLayer: 0).maxLayer, 1);
    });
  });
}
