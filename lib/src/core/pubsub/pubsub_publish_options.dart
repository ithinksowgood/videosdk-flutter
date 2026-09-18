// ignore_for_file: unintended_html_in_doc_comment, dangling_library_doc_comments

/// Represents the options for publishing a PubSub message.
class PubSubPublishOptions {
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

  /// Whether the message should be persisted.
  final bool persist;

  /// A list of participant IDs to send the message to.
  /// If empty, the message is sent to all participants.
  final List<String> sendOnly;

  /// Creates a new [PubSubPublishOptions] instance.
  ///
  /// ### **Parameters**
  /// - `persist` (bool): Whether to persist the message. Defaults to `false`.
  /// - `sendOnly` (List<String>): List of participant IDs to receive the message. Defaults to empty list (all participants).
  /// @nodoc
  const PubSubPublishOptions({this.persist = false, this.sendOnly = const []});

  /// @nodoc
  Map<String, dynamic> toJson() => {"persist": persist, "sendOnly": sendOnly};
}
