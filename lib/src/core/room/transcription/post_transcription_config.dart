// ignore_for_file: prefer_initializing_formals

import 'package:videosdk/src/core/room/transcription/summary_config.dart';

/// Configuration for post-transcription processing.
///
/// - This class defines the settings for actions that should be performed
/// after transcription is completed, such as generating summaries
/// or selecting a specific AI model.
class PostTranscriptionConfig {
  /// @nodoc
  @override
  String toString() {
    return super.toString();
  }

  /// @nodoc
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }

  /// @nodoc
  @override
  bool operator ==(Object other) {
    return super == other;
  }

  /// @nodoc
  @override
  int get hashCode => super.hashCode;

  /// Whether post-transcription processing is enabled.
  ///
  /// - If `true`, the system will perform post-processing actions
  /// such as summary generation after transcription completes.
  late final bool enabled;

  /// Configuration for generating a transcription summary.
  ///
  /// - If provided, the transcription result may be summarized
  /// according to the rules defined in [SummaryConfig].
  late final SummaryConfig? summary;

  /// Identifier of the AI model to be used for post-transcription processing.
  ///
  /// - This can be used to specify a custom or predefined model.
  late final String? modelId;

  /// Creates a [PostTranscriptionConfig].
  ///
  /// ### **Parameters**
  ///
  /// - [enabled]
  ///   Enables or disables post-transcription processing.
  ///
  /// - [summaryConfig]
  ///   Optional configuration for generating a summary
  ///   after transcription is completed.
  ///
  /// - [modelId]
  ///   Optional identifier of the model to be used
  ///   for post-transcription tasks.
  ///
  /// @nodoc
  PostTranscriptionConfig({
    required bool enabled,
    SummaryConfig? summaryConfig,
    String? modelId,
  }) {
    this.enabled = enabled;
    summary = summaryConfig;
    this.modelId = modelId;
  }

  /// @nodoc
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'summary': summary?.toJson(),
      'modelId': modelId,
    };
  }
}
