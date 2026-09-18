import 'event_category.dart';
import 'log_level.dart';

abstract class TraceOutput {
  Set<EventCategory> subscribedCategories = {
    EventCategory.telemetry,
    EventCategory.error
  };
  bool canAccessSensitiveData = false;
  bool respectsLogLevel = true;

  int get outputBit;

  void setLogLevel(LogLevel level) {}

  void clearSpanHistory() {}

  void onSpanStarted({
    required String id,
    required String name,
    String? parentId,
    required Map<String, String> attributes,
    required EventCategory category,
    bool? dashboardLog,
  });

  void onSpanEnded({
    required String id,
    required String name,
    required EventCategory category,
    required int durationMs,
    required bool success,
    required String message,
    required Map<String, String> attributes,
    bool? dashboardLog,
  });

  void onEvent({
    required String name,
    required Map<String, String> attributes,
    String? parentId,
    required EventCategory category,
    bool? success,
    bool? dashboardLog,
  });
}
