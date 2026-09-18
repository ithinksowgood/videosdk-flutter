// ignore_for_file: constant_identifier_names

/// Represents the current state of the real-time transcription service.
///
/// - This enum is emitted with transcription-related events to indicate
/// the lifecycle state of the transcription process.
///
/// ### **Example**
/// ```dart
/// room.on(
///   Events.transcriptionStateChanged,
///   (TranscriptionState state) {
///     print('Transcription state: $state');
///   },
/// );
/// ```
enum TranscriptionState {
  /// Transcription is initializing and preparing to start.
  ///
  /// ### **Example**
  /// ```dart
  /// TranscriptionState.TRANSCRIPTION_STARTING
  /// ```
  TRANSCRIPTION_STARTING,

  /// Transcription is actively running and processing audio.
  ///
  /// ### **Example**
  /// ```dart
  /// TranscriptionState.TRANSCRIPTION_STARTED
  /// ```
  TRANSCRIPTION_STARTED,

  /// Transcription is in the process of stopping.
  ///
  /// ### **Example**
  /// ```dart
  /// TranscriptionState.TRANSCRIPTION_STOPPING
  /// ```
  TRANSCRIPTION_STOPPING,

  /// Transcription has completely stopped.
  ///
  /// ### **Example**
  /// ```dart
  /// TranscriptionState.TRANSCRIPTION_STOPPED
  /// ```
  TRANSCRIPTION_STOPPED,
}
