/// @nodoc
class TranslationText {
  late final String? _participantId;
  late final String? _participantName;
  late final String? _participantLanguage;
  late final String? _language;
  late final String? _text;
  late final double? _timestamp;
  late final String? _type;

  TranslationText(
      {String? participantId,
      String? participantName,
      String? participantLanguage,
      String? language,
      String? text,
      double? timestamp,
      String? type}) {
    _participantId = participantId;
    _participantName = participantName;
    _participantLanguage = participantLanguage;
    _language = language;
    _text = text;
    _timestamp = timestamp;
    _type = type;
  }

  String? get participantId => _participantId;
  String? get participantName => _participantName;
  String? get participantLanguage => _participantLanguage;
  String? get language => _language;
  String? get text => _text;
  double? get timestamp => _timestamp;
  String? get type => _type;

  Map<String, dynamic> toJson() {
    return {
      "participantId": participantId,
      "participantName": participantName,
      "participantLanguage": participantLanguage,
      "language": language,
      "text": text,
      "timestamp": timestamp,
      "type": type,
    };
  }
}
