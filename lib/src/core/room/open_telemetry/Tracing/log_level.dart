import 'event_category.dart';

/// Defines the available logging levels for the SDK.
///
/// Log levels control how much diagnostic information the SDK emits.
/// They allow you to adjust logging verbosity based on your debugging needs
/// without affecting SDK behavior.
///
/// Log levels are ordered from least to most verbose:
///
/// - [LogLevel.none]
///   Disables all logging. No console output will be generated.
///
/// - [LogLevel.error]
///   Logs only critical errors and unrecoverable failures.
///   Useful for production environments where only serious issues should be tracked.
///
/// - [LogLevel.warn]
///   Logs warnings and errors.
///   Warnings represent recoverable issues or unexpected states
///   that do not stop execution.
///
/// - [LogLevel.info]
///   Logs general SDK lifecycle events and state changes.
///   This is the default logging level.
///
/// - [LogLevel.debug]
///   Logs detailed diagnostic information useful during development.
///   Includes internal state changes and debugging data.
///
/// - [LogLevel.all]
///   Enables extremely verbose logging.
///   Includes high-frequency real-time events and detailed internal traces.
///   Intended strictly for deep debugging scenarios.
///
enum LogLevel {
  none,
  error,
  warn,
  info,
  debug,
  all,
}

const Map<LogLevel, Set<EventCategory>> logLevelCategoryMap = {
  LogLevel.none: {},
  LogLevel.error: {EventCategory.error, EventCategory.backendError},
  LogLevel.warn: {
    EventCategory.error,
    EventCategory.warn,
    EventCategory.backendError
  },
  LogLevel.info: {
    EventCategory.backendError,
    EventCategory.error,
    EventCategory.warn,
    EventCategory.telemetry
  },
  LogLevel.debug: {
    EventCategory.error,
    EventCategory.warn,
    EventCategory.debug,
    EventCategory.telemetry,
    EventCategory.backendError
  },
  LogLevel.all: {
    EventCategory.error,
    EventCategory.warn,
    EventCategory.telemetry,
    EventCategory.debug,
    EventCategory.realTime,
    EventCategory.backendError
  }
};

extension LogLevelExt on LogLevel {
  bool shouldShow(EventCategory category) {
    if (this == LogLevel.none) return false;
    final visible = logLevelCategoryMap[this];
    return visible != null && visible.contains(category);
  }
}
