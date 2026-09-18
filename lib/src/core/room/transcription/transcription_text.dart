/// Represents a segment of transcribed text.
///
/// This class holds information about a piece of transcribed text, including
/// the speaker's identity, the text content, and the timestamp.
class TranscriptionText {
  late final String? _participantId;
  late final String? _participantName;
  late final String? _text;
  late final int? _timestamp;
  late final String? _type;

  /// @nodoc
  TranscriptionText(
      {String? participantId,
      String? participantName,
      String? text,
      int? timestamp,
      String? type}) {
    _participantId = participantId;
    _participantName = participantName;
    _text = text;
    _timestamp = timestamp;
    _type = type;
  }

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

  // Getter methods

  /// The ID of the participant who spoke.
  /// ### Type
  ///
  /// - `String?`
  String? get participantId => _participantId;

  /// The name of the participant who spoke.
  /// ### Type
  ///
  /// - `String?`
  String? get participantName => _participantName;

  /// The transcribed text content.
  /// ### Type
  ///
  /// - `String?`
  String? get text => _text;

  /// The timestamp of the transcription in milliseconds.
  /// ### Type
  ///
  /// - `int?`
  int? get timestamp => _timestamp;

  /// The type of transcription event.
  /// ### Type
  ///
  /// - `String?`
  String? get type => _type;

  /// Converts this [TranscriptionText] instance into a JSON-compatible map.
  ///
  /// ### Returns
  ///
  /// - A `Map<String, dynamic>` containing the transcription details:
  ///   - `participantId`: `String?`
  ///   - `participantName`: `String?`
  ///   - `text`: `String?`
  ///   - `timestamp`: `int?`
  ///   - `type`: `String?`
  /// @nodoc
  Map<String, dynamic> toJson() {
    return {
      'participantId': participantId,
      'participantName': participantName,
      'text': text,
      'timestamp': timestamp,
      'type': type
    };
  }
}
