import 'package:videosdk/src/core/room/transcription/summary_config.dart';

/// Configuration for the transcription service.
///
/// - This class encapsulates the settings required to start transcription,
/// including the webhook URL for delivering results and optional summary configuration.
class TranscriptionConfig {
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

  /// Webhook URL to which transcription results will be sent.
  late final String? webhookUrl;

  /// Optional configuration for generating a transcription summary.
  late final SummaryConfig? summary;

  /// @nodoc
  TranscriptionConfig({this.webhookUrl, SummaryConfig? summaryConfig}) {
    summary = summaryConfig;
  }

  /// @nodoc
  Map<String, dynamic> toJson() {
    return {
      'webhookUrl': webhookUrl,
      'summary': summary?.toJson(),
    };
  }
}
