import 'dart:async' show unawaited;
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:videosdk/src/core/room/open_telemetry/Tracing/Outputs/telemetry_output.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/Outputs/backend_log_output.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/Outputs/console_output.dart';

import 'event_category.dart';
import 'component_category.dart';
import 'log_level.dart';
import 'output_target.dart';
import 'redaction_mode.dart';
import 'span_scope.dart';
import 'trace_output.dart';
import 'routed_tracer.dart';

// ---------------------------------------------------------------------------
// Top-level helpers for compute() — pure functions, no instance state
// ---------------------------------------------------------------------------

/// Removes [removalKeys] from every JSON-valued attribute.
/// Runs in a background isolate via compute().
Map<String, String> _computeRemoveAttributes(
    ({Map<String, String> attributes, Set<String> removalKeys}) args) {
  final output = <String, String>{};
  args.attributes.forEach((key, value) {
    if (args.removalKeys.contains(key.toLowerCase())) return;
    final cleaned = _cleanJsonValue(value, args.removalKeys);
    output[key] = cleaned ?? value;
  });
  return output;
}

/// If [value] looks like JSON, decode → strip keys → re-encode.
/// Returns null for plain strings (fast-path, no decode attempted).
String? _cleanJsonValue(String value, Set<String> removalKeys) {
  final trimmed = value.trim();
  final isObj = trimmed.startsWith('{') && trimmed.endsWith('}');
  final isArr = trimmed.startsWith('[') && trimmed.endsWith(']');
  if (!isObj && !isArr) return null;
  dynamic json;
  try {
    json = jsonDecode(value);
  } catch (_) {
    return null;
  }
  try {
    return jsonEncode(_deepRemoveKeys(json, removalKeys));
  } catch (_) {
    return null;
  }
}

dynamic _deepRemoveKeys(dynamic object, Set<String> removalKeys) {
  if (object is Map) {
    final result = <String, dynamic>{};
    object.forEach((key, value) {
      if (!removalKeys.contains(key.toString().toLowerCase())) {
        result[key.toString()] = _deepRemoveKeys(value, removalKeys);
      }
    });
    return result;
  } else if (object is List) {
    return object.map((e) => _deepRemoveKeys(e, removalKeys)).toList();
  }
  return object;
}
// ---------------------------------------------------------------------------

class SdkTracer {
  static final SdkTracer shared = SdkTracer._internal();
  SdkTracer._internal();

  // ignore: constant_identifier_names
  static const COMPONENT_KEY = "component";

  LogLevel _globalLogLevel = LogLevel.info;

  final List<TraceOutput> _outputs = [];

  String _genId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final random = Random();
    final rand = (random.nextInt(10000) ^ (ts >> 7)).toRadixString(16);
    return "span_$ts$rand";
  }

  // ignore: unused_field
  String? _sessionId;
  bool _isLogLevelSet = false;

  TelemetryOutput? _telemetryOutput;
  ConsoleOutput? _consoleOutput;
  BackendLogOutput? _backendLogOutput;

  final Set<String> _sensitiveKeys = HashSet.of({
    "token",
    "jwt",
    "apikey",
    "authtoken",
    "secret",
    "sessionid",
    "password",
    "credential",
    "accesstoken",
    "refreshtoken",
    "id",
    "signalingurl",
    "signalingbaseurl",
    "securekey",
  });

  final RedactionMode _redactionMode = RedactionMode.maskValues;

  void setLogLevel(LogLevel level) {
    _globalLogLevel = level;
    _isLogLevelSet = true;

    // Unregister old outputs if they exist
    if (_telemetryOutput != null) {
      unregisterOutput(_telemetryOutput!);
    }
    if (_consoleOutput != null) {
      unregisterOutput(_consoleOutput!);
    }
    if (_backendLogOutput != null) {
      unregisterOutput(_backendLogOutput!);
    }

    // Register new outputs
    _telemetryOutput = TelemetryOutput(respectsLogLevel: false);
    _consoleOutput = ConsoleOutput();
    registerOutput(_telemetryOutput!);
    registerOutput(_consoleOutput!);

    for (final o in _outputs) {
      o.setLogLevel(_globalLogLevel);
    }
  }

  LogLevel getLogLevel() => _globalLogLevel;

  bool get isLogLevelSet => _isLogLevelSet;

  void setSessionId(String? id) {
    _sessionId = id;
  }

  void registerOutput(TraceOutput output) {
    if (!_outputs.contains(output)) {
      _outputs.add(output);
      output.setLogLevel(_globalLogLevel);
      // Keep reference to known outputs
      if (output is BackendLogOutput) {
        _backendLogOutput = output;
      }
      if (output is TelemetryOutput) {
        _telemetryOutput = output;
      }
      if (output is ConsoleOutput) {
        _consoleOutput = output;
      }
    }
  }

  void unregisterOutput(TraceOutput output) {
    _outputs.remove(output);
    if (output is BackendLogOutput && _backendLogOutput == output) {
      _backendLogOutput = null;
    }
    if (output is TelemetryOutput && _telemetryOutput == output) {
      _telemetryOutput = null;
    }
    if (output is ConsoleOutput && _consoleOutput == output) {
      _consoleOutput = null;
    }
  }

  void clearOutputs() {
    _outputs.clear();
    _telemetryOutput = null;
    _consoleOutput = null;
    _backendLogOutput = null;
  }

  /// Ensure default telemetry & console outputs are created and registered.
  void registerDefaultOutputsIfNeeded() {
    if (_telemetryOutput == null) {
      _telemetryOutput = TelemetryOutput(respectsLogLevel: false);
      registerOutput(_telemetryOutput!);
    }
    // only happens from the Videosdk SetLogLevel
    // if (_consoleOutput == null) {
    //   _consoleOutput = ConsoleOutput();
    //   registerOutput(_consoleOutput!);
    // }
    // If a backend output instance already exists (created elsewhere), ensure it's registered
    if (_backendLogOutput != null && !_outputs.contains(_backendLogOutput)) {
      registerOutput(_backendLogOutput!);
    }

    // Apply global log level to all outputs
    for (final o in _outputs) {
      o.setLogLevel(_globalLogLevel);
    }
  }

  void unregisterConsoleAndTelemetryOutputs() {
    if (_telemetryOutput != null) {
      unregisterOutput(_telemetryOutput!);
      _telemetryOutput = null;
    }
    if (_consoleOutput != null) {
      unregisterOutput(_consoleOutput!);
      _consoleOutput = null;
    }
    if (_backendLogOutput != null) {
      unregisterOutput(_backendLogOutput!);
      _backendLogOutput = null;
    }
  }

  void clearSpanHistory() {
    for (final o in _outputs) {
      o.clearSpanHistory();
    }
  }

  SpanScope startSpan({
    required String spanName,
    Map<String, dynamic>? attributes,
    Object? parentSpan,
    ComponentCategory? component,
    EventCategory category = EventCategory.debug,
    bool dashboardLog = false,
  }) {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final attrsWithComponent = Map<String, dynamic>.from(attributes ?? {});
    if (component != null) {
      attrsWithComponent[COMPONENT_KEY] = component.name;
    }
    var stringAttrs =
        attrsWithComponent.map((key, value) => MapEntry(key, "$value"));

    final spanId = _genId();
    String? parentId;
    if (parentSpan is SpanScope) {
      parentId = parentSpan.id;
    } else if (parentSpan is String) {
      parentId = parentSpan;
    }
    unawaited(_dispatchSpanStarted(
      id: spanId,
      name: spanName,
      parentId: parentId,
      attributes: stringAttrs,
      category: category,
      dashboardLog: dashboardLog,
    ));
    return SpanScope(
      id: spanId,
      name: spanName,
      startTime: startTime,
      attributes: stringAttrs,
      parentId: parentId,
      category: category,
    );
  }

  void endSpan(
    SpanScope? spanScope, {
    EventCategory? category,
    Map<String, String>? attributes,
    bool success = true,
    String message = "SUCCESS",
    bool dashboardLog = false,
  }) {
    if (spanScope == null) return;
    final durationMs =
        DateTime.now().millisecondsSinceEpoch - spanScope.startTime;

    for (final output in _outputs) {
      final shouldReceive =
          output.subscribedCategories.contains(category ?? spanScope.category);
      if (shouldReceive) {
        output.onSpanEnded(
          id: spanScope.id,
          name: spanScope.name,
          category: category ?? spanScope.category,
          durationMs: durationMs,
          success: success,
          message: message,
          attributes: attributes ?? {},
          dashboardLog: dashboardLog,
        );
      }
    }
  }

  void traceEvent({
    required String spanName,
    Map<String, dynamic>? attributes,
    SpanScope? parentScope,
    String? parentId,
    ComponentCategory? component,
    EventCategory category = EventCategory.debug,
    bool success = true,
    bool dashboardLog = false,
  }) {
    final attrsWithComponent = Map<String, dynamic>.from(attributes ?? {});
    if (component != null) {
      attrsWithComponent[COMPONENT_KEY] = component.name;
    }
    var stringAttrs =
        attrsWithComponent.map((key, value) => MapEntry(key, "$value"));
    final pid = parentId ?? parentScope?.id;
    unawaited(_dispatchEvent(
      name: spanName,
      attributes: stringAttrs,
      parentId: pid,
      category: category,
      success: success,
      dashboardLog: dashboardLog,
    ));
  }

  void error(String message,
      {ComponentCategory? component = ComponentCategory.internalLog,
      Map<String, dynamic>? attributes}) {
    traceEvent(
        spanName: message,
        attributes: attributes,
        component: component,
        category: EventCategory.error);
  }

  void backendError(String message,
      {ComponentCategory? component = ComponentCategory.internalLog,
      Map<String, dynamic>? attributes}) {
    traceEvent(
        spanName: message,
        attributes: attributes,
        component: component,
        category: EventCategory.backendError);
  }

  void warn(String message,
      {ComponentCategory? component = ComponentCategory.internalLog,
      Map<String, dynamic>? attributes}) {
    traceEvent(
        spanName: message,
        attributes: attributes,
        component: component,
        category: EventCategory.warn);
  }

  void info(String message,
      {ComponentCategory? component = ComponentCategory.internalLog,
      Map<String, dynamic>? attributes}) {
    traceEvent(
        spanName: message,
        attributes: attributes,
        component: component,
        category: EventCategory.telemetry);
  }

  void debug(String message,
      {ComponentCategory? component = ComponentCategory.internalLog,
      Map<String, dynamic>? attributes}) {
    traceEvent(
        spanName: message,
        attributes: attributes,
        component: component,
        category: EventCategory.debug);
  }

  /// Create a routed tracer that filters outputs based on target mask
  /// Usage: SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(...)
  /// Usage: SdkTracer.shared.to(OutputTarget.toConsole, OutputTarget.toTelemetry).traceEvent(...)
  RoutedTracer to(OutputTarget target,
      [OutputTarget? target2, OutputTarget? target3, OutputTarget? target4]) {
    int mask = target.rawValue;
    if (target2 != null) mask |= target2.rawValue;
    if (target3 != null) mask |= target3.rawValue;
    if (target4 != null) mask |= target4.rawValue;
    return RoutedTracer(this, mask);
  }

  /// Internal method: startSpan with output mask filtering
  SpanScope startSpanWithMask({
    required String spanName,
    Map<String, dynamic>? attributes,
    Object? parentSpan,
    ComponentCategory? component,
    EventCategory category = EventCategory.telemetry,
    bool dashboardLog = false,
    required int targetMask,
  }) {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final attrsWithComponent = Map<String, dynamic>.from(attributes ?? {});
    if (component != null) {
      attrsWithComponent[COMPONENT_KEY] = component.name;
    }
    var stringAttrs =
        attrsWithComponent.map((key, value) => MapEntry(key, "$value"));
    final spanId = _genId();
    String? parentId;
    if (parentSpan is SpanScope) {
      parentId = parentSpan.id;
    } else if (parentSpan is String) {
      parentId = parentSpan;
    }
    unawaited(_dispatchSpanStartedWithMask(
      id: spanId,
      name: spanName,
      parentId: parentId,
      attributes: stringAttrs,
      category: category,
      dashboardLog: dashboardLog,
      targetMask: targetMask,
    ));
    return SpanScope(
      id: spanId,
      name: spanName,
      startTime: startTime,
      attributes: stringAttrs,
      parentId: parentId,
      category: category,
    );
  }

  /// Internal method: endSpan with output mask filtering
  void endSpanWithMask(
    SpanScope? spanScope, {
    EventCategory category = EventCategory.telemetry,
    Map<String, String>? attributes,
    bool success = true,
    String message = "SUCCESS",
    bool dashboardLog = false,
    required int targetMask,
  }) {
    if (spanScope == null) return;
    final durationMs =
        DateTime.now().millisecondsSinceEpoch - spanScope.startTime;

    for (final output in _outputs) {
      final shouldReceive =
          output.subscribedCategories.contains(spanScope.category) &&
              (output.outputBit & targetMask) != 0;
      if (shouldReceive) {
        output.onSpanEnded(
          id: spanScope.id,
          name: spanScope.name,
          category: category,
          durationMs: durationMs,
          success: success,
          message: message,
          attributes: attributes ?? {},
          dashboardLog: dashboardLog,
        );
      }
    }
  }

  /// Internal method: traceEvent with output mask filtering
  void traceEventWithMask({
    required String spanName,
    Map<String, dynamic>? attributes,
    SpanScope? parentScope,
    String? parentId,
    ComponentCategory? component,
    EventCategory category = EventCategory.telemetry,
    bool success = true,
    bool dashboardLog = false,
    required int targetMask,
  }) {
    final attrsWithComponent = Map<String, dynamic>.from(attributes ?? {});
    if (component != null) {
      attrsWithComponent[COMPONENT_KEY] = component.name;
    }
    var stringAttrs =
        attrsWithComponent.map((key, value) => MapEntry(key, "$value"));

    final pid = parentId ?? parentScope?.id;
    unawaited(_dispatchEventWithMask(
      name: spanName,
      attributes: stringAttrs,
      parentId: pid,
      category: category,
      success: success,
      dashboardLog: dashboardLog,
      targetMask: targetMask,
    ));
  }

  Future<void> _dispatchSpanStarted({
    required String id,
    required String name,
    String? parentId,
    required Map<String, String> attributes,
    required EventCategory category,
    bool dashboardLog = false,
  }) async {
    try {
      final redacted =
          await _redactIfNeeded(attributes, canAccessSensitiveData: false);
      for (final output in _outputs) {
        if (output.subscribedCategories.contains(category)) {
          final finalAttrs =
              output.canAccessSensitiveData ? attributes : redacted;
          output.onSpanStarted(
            id: id,
            name: name,
            parentId: parentId,
            attributes: finalAttrs,
            category: category,
            dashboardLog: dashboardLog,
          );
        }
      }
    } catch (e) {
      debugPrint('Telemetry dispatch error (spanStarted): $e');
    }
  }

  Future<void> _dispatchEvent({
    required String name,
    required Map<String, String> attributes,
    String? parentId,
    required EventCategory category,
    bool success = true,
    bool dashboardLog = false,
  }) async {
    try {
      final redacted =
          await _redactIfNeeded(attributes, canAccessSensitiveData: false);
      for (final output in _outputs) {
        if (output.subscribedCategories.contains(category)) {
          final finalAttrs =
              output.canAccessSensitiveData ? attributes : redacted;
          output.onEvent(
            name: name,
            attributes: finalAttrs,
            parentId: parentId,
            category: category,
            success: success,
            dashboardLog: dashboardLog,
          );
        }
      }
    } catch (e) {
      debugPrint('Telemetry dispatch error (event): $e');
    }
  }

  /// Internal: dispatch span start with output mask filtering
  Future<void> _dispatchSpanStartedWithMask({
    required String id,
    required String name,
    String? parentId,
    required Map<String, String> attributes,
    required EventCategory category,
    bool dashboardLog = false,
    required int targetMask,
  }) async {
    try {
      final redacted =
          await _redactIfNeeded(attributes, canAccessSensitiveData: false);
      for (final output in _outputs) {
        if (output.subscribedCategories.contains(category) &&
            (output.outputBit & targetMask) != 0) {
          final finalAttrs =
              output.canAccessSensitiveData ? attributes : redacted;
          output.onSpanStarted(
            id: id,
            name: name,
            parentId: parentId,
            attributes: finalAttrs,
            category: category,
            dashboardLog: dashboardLog,
          );
        }
      }
    } catch (e) {
      debugPrint('Telemetry dispatch error (spanStartedWithMask): $e');
    }
  }

  /// Internal: dispatch event with output mask filtering
  Future<void> _dispatchEventWithMask({
    required String name,
    required Map<String, String> attributes,
    String? parentId,
    required EventCategory category,
    bool success = true,
    bool dashboardLog = false,
    required int targetMask,
  }) async {
    try {
      final redacted =
          await _redactIfNeeded(attributes, canAccessSensitiveData: false);
      for (final output in _outputs) {
        if (output.subscribedCategories.contains(category) &&
            (output.outputBit & targetMask) != 0) {
          final finalAttrs =
              output.canAccessSensitiveData ? attributes : redacted;
          output.onEvent(
            name: name,
            attributes: finalAttrs,
            parentId: parentId,
            category: category,
            success: success,
            dashboardLog: dashboardLog,
          );
        }
      }
    } catch (e) {
      debugPrint('Telemetry dispatch error (eventWithMask): $e');
    }
  }

  Set<String> removalKeys = {
    "consumerid",
    "producerid",
    "transportid",
    "method"
  };
  dynamic removeKeysDeep(dynamic object) {
    if (object is Map) {
      final Map<String, dynamic> result = {};

      object.forEach((key, value) {
        if (!removalKeys.contains(key.toLowerCase())) {
          result[key] = removeKeysDeep(value);
        }
      });

      return result;
    } else if (object is List) {
      return object.map((item) => removeKeysDeep(item)).toList();
    } else {
      return object;
    }
  }

  String? removeNestedKeysIfJSONString(String value) {
    // Quick check to avoid unnecessary parsing
    final trimmed = value.trim();

    final isJsonObject = trimmed.startsWith('{') && trimmed.endsWith('}');
    final isJsonArray = trimmed.startsWith('[') && trimmed.endsWith(']');

    if (!isJsonObject && !isJsonArray) {
      return null;
    }

    // Try JSON parse
    dynamic json;
    try {
      json = jsonDecode(value);
    } catch (_) {
      return null;
    }

    // Recursively remove keys
    final cleaned = removeKeysDeep(json);

    // Re-serialize to string
    try {
      return jsonEncode(cleaned);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, String>> removeAttributes(
      Map<String, String>? attributes) {
    if (attributes == null) return Future.value({});
    return compute(
      _computeRemoveAttributes,
      (attributes: attributes, removalKeys: removalKeys),
    );
  }

  Future<Map<String, String>> _redactIfNeeded(
    Map<String, String> attributes, {
    required bool canAccessSensitiveData,
  }) async {
    // Step 1: Always filter attributes first (runs in background isolate)
    final filteredAttributes = await removeAttributes(attributes);

    // Step 2: If sensitive data access is allowed, return filtered attributes
    if (canAccessSensitiveData) {
      return filteredAttributes;
    }

    // Step 3: Take a snapshot of sensitive keys (no lock needed in Dart single isolate)
    final keys = Set<String>.from(_sensitiveKeys);

    // Step 4: Redact as needed
    final newAttrs = <String, String>{};

    for (final entry in filteredAttributes.entries) {
      final keyLower = entry.key.toLowerCase();

      if (keys.contains(keyLower)) {
        newAttrs[entry.key] = _redactValue(entry.value);
      } else {
        newAttrs[entry.key] = _redactSensitivePatterns(entry.value);
      }
    }

    return newAttrs;
  }

  String _redactValue(String value) {
    switch (_redactionMode) {
      case RedactionMode.none:
        return value;
      case RedactionMode.hideValues:
        return "***";
      case RedactionMode.maskValues:
        if (value.length <= 4) return "****";
        final visible = value.substring(0, 2);
        return "$visible****";
    }
  }

  String _redactSensitivePatterns(String value) {
    var result = value;

    // Existing sensitive key redaction
    for (final key in _sensitiveKeys) {
      final jsonPattern =
          RegExp('"$key"\\s*:\\s*"([^"]+)"', caseSensitive: false);
      result = result.replaceAllMapped(jsonPattern, (m) {
        final v = m.group(1) ?? "";
        return '"$key":"${_redactValue(v)}"';
      });

      final dartMapPattern =
          RegExp('\\b($key):\\s*([^,}\\]]+)', caseSensitive: false);
      result = result.replaceAllMapped(dartMapPattern, (m) {
        final k = m.group(1) ?? key;
        final v = (m.group(2) ?? "").trim();
        return '$k: ${_redactValue(v)}';
      });
    }

    // NEW: Remove removalKeys from Dart Map string format
    for (final key in removalKeys) {
      final removePattern = RegExp(
        '\\b$key\\s*:\\s*[^,}\\]]+,?',
        caseSensitive: false,
      );

      result = result.replaceAll(removePattern, '');
    }

    return result;
  }
}
