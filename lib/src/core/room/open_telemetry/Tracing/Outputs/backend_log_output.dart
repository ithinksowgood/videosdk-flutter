import '../event_category.dart';
import '../log_level.dart';
import '../trace_output.dart';
import '../output_target.dart';
import '../sdk_tracer.dart';
import '../../videosdk_log.dart';

class BackendLogOutput implements TraceOutput {
  final String roomId;
  final String peerId;
  final Map<String, dynamic> logs;
  final String observabilityJwt;
  final Map<String, dynamic> deviceInfo;
  String? sessionId;
  final bool debugMode;
  late final Map<String, dynamic>? browserOrDeviceInfo;

  BackendLogOutput({
    required this.roomId,
    required this.peerId,
    required this.logs,
    required this.observabilityJwt,
    required this.deviceInfo,
    this.sessionId,
    required this.debugMode,
  }) {
    if (deviceInfo.containsKey('browserUserAgent')) {
      final browser = deviceInfo['browserUserAgent']['browser'];
      final os = deviceInfo['browserUserAgent']['os'];
      browserOrDeviceInfo = {
        'browserName': browser['name'],
        'browserVersion': browser['version'],
        'osName': os['name'],
        'osVersion': os['version'],
        'platform': deviceInfo['platform'],
      };
    } else if (deviceInfo.containsKey('deviceUserAgent')) {
      browserOrDeviceInfo = {
        'platform': deviceInfo['platform'],
        ...deviceInfo['deviceUserAgent'],
      };
    } else {
      browserOrDeviceInfo = null;
    }
  }

  @override
  Set<EventCategory> subscribedCategories = {
    EventCategory.error,
    EventCategory.warn,
    EventCategory.backendError,
  };

  @override
  bool canAccessSensitiveData = true;

  @override
  bool respectsLogLevel = false;

  LogLevel _level = LogLevel.info;

  @override
  int get outputBit => OutputTarget.toBackend.rawValue;

  @override
  void setLogLevel(LogLevel level) {
    _level = level;
  }

  void setSessionId(String? id) {
    sessionId = id;
  }

  @override
  void clearSpanHistory() {}

  @override
  void onSpanStarted({
    required String id,
    required String name,
    String? parentId,
    required Map<String, String> attributes,
    required EventCategory category,
    bool? dashboardLog,
  }) {}

  @override
  void onSpanEnded({
    required String id,
    required String name,
    required EventCategory category,
    required int durationMs,
    required bool success,
    required String message,
    required Map<String, String> attributes,
    bool? dashboardLog,
  }) {
    if (respectsLogLevel && !_level.shouldShow(category)) return;

    String logType;
    if (category == EventCategory.backendError ||
        category == EventCategory.error) {
      logType = "ERROR";
    } else if (category == EventCategory.warn) {
      logType = "WARN";
    } else {
      logType = "INFO";
    }

    _pushLogs(
      logType: logType,
      logText: message,
      attributes: attributes,
      dashboardLog: dashboardLog ?? false,
      spanId: id,
    );
  }

  @override
  void onEvent({
    required String name,
    required Map<String, String> attributes,
    String? parentId,
    required EventCategory category,
    bool? success,
    bool? dashboardLog,
  }) {
    if (respectsLogLevel && !_level.shouldShow(category)) return;

    String logType;
    if (category == EventCategory.backendError ||
        category == EventCategory.error) {
      logType = "ERROR";
    } else if (category == EventCategory.warn) {
      logType = "WARN";
    } else {
      logType = "INFO";
    }

    _pushLogs(
      logType: logType,
      logText: name,
      attributes: attributes,
      dashboardLog: dashboardLog ?? false,
    );
  }

  Future<void> _pushLogs({
    required String logType,
    required String logText,
    required Map<String, dynamic> attributes,
    bool dashboardLog = false,
    String? traceId,
    String? spanId,
  }) async {
    try {
      final bodyAttributes = {
        ...attributes,
        if (traceId != null) 'traceId': traceId,
        if (spanId != null) 'spanId': spanId,
      };
      // Remove component key if present
      bodyAttributes.remove(SdkTracer.COMPONENT_KEY);

      // Use VideoSDKLog for centralized logging
      VideoSDKLog.createLog(
        message: logText,
        logLevel: logType,
        attributes: bodyAttributes,
        dashboardLog: dashboardLog,
      );
    } catch (error) {
      // Silently fail
    }
  }
}
