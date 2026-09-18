import 'dart:developer';

import 'package:videosdk/src/core/utils/event_emitter.dart';
import 'package:synchronized/synchronized.dart';
import 'package:videosdk/src/core/room/open_telemetry/videosdk_log.dart';

import 'pubsub_message.dart';
import 'pubsub_publish_options.dart';

/// Represents the PubSub (Publish-Subscribe) mechanism for the room.
///
/// - This class allows participants to publish messages to topics and subscribe to
/// topics to receive messages. It supports persistent messages and payload attachments.
///
/// ## Usage
///
/// ```dart
/// // Publish a message
/// await room.pubSub.publish("CHAT", "Hello");
///
/// // Subscribe to a topic
/// room.pubSub.subscribe("CHAT", (message) {
///   print(message.message);
/// });
/// ```
class PubSub {
  //
  late Function _pubsubPublish;

  //
  late Function _pubsubSubscribe;

  //
  late Function _pubsubUnsubscribe;

  //
  late EventEmitter? _topicEventEmitter;

  //Room's meeting-state gate. PubSub has to run it itself rather than rely on
  //the room-side callbacks, because subscribe/unsubscribe touch the local
  //listener map before and after those calls — a rejected call must leave that
  //map exactly as it found it.
  late bool Function(String methodName) _ensureJoined;

  //
  late final Lock _lock;

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
  PubSub({
    required Function pubsubPublish,
    required Function pubsubSubscribe,
    required Function pubsubUnsubscribe,
    required topicEventEmitter,
    bool Function(String methodName)? ensureJoined,
  }) {
    _topicEventEmitter = topicEventEmitter;
    _pubsubPublish = pubsubPublish;
    _pubsubSubscribe = pubsubSubscribe;
    _pubsubUnsubscribe = pubsubUnsubscribe;
    _ensureJoined = ensureJoined ?? (String _) => true;

    _lock = Lock();
  }

  /// `publish()` is used to publish messages on a specified topic in the room.
  ///
  /// ### **Parameters**:
  /// * [topic] - This is the name of the topic, for which message will be published.
  /// * [message] - This is the actual message.
  /// * [options] - This specifies the options for publish.
  /// * [payload] - If you need to include additional information along with a message, you can pass here as `Map<String, dynamic>`. This is optional parameter.
  ///
  /// Returns:
  /// * [Future<void>]
  ///
  /// ### **Example**
  /// ```dart
  /// // Publishing message
  /// room.pubSub
  ///     .publish(
  ///       "CHAT",
  ///       "Hii",
  ///       const PubSubPublishOptions(persist: true),
  ///     );
  /// ```
  Future<void> publish(String topic, String message,
          [PubSubPublishOptions? options,
          Map<String, dynamic> payload = const {}]) =>
      _publish(topic, message, options, payload);
  Future<void> _publish(String topic, String message,
      [PubSubPublishOptions? options,
      Map<String, dynamic> payload = const {}]) async {
    if (!_ensureJoined("pubSub.publish")) return;

    options ??= const PubSubPublishOptions();
    await _pubsubPublish(
      topic: topic,
      message: message,
      options: options.toJson(),
      payload: payload,
    );
  }

  /// `subscribe()` is used to subscribe a particular topic to get all the messages of that particular topic in the room.
  ///
  /// ### **Parameters**:
  /// * [topic] - Participants can listen to messages on that particular topic.
  /// * [onMessageReceived] - This function will be called, whenever pubsub message received.
  ///
  /// Returns:
  /// * [Future<PubSubMessages>]
  ///
  /// ### **Example**
  /// ```dart
  /// // Subscribing 'CHAT' Topic
  ///
  /// void handleMessage(PubSubMessage pubsubMessage) {
  ///   print(pubsubMessage.message);
  /// }
  ///
  /// void subscribePubSubTopic() async {
  ///   PubSubMessages pubsubMessages =
  ///       await room.pubSub.subscribe("CHAT", handleMessage);
  ///
  ///   // do something
  /// }
  ///
  /// subscribePubSubTopic();
  /// ```
  Future<PubSubMessages> subscribe(
          String topic, Function(PubSubMessage) onMessageReceived) =>
      _subscribe(topic, onMessageReceived);
  Future<PubSubMessages> _subscribe(
          String topic, Function(PubSubMessage) onMessageReceived) =>
      _lock.synchronized(() async {
        //Checked before the listener is registered: a rejected subscribe that
        //still left a handler behind would deliver messages the app never
        //successfully subscribed to.
        if (!_ensureJoined("pubSub.subscribe")) {
          return PubSubMessages.fromJson(<String, dynamic>{"messages": []});
        }

        final msgs = (await _pubsubSubscribe(topic)) ??
            <String, dynamic>{"messages": []};

        var messages = PubSubMessages.fromJson(msgs);

        if (!_topicEventEmitter!.listeners(topic).contains(onMessageReceived)) {
          _topicEventEmitter!.on(topic, onMessageReceived);
        }

        return messages;
      });

  /// `unsubscribe()` is used to unsubscribe a particular topic on which you have subscribed priviously.
  ///
  /// ### **Parameters**:
  /// * [topic] - This is the name of the topic to be unsubscribed.
  /// * [onMessageReceived] - This is the message handler to be unsubscribed.
  ///
  /// Returns:
  /// * [Future<void>]
  ///
  /// ### **Example**
  /// ```dart
  /// // Unsubscribing 'CHAT' topic
  /// room.pubSub.unsubscribe("CHAT", handleMessage);
  /// ```
  Future<void> unsubscribe(
          String topic, Function(PubSubMessage) onMessageReceived) =>
      _unsubscribe(topic, onMessageReceived);
  Future<void> _unsubscribe(
      String topic, Function(PubSubMessage) onMessageReceived) async {
    //The local handler is removed unconditionally, before the gate. The usual
    //Flutter teardown is room.leave() followed by unsubscribe() in
    //State.dispose(); gating the removal meant the handler stayed bound to a
    //disposed State forever, and a later delivery on that topic would call
    //setState() after dispose(). Only the server round-trip below is gated —
    //that is the part a not-joined or reconnecting room genuinely cannot do.
    try {
      _topicEventEmitter!.remove(topic, onMessageReceived);
    } catch (e) {
      //
      VideoSDKLog.createLog(
          message: "Error in pubSub unsubscribe \n ${e.toString()}",
          logLevel: "ERROR");
      //
      log("unsubscribe() | error: $e");
    }

    if (_topicEventEmitter!.listeners(topic).isEmpty) {
      if (!_ensureJoined("pubSub.unsubscribe")) return;
      await _pubsubUnsubscribe(topic);
    }
  }
}
