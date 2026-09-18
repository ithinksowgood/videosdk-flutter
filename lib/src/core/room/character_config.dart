// ignore_for_file: constant_identifier_names

/// @nodoc
/// Configuration class used to set up or resume a character interaction.
class CharacterConfig {
  String? _characterId;
  String? _interactionId;
  String? _displayName;
  String? _characterRole;
  CharacterMode? _characterMode;
  Map<String, dynamic>? _metaData;
  List<String>? _knowledgeBases;
  String? _language;

  CharacterConfig.newInteraction({
    required String characterId,
    String? displayName,
    CharacterMode? characterMode,
    String? characterRole,
    String? interactionId,
    Map<String, dynamic>? metaData,
    String? language,
    List<String>? knowledgeBases,
  }) {
    _characterId = characterId;
    _displayName = displayName;
    _characterMode = characterMode;
    _characterRole = characterRole;
    _metaData = metaData;
    _interactionId = interactionId;
    _language = language;
    _knowledgeBases = knowledgeBases;
  }

  /// Resumes an existing character interaction.
  CharacterConfig.resumeInteraction({
    required String interactionId,
  }) {
    _interactionId = interactionId;
  }

  /// Converts the configuration to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'characterId': _characterId,
      'interactionId': _interactionId,
      'displayName': _displayName,
      'characterRole': _characterRole,
      'characterMode': _characterMode?.name.toLowerCase() ??
          CharacterMode.TEXT.name.toLowerCase(),
      'metaData': _metaData,
      'language': _language,
      'knowledgeBases': _knowledgeBases,
    };
  }
}

/// @nodoc
/// Enum representing different character interaction modes.
enum CharacterMode {
  /// The character communicates using only text.
  TEXT,

  /// The character takes voice input and responds using text.
  CO_PILOT,

  /// The character communicates using voice (both input and output).
  AUTO_PILOT,

  /// The character communicates using video.
  VISION_PILOT,
}

/// @nodoc
/// Enum representing the character's current state.
enum CharacterState {
  /// The character is speaking.
  CHARACTER_SPEAKING,

  /// The character is thinking (processing input or generating a response).
  CHARACTER_THINKING,

  /// The character is listening for input.
  CHARACTER_LISTENING,
}
