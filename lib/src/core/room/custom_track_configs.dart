// ignore_for_file: constant_identifier_names

import 'package:videosdk/videosdk.dart';

/// Defines video resolution and encoding presets for camera video tracks.
///
/// - These presets control the width and height of the video stream and
/// are used while creating a custom camera video track.
///
/// ### **Example**
/// ```dart
/// final videoTrack = await VideoSDK.createCameraVideoTrack(
///   encoderConfig: CustomVideoTrackConfig.h720p_w1280p,
/// );
/// ```
enum CustomVideoTrackConfig {
  /// 160x90 video resolution.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h90p_w160p
  /// ```
  h90p_w160p,

  /// 320x180 video resolution.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h180p_w320p
  /// ```
  h180p_w320p,

  /// 384x216 video resolution.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h216p_w384p
  /// ```
  h216p_w384p,

  /// 640x360 video resolution (SD).
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h360p_w640p
  /// ```
  h360p_w640p,

  /// 960x540 video resolution.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h540p_w960p
  /// ```
  h540p_w960p,

  /// 1280x720 video resolution (HD).
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h720p_w1280p
  /// ```
  h720p_w1280p,

  /// 1920x1080 video resolution (Full HD).
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h1080p_w1920p
  /// ```
  h1080p_w1920p,

  /// 2560x1440 video resolution (2K).
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h1440p_w2560p
  /// ```
  h1440p_w2560p,

  /// 3840x2160 video resolution (4K).
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h2160p_w3840p
  /// ```
  h2160p_w3840p,

  /// 160x120 video resolution.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h120p_w160p
  /// ```
  h120p_w160p,

  /// 192x144 video resolution.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h144_w192p
  /// ```
  h144_w192p,

  /// 240x180 video resolution.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h180p_w240p
  /// ```
  h180p_w240p,

  /// 320x240 video resolution.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h240p_w320p
  /// ```
  h240p_w320p,

  /// 480x360 video resolution.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h360p_w480p
  /// ```
  h360p_w480p,

  /// 640x480 video resolution.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h480p_w640p
  /// ```
  h480p_w640p,

  /// 720x540 video resolution.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h540p_w720p
  /// ```
  h540p_w720p,

  /// 960x720 video resolution.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h720p_w960p
  /// ```
  h720p_w960p,

  /// 1440x1080 video resolution.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h1080p_w1440p
  /// ```
  h1080p_w1440p,

  /// 1920x1440 video resolution.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomVideoTrackConfig.h1440p_w1920p
  /// ```
  h1440p_w1920p,
}

/// Defines audio quality presets for microphone audio tracks.
///
/// - These presets control audio bitrate, channel configuration,
/// and overall sound quality.
///
/// ### **Encoder Config Reference**
///
/// | Encoder Config        | Bitrate   | Auto Gain | Echo Cancellation | Noise Suppression |
/// |-----------------------|-----------|-----------|-------------------|-------------------|
/// | speech_low_quality    | 16 kbps   | TRUE      | TRUE              | TRUE              |
/// | speech_standard       | 24 kbps   | TRUE      | TRUE              | TRUE              |
/// | music_standard        | 32 kbps   | FALSE     | FALSE             | FALSE             |
/// | standard_stereo       | 64 kbps   | FALSE     | FALSE             | FALSE             |
/// | high_quality          | 128 kbps  | FALSE     | TRUE              | FALSE             |
/// | high_quality_stereo   | 192 kbps  | FALSE     | FALSE             | FALSE             |
///
/// > **Note:** If you face issues related to echo, you can use `noiseConfig`
/// > with `echoCancellation: true`. Echo cancellation attempts to prevent echo
/// > effects on a two-way audio connection by reducing or eliminating crosstalk
/// > between the user's output device and their input device — for example,
/// > filtering out sound produced by the speakers from being captured by the
/// > microphone input track.
///
/// ### **Example**
/// ```dart
/// final audioTrack = await VideoSDK.createMicrophoneAudioTrack(
///   encoderConfig: CustomAudioTrackConfig.high_quality,
/// );
/// ```
///
enum CustomAudioTrackConfig {
  /// Low-quality speech-optimized audio.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomAudioTrackConfig.speech_low_quality
  /// ```
  speech_low_quality,

  /// Standard-quality speech audio (recommended).
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomAudioTrackConfig.speech_standard
  /// ```
  speech_standard,

  /// Standard-quality music audio.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomAudioTrackConfig.music_standard
  /// ```
  music_standard,

  /// Stereo audio with standard quality.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomAudioTrackConfig.standard_stereo
  /// ```
  standard_stereo,

  /// High-quality mono audio.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomAudioTrackConfig.high_quality
  /// ```
  high_quality,

  /// High-quality stereo audio.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomAudioTrackConfig.high_quality_stereo
  /// ```
  high_quality_stereo,
}

/// Defines resolution and frame-rate presets for screen sharing.
///
/// - These presets control the quality and frame rate of the
/// screen-sharing video stream.
///
/// ### **Example**
/// ```dart
/// final shareTrack = await VideoSDK.createScreenShareVideoTrack(
///   encoderConfig: CustomScreenShareTrackConfig.h1080p_30fps,
/// );
/// ```
enum CustomScreenShareTrackConfig {
  /// 360p screen share at 30 FPS.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomScreenShareTrackConfig.h360p_30fps
  /// ```
  h360p_30fps,

  /// 720p screen share at 5 FPS.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomScreenShareTrackConfig.h720p_5fps
  /// ```
  h720p_5fps,

  /// 720p screen share at 15 FPS.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomScreenShareTrackConfig.h720p_15fps
  /// ```
  h720p_15fps,

  /// 1080p screen share at 15 FPS.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomScreenShareTrackConfig.h1080p_15fps
  /// ```
  h1080p_15fps,

  /// 1080p screen share at 30 FPS.
  ///
  /// ### **Example**
  /// ```dart
  /// encoderConfig: CustomScreenShareTrackConfig.h1080p_30fps
  /// ```
  h1080p_30fps,
}

Map<CustomAudioTrackConfig, Map<String, dynamic>> customAudioTrackConfigMap = {
  CustomAudioTrackConfig.speech_low_quality: {
    "sampleRate": 16000,
    "bitRate": 24,
    "sampleSize": 16,
    "stereo": false,
    "dtx": true,
    "fec": true,
    "maxPlaybackRate": 16000,
    "packetTime": 20,
    "autoGainControl": true,
    "echoCancellation": true,
    "noiseSuppression": true,
    "channelCount": 1
  },
  CustomAudioTrackConfig.speech_standard: {
    "sampleRate": 32000,
    "bitRate": 24,
    "sampleSize": 24,
    "stereo": false,
    "dtx": true,
    "fec": true,
    "maxPlaybackRate": 32000,
    "packetTime": 30,
    "autoGainControl": true,
    "echoCancellation": true,
    "noiseSuppression": true,
    "channelCount": 1
  },
  CustomAudioTrackConfig.music_standard: {
    "sampleRate": 48000,
    "bitRate": 40,
    "sampleSize": 32,
    "stereo": false,
    "dtx": false,
    "fec": true,
    "maxPlaybackRate": 48000,
    "packetTime": 40,
    "autoGainControl": false,
    "echoCancellation": false,
    "noiseSuppression": false,
    "channelCount": 1
  },
  CustomAudioTrackConfig.standard_stereo: {
    "sampleRate": 48000,
    "sampleSize": 32,
    "bitRate": 64,
    "stereo": true,
    "dtx": false,
    "fec": true,
    "maxPlaybackRate": 48000,
    "packetTime": 40,
    "autoGainControl": false,
    "echoCancellation": false,
    "noiseSuppression": false,
    "channelCount": 2
  },
  CustomAudioTrackConfig.high_quality: {
    "sampleRate": 48000,
    "sampleSize": 32,
    "bitRate": 128,
    "stereo": false,
    "dtx": false,
    "fec": true,
    "maxPlaybackRate": 48000,
    "packetTime": 60,
    "autoGainControl": false,
    "echoCancellation": false,
    "noiseSuppression": false,
    "channelCount": 1
  },
  CustomAudioTrackConfig.high_quality_stereo: {
    "sampleRate": 48000,
    "sampleSize": 32,
    "bitRate": 192,
    "stereo": true,
    "dtx": false,
    "fec": true,
    "maxPlaybackRate": 48000,
    "packetTime": 60,
    "autoGainControl": false,
    "echoCancellation": false,
    "noiseSuppression": false,
    "channelCount": 2
  }
};

Map<CustomVideoTrackConfig, Map<String, dynamic>> customVideotrackConfigMap = {
  // ToDo: portrait mode
  // mobile and web both
  CustomVideoTrackConfig.h90p_w160p: {
    "width": 160,
    "height": 90,
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 60 * 1000,
      BitrateMode.BALANCED.name: 100 * 1000,
      BitrateMode.HIGH_QUALITY.name: 150 * 1000,
    },
    "frameRate": 15,
    "aspectRatio": "oneSixNine",
  },
  // only web
  CustomVideoTrackConfig.h180p_w320p: {
    "width": 320,
    "height": 180,
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 100 * 1000,
      BitrateMode.BALANCED.name: 150 * 1000,
      BitrateMode.HIGH_QUALITY.name: 250 * 1000,
    },
    "frameRate": 15,
    "aspectRatio": "oneSixNine"
  },
  // only web
  CustomVideoTrackConfig.h216p_w384p: {
    "width": 384,
    "height": 216,
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 120 * 1000,
      BitrateMode.BALANCED.name: 200 * 1000,
      BitrateMode.HIGH_QUALITY.name: 350 * 1000,
    },
    "frameRate": 15,
    "aspectRatio": "oneSixNine"
  },
  // mobile and web both
  CustomVideoTrackConfig.h360p_w640p: {
    "width": 640,
    "height": 360,
    "frameRate": 20,
    "aspectRatio": "oneSixNine",
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 200 * 1000,
      BitrateMode.BALANCED.name: 400 * 1000,
      BitrateMode.HIGH_QUALITY.name: 600 * 1000,
    }
  },
  // only web
  CustomVideoTrackConfig.h540p_w960p: {
    "width": 960,
    "height": 540,
    "frameRate": 25,
    "aspectRatio": "oneSixNine",
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 400 * 1000,
      BitrateMode.BALANCED.name: 600 * 1000,
      BitrateMode.HIGH_QUALITY.name: 800 * 1000,
    }
  },
  // mobile and web both
  CustomVideoTrackConfig.h720p_w1280p: {
    "width": 1280,
    "height": 720,
    "bitRate": 2000 * 1000,
    "frameRate": 30,
    "aspectRatio": "oneSixNine",
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 1000 * 1000,
      BitrateMode.BALANCED.name: 1500 * 1000,
      BitrateMode.HIGH_QUALITY.name: 2000 * 1000,
    }
  },
  // mobile and web both
  CustomVideoTrackConfig.h1080p_w1920p: {
    "width": 1920,
    "height": 1080,
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 1600 * 1000,
      BitrateMode.BALANCED.name: 2300 * 1000,
      BitrateMode.HIGH_QUALITY.name: 2700 * 1000,
    },
    "frameRate": 30,
    "aspectRatio": "oneSixNine"
  },
  // mobile and web both
  CustomVideoTrackConfig.h1440p_w2560p: {
    "width": 2560,
    "height": 1440,
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 5000 * 1000,
      BitrateMode.BALANCED.name: 5500 * 1000,
      BitrateMode.HIGH_QUALITY.name: 6000 * 1000,
    },
    "frameRate": 30,
    "aspectRatio": "oneSixNine"
  },
  // mobile and web both
  CustomVideoTrackConfig.h2160p_w3840p: {
    "width": 3840,
    "height": 2160,
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 8000 * 1000,
      BitrateMode.BALANCED.name: 8500 * 1000,
      BitrateMode.HIGH_QUALITY.name: 9000 * 1000,
    },
    "frameRate": 30,
    "aspectRatio": "oneSixNine"
  },
  // only web
  CustomVideoTrackConfig.h120p_w160p: {
    "width": 160,
    "height": 120,
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 60 * 1000,
      BitrateMode.BALANCED.name: 100 * 1000,
      BitrateMode.HIGH_QUALITY.name: 150 * 1000,
    },
    "frameRate": 15,
    "aspectRatio": "fourThree"
  },
  // mobile and web both
  CustomVideoTrackConfig.h144_w192p: {
    "width": 192,
    "height": 144,
    "frameRate": 15,
    "aspectRatio": "fourThree",
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 60 * 1000,
      BitrateMode.BALANCED.name: 100 * 1000,
      BitrateMode.HIGH_QUALITY.name: 150 * 1000,
    }
  },
  // only web
  CustomVideoTrackConfig.h180p_w240p: {
    "width": 240,
    "height": 180,
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 100 * 1000,
      BitrateMode.BALANCED.name: 150 * 1000,
      BitrateMode.HIGH_QUALITY.name: 250 * 1000,
    },
    "frameRate": 15,
    "aspectRatio": "fourThree"
  },
  // mobile and web both
  CustomVideoTrackConfig.h240p_w320p: {
    "width": 320,
    "height": 240,
    "frameRate": 15,
    "aspectRatio": "fourThree",
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 120 * 1000,
      BitrateMode.BALANCED.name: 200 * 1000,
      BitrateMode.HIGH_QUALITY.name: 350 * 1000,
    },
  },
  // only web
  CustomVideoTrackConfig.h360p_w480p: {
    "width": 480,
    "height": 360,
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 200 * 1000,
      BitrateMode.BALANCED.name: 400 * 1000,
      BitrateMode.HIGH_QUALITY.name: 600 * 1000,
    },
    "frameRate": 20,
    "aspectRatio": "fourThree"
  },
  // mobile and web both
  CustomVideoTrackConfig.h480p_w640p: {
    "width": 640,
    "height": 480,
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 300 * 1000,
      BitrateMode.BALANCED.name: 500 * 1000,
      BitrateMode.HIGH_QUALITY.name: 750 * 1000,
    },
    "frameRate": 25,
    "aspectRatio": "fourThree"
  },
  // only web
  CustomVideoTrackConfig.h540p_w720p: {
    "width": 720,
    "height": 540,
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 350 * 1000,
      BitrateMode.BALANCED.name: 650 * 1000,
      BitrateMode.HIGH_QUALITY.name: 800 * 1000,
    },
    "frameRate": 30,
    "aspectRatio": "fourThree"
  },
  // mobile and web both
  CustomVideoTrackConfig.h720p_w960p: {
    "width": 960,
    "height": 720,
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 800 * 1000,
      BitrateMode.BALANCED.name: 1200 * 1000,
      BitrateMode.HIGH_QUALITY.name: 1600 * 1000,
    },
    "frameRate": 30,
    "aspectRatio": "fourThree"
  },
  // mobile and web both
  CustomVideoTrackConfig.h1080p_w1440p: {
    "width": 1440,
    "height": 1080,
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 1600 * 1000,
      BitrateMode.BALANCED.name: 2200 * 1000,
      BitrateMode.HIGH_QUALITY.name: 2700 * 1000,
    },
    "frameRate": 30,
    "aspectRatio": "fourThree"
  },
  // mobile and web both
  CustomVideoTrackConfig.h1440p_w1920p: {
    "width": 1920,
    "height": 1440,
    "bitrates": {
      BitrateMode.BANDWIDTH_OPTIMIZED.name: 3500 * 1000,
      BitrateMode.BALANCED.name: 4000 * 1000,
      BitrateMode.HIGH_QUALITY.name: 4500 * 1000,
    },
    "frameRate": 30,
    "aspectRatio": "fourThree"
  }
};

Map<CustomScreenShareTrackConfig, Map<String, dynamic>>
    customScreenShareTrackConfig = {
  CustomScreenShareTrackConfig.h360p_30fps: {
    "width": 640,
    "height": 360,
    "bitRate": 200 * 1000,
    "frameRate": 3
  },
  CustomScreenShareTrackConfig.h720p_5fps: {
    "width": 1280,
    "height": 720,
    "bitRate": 400 * 1000,
    "frameRate": 5
  },
  CustomScreenShareTrackConfig.h720p_15fps: {
    "width": 1280,
    "height": 720,
    "bitRate": 1000 * 1000,
    "frameRate": 15
  },
  CustomScreenShareTrackConfig.h1080p_15fps: {
    "width": 1920,
    "height": 1080,
    "bitRate": 1500 * 1000,
    "frameRate": 15
  },
  CustomScreenShareTrackConfig.h1080p_30fps: {
    "width": 1920,
    "height": 1080,
    "bitRate": 1000 * 1000,
    "frameRate": 15
  }
};
