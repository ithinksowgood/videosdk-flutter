import 'package:videosdk_otel/api.dart';
import '../event_category.dart';
import '../log_level.dart';
import '../trace_output.dart';
import '../../videosdk_telemetry.dart';
import '../output_target.dart';

class TelemetryOutput implements TraceOutput {
  @override
  Set<EventCategory> subscribedCategories;
  @override
  bool canAccessSensitiveData;
  @override
  bool respectsLogLevel;

  TelemetryOutput({
    this.subscribedCategories = const {
      EventCategory.telemetry,
      EventCategory.error,
      EventCategory.debug,
    },
    this.canAccessSensitiveData = true,
    this.respectsLogLevel = false,
  });

  static VideoSDKTelemetery? _telemetry;
  static void setTelemetry(VideoSDKTelemetery telemetry) {
    _telemetry = telemetry;
  }

  static void clearTelemetry() {
    _telemetry = null;
  }

  final Map<String, Span> _activeSpans = {};
  LogLevel _configuredLevel = LogLevel.info;

  @override
  int get outputBit => OutputTarget.toTelemetry.rawValue;

  @override
  void setLogLevel(LogLevel level) {
    _configuredLevel = level;
  }

  @override
  void clearSpanHistory() {
    _activeSpans.clear();
  }

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
    final telemetry = _telemetry;
    if (telemetry == null) return;
    final span = _activeSpans[id];
    if (span == null) return;
    final status = success ? StatusCode.ok : StatusCode.error;
    telemetry.completeSpan(span: span, status: status, message: message);
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
    final telemetry = _telemetry;
    if (telemetry == null) return;
    if (respectsLogLevel && !_configuredLevel.shouldShow(category)) return;
    final attrs = Map<String, String>.from(attributes);
    attrs['category'] = category.name;
    Span? parentSpan;
    if (parentId != null) {
      parentSpan = _activeSpans[parentId];
    }
    parentSpan ??= telemetry.getCurrentSpan();
    final status = (success ?? false) ? StatusCode.ok : StatusCode.error;
    telemetry.traceAutoComplete(
      spanName: name,
      attributes: attrs.entries
          .map((e) => Attribute.fromString(e.key, e.value))
          .toList(),
      span: parentSpan,
      status: status,
      message: (success ?? false) ? "SUCCESS" : "ERROR",
    );
  }

  @override
  void onSpanStarted({
    required String id,
    required String name,
    String? parentId,
    required Map<String, String> attributes,
    required EventCategory category,
    bool? dashboardLog,
  }) {
    final telemetry = _telemetry;
    if (telemetry == null) return;
    if (respectsLogLevel && !_configuredLevel.shouldShow(category)) return;
    final attrs = Map<String, String>.from(attributes);
    attrs['category'] = category.name;
    Span? parentSpan;
    if (parentId != null) {
      parentSpan = _activeSpans[parentId];
    }
    parentSpan ??= telemetry.getCurrentSpan();
    final span = telemetry.trace(
      spanName: name,
      attributes: attrs.entries
          .map((e) => Attribute.fromString(e.key, e.value))
          .toList(),
      span: parentSpan,
    );
    _activeSpans[id] = span;
  }
}
