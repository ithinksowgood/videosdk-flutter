import 'dart:convert';

/// @nodoc
PubSubMessages pubSubMessagesFromJson(String str) =>
    PubSubMessages.fromJson(json.decode(str));

/// @nodoc
String pubSubMessagesToJson(PubSubMessages data) => json.encode(data.toJson());

/// Represents a collection of PubSub messages.
class PubSubMessages {
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

  /// @nodoc
  PubSubMessages({
    required this.messages,
  });

  /// A list of messages.
  late List<PubSubMessage> messages;

  /// @nodoc
  factory PubSubMessages.fromJson(Map<String, dynamic> json) => PubSubMessages(
        messages: json["messages"] != null
            ? List<PubSubMessage>.from(
                json["messages"].map((x) => PubSubMessage.fromJson(x)))
            : <PubSubMessage>[],
      );

  /// @nodoc
  Map<String, dynamic> toJson() => {
        "messages": List<dynamic>.from(messages.map((x) => x.toJson())),
      };
}

/// Represents a single PubSub message.
class PubSubMessage {
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

  /// @nodoc
  PubSubMessage(
      {required this.id,
      required this.message,
      required this.senderId,
      required this.senderName,
      required this.timestamp,
      required this.topic,
      required this.payload});

  /// The unique identifier of the message.
  String id;

  /// The content of the message.
  String message;

  /// The ID of the sender.
  String senderId;

  /// The name of the sender.
  String senderName;

  /// The timestamp when the message was sent.
  DateTime timestamp;

  /// The topic of the message.
  String topic;

  /// Additional payload data associated with the message.
  Map<String, dynamic>? payload;

  /// @nodoc
  factory PubSubMessage.fromJson(Map<String, dynamic> json) {
    // perform null-safe extraction with defaults to avoid runtime type errors
    final id = json["id"] as String? ?? '';
    final message = json["message"] as String? ?? '';
    final senderId = json["senderId"] as String? ?? '';
    final senderName = json["senderName"] as String? ?? '';
    final rawTimestamp = json["timestamp"] as String?;
    final timestamp = rawTimestamp != null
        ? DateTime.parse(rawTimestamp)
        : DateTime.fromMillisecondsSinceEpoch(0);
    final topic = json["topic"] as String? ?? '';
    final payload = json["payload"] as Map<String, dynamic>?;

    return PubSubMessage(
      id: id,
      message: message,
      senderId: senderId,
      senderName: senderName,
      timestamp: timestamp,
      topic: topic,
      payload: payload,
    );
  }

  /// @nodoc
  Map<String, dynamic> toJson() => {
        "id": id,
        "message": message,
        "senderId": senderId,
        "senderName": senderName,
        "timestamp": timestamp.toIso8601String(),
        "topic": topic,
        "payload": payload,
      };
}
