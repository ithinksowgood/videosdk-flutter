// ignore_for_file: strict_top_level_inference

import 'dart:convert';
import 'dart:developer';

import 'package:http/http.dart' as http;
import 'package:videosdk/src/utils/constants.dart';

class VideoSDKLog {
  static String? meetingId;
  static String? sessionId;
  static String? peerId;
  // ignore: prefer_typing_uninitialized_variables
  static var logsConfig;
  static String? jwtKey;
  static Map<String, dynamic>? deviceInfo;
  static bool? debugMode;

  static createLog(
      {required String message,
      required String logLevel,
      Map? attributes,
      bool? dashboardLog}) {
    if (meetingId == null ||
        peerId == null ||
        logsConfig == null ||
        jwtKey == null) {
      return;
    }
    if (logsConfig['enabled']) {
      // Snapshot all values now (synchronous, cheap) so the microtask
      // closure captures stable copies and not stale references.
      final endpoint = logsConfig['endPoint'] as String;
      final jwt = jwtKey!;
      final body = <String, dynamic>{
        "logText": message,
        "logType": logLevel,
        "attributes": <String, dynamic>{
          "SDK": "flutter",
          "SDK_VERSION": sdkVersion,
          "roomId": meetingId,
          "peerId": peerId,
          "sessionId": sessionId,
          ...?deviceInfo,
          ...?attributes,
        },
        "dashboardLog": dashboardLog,
        "debugMode": debugMode,
      };

      // Defer json.encode + HTTP post off the caller's frame.
      // Errors are logged instead of silently swallowed.
      Future.microtask(() async {
        try {
          await http.post(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': jwt,
            },
            body: json.encode(body),
          );
        } catch (error) {
          log("Error in createLog() \n $error");
        }
      });
    }
  }
}
