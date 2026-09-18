// ignore_for_file: prefer_initializing_formals, dangling_library_doc_comments
/// Configuration for transcription summary generation.
///
/// - This class defines the settings for generating a summary of the transcription,
/// including whether it is enabled and the prompt to be used.

class SummaryConfig {
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

  /// Whether transcription summary generation is enabled.
  late final bool enabled;

  /// The prompt used to guide the summary generation.
  late final String prompt;

  /// @nodoc
  SummaryConfig({required bool enabled, required String prompt}) {
    this.enabled = enabled;
    this.prompt = prompt;
  }

  /// @nodoc
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'prompt': prompt,
    };
  }
}
