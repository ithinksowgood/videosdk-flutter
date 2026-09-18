import '../event_category.dart';
import '../log_level.dart';
import '../trace_output.dart';
import '../output_target.dart';

class ConsoleOutput implements TraceOutput {
  @override
  Set<EventCategory> subscribedCategories = {
    EventCategory.telemetry,
    EventCategory.error,
    EventCategory.warn,
    EventCategory.debug,
    EventCategory.backendError,
    EventCategory.realTime,
  };
  @override
  bool canAccessSensitiveData = false;
  @override
  bool respectsLogLevel = true;

  LogLevel _level = LogLevel.info;

  final Map<String, _SpanInfo> _spanInfoMap = {};

  @override
  int get outputBit => OutputTarget.toConsole.rawValue;

  @override
  void setLogLevel(LogLevel level) {
    _level = level;
  }

  @override
  void clearSpanHistory() {
    _spanInfoMap.clear();
  }

  String _getIndent(int depth) {
    return depth > 0 ? "│   " * depth : "";
  }

  String _formatAttributes(Map<String, String> attributes) {
    if (attributes.isEmpty) return "";

    final filtered = Map<String, String>.from(attributes);
    filtered.remove('component');

    if (filtered.isEmpty) return "";

    final entries =
        filtered.entries.map((e) => "${e.key}: ${e.value}").join(", ");
    return " { $entries }";
  }

  String _getStartColor(EventCategory c) {
    switch (c) {
      case EventCategory.error:
      case EventCategory.backendError:
        // Red
        return "\x1B[31m";
      case EventCategory.warn:
        // Yellow
        return "\x1B[33m";
      case EventCategory.debug:
        // Cyan
        return "\x1B[36m";
      case EventCategory.internalLog:
        // Blue
        return "\x1B[34m";
      case EventCategory.realTime:
        // Green
        return "\x1B[32m";
      case EventCategory.telemetry:
        // White
        return "\x1B[37m";
    }
  }

  String _getEndColor(EventCategory c) {
    // if (kIsWeb) return "";
    return "\x1B[0m";
  }

  void _logByCategory(EventCategory category, String message) {
    final msg =
        "${_getStartColor(category)}VideoSDK: $message${_getEndColor(category)}";
    // ignore: avoid_print
    print(msg);
  }

  String? _resolveParent(String? parentId) {
    // In Dart, parentId is already a String or null, assuming passed directly.
    return parentId;
  }

  @override
  void onSpanStarted({
    required String id,
    required String name,
    String? parentId,
    required Map<String, String> attributes,
    EventCategory category = EventCategory.debug,
    bool? dashboardLog,
  }) {
    final pId = _resolveParent(parentId);
    final parentInfo = pId != null ? _spanInfoMap[pId] : null;
    final depth = (parentInfo?.depth ?? -1) + 1;

    final component = attributes['component'];

    _spanInfoMap[id] = _SpanInfo(
      id: id,
      name: name,
      startTime: DateTime.now().millisecondsSinceEpoch,
      depth: depth,
      component: component,
      category: category,
    );

    if (respectsLogLevel && !_level.shouldShow(category)) {
      return;
    }

    final indent = _getIndent(depth);
    final componentTag = component != null ? "[$component] " : "";
    final attrString = _formatAttributes(attributes);

    final logMsg = "$indent▶$componentTag $name$attrString";

    _logByCategory(category, logMsg);
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
    final spanInfo = _spanInfoMap[id];

    final depth = spanInfo?.depth ?? 0;

    if (respectsLogLevel && !_level.shouldShow(category)) {
      return;
    }

    final attrString = _formatAttributes(attributes);
    final indent = _getIndent(depth);
    final componentTag =
        spanInfo?.component != null ? "[${spanInfo!.component}] " : "";

    final statusSymbol = success ? "✓" : "✗";
    final msg =
        (message.isNotEmpty && message != "SUCCESS") ? " - $message" : "";

    final logMsg =
        "$indent◀$componentTag $name ($durationMs ms $statusSymbol)$msg${attrString.isNotEmpty ? " $attrString" : ""}";

    _logByCategory(category, logMsg);
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
    if (respectsLogLevel && !_level.shouldShow(category)) {
      return;
    }

    final pId = _resolveParent(parentId);
    final parentInfo = pId != null ? _spanInfoMap[pId] : null;
    final depth = (parentInfo?.depth ?? -1) + 1;

    final indent = _getIndent(depth);
    final component = attributes['component'];
    final componentTag = component != null ? "[$component] " : "";
    final attrString = _formatAttributes(attributes);

    final logMsg = "$indent⚡$componentTag $name$attrString";

    _logByCategory(category, logMsg);
  }
}

class _SpanInfo {
  final String id;
  final String name;
  final int startTime;
  final int depth;
  final String? component;
  final EventCategory category;

  _SpanInfo({
    required this.id,
    required this.name,
    required this.startTime,
    required this.depth,
    this.component,
    required this.category,
  });
}
