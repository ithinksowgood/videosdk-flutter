import 'event_category.dart';
import 'component_category.dart';
import 'sdk_tracer.dart';
import 'span_scope.dart';

/// A routed tracer that filters outputs based on a target mask.
/// This allows selective routing of trace events to specific outputs.
class RoutedTracer {
  final SdkTracer _tracer;
  final int _targetMask;

  RoutedTracer(this._tracer, this._targetMask);

  /// Start a span with output routing
  SpanScope startSpan({
    required String spanName,
    Map<String, dynamic>? attributes,
    Object? parentSpan,
    ComponentCategory? component,
    EventCategory category = EventCategory.debug,
    bool dashboardLog = false,
  }) {
    return _tracer.startSpanWithMask(
      spanName: spanName,
      attributes: attributes,
      parentSpan: parentSpan,
      component: component,
      category: category,
      dashboardLog: dashboardLog,
      targetMask: _targetMask,
    );
  }

  /// End a span with output routing
  void endSpan(
    SpanScope? spanScope, {
    EventCategory category = EventCategory.telemetry,
    Map<String, String>? attributes,
    bool success = true,
    String message = "SUCCESS",
    bool dashboardLog = false,
  }) {
    _tracer.endSpanWithMask(
      spanScope,
      category: category,
      attributes: attributes,
      success: success,
      message: message,
      dashboardLog: dashboardLog,
      targetMask: _targetMask,
    );
  }

  /// Trace an event with output routing
  void traceEvent({
    required String name,
    Map<String, dynamic>? attributes,
    SpanScope? parentScope,
    String? parentId,
    ComponentCategory? component,
    EventCategory category = EventCategory.debug,
    bool success = true,
    bool dashboardLog = false,
  }) {
    _tracer.traceEventWithMask(
      spanName: name,
      attributes: attributes,
      parentScope: parentScope,
      parentId: parentId,
      component: component,
      category: category,
      success: success,
      dashboardLog: dashboardLog,
      targetMask: _targetMask,
    );
  }
}
