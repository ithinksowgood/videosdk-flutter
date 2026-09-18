import 'dart:developer';
import 'dart:io';
// ignore: library_prefixes
import 'dart:math' as Math;

import 'package:flutter/foundation.dart';
import 'package:videosdk/src/core/room/custom_track_configs.dart';
import 'package:videosdk/src/core/webrtc/webrtc_client.dart';
import 'package:videosdk/videosdk.dart';

class SdkCapabilities {
  static var videoRids = ['q', 'h', 'f'];

  static int _selectBitrateFromConfig(
      Map<dynamic, dynamic> config, BitrateMode mode) {
    final dynamic bitrateMap = config['bitrates'];

    return bitrateMap[mode.name] as int;
  }

  static List<dynamic> getResolutionScalings(List<dynamic> encodings) {
    List<dynamic> resolutionScalings = [];

    if (encodings.isEmpty) {
      return resolutionScalings;
    }

    if (encodings.length == 1) {
      const spatialLayers = 3;
      for (int i = 0; i < spatialLayers; i++) {
        resolutionScalings.add(Math.pow(2, (spatialLayers - i - 1)));
      }

      return resolutionScalings;
    }

    // Simulcast encodings
    bool scaleResolutionDownByDefined = false;

    for (var encoding in encodings) {
      if (encoding['scaleResolutionDownBy'] != null) {
        // at least one scaleResolutionDownBy is defined
        scaleResolutionDownByDefined = true;
        // scaleResolutionDownBy must be >= 1.0
        resolutionScalings
            .add(Math.max(1, encoding['scaleResolutionDownBy'] as num));
      } else {
        // If encodings contains any encoding whose scaleResolutionDownBy
        // attribute is defined, set any undefined scaleResolutionDownBy
        // of the other encodings to 1.0.
        resolutionScalings.add(1.0);
      }
    }

    // If the scaleResolutionDownBy attribues of sendEncodings are
    // still undefined, initialize each encoding's scaleResolutionDownBy
    // to 2^(length of sendEncodings - encoding index - 1).
    if (!scaleResolutionDownByDefined) {
      for (var i = 0; i < encodings.length; i++) {
        resolutionScalings[i] = Math.pow(2, encodings.length - i - 1);
      }
    }

    return resolutionScalings;
  }

  static Map<String, dynamic>? getAdaptivePreferredLayers(
      Consumer consumer, viewportWidth, viewportHeight) {
    Map<String, dynamic> result = {};
    result.putIfAbsent('consumerId', () => consumer.id);
    try {
      int width = consumer.appData['width'];
      int height = consumer.appData['height'];
      List<dynamic> encodings = consumer.appData['encodings'];

      List<dynamic> resolutionScalings = getResolutionScalings(encodings);
      log(resolutionScalings.toString());
      const adaptiveScalingFactor = 0.75;

      int newPreferredSpatialLayer = 0;
      for (int i = 0; i < resolutionScalings.length; i++) {
        var levelWidth = adaptiveScalingFactor * width / resolutionScalings[i];
        var levelHeight =
            adaptiveScalingFactor * height / resolutionScalings[i];
        log("levelWidth = $levelWidth");
        log("levelHeight = $levelHeight");
        if (viewportWidth >= levelWidth && viewportHeight >= levelHeight) {
          newPreferredSpatialLayer = i;
        } else {
          break;
        }
      }

      var newPreferredTemporalLayer = consumer.temporalLayer;
      log(consumer.temporalLayer.toString());

      if (newPreferredSpatialLayer == 0 && newPreferredTemporalLayer > 0) {
        var lowestLevelWidth = width / resolutionScalings[0];
        var lowestLevelHeight = height / resolutionScalings[0];

        if (viewportWidth < lowestLevelWidth * 0.5 &&
            viewportHeight < lowestLevelHeight * 0.5) {
          newPreferredTemporalLayer -= 1;
        }
        if (newPreferredTemporalLayer > 0 &&
            viewportWidth < lowestLevelWidth * 0.25 &&
            viewportHeight < lowestLevelHeight * 0.25) {
          newPreferredTemporalLayer -= 1;
        }
      }

      result.addAll({
        'newPreferredSpatialLayer': newPreferredSpatialLayer,
        'newPreferredTemporalLayer': newPreferredTemporalLayer,
      });
    } catch (exception) {
      //
      return null;
    }
    return result;
  }

  static List<RtpEncodingParameters> computeVideoEncodings(
      bool isScreenShare,
      int width,
      int height,
      Map<String, dynamic> options,
      int maxLayer,
      BitrateMode mode) {
    List<RtpEncodingParameters> encodings = [];
    final RtpEncodingParameters initialEncoding =
        determineAppropriateEncoding(isScreenShare, width, height, mode);
    bool useSimulcast = options["simulcast"];
    encodings.add(initialEncoding);
    if (maxLayer == 1) {
      useSimulcast = false;
    }

    if (!useSimulcast) {
      return encodings;
    }

    Map<String, dynamic> original = {
      "width": width,
      "height": height,
      "encoding": RtpEncodingParameters(
        maxBitrate: initialEncoding.maxBitrate,
        maxFramerate: initialEncoding.maxFramerate,
      )
    };

    List<Map<String, dynamic>> presets =
        defaultSimulcastLayers(isScreenShare, original, mode);
    Map<String, dynamic>? midPreset;
    Map<String, dynamic> lowPreset = presets.first;

    if (maxLayer >= 3) {
      midPreset = presets.elementAt(1);
    }

    int size = Math.max(width, height);
    if (size >= 960 && midPreset != null) {
      return encodingsFromPresets(
          width, height, [lowPreset, midPreset, original]);
    }

    if (size >= 480) {
      return encodingsFromPresets(width, height, [lowPreset, original]);
    }

    return encodingsFromPresets(width, height, [original]);
  }

  static List<Map<String, dynamic>> defaultSimulcastLayers(
    bool isScreenShare,
    Map<String, dynamic> original,
    BitrateMode mode,
  ) {
    if (isScreenShare) {}

    final int width = original['width'];
    final int height = original['height'];

    final double aspect = width > height ? width / height : height / width;

    final bool is169 = (aspect - 16.0 / 9).abs() < (aspect - 4.0 / 3).abs();

    if (is169) {
      final preset169 = _getPresets169(mode);
      return getSimulcastPresets169(height, preset169);
    } else {
      final preset43 = _getPresets43(mode);
      return getSimulcastPresets43(height, preset43);
    }
  }

  static List<Map<String, dynamic>> getSimulcastPresets169(
    int height,
    Map<String, Map<String, dynamic>> preset169,
  ) {
    final platformKey =
        (!kIsWeb && (Platform.isAndroid || Platform.isIOS && !kIsWeb))
            ? 'mobile'
            : 'web';

    final presets = simulcastPresets169ByPlatform(preset169)[platformKey]!;

    if (height >= 2160 && presets["2160"] != null) return presets["2160"]!;
    if (height >= 1440 && presets["1440"] != null) return presets["1440"]!;
    if (height >= 1080 && presets["1080"] != null) return presets["1080"]!;

    return presets["default"]!;
  }

  static List<Map<String, dynamic>> getSimulcastPresets43(
    int height,
    Map<String, Map<String, dynamic>> preset43,
  ) {
    final platformKey =
        (!kIsWeb && (Platform.isAndroid || Platform.isIOS && !kIsWeb))
            ? 'mobile'
            : 'web';

    final presets = simulcastPresets43ByPlatform(preset43)[platformKey]!;

    if (height >= 1440 && presets["1440"] != null) return presets["1440"]!;
    if (height >= 1080 && presets["1080"] != null) return presets["1080"]!;

    return presets["default"]!;
  }

  static Map<String, Map<String, List<Map<String, dynamic>>>>
      simulcastPresets169ByPlatform(
    Map<String, Map<String, dynamic>> preset169,
  ) {
    return {
      'web': {
        "default": [
          preset169[CustomVideoTrackConfig.h180p_w320p.name]!,
          preset169[CustomVideoTrackConfig.h360p_w640p.name]!,
        ],
        "1080": [
          preset169[CustomVideoTrackConfig.h360p_w640p.name]!,
          preset169[CustomVideoTrackConfig.h540p_w960p.name]!,
        ],
        "1440": [
          preset169[CustomVideoTrackConfig.h360p_w640p.name]!,
          preset169[CustomVideoTrackConfig.h720p_w1280p.name]!,
        ],
        "2160": [
          preset169[CustomVideoTrackConfig.h540p_w960p.name]!,
          preset169[CustomVideoTrackConfig.h1080p_w1920p.name]!,
        ],
      },
      'mobile': {
        "default": [
          preset169[CustomVideoTrackConfig.h90p_w160p.name]!,
          preset169[CustomVideoTrackConfig.h360p_w640p.name]!,
        ],
        "1080": [
          preset169[CustomVideoTrackConfig.h360p_w640p.name]!,
          preset169[CustomVideoTrackConfig.h720p_w1280p.name]!,
        ],
        "1440": [
          preset169[CustomVideoTrackConfig.h360p_w640p.name]!,
          preset169[CustomVideoTrackConfig.h720p_w1280p.name]!,
        ],
        "2160": [
          preset169[CustomVideoTrackConfig.h720p_w1280p.name]!,
          preset169[CustomVideoTrackConfig.h1080p_w1920p.name]!,
        ],
      },
    };
  }

  static Map<String, Map<String, List<Map<String, dynamic>>>>
      simulcastPresets43ByPlatform(
    Map<String, Map<String, dynamic>> preset43,
  ) {
    return {
      'web': {
        "default": [
          preset43[CustomVideoTrackConfig.h180p_w240p.name]!,
          preset43[CustomVideoTrackConfig.h360p_w480p.name]!,
        ],
        "1080": [
          preset43[CustomVideoTrackConfig.h360p_w480p.name]!,
          preset43[CustomVideoTrackConfig.h540p_w720p.name]!,
        ],
        "1440": [
          preset43[CustomVideoTrackConfig.h360p_w480p.name]!,
          preset43[CustomVideoTrackConfig.h720p_w960p.name]!,
        ],
      },
      'mobile': {
        "default": [
          preset43[CustomVideoTrackConfig.h240p_w320p.name]!,
          preset43[CustomVideoTrackConfig.h480p_w640p.name]!,
        ],
        "1080": [
          preset43[CustomVideoTrackConfig.h480p_w640p.name]!,
          preset43[CustomVideoTrackConfig.h720p_w960p.name]!,
        ],
        "1440": [
          preset43[CustomVideoTrackConfig.h480p_w640p.name]!,
          preset43[CustomVideoTrackConfig.h720p_w960p.name]!,
        ],
      },
    };
  }

  static List<RtpEncodingParameters> encodingsFromPresets(
      int width, int height, List<Map<String, dynamic>> presets) {
    List<RtpEncodingParameters> encodings = [];

    for (int i = 0; i < presets.length; i++) {
      if (i >= videoRids.length) {
        continue;
      }
      Map<String, dynamic> preset = presets[i];

      int size = Math.min(width, height);
      String rid = videoRids[i];

      RtpEncodingParameters encoding = RtpEncodingParameters(
          rid: rid,
          scaleResolutionDownBy:
              size / Math.min(preset['width'], preset['height']),
          maxBitrate: (preset["encoding"] as RtpEncodingParameters).maxBitrate,
          maxFramerate:
              (preset["encoding"] as RtpEncodingParameters).maxFramerate);
      encodings.add(encoding);
    }

    return encodings;
  }

  static RtpEncodingParameters determineAppropriateEncoding(
      bool isScreenShare, int width, int height, BitrateMode mode) {
    final List<Map<String, dynamic>> presets =
        presetsForResolution(isScreenShare, width, height, mode);

    if (presets.isEmpty) {
      return RtpEncodingParameters();
    }

    final int size = Math.max(width, height);
    Map<String, dynamic>? matchedPreset;

    for (int i = 0; i < presets.length; i++) {
      final Map<String, dynamic> preset = presets[i];
      final int presetSize = Math.max(preset['width'], preset['height']);
      if (presetSize >= size) {
        matchedPreset = preset;
        break;
      }
    }

    matchedPreset ??= presets.last;

    final RtpEncodingParameters encoding =
        matchedPreset['encoding'] as RtpEncodingParameters;

    return encoding;
  }

  static List<Map<String, dynamic>> presetsForResolution(
      bool isScreenShare, int width, int height, BitrateMode mode) {
    final List<Map<String, dynamic>> presets;

    if (isScreenShare) {
      presets = _getScreenSharePreset().values.toList();
    } else {
      double aspectRatio = width > height ? width / height : height / width;
      if ((aspectRatio - 16.0 / 9).abs() < (aspectRatio - 4.0 / 3).abs()) {
        presets = _getPresets169(mode).values.toList();
      } else {
        presets = _getPresets43(mode).values.toList();
      }
    }
    // This sort is needed in case the resolution array from the config file is not in sorted order.
    // Kept as a safety measure.
    presets.sort((a, b) {
      final int aSize = Math.max(a['width'], a['height']);
      final int bSize = Math.max(b['width'], b['height']);
      return aSize.compareTo(bSize);
    });

    return presets;
  }

  static Map<String, Map<String, dynamic>> _getScreenSharePreset() {
    Map<String, Map<String, dynamic>> presets = {};
    for (var config in customScreenShareTrackConfig.entries) {
      presets.putIfAbsent(config.key.name, () {
        return {
          "height": config.value["height"],
          "width": config.value["width"],
          "encoding": RtpEncodingParameters(
              maxBitrate: config.value['bitRate'],
              maxFramerate: config.value['frameRate'])
        };
      });
    }
    return presets;
  }

  static Map<String, Map<String, dynamic>> _getPresets169(BitrateMode mode) {
    Map<String, Map<String, dynamic>> presets = {};
    for (var config in customVideotrackConfigMap.entries) {
      if (config.value["aspectRatio"] == "oneSixNine") {
        presets.putIfAbsent(config.key.name, () {
          final int selectedBitrate =
              _selectBitrateFromConfig(config.value, mode);
          return {
            "height": config.value["height"],
            "width": config.value["width"],
            "encoding": RtpEncodingParameters(
                maxBitrate: selectedBitrate,
                maxFramerate: config.value['frameRate'])
          };
        });
      }
    }

    return presets;
  }

  static Map<String, Map<String, dynamic>> _getPresets43(BitrateMode mode) {
    Map<String, Map<String, dynamic>> presets = {};
    for (var config in customVideotrackConfigMap.entries) {
      if (config.value["aspectRatio"] == "fourThree") {
        presets.putIfAbsent(config.key.name, () {
          final int selectedBitrate =
              _selectBitrateFromConfig(config.value, mode);

          return {
            "height": config.value["height"],
            "width": config.value["width"],
            "encoding": RtpEncodingParameters(
                maxBitrate: selectedBitrate,
                maxFramerate: config.value['frameRate'])
          };
        });
      }
    }

    return presets;
  }
}
