// ignore_for_file: constant_identifier_names

import 'package:videosdk_webrtc/flutter_webrtc.dart';

extension PriorityExtension on RTCPriorityType {
  static const Map<String, RTCPriorityType> types = {
    'very-low': RTCPriorityType.veryLow,
    'low': RTCPriorityType.low,
    'medium': RTCPriorityType.medium,
    'high': RTCPriorityType.high,
  };

  static const Map<RTCPriorityType, String> values = {
    RTCPriorityType.veryLow: 'very-low',
    RTCPriorityType.low: 'low',
    RTCPriorityType.medium: 'medium',
    RTCPriorityType.high: 'high',
  };

  static RTCPriorityType fromString(String i) => types[i]!;
  String get value => values[this]!;
}
