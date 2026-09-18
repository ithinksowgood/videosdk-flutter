// ignore_for_file: strict_top_level_inference

import 'package:videosdk/src/core/utils/event_emitter.dart';
import 'package:videosdk/src/core/room/events.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/sdk_tracer.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/output_target.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/event_category.dart';
import 'package:videosdk/videosdk.dart';
// ignore: unnecessary_import
import 'package:videosdk_webrtc/flutter_webrtc.dart';

import '../webrtc/webrtc_client.dart';

/// Defines the type of media stream.
enum StreamKind {
  /// Video stream
  video,

  /// Audio stream
  audio,

  /// Screen share stream
  share
}

/// Represents a media stream in a VideoSDK room.
///
/// - A [Stream] object encapsulates either an audio or video track from a participant,
/// including screen sharing streams. It provides methods to control playback and
/// listen to stream state changes.
///
/// ## Usage
///
/// ```dart
/// // Listen to stream state changes
/// stream.on(Events.streamStateChanged, (state) {
///   print('Stream state changed: $state');
/// });
///
/// // Pause the stream
/// stream.pause();
///
/// // Resume the stream
/// await stream.resume();
/// ```
///
/// See also:
/// * [Participant], which produces streams
/// * [Room], which manages all streams in a meeting
class Stream {
  /// Represents the id for that stream .
  late String id;

  /// It represents a single media track within a stream.
  /// You can call pause() method to pause MediaStreamTrack.
  /// And you can also call resume() method to resume MediaStreamTrack.
  late Consumer track;

  /// kind represents the type of stream which could be audio | video or share .
  late String? kind;

  /// This is a renderer, which is passed to RTCVideoView widget.
  late RTCVideoRenderer? renderer;

  /// Whether this stream belongs to the local participant.
  ///
  /// * `true` - This is a stream from the local participant
  /// * `false` - This is a remote participant's stream
  late final bool isLocal;

  late final EventEmitter _streamEventEmitter;
  late final EventEmitter _eventEmitter;

  /// Creates a new [Stream] instance.
  ///
  /// ### **Parameters**:
  /// * [consumer] - The consumer representing the media track
  /// * [renderer] - Optional video renderer for displaying the stream
  /// * [eventEmitter] - Room-level event emitter for control requests
  /// * [isLocal] - Whether this stream belongs to the local participant
  /// @nodoc
  Stream({
    required consumer,
    this.renderer,
    required EventEmitter eventEmitter,
    required this.isLocal,
  }) {
    track = consumer;
    id = track.id;
    kind = track.appData['share'] == true ? "share" : track.kind;
    _eventEmitter = eventEmitter;
    _streamEventEmitter = EventEmitter();
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

  ///
  /// By using pause(), a participant can pause the stream of Remote Participant.
  ///
  /// ### **Example**
  /// ```dart
  /// stream.pause();
  /// ```
  void pause() => _pause();
  void _pause() {
    try {
      _eventEmitter.emit("request-pause-stream", {
        'isLocal': isLocal,
        'consumer': track,
      });
      // ignore: empty_catches
    } catch (e) {}
  }

  ///
  /// By using resume(), a participant can resume the stream of Remote Participant.
  ///
  /// ### **Example**
  /// ```dart
  /// await stream.resume();
  /// ```
  ///
  /// Returns a [Future] that completes when the resume request has been sent.
  Future<void> resume() => _resume();
  Future<void> _resume() async {
    try {
      _eventEmitter.emit("request-resume-stream", {
        'isLocal': isLocal,
        'consumer': track,
      });
      // ignore: empty_catches
    } catch (e) {}
  }

  /// @nodoc

  void handleStateChanged(state) {
    var timeStamp = DateTime.now().millisecondsSinceEpoch;

    _streamEventEmitter.emit('stream-state-changed', state, timeStamp);
    if (state != 'active' && state != 'ended') {
      SdkTracer.shared.to(OutputTarget.toConsole).traceEvent(
            name: "Emitting STREAM_STATE_CHANGED Event",
            attributes: {
              "state": state.toString(),
              "peerId": track.peerId,
              "kind": kind,
            },
            category: EventCategory.warn,
          );
    }
  }

  void on(Events event, Function handler) => _on(event, handler);
  _on(Events event, handler) {
    _streamEventEmitter.on(event.parseToString(), handler);
  }

  /// @nodoc
  Stream copyWith({
    Consumer? track,
    RTCVideoRenderer? renderer,
  }) {
    return Stream(
      consumer: track ?? this.track,
      renderer: renderer ?? this.renderer,
      eventEmitter: _eventEmitter,
      isLocal: isLocal,
    );
  }
}
