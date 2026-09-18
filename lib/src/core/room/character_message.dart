/// @nodoc
/// Represents a message sent by or related to a character.
/// @nodoc
class CharacterMessage {
  /// Creates a new instance of [CharacterMessage].
  CharacterMessage({
    required this.text,
    required this.characterId,
    required this.characterName,
    required this.timestamp,
  });

  /// The content of the message.
  String text;

  /// The ID of the character who sent the message.
  String characterId;

  /// The display name of the character.
  String characterName;

  /// The timestamp when the message was sent (in milliseconds since epoch).
  int timestamp;

  /// Creates a [CharacterMessage] instance from a JSON map.
  factory CharacterMessage.fromJson(Map<String, dynamic> json) =>
      CharacterMessage(
        text: json["text"],
        characterId: json["characterId"],
        characterName: json["characterName"],
        timestamp: json["timestamp"],
      );

  /// Converts the [CharacterMessage] instance to a JSON map.
  Map<String, dynamic> toJson() => {
        "text": text,
        "characterId": characterId,
        "characterName": characterName,
        "timestamp": timestamp,
      };
}
