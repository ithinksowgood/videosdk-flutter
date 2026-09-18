import 'package:videosdk/src/core/utils/event_emitter.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/event_category.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/sdk_tracer.dart';
import 'package:videosdk/videosdk.dart';
import 'events.dart';

/// Represents an AI agent participant in the room.
///
/// [AgentParticipant] extends [Participant] and provides agent-specific
/// functionality such as state tracking (`idle`, `listening`, `thinking`,
/// `speaking`) and transcription events.
///
/// Agent-specific events:
/// - [Events.agentStateChanged] — emitted when the agent's state changes.
/// - [Events.agentTranscriptionReceived] — emitted when a transcription segment
///   is received from the agent.
/// - [Events.agentMetrics] — emitted when metrics data is received from the agent.
///
/// Supported methods: [remove], [pin], [unpin], [getVideoStats], [getAudioStats],
///
/// Methods that are not applicable to an agent participant throw an
/// [UnsupportedError] when called.
///
/// ### **Example**
///
/// ```dart
///   participant.on(Events.agentStateChanged, (AgentState state) {
///     print('Agent state: ${state.name}');
///   });
///
///   participant.on(Events.agentTranscriptionReceived, (TranscriptionSegment segment, Participant participant) {
///     print('Transcription: ${segment.text}');
///   });
/// });
/// ```
class AgentParticipant extends Participant {
  AgentState _agentState = AgentState.idle;
  dynamic _lastTranscription; // ADD THIS
  final Function _getStatsInternal;
  final Function _removePeerInternal;
  final Function _participantPinStateChangedInternal;
  late final EventEmitter _eventEmitter;

  /// The unique agent identifier.
  ///
  /// Resolved from `agentId` or `metaData['agent_id']`.
  ///
  /// ### Type
  ///
  /// - `String?`
  String? agentId;

  /// The current state of the agent.
  ///
  /// ### Type
  ///
  /// - [AgentState]
  ///
  /// ### Possible values
  ///
  /// - [AgentState.idle]
  /// - [AgentState.listening]
  /// - [AgentState.thinking]
  /// - [AgentState.speaking]
  AgentState get agentState => _agentState;

  /// Whether this participant is an agent.
  ///
  /// Always `true` for [AgentParticipant].
  ///
  /// ### Type
  ///
  /// - `bool`
  @override
  bool get isAgent => true;

  /// @nodoc
  AgentParticipant({
    required String id,
    required super.displayName,
    required EventEmitter eventEmitter,
    String? agentIdParam,
    Map<String, dynamic>? metaData,
    required super.enablePeerMic,
    required super.disablePeerMic,
    required super.enablePeerCamera,
    required super.disablePeerCamera,
    required super.getStats,
    required super.removePeer,
    required super.setConsumerQuality,
    required Function setViewPort,
    required super.participantPinStateChanged,
  })  : _getStatsInternal = getStats,
        _removePeerInternal = removePeer,
        _participantPinStateChangedInternal = participantPinStateChanged,
        super(
          id: id,
          isLocal: false,
          pinState: ParticipantPinState(),
          mode: Mode.SEND_AND_RECV,
          eventEmitter: eventEmitter,
          setViewPort: () {},
          metaData: metaData,
        ) {
    _eventEmitter = eventEmitter;

    agentId = agentIdParam ?? metaData?['agent_id'] as String?;
    _agentState = AgentState.idle;

    _eventEmitter.on('AGENT_STATE_CHANGED_$id', (data) {
      handleAgentStateChanged(data);
    });

    _eventEmitter.on('AGENT_TRANSCRIPTION_$id', (participant, segment) {
      handleTranscriptionReceived(participant, segment);
    });

    _eventEmitter.on('AGENT_METRICS_$id', (data) {
      handleAgentMetrics(data);
    });
  }

  /// @nodoc
  /// Handles incoming agent state change notifications and updates internal state.
  void handleAgentStateChanged(Map<String, dynamic> data) {
    final rawState = data['state'] as String?;
    if (rawState == null) return;

    final newState = AgentState.values.firstWhere(
      (s) => s.name == rawState,
      orElse: () => AgentState.idle,
    );

    _agentState = newState;
    _eventEmitter.emit('agent-state-changed', newState);
    SdkTracer.shared.traceEvent(
      spanName: "Emitted AGENT_STATE_CHANGED",
      attributes: {
        'State': newState,
      },
      category: EventCategory.realTime,
    );
  }

  /// @nodoc
  /// Handles incoming agent metrics notifications.
  void handleAgentMetrics(Map<String, dynamic> data) {
    _eventEmitter.emit('agent-metrics', data);
    SdkTracer.shared.traceEvent(
      spanName: "Emitted AGENT_METRICS",
      attributes: {
        'data': data.toString(),
      },
      category: EventCategory.realTime,
    );
  }

  /// Registers an event listener on this [AgentParticipant].
  ///
  /// Handles agent-specific events ([Events.agentStateChanged],
  /// [Events.agentTranscriptionReceived]) directly, and delegates all
  /// inherited [Participant] events to the parent implementation.
  ///
  /// ### **Parameters**
  ///
  /// - [event]: The [Events] type to listen for.
  /// - [handler]: A callback function invoked when the event fires.
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// participant.on(Events.agentStateChanged, (AgentState state) {
  ///   print('New state: ${state.name}');
  /// });
  /// ```
  @override
  on(Events event, handler) => _on(event, handler);
  void _on(Events event, handler) {
    switch (event) {
      case Events.agentStateChanged:
      case Events.agentMetrics:
        _eventEmitter.on(event.parseToString(), handler);
        break;
      case Events.agentTranscriptionReceived:
        _eventEmitter.on(event.parseToString(), handler);
        // Replay last transcription if one arrived before listener registered
        if (_lastTranscription != null) {
          handler(_lastTranscription);
        }
        break;
      default:
        super.on(event, handler);
    }
  }

  /// @nodoc
  void handleTranscriptionReceived(
      Participant participant, TranscriptionSegment segment) {
    _eventEmitter.emit('agent-transcription-received', segment, participant);
    SdkTracer.shared.traceEvent(
      spanName: "Emitted AGENT_TRANSCRIPTION_RECEIVED",
      attributes: {
        'participant': participant.id,
        'text': segment.text,
        'timestamp': segment.timestamp,
      },
      category: EventCategory.realTime,
    );
  }

  /// Removes a previously registered event listener from this [AgentParticipant].
  ///
  /// Handles agent-specific events ([Events.agentStateChanged],
  /// [Events.agentTranscriptionReceived]) directly, and delegates all
  /// inherited [Participant] events to the parent implementation.
  ///
  /// ### **Parameters**
  ///
  /// - [event]: The [Events] type for which to remove the listener.
  /// - [handler]: The same callback originally passed to [on].
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// void onStateChanged(AgentState state) { ... }
  ///
  /// participant.on(Events.agentStateChanged, onStateChanged);
  /// participant.off(Events.agentStateChanged, onStateChanged);
  /// ```
  ///
  @override
  off(Events event, handler) => _off(event, handler);
  void _off(Events event, handler) {
    switch (event) {
      case Events.agentStateChanged:
      case Events.agentTranscriptionReceived:
      case Events.agentMetrics:
        _eventEmitter.remove(event.parseToString(), handler);
        break;
      default:
        super.off(event, handler);
    }
  }

  /// Removes the agent participant from the room.
  @override
  remove() => _removePeerInternal(id);

  /// Pins the agent participant's media streams.
  @override
  void pin([PinType pinType = PinType.SHARE_AND_CAM]) => _setAgentPin(pinType);

  /// Unpins the agent participant's media streams.
  @override
  void unpin([PinType pinType = PinType.SHARE_AND_CAM]) =>
      _setAgentUnpin(pinType);

  /// Retrieves real-time video statistics for the agent participant.
  @override
  List<dynamic>? getVideoStats() => _getVideoStats();
  List<dynamic>? _getVideoStats() {
    for (var entry in streams.entries) {
      if (entry.value.kind == 'video') {
        return _getStatsInternal(entry.key, 'consumer') as List<dynamic>?;
      }
    }
    return null;
  }

  /// Retrieves real-time audio statistics for the agent participant.
  @override
  List<dynamic>? getAudioStats() => _getAudioStats();
  List<dynamic>? _getAudioStats() {
    for (var entry in streams.entries) {
      if (entry.value.kind == 'audio') {
        return _getStatsInternal(entry.key, 'consumer') as List<dynamic>?;
      }
    }
    return null;
  }

  void _setAgentPin(PinType pinType) {
    switch (pinType) {
      case PinType.SHARE_AND_CAM:
        pinState.cam = true;
        pinState.share = true;
        break;
      case PinType.CAM:
        pinState.cam = true;
        break;
      case PinType.SHARE:
        pinState.share = true;
        break;
    }
    _participantPinStateChangedInternal(id, pinState);
  }

  void _setAgentUnpin(PinType pinType) {
    switch (pinType) {
      case PinType.SHARE_AND_CAM:
        pinState.cam = false;
        pinState.share = false;
        break;
      case PinType.CAM:
        pinState.cam = false;
        break;
      case PinType.SHARE:
        pinState.share = false;
        break;
    }
    _participantPinStateChangedInternal(id, pinState);
  }

  // ── Unsupported overrides ────────────────────────────────────────────────
  /// @nodoc
  @override
  unmuteMic() => throw UnsupportedError(
        'The unmuteMic() method is not supported on an agent participant.',
      );

  /// @nodoc
  @override
  muteMic() => throw UnsupportedError(
        'The muteMic() method is not supported on an agent participant.',
      );

  /// @nodoc
  @override
  void enableCam() => throw UnsupportedError(
        'The enableCam() method is not supported on an agent participant.',
      );

  /// @nodoc
  @override
  void disableCam() => throw UnsupportedError(
        'The disableCam() method is not supported on an agent participant.',
      );

  /// @nodoc
  @override
  void setViewPort(width, height) => throw UnsupportedError(
        'The setViewPort() method is not supported on an agent participant.',
      );

  /// @nodoc
  @override
  Future<String?> captureImage({int? width, int? height}) =>
      throw UnsupportedError(
        'The captureImage() method is not supported on an agent participant.',
      );

  /// @nodoc
  @override
  void consumeMicStreams() => throw UnsupportedError(
        'The consumeMicStreams() method is not supported on an agent participant.',
      );

  /// @nodoc
  @override
  void consumeWebcamStreams() => throw UnsupportedError(
        'The consumeWebcamStreams() method is not supported on an agent participant.',
      );

  /// @nodoc
  @override
  void stopConsumingMicStreams() => throw UnsupportedError(
        'The stopConsumingMicStreams() method is not supported on an agent participant.',
      );

  /// @nodoc
  @override
  void stopConsumingWebcamStreams() => throw UnsupportedError(
        'The stopConsumingWebcamStreams() method is not supported on an agent participant.',
      );

  /// @nodoc
  @override
  void setQuality(quality) => throw UnsupportedError(
        'The setQuality() method is not supported on an agent participant.',
      );

  /// @nodoc
  @override
  List<dynamic>? getShareStats() => throw UnsupportedError(
        'The getShareStats() method is not supported on an agent participant.',
      );
}

// ── Supporting types ─────────────────────────────────────────────────────────

/// Represents the operational state of an AI agent participant.
///
/// ### Values
///
/// - [AgentState.idle] — The agent is idle and not processing anything.
/// - [AgentState.listening] — The agent is actively listening to audio input.
/// - [AgentState.thinking] — The agent is processing or generating a response.
/// - [AgentState.speaking] — The agent is producing audio output.
enum AgentState {
  /// The agent is idle and not processing anything.
  idle,

  /// The agent is actively listening to audio input.
  listening,

  /// The agent is processing input or generating a response.
  thinking,

  /// The agent is producing audio output / speaking.
  speaking,
}

/// A transcription segment produced by an AI agent.
///
/// ### Fields
///
/// - [text] — The transcribed text content.
/// - [timestamp] — Unix timestamp in milliseconds when the segment was produced.
class TranscriptionSegment {
  /// The transcribed text content.
  final String? text;

  /// Unix timestamp in milliseconds.
  final int? timestamp;

  /// @nodoc
  TranscriptionSegment({this.text, this.timestamp});

  /// @nodoc
  factory TranscriptionSegment.fromJson(Map<String, dynamic> json) {
    return TranscriptionSegment(
      text: json['text'] as String?,
      timestamp: json['timestamp'] as int?,
    );
  }
}
