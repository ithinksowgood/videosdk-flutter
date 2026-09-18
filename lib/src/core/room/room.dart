// ignore_for_file: unnecessary_null_comparison, deprecated_member_use_from_same_package, no_leading_underscores_for_local_identifiers, constant_identifier_names, strict_top_level_inference

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer';
import 'dart:io' show Platform;
import 'dart:io';
import 'stats_isolate.dart';
import 'package:collection/collection.dart';
import 'package:videosdk/src/core/utils/event_emitter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:videosdk/src/core/room/codec.dart';
import 'package:videosdk/src/core/room/webcam_config.dart';
import 'package:videosdk/src/core/room/mic_config.dart';
// import 'package:videosdk/src/core/realtimeStore/realtime_store.dart';
import 'package:videosdk/src/core/webrtc/src/utils.dart';
import 'package:videosdk_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:videosdk/src/core/room/audio_html/audio_html_interface.dart';
import 'package:videosdk/src/core/room/custom_track_configs.dart';
import 'package:videosdk/src/core/room/open_telemetry/videosdk_log.dart';
import 'package:videosdk/src/core/room/open_telemetry/videosdk_telemetry.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/sdk_tracer.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/Outputs/telemetry_output.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/component_category.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/event_category.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/span_scope.dart';
import 'package:videosdk/src/core/room/open_telemetry/Tracing/output_target.dart';
import 'package:videosdk/src/core/room/room_mode.dart';
import 'package:videosdk_room_stats/videosdk_room_stats.dart';

import '../../../videosdk.dart';
// import '../../core/pubsub/pubsub.dart';
import '../../core/webrtc/src/handlers/handler_interface.dart';
import '../../core/webrtc/webrtc_client.dart';
import '../../services/signalling/web_socket.dart';
import '../../utils/constants.dart';
import 'events.dart';
import 'peer.dart';
import 'sdk_capabilites.dart';

// Top-level helper for compute() — decrypts + JSON-decodes ICE server list
// off the main isolate during join().
List<dynamic> _decryptIceServers(String encryptedIceServers) {
  final decrypted = decrypt(encryptedIceServers);
  return json.decode(decrypted.substring(0, decrypted.lastIndexOf(']') + 1))
      as List;
}

// Top-level helper for compute() — serializes RtpParameters to a plain Map
// off the main isolate during track publish.
Map<String, dynamic> _rtpParametersToMap(dynamic params) =>
    Map<String, dynamic>.from(params.toMap() as Map);

class Room {
  /// Unique id of the room where the participant has joined.
  ///
  /// ### Type
  ///
  /// - `String`
  // Room Configuration Properties
  late final String id;
  final Set<String> _disposedVideoRendererPeerIds = <String>{};
  late final String _token;
  late bool _micEnabled;
  late bool _camEnabled;
  late final bool _multiStream;
  late final NotificationInfo _notification;
  late String _maxResolution;
  late bool _debugMode;

  late CustomTrack? _customCameraVideoTrack;
  late CustomTrack? _customMicrophoneAudioTrack;
  Timer? _sendTransportInternal;
  late Mode _mode;

  // Event Emitters
  final _eventEmitter = EventEmitter();
  final _topicEventEmitter = EventEmitter();
  final _relatimeStoreEventEmitter = EventEmitter();
  // E2EE Emitters
  ///@nodoc
  static final e2eeEvent = EventEmitter();

  ///@nodoc
  static String localParticipantId = "";

  /// The local participant in the room.
  ///
  /// This represents the [Participant] instance for the local user
  /// (you) who has joined the room.
  ///
  /// ### Type
  ///
  /// - [Participant]
  late final Participant localParticipant;

  /// A collection of all remote participants in the room.
  ///
  /// This map contains all participants who have joined the room,
  /// excluding the [localParticipant]. Each entry is keyed by the
  /// participant’s unique ID.
  ///
  /// ### Type
  ///
  /// - `Map<String, Participant>`
  ///
  /// ### **Example**
  /// ```dart
  /// // Access a remote participant by ID
  /// const remoteParticipantId = 'ajf897';
  ///
  /// final Participant? remoteParticipant =
  ///     room.participants[remoteParticipantId];
  /// ```
  final Map<String, Participant> participants = {};
  final Map<String, Participant> agentParticipants = {};

  /// A collection of all pinned participants in the room.
  ///
  /// This map contains the pin state of participants who are currently pinned
  /// in the room. Each entry is keyed by the participant’s unique ID and
  /// maps to the corresponding [ParticipantPinState].
  ///
  /// ### Type
  ///
  /// - `Map<String, ParticipantPinState>`
  ///
  /// ### **Example**
  /// ```dart
  /// // Access pin state of a pinned participant
  /// const participantId = 'ajf897';
  ///
  /// final pinState = room.pinnedParticipants[participantId];
  ///
  /// if (pinState?.cam == true) {
  ///   print('Participant WebCam is pinned');
  /// }
  /// ```
  final pinnedParticipants = <String, ParticipantPinState>{};
  SpanScope? _joinSpanScope;
  SpanScope? _requestEntrySpan;
  final Map<String, SpanScope> _peerSpans = {};
  final Map<String, SpanScope> _consumerSpans = {};

  /// Provides access to the Publisher–Subscriber (PubSub) feature for the room.
  ///
  /// This allows participants to publish and subscribe to custom messages
  /// and events within the room.
  ///
  /// Learn more about [PubSub] in the documentation.
  ///
  /// ### Type
  ///
  /// - [PubSub]
  // PubSub
  late PubSub pubSub;

  late RealtimeStore realtimeStore;

  // States for MediaDevices
  VideoDeviceInfo? _selectedVideoInput;

  ///@nodoc

  List<VideoDeviceInfo>? videoDevices;

  ///@nodoc

  List<AudioDeviceInfo>? audioDevices;

  AudioDeviceInfo? _selectedAudioOutput;
  AudioDeviceInfo? _selectedAudioInput;

  // States
  bool _cameraInProgress = false;
  bool _micInProgress = false;
  bool _screenShareInProgress = false;

  // Webcam codec negotiation state
  bool _codecSwitchEnabled = true;

  final Set<VideoCodec> _unsupportedCodecs = {};
  String? _codecChangeParticipantId;

  bool _codecRecycleInProgress = false;

  //The codec a completed recycle moved away from — the guard that stops one
  //unsupportedCodecAdded notification after another from recycling the camera
  //in a loop. Only _addProducer sets it, from _codecRecyclePending, because
  //only a producer landing proves the recycle happened; a recycle whose
  //produce never completes leaves it clear so the next notification retries
  //instead of being locked out.
  VideoCodec? _codecRecycleFrom;

  //The codec an in-flight recycle is moving away from. Set immediately before
  //the enable, consumed by _addProducer, and dropped by _disableCamImpl so a
  //produce that never lands cannot latch onto an unrelated later one.
  VideoCodec? _codecRecyclePending;

  late WebcamConfig _customVideoTrackConfig;
  MicConfig _micConfig = MicConfig.defaults();

  static const Map<String, VideoCodec> _mimeToVideoCodec = {
    'video/vp8': VideoCodec.VP8,
    'video/vp9': VideoCodec.VP9,
    'video/av1': VideoCodec.AV1,
    'video/h264': VideoCodec.H264,
  };

  // Internal Components
  WebSocket? _webSocket;
  Device? _device;
  Transport? _sendTransport, _recvTransport;
  bool _produce = false;
  bool _consume = false;
  bool _joined = false, _closed = false;

  bool _rejoinInProgress = false;
  RoomState _roomState = RoomState.connecting;
  Future<List<dynamic>>?
      _devicePrefetch; // prefetched devices during WebSocket connect
  Future<List<Map<String, bool>>>?
      _permissionPrefetch; // prefetched web permissions during WebSocket connect

  // router RTP capabilities prefetch — fired as soon as WebSocket opens,
  // in parallel with requestEntry, so _joinRoom() pays 0ms waiting for it
  Future<dynamic>? _rtpCapsPrefetch;
  String? _activeSpeakerId, _activePresenterId;
  Producer? _micProducer,
      _cameraProducer,
      _screenshareProducer,
      _screenShareAudioProducer;
  RTCVideoRenderer? _cameraRenderer,
      _screenshareRenderer,
      _screenShareAudioRenderer;
  final List<RTCIceServer> _iceServers = [];
  final Map<String, Peer> _peers = {};
  DesktopCapturerSource? _selectedScreenSource;

  VideoSDKMetrics? _metricsCollector;
  var _stats = {};
  final _latestStats = {};

  // T10: cache CPU/memory usage to avoid platform channel roundtrips on every
  // statsData request. Native values are re-fetched at most once per 5 seconds.
  Map<String, dynamic>? _cachedUsage;
  DateTime? _usageFetchedAt;
  static const _usageCacheTtl = Duration(seconds: 5);

  String _recordingState = "RECORDING_STOPPED";
  String _hlsState = "HLS_STOPPED";
  String? _hlsDownstreamUrl;
  Map<String, String?> _hlsUrls = {
    "downstreamUrl": null,
    "playbackHlsUrl": null,
    "livestreamUrl": null,
  };
  String _livestreamState = "LIVESTREAM_STOPPED";
  late String _displayName;

  //open-telemetery
  // /// @nodoc
  VideoSDKTelemetery? videoSDKTelemetery;
  late Map<String, dynamic> _metaData;

  ///@nodoc

  late Map<String, dynamic> deviceInfo;

  //Live producer state, per Room — deliberately not static: two Room
  //instances (e.g. across a leave/rejoin overlap) must never share it.
  bool _micState = false;
  bool _camState = false;

  String _signalingBaseUrl = "api.videosdk.live";

  /// @nodoc
  String baseUrl = "";
  late String _preferredProtocol;
  static const MethodChannel _channel = MethodChannel('videosdk');

  late int _defaultCameraIndex;

  /// @nodoc
  Map<String, dynamic>? characters = {};

  String? _translationLanguage;

  String? _speakingLanguage;
  bool? _autoConsume;

  bool _enableBatching = true;

  /// @nodoc
  Room({
    required String meetingId,
    required String token,
    required String participantId,
    required String displayName,
    required bool micEnabled,
    required bool camEnabled,
    required String maxResolution,
    required bool multiStream,
    required CustomTrack? customCameraVideoTrack,
    required CustomTrack? customMicrophoneAudioTrack,
    required NotificationInfo notification,
    required Mode mode,
    required Map<String, dynamic> metaData,
    int defaultCameraIndex = 0,
    required String signalingBaseUrl,
    required PreferredProtocol preferredProtocol,
    required bool debugMode,
    required String? translationLanguage,
    required String? speakingLanguage,
    required bool autoConsume,
    bool codecSwitchEnabled = true,
    bool enableBatching = true,
  }) {
    //
    _translationLanguage = translationLanguage;

    _speakingLanguage = speakingLanguage;
    //
    id = meetingId;
    //
    _token = token;
    //
    _displayName = displayName;
    //
    _micEnabled = micEnabled;
    //
    _camEnabled = camEnabled;
    //
    _maxResolution = maxResolution;
    //
    _notification = notification;
    //
    _multiStream = multiStream;
    //
    _customCameraVideoTrack = customCameraVideoTrack;

    _customVideoTrackConfig = customCameraVideoTrack != null
        ? WebcamConfig.fromCustomTrack(customCameraVideoTrack)
        : WebcamConfig.defaults(multiStream: multiStream);
    //
    _customMicrophoneAudioTrack = customMicrophoneAudioTrack;

    if (customMicrophoneAudioTrack != null) {
      _micConfig = MicConfig.fromCustomTrack(customMicrophoneAudioTrack);
    }
    //
    _debugMode = debugMode;

    _mode = mode;

    _autoConsume = autoConsume;

    _codecSwitchEnabled = codecSwitchEnabled;

    // Stream now emits control requests via EventEmitter; no static room binding
    if (mode == Mode.SEND_AND_RECV || mode == Mode.CONFERENCE) {
      _produce = true;
      _consume = true;
    } else if (mode == Mode.RECV_ONLY) {
      _consume = true;
    } else {
      _produce = false;
      _consume = false;
    }

    _metaData = metaData;

    _signalingBaseUrl = signalingBaseUrl;

    _preferredProtocol = preferredProtocol.name;

    _enableBatching = enableBatching;

    //
    localParticipant = Participant(
      id: participantId,
      displayName: displayName,
      isLocal: true,
      pinState: ParticipantPinState(),
      mode: _mode,
      eventEmitter: _eventEmitter,
      enablePeerMic: _enablePeerMic,
      disablePeerMic: _disablePeerMic,
      enablePeerCamera: _enablePeerCamera,
      disablePeerCamera: _disablePeerCamera,
      removePeer: _removePeer,
      setConsumerQuality: setConsumerQuality,
      setViewPort: setViewPort,
      getStats: _getStats,
      participantPinStateChanged: _participantPinStateChange,
      consumeMicStreams: _consumeMicStreams,
      stopConsumingMicStreams: _stopConsumingMicStreams,
      consumeWebcamStreams: _consumeWebcamStreams,
      stopConsumingWebcamStreams: _stopConsumingWebcamStreams,
      metaData: _metaData,
    );

    localParticipantId = participantId;
    //
    pubSub = PubSub(
      pubsubPublish: _pubsubPublish,
      pubsubSubscribe: _pubsubSubscribe,
      pubsubUnsubscribe: _pubsubUnsubscribe,
      topicEventEmitter: _topicEventEmitter,
      ensureJoined: _ensureJoined,
    );
    realtimeStore = RealtimeStore(
        setValue: _setValue,
        getValue: _getValue,
        observe: _observe,
        stopObserve: _stopObserving,
        ensureJoined: _ensureJoined,
        realtimeStoreEventEmitter: _relatimeStoreEventEmitter);
    _defaultCameraIndex = defaultCameraIndex;

    // now,calling in joinRoom()
    // getDefaultDevices(defaultCameraIndex);

    //
    _eventEmitter.on("peers-bloc-participant-joined", (Peer newPeer) {
      if (newPeer.agentId != null) {
        // ── Agent participant ────────────────────────────────────────────
        final agentParticipant = AgentParticipant(
          id: newPeer.id,
          displayName: newPeer.displayName,
          eventEmitter: _eventEmitter,
          agentIdParam: newPeer.agentId,
          metaData: newPeer.metaData,
          enablePeerMic: _enablePeerMic,
          disablePeerMic: _disablePeerMic,
          enablePeerCamera: _enablePeerCamera,
          disablePeerCamera: _disablePeerCamera,
          // ── Add these 5 ──────────────────────────────
          getStats: _getStats,
          removePeer: _removePeer,
          setConsumerQuality: setConsumerQuality,
          setViewPort: setViewPort,
          participantPinStateChanged: _participantPinStateChange,
        );

        participants[newPeer.id] = agentParticipant;
        agentParticipants[newPeer.id] = agentParticipant;
        _eventEmitter.emit('participant-joined', agentParticipant);
      } else {
        // ── Regular participant ──────────────────────────────────────────
        final newParticipant = Participant(
          id: newPeer.id,
          displayName: newPeer.displayName,
          isLocal: false,
          mode: newPeer.mode,
          pinState: ParticipantPinState(),
          eventEmitter: _eventEmitter,
          enablePeerMic: _enablePeerMic,
          disablePeerMic: _disablePeerMic,
          enablePeerCamera: _enablePeerCamera,
          disablePeerCamera: _disablePeerCamera,
          removePeer: _removePeer,
          setConsumerQuality: setConsumerQuality,
          setViewPort: setViewPort,
          getStats: _getStats,
          participantPinStateChanged: _participantPinStateChange,
          consumeMicStreams: _consumeMicStreams,
          stopConsumingMicStreams: _stopConsumingMicStreams,
          consumeWebcamStreams: _consumeWebcamStreams,
          stopConsumingWebcamStreams: _stopConsumingWebcamStreams,
          metaData: newPeer.metaData,
        );
        participants[newPeer.id] = newParticipant;
        _eventEmitter.emit('participant-joined', newParticipant);
      }
    });

    //
    _eventEmitter.on("peers-bloc-participant-left",
        (String peerId, LeaveReason reason) {
      // Handle agent participant left
      if (agentParticipants.containsKey(peerId)) {
        agentParticipants.remove(peerId);
      }
      participants.remove(peerId);

      _eventEmitter.emit('participant-left', peerId, reason);

      if (VideoSDK.keyProvider != null &&
          VideoSDK.keyProvider!.keyMap != null &&
          VideoSDK.keyProvider!.keyMap.containsKey(peerId)) {
        VideoSDK.keyProvider!.keyMap.remove(peerId);
      }

      _eventEmitter.emit('participant-left', peerId, reason);

      SdkTracer.shared.traceEvent(
        spanName: 'Emitted `PARTICIPANT_LEFT` Event',
        attributes: {
          'peerId': peerId,
          'reason': reason.message,
          'code': reason.code,
        },
      );
    });

    //
    _eventEmitter.on("pubsub-message", _handlePubSubMessage);

    //
    _eventEmitter.on("peers-bloc-presenter-changed", (peerId) {
      _activePresenterId = peerId;
      _eventEmitter.emit("presenter-changed", peerId);
      SdkTracer.shared.traceEvent(
        spanName: 'Emitted `PRESENTER-CHANGED` Event',
        component: ComponentCategory.meeting,
        category: EventCategory.telemetry,
        attributes: {
          'peerId': peerId,
        },
      );
    });

    _eventEmitter.on("INIT_CHARACTER", (character) {
      characters?[character.id] = character;
    });

    _eventEmitter.on("ADD_CHARACTER", (config) {
      var id = config['id'];
      Character? character = characters?[id];

      if (character == null) {
        CharacterConfig characterConfig = CharacterConfig.newInteraction(
            characterId: config['id'],
            characterMode: CharacterMode.values.firstWhere(
                (value) => value.name.toLowerCase() == config['characterMode']),
            displayName: config['displayName']);
        character = Character(
            characterConfig: characterConfig,
            eventEmitter: _eventEmitter,
            state: CharacterState.values
                .firstWhereOrNull((value) => value.name == config['state']),
            enablePeerMic: _enablePeerMic,
            disablePeerMic: _disablePeerMic,
            enablePeerCamera: _enablePeerCamera,
            disablePeerCamera: _disablePeerCamera,
            joinCharacter: _joinCharacter,
            removeCharacter: _removeCharacter,
            sendMessage: _sendCharacterMessage,
            interruptCharacter: _interruptCharacter);
        characters?[character.id] = character;
      }

      _eventEmitter.emit("character-joined", character);
      //To emit event from the character class
      _eventEmitter.emit("CHARACTER-JOINED", character);
    });

    _eventEmitter.on("REMOVE_CHARACTER", (config) {
      var id = config['id'];
      if (characters?.containsKey(id) == true) {
        Character character = characters?[id];
        _eventEmitter.emit("character-left", character);
        //To emit event from the character class
        _eventEmitter.emit("CHARACTER-LEFT", character);
        characters?.remove(id);
      }
    });

    _metricsCollector = VideoSDKMetrics(VideoSDKMetricsConfig(
        emit: _eventEmitter.emit,
        name: "RoomMetrics",
        roomId: meetingId,
        peerId: participantId));

    _eventEmitter.on("request-pause-stream", (Map payload) async {
      try {
        final bool isLocal = payload['isLocal'] == true;
        final Consumer consumer = payload['consumer'];

        if (isLocal) {
          return;
        } else {
          await pause(consumer);
        }
      } catch (e) {
        //
      }
    });

    _eventEmitter.on("request-resume-stream", (Map payload) async {
      try {
        final bool isLocal = payload['isLocal'] == true;
        final Consumer consumer = payload['consumer'];
        if (isLocal) {
          return;
        } else {
          await resume(consumer);
        }
      } catch (e) {
        //
      }
    });
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

  bool _ensureJoined(String methodName, {bool allowWhileReconnecting = false}) {
    if (_joined &&
        (_roomState == RoomState.reconnecting || _rejoinInProgress) &&
        !allowWhileReconnecting) {
      _emitMeetingStateError(3027, methodName);
      return false;
    }

    if (!_joined ||
        _closed ||
        _webSocket == null ||
        _roomState == RoomState.failed) {
      _emitMeetingStateError(3022, methodName);
      return false;
    }

    return true;
  }

  bool _ensureLeavable(String methodName,
      {bool allowWhileReconnecting = true}) {
    if (_joined &&
        (_roomState == RoomState.reconnecting || _rejoinInProgress) &&
        !allowWhileReconnecting) {
      _emitMeetingStateError(3027, methodName);
      return false;
    }

    if (_webSocket == null || _closed) {
      _emitMeetingStateError(3022, methodName);
      return false;
    }

    return true;
  }

  void _emitMeetingStateError(int code, String methodName) {
    final Map<String, String> error = VideoSDKErrors[code]!;

    SdkTracer.shared.traceEvent(
      spanName: 'Emitting ERROR Event',
      component: ComponentCategory.meeting,
      category: EventCategory.error,
      dashboardLog: true,
      success: false,
      attributes: {
        "error":
            "${error['message']} Error encountered in $methodName() with code: ${error['code']}",
      },
    );

    _eventEmitter.emit("error", error);
    log("An error occurred in $methodName(): ${error['message']}");
  }

  _getDefaultDevices(defaultCameraIndex) async {
    try {
      // Use prefetched results if available (fired during WebSocket connect)
      if (_devicePrefetch != null) {
        final results = await _devicePrefetch!;
        videoDevices = results[0] as List<VideoDeviceInfo>?;
        audioDevices = results[1] as List<AudioDeviceInfo>?;
        _devicePrefetch = null;
      } else {
        final results = await Future.wait([
          VideoSDK.getVideoDevices(),
          VideoSDK.getAudioDevices(),
        ]);
        videoDevices = results[0] as List<VideoDeviceInfo>?;
        audioDevices = results[1] as List<AudioDeviceInfo>?;
      }
      //If custom track is given, set the deviceId from custom track as the selected device.
      //Otherwise set the selected device as the first device, because
      //enableMicImpl needs a device to make a custom track
      if (_customMicrophoneAudioTrack != null) {
        _setSelectedMicId(customTrack: _customMicrophoneAudioTrack);
      } else {
        _selectedAudioInput = audioDevices
            ?.firstWhereOrNull((device) => device.kind == "audioinput");
      }

      //If custom track is given, set the deviceId from custom track as the selected device.
      //Otherwise set the selected device as the first device, because
      //enableCamImpl needs a device to make a custom track
      if (_customCameraVideoTrack != null) {
        _setSelectedCamId(customTrack: _customCameraVideoTrack);
      } else {
        _selectedVideoInput = videoDevices?[defaultCameraIndex];
      }

      //In windows, and iOS the newly connected devices are rendered at the last position.
      if (!kIsWeb) {
        if (Platform.isWindows || Platform.isIOS) {
          _selectedAudioOutput = audioDevices
              ?.lastWhereOrNull((device) => device.kind == "audiooutput");
        }
      }
      if (kIsWeb || Platform.isAndroid || Platform.isMacOS) {
        _selectedAudioOutput = audioDevices
            ?.firstWhereOrNull((device) => device.kind == "audiooutput");
      }

      // Snapshot for device-change detection — reuse already-fetched audioDevices (no extra native call)
      List<AudioDeviceInfo>? tempAudioDevices = List.from(audioDevices ?? []);

      //Not available for MacOS
      VideoSDK.on(Events.deviceChanged, () async {
        videoDevices = await VideoSDK.getVideoDevices();
        audioDevices = await VideoSDK.getAudioDevices();
        if (!kIsWeb) {
          //In IOS and Windows the newly connected device is coming last in the list.
          if (Platform.isIOS || Platform.isWindows) {
            _selectedAudioOutput = audioDevices
                ?.lastWhereOrNull((device) => device.kind == "audiooutput");
            _selectedAudioInput = audioDevices
                ?.lastWhereOrNull((device) => device.kind == "audioinput");
          }
          //In android, deviceChange event coming even when switching from one device to another.
          // Change device id only when new device is connected/disconnected.
          else {
            //Get a new audio device list
            AudioDeviceInfo? device = audioDevices?.firstWhereOrNull(
                (newDevice) => !tempAudioDevices!.any(
                    (oldDevice) => oldDevice.deviceId == newDevice.deviceId));
            if (tempAudioDevices?.length != audioDevices?.length ||
                device?.deviceId != null) {
              _selectedAudioOutput = audioDevices
                  ?.firstWhereOrNull((device) => device.kind == "audiooutput");
              _selectedAudioInput = audioDevices
                  ?.firstWhereOrNull((device) => device.kind == "audioinput");
              tempAudioDevices = audioDevices;
            }
          }
        } else {
          _selectedAudioOutput = audioDevices
              ?.firstWhereOrNull((device) => device.kind == "audiooutput");
          _selectedAudioInput = audioDevices
              ?.firstWhereOrNull((device) => device.kind == "audioinput");
        }

        _dropStalePinnedDevices();
      });
    } catch (error) {
      SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
            name: "Error in get default media device",
            attributes: {
              "error": error.toString(),
            },
            category: EventCategory.error,
          );

      log("Unable to set default media device $error");
    }
  }

  //A pinned id in the track stores outranks _selectedAudioInput /
  //_selectedVideoInput on every rebuild, so a pin left pointing at hardware
  //that has since been unplugged keeps being requested after it is gone — the
  //factory then quietly resolves to devices.first instead. Dropping the pin
  //hands the choice back to the live selection the caller just refreshed.
  //An explicit changeMic()/changeCam() pin is only dropped once its device
  //actually disappears, so a deliberate choice survives unrelated churn.
  void _dropStalePinnedDevices() {
    final String? pinnedMicrophoneId = _micConfig.microphoneId;
    final List<AudioDeviceInfo>? mics = audioDevices;

    if (pinnedMicrophoneId != null &&
        mics != null &&
        mics.isNotEmpty &&
        !mics.any((device) => device.deviceId == pinnedMicrophoneId)) {
      _micConfig = _micConfig.copyWith(clearMicrophoneId: true);
    }

    final String? pinnedCameraId = _customVideoTrackConfig.cameraId;
    final List<VideoDeviceInfo>? cameras = videoDevices;

    if (pinnedCameraId != null &&
        cameras != null &&
        cameras.isNotEmpty &&
        !cameras.any((device) => device.deviceId == pinnedCameraId)) {
      _customVideoTrackConfig =
          _customVideoTrackConfig.copyWith(clearCameraId: true);
    }
  }

  /// It will be the `id` of the participant who is actively speaking in the room. If no participant is speaking, at that time value of `activeSpeakerId` will be `null`.
  ///
  /// ### Type
  ///
  /// - `String`
  String? get activeSpeakerId => _activeSpeakerId;

  /// It will be the `id` of the participant who started `Presenting` / `Screen sharing` in the room. If no participant is sharing the screen, at that time value of `activePresenterId` will be `null`.
  ///
  /// ### Type
  ///
  /// - `String`
  String? get activePresenterId => _activePresenterId;

  /// Represents the current livestream state of the room.
  ///
  /// This returns the current status of livestreaming for the room.
  ///
  /// ### Type
  ///
  /// - `String`
  String get livestreamState => _livestreamState;

  /// Represents the current HLS state of the room.
  ///
  /// This returns the current status of HLS streaming for the room.
  ///
  /// ### Type
  ///
  /// - `String`
  String get hlsState => _hlsState;

  /// Represents the current recording state of the room.
  ///
  /// This returns the current status of room recording.
  ///
  /// ### Type
  ///
  /// - `String`
  String get recordingState => _recordingState;

  /// Returns the downstream URL for the ongoing HLS session, if available.
  ///
  /// This URL can be used to access the live HLS stream of the room.
  ///
  /// ### Type
  ///
  /// - `String?`
  String? get hlsDownstreamUrl => _hlsDownstreamUrl;

  /// @nodoc
  Map<String, String?> get hlsUrls => _hlsUrls;

  /// Disables (mutes) the microphone device for the local participant.
  ///
  /// - When the microphone is successfully disabled, a [Events.streamDisabled]
  /// event is emitted with the corresponding audio [Stream] object in the
  /// event handler, inside the associated [Participant] object.
  ///
  /// ## Events associated with muteMic()
  ///
  /// - [Events.streamDisabled] with the disabled audio [Stream]
  ///
  /// ### **Example**
  /// ```dart
  /// // Mute microphone
  /// await room.muteMic();
  ///
  /// room.on(Events.streamDisabled, (event) {
  ///   print('Microphone stream disabled: ${event.stream.id}');
  /// });
  ///
  /// // Mute microphone from a button
  /// ElevatedButton(
  ///   onPressed: () async {
  ///     await room.muteMic();
  ///   },
  ///   child: Text('Mute Mic'),
  /// )
  /// ```
  Future<void> muteMic() async {
    if (!_ensureJoined("muteMic")) return;
    await _disableMic(clearIntent: true);
  }

  /// Enables (unmutes) the microphone device for the local participant.
  ///
  /// When the microphone is successfully enabled, a [Events.streamEnabled] event
  /// is emitted with the corresponding audio [Stream] object in the event
  /// handler, inside the associated [Participant] object.
  ///
  /// ### **Parameters**
  ///
  /// - [customAudioTrack] *(optional)*:
  ///   A custom audio track to be used instead of the default microphone input.
  ///   This can be useful when providing an externally generated audio source
  ///   or applying custom audio processing before publishing.
  ///
  /// ## Events associated with unmuteMic()
  ///
  /// - [Events.streamEnabled] with the enabled audio [Stream]
  ///
  /// ### **Example**
  /// ```dart
  /// // Unmute microphone using the default device
  /// await room.unmuteMic();
  ///
  /// // Unmute microphone with a custom audio track
  /// final customTrack = await CustomTrack.createAudioTrack();
  /// await room.unmuteMic(customTrack);
  ///
  /// room.on(Events.streamEnabled, (event) {
  ///   print('Microphone stream enabled: ${event.stream.id}');
  /// });
  /// ```
  //
  Future<void> unmuteMic([CustomTrack? customAudioTrack]) async {
    if (!_ensureJoined("unmuteMic")) {
      customAudioTrack?.dispose();
      return;
    }
    await _enableMicImpl(customTrack: customAudioTrack, setIntent: true);
  }

  //
  Future<void> _disableMic(
      {SpanScope? parentSpan,
      bool trackEnded = false,
      bool clearIntent = false}) async {
    SpanScope? disableMicSpan = SdkTracer.shared.startSpan(
      spanName: "Disabling Microphone",
      parentSpan: parentSpan,
      component: ComponentCategory.media,
      category:
          parentSpan == null ? EventCategory.telemetry : EventCategory.debug,
    );

    if (_webSocket == null) {
      SdkTracer.shared.to(OutputTarget.toConsole).endSpan(
            disableMicSpan,
            category: EventCategory.error,
            success: false,
            message: VideoSDKErrors[3022]!['message']!,
          );
      return;
    }

    if (clearIntent) {
      _micEnabled = false;
    }

    if (_micProducer == null) {
      SdkTracer.shared.endSpan(
        disableMicSpan,
        success: false,
        message:
            "Attempted to call muteMic() while the microphone is already disabled",
        dashboardLog: true,
        category: EventCategory.error,
        attributes: {
          'error': "Error in muteMic() -> microphone is already disabled",
        },
      );
      //  log("An error occurred in muteMic(): Attempted to call muteMic() while the microphone is already disabled");
      return;
    }

    String micId = _micProducer!.id;

    _micInProgress = true;

    SpanScope? internalSpan = SdkTracer.shared.startSpan(
      spanName: "Disposing Audio Track",
      parentSpan: disableMicSpan,
      component: ComponentCategory.media,
    );

    _micState = false;

    if (trackEnded) {
      _removeProducer(_micProducer!, _ProducerType.micProducer, disableMicSpan);
      _micProducer = null;

      SdkTracer.shared.endSpan(
        internalSpan,
        message: "Audio track disposed successfully",
      );
    } else {
      _micProducer!.pause();

      SdkTracer.shared.endSpan(
        internalSpan,
        message: "Audio track disposed successfully",
      );

      SdkTracer.shared.traceEvent(
        spanName: "Emitting STREAM_DISABLED event",
        parentScope: disableMicSpan,
        attributes: {
          'kind': 'audio',
          'peerId': localParticipant.id,
        },
        category: EventCategory.telemetry,
        component: ComponentCategory.media,
      );

      _eventEmitter.emit(
        "stream-disabled-${localParticipant.id}",
        {
          "audioConsumerId": micId,
        },
      );
    }

    SpanScope? transSpan;
    try {
      transSpan = SdkTracer.shared.startSpan(
        spanName: "Stopping Audio Stream transmission",
        parentSpan: disableMicSpan,
        component: ComponentCategory.media,
      );

      await _webSocket!.sendRequest(
        'closeProducer',
        {
          'producerId': micId,
        },
      );

      SdkTracer.shared.endSpan(
        transSpan,
        message: "Audio Stream transmission stopped successfully",
      );

      SdkTracer.shared.endSpan(
        disableMicSpan,
        message: "Microphone disabled successfully",
      );
    } catch (error) {
      SdkTracer.shared.endSpan(
        transSpan,
        success: false,
        category: EventCategory.error,
        message:
            "Failed to stop Audio Stream transmission: ${error.toString()}",
      );

      SdkTracer.shared.endSpan(
        disableMicSpan,
        success: false,
        message: "Error encountered while disabling the Microphone ",
        dashboardLog: true,
        category: EventCategory.error,
        attributes: {"error": "Error in muteMic() -> ${error.toString()}"},
      );
    } finally {
      _micInProgress = false;
    }
  }

  //
  Future<void> _enableMicImpl(
      {CustomTrack? customTrack,
      SpanScope? parentSpan,
      bool setIntent = false}) async {
    //If method is called before meeting is joined
    SpanScope? enableMicSpan = SdkTracer.shared.startSpan(
        spanName:
            'Enabling microphone with${customTrack != null ? " " : "out "}Custom Audio Track',
        attributes: {
          'customAudioConfig': customTrack != null
              ? customTrack.toMap().toString()
              : 'Custom Track not provided',
        },
        category:
            parentSpan != null ? EventCategory.debug : EventCategory.telemetry,
        parentSpan: parentSpan,
        component: ComponentCategory.media);

    if (_webSocket == null) {
      SdkTracer.shared.to(OutputTarget.toConsole).endSpan(
            enableMicSpan,
            category: EventCategory.error,
            success: false,
            message: VideoSDKErrors[3022]!['message']!,
          );
      //Silent: unmuteMic() already reported this to the app, and the internal
      //callers (changeMic, reconnect rebuild) must not raise one.
      if (customTrack != null) {
        customTrack.dispose();
      }
      return;
    }

    SpanScope? micProducerSpan;
    AudioDeviceInfo? deviceToSwitch;

    if (_micInProgress) {
      SdkTracer.shared.endSpan(
        enableMicSpan,
        success: false,
        message:
            'Attempted to call unmuteMic() while the microphone is already enabled',
        dashboardLog: true,
        category: EventCategory.error,
        attributes: {
          'error': "Error in unmuteMic() -> microphone is already enabled"
        },
      );
      //  log("An error occurred in unmuteMic(): Attempted to call unmuteMic() while the microphone is already enabled");
      if (customTrack != null) {
        customTrack.dispose();
      }
      return;
    }

    _micInProgress = true;

    if (!kIsWeb) {
      if (Platform.isAndroid || Platform.isIOS) {
        if (customTrack != null && customTrack.microphoneId != null) {
          var speakers = await VideoSDK.getAudioDevices();
          deviceToSwitch = speakers?.firstWhereOrNull(
              (speaker) => speaker.deviceId == customTrack?.microphoneId);
        }
      }
    }

    if (customTrack != null) {
      if (customTrack.ended == true) {
        customTrack = null;
        SdkTracer.shared.endSpan(
          enableMicSpan,
          success: false,
          message: 'Invalid Custom Audio Track Passed. Reverting to default',
          category: EventCategory.error,
        );

        _eventEmitter.emit("error", VideoSDKErrors[3002]);
        log("An error occurred in unmuteMic(): VIDEOSDK ERROR :: ${VideoSDKErrors[3002]?['code']}  :: ${VideoSDKErrors[3002]?['name']} :: ${VideoSDKErrors[3002]?['message']}");
      }
    }

    //If mic is unmuted other than the first time.
    if (_micProducer != null) {
      micProducerSpan = SdkTracer.shared.startSpan(
        spanName: 'Starting Audio Stream transmission',
        parentSpan: enableMicSpan,
        attributes: {
          'audioTrackConfig': _micProducer?.track != null
              ? 'kind: ${_micProducer!.track.kind}, id: ${_micProducer!.track.id}, label: ${_micProducer!.track.label}'
              : 'Track not provided',
        },
        component: ComponentCategory.media,
      );

      if (customTrack != null) {
        if (_customMicrophoneAudioTrack != null) {
          _customMicrophoneAudioTrack!.dispose();
          _customMicrophoneAudioTrack = null;
        }
        //This is because _customMicrophoneTrack is disposed here,
        //but used the next time as customTrack in case a track is not provided
        // (here : customTrack ??= _customMicrophoneAudioTrack;)
        _customMicrophoneAudioTrack = customTrack;

        //Accepted custom track ⇒ full config replace (R5), so the supplied
        //profile survives later store-driven rebuilds (unmuteMic/changeMic).
        _micConfig = MicConfig.fromCustomTrack(customTrack);

        SdkTracer.shared.traceEvent(
          spanName: 'Utilising resolved Audio Track',
          parentScope: enableMicSpan,
          component: ComponentCategory.media,
          category: EventCategory.telemetry,
          attributes: {
            'config': _micConfig.encoderConfig.name,
            'configSource': 'custom-track',
          },
        );
      }

      //
      MediaStream? audioStream;
      MediaStreamTrack? track;
      Map<String, dynamic>? encoderConfig;
      ProducerCodecOptions? codecOptions;

      customTrack ??= _customMicrophoneAudioTrack;

      if (customTrack == null || customTrack.ended == true) {
        customTrack = await VideoSDK.createMicrophoneAudioTrack(
            microphoneId:
                _micConfig.microphoneId ?? _selectedAudioInput?.deviceId,
            encoderConfig: _micConfig.encoderConfig,
            noiseConfig: _micConfig.noiseConfig ?? const {});

        //If there is an error, createMicrophoneAudioTrack will return null.
        if (customTrack == null) {
          SdkTracer.shared.endSpan(
            micProducerSpan,
            success: false,
            message:
                'Error in unmuteMic() -> while rebuilding Microphone Track',
            category: EventCategory.error,
          );

          SdkTracer.shared.endSpan(
            enableMicSpan,
            success: false,
            message: VideoSDKErrors[3012]!['message']!,
            dashboardLog: true,
            category: EventCategory.error,
            attributes: {
              'error': 'Error in unmuteMic() -> Cannot create audio track',
            },
          );

          _eventEmitter.emit("error", VideoSDKErrors[3012]);
          log("An error occurred in unmuteMic(): VIDEOSDK ERROR :: ${VideoSDKErrors[3012]?['code']}  :: ${VideoSDKErrors[3012]?['name']} :: ${VideoSDKErrors[3012]?['message']}");

          _micInProgress = false;
          return;
        }

        _customMicrophoneAudioTrack = customTrack;
      }

      audioStream = customTrack.mediaStream;
      track = audioStream.getAudioTracks().first;
      encoderConfig =
          customAudioTrackConfigMap[customTrack.audioEncoderConfig]!;

      if (encoderConfig != null) {
        codecOptions = ProducerCodecOptions(
          opusStereo: encoderConfig["stereo"] ? 1 : 0,
          opusFec: encoderConfig["fec"] ? 1 : 0,
          opusDtx: encoderConfig["dtx"] ? 1 : 0,
          opusMaxPlaybackRate: encoderConfig["maxPlaybackRate"],
          opusPtime: encoderConfig["packetTime"],
          // opusMaxAverageBitrate: encoderConfig["bitRate"]
        );
      }

      if (!setIntent && !_micEnabled) {
        SdkTracer.shared.endSpan(
          micProducerSpan,
          success: true,
          message:
              'Audio Stream transmission aborted : mic was muted while the track was being prepared',
        );

        SdkTracer.shared.endSpan(
          enableMicSpan,
          success: true,
          message: 'Microphone enable aborted : mic was muted by the user',
        );

        await customTrack.dispose();
        _customMicrophoneAudioTrack = null;
        _micInProgress = false;
        return;
      }

      if (_sendTransport != null) {
        //Resumed here rather than before the rebuild above: everything between
        //the two points can fail and return, and un-pausing first would leave
        //the old producer live on the previous device while _micState stayed
        //false — audio flowing from a mic the caller believes is muted. This
        //is the normal route after a changeMic() while muted, which clears
        //_customMicrophoneAudioTrack and so always forces the rebuild.
        if (!_micProducer!.closed && _micProducer!.paused) {
          _micProducer!.resume();
        }

        _sendTransport!.produce(
          track: track,
          codecOptions: codecOptions,
          stream: audioStream,
          appData: {
            'source': 'mic',
            'encoderConfig': encoderConfig,
          },
          stopTracks: false,
          source: 'mic',
          sourceContext: enableMicSpan,
        );
      } else {
        SdkTracer.shared.endSpan(
          micProducerSpan,
          success: false,
          message:
              'Error in unmuteMic() -> Tried to unmute mic while room is in a connecting state.',
          category: EventCategory.error,
        );

        SdkTracer.shared.endSpan(
          enableMicSpan,
          success: false,
          message: VideoSDKErrors[3012]!['message']!,
          category: EventCategory.error,
          attributes: {
            'error':
                'Error in enableMic() -> Tried to enable mic while meeting is in a connecting state.',
          },
        );

        _eventEmitter.emit("error", VideoSDKErrors[3012]);
        //  log("An error occurred in unmuteMic(): VIDEOSDK ERROR :: ${VideoSDKErrors[3012]?['code']}  :: ${VideoSDKErrors[3012]?['name']} :: ${VideoSDKErrors[3012]?['message']}");
        if (customTrack != null) {
          customTrack.dispose();
        }
        _micInProgress = false;
        return;
      }

      SdkTracer.shared.endSpan(
        micProducerSpan,
        message: 'Audio Stream transmission started successfully',
      );

      SdkTracer.shared.endSpan(
        enableMicSpan,
        message: 'Microphone turned on successfully',
      );

      _micState = true;
      if (setIntent) {
        _micEnabled = true;
      }

      if (kIsWeb || Platform.isWindows || Platform.isMacOS) {
        _setSelectedMicId(customTrack: customTrack);
      } else {
        if (deviceToSwitch != null) {
          switchAudioDevice(deviceToSwitch);
        }
      }

      return;
    }

    _micInProgress = true;

    //
    if (_device?.canProduce(RTCRtpMediaType.RTCRtpMediaTypeAudio) == false) {
      SdkTracer.shared.endSpan(
        enableMicSpan,
        success: false,
        message: VideoSDKErrors[3020]!['message']!,
        dashboardLog: true,
        category: EventCategory.error,
        attributes: {
          'error': 'Error in unmuteMic() -> Microphone access unavailable',
        },
      );

      _eventEmitter.emit("error", VideoSDKErrors[3020]);
      if (customTrack != null) {
        customTrack.dispose();
      }
      _micInProgress = false;
      return;
    }

    MediaStreamTrack? track;
    SpanScope? trackSpan;

    //configSource for the resolved-track telemetry below.
    final bool micRebuiltFromStore = customTrack == null;

    try {
      if (customTrack == null) {
        trackSpan = SdkTracer.shared.startSpan(
          spanName: 'Creating Audio Track',
          parentSpan: enableMicSpan,
          component: ComponentCategory.media,
        );

        SdkTracer.shared.traceEvent(
          spanName: 'Rebuilding Audio Track',
          parentScope: enableMicSpan,
          component: ComponentCategory.media,
          category: EventCategory.telemetry,
          attributes: {
            'config': _micConfig.encoderConfig.name,
          },
        );

        customTrack = await VideoSDK.createMicrophoneAudioTrack(
            microphoneId:
                _micConfig.microphoneId ?? _selectedAudioInput?.deviceId,
            encoderConfig: _micConfig.encoderConfig,
            noiseConfig: _micConfig.noiseConfig ?? const {});

        //If there is an error, createMicrophoneAudioTrack will return null.
        if (customTrack == null) {
          SdkTracer.shared.endSpan(
            trackSpan,
            success: false,
            message: 'Error in unmuteMic() -> while creating Microphone Track',
            category: EventCategory.error,
          );

          SdkTracer.shared.endSpan(
            enableMicSpan,
            success: false,
            message: VideoSDKErrors[3012]!['message']!,
            dashboardLog: true,
            category: EventCategory.error,
            attributes: {
              'error': 'Error in unmuteMic() -> Cannot create audio track',
            },
          );

          _eventEmitter.emit("error", VideoSDKErrors[3012]);
          log("An error occurred in unmuteMic(): VIDEOSDK ERROR :: ${VideoSDKErrors[3012]?['code']}  :: ${VideoSDKErrors[3012]?['name']} :: ${VideoSDKErrors[3012]?['message']}");

          _micInProgress = false;
          return;
        }

        SdkTracer.shared.endSpan(
          trackSpan,
          message: 'Default Audio Track Generated',
        );
      } else {
        trackSpan = SdkTracer.shared.startSpan(
          spanName: 'Utilising provided custom track',
          parentSpan: enableMicSpan,
          attributes: {
            'customAudioTrackConfig': customTrack.toMap().toString(),
          },
          component: ComponentCategory.media,
        );

        if (customTrack.ended == true) {
          SdkTracer.shared.endSpan(
            trackSpan,
            success: false,
            message: 'Invalid Custom Audio Track Passed. Reverting to default',
            category: EventCategory.error,
          );

          _eventEmitter.emit("error", VideoSDKErrors[3002]);
          customTrack = null;
        } else {
          SdkTracer.shared.endSpan(
            trackSpan,
          );
          track = customTrack.mediaStream.getAudioTracks().first;
        }
      }

      _customMicrophoneAudioTrack = customTrack;

      //Accepted custom track ⇒ full config replace (R5). Store-rebuilt tracks
      //round-trip their stamped metadata, so this is a no-op for them — with
      //one exception. The rebuild resolves the device as
      //`_micConfig.microphoneId ?? _selectedAudioInput?.deviceId`, and the
      //factory stamps whatever it resolved onto the track. Writing that back
      //would turn a one-off fallback into a permanent pin that the `??` can
      //never see past again, so a store rebuild keeps the store's own id.
      if (customTrack != null) {
        final MicConfig resolvedMicConfig =
            MicConfig.fromCustomTrack(customTrack);
        final String? pinnedMicrophoneId = _micConfig.microphoneId;

        _micConfig = micRebuiltFromStore
            ? resolvedMicConfig.copyWith(
                microphoneId: pinnedMicrophoneId,
                clearMicrophoneId: pinnedMicrophoneId == null,
              )
            : resolvedMicConfig;
      }

      SdkTracer.shared.traceEvent(
        spanName: 'Utilising resolved Audio Track',
        parentScope: enableMicSpan,
        component: ComponentCategory.media,
        category: EventCategory.telemetry,
        attributes: {
          'config': _micConfig.encoderConfig.name,
          'configSource':
              micRebuiltFromStore ? 'store-rebuild' : 'custom-track',
        },
      );

      //Updating the list, in case permission status has changed.
      //(As in web, device labels and ids are not available w/o media permissions.)
      //await VideoSDK.loadMediaDevices();
      audioDevices = await VideoSDK.getAudioDevices();

      //
      MediaStream? audioStream;

      SpanScope? _internalSpan;
      //
      _internalSpan = SdkTracer.shared.startSpan(
        spanName: 'Generating configurations for Audio Stream',
        parentSpan: enableMicSpan,
        component: ComponentCategory.media,
      );

      //
      audioStream = customTrack!.mediaStream;
      //
      track ??= audioStream.getAudioTracks().first;

      Map<String, dynamic> encoderConfig =
          customAudioTrackConfigMap[customTrack.audioEncoderConfig]!;

      ProducerCodecOptions codecOptions = ProducerCodecOptions(
        opusStereo: encoderConfig["stereo"] ? 1 : 0,
        opusFec: encoderConfig["fec"] ? 1 : 0,
        opusDtx: encoderConfig["dtx"] ? 1 : 0,
        opusMaxPlaybackRate: encoderConfig["maxPlaybackRate"],
        opusPtime: encoderConfig["packetTime"],
        // opusMaxAverageBitrate: encoderConfig["bitRate"]
      );

      SdkTracer.shared.endSpan(
        _internalSpan,
        message: 'Audio stream configurations generated',
      );

      _internalSpan = SdkTracer.shared.startSpan(
        spanName: 'Starting Audio Stream transmission',
        parentSpan: enableMicSpan,
        attributes: {
          'audioTrackConfig': track != null
              ? 'kind: ${track.kind}, id: ${track.id}, label: ${track.label}'
              : 'Track not provided',
        },
        component: ComponentCategory.media,
      );

      //Same last intent check as the resume branch above — this is the
      //first-unmute path into the same window.
      if (!setIntent && !_micEnabled) {
        SdkTracer.shared.endSpan(
          _internalSpan,
          success: true,
          message:
              'Audio Stream transmission aborted : mic was muted while the track was being prepared',
        );

        SdkTracer.shared.endSpan(
          enableMicSpan,
          success: true,
          message: 'Microphone enable aborted : mic was muted by the user',
        );

        await customTrack.dispose();
        _customMicrophoneAudioTrack = null;
        _micInProgress = false;
        return;
      }

      //
      if (_sendTransport != null) {
        _sendTransport!.produce(
          track: track,
          codecOptions: codecOptions,
          stream: audioStream,
          appData: {
            'source': 'mic',
            'encoderConfig': encoderConfig,
          },
          stopTracks: false,
          source: 'mic',
          sourceContext: enableMicSpan,
        );
      } else {
        SdkTracer.shared.endSpan(
          _internalSpan,
          success: false,
          message:
              'Error in unmuteMic() -> Tried to unmute mic while room is in a connecting state.',
          category: EventCategory.error,
        );

        SdkTracer.shared.endSpan(
          enableMicSpan,
          success: false,
          message: VideoSDKErrors[3012]!['message']!,
          dashboardLog: true,
          category: EventCategory.error,
          attributes: {
            'error':
                'Error in enableMic() -> Tried to enable mic while meeting is in a connecting state.',
          },
        );

        _eventEmitter.emit("error", VideoSDKErrors[3012]);
        log("An error occurred in unmuteMic(): VIDEOSDK ERROR :: ${VideoSDKErrors[3012]?['code']}  :: ${VideoSDKErrors[3012]?['name']} :: ${VideoSDKErrors[3012]?['message']}");
        if (customTrack != null) {
          customTrack.dispose();
        }
        if (audioStream != null) {
          await audioStream.dispose();
        }
        _micInProgress = false;
        return;
      }

      SdkTracer.shared.endSpan(
        _internalSpan,
        message: 'Audio Stream transmission started successfully',
      );

      SdkTracer.shared.endSpan(
        enableMicSpan,
        message: 'Microphone turned on successfully',
      );

      _micState = true;
      if (setIntent) {
        _micEnabled = true;
      }

      if (kIsWeb || Platform.isWindows || Platform.isMacOS) {
        _setSelectedMicId(customTrack: customTrack);
      } else {
        if (deviceToSwitch != null) {
          switchAudioDevice(deviceToSwitch);
        }
      }
    } catch (error) {
      _micInProgress = false;

      SdkTracer.shared.endSpan(
        enableMicSpan,
        success: false,
        message: 'Error while enabling microphone in unmuteMic()',
        dashboardLog: true,
        category: EventCategory.error,
        attributes: {
          'error': 'Error in unmuteMic() ->  ${error.toString()}',
        },
      );
      if (track != null) {
        track.stop();
      }
    }
  }

  Future<void> _setSelectedMicId({CustomTrack? customTrack}) async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return;
    }

    try {
      MediaStreamTrack? track = customTrack?.mediaStream.getAudioTracks().first;
      if (!kIsWeb) {
        //For devices other than web directly getting deviceId on customTrack
        if (track != null && track.getSettings().containsKey("deviceId")) {
          AudioDeviceInfo? device = audioDevices?.firstWhereOrNull(
            (device) =>
                device.deviceId == track.getSettings()["deviceId"] &&
                device.kind == "audioinput",
          );
          _selectedAudioInput = device;
        }
      } else {
        if (track != null && track.label != null) {
          AudioDeviceInfo? device = audioDevices?.firstWhereOrNull(
            (device) =>
                device.label == track.label && device.kind == "audioinput",
          );
          _selectedAudioInput = device;
        }
      }
    } catch (_) {}
  }

  /// Enables the WebCam device for the local participant.
  ///
  /// - When the WebCam is successfully enabled, a [Events.streamEnabled] event
  /// is emitted with a [Stream] object in the event handler, inside the
  /// corresponding [Participant] object.
  ///
  /// ### **Parameters**
  ///
  /// - [customVideoTrack] *(optional)*:
  ///   A custom video track to be used instead of the default WebCam track.
  ///   This is useful when you want to provide a pre-processed video source
  ///   (for example, a virtual WebCam, screen capture, or a WebCam track
  ///   with applied effects).
  ///
  /// ## Events associated with enableCam()
  ///
  /// - [Events.streamEnabled] with the enabled video [Stream]
  ///
  /// ### **Example**
  /// ```dart
  /// // Enable WebCam with default device
  /// await room.enableCam();
  ///
  /// // Enable WebCam with a custom video track
  /// final customTrack = await CustomTrack.createCameraTrack();
  /// await room.enableCam(customTrack);
  ///
  /// room.on(Events.streamEnabled, (event) {
  ///   print('Camera stream enabled: ${event.stream.id}');
  /// });
  /// ```
  Future<void> enableCam([CustomTrack? customVideoTrack]) async {
    if (!_ensureJoined("enableCam")) {
      customVideoTrack?.dispose();
      return;
    }
    await _enableCamImpl(customTrack: customVideoTrack, setIntent: true);
  }

  Future<void> _enableCamImpl(
      {CustomTrack? customTrack,
      SpanScope? parentSpan,
      bool setIntent = false,
      VideoCodec? recycleFrom}) async {
    // send trace enableCam
    SpanScope? enableWebcamScope = SdkTracer.shared.startSpan(
      spanName:
          'Enabling Webcam with${customTrack != null ? " " : "out "}Custom Video Track',
      attributes: {
        'customVideoConfig': customTrack != null
            ? customTrack.toMap().toString()
            : 'Custom Track not provided',
      },
      parentSpan: parentSpan,
      category:
          parentSpan == null ? EventCategory.telemetry : EventCategory.debug,
      component: ComponentCategory.media,
    );

    //If method is called before meeting is joined
    if (_webSocket == null) {
      SdkTracer.shared.to(OutputTarget.toConsole).endSpan(
            enableWebcamScope,
            category: EventCategory.error,
            success: false,
            message: VideoSDKErrors[3022]!['message']!,
          );
      if (customTrack != null) {
        customTrack.dispose();
      }
      return;
    }

    //If WebCam is already enabled, return without enabling it again
    if (_cameraInProgress) {
      SdkTracer.shared.endSpan(
        enableWebcamScope,
        category: EventCategory.error,
        success: false,
        message:
            'Attempted to call enableCam() while the Cam is already enabled',
        dashboardLog: true,
        attributes: {
          'error': 'Error in enableCam() -> Camera is already enabled',
        },
      );

      if (customTrack != null) {
        customTrack.dispose();
      }
      return;
    }

    _cameraInProgress = true;

    //If the device is incapable of producing video
    if (_device?.canProduce(RTCRtpMediaType.RTCRtpMediaTypeVideo) == false) {
      SdkTracer.shared.endSpan(
        enableWebcamScope,
        category: EventCategory.error,
        success: false,
        message: VideoSDKErrors[3019]!['message']!,
        dashboardLog: true,
        attributes: {
          'error': 'Error in enableCam() -> Camera access unavailable',
        },
      );

      _eventEmitter.emit("error", VideoSDKErrors[3019]);
      //   log("An error occurred in enableCam(): VIDEOSDK ERROR :: ${VideoSDKErrors[3019]?['code']}  :: ${VideoSDKErrors[3019]?['name']} :: ${VideoSDKErrors[3019]?['message']}");

      if (customTrack != null) {
        customTrack.dispose();
      }
      _cameraInProgress = false;
      return;
    }

    //If user has given a track that has been disposed.
    if (customTrack != null) {
      SpanScope? trackValidationSpan;

      trackValidationSpan = SdkTracer.shared.startSpan(
        spanName: 'Utilising provided custom track',
        parentSpan: enableWebcamScope,
        attributes: {
          'customVideoTrackConfig': customTrack.toMap().toString(),
        },
        component: ComponentCategory.media,
      );

      if (customTrack.ended == true) {
        SdkTracer.shared.endSpan(
          trackValidationSpan,
          category: EventCategory.error,
          success: false,
          message: 'Invalid Custom Video Track Passed. Reverting to default.',
        );
        customTrack = null;
        _eventEmitter.emit("error", VideoSDKErrors[3001]);
        log("An error occurred in enableCam(): VIDEOSDK ERROR :: ${VideoSDKErrors[3001]?['code']}  :: ${VideoSDKErrors[3001]?['name']} :: ${VideoSDKErrors[3001]?['message']}");
      } else {
        try {
          SdkTracer.shared.endSpan(
            trackValidationSpan,
          );
        } catch (_) {}
      }
    }

    //configSource for the resolved-track telemetry below: a track the app
    //supplied on this call (and that survived validation) vs a store rebuild.
    final bool camRebuiltFromStore = customTrack == null;

    if (customTrack == null) {
      SpanScope? _internalScope;
      try {
        _internalScope = SdkTracer.shared.startSpan(
          spanName: 'Creating Video Track',
          parentSpan: enableWebcamScope,
          component: ComponentCategory.media,
        );
      } catch (_) {}

      try {
        SdkTracer.shared.traceEvent(
          spanName: 'Rebuilding Video Track',
          parentScope: enableWebcamScope,
          component: ComponentCategory.media,
          category: EventCategory.telemetry,
          attributes: {
            'config': _customVideoTrackConfig.encoderConfig.name,
          },
        );

        customTrack = await VideoSDK.createCameraVideoTrack(
            cameraId: _customVideoTrackConfig.cameraId ??
                _selectedVideoInput?.deviceId,
            multiStream: _customVideoTrackConfig.multiStream,
            encoderConfig: _customVideoTrackConfig.encoderConfig,
            facingMode: _customVideoTrackConfig.facingMode,
            bitrateMode: _customVideoTrackConfig.bitrateMode,
            maxLayer: _customVideoTrackConfig.maxLayer,
            codec: _customVideoTrackConfig.codec);

        //If there is an error, createCameraVideoTrack will return null.
        if (customTrack == null) {
          SdkTracer.shared.endSpan(
            _internalScope,
            category: EventCategory.error,
            success: false,
            message: 'Error in enableCam() -> while creating Video Track',
          );
          SdkTracer.shared.endSpan(
            enableWebcamScope,
            category: EventCategory.error,
            success: false,
            message: VideoSDKErrors[3011]!['message']!,
            dashboardLog: true,
            attributes: {
              'error': 'Error in enableCam() -> Cannot create video track',
            },
          );

          _eventEmitter.emit("error", VideoSDKErrors[3011]);
          log("An error occurred in enableCam(): VIDEOSDK ERROR :: ${VideoSDKErrors[3011]?['code']}  :: ${VideoSDKErrors[3011]?['name']} :: ${VideoSDKErrors[3011]?['message']}");

          _cameraInProgress = false;
          return;
        }

        try {
          SdkTracer.shared.endSpan(
            _internalScope,
            success: true,
            message: 'Default Camera Track Generated',
          );
        } catch (_) {}
      } catch (error) {
        SdkTracer.shared.endSpan(
          _internalScope,
          category: EventCategory.error,
          success: false,
          message:
              'Error in enableCam() while creating Video Track -> ${error.toString()}',
        );
        SdkTracer.shared.endSpan(
          enableWebcamScope,
          category: EventCategory.error,
          success: false,
          message: VideoSDKErrors[3011]!['message']!,
          dashboardLog: true,
          attributes: {
            'error': 'Error in enableCam() -> Cannot create video track',
            'errorMessage': error.toString(),
          },
        );

        _eventEmitter.emit("error", VideoSDKErrors[3011]);
        log("An error occurred in enableCam(): VIDEOSDK ERROR :: ${VideoSDKErrors[3011]?['code']}  :: ${VideoSDKErrors[3011]?['name']} :: ${VideoSDKErrors[3011]?['message']}");

        _cameraInProgress = false;
        return;
      }
    }

    MediaStream? videoStream;
    MediaStreamTrack? track;
    SpanScope? _internalScope;

    //Updating the list, in case permission status has changed.
    //(As in web, device labels and ids are not available w/o media permissions.)
    //await VideoSDK.loadMediaDevices();
    videoDevices = await VideoSDK.getVideoDevices();

    try {
      try {
        _internalScope = SdkTracer.shared.startSpan(
          spanName: 'Generating configurations for Video Stream',
          parentSpan: enableWebcamScope,
          component: ComponentCategory.media,
        );
      } catch (_) {}

      RtpCodecCapability codec;

      //Same pin hazard as the mic store (see _enableMicImpl): the rebuild
      //resolves `_customVideoTrackConfig.cameraId ?? _selectedVideoInput`, and
      //the factory stamps the resolved id onto the track. The rest of the
      //write-back is wanted — the factory also resolves maxLayer — so only the
      //id is held back on a store rebuild.
      final WebcamConfig resolvedWebcamConfig =
          WebcamConfig.fromCustomTrack(customTrack);
      final String? pinnedCameraId = _customVideoTrackConfig.cameraId;

      _customVideoTrackConfig = camRebuiltFromStore
          ? resolvedWebcamConfig.copyWith(
              cameraId: pinnedCameraId,
              clearCameraId: pinnedCameraId == null,
            )
          : resolvedWebcamConfig;

      SdkTracer.shared.traceEvent(
        spanName: 'Utilising resolved Video Track',
        parentScope: enableWebcamScope,
        component: ComponentCategory.media,
        category: EventCategory.telemetry,
        attributes: {
          'config': _customVideoTrackConfig.encoderConfig.name,
          'configSource':
              camRebuiltFromStore ? 'store-rebuild' : 'custom-track',
          'facingMode': _customVideoTrackConfig.facingMode.name,
          'multiStream': _customVideoTrackConfig.multiStream,
          'maxLayer': _customVideoTrackConfig.maxLayer,
          'bitrateMode': _customVideoTrackConfig.bitrateMode.name,
          'requestedCodec': _customVideoTrackConfig.codec.name,
        },
      );

      final VideoCodec rawDesiredCodec = customTrack.codec;
      final bool shouldRemoteFallback = _codecSwitchEnabled &&
          _unsupportedCodecs.isNotEmpty &&
          rawDesiredCodec != VideoCodec.VP8;

      if (shouldRemoteFallback) {
        final VideoCodec previousCodec = _customVideoTrackConfig.codec;

        final VideoCodec unsupportedCodec = _unsupportedCodecs.first;

        final String? participantId = _codecChangeParticipantId;

        _codecChangeParticipantId = null;

        //R8: only the live track is downgraded here — the store's codec is
        //committed from the producer's actual RTP parameters after produce
        //succeeds (see the local 'webcam' producer handler).
        customTrack.codec = VideoCodec.VP8;

        final Participant? causedBy =
            participantId != null ? participants[participantId] : null;

        SdkTracer.shared.traceEvent(
          spanName: 'Fallback to VP8 Codec',
          parentScope: enableWebcamScope,
          attributes: {
            "reason": causedBy != null
                ? "Due to Participant: ${causedBy.displayName}"
                    "($participantId) doesn't support ${unsupportedCodec.parseToString()} Codec."
                : "Due to one of the participants doesn't support "
                    "${unsupportedCodec.parseToString()} Codec.",
          },
          category: EventCategory.telemetry,
          component: ComponentCategory.media,
        );

        _eventEmitter.emit(
          'codec-changed',
          CodecChangeInfo(
            unsupportedRemoteCodec: unsupportedCodec,
            currentCodec: VideoCodec.VP8,
            previousCodec: previousCodec,
            kind: 'video',
            causedBy: causedBy,
          ),
        );

        SdkTracer.shared.traceEvent(
          spanName: 'Emitting CODEC_CHANGED Event',
          attributes: {
            'unsupportedRemoteCodec': unsupportedCodec.parseToString(),
            'currentCodec': VideoCodec.VP8.parseToString(),
            'previousCodec': previousCodec.parseToString(),
            'causedBy': causedBy?.displayName ?? 'unknown',
            'kind': 'video'
          },
          category: EventCategory.telemetry,
          component: ComponentCategory.media,
        );
      }

      VideoCodec desiredCodec = customTrack.codec;

      if (_device != null) {
        final codecs = _device!.rtpCapabilities.codecs;

        final vp8Codec = codecs.firstWhereOrNull(
          (c) => c.mimeType.toLowerCase() == 'video/vp8',
        );

        RtpCodecCapability? selectedCodec;
        final String? configMime = _mimeToVideoCodec.entries
            .firstWhereOrNull((e) => e.value == desiredCodec)
            ?.key;

        if (configMime != null) {
          selectedCodec = codecs.firstWhereOrNull((c) {
            final matchMime = c.mimeType.toLowerCase() == configMime;
            final matchProfile = desiredCodec != VideoCodec.H264 ||
                c.parameters['profile-level-id'] == '42e01f';
            return matchMime && matchProfile;
          });

          // If not found (profile-level-id missing or different), fall back to any H264
          if (selectedCodec == null && desiredCodec == VideoCodec.H264) {
            selectedCodec = codecs.firstWhereOrNull(
              (c) => c.mimeType.toLowerCase() == configMime,
            );
          }

          if (selectedCodec == null) {
            _eventEmitter.emit("error", VideoSDKErrors[3025]);

            selectedCodec = vp8Codec;
            customTrack.codec = VideoCodec.VP8;
          } else {
            if (customTrack.multiStream &&
                (desiredCodec == VideoCodec.VP9 ||
                    desiredCodec == VideoCodec.AV1 ||
                    desiredCodec == VideoCodec.H264)) {
              //Fire only when the app supplied the track on this call —
              //store rebuilds must not re-emit the same downgrade warning
              //on every camera toggle (§5.4: 3009 semantics).
              if (!camRebuiltFromStore) {
                _eventEmitter.emit("error", VideoSDKErrors[3026]);
              }
              // Only the live track reflects the downgrade for this publish
              // attempt — _customVideoTrackConfig keeps the requested
              // multiStream intent so it comes back automatically once the
              // codec allows simulcast again (see rule R11 in the
              // media-config-store design notes).
              customTrack.multiStream = false;
            }
          }
        } else {
          selectedCodec = vp8Codec;
          customTrack.codec = VideoCodec.VP8;
        }

        if (selectedCodec == null) {
          SdkTracer.shared.endSpan(
            _internalScope,
            category: EventCategory.error,
            success: false,
            message:
                'Error in enableCam() -> No supported video codec advertised by device (VP8 unavailable)',
          );

          SdkTracer.shared.endSpan(
            enableWebcamScope,
            category: EventCategory.error,
            success: false,
            message:
                'Error in enableCam() -> No supported video codec advertised by device (VP8 unavailable)',
          );

          _eventEmitter.emit("error", VideoSDKErrors[3025]);

          customTrack.dispose();
          _cameraInProgress = false;
          return;
        }

        codec = selectedCodec;
      } else {
        SdkTracer.shared.endSpan(
          _internalScope,
          category: EventCategory.error,
          success: false,
          message: 'Error in enableCam() -> Transport is not setup',
        );

        SdkTracer.shared.endSpan(
          enableWebcamScope,
          category: EventCategory.error,
          success: false,
          message: 'Error in enableCam() -> Device not found',
        );

        _eventEmitter.emit("error", VideoSDKErrors[3011]);

        if (customTrack != null) {
          customTrack.dispose();
        }
        _cameraInProgress = false;
        return;
      }

      videoStream = customTrack.mediaStream;

      track = videoStream.getVideoTracks().first;

      // check browser is Firefox or not
      bool isFirefox =
          deviceInfo['browserUserAgent']?['browser']?['name'] == "Firefox";
      List<RtpEncodingParameters> encodings =
          SdkCapabilities.computeVideoEncodings(
              false,
              customVideotrackConfigMap[customTrack.videoEncoderConfig]![
                  "width"],
              customVideotrackConfigMap[customTrack.videoEncoderConfig]![
                  "height"],
              {"simulcast": isFirefox ? false : customTrack.multiStream},
              customTrack.maxLayer,
              customTrack.bitrateMode);

      // no need to reverse the order
      // encodings = encodings.reversed.toList();

      Map<String, dynamic> appData = {
        'source': 'webcam',
        'width':
            customVideotrackConfigMap[customTrack.videoEncoderConfig]!["width"],
        'height': customVideotrackConfigMap[customTrack.videoEncoderConfig]![
            "height"],
      };
      appData['encodings'] = [];

      for (var encoding in encodings) {
        appData['encodings'].add(encoding.toMap());
      }

      try {
        SdkTracer.shared.endSpan(
          _internalScope,
          success: true,
          message: 'Video stream configurations generated',
        );
      } catch (_) {}

      try {
        _internalScope = SdkTracer.shared.startSpan(
          spanName: 'Starting Video Stream transmission',
          attributes: {
            'width': appData['width'],
            'height': appData['height'],
            'simulcast': customTrack.multiStream,
          },
          parentSpan: enableWebcamScope,
          component: ComponentCategory.media,
        );
      } catch (_) {}

      //Last intent check before the camera actually goes live. The callers
      //that check _camEnabled themselves do it before calling in, and this
      //method then awaits getVideoDevices() and the track build — a
      //disableCam() landing in that gap would otherwise be overrun and the
      //camera would come back on after the user turned it off. Skipped when
      //setIntent is set, because that call is the one establishing the intent
      //and _camEnabled is still false until below.
      if (!setIntent && !_camEnabled) {
        SdkTracer.shared.endSpan(
          _internalScope,
          success: true,
          message:
              'Video Stream transmission aborted : camera was turned off while the track was being prepared',
        );

        SdkTracer.shared.endSpan(
          enableWebcamScope,
          success: true,
          message: 'Camera enable aborted : camera was turned off by the user',
        );

        await customTrack.dispose();
        _cameraInProgress = false;
        return;
      }

      if (_sendTransport != null) {
        _sendTransport!.produce(
          track: track,
          codecOptions: ProducerCodecOptions(
            videoGoogleStartBitrate: 1000,
          ),
          encodings: encodings,
          stream: videoStream,
          appData: appData,
          source: 'webcam',
          codec: codec,
          sourceContext: enableWebcamScope,
        );

        //Armed only here — see the note on recycleFrom above. After the
        //produce rather than before it, so a produce that throws leaves it
        //clear; still ahead of any read, since produce() only queues the task
        //and _addProducer cannot run until this turn ends.
        _codecRecyclePending = recycleFrom;
      } else {
        SdkTracer.shared.endSpan(
          _internalScope,
          category: EventCategory.error,
          success: false,
          message:
              'Error in enableCam() -> Tried to enable webcam while room is in a connecting state',
        );

        SdkTracer.shared.endSpan(
          enableWebcamScope,
          category: EventCategory.error,
          success: false,
          message: VideoSDKErrors[3011]!['message']!,
          dashboardLog: true,
          attributes: {
            'error':
                'Error in enableCam() -> Tried to enable webcam while room is in a connecting state.',
          },
        );

        _eventEmitter.emit("error", VideoSDKErrors[3011]);
        log("An error occurred in enableCam(): VIDEOSDK ERROR :: ${VideoSDKErrors[3011]?['code']}  :: ${VideoSDKErrors[3011]?['name']} :: ${VideoSDKErrors[3011]?['message']}");
        if (customTrack != null) {
          customTrack.dispose();
        }
        if (videoStream != null) {
          await videoStream.dispose();
        }
        _cameraInProgress = false;
        return;
      }

      SdkTracer.shared.endSpan(
        _internalScope,
        success: true,
        message: 'Video Stream transmission started successfully',
      );

      SdkTracer.shared.endSpan(
        enableWebcamScope,
        success: true,
        message: 'Camera turned on successfully',
      );

      _camState = true;
      if (setIntent) {
        _camEnabled = true;
      }
      _cameraInProgress = true;
      _setSelectedCamId(customTrack: customTrack);
    } catch (error) {
      //
      _cameraInProgress = false;

      if (videoStream != null) {
        await videoStream.dispose();
      }

      SdkTracer.shared.endSpan(
        _internalScope,
        category: EventCategory.error,
        success: false,
        message: 'Error in enableCam() -> ${error.toString()}',
      );

      SdkTracer.shared.endSpan(
        enableWebcamScope,
        category: EventCategory.error,
        success: false,
        message: 'Error while enabling video in enableCam()',
        dashboardLog: true,
        attributes: {
          'error': 'Error in enableCam() -> ${error.toString()}',
        },
      );

      _eventEmitter.emit("error", VideoSDKErrors[3011]);
    }
  }

  Future<void> _setSelectedCamId({CustomTrack? customTrack}) async {
    try {
      MediaStreamTrack? track = customTrack?.mediaStream.getVideoTracks().first;
      if (!kIsWeb) {
        //For devices other than web directly getting deviceId on customTrack
        if (track != null && track.getSettings().containsKey("deviceId")) {
          VideoDeviceInfo? device = videoDevices?.firstWhereOrNull(
            (device) => device.deviceId == track.getSettings()["deviceId"],
          );
          _selectedVideoInput = device;
        }
      } else {
        if (track != null && track.label != null) {
          VideoDeviceInfo? device = videoDevices?.firstWhereOrNull(
            (device) => device.label == track.label,
          );
          _selectedVideoInput = device;
        }
      }
    } catch (_) {}
  }

  /// Disables the WebCam device for the local participant.
  ///
  /// - When the WebCam is successfully disabled, a [Events.streamDisabled] event
  /// is emitted with the corresponding video [Stream] object in the event
  /// handler, inside the associated [Participant] object.
  ///
  /// ## Events associated with disableCam()
  ///
  /// - [Events.streamDisabled] with the disabled video [Stream]
  ///
  /// ### **Example**
  /// ```dart
  /// // Disable WebCam
  /// await room.disableCam();
  ///
  /// room.on(Events.streamDisabled, (event) {
  ///   print('Camera stream disabled: ${event.stream.id}');
  /// });
  ///
  /// // Disable WebCam from a button
  /// ElevatedButton(
  ///   onPressed: () async {
  ///     await room.disableCam();
  ///   },
  ///   child: Text('Turn Off Camera'),
  /// )
  /// ```

  Future<void> disableCam() async {
    if (!_ensureJoined("disableCam")) return;
    await _disableCamImpl(clearIntent: true);
  }

  void _addUnsupportedCodecs(List<String>? raw) {
    if (!_codecSwitchEnabled || raw == null) return;

    for (final entry in raw) {
      final VideoCodec? normalized = _mimeToVideoCodec[entry.toLowerCase()];
      if (normalized == null) continue;
      _unsupportedCodecs.add(normalized);
    }
  }

  Future<void> _sendChangeModeRequest(Mode requestedMode) async {
    final dynamic res = await _webSocket!
        .sendRequest('changeMode', {"mode": requestedMode.parseToString()});
    if (res is Map) {
      _addUnsupportedCodecs(res['unsupportedCodecs']?.cast<String>());
    }
  }

  Future<void> _changeWebcamCodec(VideoCodec currentCodec) async {
    if (_codecRecycleInProgress) return;
    if (_codecRecycleFrom == currentCodec) return;

    if (!_camEnabled) return;

    _codecRecycleInProgress = true;

    try {
      final CustomVideoTrackConfig encoderConfig =
          _customVideoTrackConfig.encoderConfig;
      final bool multiStream = _customVideoTrackConfig.multiStream;
      final BitrateMode bitrateMode = _customVideoTrackConfig.bitrateMode;
      final int maxLayer = _customVideoTrackConfig.maxLayer;
      final String? cameraId = _customVideoTrackConfig.cameraId;
      final FacingMode facingMode = _customVideoTrackConfig.facingMode;

      final CustomTrack? newTrack = await VideoSDK.createCameraVideoTrack(
        cameraId: cameraId,
        encoderConfig: encoderConfig,
        multiStream: multiStream,
        bitrateMode: bitrateMode,
        maxLayer: maxLayer,
        codec: currentCodec,
        facingMode: facingMode,
      );

      if (newTrack == null) {
        return;
      }

      if (!_camEnabled) {
        newTrack.dispose();
        return;
      }

      await _disableCamImpl();

      if (!_camEnabled) {
        newTrack.dispose();
        return;
      }

      await _enableCamImpl(customTrack: newTrack, recycleFrom: currentCodec);
    } finally {
      _codecRecycleInProgress = false;
    }
  }

  //
  Future<void> _disableCamImpl(
      {SpanScope? parentSpan, bool clearIntent = false}) async {
    SpanScope? disableWebcamSpan = SdkTracer.shared.startSpan(
      spanName: "Disabling Webcam",
      parentSpan: parentSpan,
      component: ComponentCategory.media,
      category:
          parentSpan == null ? EventCategory.telemetry : EventCategory.debug,
    );

    if (_webSocket == null) {
      SdkTracer.shared.to(OutputTarget.toConsole).endSpan(
            disableWebcamSpan,
            category: EventCategory.error,
            success: false,
            message: VideoSDKErrors[3022]!['message']!,
          );

      //Silent: disableCam() already reported this to the app, and the internal
      //callers (changeCam, codec recycle, reconnect rebuild) must not raise one.
      return;
    }

    if (clearIntent) {
      _camEnabled = false;
    }

    //Any camera teardown invalidates a recycle still waiting on a producer.
    //_enableCamImpl arms it at its produce() call, after the disable both
    //recycle paths run first, so this only ever drops a pending whose
    //producer is no longer coming.
    _codecRecyclePending = null;

    if (_cameraProducer == null) {
      SdkTracer.shared.endSpan(
        disableWebcamSpan,
        success: false,
        message:
            "Attempted to call disableCam() while WebCam is already disabled.",
        dashboardLog: true,
        attributes: {
          'error': "Error in disableCam() -> Camera is already disabled.",
        },
        category: EventCategory.error,
      );
      //log("An error occurred in disableCam(): Attempted to call disableCam() while the webcam is already disabled");
      return;
    }

    String? cameraId = _cameraProducer?.id;
    _cameraInProgress = true;

    SpanScope? internalSpan = SdkTracer.shared.startSpan(
      spanName: "Disposing Video Track",
      parentSpan: disableWebcamSpan,
      component: ComponentCategory.media,
    );

    _removeProducer(
        _cameraProducer!, _ProducerType.cameraProducer, disableWebcamSpan);
    _cameraProducer = null;

    //Cleared here, not after the closeProducer round-trip below: the producer
    //is already gone locally, so a socket error must not leave the camera
    //reading as live. _disableMic clears _micState in the same position, and
    //changeCam()/camEnabled both gate on this flag.
    _camState = false;

    SdkTracer.shared.endSpan(
      internalSpan,
      message: "Video track disposed successfully",
    );

    SpanScope? transSpan;
    try {
      transSpan = SdkTracer.shared.startSpan(
        spanName: "Stopping Video Stream transmission",
        parentSpan: disableWebcamSpan,
        component: ComponentCategory.media,
      );

      await _webSocket!.sendRequest('closeProducer', {
        'producerId': cameraId,
      });

      SdkTracer.shared.endSpan(
        transSpan,
        message: "Video Stream transmission stopped successfully",
      );

      SdkTracer.shared.endSpan(
        disableWebcamSpan,
        message: "Camera disabled successfully",
      );
    } catch (error) {
      SdkTracer.shared.endSpan(
        transSpan,
        success: false,
        category: EventCategory.error,
        message:
            "Failed to stop Video Stream transmission: ${error.toString()}",
      );

      SdkTracer.shared.endSpan(disableWebcamSpan,
          success: false,
          message: "Error encountered while disabling the Camera",
          dashboardLog: true,
          category: EventCategory.error,
          attributes: {
            "error": "Error in disableCam() -> ${error.toString()}"
          });
    } finally {
      _cameraInProgress = false;
    }
  }

  /// Retrieves all available screens and open application windows
  /// that can be shared.
  ///
  /// - This method is supported only on desktop platforms
  /// (Windows, macOS, and Linux).
  ///
  /// ### Returns
  ///
  /// - A [Future] that resolves to a list of [DesktopCapturerSource]
  ///   objects representing available screens and windows.
  ///
  /// ### **Example**
  /// ```dart
  /// final sources = await meeting.getScreenShareSources();
  /// print('Available sources: $sources');
  /// ```
  Future<List<DesktopCapturerSource>> getScreenShareSources() =>
      _getScreenShareSources();

  Future<List<DesktopCapturerSource>> _getScreenShareSources() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS)) {
      List<DesktopCapturerSource> sources = await desktopCapturer
          .getSources(types: [SourceType.Screen, SourceType.Window]);

      sources.asMap().forEach((key, value) {
        log("Screenshare source name:${value.name}");
      });

      return sources;
    } else {
      throw UnsupportedError(
          'The getScreenShareSources() method is only supported for desktop apps.');
    }
  }

  /// Enables screen sharing for the local participant.
  ///
  /// - When screen sharing is successfully started, a [Events.streamEnabled]
  /// event is emitted with the corresponding screen-share [Stream] object
  /// in the event handler, inside the associated [Participant] object.
  ///
  /// - Additionally, a [Events.presenterChanged] event is emitted with the
  /// `presenterId` of the participant who started presenting.
  ///
  /// ### **Parameters**
  ///
  /// - [enableAudio] *(optional)*:
  ///   Specifies whether system audio should be shared along with the screen,
  ///   if supported by the platform.
  ///
  /// - [source] *(optional)*:
  ///   A [DesktopCapturerSource] representing the selected screen or application
  ///   window to share.
  ///   This parameter is applicable only for desktop platforms. If not provided,
  ///   the default screen source will be used.
  ///
  /// ## Events associated with enableScreenShare()
  ///
  /// - [Events.streamEnabled] with the screen-share [Stream]
  /// - [Events.presenterChanged] with the `presenterId`
  ///
  /// ### **Example**
  /// ```dart
  /// // Enable screen sharing with default screen
  /// await meeting.enableScreenShare();
  ///
  /// // Enable screen sharing with a selected source (desktop)
  /// final sources = await meeting.getScreenShareSources();
  /// await meeting.enableScreenShare(source: sources.first);
  ///
  /// meeting.on(Events.presenterChanged, (event) {
  ///   print('Presenter changed: ${event.presenterId}');
  /// });
  /// ```
  Future<void> enableScreenShare({
    bool? enableAudio,
    DesktopCapturerSource? source,
  }) async {
    if (!_ensureJoined("enableScreenShare")) return;
    await _enableScreenShare(enableAudio: enableAudio, source: source);
  }

  Future<void> _enableScreenShare({
    bool? enableAudio,
    DesktopCapturerSource? source,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      if (e2eeEnabled) {
        enableAudio = false;
      }
      await Helper.setScreenShareAudio(enableAudio ?? false);
    }
    await enableShare(source);
  }

  //
  ///@nodoc

  Future<void> enableShare(DesktopCapturerSource? source,
      {bool iosPermissionGiven = false}) async {
    //Silent, like every other internal not-joined branch: there is no meeting
    //to present to, and starting capture here would open a picker for nothing.
    //Note this stays true during a reconnect, which is the case that matters.
    if (!_joined || _closed || _webSocket == null) return;

    SpanScope? enableShareSpan;
    enableShareSpan = SdkTracer.shared.startSpan(
      spanName: "Enabling Screen Share without Custom Screen Sharing Track",
      component: ComponentCategory.media,
      category: EventCategory.telemetry,
    );

    if (_screenShareInProgress) {
      //  log("An error occurred in enableScreenShare() : Attempted to call enableScreenShare()  while the screenshare is already enabled");
      SdkTracer.shared.endSpan(
        enableShareSpan,
        message:
            "Attempted to call enableScreenShare()  while the screen share is already enabled",
        dashboardLog: true,
        category: EventCategory.error,
        success: false,
        attributes: {
          "error":
              "Error in enableScreenShare() -> Screen Share is already enabled"
        },
      );
      return;
    }

    if (source == null) {
      if (!kIsWeb && (Platform.isWindows || Platform.isMacOS)) {
        var sources =
            await desktopCapturer.getSources(types: [SourceType.Screen]);

        _selectedScreenSource = sources.first;
      }
    } else {
      _selectedScreenSource = source;
    }

    if (_isMobilePlatform()) {
      if (Platform.isIOS && !iosPermissionGiven) {
        VideoSDK.requestIOSScreenSharePermission();
        return;
      }

      if (Platform.isAndroid) {
        SpanScope? enableForegroundTask;
        try {
          bool androidPermission = await Helper.requestCapturePermission();

          if (!androidPermission) {
            if (enableShareSpan != null) {
              SdkTracer.shared.endSpan(
                enableShareSpan,
                message: VideoSDKErrors[3014]!['message']!,
                success: false,
                dashboardLog: true,
                category: EventCategory.error,
                attributes: {
                  'error':
                      "Error in enableScreenShare()  -> Screenshare Permission denied",
                },
              );
            }
            _eventEmitter.emit("error", VideoSDKErrors[3014]);
            //   log("An error occurred in enableScreenShare()  : VIDEOSDK ERROR :: ${VideoSDKErrors[3014]?['code']}  :: ${VideoSDKErrors[3014]?['name']} :: ${VideoSDKErrors[3014]?['message']}");
            return;
          }

          enableForegroundTask = SdkTracer.shared.startSpan(
              spanName: "Enable Share Screen Foreground Task Starting",
              parentSpan: enableShareSpan,
              component: ComponentCategory.media);

          await FlutterForegroundTask.startService(
              notificationTitle: _notification.title,
              notificationText: _notification.message,
              callback: null);
          SdkTracer.shared.endSpan(enableForegroundTask,
              message: "Enable Share Screen Foreground Task Started");
        } catch (error) {
          SdkTracer.shared.endSpan(
            enableForegroundTask,
            message:
                "Error in enableScreenShare()  -> Failed to initialize the foreground service.",
            success: false,
            category: EventCategory.error,
          );

          SdkTracer.shared.endSpan(
            enableShareSpan,
            message: VideoSDKErrors[3016]!['message']!,
            dashboardLog: true,
            success: false,
            category: EventCategory.error,
            attributes: {
              'error':
                  'Error in enableScreenShare() -> starting Foreground service',
            },
          );
          _eventEmitter.emit("error", VideoSDKErrors[3016]);
          //    log("An error occurred in enableScreenShare() : VIDEOSDK ERROR :: ${VideoSDKErrors[3016]?['code']}  :: ${VideoSDKErrors[3016]?['name']} :: ${VideoSDKErrors[3016]?['message']}");
          return;
        }
      }
    }

    //
    _screenShareInProgress = true;

    //
    MediaStream? shareStream;
    MediaStreamTrack? videoTrack;
    MediaStreamTrack? audioTrack;

    SpanScope? _internalSpan;
    SpanScope? trackSpan;
    SpanScope? producerSpan;
    SpanScope? audioProducerSpan;
    try {
      try {
        if (enableShareSpan != null) {
          _internalSpan = SdkTracer.shared.startSpan(
            spanName: "Generating configurations for Screenshare Stream",
            component: ComponentCategory.media,
            parentSpan: enableShareSpan,
          );
        }
      } catch (_) {}
      //
      RtpCodecCapability? videoCodec;

      if (_device != null) {
        videoCodec = _device!.rtpCapabilities.codecs.firstWhere(
            (RtpCodecCapability c) {
          return c.mimeType.toLowerCase() == 'video/vp9' ||
              c.mimeType.toLowerCase() == 'video/vp8';
        },
            // (RtpCodecCapability c) => c.mimeType.toLowerCase() == 'video/h264',
            orElse: () {
          //
          SdkTracer.shared.endSpan(
            _internalSpan,
            message:
                "Error in enableScreenShare() -> Desired vp9 codec+configuration is not supported",
            success: false,
            category: EventCategory.error,
          );
          SdkTracer.shared.endSpan(
            enableShareSpan,
            message: "Error in enableScreenShare() -> Coded not supported",
            success: false,
            category: EventCategory.error,
          );
          //
          throw 'desired vp9 codec+configuration is not supported';
        });
      } else {
        SdkTracer.shared.endSpan(
          _internalSpan,
          message: VideoSDKErrors[3013]!['message']!,
          success: false,
          category: EventCategory.error,
        );
        SdkTracer.shared.endSpan(
          enableShareSpan,
          message: "Enable Screenshare Failed -> Device not Found",
          success: false,
          category: EventCategory.error,
        );

        _eventEmitter.emit("error", VideoSDKErrors[3013]);

        //  log("An error occurred in enableScreenShare() : VIDEOSDK ERROR :: ${VideoSDKErrors[3013]?['code']}  :: ${VideoSDKErrors[3013]?['name']} :: ${VideoSDKErrors[3013]?['message']}");
        _screenShareInProgress = false;
        if (!kIsWeb) {
          if (Platform.isAndroid) {
            //
            FlutterForegroundTask.stopService();
          }
        }
        return;
      }

      try {
        if (_internalSpan != null) {
          SdkTracer.shared.endSpan(
            _internalSpan,
            message: 'Generated configurations for Screenshare Stream',
          );
          _internalSpan = null;
        }
      } catch (_) {}

      //
      try {
        if (enableShareSpan != null) {
          trackSpan = SdkTracer.shared.startSpan(
            spanName: "Creating Screenshare Track",
            component: ComponentCategory.media,
            parentSpan: enableShareSpan,
          );
        }
      } catch (_) {}

      shareStream = await _createShareStream(trackSpan);

      if (shareStream != null) {
        //
        videoTrack = shareStream.getVideoTracks().first;
        if (shareStream.getAudioTracks().isNotEmpty) {
          audioTrack = shareStream.getAudioTracks().first;
        }

        if (trackSpan != null) {
          SdkTracer.shared.endSpan(
            trackSpan,
            message:
                'Track Generated with videoTrack ${videoTrack.toString()} & audioTrack ${audioTrack != null ? audioTrack.toString() : 'No audio'}',
          );
          trackSpan = null;
        }

        //
        _screenShareInProgress = true;

        if (enableShareSpan != null) {
          producerSpan = SdkTracer.shared.startSpan(
            spanName: "Starting Screen Share Stream transmission",
            parentSpan: enableShareSpan,
            component: ComponentCategory.media,
          );
        }

        //
        if (_sendTransport != null) {
          _sendTransport!.produce(
            track: videoTrack,
            codecOptions: ProducerCodecOptions(
              videoGoogleStartBitrate: 1000,
            ),
            stream: shareStream,
            appData: {'share': true},
            source: 'screen',
            sourceContext: enableShareSpan,
            codec: videoCodec,
          );
        } else {
          SdkTracer.shared.endSpan(producerSpan,
              message: VideoSDKErrors[3013]!['message']!,
              success: false,
              dashboardLog: true,
              category: EventCategory.error,
              attributes: {
                'error':
                    "Error in enableScreenShare() -> Tried to enable screen share while room is in a connecting state.",
              });
          producerSpan = null;

          _eventEmitter.emit("error", VideoSDKErrors[3013]);

          //    log("An error occurred in enableScreenShare() : VIDEOSDK ERROR :: ${VideoSDKErrors[3013]?['code']}  :: ${VideoSDKErrors[3013]?['name']} :: ${VideoSDKErrors[3013]?['message']}");
          if (shareStream != null) {
            await shareStream.dispose();
          }
          _screenShareInProgress = false;
          if (!kIsWeb) {
            if (Platform.isAndroid) {
              //
              FlutterForegroundTask.stopService();
            }
          }
          return;
        }

        try {
          if (producerSpan != null) {
            SdkTracer.shared.endSpan(
              producerSpan,
              message: "Screen share transmission started successfully",
            );

            producerSpan = null;
          }
        } catch (_) {}

        if (audioTrack != null) {
          if (enableShareSpan != null) {
            audioProducerSpan = SdkTracer.shared.startSpan(
              spanName: "Starting Screen Share Audio Stream transmission",
              component: ComponentCategory.media,
              parentSpan: enableShareSpan,
            );
          }

          if (_sendTransport != null) {
            _sendTransport!.produce(
                track: audioTrack,
                codecOptions: ProducerCodecOptions(
                  opusStereo: 1,
                  opusDtx: 1,
                ),
                stream: shareStream,
                appData: {'share': true},
                source: 'screen-audio',
                sourceContext: enableShareSpan);
          } else {
            try {
              if (audioProducerSpan != null) {
                SdkTracer.shared.endSpan(audioProducerSpan,
                    message: VideoSDKErrors[3013]!['message']!,
                    success: false,
                    dashboardLog: true,
                    category: EventCategory.error,
                    attributes: {
                      'error':
                          "Error in enableScreenShare() -> Tried to enable screen share audio while room is in a connecting state.",
                    });

                audioProducerSpan = null;
              }
            } catch (_) {}

            _eventEmitter.emit("error", VideoSDKErrors[3013]);

            //   log("An error occurred in enableScreenShare() : VIDEOSDK ERROR :: ${VideoSDKErrors[3013]?['code']}  :: ${VideoSDKErrors[3013]?['name']} :: ${VideoSDKErrors[3013]?['message']}");

            if (shareStream != null) {
              await shareStream.dispose();
            }
            if (!kIsWeb) {
              if (Platform.isAndroid) {
                //
                FlutterForegroundTask.stopService();
              }
            }
            _screenShareInProgress = false;
            return;
          }

          if (audioProducerSpan != null) {
            SdkTracer.shared.endSpan(
              audioProducerSpan,
              message:
                  "Screen Share Audio Stream transmission started successfully",
            );
            audioProducerSpan = null;
          }
        }

        SdkTracer.shared.endSpan(
          enableShareSpan,
          message: "Screen Share enabled successfully",
        );
        enableShareSpan = null;
      } else {
        SdkTracer.shared.endSpan(
          enableShareSpan,
          message: VideoSDKErrors[3013]!['message']!,
          dashboardLog: true,
          success: false,
          category: EventCategory.error,
          attributes: {
            'error': "Error in enableScreenShare() -> Share Stream is empty",
          },
        );

        _eventEmitter.emit("error", VideoSDKErrors[3013]);

        ///   log("An error occurred in enableScreenShare() : VIDEOSDK ERROR :: ${VideoSDKErrors[3013]?['code']}  :: ${VideoSDKErrors[3013]?['name']} :: ${VideoSDKErrors[3013]?['message']}");
        if (!kIsWeb) {
          if (Platform.isAndroid) {
            //
            FlutterForegroundTask.stopService();
          }
        }
        _screenShareInProgress = false;
        return;
      }
    } catch (error) {
      //
      _screenShareInProgress = false;

      if (!kIsWeb) {
        if (Platform.isAndroid) {
          //
          FlutterForegroundTask.stopService();
        }
      }

      if (shareStream != null) {
        await shareStream.dispose();
      }

      if (error.toString().contains("NotAllowedError")) {
        _eventEmitter.emit("error", VideoSDKErrors[3014]);
        log("An error occurred in enableScreenShare() : VIDEOSDK ERROR :: ${VideoSDKErrors[3014]?['code']}  :: ${VideoSDKErrors[3014]?['name']} :: ${VideoSDKErrors[3014]?['message']}");
      } else {
        _eventEmitter.emit("error", VideoSDKErrors[3013]);
        log("An error occurred in enableScreenShare() : VIDEOSDK ERROR :: ${VideoSDKErrors[3013]?['code']}  :: ${VideoSDKErrors[3013]?['name']} :: ${VideoSDKErrors[3013]?['message']}");
      }

      if (trackSpan != null) {
        SdkTracer.shared.endSpan(
          trackSpan,
          message:
              'Error in enableScreenShare() -> while creating screenshare track',
          success: false,
          category: EventCategory.error,
        );
      }
      if (producerSpan != null) {
        SdkTracer.shared.endSpan(
          producerSpan,
          message: 'Error in enableScreenShare() -> while stream transmission',
          success: false,
          category: EventCategory.error,
        );
      }

      if (audioProducerSpan != null) {
        SdkTracer.shared.endSpan(
          audioProducerSpan,
          message: 'Error in enableScreenShare() -> audio stream transmission',
          success: false,
          category: EventCategory.error,
        );
      }

      if (enableShareSpan != null) {
        if (error.toString().contains("NotAllowedError")) {
          SdkTracer.shared.endSpan(
            enableShareSpan,
            message: VideoSDKErrors[3014]!['message']!,
            success: false,
            dashboardLog: true,
            category: EventCategory.error,
            attributes: {
              'error': "Error in enableScreenShare()  -> ${error.toString()}",
            },
          );
        } else {
          SdkTracer.shared.endSpan(
            enableShareSpan,
            message: "Screenshare stream could not be produced",
            success: false,
            dashboardLog: true,
            category: EventCategory.error,
            attributes: {
              'error': "Error in enableScreenShare()  -> ${error.toString()}",
            },
          );
        }
      }
    }
  }

  /// Disables screen sharing for the local participant.
  ///
  /// - When screen sharing is successfully stopped, a [Events.streamDisabled]
  /// event is emitted with the corresponding screen-share [Stream] object
  /// in the event handler, inside the associated [Participant] object.
  ///
  /// - Additionally, a [Events.presenterChanged] event is emitted with a `null`
  /// value, indicating that there is no active presenter.
  ///
  /// ## Events associated with disableScreenShare()
  ///
  /// - [Events.streamDisabled] with the disabled screen-share [Stream]
  /// - [Events.presenterChanged] with `null`
  ///
  /// ### **Example**
  /// ```dart
  /// // Disable screen sharing
  /// await meeting.disableScreenShare();
  ///
  /// meeting.on(Events.presenterChanged, (event) {
  ///   print('Screen sharing stopped');
  /// });
  /// ```
  Future<void> disableScreenShare() async {
    if (!_ensureJoined("disableScreenShare")) {
      return;
    }
    await _disableScreenShare();
  }

  //
  ///@nodoc
  //The counterpart to enableShare(): the SDK's own EventChannel calls this
  //when the user stops the broadcast from the system UI. Ungated for the same
  //reason — it is not an app call, and refusing it would leave the meeting
  //believing it is still presenting.
  Future<void> disableShare() => _disableScreenShare();
  //
  Future<void> _disableScreenShare() async {
    SpanScope? disableShareSpan;
    disableShareSpan = SdkTracer.shared.startSpan(
      spanName: "Disabling Screen Share",
      component: ComponentCategory.media,
      category: EventCategory.telemetry,
    );
    if (_webSocket == null) {
      SdkTracer.shared.to(OutputTarget.toConsole).endSpan(
            disableShareSpan,
            category: EventCategory.error,
            success: false,
            message: VideoSDKErrors[3022]!['message']!,
          );
      return;
    }

    if (_screenshareProducer == null) {
      SdkTracer.shared.endSpan(
        disableShareSpan,
        message:
            "Attempted to call disableShare() while the screen share is already disabled",
        success: false,
        dashboardLog: true,
        category: EventCategory.error,
        attributes: {
          'error':
              "Error in disableScreenShare() -> Screen Share is already disabled"
        },
      );
      //   log("An error occurred in disableScreenShare(): Attempted to call disableScreenShare() while the screenshare is already disabled");
      return;
    }

    _screenShareInProgress = true;

    SpanScope? disposeTrackSpan;
    SpanScope? disposeAudioTrackSpan;
    SpanScope? transSpan;

    String? screenShareAudioId; // Declare at function scope

    try {
      // Dispose screenshare video track
      disposeTrackSpan = SdkTracer.shared.startSpan(
        spanName: "Disposing Screenshare Track",
        parentSpan: disableShareSpan,
        component: ComponentCategory.media,
      );

      String screenShareId = _screenshareProducer!.id;
      _removeProducer(_screenshareProducer!, _ProducerType.screenshareProducer,
          disableShareSpan);
      _screenshareProducer = null;

      SdkTracer.shared.endSpan(
        disposeTrackSpan,
        message: "Screenshare track disposed successfully",
      );
      disposeTrackSpan = null;

      // Dispose screenshare audio track if exists
      if (_screenShareAudioProducer != null) {
        disposeAudioTrackSpan = SdkTracer.shared.startSpan(
          spanName: "Disposing Screenshare Audio Track",
          parentSpan: disableShareSpan,
          component: ComponentCategory.media,
        );

        screenShareAudioId = _screenShareAudioProducer!.id;
        _removeProducer(_screenShareAudioProducer!,
            _ProducerType.screenShareAudioProducer, disableShareSpan);
        _screenShareAudioProducer = null;

        SdkTracer.shared.endSpan(
          disposeAudioTrackSpan,
          message: "Screenshare Audio Track disposed successfully",
        );
        disposeAudioTrackSpan = null;
      }

      // Stop transmission
      transSpan = SdkTracer.shared.startSpan(
        spanName: "Stopping Screenshare Stream transmission",
        parentSpan: disableShareSpan,
        component: ComponentCategory.media,
      );

      if (_webSocket != null) {
        await _webSocket!.sendRequest('closeProducer', {
          'producerId': screenShareId,
        });

        if (screenShareAudioId != null) {
          SdkTracer.shared.traceEvent(
            spanName: "Stopping Screenshare Audio Stream transmission",
            parentScope: transSpan,
            component: ComponentCategory.media,
          );

          await _webSocket!.sendRequest('closeProducer', {
            'producerId': screenShareAudioId,
          });
        }
      }

      SdkTracer.shared.endSpan(
        transSpan,
        message: screenShareAudioId != null
            ? "Screenshare Stream and Screenshare Audio Stream transmission stopped successfully"
            : "Screenshare Stream transmission stopped successfully",
      );
      transSpan = null;

      SdkTracer.shared.endSpan(
        disableShareSpan,
        message: "Screen share disabled successfully",
      );
      disableShareSpan = null;
    } catch (error) {
      if (disposeTrackSpan != null) {
        SdkTracer.shared.endSpan(
          disposeTrackSpan,
          message:
              "Error in disableScreenShare -> Failed to dispose Screenshare track",
          success: false,
          category: EventCategory.error,
        );
      }

      if (disposeAudioTrackSpan != null) {
        SdkTracer.shared.endSpan(
          disposeAudioTrackSpan,
          message:
              "Error in disableScreenShare -> Failed to dispose Screenshare Audio track",
          success: false,
          category: EventCategory.error,
        );
      }

      if (transSpan != null) {
        SdkTracer.shared.endSpan(
          transSpan,
          message:
              "Error in disableScreenShare -> while disposing track ${error.toString()}",
          success: false,
          category: EventCategory.error,
        );
      }

      if (disableShareSpan != null) {
        SdkTracer.shared.endSpan(
          disableShareSpan,
          message: "Error encountered while disabling Screen Share",
          success: false,
          dashboardLog: true,
          category: EventCategory.error,
          attributes: {
            'error': "Error in disableScreenShare() -> ${error.toString()}",
          },
        );
      }

      //    log("An error occurred in disableScreenShare(): Something went wrong, and the screenshare could not be disabled. Please try again.");
    } finally {
      _closeForegroundService();
      _screenShareInProgress = false;
    }
  }

  Future<void> _participantPinStateChange(
      String peerId, ParticipantPinState pinState) async {
    //Computed before the gate so a rejected unpin is reported as
    //participant.unpin() rather than participant.pin().
    final bool isPin = pinState.toJson()['pin'] == true;

    if (!_ensureJoined(isPin ? "participant.pin" : "participant.unpin")) return;

    SpanScope? pinStateChangeSpan = SdkTracer.shared.startSpan(
      spanName: isPin ? "Pin State Requested" : "Unpin State Requested",
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
      attributes: {
        'peerId': peerId,
        'state': pinState.toJson().toString(),
      },
    );

    try {
      await _webSocket!.sendRequest(
          'pinStateChanged', {'peerId': peerId, 'state': pinState.toJson()});

      SdkTracer.shared.endSpan(
        pinStateChangeSpan,
        message: "Pin state change request sent successfully",
      );
    } catch (error) {
      SdkTracer.shared.endSpan(
        pinStateChangeSpan,
        message:
            "Error in ${isPin ? "pin()" : "unpin()"}. -> ${error.toString()}",
        success: false,
        category: EventCategory.error,
        attributes: {
          'error': error.toString(),
        },
      );

      log("Error Setting Pin State $error");
    }
  }

  /// Switches the local participant from the current meeting to another meeting
  /// seamlessly.
  ///
  /// - This method allows transitioning to a new meeting without manually
  /// disconnecting from the current one and reconnecting again. The SDK
  /// handles the cleanup and reinitialization internally.
  ///
  /// ### **Parameters**
  ///
  /// - [meetingId]:
  ///   The ID of the destination meeting to switch to.
  ///
  /// - [token] *(optional)*:
  ///   Authentication token for the destination meeting.
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Switch to another meeting
  /// await room.switchTo(
  ///   '<NEW_MEETING_ID>',
  ///   token: '<VIDEOSDK_TOKEN>',
  /// );
  ///
  /// ElevatedButton(
  ///   onPressed: () async {
  ///     await room.switchTo(
  ///       '<NEW_MEETING_ID>',
  ///       token: '<VIDEOSDK_TOKEN>',
  ///     );
  ///   },
  ///   child: const Text('Switch Meeting'),
  /// );
  /// ```
  Future<void> switchTo(String meetingId, {String? token}) async {
    if (!_ensureJoined("switchTo")) return;
    await _switchTo(meetingId, token: token);
  }

  // before switching to new meeting - at time of inital request
  Future<void> _switchTo(String meetingId, {String? token}) async {
    SpanScope? switchToSpan = SdkTracer.shared.startSpan(
      spanName: "Switch Meeting Requested",
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
      attributes: {
        "peer.id": localParticipantId,
        "meetingId": meetingId,
      },
    );

    try {
      var respo = await _webSocket!.sendRequest('switchToMeeting', {
        "secret": token ?? _token,
        "meetingId": meetingId,
        "participantId": localParticipantId,
      });

      log("Switched to new meeting $respo");

      SdkTracer.shared.endSpan(
        switchToSpan,
        message: "Meeting switch request sent successfully",
      );
    } catch (error) {
      SdkTracer.shared.endSpan(
        switchToSpan,
        message: "Error in switchTo() -> ${error.toString()}",
        success: false,
        category: EventCategory.error,
      );

      log("Error in switchTo() $error");
    }
  }

  ///@nodoc
  Future<void> switchingRoom(String switchingRoomId) async {
    _unsupportedCodecs.clear();
    _codecChangeParticipantId = null;
    _codecRecycleFrom = null;
    _codecRecyclePending = null;
    SpanScope? switchRoomScope;
    SpanScope? joinRequestScope;

    try {
      // Start main switching span
      switchRoomScope = SdkTracer.shared.startSpan(
        spanName: 'Switching Room',
        component: ComponentCategory.meeting,
        category: EventCategory.telemetry,
      );

      // Start child span for join request
      joinRequestScope = SdkTracer.shared.startSpan(
        spanName: 'Requesting to join switched room',
        parentSpan: switchRoomScope,
        component: ComponentCategory.meeting,
      );

      Map response = await _webSocket!.sendRequest('join', {
        'displayName': localParticipant.displayName,
        'device': {
          'name': "Flutter",
          'flag': 'flutter',
          'version': sdkVersion,
        },
        'rtpCapabilities': _device!.rtpCapabilities.toMap(),
        'sctpCapabilities': _device!.sctpCapabilities.toMap(),
        'deviceInfo': deviceInfo,
        'switchingRoom': true,
        'metaData': _metaData,
        'autoConsume': _autoConsume,
        'batchingEnabled': _enableBatching,
      });

      // Complete join request span
      SdkTracer.shared.endSpan(
        joinRequestScope,
        success: true,
        message: 'Requested to join switched room successfully',
      );

      //The room switch reuses the live socket, so onOpen does not re-fire.
      _rejoinInProgress = false;
      _roomState = RoomState.connected;
      _eventEmitter.emit('meeting-state-changed', RoomState.connected);

      SdkTracer.shared.traceEvent(
        spanName: 'Emitting MEETING_JOINED Event',
        component: ComponentCategory.meeting,
        category: EventCategory.telemetry,
        attributes: {
          'switchingRoomId': switchingRoomId,
        },
      );
      _eventEmitter.emit('meeting-joined', {
        'switchingRoomId': switchingRoomId,
      });

      response['peers'].forEach((value) {
        _addPeer(value, switchRoomScope);
      });

      _addUnsupportedCodecs(response['unsupportedCodecs']?.cast<String>());

      final VideoCodec currentCodec = _customVideoTrackConfig.codec;

      final bool needsCodecRecycle = _camEnabled &&
          _codecSwitchEnabled &&
          !_codecRecycleInProgress &&
          _codecRecycleFrom != currentCodec &&
          _unsupportedCodecs.isNotEmpty &&
          currentCodec != VideoCodec.VP8;

      if (needsCodecRecycle) {
        final SpanScope camCycleSpan = SdkTracer.shared.startSpan(
          spanName: 'Change webcam due to unsupported codec',
          parentSpan: switchRoomScope,
          component: ComponentCategory.media,
          category: EventCategory.telemetry,
          attributes: {
            "reason":
                "Due to one of the participants doesn't support ${_unsupportedCodecs.first.parseToString()} Codec.",
          },
        );

        _codecRecycleInProgress = true;

        try {
          await _disableCamImpl(parentSpan: camCycleSpan);

          if (!_camEnabled) {
            SdkTracer.shared.endSpan(
              camCycleSpan,
              success: true,
              message:
                  'Webcam recycle aborted : camera was turned off by the user',
            );
          } else {
            await _enableCamImpl(
                parentSpan: camCycleSpan, recycleFrom: currentCodec);

            SdkTracer.shared.endSpan(
              camCycleSpan,
              success: true,
              message:
                  'Webcam changed successfully to handle unsupported codec',
            );
          }
        } catch (error) {
          SdkTracer.shared.endSpan(
            camCycleSpan,
            success: false,
            category: EventCategory.error,
            message: 'Webcam change failed : ${error.toString()}',
          );
        } finally {
          _codecRecycleInProgress = false;
        }
      }

      // Complete main span
      SdkTracer.shared.endSpan(
        switchRoomScope,
        success: true,
        message: 'Room switch completed successfully',
      );
    } catch (error) {
      // End child span if failed
      try {
        if (joinRequestScope != null) {
          SdkTracer.shared.endSpan(
            joinRequestScope,
            category: EventCategory.error,
            success: false,
            message: 'Switching room failed with error: ${error.toString()}',
          );
        }
      } catch (_) {}

      // End parent span if failed
      try {
        if (switchRoomScope != null) {
          SdkTracer.shared.endSpan(
            switchRoomScope,
            category: EventCategory.error,
            success: false,
            message: 'Switching room failed with error: ${error.toString()}',
          );
        }
      } catch (_) {}

      _close(LeaveReason.switchRoomFailed);
    }
  }

  /// Starts relaying selected media streams from the current meeting
  /// to another destination meeting.
  ///
  /// - This method allows you to relay specific media streams such as
  /// WebCam video, microphone audio, or screen-sharing streams to
  /// a different meeting.
  ///
  /// ### **Parameters**
  ///
  /// - [meetingId]:
  ///   The ID of the destination meeting where the media streams
  ///   should be relayed.
  ///
  /// - [token] *(optional)*:
  ///   Authentication token for the destination meeting.
  ///
  /// - [kinds] *(optional)*:
  ///   A list of media stream types to relay.
  ///   If not provided, all supported media streams may be relayed.
  ///
  ///   Possible values:
  ///   - `"audio"`: Relays microphone audio streams
  ///   - `"video"`: Relays WebCam video streams
  ///   - `"share"`: Relays screen-sharing video streams
  ///   - `"share_audio"`: Relays screen-sharing audio streams
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Relay audio and video streams to another meeting
  /// await room.requestMediaRelay(
  ///   '<DESTINATION_MEETING_ID>',
  ///   token: '<VIDEOSDK_TOKEN>',
  ///   kinds: ['audio', 'video'],
  /// );
  /// ```
  Future<void> requestMediaRelay(String meetingId,
      {String? token, List<String>? kinds}) async {
    if (!_ensureJoined("requestMediaRelay")) return;
    await _requestMediaRelay(meetingId, token: token, kinds: kinds);
  }

  Future<void> _requestMediaRelay(String meetingId,
      {String? token, List<String>? kinds}) async {
    final List<String> relayKinds =
        kinds ?? ["audio", "video", "share", "share_audio"];

    SpanScope? mediaRelaySpan = SdkTracer.shared.startSpan(
      spanName: "Requesting to send media relay",
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
      attributes: {
        "meetingId": meetingId,
        "kinds": relayKinds.toString(),
      },
    );

    try {
      await _webSocket!.sendRequest('mediaRelayRequestSent', {
        "secret": token ?? _token,
        "meetingId": meetingId,
        "kinds": relayKinds,
      });

      SdkTracer.shared.endSpan(
        mediaRelaySpan,
        message: "Media relay request sent successfully",
      );
    } catch (e) {
      SdkTracer.shared.endSpan(
        mediaRelaySpan,
        message: "Error in requestMediaRelay() -> ${e.toString()}",
        success: false,
        category: EventCategory.error,
      );
    }
  }

  /// Stops the ongoing media relay to a destination meeting.
  ///
  /// - This method terminates the relay of media streams from the current
  /// meeting to the specified destination meeting.
  ///
  /// ### **Parameters**
  ///
  /// - [meetingId]:
  ///   The ID of the destination meeting for which the media relay
  ///   should be stopped.
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Stop media relay to a destination meeting
  /// await room.stopMediaRelay('<DESTINATION_MEETING_ID>');
  /// ```
  Future<void> stopMediaRelay(String meetingId) => _stopMediaRelay(meetingId);
  Future<void> _stopMediaRelay(String meetingId) async {
    SpanScope? stopMediaRelaySpan = SdkTracer.shared.startSpan(
      spanName: "Requesting to stop media relay",
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
      attributes: {
        "meetingId": meetingId,
      },
    );

    try {
      await _webSocket!.sendRequest('mediaRelayRequestStop', {
        'meetingId': meetingId,
      });

      SdkTracer.shared.endSpan(
        stopMediaRelaySpan,
        message: "Media relay stop request sent successfully",
      );
    } catch (e) {
      SdkTracer.shared.endSpan(
        stopMediaRelaySpan,
        message: "Error in stopMediaRelay() -> ${e.toString()}",
        success: false,
        category: EventCategory.error,
      );
    }
  }

  /// @nodoc
  Future<void> enableRelayMedia(String meetingId, List<String> kind) async {
    if (!_ensureJoined("enableRelayMedia")) return;

    try {
      await _webSocket!.sendRequest('enableRelayMedia', {
        "meetingId": meetingId,
        "kind": kind,
      });
    } catch (e) {
      SdkTracer.shared.traceEvent(
        spanName: "Error while enabling relay media request",
        category: EventCategory.backendError,
        component: ComponentCategory.meeting,
      );
    }
  }

  /// @nodoc
  Future<void> disableRelayMedia(String meetingId, List<String> kind) async {
    if (!_ensureJoined("disableRelayMedia")) return;

    try {
      await _webSocket!.sendRequest('disableRelayMedia', {
        "meetingId": meetingId,
        "kind": kind,
      });
    } catch (e) {
      SdkTracer.shared.traceEvent(
        spanName: "Error while disabling relay media request",
        category: EventCategory.backendError,
        attributes: {
          'error': e.toString(),
        },
        component: ComponentCategory.meeting,
      );
    }
  }

  Future<void> _handleMediaRelayRequest(
      String peerId, String decision, String meetingId) async {
    SpanScope? relayResponseSpan = SdkTracer.shared.startSpan(
      spanName: "Requesting to send response of media realy request",
      component: ComponentCategory.meeting,
      attributes: {
        "peerId": peerId,
        "meetingId": meetingId,
        "decision": decision,
      },
    );

    try {
      await _webSocket!.sendRequest('respondToMediaRelayRequest', {
        "meetingId": meetingId,
        "decidedBy": localParticipantId,
        "decision": decision,
        "peerId": peerId,
      });

      SdkTracer.shared.endSpan(
        relayResponseSpan,
        message: "Media relay response request sent successfully",
      );
    } catch (e) {
      SdkTracer.shared.endSpan(
        relayResponseSpan,
        message:
            "Media relay response request failed with error: ${e.toString()}",
        success: false,
        category: EventCategory.error,
      );
    }
  }

  /// @nodoc
  Future<void> pause(Consumer consumer) async {
    if (!_ensureJoined("stream.pause")) return;

    SpanScope? pauseConsumerSpan;

    pauseConsumerSpan = SdkTracer.shared.startSpan(
      spanName: "Pause Stream Requested",
      component: ComponentCategory.media,
      attributes: {
        'kind': consumer.kind,
      },
      category: EventCategory.telemetry,
    );

    try {
      await _webSocket!.sendRequest('pauseConsumer', {
        'consumerId': consumer.id,
      });

      SdkTracer.shared.endSpan(
        pauseConsumerSpan,
        message: "Stream pause request sent successfully",
      );
    } catch (e) {
      SdkTracer.shared.endSpan(
        pauseConsumerSpan,
        success: false,
        message: "Error in stream's pause() -> ${e.toString()}",
        category: EventCategory.error,
      );
    }
  }

  /// @nodoc

  Future<void> resume(Consumer consumer) async {
    if (!_ensureJoined("stream.resume")) return;

    SpanScope? resumeConsumerSpan;

    resumeConsumerSpan = SdkTracer.shared.startSpan(
      spanName: "Resume Stream Requested",
      component: ComponentCategory.media,
      attributes: {
        'kind': consumer.kind,
      },
      category: EventCategory.telemetry,
    );

    try {
      await _webSocket!.sendRequest('resumeConsumer', {
        'consumerId': consumer.id,
      });

      SdkTracer.shared.endSpan(
        resumeConsumerSpan,
        message: "Stream resume request sent successfully",
      );
    } catch (e) {
      SdkTracer.shared.endSpan(
        resumeConsumerSpan,
        success: false,
        message: "Error in stream's resume() -> ${e.toString()}",
        category: EventCategory.error,
        attributes: {
          'error': e.toString(),
        },
      );
    }
  }

  /// Enables Adaptive Subscription for the current meeting.
  ///
  /// - Adaptive Subscription automatically optimizes video stream
  /// subscriptions based on participant visibility and current
  /// network conditions. This helps reduce bandwidth usage and
  /// improves overall performance by subscribing only to the
  /// most relevant video streams at any given time.
  ///
  /// - Once enabled, the SDK dynamically manages video layer
  /// subscriptions without requiring manual intervention.
  ///
  /// ### **Example**
  /// ```dart
  /// // Enable Adaptive Subscription once the meeting is joined
  /// meeting.on(Events.roomJoined, () async {
  ///   await meeting.enableAdaptiveSubscription();
  /// });
  /// ```
  Future<void> enableAdaptiveSubscription() async {
    if (!_ensureJoined("enableAdaptiveSubscription")) return;
    await _enableAdaptiveSubscription();
  }

  Future<void> _enableAdaptiveSubscription() async {
    SpanScope? enableAdaptiveSpan;

    enableAdaptiveSpan = SdkTracer.shared.startSpan(
      spanName: "Requesting to enable adaptive subscription",
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
    );

    try {
      await _webSocket!.sendRequest('enableAdaptiveSubscription', {});

      SdkTracer.shared.endSpan(
        enableAdaptiveSpan,
        message: "Adaptive subscription enable request sent successfully",
      );
    } catch (e) {
      SdkTracer.shared.endSpan(
        enableAdaptiveSpan,
        success: false,
        message: "Enable adaptive subscription failed",
        category: EventCategory.error,
        dashboardLog: true,
        attributes: {
          'error': "Error in enableAdaptiveSubscription() -> ${e.toString()}",
        },
      );
    }
  }

  /// Disables Adaptive Subscription for the current meeting.
  ///
  /// - When Adaptive Subscription is disabled, the SDK will continue to
  /// subscribe to all available video streams, regardless of participant
  /// visibility or current network conditions. This may increase bandwidth
  /// usage but ensures that all video streams are always received.
  ///
  /// ### **Example**
  /// ```dart
  /// // Disable Adaptive Subscription
  /// await meeting.disableAdaptiveSubscription();
  ///
  /// ```
  Future<void> disableAdaptiveSubscription() async {
    if (!_ensureJoined("disableAdaptiveSubscription")) return;
    await _disableAdaptiveSubscription();
  }

  Future<void> _disableAdaptiveSubscription() async {
    SpanScope? disableAdaptiveSpan;

    disableAdaptiveSpan = SdkTracer.shared.startSpan(
      spanName: "Requesting to disable adaptive subscription",
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
    );

    try {
      await _webSocket!.sendRequest('disableAdaptiveSubscription', {});

      SdkTracer.shared.endSpan(
        disableAdaptiveSpan,
        message: "Adaptive subscription disable request sent successfully",
      );
    } catch (e) {
      SdkTracer.shared.endSpan(
        disableAdaptiveSpan,
        success: false,
        message: "Disable adaptive Susbcription failed",
        category: EventCategory.error,
        dashboardLog: true,
        attributes: {
          'error': "Error in disableAdaptiveSubscription() -> ${e.toString()}",
        },
      );
    }
  }

  Future<void> _setValue(String key, String? value) async {
    try {
      // Socket request
      final resp = await _webSocket!.sendRequest('realtimeStoreSet', {
        "key": key,
        "value": value,
      });

      if (resp["status"] == "error") {
        throw Exception(
          resp["message"] ??
              "Something went wrong while setting value in Realtime Store",
        );
      }
    } catch (error) {
      rethrow;
    }
  }

  Future<String?> _getValue(String key) async {
    try {
      final response = await _webSocket!.sendRequest(
        "realtimeStoreGet",
        {
          "key": key,
        },
      );

      if (response != null && response["status"] == "ok") {
        return response["value"] as String;
      } else if (response != null && response["status"] == "error") {
        throw Exception(
          response["message"] ??
              "Something went wrong while getting value from Realtime Store",
        );
      }
      return null;
    } catch (error) {
      rethrow;
    }
  }

  Future<void> _observe(String key) async {
    if (_closed) return;

    try {
      await _webSocket!.sendRequest(
        "realtimeStoreObserve",
        {
          "key": key,
        },
      );

      SdkTracer.shared.traceEvent(
        spanName:
            "RealtimeStore observation started successfully for key '$key'.",
        component: ComponentCategory.meeting,
        category: EventCategory.backendError,
      );
    } catch (error) {
      SdkTracer.shared.traceEvent(
        spanName: "Error observe() | failed",
        component: ComponentCategory.meeting,
        category: EventCategory.backendError,
        attributes: {
          'error': error.toString(),
        },
      );
      rethrow;
    }
  }

  Future<void> _stopObserving(String key) async {
    if (_closed) return;

    try {
      await _webSocket!.sendRequest("realtimeStoreStopObserve", {
        "key": key,
      });

      SdkTracer.shared.traceEvent(
        spanName:
            "RealtimeStore observation stopped successfully for key '$key'.",
        component: ComponentCategory.meeting,
        category: EventCategory.backendError,
      );
    } catch (error) {
      SdkTracer.shared.traceEvent(
        spanName: "Error stopObserving() | failed",
        component: ComponentCategory.meeting,
        category: EventCategory.backendError,
        attributes: {
          'error': error.toString(),
        },
      );
      rethrow;
    }
  }

  /// Joins the VideoSDK Room.
  ///
  /// - After creating the instance of VideoSDK Room, you can join the room by calling this method.
  ///
  /// **Events associated with join():**
  ///
  /// * Local Participant will receive a [Events.roomJoined] event when successfully joined.
  /// * Remote Participant will receive a [Events.participantJoined] event with the newly
  ///   joined [Participant] object from the event handler.
  ///
  /// **Permission-based join behavior:**
  ///
  /// *Participant with `ask_join` permission:*
  ///
  /// If a token contains the `ask_join` permission, the participant will not join
  /// the room directly. Instead, an [Events.entryRequested] event will be emitted to
  /// participants with the `allow_join` permission. After the decision is made,
  /// an [Events.entryResponded] event will be emitted containing the decision.
  ///
  /// *Participant with `allow_join` permission:*
  ///
  /// If a token contains the `allow_join` permission, the participant will join
  /// the room directly after calling [join].
  ///
  /// ### **Example**
  /// ```dart
  /// // Create and join a room
  /// Room room = VideoSDK.createRoom(
  ///   roomId: "abcd-efgh-ijkl",
  ///   token: "your-token",
  /// );
  ///
  /// // Listen to room joined event
  /// room.on(Events.roomJoined, () {
  ///   print('Successfully joined the room');
  /// });
  ///
  /// // Join the room
  /// await room.join();
  /// ```
  ///
  Future<void> join() => _join();

  Future<void> _join() async {
    if (_joined) {
      //
      log("Already Joined");
      return;
    }

    String? socketPath;
    String? socketUrl;

    try {
      String initConfigUrl =
          "https://$_signalingBaseUrl/infra/v1/meetings/sdk-init-config";

      final jsonRes = await http.post(Uri.parse(initConfigUrl), body: {
        'roomId': id,
      }, headers: {
        'Authorization': _token,
      });

      final jsonData = json.decode(jsonRes.body);

      if (jsonRes.statusCode != 200) {
        throw jsonData['error'] ?? "Error while getting baseUrl";
      }

      final data = jsonData['data'];
      baseUrl = data['baseUrl'];
      socketPath = data['socketPath'];
      socketUrl = data['socketUrl'];

      //
      try {
        List<dynamic> iceServers =
            await compute(_decryptIceServers, data['iceServers'] as String);
        //
        iceServers.asMap().forEach((key, value) {
          //
          if (value['url'].toString().contains("stun")) {
            //
            RTCIceServer iceServer = RTCIceServer(
                credentialType: RTCIceCredentialType.password,
                username: "",
                urls: [value['url']],
                credential: "");
            _iceServers.add(iceServer);
          } else {
            //
            RTCIceServer iceServer = RTCIceServer(
                credentialType: RTCIceCredentialType.password,
                username: value['username'],
                urls: [value['url']],
                credential: value['credential']);
            _iceServers.add(iceServer);
          }
        });
        final observability = data['observability'];
        // set meetingId, peerId for Logs
        VideoSDKLog.meetingId = id;
        VideoSDKLog.peerId = localParticipant.id;
        VideoSDKLog.logsConfig = observability['logs'];
        VideoSDKLog.jwtKey = observability['jwt'];
        VideoSDKLog.debugMode = _debugMode;

        deviceInfo = await VideoSDK.getDeviceInfo();

        final logDeviceInfo = <String, dynamic>{};
        if (deviceInfo.containsKey("browserUserAgent")) {
          logDeviceInfo.addAll(<String, dynamic>{
            "browserName": deviceInfo['browserUserAgent']['browser']['name'],
            "browserVersion": deviceInfo['browserUserAgent']['browser']
                ['version'],
            "osName": deviceInfo['browserUserAgent']['os']['name'],
            "osVersion": deviceInfo['browserUserAgent']['os']['type'],
            "platform": deviceInfo['platform']
          });
        }
        if (deviceInfo.containsKey("deviceUserAgent")) {
          logDeviceInfo.addAll(<String, dynamic>{
            "brand": deviceInfo['deviceUserAgent']['brand'],
            "model": deviceInfo['deviceUserAgent']['modelName'],
            "osVersion": deviceInfo['deviceUserAgent']['osVersion'],
            "platform": deviceInfo['platform']
          });
        }

        VideoSDKLog.deviceInfo = logDeviceInfo;

        // open-telemeetry
        // Dispose old telemetry if it exists
        videoSDKTelemetery?.dispose();

        videoSDKTelemetery = VideoSDKTelemetery(
          roomId: id,
          peerId: localParticipant.id,
          observabilityJwt: observability['jwt'],
          traces: observability['traces'],
          logs: observability['logs'],
          deviceInfo: deviceInfo,
          debugMode: _debugMode,
          metaData: observability['metaData'],
        );

        TelemetryOutput.setTelemetry(videoSDKTelemetery!);

        // Ensure tracer has default outputs registered now that telemetry is initialized
        SdkTracer.shared.registerDefaultOutputsIfNeeded();

        if (SdkTracer.shared.isLogLevelSet) {
          SdkTracer.shared.traceEvent(
            spanName:
                "VideoSDK Log Level set to: ${SdkTracer.shared.getLogLevel().name}",
            component: ComponentCategory.meeting,
            category: EventCategory.telemetry,
          );
        }
      } catch (error) {
        //
      }
    } catch (err) {
      //
      SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
            name: "Error in join()",
            attributes: {
              "error": err.toString(),
            },
            category: EventCategory.error,
          );

      final error = <String, dynamic>{};

      error.addAll(<String, dynamic>{
        "code": "3023",
        "name": "ERROR_JOINING_MEETING",
        "message":
            "An error occured while joining the meeting :  ${err.toString()}"
      });

      _eventEmitter.emit("error", error);

      _roomState = RoomState.failed;
      _eventEmitter.emit('meeting-state-changed', RoomState.failed);

      log("An error occured while joining the meeting : VIDEOSDK ERROR :: 3023  :: ERROR_JOINING_MEETING :: ${err.toString()}");

      throw "Error while getting baseUrl";
    }

    // Kick off device enumeration now — runs in parallel with WebSocket connect
    _devicePrefetch = Future.wait([
      VideoSDK.getVideoDevices(),
      VideoSDK.getAudioDevices(),
    ]);

    // Kick off web permission checks in parallel with WebSocket connect.
    // Permissions don't depend on WebSocket — by the time join handshake
    // completes they will already be resolved.
    if (kIsWeb) {
      final isFirefoxEarly =
          deviceInfo['browserUserAgent']?['browser']?['name'] == "Firefox";
      if (!isFirefoxEarly) {
        _permissionPrefetch = Future.wait([
          if (_micEnabled)
            VideoSDK.requestPermissions(Permissions.audio)
          else
            Future.value(<String, bool>{'audio': false}),
          if (_camEnabled)
            VideoSDK.requestPermissions(Permissions.video)
          else
            Future.value(<String, bool>{'video': false}),
        ]);
      }
    }
    _roomState = RoomState.connecting;
    _eventEmitter.emit('meeting-state-changed', RoomState.connecting);

    // send trace roomConfig
    try {
      _joinSpanScope = SdkTracer.shared.startSpan(
        spanName: 'Joining the meeting',
        attributes: {
          'deviceInfo': deviceInfo.toString(),
          'displayName': _displayName,
          'micEnabled': micEnabled,
          'camEnabled': _camEnabled,
          'maxResolution': _maxResolution,
          'multiStream': _multiStream,
          'mode': _mode.name.toString(),
          if (_customCameraVideoTrack != null)
            'customCameraVideoTrack':
                _customCameraVideoTrack!.toMap().toString(),
          if (_customMicrophoneAudioTrack != null)
            'customMicrophoneAudioTrack':
                _customMicrophoneAudioTrack!.toMap().toString(),
          if (_selectedAudioInput != null)
            'selectedAudioInput': _selectedAudioInput!.label,
          if (_selectedVideoInput != null)
            'selectedVideoInput': _selectedVideoInput!.label,
        },
        component: ComponentCategory.meeting,
        category: EventCategory.telemetry,
      );
    } catch (error) {
      //
    }

    //
    _webSocket = WebSocket(
      baseUrl: baseUrl,
      peerId: localParticipant.id,
      meetingId: id,
      token: _token,
      mode: _mode.name,
      socketPath: socketPath,
      socketUrl: socketUrl,
    );

    try {
      SdkTracer.shared.traceEvent(
        spanName: 'Meeting State: CONNECTING',
        parentScope: _joinSpanScope,
        component: ComponentCategory.meeting,
        category: EventCategory.telemetry,
      );
    } catch (error) {
      SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
        name: 'Meeting State connection failed',
        parentScope: _joinSpanScope,
        component: ComponentCategory.meeting,
        attributes: {
          "error": error.toString(),
        },
      );
    }

    //
    _webSocket!.onOpen = () {
      try {
        _roomState = RoomState.connected;
        _eventEmitter.emit('meeting-state-changed', RoomState.connected);

        SdkTracer.shared.traceEvent(
          spanName: 'Meeting State: CONNECTED',
          parentScope: _joinSpanScope,
          component: ComponentCategory.meeting,
          category: EventCategory.telemetry,
        );
      } catch (error) {
        SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
          name: 'Meeting State connection failed',
          parentScope: _joinSpanScope,
          component: ComponentCategory.meeting,
          attributes: {
            "error": error.toString(),
          },
        );
      }

      // Fire getRouterRtpCapabilities immediately — runs in parallel with
      // requestEntry server round-trip (~47ms), so _joinRoom() pays 0ms for it
      _rtpCapsPrefetch =
          _webSocket!.sendRequest('getRouterRtpCapabilities', {});

      _requestEntry();
    };

    _webSocket!.onReconnection = (error) {
      if (_webSocket != null) {
        SpanScope reconnectSpan = SdkTracer.shared.startSpan(
          spanName: 'Reconnecting to the meeting',
          parentSpan: _joinSpanScope,
          category: EventCategory.telemetry,
        );

        SdkTracer.shared.traceEvent(
          spanName: 'Meeting State: RECONNECTING',
          parentScope: reconnectSpan,
          attributes: {
            "error": error.toString(),
          },
          category: EventCategory.telemetry,
        );

        _rejoinInProgress = true;
        _roomState = RoomState.reconnecting;
        _eventEmitter.emit('meeting-state-changed', RoomState.reconnecting);

        SpanScope closeSpan = SdkTracer.shared.startSpan(
          spanName: 'Closing resources',
          parentSpan: reconnectSpan,
        );

        _closeForegroundService();

        if (_sendTransport != null) {
          _sendTransport!.close();
          _sendTransport = null;
        }

        if (_recvTransport != null) {
          _recvTransport!.close();
          _recvTransport = null;
        }

        if (_micProducer != null) {
          if (!_micProducer!.closed && _micProducer!.paused) {
            _micProducer!.resume();
          }
          _micProducer!.track.stop();
          _micProducer!.close();

          _removeProducer(
              _micProducer!, _ProducerType.micProducer, _joinSpanScope!);
          _micInProgress = false;
          _micProducer = null;
          _customMicrophoneAudioTrack?.dispose();
          _customMicrophoneAudioTrack = null;
        }

        if (_cameraProducer != null) {
          //

          _removeProducer(
              _cameraProducer!, _ProducerType.cameraProducer, _joinSpanScope!);
          _cameraInProgress = false;
          _cameraProducer = null;
          _customCameraVideoTrack?.dispose();
          _customCameraVideoTrack = null;
        }
        if (_screenShareAudioProducer != null) {
          _removeProducer(_screenShareAudioProducer!,
              _ProducerType.screenShareAudioProducer, _joinSpanScope!);

          if (!_screenShareAudioProducer!.closed &&
              _screenShareAudioProducer!.paused) {
            _screenShareAudioProducer!.resume();
          }
          _screenShareInProgress = false;
          _screenShareAudioProducer!.track.stop();
          _screenShareAudioProducer!.close();
          _screenShareAudioProducer = null;
        }
        if (_screenshareProducer != null) {
          _removeProducer(_screenshareProducer!,
              _ProducerType.screenshareProducer, _joinSpanScope!);

          if (!_screenshareProducer!.closed && _screenshareProducer!.paused) {
            _screenshareProducer!.resume();
          }
          _screenShareInProgress = false;
          _screenshareProducer!.track.stop();
          _screenshareProducer!.close();
          _screenshareProducer = null;
        }

        if (_sendTransport != null) {
          _sendTransport!.close();
          _sendTransport = null;
        }

        if (_recvTransport != null) {
          _recvTransport!.close();
          _recvTransport = null;
        }

        SdkTracer.shared.endSpan(
          closeSpan,
          message: "Resource closed Successfully",
        );
        SdkTracer.shared.endSpan(reconnectSpan,
            message: "Meeting reconnecting completed",
            category: EventCategory.telemetry);
      }
    };

    _webSocket!.onDisconnected = () {
      //Fires the moment the transport drops. onReconnection is wired to
      //socket.io's reconnect_attempt, which waits out setReconnectionDelay
      //(5s) first — so without this the gate stayed open for ~5s against a
      //dead socket, where requests reach emitWithAck and never get an ack.
      //Only the internal flag is set: RoomState timing stays as apps see it.
      if (_closed) return;
      _rejoinInProgress = true;
    };

    _webSocket!.onClose = (data) {
      if (_closed) return;

      int code = LeaveReason.unknown.code;
      try {
        if (data is List && data.isNotEmpty) {
          var actualData = data[0]; // Get the first element

          if (actualData != null && actualData['reason'] != null) {
            var reason = actualData['reason'];

            // Extract code
            if (reason['code'] != null) {
              code = reason['code'] is int
                  ? reason['code']
                  : int.tryParse(reason['code'].toString()) ??
                      LeaveReason.unknown.code;
            }

            // Extract message
            if (reason['message'] != null) {}
          }
        }
      } catch (e) {
        log("Error parsing close data: $e");
      }

      _close(LeaveReason.fromCode(code));
    };

    _webSocket!.onRequest = (request, accept, reject) async {
      switch (request['method']) {
        // case "close":
        //   {
        //  _close();
        //     break;
        //   }

        case 'newConsumer':
          {
            final peerId = request['peerId'];
            final producerId = request['producerId'];
            final id = request['id'];
            final kind = request['kind'];
            final appData = Map<String, dynamic>.from(request['appData']);

            // Get the peer span for hierarchical tracing
            final peerSpan = _peerSpans[peerId];

            // Determine the final kind (share, share audio, or regular kind)
            final bool isShare = appData['share'] == true;
            final String finalKind =
                isShare ? (kind == 'video' ? 'share' : 'share audio') : kind;

            SpanScope newConsumerSpan = SdkTracer.shared.startSpan(
              spanName: "Starting Participant's $finalKind Stream",
              parentSpan: peerSpan,
              component: ComponentCategory.media,
              attributes: {
                'peer.id': peerId,
              },
            );

            if (newConsumerSpan != null) {
              _consumerSpans[id] = newConsumerSpan;
            }

            if (!_consume) {
              reject(403, 'I do not want to consume');
              SdkTracer.shared.endSpan(
                newConsumerSpan,
                success: false,
                message: "I do not want to consume",
              );
              break;
            }

            try {
              _recvTransport!.consume(
                id: id,
                producerId: producerId,
                kind: RTCRtpMediaTypeExtension.fromString(kind),
                rtpParameters: RtpParameters.fromMap(request['rtpParameters']),
                appData: appData,
                peerId: peerId,
                accept: accept,
              );

              // Complete the main newConsumer span
              SdkTracer.shared.endSpan(
                newConsumerSpan,
                message: "New media stream received successfully",
              );
            } catch (error) {
              SdkTracer.shared.endSpan(
                newConsumerSpan,
                success: false,
                message:
                    "Unable to receive participant's media stream: ${error.toString()}",
                category: EventCategory.error,
              );

              log(error.toString());
              rethrow;
            }
            break;
          }

        case 'enableMic':
          {
            SpanScope? enableMicSpan;
            try {
              try {
                enableMicSpan = SdkTracer.shared.startSpan(
                  spanName:
                      'Mic enable request received from peer(${request['peerId']})',
                  component: ComponentCategory.meeting,
                  category: EventCategory.telemetry,
                );
              } catch (_) {}

              _eventEmitter.emit('mic-requested', {
                // 'participantId': peerId,
                "accept": () {
                  try {
                    if (enableMicSpan != null) {
                      SdkTracer.shared.traceEvent(
                        spanName: 'Mic enable request accepted',
                        parentScope: enableMicSpan,
                        component: ComponentCategory.meeting,
                        category: EventCategory.telemetry,
                      );
                    }
                  } catch (_) {}
                  _enableMicImpl(parentSpan: enableMicSpan, setIntent: true)
                      .then((_) {
                    if (enableMicSpan != null) {
                      SdkTracer.shared.endSpan(
                        enableMicSpan,
                        message: 'Mic enabled successfully',
                      );
                    }
                  });
                },
                "reject": () {
                  try {
                    if (enableMicSpan != null) {
                      SdkTracer.shared.traceEvent(
                        spanName: 'Mic enable request rejected',
                        parentScope: enableMicSpan,
                        component: ComponentCategory.meeting,
                        category: EventCategory.telemetry,
                      );
                      SdkTracer.shared.endSpan(
                        enableMicSpan,
                        message: 'Mic enable request rejected by user',
                      );
                    }
                  } catch (_) {}
                },
              });

              accept({});

              accept({});
            } catch (error) {
              //
              if (enableMicSpan != null) {
                SdkTracer.shared.endSpan(
                  enableMicSpan,
                  category: EventCategory.backendError,
                  attributes: {
                    'error': error.toString(),
                    'peeId': request['peerId'],
                  },
                  success: false,
                  message:
                      "Error in participant's enableMic() -> ${error.toString()}",
                );
              }

              rethrow;
            }
            break;
          }
        case 'disableMic':
          {
            SpanScope? disableMicSpan;
            try {
              try {
                disableMicSpan = SdkTracer.shared.startSpan(
                  spanName:
                      'Disabling Microphone as requested by Participant${request['peerId']}',
                  component: ComponentCategory.media,
                );
              } catch (_) {}

              _disableMic(parentSpan: disableMicSpan).then((_) {
                if (disableMicSpan != null) {
                  SdkTracer.shared.endSpan(
                    disableMicSpan,
                    message: 'Microphone disabled successfully',
                  );
                }
              });
              accept({});
            } catch (error) {
              //

              if (disableMicSpan != null) {
                SdkTracer.shared.endSpan(
                  disableMicSpan,
                  success: false,
                  message: 'Error disableMic request failed',
                  category: EventCategory.error,
                );
              }

              rethrow;
            }
            break;
          }
        case 'enableWebcam':
          {
            SpanScope? enableWebcam;
            try {
              enableWebcam = SdkTracer.shared.startSpan(
                spanName:
                    'Camera enable request received from peer${request['peerId']}',
                component: ComponentCategory.media,
                category: EventCategory.telemetry,
              );
            } catch (_) {}

            try {
              _eventEmitter.emit('webcam-requested', {
                // "participantId": peerId,
                "accept": () {
                  _enableCamImpl(parentSpan: enableWebcam, setIntent: true)
                      .then((_) {
                    try {
                      if (enableWebcam != null) {
                        SdkTracer.shared.traceEvent(
                          spanName: 'Camera enable request accepted',
                          parentScope: enableWebcam,
                          component: ComponentCategory.media,
                          category: EventCategory.telemetry,
                        );
                        SdkTracer.shared.endSpan(
                          enableWebcam,
                          message: 'Camera enabled successfully',
                        );
                      }
                    } catch (_) {}
                  });
                },
                "reject": () {
                  if (enableWebcam != null) {
                    SdkTracer.shared.traceEvent(
                      spanName: 'Camera enable request rejected',
                      parentScope: enableWebcam,
                      component: ComponentCategory.media,
                      category: EventCategory.telemetry,
                    );
                    SdkTracer.shared.endSpan(
                      enableWebcam,
                      message: 'Camera enable request rejected by user',
                    );
                  }
                },
              });

              accept({});
            } catch (error) {
              if (enableWebcam != null) {
                SdkTracer.shared.endSpan(
                  enableWebcam,
                  success: false,
                  attributes: {
                    'error': error.toString(),
                    'peerId': request['peerId'],
                  },
                  message: 'Webcam enable request failed',
                  category: EventCategory.error,
                );
              }
              rethrow;
            }
            break;
          }
        case 'disableWebcam':
          {
            SpanScope? disableWebcamSpan;

            try {
              disableWebcamSpan = SdkTracer.shared.startSpan(
                spanName:
                    'Disabling Webcam as requested by Participant: ${request['peerId']}',
                component: ComponentCategory.media,
                category: EventCategory.telemetry,
              );

              _disableCamImpl(parentSpan: disableWebcamSpan).then((_) {
                if (disableWebcamSpan != null) {
                  SdkTracer.shared.endSpan(
                    disableWebcamSpan,
                    message: 'Webcam disabled successfully',
                  );
                }
              });
              accept({});
            } catch (error) {
              //
              if (disableWebcamSpan != null) {
                SdkTracer.shared.endSpan(
                  disableWebcamSpan,
                  success: false,
                  message: 'Error cam request failed',
                  category: EventCategory.error,
                );
              }

              rethrow;
            }
            break;
          }
        case "statsData":
          {
            if (!kIsWeb) {
              if (Platform.isAndroid || Platform.isIOS) {
                final usage = await _getCpuAndMemoryUsage();
                if (usage != null) {
                  _stats['deviceStats'] = [];
                  _stats['deviceStats'].add({
                    'timestamp': DateTime.now().millisecondsSinceEpoch,
                    'cpuUsage': usage['cpuUsage'],
                    'memoryUsage': usage['memoryUsage'],
                  });
                }
              }
            }

            accept({
              "peerId": localParticipant.id,
              "statsData": _stats,
            });
            _stats = {};
            break;
          }
        case "pinStateChanged":
          {
            SpanScope? pinStateChangedSpan;

            try {
              String peerId = request['peerId'];
              Map<dynamic, dynamic> state = request['state'];
              String? pinnedBy = request['pinnedBy'];

              // Start span
              pinStateChangedSpan = SdkTracer.shared.startSpan(
                spanName: "Emitting PIN_STATE_CHANGED Event",
                component: ComponentCategory.meeting,
                category: EventCategory.telemetry,
                attributes: {
                  "peerId": peerId,
                  "state": state.toString(),
                  if (pinnedBy != null) "pinnedBy": pinnedBy,
                },
              );

              // Ensure peer exists in map
              if (!pinnedParticipants.containsKey(peerId)) {
                pinnedParticipants[peerId] = ParticipantPinState(
                  cam: false,
                  share: false,
                );
              }

              // Update pin state
              ParticipantPinState pinPeer = pinnedParticipants[peerId]!;

              if (state['cam'] != null) {
                pinPeer.cam = state['cam'];
              }

              if (state['share'] != null) {
                pinPeer.share = state['share'];
              }

              pinnedParticipants[peerId] = pinPeer;

              // Emit events
              _eventEmitter.emit('pin-state-changed-$peerId', {
                'participantId': peerId,
                'state': state,
                'pinnedBy': pinnedBy,
              });

              _eventEmitter.emit('pin-state-changed', {
                'participantId': peerId,
                'state': state,
                'pinnedBy': pinnedBy,
              });

              // Remove if both false
              if (!pinPeer.cam && !pinPeer.share) {
                pinnedParticipants.remove(peerId);
              }

              // Accept request
              accept({});

              // End span success
              SdkTracer.shared.endSpan(
                pinStateChangedSpan,
                success: true,
                message: "Participant pin state updated successfully",
              );
            } catch (error) {
              // End span error
              if (pinStateChangedSpan != null) {
                SdkTracer.shared.endSpan(
                  pinStateChangedSpan,
                  success: false,
                  message:
                      "Failed to process pinStateChanged: ${error.toString()}",
                  category: EventCategory.error,
                  attributes: {
                    "error": error.toString(),
                  },
                );
              }

              rethrow;
            }

            break;
          }
        default:
          break;
      }
    };

    _webSocket!.onNotification = _handleNotification;

    _webSocket!.socket.on('batchNotification', (data) async {
      if (data is Map && data['notifications'] is List) {
        for (final n in (data['notifications'] as List)) {
          await _handleNotification(n);
        }
      }
    });
  }

  Future<void> _handleNotification(notification) async {
    switch (notification['method']) {
      case 'error':
        {
          dynamic error = notification['data'];
          //
          if (error != null) {
            SdkTracer.shared.traceEvent(
              spanName: 'Emitting ERROR Event',
              parentScope: _joinSpanScope,
              component: ComponentCategory.meeting,
              category: EventCategory.error,
              dashboardLog: true,
              attributes: {
                "error": "Error encountered with code: ${error.toString()}",
              },
            );
            //
            if (error is Map && VideoSDKErrors.containsKey(error['code'])) {
              _eventEmitter.emit("error", VideoSDKErrors[error['code']]);
            } else {
              _eventEmitter.emit("error", error);
            }
          } else {
            try {
              SdkTracer.shared.traceEvent(
                spanName: 'Error from server',
                parentScope: _joinSpanScope,
                component: ComponentCategory.meeting,
                attributes: {
                  "error": error.toString(),
                },
              );
            } catch (_) {}
            _eventEmitter
                .emit("error", {"message": "Unknown error", "code": 0});
          }

          break;
        }

      case 'producerScore':
        {
          break;
        }

      case 'consumerClosed':
        {
          String consumerId = notification['consumerId'];

          SpanScope? closingSpan;
          try {
            Consumer? consumer = _recvTransport?.consumers[consumerId];

            if (consumer != null) {
              await _removePeerConsumer(consumerId);
            } else {
              _removePeerConsumer(consumerId);
            }
          } catch (e) {
            SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
                  name: "Error in consumerClosed",
                  attributes: {
                    "error": e.toString(),
                  },
                  success: false,
                );
            try {
              if (closingSpan != null) {
                SdkTracer.shared.endSpan(
                  closingSpan,
                  success: false,
                  message: "Participant's stream disabled failed",
                );
              }
            } catch (_) {}
          }
          break;
        }

      case 'consumerPaused':
        {
          String consumerId = notification['consumerId'];
          Consumer consumer = _recvTransport!.getConsumer(consumerId)!;
          consumer.pause();
          final consumerSpan = _consumerSpans[consumerId];
          try {
            SdkTracer.shared.traceEvent(
              spanName: 'Stream: Paused',
              parentScope: consumerSpan,
              component: ComponentCategory.participant,
              attributes: {
                "Stream": consumer.track.kind,
              },
            );
          } catch (_) {}

          break;
        }

      case 'consumerResumed':
        {
          String consumerId = notification['consumerId'];
          Consumer consumer = _recvTransport!.getConsumer(consumerId)!;
          var peerId = consumer.peerId;
          SpanScope? consumerSpan = _consumerSpans[consumerId];

          final Participant? participant = participants[peerId];
          if (participant != null) {
            var state = 'active';
            var streamId = consumer.track.id;
            Future.delayed(Duration(milliseconds: 1000), () {
              participant.handleStreamStateChanged(state, streamId);
            });
          }
          _recvTransport!.getConsumer(consumerId)!.resume();
          try {
            SdkTracer.shared.traceEvent(
              spanName: 'Stream: Resumed',
              parentScope: consumerSpan,
              component: ComponentCategory.participant,
              attributes: {
                "Stream": consumer.track.kind,
              },
            );
          } catch (_) {}
          // String consumerId = notification['data']['consumerId'];
          // peersBloc.add(PeerResumedConsumer(consumerId: consumerId));

          break;
        }
      case "consumerResumedSubManager":
        {
          String peerId = notification['peerId'];
          _eventEmitter.emit('subs-manager-resumed-$peerId', notification);
          break;
        }
      case "consumerPausedSubManager":
        {
          String peerId = notification['peerId'];
          _eventEmitter.emit('subs-manager-paused-$peerId', notification);
          break;
        }

      case "consumerLayersChanged":
        {
          String consumerId = notification['consumerId'];
          Consumer? consumer = _recvTransport?.getConsumer(consumerId);
          int spatialLayer = notification['spatialLayer'] ?? -1;
          int temporalLayer = notification['temporalLayer'] ?? -1;

          if (consumer != null) {
            SdkTracer.shared.traceEvent(
              spanName:
                  "Remote Peer ${consumer.peerId}  changed to $spatialLayer, previous quality was $temporalLayer",
              attributes: {
                "spatialLayer": spatialLayer,
                "temporalLayer": temporalLayer,
              },
              category: EventCategory.realTime,
              component: ComponentCategory.participant,
            );
          }

          _changePeerConsumerQuality(
            consumerId,
            spatialLayer: spatialLayer,
            temporalLayer: temporalLayer,
          );

          if (consumer != null) {
            consumer.spatialLayer = spatialLayer;
            consumer.temporalLayer = temporalLayer;
          }

          break;
        }

      case "entryRequested":
        {
          SpanScope? entryRequestedSpan;

          try {
            final String id = notification['id'];
            final String name = notification['name'];

            // Start span (child of join span)
            entryRequestedSpan = SdkTracer.shared.startSpan(
              spanName: "Entry Request from $name",
              parentSpan: _joinSpanScope,
              component: ComponentCategory.meeting,
              attributes: {
                "participantId": id,
                "name": name,
              },
            );

            if (id != localParticipant.id) {
              // Trace event for UI emission
              SdkTracer.shared.traceEvent(
                spanName: "Emitting ENTRY_REQUESTED Event",
                parentScope: _joinSpanScope,
                component: ComponentCategory.meeting,
                category: EventCategory.telemetry,
                attributes: {
                  "participantId": id,
                  "name": name,
                },
              );

              _eventEmitter.emit("entry-requested", <String, dynamic>{
                'participantId': id,
                'name': name,
                'allow': () {
                  _respondEntry(id, "allowed");
                },
                'deny': () {
                  _respondEntry(id, "denied");
                },
              });

              // End span success
              SdkTracer.shared.endSpan(
                entryRequestedSpan,
                success: true,
                message: "ENTRY_REQUESTED event emitted successfully",
              );
            } else {
              // End span failure
              SdkTracer.shared.endSpan(
                entryRequestedSpan,
                success: false,
                message: "ENTRY_REQUESTED ignored for local participant",
                category: EventCategory.error,
              );
            }
          } catch (error) {
            if (entryRequestedSpan != null) {
              SdkTracer.shared.endSpan(
                entryRequestedSpan,
                success: false,
                message:
                    "Failed to process entryRequested: ${error.toString()}",
                category: EventCategory.error,
                attributes: {
                  "error": error.toString(),
                },
              );
            }
          }

          break;
        }

      case "entryResponded":
        {
          var id = notification['id'];
          var decision = notification['decision'];
          var sessionId = notification['sessionId'];
          var switchingRoomId = notification['switchingRoomId'];

          // Create a span for entry response handling
          SpanScope? entryResponseSpan = SdkTracer.shared.startSpan(
            spanName: 'Entry response: ${decision.toString().toUpperCase()}',
            parentSpan: _requestEntrySpan,
            component: ComponentCategory.meeting,
            attributes: {
              'peer.id': id,
              'entry.decision': decision,
              'sessionId': sessionId,
              'switching_room': switchingRoomId != null,
            },
          );

          SdkTracer.shared.traceEvent(
            spanName: 'Emitting ENTRY_RESPONDED Event',
            parentScope: _requestEntrySpan,
            component: ComponentCategory.meeting,
            category: EventCategory.telemetry,
            attributes: {
              'id': id,
              'decision': decision,
            },
          );

          // Emit the event once
          _eventEmitter.emit(
            "entry-responded",
            <String, dynamic>{
              "id": id,
              "decision": decision,
            },
          );

          if (id == localParticipant.id && decision == "allowed") {
            if (switchingRoomId != null) {
              SdkTracer.shared.endSpan(
                entryResponseSpan,
                message: 'Switching room initiated',
              );
              if (_requestEntrySpan != null) {
                try {
                  SdkTracer.shared.endSpan(
                    _requestEntrySpan!,
                  );
                } catch (_) {}
              }

              _softClose();
              switchingRoom(switchingRoomId);
              _requestEntrySpan = null;
              break;
            }

            SdkTracer.shared.setSessionId(sessionId?.toString());
            VideoSDKLog.sessionId = sessionId;

            _joinRoom();

            SdkTracer.shared.endSpan(
              entryResponseSpan,
              message: 'Entry Responded',
            );
            if (_requestEntrySpan != null) {
              try {
                SdkTracer.shared.endSpan(
                  _requestEntrySpan!,
                  message: 'Entry Responded',
                );
              } catch (_) {}
            }
            _requestEntrySpan = null;
          } else if (id == localParticipant.id && decision == "denied") {
            _rejoinInProgress = false;

            SdkTracer.shared.endSpan(
              _joinSpanScope!,
              success: false,
              message: 'Join Request Denied',
            );
            if (_requestEntrySpan != null) {
              try {
                SdkTracer.shared.endSpan(
                  _requestEntrySpan!,
                  success: false,
                );
              } catch (_) {}
            }
            _requestEntrySpan = null;
          }

          break;
        }

      case 'newPeer':
        {
          Map<String, dynamic> newPeer =
              Map<String, dynamic>.from(notification);

          SpanScope? newPeerSpan;

          try {
            // ── Sanitize metaData and promote agentId (mirrors JS SDK) ──
            final rawMetaData = newPeer['metaData'];
            if (rawMetaData is Map) {
              final metaData = Map<String, dynamic>.from(rawMetaData);

              final agentId = metaData['agent_id'] as String?;
              bool metaDataUpdated = false;

              if (metaData.containsKey('agent_id')) {
                metaData.remove('agent_id');
                metaDataUpdated = true;
              }
              if (metaData.containsKey('agent_name')) {
                metaData.remove('agent_name');
                metaDataUpdated = true;
              }
              if (metaData.containsKey('is_videosdk_agent')) {
                metaData.remove('is_videosdk_agent');
                metaDataUpdated = true;
              }
              if (metaData.containsKey('enableAgentEvents')) {
                metaData.remove('enableAgentEvents');
                metaDataUpdated = true;
              }
              if (metaDataUpdated || agentId != null) {
                newPeer = {
                  ...newPeer,
                  if (agentId != null) 'agentId': agentId,
                  if (metaDataUpdated) 'metaData': metaData,
                };
              }
            }
            // ── End sanitization ──────────────────────────────────────

            final String participantId = newPeer['id'];
            final String displayName = newPeer['displayName'] ?? 'Unknown';

            // Start span
            newPeerSpan = SdkTracer.shared.startSpan(
              spanName: "Participant '$displayName' joined the room",
              attributes: {
                'newPeer': newPeer.toString(),
              },
              component: ComponentCategory.participant,
              category: EventCategory.telemetry,
            );

            // Store span for lifecycle tracking
            _peerSpans[participantId] = newPeerSpan;

            // Add peer and allow child spans inside it
            _addPeer(newPeer, newPeerSpan);
          } catch (error) {
            if (newPeerSpan != null) {
              SdkTracer.shared.endSpan(
                newPeerSpan,
                category: EventCategory.error,
                success: false,
                message: "Failed handling newPeer: ${error.toString()}",
              );
            }

            SdkTracer.shared.error(
              "Error processing newPeer: ${error.toString()}",
            );
          }

          break;
        }

      case 'peerClosed':
        {
          try {
            final String peerId = notification['peerId'];

            int code = LeaveReason.unknown.code;
            final Map<String, dynamic>? reason =
                notification['reason'] as Map<String, dynamic>?;

            if (reason != null && reason.isNotEmpty) {
              code = reason['code'] ?? LeaveReason.unknown.code;
            }

            final leaveReason = LeaveReason.fromCode(code);

            final SpanScope? peerSpan = _peerSpans[peerId];

            // Emit PARTICIPANT_LEFT event trace
            if (peerSpan != null) {
              SdkTracer.shared.traceEvent(
                spanName: "Emitting PARTICIPANT_LEFT Event",
                parentScope: peerSpan,
                category: EventCategory.telemetry,
                component: ComponentCategory.participant,
              );

              // Emit peer closed trace
              SdkTracer.shared.traceEvent(
                spanName: "Peer $peerId closed",
                attributes: {
                  "leaveReasonCode": leaveReason.code,
                  "leaveReason": leaveReason.message,
                },
                parentScope: peerSpan,
              );
            }

            // Remove peer from meeting
            __removePeer(peerId, leaveReason, peerSpan);

            // End participant lifecycle span
            if (peerSpan != null) {
              SdkTracer.shared.endSpan(
                peerSpan,
                success: true,
                message:
                    "Participant left. Reason: ${leaveReason.message} (Code: ${leaveReason.code})",
              );

              // Remove from map
              _peerSpans.remove(peerId);
            }
          } catch (error) {
            SdkTracer.shared.error(
              "Error handling peerClosed: ${error.toString()}",
            );
          }

          break;
        }

      case 'recordingStarted':
        {
          _eventEmitter.emit('recording-started');
          break;
        }

      case 'recordingStopped':
        {
          _eventEmitter.emit('recording-stopped');
          break;
        }

      case 'recordingStateChanged':
        {
          _recordingState = notification['status'];

          _eventEmitter.emit('recording-state-changed', _recordingState);

          SdkTracer.shared.traceEvent(
            spanName: "Recording State:${_recordingState.toUpperCase()}",
            component: ComponentCategory.meeting,
            category: EventCategory.telemetry,
          );
          break;
        }

      case "livestreamStarted":
        {
          _eventEmitter.emit('livestream-started');

          break;
        }

      case "livestreamStopped":
        {
          _eventEmitter.emit('livestream-stopped');

          break;
        }

      case 'livestreamStateChanged':
        {
          _livestreamState = notification['status'];

          _eventEmitter.emit('livestream-state-changed', _livestreamState);

          SdkTracer.shared.traceEvent(
            spanName:
                'Meeting live stream state changed to: ${notification['status']}',
            attributes: {
              'data': notification['data'].toString(),
            },
            component: ComponentCategory.meeting,
            category: EventCategory.telemetry,
          );

          break;
        }

      case "hlsStarted":
        {
          var downstreamUrl = notification['downstreamUrl'];
          _eventEmitter.emit('hls-started', downstreamUrl);

          break;
        }

      case "hlsStopped":
        {
          _eventEmitter.emit('hls-stopped');

          break;
        }

      case 'hlsStateChanged':
        {
          _hlsState = notification['status'];

          var downstreamUrl = notification['downstreamUrl'];
          var playbackHlsUrl = notification['playbackHlsUrl'];
          var livestreamUrl = notification['livestreamUrl'];

          if (_hlsState == "HLS_STARTED") {
            _hlsDownstreamUrl = downstreamUrl;
            _hlsUrls = {
              "downstreamUrl": downstreamUrl,
              "playbackHlsUrl": playbackHlsUrl,
              "livestreamUrl": livestreamUrl,
            };
          } else if (_hlsState == "HLS_STOPPED") {
            _hlsDownstreamUrl = null;
            _hlsUrls = _hlsUrls = {
              "downstreamUrl": null,
              "playbackHlsUrl": null,
              "livestreamUrl": null,
            };
          }

          _eventEmitter.emit('hls-state-changed', <String, dynamic>{
            "status": _hlsState,
            "downstreamUrl": downstreamUrl,
            "playbackHlsUrl": playbackHlsUrl,
            "livestreamUrl": livestreamUrl,
          });

          SdkTracer.shared.traceEvent(
            spanName: "HLS State:${_hlsState.toString()}",
            attributes: {
              'data': notification.toString(),
            },
            component: ComponentCategory.meeting,
            category: EventCategory.telemetry,
          );

          break;
        }

      case 'hlsPlayableStateChanged':
        {
          bool isPlayable = notification["isPlayable"];
          if (isPlayable) {
            _hlsState = "HLS_PLAYABLE";
            var downstreamUrl = notification['downstreamUrl'];
            var playbackHlsUrl = notification['playbackHlsUrl'];
            var livestreamUrl = notification['livestreamUrl'];

            _hlsUrls = {
              "downstreamUrl": downstreamUrl,
              "playbackHlsUrl": playbackHlsUrl,
              "livestreamUrl": livestreamUrl,
            };
            _eventEmitter.emit('hls-state-changed', <String, dynamic>{
              "status": _hlsState,
              "downstreamUrl": downstreamUrl,
              "playbackHlsUrl": playbackHlsUrl,
              "livestreamUrl": livestreamUrl,
            });

            SdkTracer.shared.traceEvent(
              spanName: 'HLS State: HLS_PLAYABLE',
              attributes: {
                'data': notification.toString(),
              },
              component: ComponentCategory.meeting,
              category: EventCategory.telemetry,
            );
          }

          break;
        }

      case 'whiteboardStarted':
        {
          SdkTracer.shared.traceEvent(
            spanName: 'Emitting WHITEBOARD_STARTED Event',
            attributes: {
              'url': notification['url'],
            },
            category: EventCategory.telemetry,
          );
          _eventEmitter.emit('whiteboard-started', notification['url']);

          break;
        }

      case 'whiteboardStopped':
        {
          SdkTracer.shared.traceEvent(
            spanName: 'Emitting WHITEBOARD_STOPPED Event',
            category: EventCategory.telemetry,
          );
          _eventEmitter.emit('whiteboard-stopped');

          break;
        }

      case "activeSpeaker":
        {
          String? peerId = notification['peerId'];

          if (peerId != _activeSpeakerId) {
            _activeSpeakerId = peerId;
            SdkTracer.shared.traceEvent(
              spanName: 'Active Speaker',
              attributes: {
                'peerId': peerId,
              },
              category: EventCategory.realTime,
            );
            _eventEmitter.emit("speaker-changed", peerId);
          }

          break;
        }
      case "pubsubMessage":
        {
          _eventEmitter.emit("pubsub-message", notification);
          break;
        }

      case "peerModeChanged":
        {
          _eventEmitter
              .emit("participant-mode-changed-${notification['peerId']}", {
            'participantId': notification['peerId'],
            'mode': notification['mode'],
          });
          _eventEmitter.emit("participant-mode-changed", {
            'participantId': notification['peerId'],
            'mode': notification['mode'],
          });

          SdkTracer.shared.traceEvent(
            spanName: 'Participant Mode Changed to ${notification['mode']}',
            parentScope: _peerSpans[notification['peerId']],
            attributes: {
              'peerId': notification['peerId'],
            },
            category: EventCategory.telemetry,
            component: ComponentCategory.meeting,
          );

          break;
        }
      case "restartIce":
        {
          String transportId = notification['transportId'];
          IceParameters iceParameters =
              IceParameters.fromMap(notification['iceParameters']);

          SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
                name:
                    'Websocket Noti: restartIce for transportId :$transportId',
                attributes: {
                  'iceParameters': iceParameters.toString(),
                },
                component: ComponentCategory.meeting,
                category: EventCategory.warn,
              );

          _handleRemoteRestartIce(transportId, iceParameters);
          break;
        }

      case 'transcriptionStateChanged':
        {
          _eventEmitter.emit("transcription-state-changed", notification);

          SdkTracer.shared.traceEvent(
            spanName:
                "Transcription State:${notification['status'].toString().toUpperCase()}",
            component: ComponentCategory.meeting,
            category: EventCategory.telemetry,
          );

          break;
        }

      case 'transcriptionText':
        {
          var data = notification;
          String participantId = data["participantId"];
          String participantName = data["participantName"];
          String text = data["text"];
          int timestamp = data["timestamp"];
          String type = data["type"];

          SdkTracer.shared.traceEvent(
            spanName: "Emitting TRANSCRIPTION_TEXT Event",
            attributes: {
              'participantId': participantId,
              'participantName': participantName,
              'text': text,
              'timestamp': timestamp,
              'type': type,
            },
            component: ComponentCategory.meeting,
            category: EventCategory.realTime,
          );

          TranscriptionText transcriptionText = TranscriptionText(
              participantId: participantId,
              participantName: participantName,
              text: text,
              timestamp: timestamp,
              type: type);

          _eventEmitter.emit("transcription-text", transcriptionText);

          break;
        }
      case 'addCharacter':
        {
          try {
            final Map<String, dynamic> newCharacter =
                Map<String, dynamic>.from(notification);

            final String characterId =
                newCharacter['id'] ?? newCharacter['characterId'] ?? "unknown";

            final String displayName =
                newCharacter['displayName'] ?? "defaultName";

            // Trace event (same pattern as Swift)
            SdkTracer.shared.traceEvent(
              spanName: "Adding Character $characterId in the meeting",
              attributes: {
                "displayName": displayName,
                "data": newCharacter.toString(),
              },
              component: ComponentCategory.meeting,
            );

            // Add character peer
            _addCharacterPeer(newCharacter, null);

            // Emit event (Flutter SDK behavior)
            _eventEmitter.emit("ADD_CHARACTER", notification);
          } catch (error) {
            SdkTracer.shared.error(
              "Error handling addCharacter: ${error.toString()}",
              component: ComponentCategory.meeting,
            );
          }

          break;
        }

      case 'removeCharacter':
        {
          try {
            final String characterId = notification['id'];

            // Trace event (matches Swift behavior)
            SdkTracer.shared.traceEvent(
              spanName: "Removing Character $characterId from the meeting",
              attributes: {
                "data": notification.toString(),
              },
              component: ComponentCategory.meeting,
            );

            // Remove character peer
            __removePeer(characterId, LeaveReason.unknown, null);

            // Emit event (Flutter SDK behavior)
            _eventEmitter.emit("REMOVE_CHARACTER", notification);
          } catch (error) {
            SdkTracer.shared.error(
              "Error handling removeCharacter: ${error.toString()}",
              component: ComponentCategory.meeting,
            );
          }

          break;
        }
      case "characterStateChanged":
        {
          _eventEmitter.emit("CHARACTER_STATE_CHANGED", notification);
          SdkTracer.shared.traceEvent(
            spanName:
                'Emitted CHARACTER_STATE_CHANGED, status : : ${notification['status']}',
            attributes: {
              'data': notification.toString(),
            },
            component: ComponentCategory.meeting,
          );

          break;
        }
      case 'characterMessage':
        {
          _eventEmitter.emit(
              "CHARACTER_MESSAGE", CharacterMessage.fromJson(notification));

          break;
        }
      case 'userMessage':
        {
          _eventEmitter.emit(
              "USER_MESSAGE", UserMessage.fromJson(notification));

          break;
        }
      case 'mediaRelayStarted':
        {
          String meetingId = notification['meetingId'];
          SdkTracer.shared.traceEvent(
            spanName: 'Emitting MEDIA_RELAY_STARTED Event',
            attributes: {
              'meetingId': meetingId,
            },
            category: EventCategory.telemetry,
          );
          _eventEmitter.emit('media-relay-started', meetingId);
        }

      case "mediaRelayStopped":
        {
          String meetingId = notification['meetingId'];
          String reason = notification['reason'];
          SdkTracer.shared.traceEvent(
            spanName: 'Emitting MEDIA_RELAY_STOPPED Event',
            attributes: {
              'meetingId': meetingId,
              'reason': reason,
            },
            category: EventCategory.telemetry,
          );
          _eventEmitter.emit('media-relay-stopped', meetingId, reason);
          break;
        }

      case "mediaRelayError":
        {
          String meetingId = notification['meetingId'];
          String reason = notification['reason'];
          SdkTracer.shared.traceEvent(
            spanName: 'Emitting MEDIA_RELAY_ERROR Event',
            attributes: {
              'meetingId': meetingId,
              'reason': reason,
            },
            category: EventCategory.telemetry,
          );
          _eventEmitter.emit('media-relay-error', meetingId, reason);
          break;
        }
      case "mediaRelayRequestResponse":
        {
          var decidedBy = notification['decidedBy'];
          var decision = notification['decision'];
          var meetingId = notification['meetingId'];
          SdkTracer.shared.traceEvent(
            spanName: 'Emitting MEDIA_RELAY_REQUEST_RESPONSE Event',
            attributes: {
              'decidedBy': decidedBy,
              'decision': decision,
              'meetingId': meetingId,
            },
            category: EventCategory.telemetry,
          );
          _eventEmitter.emit(
              'media-relay-request-response', decidedBy, decision, meetingId);
          break;
        }

      case "mediaRelayRequestReceived":
        {
          String meetingId = notification['meetingId'];
          String peerId = notification['peerId'];
          String displayName = notification['displayName'];
          SdkTracer.shared.traceEvent(
            spanName: 'Emitting MEDIA_RELAY_REQUEST_RECEIVED Event',
            attributes: {
              'meetingId': meetingId,
              'peerId': peerId,
              'displayName': displayName,
            },
            category: EventCategory.telemetry,
          );
          void accept() {
            _handleMediaRelayRequest(peerId, "allowed", meetingId);
          }

          void reject() {
            _handleMediaRelayRequest(peerId, "denied", meetingId);
          }

          _eventEmitter.emit('media-relay-request-received', meetingId, peerId,
              displayName, accept, reject);
          break;
        }

      case "translationStateChanged":
        {
          String state = notification['status'];

          if (state == "TRANSLATION_STARTING") {
            _eventEmitter.emit(
              'translation-state-changed',
              TranslationState.TRANSLATION_STARTING,
            );
          } else if (state == "TRANSLATION_STARTED") {
            _eventEmitter.emit(
              'translation-state-changed',
              TranslationState.TRANSLATION_STARTED,
            );
          } else if (state == "TRANSLATION_STOPPED") {
            _eventEmitter.emit(
              'translation-state-changed',
              TranslationState.TRANSLATION_STOPPED,
            );
          } else if (state == "TRANSLATION_STOPPING") {
            _eventEmitter.emit(
              'translation-state-changed',
              TranslationState.TRANSLATION_STOPPING,
            );
          }

          break;
        }

      case "translationText":
        {
          var data = notification;
          String participantId = data['participantId'];
          double timestamp = data['timestamp'];
          String participantName = data['participantName'];
          String participantLanguage = data['participantLanguage'];
          String language = data['language'];
          String text = data['text'];
          String type = data['type'];

          if (_translationLanguage == language) {
            TranslationText translationText = TranslationText(
              language: language,
              participantId: participantId,
              timestamp: timestamp,
              participantLanguage: participantLanguage,
              type: type,
              text: text,
              participantName: participantName,
            );

            _eventEmitter.emit('translation-text', translationText);
          }

          break;
        }

      case "translationLanguageChanged":
        {
          String lan = notification["language"];
          if (localParticipant.id == notification["peerId"]) {
            _translationLanguage = lan;
            _eventEmitter.emit("translation-language-changed", lan);
          }
          break;
        }
      case "realtimeStoreValueChanged":
        {
          String key = notification["key"];
          String? value = notification["value"];
          String updatedPeerIdBy = notification["updatedBy"];
          Participant? updatedBy;
          // try catch as participantId can be null
          try {
            if (localParticipant.id == updatedPeerIdBy) {
              updatedBy = localParticipant;
            } else {
              updatedBy = participants[updatedPeerIdBy];
            }
          } catch (_) {}

          _relatimeStoreEventEmitter.emit(key, {
            "value": value,
            "updatedBy": updatedBy,
          });

          break;
        }
      case "agentStateChanged":
        {
          // Emit to specific agent participant listener
          var peerId = notification['peerId'] ?? notification['participantId'];
          if (peerId != null) {
            _eventEmitter.emit('AGENT_STATE_CHANGED_$peerId', notification);
          }

          break;
        }

      case "agentTranscript":
        {
          var peerId = notification['peerId'] ?? notification['participantId'];

          final Participant? participant = peerId == localParticipant.id
              ? localParticipant
              : participants[peerId];

          TranscriptionSegment agentSegment = TranscriptionSegment(
            text: notification['text'],
            timestamp: notification['timestamp'],
          );

          if (peerId != null) {
            _eventEmitter.emit(
                'AGENT_TRANSCRIPTION_$agentPeerId', participant, agentSegment);
          }

          break;
        }
      case 'agentMetrics':
        {
          var peerId = notification['peerId'];
          if (peerId != null) {
            final data = Map<String, dynamic>.from(notification);
            data.remove('peerId');
            _eventEmitter.emit('AGENT_METRICS_$peerId', data);
          }
          break;
        }

      case 'unsupportedCodecAdded':
        {
          final String? mime =
              (notification['codec'] as String?)?.toLowerCase();

          final String? consumerPeerId = (notification['consumerPeerId'] ??
              notification['peerId']) as String?;

          final VideoCodec? unsupported = _mimeToVideoCodec[mime];

          if (unsupported == null) {
            break;
          }

          _unsupportedCodecs.add(unsupported);

          _codecChangeParticipantId = consumerPeerId;

          final VideoCodec currentCodec = _customVideoTrackConfig.codec;

          if (_camEnabled &&
              _codecSwitchEnabled &&
              currentCodec != VideoCodec.VP8) {
            await _changeWebcamCodec(currentCodec);
          }

          break;
        }
      default:
        break;
    }
  }

  void _handleRemoteRestartIce(
      String transportId, IceParameters iceParameters) async {
    // Restart ICE on the matching transport
    if (_sendTransport?.id == transportId) {
      _sendTransport!.restartIce(iceParameters);
    }
    if (_recvTransport?.id == transportId) {
      _recvTransport!.restartIce(iceParameters);
    }

    try {
      // Send iceRestarted confirmation to server
      await _webSocket!.sendRequest('iceRestarted', {
        "transportId": transportId,
      });
    } catch (error) {
      SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
            name: 'Error while RestartIce request.',
            category: EventCategory.error,
            attributes: {
              'error': error.toString(),
            },
            component: ComponentCategory.transport,
          );

      _eventEmitter.emit("error", VideoSDKErrors[3022]);
    }
  }

  Future<Map<String, dynamic>?> _getCpuAndMemoryUsage() async {
    // Return cached value if it is still fresh — avoids two platform-channel
    // roundtrips on every statsData server request (T10).
    if (_cachedUsage != null &&
        _usageFetchedAt != null &&
        DateTime.now().difference(_usageFetchedAt!) < _usageCacheTtl) {
      return _cachedUsage;
    }
    try {
      final cpuUsage = await _channel.invokeMethod('getCpuUsage');
      final memoryUsage = await _channel.invokeMethod('getMemoryUsage');
      _cachedUsage = {
        "cpuUsage": cpuUsage,
        "memoryUsage": Platform.isIOS ? memoryUsage['used'] : memoryUsage,
      };
      _usageFetchedAt = DateTime.now();
      return _cachedUsage;
    } catch (_) {}
    return null;
  }

//
  Future<void> _joinRoom() async {
    if (_webSocket == null || _closed) {
      return;
    }
    try {
      _device = Device();

      SpanScope? routerScope = SdkTracer.shared.startSpan(
        spanName: 'Loading Device Capabilities',
        parentSpan: _joinSpanScope,
        component: ComponentCategory.meeting,
      );

      // Capture into a local so that _close() nulling the field doesn't
      // affect us, then check _closed after the await to bail out if the
      // room was torn down while we were waiting.
      final rtpCapsFuture = _rtpCapsPrefetch ??
          _webSocket!.sendRequest('getRouterRtpCapabilities', {});
      _rtpCapsPrefetch = null;
      dynamic routerRtpCapabilities = await rtpCapsFuture;
      if (_closed) return;

      final rtpCapabilities = RtpCapabilities.fromMap(routerRtpCapabilities);
      rtpCapabilities.headerExtensions
          .removeWhere((he) => he.uri == 'urn:3gpp:video-orientation');

      await _device!.load(routerRtpCapabilities: rtpCapabilities);

      SdkTracer.shared.endSpan(
        routerScope,
        success: true,
        message:
            'Router Capabilities Loaded ${routerRtpCapabilities.toString()}',
      );

      if ((_device!.canProduce(RTCRtpMediaType.RTCRtpMediaTypeAudio) == true ||
              _device!.canProduce(RTCRtpMediaType.RTCRtpMediaTypeVideo) ==
                  true) &&
          (_mode == Mode.SEND_AND_RECV || _mode == Mode.CONFERENCE)) {
        _produce = true;
      }

      // eagerError: if one transport fails, propagate immediately instead of
      // waiting for the other to finish. The outer catch calls _close() which
      // tears down whichever transport was already created.
      await Future.wait(
        [
          _createSendTransport(parentSpan: _joinSpanScope),
          _createReceiveTransport(parentSpan: _joinSpanScope),
        ],
        eagerError: true,
      );

      _metaData = {
        ..._metaData,
        "translationLanguage": _translationLanguage,
        "speakingLanguage": _speakingLanguage,
        "enableAgentEvents": true,
      };

      Map response = await _webSocket!.sendRequest('join', {
        'displayName': localParticipant.displayName,
        'device': {
          'name': "Flutter",
          'flag': 'flutter',
          'version': sdkVersion,
        },
        'rtpCapabilities': _device!.rtpCapabilities.toMap(),
        'sctpCapabilities': _device!.sctpCapabilities.toMap(),
        'deviceInfo': deviceInfo,
        'metaData': _metaData,
        'autoConsume': _autoConsume,
        'batchingEnabled': _enableBatching,
      });
      response['peers'].forEach((value) {
        _addPeer(value, _joinSpanScope);
      });

      _addUnsupportedCodecs(response['unsupportedCodecs']?.cast<String>());

      if (!kIsWeb) {
        if (Platform.isIOS) {
          VideoSDK.setAppleAudioConfiguration();
        }
      }

      //Request permission before setting default device for web
      //As in web, device labels and ids are not available w/o media permissions.
      bool audioPermission = false;
      bool videoPermission = false;

      // check browser is Firefox or not
      bool isFirefox =
          deviceInfo['browserUserAgent']?['browser']?['name'] == "Firefox";

      if (!isFirefox && kIsWeb) {
        if (_produce) {
          List<Map<String, bool>> permResults;
          if (_permissionPrefetch != null) {
            permResults = await _permissionPrefetch!;
            _permissionPrefetch = null;
          } else {
            permResults = await Future.wait([
              if (_micEnabled)
                VideoSDK.requestPermissions(Permissions.audio)
              else
                Future.value(<String, bool>{'audio': false}),
              if (_camEnabled)
                VideoSDK.requestPermissions(Permissions.video)
              else
                Future.value(<String, bool>{'video': false}),
            ]);
          }
          audioPermission = permResults[0]['audio']!;
          videoPermission = permResults[1]['video']!;
          _micEnabled = audioPermission;
          _camEnabled = videoPermission;
        }
      }

      await _getDefaultDevices(_defaultCameraIndex);

      _joined = true;
      _rejoinInProgress = false;

      _eventEmitter.emit('meeting-joined');

      SdkTracer.shared.traceEvent(
          spanName: 'Emitting MEETING_JOINED Event',
          parentScope: _joinSpanScope,
          component: ComponentCategory.meeting,
          category: EventCategory.telemetry);

      try {
        if (_produce) {
          if (_micEnabled) {
            await _enableMicImpl(
                customTrack: _customMicrophoneAudioTrack,
                parentSpan: _joinSpanScope);
          } else {
            if (_customMicrophoneAudioTrack != null) {
              _customMicrophoneAudioTrack?.dispose();
              _customMicrophoneAudioTrack = null;
            }
          }
          if (_camEnabled) {
            await _enableCamImpl(
                customTrack: _customCameraVideoTrack,
                parentSpan: _joinSpanScope);
          } else {
            if (_customCameraVideoTrack != null) {
              _customCameraVideoTrack?.dispose();
              _customCameraVideoTrack = null;
            }
          }
        } else {
          if (_customMicrophoneAudioTrack != null) {
            _customMicrophoneAudioTrack?.dispose();
            _customMicrophoneAudioTrack = null;
          }
          if (_customCameraVideoTrack != null) {
            _customCameraVideoTrack?.dispose();
            _customCameraVideoTrack = null;
          }
        }

        // Complete new SdkTracer span AFTER mic/WebCam enablement
        try {
          if (_joinSpanScope != null) {
            SdkTracer.shared.endSpan(
              _joinSpanScope!,
              success: true,
              message: 'Room Joined',
            );
          }
        } catch (_) {}

        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'notification_share_screen',
            channelName: 'Foreground Notification',
            channelDescription:
                'This notification appears when the foreground service is running.',
            channelImportance: NotificationChannelImportance.LOW,
            priority: NotificationPriority.LOW,
          ),
          iosNotificationOptions: const IOSNotificationOptions(
            showNotification: true,
            playSound: false,
          ),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.repeat(5000),
            autoRunOnBoot: true,
            allowWifiLock: true,
          ),
        );
      } catch (err) {
        //
        SdkTracer.shared.warn(
            "Error in foreground notification \n ${err.toString()}",
            component: ComponentCategory.meeting);
        //
        log(err.toString());
      }
    } catch (error) {
      //
      SdkTracer.shared.error("Error in joinRoom() \n ${error.toString()}",
          component: ComponentCategory.meeting);

      //
      log(error.toString());

      // Complete new SdkTracer span on error
      try {
        if (_joinSpanScope != null) {
          SdkTracer.shared.endSpan(
            _joinSpanScope!,
            category: EventCategory.error,
            success: false,
            message: 'Room Join Failed: ${error.toString()}',
          );
        }
      } catch (_) {}

      _close(LeaveReason.joinRoomFailed);
    }
  }

  Future<void> _createSendTransport({Object? parentSpan}) async {
    if (_webSocket == null) {
      return;
    }

    SpanScope? sendTransportScope;
    try {
      if (_produce) {
        sendTransportScope = SdkTracer.shared.startSpan(
          spanName: 'Creating Send Media Transport',
          parentSpan: parentSpan,
          component: ComponentCategory.media,
        );

        Map transportInfo =
            await _webSocket!.sendRequest('createWebRtcTransport', {
          'preferredProtocol': _preferredProtocol,
          'producing': true,
          'consuming': false,
          'sctpCapabilities': _device!.sctpCapabilities.toMap(),
        });

        _sendTransport = _device!.createSendTransportFromMap(
          transportInfo,
          producerCallback: _producerCallback,
          iceServers: _iceServers,
        );
        // Trace state stored as plain maps so they are sendable to an isolate.
        final Map<String, Map<String, dynamic>> outbTraces = HashMap();
        final Map<String, Map<String, dynamic>> remoteInbTraces = HashMap();
        double? _ewmaRttInMs;
        bool _congested = false;
        bool _cpuLimited = false;
        bool _bandwidthLimited = false;

        _sendTransportInternal = Timer.periodic(
          const Duration(seconds: 1),
          (timer) async {
            // Platform-channel call must stay on the main isolate.
            List<dynamic>? rawReports;
            try {
              rawReports = await _sendTransport?.getStats() as List<dynamic>?;
            } catch (_) {
              return;
            }
            if (rawReports == null) return;

            // Lightweight serialisation — converts native StatsReport wrappers
            // to plain Dart maps so they can be sent to a background isolate.
            final plainReports = rawReports.map((r) {
              Map<String, dynamic> values = {};
              try {
                values = Map<String, dynamic>.from(r.values as Map? ?? {});
              } catch (_) {}
              return <String, dynamic>{
                'type': r.type as String? ?? '',
                'id': r.id as String? ?? '',
                'values': values,
              };
            }).toList();

            // Snapshot current trace state (copies so the isolate owns them).
            final outbSnapshot =
                Map<String, Map<String, dynamic>>.from(outbTraces);
            final remoteInbSnapshot =
                Map<String, Map<String, dynamic>>.from(remoteInbTraces);

            // ── Background isolate: all the loop work ──────────────────────
            Map<String, dynamic>? result;
            try {
              result = await runRttStats(
                  plainReports, outbSnapshot, remoteInbSnapshot);
            } catch (_) {
              return;
            }
            if (result == null) return;

            // ── Back on main isolate: write state and emit events ──────────
            outbTraces
              ..clear()
              ..addAll((result['outbTraces'] as Map)
                  .cast<String, Map<String, dynamic>>());
            remoteInbTraces
              ..clear()
              ..addAll((result['remoteInbTraces'] as Map)
                  .cast<String, Map<String, dynamic>>());

            final avgRoundTripTimeInMs = result['avgRttMs'] as double;
            final isCurrentlyBandwidthLimited =
                result['isBandwidthLimited'] as bool;
            final isCurrentlyCPULimited = result['isCpuLimited'] as bool;

            if (avgRoundTripTimeInMs.isNaN) return;
            _ewmaRttInMs ??= avgRoundTripTimeInMs;

            try {
              // Check for congestion detection
              if (!_congested &&
                  isCurrentlyBandwidthLimited &&
                  avgRoundTripTimeInMs - _ewmaRttInMs! > 50) {
                SdkTracer.shared
                    .to(OutputTarget.toBackend, OutputTarget.toConsole)
                    .traceEvent(
                      name:
                          'Network Congestion detected, the network is bandwidth limited and the round trip time is increasing.',
                      category: EventCategory.warn,
                      component: ComponentCategory.media,
                      attributes: {
                        'avgRoundTripTimeInMs': avgRoundTripTimeInMs,
                        'ewmaRttInMs': _ewmaRttInMs,
                      },
                      dashboardLog: false,
                    );
                _congested = true;
                _eventEmitter.emit('quality-limitation', 'congestion',
                    'detected', DateTime.now().millisecondsSinceEpoch);
              } else if (_congested &&
                  avgRoundTripTimeInMs - _ewmaRttInMs! < 30) {
                SdkTracer.shared
                    .to(OutputTarget.toBackend, OutputTarget.toConsole)
                    .traceEvent(
                      name:
                          'Network Congestion resolved, the round trip time is back to normal',
                      category: EventCategory.warn,
                      component: ComponentCategory.media,
                      attributes: {
                        'avgRoundTripTimeInMs': avgRoundTripTimeInMs,
                        'ewmaRttInMs': _ewmaRttInMs,
                      },
                      dashboardLog: false,
                    );
                _congested = false;
                _eventEmitter.emit('quality-limitation', 'congestion',
                    'resolved', DateTime.now().millisecondsSinceEpoch);
              }

              // Check for bandwidth limitation
              if (isCurrentlyBandwidthLimited && !_bandwidthLimited) {
                SdkTracer.shared
                    .to(OutputTarget.toBackend, OutputTarget.toConsole)
                    .traceEvent(
                  name: 'Bandwidth Limitation detected',
                  category: EventCategory.warn,
                  component: ComponentCategory.media,
                  dashboardLog: true,
                  attributes: {
                    'avgRoundTripTimeInMs': avgRoundTripTimeInMs,
                    'ewmaRttInMs': _ewmaRttInMs,
                  },
                );
                _bandwidthLimited = true;
                _eventEmitter.emit('quality-limitation', 'bandwidth',
                    'detected', DateTime.now().millisecondsSinceEpoch);
              } else if (!isCurrentlyBandwidthLimited && _bandwidthLimited) {
                SdkTracer.shared
                    .to(OutputTarget.toBackend, OutputTarget.toConsole)
                    .traceEvent(
                  name: 'Bandwidth Limitation resolved',
                  category: EventCategory.warn,
                  component: ComponentCategory.media,
                  dashboardLog: true,
                  attributes: {
                    'avgRoundTripTimeInMs': avgRoundTripTimeInMs,
                    'ewmaRttInMs': _ewmaRttInMs,
                  },
                );
                _bandwidthLimited = false;
                _eventEmitter.emit('quality-limitation', 'bandwidth',
                    'resolved', DateTime.now().millisecondsSinceEpoch);
              }

              // Update EWMA
              _ewmaRttInMs = 0.9 * _ewmaRttInMs! + 0.1 * avgRoundTripTimeInMs;

              // Check for CPU limitation
              if (!_cpuLimited && isCurrentlyCPULimited) {
                _cpuLimited = true;
                _eventEmitter.emit('quality-limitation', 'cpu', 'detected',
                    DateTime.now().millisecondsSinceEpoch);
                SdkTracer.shared
                    .to(OutputTarget.toBackend, OutputTarget.toConsole)
                    .traceEvent(
                  name: 'CPU Limitation detected',
                  category: EventCategory.warn,
                  component: ComponentCategory.media,
                  attributes: {
                    'avgRoundTripTimeInMs': avgRoundTripTimeInMs,
                    'ewmaRttInMs': _ewmaRttInMs,
                  },
                );
              } else if (_cpuLimited && !isCurrentlyCPULimited) {
                _cpuLimited = false;
                _eventEmitter.emit('quality-limitation', 'cpu', 'resolved',
                    DateTime.now().millisecondsSinceEpoch);
                SdkTracer.shared
                    .to(OutputTarget.toBackend, OutputTarget.toConsole)
                    .traceEvent(
                  name: 'CPU Limitation resolved',
                  category: EventCategory.warn,
                  component: ComponentCategory.media,
                  attributes: {
                    'avgRoundTripTimeInMs': avgRoundTripTimeInMs,
                    'ewmaRttInMs': _ewmaRttInMs,
                  },
                );
              }
            } catch (_) {}
          },
        );
        _sendTransport!.on('connect', (Map data) {
          try {
            SdkTracer.shared.traceEvent(
              spanName: 'Establishing connection: ICE+DTLS',
              parentScope: sendTransportScope,
              component: ComponentCategory.media,
            );

            _webSocket!
                .sendRequest('connectWebRtcTransport', {
                  'transportId': _sendTransport!.id,
                  'dtlsParameters': data['dtlsParameters'].toMap(),
                })
                .then(data['callback'])
                .catchError((error) {
                  data['callback'];
                  //
                });
          } catch (_) {}
        });

        _sendTransport!.on('produce', (Map data) async {
          try {
            SdkTracer.shared.traceEvent(
              spanName: 'Starting ${data['kind']} Stream Negotiation',
              parentScope: sendTransportScope,
              component: ComponentCategory.transport,
            );
          } catch (_) {}

          try {
            // Offload the deep recursive toMap() serialization to a background
            // isolate so it doesn't block the UI thread during track publish.
            final rtpParamsMap =
                await compute(_rtpParametersToMap, data['rtpParameters']);

            Map response = await _webSocket!.sendRequest(
              'produce',
              {
                'transportId': _sendTransport!.id,
                'kind': data['kind'],
                'rtpParameters': rtpParamsMap,
                if (data['appData'] != null)
                  'appData': Map<String, dynamic>.from(data['appData'])
              },
            );

            data['callback'](response['id']);
          } catch (error) {
            data['errback'](error);
          }
        });

        _sendTransport!.on('producedata', (data) async {
          try {
            Map response = await _webSocket!.sendRequest('produceData', {
              'transportId': _sendTransport!.id,
              'sctpStreamParameters': data['sctpStreamParameters'].toMap(),
              'label': data['label'],
              'protocol': data['protocol'],
              'appData': data['appData'],
            });
            data['callback'](response['id']);
          } catch (error) {
            data['errback'](error);
            //
            SdkTracer.shared.error(
                "Error in sendTransport produceData \n ${error.toString()}",
                component: ComponentCategory.media);
          }
        });

        _sendTransport!.on('connectionstatechange', (connectionState) {
          try {
            final state = connectionState
                .toString()
                .split(':')
                .last
                .replaceAll('}', '')
                .trim()
                .toUpperCase();

            SdkTracer.shared.traceEvent(
              spanName: 'Media Transport State: $state',
              parentScope: sendTransportScope,
              component: ComponentCategory.transport,
            );
          } catch (_) {}

          if (connectionState['connectionState'] == 'failed') {
            _failedclosed();
          }
        });

        var reportCounter = 0;
        // Serialization guard: prevents overlapping async handlers from
        // mutating _stats / _latestStats concurrently.
        Future<void> _sendStatsLock = Future.value();
        Probe probe =
            _metricsCollector!.addNewProbe(_sendTransport!, "sendTransport");
        _eventEmitter.on("stats-collected-${probe.id}", (dynamic rawReport) {
          _sendStatsLock = _sendStatsLock.then((_) async {
            try {
              final report = rawReport as Map<String, dynamic>;

              // Extract track/producer IDs as plain strings before the isolate
              // (Producer.track is a native handle — not isolate-sendable).
              final micTrackId = _micProducer?.track.id;
              final micProducerId = _micProducer?.id;
              final cameraTrackId = _cameraProducer?.track.id;
              final cameraProducerId = _cameraProducer?.id;
              final shareTrackId = _screenshareProducer?.track.id;
              final shareProducerId = _screenshareProducer?.id;
              final counter = reportCounter;

              // ── Background isolate: filter stats by track ID ───────────────
              final result = await runProducerStats(
                report: report,
                micTrackId: micTrackId,
                micProducerId: micProducerId,
                cameraTrackId: cameraTrackId,
                cameraProducerId: cameraProducerId,
                shareTrackId: shareTrackId,
                shareProducerId: shareProducerId,
                reportCounter: counter,
              );

              // ── Back on main isolate: apply results ────────────────────────
              _latestStats[micProducerId] = result['latestMicStats'];
              _latestStats[cameraProducerId] = result['latestCameraStats'];
              _latestStats[shareProducerId] = result['latestShareStats'];

              _stats['producerStats'] ??= {};
              _stats['producerStats']['audio'] ??= [];
              _stats['producerStats']['video'] ??= [];
              _stats['producerStats']['share'] ??= [];

              if (result['audioStatToAdd'] != null) {
                _stats['producerStats']['audio'].add(result['audioStatToAdd']);
              }
              if (result['shouldRecord'] == true && _cameraProducer != null) {
                _stats['producerStats']['video'].add({
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                  'stats': _latestStats[cameraProducerId],
                });
              }
              if (result['shouldRecord'] == true &&
                  _screenshareProducer != null) {
                _stats['producerStats']['share'].add({
                  'timestamp': DateTime.now().millisecondsSinceEpoch,
                  'stats': _latestStats[shareProducerId],
                });
              }
              reportCounter++;
            } catch (error) {
              SdkTracer.shared.debug(
                  "Error in stats-collected \n ${error.toString()}",
                  component: ComponentCategory.media);
              log("PART ERRO :: ${error.toString()}");
            }
          }); // end _sendStatsLock.then
        });
        probe.start();
        _sendTransport!.observer.on('close', () {
          probe.stop();
          _metricsCollector!.removeExistingProbe(probe);
        });

        SdkTracer.shared.endSpan(
          sendTransportScope,
          success: true,
          message: 'Send Transport Created Successfully',
        );
      }
    } catch (error) {
      SdkTracer.shared.error(
          "Error in _createSendTransport ${error.toString()}",
          component: ComponentCategory.media);

      SdkTracer.shared.endSpan(
        sendTransportScope,
        category: EventCategory.error,
        success: false,
        message: 'Send Transport failed with error: ${error.toString()}',
      );
    }
  }

  Future<void> _createReceiveTransport({Object? parentSpan}) async {
    if (_webSocket == null) {
      return;
    }

    SpanScope? receiveTransportScope;
    try {
      if (_consume) {
        receiveTransportScope = SdkTracer.shared.startSpan(
          spanName: 'Creating Recieve Media Transport',
          parentSpan: parentSpan,
          component: ComponentCategory.media,
        );

        Map transportInfo = await _webSocket!.sendRequest(
          'createWebRtcTransport',
          {
            'preferredProtocol': _preferredProtocol,
            'producing': false,
            'consuming': true,
            'sctpCapabilities': _device!.sctpCapabilities.toMap(),
          },
        );

        _recvTransport = _device!.createRecvTransportFromMap(
          transportInfo,
          consumerCallback: _consumerCallback,
          iceServers: _iceServers,
        );

        _recvTransport!.on(
          'connect',
          (data) {
            try {
              SdkTracer.shared.traceEvent(
                spanName: 'Establishing connection: ICE+DTLS',
                parentScope: receiveTransportScope,
                component: ComponentCategory.media,
              );
            } catch (_) {}

            _webSocket!
                .sendRequest(
                  'connectWebRtcTransport',
                  {
                    'transportId': _recvTransport!.id,
                    'dtlsParameters': data['dtlsParameters'].toMap(),
                  },
                )
                .then(data['callback'])
                .catchError((error) {
                  data['callback'];
                  //
                  SdkTracer.shared.error(
                      "Error in receiveTransport connect \n ${error.toString()}",
                      component: ComponentCategory.media);
                });
          },
        );

        _recvTransport!.on('connectionstatechange', (connectionState) {
          try {
            final state = connectionState
                .toString()
                .split(':')
                .last
                .replaceAll('}', '')
                .trim()
                .toUpperCase();

            SdkTracer.shared.traceEvent(
              spanName: '_recvTransport Event: $state',
              parentScope: receiveTransportScope,
              component: ComponentCategory.media,
            );
          } catch (_) {}

          if (connectionState['connectionState'] == 'failed') {
            _failedclosed();
          }
        });

        var reportCounter = 0;
        // Serialization guard: prevents overlapping async handlers from
        // mutating traces / _stats / participants concurrently (issue #1).
        Future<void> _recvStatsLock = Future.value();
        Probe probe =
            _metricsCollector!.addNewProbe(_recvTransport!, "transport");
        final Map<dynamic, dynamic> traces = HashMap();
        final Map<String, dynamic> freezeTraces = HashMap();
        final Map<String, dynamic> freezeTimestamps = HashMap();
        final Map<String, dynamic> freezeResolvedEmitted = HashMap();
        _eventEmitter.on("stats-collected-${probe.id}", (dynamic rawReport) {
          _recvStatsLock = _recvStatsLock.then((_) async {
            try {
              final report = rawReport as Map<String, dynamic>;

              // Build a plain-data snapshot of the current consumer map so we
              // don't send native handles (Consumer.track, Consumer.stream…) to
              // the background isolate.
              final consumerSnapshot = <String, Map<String, dynamic>>{};
              _recvTransport?.consumers.forEach((consumerId, consumer) {
                consumerSnapshot[consumerId] = {
                  'peerId': consumer.peerId,
                  'kind': consumer.kind ?? '',
                  'id': consumer.id,
                  // Only copy the primitive fields the isolate actually reads
                  // (see _resolveConsumerType). Sending the full appData risks
                  // including non-sendable objects (Participant, Stream, native
                  // refs) which would crash Isolate.run.
                  'appData': <String, dynamic>{
                    'share': consumer.appData['share'],
                  },
                  'nativeTrackId': consumer.track.id,
                };
              });

              final counter = reportCounter;

              // ── Background isolate: process audio/video stats ──────────────
              final result = await runConsumerStats(
                report: report,
                consumerSnapshot: consumerSnapshot,
                traces: Map<dynamic, dynamic>.from(traces),
                freezeTraces: Map<String, dynamic>.from(freezeTraces),
                freezeTimestamps: Map<String, dynamic>.from(freezeTimestamps),
                freezeResolvedEmitted:
                    Map<String, dynamic>.from(freezeResolvedEmitted),
                reportCounter: counter,
              );

              // ── Back on main isolate: write state ─────────────────────────
              traces
                ..clear()
                ..addAll(result['traces'] as Map);
              freezeTraces
                ..clear()
                ..addAll(
                    (result['freezeTraces'] as Map).cast<String, dynamic>());
              freezeTimestamps
                ..clear()
                ..addAll((result['freezeTimestamps'] as Map)
                    .cast<String, dynamic>());
              freezeResolvedEmitted
                ..clear()
                ..addAll((result['freezeResolvedEmitted'] as Map)
                    .cast<String, dynamic>());

              // Apply accumulated stat entries
              _stats['consumerStats'] ??= {};
              for (final entry
                  in result['statsToAdd'] as List<Map<String, dynamic>>) {
                final peerId = entry['peerId'] as String;
                final type = entry['type'] as String;
                _stats['consumerStats'][peerId] ??= {};
                _stats['consumerStats'][peerId][type] ??= [];
                _stats['consumerStats'][peerId][type].add(entry['stat']);
              }

              // Apply latest-stats updates
              for (final entry in (result['latestStatsUpdates']
                      as Map<String, List<dynamic>>)
                  .entries) {
                _latestStats[entry.key] = entry.value;
              }

              // Dispatch freeze / stutter events (requires Participant lookup —
              // must happen on the main isolate).
              for (final event
                  in result['events'] as List<Map<String, dynamic>>) {
                final peerId = event['peerId'] as String;
                final streamId = event['streamId'] as String;
                final action = event['action'] as String;
                participants[peerId]
                    ?.handleStreamStateChanged(action, streamId);
              }

              reportCounter++;
            } catch (error) {
              SdkTracer.shared.debug(
                  "Error in recv stats-collected \n ${error.toString()}",
                  component: ComponentCategory.media);
              log("RECV STATS ERROR :: ${error.toString()}");
            }
          }); // end _recvStatsLock.then
        });
        probe.start();
        _recvTransport?.observer.on('close', () {
          probe.stop();
          _metricsCollector!.removeExistingProbe(probe);
        });

        SdkTracer.shared.endSpan(
          receiveTransportScope,
          success: true,
          message: 'Receive Transport Created Successfully',
        );
      }
    } catch (error) {
      SdkTracer.shared.error("Error in receiveTransport ${error.toString()}",
          component: ComponentCategory.media);

      SdkTracer.shared.endSpan(
        receiveTransportScope,
        category: EventCategory.error,
        success: false,
        message: 'Receive Transport failed with error: ${error.toString()}',
      );
    }
  }

  /// Ends the current running room session.
  ///
  /// - Calling `end()` forcefully terminates the room for everyone.
  /// All joined participants, including the local participant,
  /// will immediately leave the session.
  ///
  /// ## Events associated with end()
  ///
  /// - All participants, including the local participant, will receive
  ///   an [Events.roomLeft] event.
  ///
  /// ### **Example**
  /// ```dart
  /// // End the meeting for all participants
  /// await room.end();
  ///
  /// // Handle room end event
  /// room.on(Events.roomLeft, () {
  ///   print('Room session has ended');
  ///   // Perform cleanup if needed
  ///   room.dispose();
  /// });
  ///
  /// // End meeting from a button
  /// ElevatedButton(
  ///   onPressed: () async {
  ///     await room.end();
  ///     Navigator.pop(context);
  ///   },
  ///   child: Text('End Meeting'),
  /// )
  /// ```
  void end() {
    if (!_ensureLeavable("end", allowWhileReconnecting: false)) return;
    _end();
  }

  void _end() {
    if (_closed) {
      return;
    }
    try {
      if (_webSocket != null) {
        _webSocket!.sendRequest('closeRoom', {});
      } else {
        return;
      }
    } catch (e) {
      //
      SdkTracer.shared.traceEvent(
        spanName: "Error in end() -> ${e.toString()}",
        category: EventCategory.error,
        success: false,
      );
    }
  }

  /// Leaves the current running room session.
  ///
  /// - When a participant leaves the room, appropriate events are emitted to notify
  /// all participants in the session.
  ///
  /// ## Events associated with leave()
  ///
  /// - Local participant will receive a [Events.roomLeft] event
  /// - All remote participants will receive a [Events.participantLeft] event with
  ///   `participantId` string from the event handler
  ///
  /// ### **Example**
  /// ```dart
  /// // Simple leave
  /// await room.leave();
  ///
  /// // Leave with cleanup
  /// room.on(Events.roomLeft, () {
  ///   print('Successfully left the room');
  ///   // Dispose resources
  ///   room.dispose();
  /// });
  ///
  /// await room.leave();
  ///
  /// // Handle leave in a button
  /// ElevatedButton(
  ///   onPressed: () async {
  ///     await room.leave();
  ///     Navigator.pop(context);
  ///   },
  ///   child: Text('Leave Meeting'),
  /// )
  /// ```
  ///
  Future<void> leave() => _leave();

  Future<void> _leave() async {
    if (_closed) {
      return;
    }

    if (!_ensureLeavable("leave")) return;

    await _close(LeaveReason.manualLeaveCalled);
  }

  void _closeForegroundService() async {
    if (!kIsWeb) {
      if (Platform.isAndroid) {
        //
        if (await FlutterForegroundTask.isRunningService) {
          FlutterForegroundTask.stopService();
        }
      }
    }
  }

  Future<void> _close(LeaveReason? reason) async {
    if (_closed) return;
    _closed = true;
    // Trace meeting left event (optional can be removed)
    // SdkTracer.shared.traceEvent(
    //   spanName: 'Meeting State: CLOSING',
    //   component: ComponentCategory.meeting,
    // );
    SpanScope? closeSpan;

    try {
      if (reason == LeaveReason.manualLeaveCalled) {
        closeSpan = SdkTracer.shared.startSpan(
          spanName: "Leaving the meeting",
          component: ComponentCategory.meeting,
          category: EventCategory.telemetry,
        );
        unawaited(_webSocket?.sendRequest('definePeerLeftReason', {
          "leaveReason": "MANUAL_LEAVE_CALLED",
        }).catchError((_) => null));
      } else {
        closeSpan = SdkTracer.shared.startSpan(
          spanName: "Closing the meeting",
          component: ComponentCategory.meeting,
          category: EventCategory.telemetry,
        );
      }
      SpanScope closingResourcesSpan = SdkTracer.shared.startSpan(
          spanName: "Closing Resources",
          parentSpan: closeSpan,
          component: ComponentCategory.meeting);

      // Close mic
      if (_micProducer != null) {
        if (!_micProducer!.closed && _micProducer!.paused) {
          _micProducer!.resume();
        }
        _micProducer!.track.stop();
        _micProducer!.close();
        _micProducer = null;
      }

      // Clear encryption keys
      if (VideoSDK.keyProvider?.keyMap != null) {
        VideoSDK.keyProvider!.keyMap.clear();
      }

      // Discard any in-flight prefetch futures so _joinRoom() cannot resume
      // and write state into an already-closed room.
      _devicePrefetch = null;
      _permissionPrefetch = null;
      _rtpCapsPrefetch = null;

      //Covers reconnect-failed -> onClose -> _close() and leave-during-reconnect.
      _rejoinInProgress = false;
      _roomState = RoomState.disconnected;
      _unsupportedCodecs.clear();
      _codecChangeParticipantId = null;
      _codecRecycleFrom = null;
      _codecRecyclePending = null;
      _closeForegroundService();

      // Release every video renderer (local + remote) so their native
      // EglRenderer / SurfaceTexture is freed on leave. `_close()` previously
      // relied only on `transportclose`, which never reaches the local
      // renderers (they are not recv-transport consumers), so they leaked and
      // kept rendering after the meeting ended. Disposed here — before the
      // transports close — so each renderer is released while its native
      // texture is still registered, avoiding the "render [N] not found" error.
      await _disposeAllRenderers();

      SpanScope closingMediaSpan = SdkTracer.shared.startSpan(
          spanName: "Closing Media Transports",
          parentSpan: closingResourcesSpan,
          component: ComponentCategory.meeting);

      _webSocket?.close();
      _metricsCollector?.stopAllProbes();
      _sendTransportInternal?.cancel();
      _sendTransportInternal = null;

      _sendTransport?.close();

      _recvTransport?.close();

      SdkTracer.shared.endSpan(
        closingMediaSpan,
        message: 'Media Transports closed successfully',
      );
      SdkTracer.shared.endSpan(
        closingResourcesSpan,
        message: 'All resources are closed',
      );
      // Determine leave reason
      LeaveReason reasonEnum = reason != null
          ? LeaveReason.fromCode(reason.code)
          : LeaveReason.unknown;

      SdkTracer.shared.traceEvent(
          spanName: 'Meeting State: DISCONNECTED',
          component: ComponentCategory.meeting,
          category: EventCategory.telemetry,
          parentScope: closeSpan);
      _eventEmitter.emit('meeting-state-changed', RoomState.disconnected);
      // Trace meeting left event
      if (reason != null) {
        SdkTracer.shared.traceEvent(
          spanName: 'Emitting MEETING_LEFT Event',
          parentScope: closeSpan,
          attributes: {
            'leaveReasonCode': reason.code,
            'leaveReason': reason.message,
          },
          component: ComponentCategory.meeting,
          category: EventCategory.telemetry,
        );
      }
      // Emit events
      _eventEmitter.emit("meeting-left", reasonEnum);

      SdkTracer.shared.endSpan(
        closeSpan,
        message: reason == LeaveReason.manualLeaveCalled
            ? 'Meeting left successfully'
            : 'Meeting closed successfully',
      );
      _peerSpans.clear();
      _consumerSpans.clear();
      SdkTracer.shared.clearSpanHistory();
      // Dispose telemetry to prevent duplicate logging on rejoin
      videoSDKTelemetery?.dispose();
      videoSDKTelemetery = null;
      // Unregister and clear all tracer outputs to avoid retained references
      SdkTracer.shared.clearOutputs();

      // Trace final state
    } catch (error) {
      SdkTracer.shared.endSpan(closeSpan,
          message: 'Error in disconnecting the meeting',
          attributes: {
            'error': error.toString(),
          });
    }
  }

  /// Disposes every video renderer owned by the SDK — the local camera and
  /// screenshare renderers and every remote peer's video/share/audio renderer —
  /// so their native EglRenderer/SurfaceTexture is released on leave.
  ///
  /// Idempotent and error-safe: `RTCVideoRenderer.dispose()` is a no-op once a
  /// renderer is disposed, and any "already released" error (native texture
  /// torn down by a concurrent connection close) is caught and ignored so it
  /// can never abort `_close()` or surface as an unhandled exception.
  Future<void> _disposeAllRenderers() async {
    Future<void> safeDispose(RTCVideoRenderer? renderer) async {
      try {
        await renderer?.dispose();
      } catch (_) {
        // Native texture may already be gone during teardown; ignore.
      }
    }

    // Local renderers
    await safeDispose(_cameraRenderer);
    await safeDispose(_screenshareRenderer);
    await safeDispose(_screenShareAudioRenderer);
    _cameraRenderer = null;
    _screenshareRenderer = null;
    _screenShareAudioRenderer = null;

    // Remote peer renderers
    for (final peer in [..._peers.values]) {
      await safeDispose(peer.renderer);
      await safeDispose(peer.shareRenderer);
      await safeDispose(peer.audioRenderer);
    }
    _disposedVideoRendererPeerIds.clear();
  }

  void _softClose() {
    try {
      // // Create a span for soft close operation
      // softCloseSpan = SdkTracer.shared.startSpan(
      //   spanName: 'Soft Close Transport',
      //   component: ComponentCategory.meeting,
      // );

      // // Create child span for consumer cleanup
      // SpanScope consumerCleanupSpan = SdkTracer.shared.startSpan(
      //   spanName: 'Cleaning up Consumers',
      //   parentSpan: softCloseSpan,
      //   component: ComponentCategory.meeting,
      //   attributes: {
      //     'peerId': localParticipant.id,
      //   },
      // );

      // Remove all participants (closes all consumers)
      for (var participant in [...participants.values]) {
        __removePeer(participant.id, LeaveReason.unknown, null);
      }

      SdkTracer.shared.to(OutputTarget.toConsole).traceEvent(
            name: 'Cleaned up media streams successfully',
            component: ComponentCategory.meeting,
            category: EventCategory.debug,
          );
    } catch (error) {
      SdkTracer.shared.traceEvent(
        spanName: 'In softClose(), Soft close failed: ${error.toString()}',
        component: ComponentCategory.meeting,
        category: EventCategory.backendError,
      );
    }
  }

  // ignore: unused_element_parameter
  void _failedclosed([String? errorMsg]) {
    if (_closed) {
      return;
    }

    SpanScope? reconnectionCleanupSpan;

    try {
      reconnectionCleanupSpan = SdkTracer.shared.startSpan(
        spanName: 'Reconnection Cleanup',
        component: ComponentCategory.meeting,
      );

      SdkTracer.shared.traceEvent(
        spanName: 'Meeting is in Reconnection State',
        parentScope: reconnectionCleanupSpan,
        component: ComponentCategory.meeting,
      );

      _closeForegroundService();

      if (_micProducer != null) {
        if (!_micProducer!.closed && _micProducer!.paused) {
          _micProducer!.resume();
        }
        _micProducer!.track.stop();
        _micProducer!.close();

        _removeProducer(
            _micProducer!, _ProducerType.micProducer, reconnectionCleanupSpan);
        _micInProgress = false;
        _micProducer = null;
        _customMicrophoneAudioTrack?.dispose();
        _customMicrophoneAudioTrack = null;
      }

      if (_cameraProducer != null) {
        //

        _removeProducer(_cameraProducer!, _ProducerType.cameraProducer,
            reconnectionCleanupSpan);
        _cameraInProgress = false;
        _cameraProducer = null;
        _customCameraVideoTrack?.dispose();
        _customCameraVideoTrack = null;
      }
      if (_screenShareAudioProducer != null) {
        _removeProducer(_screenShareAudioProducer!,
            _ProducerType.screenShareAudioProducer, reconnectionCleanupSpan);

        if (!_screenShareAudioProducer!.closed &&
            _screenShareAudioProducer!.paused) {
          _screenShareAudioProducer!.resume();
        }
        _screenShareInProgress = false;
        _screenShareAudioProducer!.track.stop();
        _screenShareAudioProducer!.close();

        _screenShareAudioProducer = null;
      }
      if (_screenshareProducer != null) {
        _removeProducer(_screenshareProducer!,
            _ProducerType.screenshareProducer, reconnectionCleanupSpan);

        if (!_screenshareProducer!.closed && _screenshareProducer!.paused) {
          _screenshareProducer!.resume();
        }
        _screenShareInProgress = false;
        _screenshareProducer!.track.stop();
        _screenshareProducer!.close();
        _screenshareProducer = null;
      }

      // Cancel the periodic stats timer before closing the transport it
      // reads from — otherwise it keeps firing against a null transport.
      _sendTransportInternal?.cancel();
      _sendTransportInternal = null;

      if (_sendTransport != null) {
        _sendTransport!.close();
        _sendTransport = null;
      }

      if (_recvTransport != null) {
        _recvTransport!.close();
        _recvTransport = null;
      }

      SdkTracer.shared.endSpan(
        reconnectionCleanupSpan,
        message: 'Reconnection cleanup completed successfully',
      );
    } catch (error) {
      SdkTracer.shared.traceEvent(
        spanName: 'Error in webSocket onReconnection: ${error.toString()}',
        component: ComponentCategory.meeting,
        category: EventCategory.backendError,
      );

      if (reconnectionCleanupSpan != null) {
        SdkTracer.shared.endSpan(
          reconnectionCleanupSpan,
          success: false,
          category: EventCategory.error,
          message: 'Reconnection cleanup failed: ${error.toString()}',
        );
      }
    }
  }

  ///@nodoc

  bool isSendAndReceiveMode(Mode currentMode) {
    if (currentMode == Mode.SEND_AND_RECV || currentMode == Mode.CONFERENCE) {
      return true;
    } else {
      return false;
    }
  }

  ///@nodoc

  bool isViewerMode(Mode currentMode) {
    if (currentMode == Mode.SIGNALLING_ONLY || currentMode == Mode.VIEWER) {
      return true;
    } else {
      return false;
    }
  }

  /// Changes the media mode of the local participant.
  ///
  /// -The participant mode determines whether audio and video streams
  /// are produced, consumed, or used only for signaling.
  ///
  /// ### Available Modes
  ///
  /// - [Mode.SEND_AND_RECV]:
  ///   Both audio and video streams will be produced and consumed.
  ///
  /// - [Mode.SIGNALLING_ONLY]:
  ///   Audio and video streams will neither be produced nor consumed.
  ///   This mode is used only for signaling.
  ///
  /// - [Mode.RECV_ONLY]:
  ///   Audio and video streams will only be consumed and not produced.
  ///
  /// - When the mode is successfully changed, a [Events.participantModeChanged]
  /// event is emitted with the `participantId` and the updated `mode`
  /// of the participant.
  ///
  /// ### **Parameters**
  ///
  /// - [requestedMode]:
  ///   The desired participant mode. Possible values are
  ///   [Mode.SEND_AND_RECV], [Mode.SIGNALLING_ONLY], or [Mode.RECV_ONLY].
  ///
  /// ## Events associated with changeMode()
  ///
  /// - [Events.participantModeChanged] with `participantId` and `mode`
  ///
  /// ### **Example**
  /// ```dart
  /// // Change participant mode to send and receive media
  /// await room.changeMode(Mode.SEND_AND_RECV);
  ///
  /// room.on(Events.participantModeChanged, (event) {
  ///   print(
  ///     'Participant ${event.participantId} changed mode to ${event.mode}',
  ///   );
  /// });
  /// ```
  Future<void> changeMode(Mode requestedMode) async {
    if (!_ensureJoined("changeMode")) return;
    await _changeMode(requestedMode);
  }

  Future<void> _changeMode(Mode requestedMode) async {
    Mode currentMode = _mode;
    SpanScope? changeModeSpan;
    SpanScope? routerSpan;
    SpanScope? requestSpan;
    changeModeSpan = SdkTracer.shared.startSpan(
      spanName:
          "Changing Mode: ${currentMode.toString()} to ${requestedMode.toString()}",
      component: ComponentCategory.meeting,
      attributes: {
        'currentMode': currentMode.toString(),
        'requestedMode': requestedMode.toString(),
      },
      category: EventCategory.telemetry,
    );
    if (_webSocket == null) {
      SdkTracer.shared.to(OutputTarget.toConsole).endSpan(
            changeModeSpan,
            category: EventCategory.error,
            success: false,
            message: VideoSDKErrors[3022]!['message']!,
          );
      //Silent: changeMode() already reported this to the app.
      return;
    }

    try {
      if (currentMode == requestedMode) {
        _eventEmitter.emit("error", VideoSDKErrors[3021]);

        SdkTracer.shared.endSpan(
          changeModeSpan,
          message: "Participant is already in ${requestedMode.toString()} mode",
          success: false,
          category: EventCategory.error,
          dashboardLog: true,
          attributes: {
            'error':
                "Error in changeMode() -> Already in the ${requestedMode.toString()} mode"
          },
        );

        //     log("An error occurred in changeMode(): You are already in the ${requestedMode.toString()} mode. Please select a different mode and try again.");
        return;
      }

      _mode = requestedMode;

      if (requestedMode == Mode.SEND_AND_RECV ||
          requestedMode == Mode.CONFERENCE) {
        _produce = true;
        _consume = true;

        routerSpan = SdkTracer.shared.startSpan(
          spanName: "Loading device capabilities",
          parentSpan: changeModeSpan,
          component: ComponentCategory.meeting,
        );

        dynamic routerRtpCapabilities =
            await _webSocket!.sendRequest('getRouterRtpCapabilities', {});
        final rtpCapabilities = RtpCapabilities.fromMap(routerRtpCapabilities);
        rtpCapabilities.headerExtensions
            .removeWhere((he) => he.uri == 'urn:3gpp:video-orientation');

        _device = Device();

        if (_device == null) {
          SdkTracer.shared.endSpan(
            routerSpan,
            message: 'Loading Router Capabilities Failed - Device not found',
            success: false,
            category: EventCategory.error,
          );

          SdkTracer.shared.endSpan(
            changeModeSpan,
            message: VideoSDKErrors[3021]!['message']!,
            success: false,
            dashboardLog: true,
            attributes: {
              "error": "Error in changeMode() -> Device not found",
            },
            category: EventCategory.error,
          );

          _eventEmitter.emit("error", VideoSDKErrors[3021]);
          //   log("An error occurred in changeMode(): VIDEOSDK ERROR :: ${VideoSDKErrors[3021]?['code']}  :: ${VideoSDKErrors[3021]?['name']} :: ${VideoSDKErrors[3021]?['message']}");
          return;
        }

        await _device!.load(routerRtpCapabilities: rtpCapabilities);

        SdkTracer.shared.endSpan(
          routerSpan,
          message: "Device Capabilities Loaded",
          attributes: {
            'routerRtpCapabilities': routerRtpCapabilities.toString(),
          },
        );
        routerSpan = null;

        if (_device!.canProduce(RTCRtpMediaType.RTCRtpMediaTypeAudio) == true ||
            _device!.canProduce(RTCRtpMediaType.RTCRtpMediaTypeVideo) == true) {
          _produce = true;
        } else {
          _produce = false;
        }

        await _createSendTransport(parentSpan: changeModeSpan);

        if (currentMode != Mode.RECV_ONLY) {
          await _createReceiveTransport(parentSpan: changeModeSpan);
        }

        requestSpan = SdkTracer.shared.startSpan(
          spanName: "Change Mode Requested",
          parentSpan: changeModeSpan,
          component: ComponentCategory.meeting,
          attributes: {'mode': requestedMode.toString()},
        );

        await _sendChangeModeRequest(requestedMode);

        SdkTracer.shared.endSpan(
          requestSpan,
          message: 'Change Mode request sent successfully',
        );
        requestSpan = null;

        if (_produce) {
          if (_micEnabled) {
            await _enableMicImpl(
              parentSpan: changeModeSpan,
            );
          } else {
            if (_customMicrophoneAudioTrack != null) {
              _customMicrophoneAudioTrack?.dispose();
              _customMicrophoneAudioTrack = null;
            }
          }
          if (_camEnabled) {
            await _enableCamImpl(parentSpan: changeModeSpan);
          } else {
            if (_customCameraVideoTrack != null) {
              _customCameraVideoTrack?.dispose();
              _customCameraVideoTrack = null;
            }
          }
        }

        if (requestedMode == Mode.SEND_AND_RECV) {
          _eventEmitter.emit("participant-mode-changed-${localParticipant.id}",
              {'participantId': localParticipant.id, 'mode': 'SEND_AND_RECV'});
          _eventEmitter.emit("participant-mode-changed",
              {'participantId': localParticipant.id, 'mode': 'SEND_AND_RECV'});
        }
        if (requestedMode == Mode.CONFERENCE) {
          _eventEmitter.emit("participant-mode-changed-${localParticipant.id}",
              {'participantId': localParticipant.id, 'mode': 'CONFERENCE'});
          _eventEmitter.emit("participant-mode-changed",
              {'participantId': localParticipant.id, 'mode': 'CONFERENCE'});
        }

        SdkTracer.shared.traceEvent(
          spanName:
              "Emitting 'PEER_MODE_CHANGED' for Peer : ${localParticipant.id}",
          parentScope: changeModeSpan,
          component: ComponentCategory.meeting,
        );
      } else if (requestedMode == Mode.SIGNALLING_ONLY ||
          requestedMode == Mode.VIEWER) {
        _consume = false;
        _produce = false;

        // // Close all consumers and dispose renderers without removing peers
        // // This keeps participants in the meeting but closes their media streams
        // try {
        //   for (var peer in [..._peers.values]) {
        //     // Close audio consumer
        //     if (peer.audio != null) {
        //       try {
        //         await peer.audio!.close();
        //         _eventEmitter.emit(
        //           "stream-disabled-${peer.id}",
        //           {"audioConsumerId": peer.audio!.id},
        //         );
        //       } catch (e) {
        //         SdkTracer.shared.traceEvent(
        //           spanName: 'Error closing audio consumer: ${e.toString()}',
        //           attributes: {'peerId': peer.id},
        //           component: ComponentCategory.media,
        //           category: EventCategory.error,
        //         );
        //       }
        //       _peers[peer.id] = _peers[peer.id]!.removeAudio();
        //     }

        //     // Close video consumer and renderer
        //     if (peer.video != null) {
        //       try {
        //         await peer.video!.close();
        //         await peer.renderer?.dispose();
        //         _eventEmitter.emit(
        //           "stream-disabled-${peer.id}",
        //           {
        //             "videoConsumerId": peer.video!.id,
        //             "renderer": peer.renderer,
        //           },
        //         );
        //       } catch (e) {
        //         SdkTracer.shared.traceEvent(
        //           spanName: 'Error closing video consumer: ${e.toString()}',
        //           attributes: {'peerId': peer.id},
        //           component: ComponentCategory.media,
        //           category: EventCategory.error,
        //         );
        //       }
        //       _peers[peer.id] = _peers[peer.id]!.removeVideoAndRenderer();
        //     }

        //     // Close share consumer and renderer
        //     if (peer.share != null) {
        //       try {
        //         await peer.share!.close();
        //         await peer.shareRenderer?.dispose();
        //         _eventEmitter.emit(
        //           "stream-disabled-${peer.id}",
        //           {
        //             "shareConsumerId": peer.share!.id,
        //             "shareRenderer": peer.shareRenderer,
        //           },
        //         );
        //       } catch (e) {
        //         SdkTracer.shared.traceEvent(
        //           spanName: 'Error closing share consumer: ${e.toString()}',
        //           attributes: {'peerId': peer.id},
        //           component: ComponentCategory.media,
        //           category: EventCategory.error,
        //         );
        //       }
        //       _peers[peer.id] = _peers[peer.id]!.removeShareAndRenderer();
        //     }
        //   }
        // } catch (e) {
        //   SdkTracer.shared.traceEvent(
        //     spanName:
        //         'Error closing consumers during mode change: ${e.toString()}',
        //     component: ComponentCategory.media,
        //     category: EventCategory.error,
        //   );
        // }

        _sendTransport?.close();
        _sendTransport = null;

        _recvTransport?.close();

        _recvTransport = null;

        requestSpan = SdkTracer.shared.startSpan(
          spanName: "Change Mode Requested",
          parentSpan: changeModeSpan,
          component: ComponentCategory.meeting,
          attributes: {'mode': requestedMode.toString()},
        );

        await _sendChangeModeRequest(requestedMode);

        SdkTracer.shared.endSpan(
          requestSpan,
          message: 'Change Mode request sent successfully',
        );
        requestSpan = null;
      } else if (isViewerMode(currentMode) && requestedMode == Mode.RECV_ONLY) {
        _consume = true;
        _createReceiveTransport();

        requestSpan = SdkTracer.shared.startSpan(
          spanName: "Change Mode Requested",
          parentSpan: changeModeSpan,
          component: ComponentCategory.meeting,
          attributes: {'mode': requestedMode.toString()},
        );

        await _sendChangeModeRequest(requestedMode);

        SdkTracer.shared.endSpan(
          requestSpan,
          message: 'Change Mode request sent successfully',
        );
        requestSpan = null;
      } else if (isSendAndReceiveMode(currentMode) &&
          requestedMode == Mode.RECV_ONLY) {
        _produce = false;

        _sendTransport?.close();
        _sendTransport = null;

        requestSpan = SdkTracer.shared.startSpan(
          spanName: "Change Mode Requested",
          parentSpan: changeModeSpan,
          component: ComponentCategory.meeting,
          attributes: {'mode': requestedMode.toString()},
        );

        await _sendChangeModeRequest(requestedMode);

        SdkTracer.shared.endSpan(
          requestSpan,
          message: 'Change Mode request sent successfully',
        );
        requestSpan = null;
      }

      SdkTracer.shared.endSpan(
        changeModeSpan,
        message: 'Changed mode to ${requestedMode.toString()} successfully',
      );
      changeModeSpan = null;
    } catch (error) {
      _eventEmitter.emit("error", VideoSDKErrors[3021]);

      //   log("An error occurred in changeMode(): VIDEOSDK ERROR :: ${VideoSDKErrors[3021]?['code']}  :: ${VideoSDKErrors[3021]?['name']} :: ${VideoSDKErrors[3021]?['message']}");

      if (routerSpan != null) {
        SdkTracer.shared.endSpan(
          routerSpan,
          message: 'Error in changeMdoe() -> ${error.toString()}',
          success: false,
          category: EventCategory.error,
        );
      }

      if (requestSpan != null) {
        SdkTracer.shared.endSpan(
          requestSpan,
          message: 'Error in changeMdoe() -> ${error.toString()}',
          success: false,
          category: EventCategory.error,
        );
      }

      if (changeModeSpan != null) {
        SdkTracer.shared.endSpan(
          changeModeSpan,
          message: 'Change mdoe to ${requestedMode.toString()} failed',
          success: false,
          category: EventCategory.error,
          dashboardLog: true,
          attributes: {
            'error': "Error in changeMode() -> ${error.toString()} ",
          },
        );
      }
    }
  }

  Future<void> _requestEntry() async {
    if (_closed) {
      Timer(const Duration(seconds: 2), () {
        _webSocket?.close();
      });
      return;
    }

    _requestEntrySpan = SdkTracer.shared.startSpan(
      spanName: 'Requesting Entry',
      parentSpan: _joinSpanScope,
      component: ComponentCategory.meeting,
    );

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('requestEntry', <String, dynamic>{
          'name': localParticipant.displayName,
        });
      } else {
        if (_requestEntrySpan != null) {
          SdkTracer.shared.endSpan(
            _requestEntrySpan!,
            success: false,
            message: 'Entry request failed: WebSocket was null',
          );
        }
        _requestEntrySpan = null;
        return;
      }

      // Don't end the span here - it will be ended in entryResponded handler
    } catch (error) {
      if (_requestEntrySpan != null) {
        SdkTracer.shared.endSpan(
          _requestEntrySpan!,
          category: EventCategory.error,
          success: false,
          message: 'Entry request failed with error: ${error.toString()}',
        );
      }
      _requestEntrySpan = null;
    }
  }

  Future<void> _respondEntry(peerId, decision) async {
    SpanScope? respondEntrySpan = SdkTracer.shared.startSpan(
      spanName: 'Responding Entry for $peerId',
      parentSpan: _joinSpanScope,
      component: ComponentCategory.meeting,
      attributes: {
        'peerId': peerId,
        'decision': decision,
      },
    );

    try {
      await _webSocket!.sendRequest("respondEntry",
          <String, dynamic>{'id': peerId, 'decision': decision});

      SdkTracer.shared.endSpan(
        respondEntrySpan,
        message: 'Entry Responded Successfully',
      );
    } catch (error) {
      SdkTracer.shared.endSpan(
        respondEntrySpan,
        success: false,
        message:
            'Respond entry failed for $peerId with error:${error.toString()}',
        category: EventCategory.error,
      );
    }
  }

  /// Starts recording the current room session.
  ///
  /// - When recording starts successfully, all participants, including the
  /// local participant, will receive a [Events.recordingStarted] event.
  ///
  /// - Once the recording is completed and stored on the server, the provided
  /// `webhookUrl` will be triggered with recording details.
  /// Learn more about webhooks here: https://en.wikipedia.org/wiki/Webhook
  ///
  /// ### **Parameters**
  ///
  /// - [webhookUrl] *(optional)*:
  ///   A URL that will be called when the recording is completed and stored
  ///   on the server.
  ///
  /// - [awsDirPath] *(optional)*:
  ///   The directory path in the configured AWS storage where the recording
  ///   files will be saved.
  ///
  /// - [config] *(optional)*:
  ///   A map containing recording configuration options:
  ///
  ///   **layout**
  ///   - `type`: `"GRID"` | `"SPOTLIGHT"` | `"SIDEBAR"`
  ///   - `priority`: `"SPEAKER"` | `"PIN"`
  ///   - `gridSize`: Number (maximum 4)
  ///
  ///   **theme**
  ///   - `"DARK"` | `"LIGHT"` | `"DEFAULT"`
  ///
  ///   **mode**
  ///   - `"video-and-audio"` | `"audio"`
  ///
  ///   **quality**
  ///   - `"low"` | `"med"` | `"high"`
  ///
  ///   **orientation**
  ///   - `"landscape"` | `"portrait"`
  ///
  /// - [postTranscriptionConfig] *(optional)*:
  ///   Configuration for post-recording transcription and summary generation:
  ///
  ///   - `enabled`: Enables post-transcription processing
  ///   - `modelId`: The transcription model identifier
  ///   - `summaryConfig`:
  ///     - `enabled`: Enables summary generation
  ///     - `prompt`: Custom prompt for generating the summary
  ///
  /// ### Events associated with startRecording()
  ///
  /// - [Events.recordingStarted]
  ///
  /// ### **Example**
  /// ```dart
  /// const webhookUrl = 'https://webhook.your-api-server.com';
  ///
  /// final config = {
  ///   'layout': {
  ///     'type': 'GRID',
  ///     'priority': 'SPEAKER',
  ///     'gridSize': 4,
  ///   },
  ///   'theme': 'LIGHT',
  ///   'mode': 'video-and-audio',
  /// };
  ///
  /// final postTranscriptionConfig = PostTranscriptionConfig(
  ///   enabled: true,
  ///   modelId: 'raman_v1',
  ///   summaryConfig: SummaryConfig(
  ///     enabled: true,
  ///     prompt:
  ///         'Write summary in sections like Title, Agenda, Speakers, '
  ///         'Action Items, Outlines, Notes and Summary',
  ///   ),
  /// );
  ///
  /// await room.startRecording(
  ///   webhookUrl: webhookUrl,
  ///   config: config,
  ///   postTranscriptionConfig: postTranscriptionConfig,
  /// );
  /// ```
  Future<void> startRecording(
      {String? webhookUrl,
      String? awsDirPath,
      Map<String, dynamic>? config,
      PostTranscriptionConfig? postTranscriptionConfig}) async {
    if (!_ensureJoined("startRecording")) return;
    await _startRecording(
      webhookUrl: webhookUrl,
      awsDirPath: awsDirPath,
      config: config,
      postTranscriptionConfig: postTranscriptionConfig,
    );
  }

  Future<void> _startRecording(
      {String? webhookUrl,
      String? awsDirPath,
      Map<String, dynamic>? config,
      PostTranscriptionConfig? postTranscriptionConfig}) async {
    if (e2eeEnabled) {
      throw Exception("Recording is not supported when E2EE is enabled.");
    }
    Map<String, dynamic> data = {};
    if (webhookUrl != null) data["webhookUrl"] = webhookUrl;
    if (awsDirPath != null) data["awsDirPath"] = awsDirPath;
    if (config != null) data["config"] = config;
    if (postTranscriptionConfig != null) {
      data["transcription"] = postTranscriptionConfig;
    }

    SpanScope? startRecordingSpan;

    startRecordingSpan = SdkTracer.shared.startSpan(
      spanName: "Start Recording Requested",
      attributes: {
        'webhookUrl': webhookUrl ?? 'webhookUrl Not Specify',
        'awsDirPath': awsDirPath ?? 'awsDirPath Not Specify',
        'config': config != null ? config.toString() : 'config Not Specify',
        'transcription': postTranscriptionConfig != null
            ? postTranscriptionConfig.toJson()
            : 'transcription not provided',
      },
      category: EventCategory.telemetry,
    );
    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('startRecording', data);

        if (startRecordingSpan != null) {
          SdkTracer.shared.endSpan(
            startRecordingSpan,
            message: "Meeting recording start request sent successfully",
          );
        }
      } else {
        SdkTracer.shared.endSpan(
          startRecordingSpan,
          message: VideoSDKErrors[3022]!['message']!,
          success: false,
          category: EventCategory.error,
        );
        //Silent: startRecording() already reported this to the app.
        return;
      }
    } catch (error) {
      SdkTracer.shared.endSpan(startRecordingSpan,
          success: false,
          message: 'Start recording failed',
          category: EventCategory.error,
          dashboardLog: true,
          attributes: {
            'error': "Error in startRecording() -> ${error.toString()}",
          });
      _eventEmitter.emit("error", VideoSDKErrors[4011]);
    }
  }

  /// Stops the ongoing room recording.
  ///
  /// - When the recording is successfully stopped, all participants,
  /// including the local participant, will receive a
  /// [Events.recordingStopped] event.
  ///
  /// ## Events associated with stopRecording()
  ///
  /// - [Events.recordingStopped]
  ///
  /// ### **Example**
  /// ```dart
  /// // Stop room recording
  /// await room.stopRecording();
  /// ```
  Future<void> stopRecording() async {
    if (!_ensureJoined("stopRecording")) return;
    await _stopRecording();
  }

  //
  Future<void> _stopRecording() async {
    SpanScope? stopRecordingSpan;
    stopRecordingSpan = SdkTracer.shared.startSpan(
      spanName: "Stop Recording Requested",
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
    );

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('stopRecording', {});

        if (stopRecordingSpan != null) {
          SdkTracer.shared.endSpan(stopRecordingSpan,
              message: "Meeting recording stop request sent successfully");
        }
      } else {
        SdkTracer.shared.endSpan(
          stopRecordingSpan,
          message: VideoSDKErrors[3022]!['message']!,
          success: false,
          category: EventCategory.error,
        );
      }
      //Silent: stopRecording() already reported this to the app.
      return;
    } catch (error) {
      SdkTracer.shared.endSpan(stopRecordingSpan,
          message: "Stop recording failed",
          success: false,
          category: EventCategory.error,
          attributes: {
            'error': "Error in stopRecording() -> ${error.toString()}",
          });
      _eventEmitter.emit("error", VideoSDKErrors[4012]);
    }
  }

  /// Starts livestreaming the current room session.
  ///
  /// - This method allows you to broadcast the room to external platforms
  /// such as YouTube, Facebook, or any other service that supports
  /// RTMP streaming.
  ///
  /// When livestreaming starts successfully, all participants,
  /// including the local participant, will receive a
  /// [Events.liveStreamStarted] event.
  ///
  /// ### **Parameters**
  ///
  /// - [outputs]:
  ///   A list of RTMP destinations to which the livestream will be sent.
  ///   Each item in the list must contain:
  ///   - `url`: The RTMP server URL (for example, YouTube or Facebook RTMP URL)
  ///   - `streamKey`: The stream key provided by the streaming platform
  ///
  /// - [config] *(optional)*:
  ///   A map containing livestream layout and theme configuration:
  ///
  ///   **layout**
  ///   - `type`: `"GRID"` | `"SPOTLIGHT"` | `"SIDEBAR"`
  ///   - `priority`: `"SPEAKER"` | `"PIN"`
  ///   - `gridSize`: Number (maximum 4)
  ///
  ///   **theme**
  ///   - `"DARK"` | `"LIGHT"` | `"DEFAULT"`
  ///
  /// - [postTranscriptionConfig] *(optional)*:
  ///   Configuration for post-livestream transcription and summary generation:
  ///
  ///   - `enabled`: Enables post-transcription processing
  ///   - `modelId`: The transcription model identifier
  ///   - `summaryConfig`:
  ///     - `enabled`: Enables summary generation
  ///     - `prompt`: Custom prompt for generating the summary
  ///
  /// ### Events associated with startLivestream()
  ///
  /// - [Events.liveStreamStarted]
  ///
  /// ### **Example**
  /// ```dart
  /// final outputs = [
  ///   {
  ///     'url': 'rtmp://a.rtmp.youtube.com/live2',
  ///     'streamKey': '<STREAM_KEY>',
  ///   },
  ///   {
  ///     'url': 'rtmps://',
  ///     'streamKey': '<STREAM_KEY>',
  ///   },
  /// ];
  ///
  /// final livestreamConfig = {
  ///   'layout': {
  ///     'type': 'GRID',
  ///     'priority': 'SPEAKER',
  ///     'gridSize': 4,
  ///   },
  ///   'theme': 'LIGHT',
  /// };
  ///
  /// final postTranscriptionConfig = PostTranscriptionConfig(
  ///   enabled: true,
  ///   modelId: 'raman_v1',
  ///   summaryConfig: SummaryConfig(
  ///     enabled: true,
  ///     prompt:
  ///         'Write summary in sections like Title, Agenda, Speakers, '
  ///         'Action Items, Outlines, Notes and Summary',
  ///   ),
  /// );
  ///
  /// await room.startLivestream(
  ///   outputs,
  ///   config: livestreamConfig,
  ///   postTranscriptionConfig: postTranscriptionConfig,
  /// );
  /// ```
  Future<void> startLivestream(outputs,
      {Map<String, dynamic>? config,
      PostTranscriptionConfig? postTranscriptionConfig}) async {
    if (!_ensureJoined("startLivestream")) return;
    await _startLivestream(
      outputs,
      config: config,
      postTranscriptionConfig: postTranscriptionConfig,
    );
  }

  //
  Future<void> _startLivestream(outputs,
      {Map<String, dynamic>? config,
      PostTranscriptionConfig? postTranscriptionConfig}) async {
    Map<String, dynamic> data = {};
    if (outputs != null) data["outputs"] = outputs;
    if (config != null) data["config"] = config;
    if (postTranscriptionConfig != null) {
      data["transcription"] = postTranscriptionConfig;
    }

    SpanScope? startLivestreamSpan;

    startLivestreamSpan = SdkTracer.shared.startSpan(
      spanName: "Start Livestream Requested",
      component: ComponentCategory.meeting,
      attributes: {
        'outputs': outputs != null ? outputs.toString() : 'outputs Not Specify',
        'config': config != null ? config.toString() : 'config Not Specify',
        'transcription': postTranscriptionConfig != null
            ? postTranscriptionConfig.toJson()
            : 'transcription not started',
      },
      category: EventCategory.telemetry,
    );

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('startLivestream', data);

        if (startLivestreamSpan != null) {
          SdkTracer.shared.endSpan(
            startLivestreamSpan,
            message: "Meeting livestream start request sent successfully",
          );
        }
      } else {
        SdkTracer.shared.endSpan(
          startLivestreamSpan,
          message: VideoSDKErrors[3022]!['message']!,
          success: false,
          category: EventCategory.error,
        );
        //Silent: startLivestream() already reported this to the app.
        return;
      }
    } catch (error) {
      SdkTracer.shared.endSpan(
        startLivestreamSpan,
        success: false,
        message: "Start RTMP livestream failed",
        category: EventCategory.error,
        attributes: {
          'error': "Error in startLiveSteam() -> ${error.toString()}",
        },
      );
    }
  }

  /// Stops the ongoing room livestream.
  ///
  /// - When livestreaming is successfully stopped, all participants,
  /// including the local participant, will receive a
  /// [Events.liveStreamStopped] event.
  ///
  /// ## Events associated with stopLivestream()
  ///
  /// - [Events.liveStreamStopped]
  ///
  /// ### **Example**
  /// ```dart
  /// // Stop room livestreaming
  /// await room.stopLivestream();
  /// ```
  Future<void> stopLivestream() async {
    if (!_ensureJoined("stopLivestream")) return;
    await _stopLivestream();
  }

  //
  Future<void> _stopLivestream() async {
    SpanScope? stopLivestreamSpan;

    stopLivestreamSpan = SdkTracer.shared.startSpan(
      spanName: "Stop Livestream Requested",
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
    );

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('stopLivestream', {});

        if (stopLivestreamSpan != null) {
          SdkTracer.shared.endSpan(
            stopLivestreamSpan,
            message: "Meeting livestream stop request sent successfully",
          );
        }
      } else {
        SdkTracer.shared.endSpan(
          stopLivestreamSpan,
          message: VideoSDKErrors[3022]!['message']!,
          success: false,
          category: EventCategory.error,
        );
        //Silent: stopLivestream() already reported this to the app.
        return;
      }
    } catch (error) {
      SdkTracer.shared.endSpan(
        stopLivestreamSpan,
        success: false,
        message: "Stop RTMP livestream failed",
        category: EventCategory.error,
        attributes: {
          'error': "Error in stopLivestream() -> ${error.toString()}",
        },
      );
      //  log("Error while stopping livestreaming $error");
    }
  }

  /// Starts HLS (HTTP Live Streaming) for the current room session.
  ///
  /// - When HLS starts successfully, all participants, including the local
  /// participant, will receive a [Events.hlsStarted] event containing:
  /// - `playbackHlsUrl`: Live HLS URL with playback (DVR) support
  /// - `livestreamUrl`: Live HLS URL without playback support
  ///
  /// > **Note:**
  /// > `downstreamUrl` is deprecated. Use `playbackHlsUrl` or `livestreamUrl`
  /// > instead.
  ///
  /// ### **Parameters**
  ///
  /// - [config] *(optional)*:
  ///   A map containing HLS layout and stream configuration:
  ///
  ///   **layout**
  ///   - `type`: `"GRID"` | `"SPOTLIGHT"` | `"SIDEBAR"`
  ///   - `priority`: `"SPEAKER"` | `"PIN"`
  ///   - `gridSize`: Number (maximum 25)
  ///
  ///   **theme**
  ///   - `"DARK"` | `"LIGHT"` | `"DEFAULT"`
  ///
  ///   **mode**
  ///   - `"video-and-audio"` | `"audio"`
  ///
  ///   **quality**
  ///   - `"low"` | `"med"` | `"high"`
  ///
  ///   **orientation**
  ///   - `"landscape"` | `"portrait"`
  ///
  /// - [postTranscriptionConfig] *(optional)*:
  ///   Configuration for post-HLS transcription and summary generation:
  ///
  ///   - `enabled`: Enables post-transcription processing
  ///   - `modelId`: The transcription model identifier
  ///   - `summaryConfig`:
  ///     - `enabled`: Enables summary generation
  ///     - `prompt`: Custom prompt for generating the summary
  ///
  /// ### Events associated with startHls()
  ///
  /// - [Events.hlsStarted] with `playbackHlsUrl` and `livestreamUrl`
  ///
  /// ### **Example**
  /// ```dart
  /// final config = {
  ///   'layout': {
  ///     'type': 'GRID',
  ///     'priority': 'SPEAKER',
  ///     'gridSize': 4,
  ///   },
  ///   'theme': 'LIGHT',
  ///   'mode': 'video-and-audio',
  /// };
  ///
  /// final postTranscriptionConfig = PostTranscriptionConfig(
  ///   enabled: true,
  ///   modelId: 'raman_v1',
  ///   summaryConfig: SummaryConfig(
  ///     enabled: true,
  ///     prompt:
  ///         'Write summary in sections like Title, Agenda, Speakers, '
  ///         'Action Items, Outlines, Notes and Summary',
  ///   ),
  /// );
  ///
  /// await room.startHls(
  ///   config: config,
  ///   postTranscriptionConfig: postTranscriptionConfig,
  /// );
  /// ```
  Future<void> startHls(
      {Map<String, dynamic>? config,
      PostTranscriptionConfig? postTranscriptionConfig}) async {
    if (!_ensureJoined("startHls")) return;
    await _startHls(
        config: config, postTranscriptionConfig: postTranscriptionConfig);
  }

  //
  Future<void> _startHls(
      {Map<String, dynamic>? config,
      PostTranscriptionConfig? postTranscriptionConfig}) async {
    Map<String, dynamic> data = {};

    if (config != null) data["config"] = config;
    if (postTranscriptionConfig != null) {
      data["transcription"] = postTranscriptionConfig;
    }

    SpanScope? startHlsSpan;
    startHlsSpan = SdkTracer.shared.startSpan(
      spanName: "Start HLS Requested",
      attributes: {
        'config': config != null ? config.toString() : 'config Not Specify',
        'transcription': postTranscriptionConfig != null
            ? postTranscriptionConfig.toJson()
            : 'transcription not started',
      },
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
    );
    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('startHls', data);
        SdkTracer.shared.endSpan(
          startHlsSpan,
          message: "HLS streaming start request sent successfully",
        );
      } else {
        SdkTracer.shared.endSpan(
          startHlsSpan,
          message: VideoSDKErrors[3022]!['message']!,
          success: false,
          category: EventCategory.error,
        );
        //Silent: startHls() already reported this to the app.
        return;
      }
    } catch (error) {
      SdkTracer.shared.endSpan(
        startHlsSpan,
        message: "Start HLS failed",
        dashboardLog: true,
        success: false,
        attributes: {
          'error': "Error in startHls() -> ${error.toString()}",
        },
        category: EventCategory.error,
      );
    }
  }

  /// Stops the ongoing HLS (HTTP Live Streaming) session.
  ///
  /// - When HLS is successfully stopped, all participants,
  /// including the local participant, will receive a
  /// [Events.hlsStopped] event.
  ///
  /// ## Events associated with stopHls()
  ///
  /// - [Events.hlsStopped]
  ///
  /// ### **Example**
  /// ```dart
  /// // Stop HLS streaming
  /// await room.stopHls();
  /// ```
  Future<void> stopHls() async {
    if (!_ensureJoined("stopHls")) return;
    await _stopHls();
  }

  //
  Future<void> _stopHls() async {
    SpanScope? stopHlsSpan;

    stopHlsSpan = SdkTracer.shared.startSpan(
      spanName: "Stop HLS Requested",
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
    );

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('stopHls', {});
        if (stopHlsSpan != null) {
          SdkTracer.shared.endSpan(
            stopHlsSpan,
            message: "HLS streaming stop request sent successfully",
          );
        }
      } else {
        SdkTracer.shared.endSpan(
          stopHlsSpan,
          message: VideoSDKErrors[3022]!['message']!,
          success: false,
          category: EventCategory.error,
        );
        //Silent: stopHls() already reported this to the app.
        return;
      }
    } catch (error) {
      SdkTracer.shared.endSpan(
        stopHlsSpan,
        message: "Stop HLS failed",
        dashboardLog: true,
        success: false,
        category: EventCategory.error,
        attributes: {
          'error': "Error in stopHls() -> ${error.toString()}",
        },
      );
      _eventEmitter.emit("error", VideoSDKErrors[4017]);
    }
  }

  /// Starts real-time transcription for the current room session.
  ///
  /// - When real-time transcription starts, all participants, including the
  /// local participant, will receive a
  /// [Events.transcriptionStateChanged] event with the
  /// `TRANSCRIPTION_STARTING` state, along with
  /// [Events.transcriptionText] events containing the transcribed text.
  ///
  /// ### **Parameters**
  ///
  /// - [transcriptionConfig] *(optional)*:
  ///   Configuration for real-time transcription:
  ///
  ///   - `webhookUrl`:
  ///     A URL that will be triggered whenever the state of real-time
  ///     transcription changes.
  ///     Learn more about webhooks: https://en.wikipedia.org/wiki/Webhook
  ///
  ///   - `summaryConfig`:
  ///     Configuration for generating a summary from the real-time
  ///     transcription:
  ///     - `enabled`: Enables summary generation. The summary will be
  ///       available after transcription is stopped.
  ///       Default: `false`
  ///     - `prompt`: Custom instructions for generating the summary
  ///       based on the transcription content.
  ///
  /// ### Events associated with startTranscription()
  ///
  /// - [Events.transcriptionStateChanged] with state `TRANSCRIPTION_STARTING`
  /// - [Events.transcriptionText]
  ///
  /// ### **Example**
  /// ```dart
  /// final transcriptionConfig = TranscriptionConfig(
  ///   webhookUrl: 'https://webhook.your-api-server.com',
  ///   summaryConfig: SummaryConfig(
  ///     enabled: true,
  ///     prompt:
  ///         'Write summary in sections like Title, Agenda, Speakers, '
  ///         'Action Items, Outlines, Notes and Summary',
  ///   ),
  /// );
  ///
  /// await room.startTranscription(
  ///   transcriptionConfig: transcriptionConfig,
  /// );
  /// ```
  Future<void> startTranscription(
      {TranscriptionConfig? transcriptionConfig}) async {
    if (!_ensureJoined("startTranscription")) return;
    await _startTranscription(transcriptionConfig: transcriptionConfig);
  }

  //
  Future<void> _startTranscription(
      {TranscriptionConfig? transcriptionConfig}) async {
    if (e2eeEnabled) {
      throw Exception("Transcription is not supported when E2EE is enabled.");
    }
    Map<String, dynamic> data = {};
    if (transcriptionConfig != null) {
      data["config"] = transcriptionConfig;
    }

    SpanScope? startTranscriptionSpan;
    startTranscriptionSpan = SdkTracer.shared.startSpan(
        spanName: "Start Transcription Requested",
        component: ComponentCategory.meeting,
        category: EventCategory.telemetry,
        attributes: {
          'config': transcriptionConfig != null
              ? transcriptionConfig.toJson()
              : 'config Not Specify'
        });
    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('startTranscription', data);
        if (startTranscriptionSpan != null) {
          SdkTracer.shared.endSpan(
            startTranscriptionSpan,
            message: "Meeting transcription start request sent successfully",
          );
        }
      } else {
        SdkTracer.shared.endSpan(
          startTranscriptionSpan,
          message: VideoSDKErrors[3022]!['message']!,
          category: EventCategory.error,
          success: false,
        );
        //Silent: startTranscription() already reported this to the app.
        return;
      }
    } catch (error) {
      SdkTracer.shared.endSpan(
        startTranscriptionSpan,
        message: "Start transcription failed",
        success: false,
        category: EventCategory.error,
        attributes: {
          'error': "Error in startTranscription() -> ${error.toString()}",
        },
      );
      _eventEmitter.emit("error", VideoSDKErrors[4031]);
    }
  }

  /// Stops the ongoing real-time transcription for the current room session.
  ///
  /// - When real-time transcription is stopped, all participants,
  /// including the local participant, will receive a
  /// [Events.transcriptionStateChanged] event with the
  /// `TRANSCRIPTION_STOPPING` state.
  ///
  /// ## Events associated with stopTranscription()
  ///
  /// - [Events.transcriptionStateChanged] with state `TRANSCRIPTION_STOPPING`
  ///
  /// ### **Example**
  /// ```dart
  /// // Stop real-time transcription
  /// await room.stopTranscription();
  /// ```
  Future<void> stopTranscription() async {
    if (!_ensureJoined("stopTranscription")) return;
    await _stopTranscription();
  }

  //
  Future<void> _stopTranscription() async {
    SpanScope? stopTranscriptionSpan;
    stopTranscriptionSpan = SdkTracer.shared.startSpan(
      spanName: "Stop Transcription Requested",
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
    );
    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('stopTranscription', {});

        if (stopTranscriptionSpan != null) {
          SdkTracer.shared.endSpan(
            stopTranscriptionSpan,
            message: "Meeting transcription stop request sent successfully",
          );
        }
      } else {
        SdkTracer.shared.endSpan(
          stopTranscriptionSpan,
          message: VideoSDKErrors[3022]!['message']!,
          success: false,
          category: EventCategory.error,
        );

        //Silent: stopTranscription() already reported this to the app.
        return;
      }
    } catch (error) {
      _eventEmitter.emit("error", VideoSDKErrors[4032]);
      SdkTracer.shared.endSpan(
        stopTranscriptionSpan,
        message: "Stop transcription failed",
        success: false,
        category: EventCategory.error,
        attributes: {
          'error': "Error in stopTranscription() -> ${error.toString()}",
        },
      );
    }
  }

  /// Changes the active WebCam device for the local participant.
  ///
  /// - If multiple WebCam devices are connected, this method allows you to
  /// switch the WebCam by providing the desired WebCam device information.
  ///
  /// - You can retrieve the list of available WebCam devices using
  /// [VideoSDK.getVideoDevices].
  ///
  /// ### **Parameters**
  ///
  /// - [device]:
  ///   The [VideoDeviceInfo] representing the WebCam device to switch to.
  ///
  /// - [customTrack] *(optional)*:
  ///   A custom video track to be used instead of the default WebCam track.
  ///   This is useful when providing a pre-processed video source or applying
  ///   custom video effects.
  ///
  /// ### **Example**
  /// ```dart
  /// // Get available WebCam devices
  /// final devices = await VideoSDK.getVideoDevices();
  ///
  /// // Switch to a specific WebCam
  /// await room.changeCam(devices.first);
  ///
  /// // Switch WebCam with a custom video track
  /// final customTrack = await CustomTrack.createCameraTrack();
  /// await room.changeCam(devices.first, customTrack);
  /// ```
  Future<void> changeCam(
    VideoDeviceInfo device, [
    CustomTrack? customTrack,
  ]) async {
    if (!_ensureJoined("changeCam")) {
      //The SDK owns a track once it is handed over, so a rejected call still
      //releases it — otherwise the camera stays open with no handle to close.
      customTrack?.dispose();
      return;
    }
    await _changeCam(device, customTrack);
  }

  Future<void> _changeCam(VideoDeviceInfo device,
      [CustomTrack? customTrack]) async {
    if (_selectedVideoInput?.deviceId == device.deviceId) {
      return;
    }

    SpanScope? changeCamSpan = SdkTracer.shared.startSpan(
      spanName: "Webcam change requested",
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
      attributes: {
        'webcamId': customTrack == null ? device.deviceId : 'none',
        'customTrackInfo':
            customTrack != null ? customTrack.toString() : 'none',
      },
    );

    try {
      //
      _cameraInProgress = true;

      if (customTrack != null) {
        if (customTrack.ended == true) {
          customTrack = null;
          SdkTracer.shared.traceEvent(
            spanName:
                "Error in changeCam() -> Invalid Custom Audio Track Passed. Reverting to default",
            category: EventCategory.error,
            success: false,
          );
          _eventEmitter.emit("error", VideoSDKErrors[3001]);
          log("An error occurred in changeCam(): VIDEOSDK ERROR :: ${VideoSDKErrors[3001]?['code']}  :: ${VideoSDKErrors[3001]?['name']} :: ${VideoSDKErrors[3001]?['message']}");
        }
      }
      //Picking a different camera while the camera is off must not turn it
      //on. Record the device in the config store — the next enableCam()
      //rebuilds from it — and leave the producer alone. The gate is _camState
      //(the live producer state), not _camEnabled: a host-forced disableCam
      //leaves the intent set, and that must not read as "camera is live".
      if (!_camState) {
        _customVideoTrackConfig = customTrack != null
            ? WebcamConfig.fromCustomTrack(customTrack)
            : _customVideoTrackConfig.copyWith(cameraId: device.deviceId);
        _selectedVideoInput = device;

        //The join-time track (:6025) and any join-time rebuild would otherwise
        //outrank what was just recorded — _enableCamImpl overwrites the store
        //with WebcamConfig.fromCustomTrack, so a camera picked on a pre-join
        //preview screen would be dropped and the meeting would open on the
        //original one. Releasing it forces the rebuild path, same as the mic
        //branch does with _customMicrophoneAudioTrack.
        await _customCameraVideoTrack?.dispose();
        _customCameraVideoTrack = null;

        //A supplied track cannot be held open until the next enableCam() —
        //that would keep the camera capturing while it reads as off — so only
        //its configuration survives.
        await customTrack?.dispose();

        _cameraInProgress = false;

        SdkTracer.shared.endSpan(
          changeCamSpan,
          message:
              'Camera device recorded while the camera is off; it will be applied on the next enableCam()',
        );
        return;
      }

      //
      await _disableCamImpl(parentSpan: changeCamSpan);

      customTrack ??= await VideoSDK.createCameraVideoTrack(
          cameraId: device.deviceId,
          multiStream: _customVideoTrackConfig.multiStream,
          encoderConfig: _customVideoTrackConfig.encoderConfig,
          facingMode: _customVideoTrackConfig.facingMode,
          bitrateMode: _customVideoTrackConfig.bitrateMode,
          maxLayer: _customVideoTrackConfig.maxLayer,
          codec: _customVideoTrackConfig.codec);

      //If there is an error, createCameraVideoTrack will return null.
      if (customTrack == null) {
        SdkTracer.shared.endSpan(
          changeCamSpan,
          success: false,
          dashboardLog: true,
          attributes: {
            'error': "Error in changeCam() -> could not create Video Track",
          },
          message: VideoSDKErrors[3011]!['message']!,
          category: EventCategory.error,
        );

        _eventEmitter.emit("error", VideoSDKErrors[3011]);
        log("An error occurred in changeCam(): VIDEOSDK ERROR :: ${VideoSDKErrors[3011]?['code']}  :: ${VideoSDKErrors[3011]?['name']} :: ${VideoSDKErrors[3011]?['message']}");

        _cameraInProgress = false;
        return;
      }

      _enableCamImpl(customTrack: customTrack, parentSpan: changeCamSpan);

      //
      _cameraInProgress = false;

      SdkTracer.shared.endSpan(
        changeCamSpan,
        message: 'Webcam changed successfully',
      );
    } catch (err) {
      //  log("An error occurred in changeCam(): Something went wrong, and the WebCam could not be changed. Please try again.");

      //
      SdkTracer.shared.endSpan(
        changeCamSpan,
        success: false,
        dashboardLog: true,
        message: VideoSDKErrors[3024]!['message']!,
        attributes: {"error": "Error in ChangeCam() -> ${err.toString()} "},
        category: EventCategory.error,
      );
    }
  }

  // @Deprecated('Use VideoSDK.getVideoDevices() instead')
  // List<MediaDeviceInfo> getCameras() =>
  //     VideoSDK.mediaDevices[MediaDeviceType.videoInput]!;

  @Deprecated("Use selectedCam instead")

  /// Returns the device ID of the currently selected WebCam.
  ///
  /// This provides the identifier of the WebCam device that is
  /// currently in use for video capture.
  ///
  /// ### Returns
  ///
  /// - A [String] representing the selected WebCam device ID,
  ///   or `null` if no WebCam device is selected.
  String? get selectedCamId => _selectedVideoInput?.deviceId;

  /// Returns the currently selected WebCam device.
  ///
  /// This provides the [VideoDeviceInfo] object representing the
  /// WebCam device that is currently in use for video capture.
  ///
  /// ### Returns
  ///
  /// - A [VideoDeviceInfo] representing the selected WebCam device,
  ///   or `null` if no WebCam device is selected.
  VideoDeviceInfo? get selectedCam => _selectedVideoInput;

  bool _isMobilePlatform() {
    if (kIsWeb) {
      return false;
    } else {
      if (Platform.isMacOS || Platform.isWindows) {
        return false;
      }
    }
    return true;
  }

  ///
  String? get agentPeerId =>
      agentParticipants.isNotEmpty ? agentParticipants.keys.first : null;

  // @Deprecated("Use VideoSDK.getAudioDevices() method instead")
  // List<MediaDeviceInfo> getMics() {
  //   if (!_isMobilePlatform()) {
  //     return VideoSDK.mediaDevices[MediaDeviceType.audioInput]!;
  //   }
  //   return [];
  // }

  // @Deprecated("Use VideoSDK.getAudioDevices() method instead")
  // List<MediaDeviceInfo> getAudioOutputDevices() {
  //   List<MediaDeviceInfo> audioOutputDevices =
  //       VideoSDK.mediaDevices[MediaDeviceType.audioOutput]!;
  //   if (!kIsWeb) {
  //     if (Platform.isIOS) {
  //       if (audioOutputDevices.length == 1) {
  //         MediaDeviceInfo mediaDeviceInfo = MediaDeviceInfo(
  //             label: "Receiver",
  //             deviceId: "Built-In Receiver",
  //             kind: "audiooutput");
  //         audioOutputDevices.add(mediaDeviceInfo);
  //       }
  //     }
  //   }
  //   return audioOutputDevices;
  // }
  /// Switches the audio output device for the local participant.
  ///
  /// - This method allows you to change the active audio output device
  /// (for example, speakers, headphones, or external audio devices).
  ///
  /// You can retrieve the list of available audio output devices using
  /// [VideoSDK.getAudioDevices].
  ///
  /// ### **Parameters**
  ///
  /// - [device]:
  ///   The [AudioDeviceInfo] representing the audio output device
  ///   to switch to.
  ///
  /// ### **Example**
  /// ```dart
  /// // Get available audio output devices
  /// final audioDevices = await VideoSDK.getAudioDevices();
  ///
  /// // Switch to a specific audio output device
  /// await room.switchAudioDevice(audioDevices.first);
  /// ```
  Future<void> switchAudioDevice(AudioDeviceInfo device) =>
      _switchAudioDevice(device);
  Future<void> _switchAudioDevice(AudioDeviceInfo device) async {
    SpanScope? switchAudioDeviceSpan;

    switchAudioDeviceSpan = SdkTracer.shared.startSpan(
      spanName: 'Switching AudioDevice',
      component: ComponentCategory.media,
      category: EventCategory.telemetry,
      attributes: {
        'deviceId': device.deviceId,
        'label': device.label,
      },
    );

    try {
      if (!kIsWeb) {
        if (Platform.isIOS && device.deviceId == "Built-In Receiver") {
          await Helper.setAppleAudioConfiguration(AppleAudioConfiguration(
              appleAudioCategory: AppleAudioCategory.playAndRecord,
              appleAudioCategoryOptions: {
                AppleAudioCategoryOption.allowBluetooth,
                AppleAudioCategoryOption.allowBluetoothA2DP
              },
              appleAudioMode: AppleAudioMode.voiceChat));
        } else {
          await navigator.mediaDevices
              .selectAudioOutput(AudioOutputOptions(deviceId: device.deviceId));
        }
      } else {
        AudioHTMLInterface().setAudioOutputDevice(device.deviceId);
      }

      _selectedAudioOutput = device;

      SdkTracer.shared.endSpan(
        switchAudioDeviceSpan,
        message: 'Switching AudioDevice Successful',
      );
    } catch (e) {
      SdkTracer.shared.endSpan(
        switchAudioDeviceSpan,
        success: false,
        message: 'Switching AudioDevice UnSuccessful ${e.toString()}',
        category: EventCategory.error,
      );

      ///  log("Something went wrong, and the audio device could not be switched. Please try again.");
    }
  }

  /// @nodoc

  @Deprecated("Use selectedSpeaker instead")
  String? get selectedSpeakerId => _selectedAudioOutput?.deviceId;

  /// Returns the currently selected speaker device.
  ///
  /// This provides the [AudioDeviceInfo] object representing the
  /// audio output (speaker) device that is currently in use.
  ///
  /// ### Type
  ///
  /// - `AudioDeviceInfo?`
  AudioDeviceInfo? get selectedSpeaker => _selectedAudioOutput;

  /// Changes the active audio input (microphone) device for the local participant.
  ///
  /// - This method allows you to switch between available microphone devices
  /// when multiple audio input devices are connected.
  ///
  /// - You can retrieve the list of available audio input devices using
  /// [VideoSDK.getAudioDevices].
  ///
  /// > **Info:**
  /// > The `changeMic()` method is not supported on mobile platforms
  /// > (Android and iOS).
  ///
  /// ### **Parameters**
  ///
  /// - [device]:
  ///   The [AudioDeviceInfo] representing the microphone device to switch to.
  ///
  /// - [customTrack] *(optional)*:
  ///   A custom audio track to be used instead of the default microphone input.
  ///   This is useful when providing an externally generated audio source or
  ///   applying custom audio processing.
  ///
  /// ### **Example**
  /// ```dart
  /// // Get available audio input devices (desktop only)
  /// final audioDevices = await VideoSDK.getAudioDevices();
  ///
  /// // Switch to a specific microphone
  /// await room.changeMic(audioDevices.first);
  ///
  /// // Switch microphone with a custom audio track
  /// final customTrack = await CustomTrack.createAudioTrack();
  /// await room.changeMic(audioDevices.first, customTrack);
  /// ``
  Future<void> changeMic(AudioDeviceInfo device,
      [CustomTrack? customTrack]) async {
    if (!_ensureJoined("changeMic")) {
      customTrack?.dispose();
      return;
    }
    await _changeMic(device, customTrack);
  }

  Future<void> _changeMic(AudioDeviceInfo device,
      [CustomTrack? customTrack]) async {
    if (!_isMobilePlatform()) {
      if (_selectedAudioInput == device) {
        return;
      }

      SpanScope? changeMicSpan = SdkTracer.shared.startSpan(
        spanName: "Microphone change requested",
        component: ComponentCategory.media,
        category: EventCategory.telemetry,
        attributes: {
          'inputType': customTrack != null ? 'object' : 'string',
          'micId': customTrack == null ? device.deviceId : 'none',
          'customTrackInfo':
              customTrack != null ? customTrack.toString() : 'none',
        },
      );

      try {
        if (customTrack != null) {
          if (customTrack.ended == true) {
            customTrack = null;
            _eventEmitter.emit("error", VideoSDKErrors[3002]);
            log("An error occurred in changeMic(): VIDEOSDK ERROR :: ${VideoSDKErrors[3002]?['code']}  :: ${VideoSDKErrors[3002]?['name']} :: ${VideoSDKErrors[3002]?['message']}");
          }
        }

        if (!_micState) {
          _micConfig = customTrack != null
              ? MicConfig.fromCustomTrack(customTrack)
              : _micConfig.copyWith(microphoneId: device.deviceId);
          _selectedAudioInput = device;

          await _customMicrophoneAudioTrack?.dispose();
          _customMicrophoneAudioTrack = null;
          await customTrack?.dispose();

          SdkTracer.shared.endSpan(
            changeMicSpan,
            message:
                'Microphone device recorded while the mic is muted; it will be applied on the next unmuteMic()',
          );
          return;
        }

        await _disableMic(parentSpan: changeMicSpan);

        customTrack ??= await VideoSDK.createMicrophoneAudioTrack(
            microphoneId: device.deviceId,
            encoderConfig: _micConfig.encoderConfig,
            noiseConfig: _micConfig.noiseConfig ?? const {});

        if (customTrack == null) {
          SdkTracer.shared.endSpan(
            changeMicSpan,
            category: EventCategory.error,
            success: false,
            attributes: {
              'error': VideoSDKErrors[3012]!['message']!,
            },
            message:
                'Microphone change failed. Error: custom track could not be created',
          );

          _eventEmitter.emit("error", VideoSDKErrors[3012]);
          log("An error occurred in changeMic(): VIDEOSDK ERROR :: ${VideoSDKErrors[3012]?['code']}  :: ${VideoSDKErrors[3012]?['name']} :: ${VideoSDKErrors[3012]?['message']}");

          return;
        }

        await _enableMicImpl(
            customTrack: customTrack, parentSpan: changeMicSpan);

        SdkTracer.shared.endSpan(
          changeMicSpan,
          message: 'Microphone changed successfully',
        );
      } catch (e) {
        log("An error occurred in changeMic(): Something went wrong, and the microphone could not be changed. Please try again.");

        //
        SdkTracer.shared.endSpan(
          changeMicSpan,
          success: false,
          message: 'Microphone change failed. Error: ${e.toString()}',
          category: EventCategory.error,
        );
      }
    } else {
      throw UnsupportedError(
          'The changeMic() method is not supported for Mobile devices, Use switchAudioDevice() method instead.');
    }
  }

  /// Returns the device ID of the currently selected microphone.
  ///
  /// ⚠️ **Deprecated:**
  /// This getter is deprecated and will be removed in a future release.
  /// Use [selectedMic] instead.
  ///
  /// On mobile platforms, this returns the selected audio output device ID.
  /// On non-mobile platforms, this returns the selected audio input
  /// (microphone) device ID.
  ///
  /// ### Returns
  ///
  /// - A [String] representing the selected microphone device ID,
  ///   or `null` if no device is selected.
  @Deprecated('Use selectedMic instead')
  String? get selectedMicId => _getSelectedMicId();

  String? _getSelectedMicId() {
    if (_isMobilePlatform()) {
      return _selectedAudioOutput?.deviceId;
    } else {
      return _selectedAudioInput?.deviceId;
    }
  }

  /// Returns the currently selected microphone device.
  ///
  /// On desktop platforms, this returns the selected audio input
  /// (microphone) device.
  ///
  /// On mobile platforms (Android and iOS), this returns the selected
  /// audio output device, as explicit microphone device selection
  /// is not supported.
  ///
  /// ### Returns
  ///
  /// - An [AudioDeviceInfo] representing the currently selected
  ///   microphone (or audio output on mobile platforms),
  ///   or `null` if no device is selected.
  ///
  /// ### **Example**
  /// ```dart
  /// final mic = room.selectedMic;
  ///
  /// if (mic != null) {
  ///   print('Selected audio device: ${mic.label}');
  ///   print('Device ID: ${mic.deviceId}');
  /// } else {
  ///   print('No audio device selected');
  /// }
  /// ```

  AudioDeviceInfo? get selectedMic => _selectedMic();
  AudioDeviceInfo? _selectedMic() {
    if (_isMobilePlatform()) {
      return _selectedAudioOutput;
    } else {
      return _selectedAudioInput;
    }
  }

  /// Indicates whether the local participant’s microphone is currently enabled.
  ///
  /// This returns `true` if the microphone is unmuted and actively publishing
  /// audio, and `false` if the microphone is muted or disabled.
  ///
  /// ### Returns
  ///
  /// - `true` if the microphone is enabled
  /// - `false` if the microphone is disabled
  ///
  bool get micEnabled => _micState;

  /// Indicates whether the local participant’s WebCam is currently enabled.
  ///
  /// This returns `true` if the WebCam is enabled and actively publishing
  /// video, and `false` if the WebCam is disabled.
  ///
  /// ### Returns
  ///
  /// - `true` if the WebCam is enabled
  /// - `false` if the WebCam is disabled
  bool get camEnabled => _camState;

//
  Future<void> _enablePeerMic(String peerId) async {
    if (!_ensureJoined("participant.unmuteMic")) return;

    SpanScope? enablePeerMicSpan;

    enablePeerMicSpan = SdkTracer.shared.startSpan(
      spanName: 'Peer($peerId) microphone enable requested',
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
    );

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('enablePeerMic', {
          "peerId": peerId,
        });
      } else {
        SdkTracer.shared.endSpan(
          enablePeerMicSpan,
          success: false,
          message: 'Enable Peer Mic for $peerId Failed, websocket was null',
          category: EventCategory.error,
          attributes: {
            'peerId': peerId,
            'error': 'Websocket was null',
          },
        );
        return;
      }

      SdkTracer.shared.endSpan(
        enablePeerMicSpan,
        message: 'Peer microphone enable request sent successfully',
      );
    } catch (error) {
      log("Error while enabling peer's mic: $error");

      SdkTracer.shared.endSpan(
        enablePeerMicSpan,
        success: false,
        message: "Error in participant's unmute() -> ${error.toString()}",
        category: EventCategory.error,
        attributes: {
          'peerId': peerId,
          'error': error.toString(),
        },
      );
    }
  }

  //
  Future<void> _disablePeerMic(String peerId) async {
    if (!_ensureJoined("participant.muteMic")) return;

    SpanScope? disablePeerMicSpan;

    disablePeerMicSpan = SdkTracer.shared.startSpan(
      spanName: 'Peer($peerId) microphone disable requested',
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
    );

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('disablePeerMic', {
          "peerId": peerId,
        });
      } else {
        //Silent: participant.muteMic() already reported this to the app.
        SdkTracer.shared.endSpan(
          disablePeerMicSpan,
          success: false,
          message: 'Disable Peer Mic for $peerId Failed, websocket was null',
          category: EventCategory.error,
          attributes: {
            'peerId': peerId,
            'error': 'Websocket was null',
          },
        );
        return;
      }

      SdkTracer.shared.endSpan(
        disablePeerMicSpan,
        message: 'Peer microphone disable request sent successfully',
      );
    } catch (error) {
      log("Error while disabling peer's mic: $error");

      SdkTracer.shared.endSpan(
        disablePeerMicSpan,
        success: false,
        message: "Error in participant's muteMic() -> ${error.toString()}",
        category: EventCategory.error,
        attributes: {
          'peerId': peerId,
          'error': error.toString(),
        },
      );
    }
  }

  //
  Future<void> _enablePeerCamera(String peerId) async {
    if (!_ensureJoined("participant.enableCam")) return;

    SpanScope? enablePeerCameraSpan;

    enablePeerCameraSpan = SdkTracer.shared.startSpan(
      spanName: 'Peer($peerId) WebCam enable requested',
      component: ComponentCategory.media,
      category: EventCategory.telemetry,
    );

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('enablePeerWebcam', {
          "peerId": peerId,
        });
      } else {
        //Silent: participant.enableCam() already reported this to the app.
        SdkTracer.shared.endSpan(
          enablePeerCameraSpan,
          success: false,
          message: 'Enable Peer Camera for $peerId Failed, websocket was null',
          category: EventCategory.error,
          attributes: {
            'peerId': peerId,
            'error': 'Websocket was null',
          },
        );
        return;
      }

      SdkTracer.shared.endSpan(
        enablePeerCameraSpan,
        message: 'Peer WebCam enable request sent successfully',
      );
    } catch (error) {
      log("Error while enabling peer's WebCam $error");

      SdkTracer.shared.endSpan(
        enablePeerCameraSpan,
        success: false,
        message: "Error in participant's enableCam() -> ${error.toString()}",
        category: EventCategory.error,
        attributes: {
          'peerId': peerId,
          'error': error.toString(),
        },
      );
    }
  }

  //
  Future<void> _disablePeerCamera(String peerId) async {
    if (!_ensureJoined("participant.disableCam")) return;

    SpanScope? disablePeerCameraSpan;

    disablePeerCameraSpan = SdkTracer.shared.startSpan(
      spanName: 'Peer($peerId) WebCam disable requested',
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
    );

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('disablePeerWebcam', {
          "peerId": peerId,
        });
      } else {
        //Silent: participant.disableCam() already reported this to the app.
        SdkTracer.shared.endSpan(
          disablePeerCameraSpan,
          success: false,
          message:
              'Disable Peer Camera for $peerId Failed \n websocket was null',
          category: EventCategory.error,
          attributes: {
            'peerId': peerId,
            'error': 'Websocket was null',
          },
        );
        return;
      }

      SdkTracer.shared.endSpan(
        disablePeerCameraSpan,
        message: 'Peer WebCam disable request sent successfully',
      );
    } catch (error) {
      log("Error while disabling peer's WebCam $error");

      SdkTracer.shared.endSpan(
        disablePeerCameraSpan,
        success: false,
        message: "Error in participant's enableCam() -> ${error.toString()}",
        category: EventCategory.error,
        attributes: {
          'peerId': peerId,
          'error': error.toString(),
        },
      );
    }
  }

  //consumeMicStreams() Calling
  Future<void> _consumeMicStreams(String peerId) async {
    if (_closed) return;
    SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
      name: "consumeMicStreams() Calling",
      component: ComponentCategory.meeting,
      attributes: {
        'peerId': peerId,
      },
    );
    try {
      if (_webSocket != null) {
        await _webSocket!
            .sendRequest("consumeAudioStreams", {"peerId": peerId});
      } else {
        SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
          name: "consumeMicStreams() Failed",
          component: ComponentCategory.meeting,
          attributes: {
            'peerId': peerId,
            'error': 'Websocket was null',
          },
        );
        return;
      }
    } catch (error) {
      log("Error while consuming peer's mic $error");
      SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
        name: "consumeMicStreams() Failed",
        component: ComponentCategory.meeting,
        attributes: {
          'peerId': peerId,
          'error': error.toString(),
        },
      );
    }
  }

  //
  Future<void> _stopConsumingMicStreams(String peerId) async {
    if (_closed) return;
    SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
      name: "stopConsumingMicStreams() Calling",
      component: ComponentCategory.meeting,
      attributes: {
        'peerId': peerId,
      },
    );
    try {
      if (_webSocket != null) {
        await _webSocket!
            .sendRequest("stopConsumingAudioStreams", {"peerId": peerId});
      } else {
        SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
          name: "stopConsumingMicStreams() Failed",
          component: ComponentCategory.meeting,
          attributes: {
            'peerId': peerId,
            'error': 'Websocket was null',
          },
        );
        return;
      }
    } catch (error) {
      log("Error while stopping peer's mic $error");
      SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
        name: "stopConsumingMicStreams() Failed",
        component: ComponentCategory.meeting,
        attributes: {
          'peerId': peerId,
          'error': error.toString(),
        },
      );
    }
  }

  //
  Future<void> _consumeWebcamStreams(String peerId) async {
    if (_closed) return;

    SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
      name: "consumeWebcamStreams() Calling",
      component: ComponentCategory.meeting,
      attributes: {
        'peerId': peerId,
      },
    );
    try {
      if (_webSocket != null) {
        await _webSocket!
            .sendRequest("consumeVideoStreams", {"peerId": peerId});
      } else {
        SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
          name: "consumeWebcamStreams() Failed",
          component: ComponentCategory.meeting,
          attributes: {
            'peerId': peerId,
            'error': 'Websocket was null',
          },
        );
        return;
      }
    } catch (error) {
      SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
        name: "consumeWebcamStreams() Failed",
        component: ComponentCategory.meeting,
        attributes: {
          'peerId': peerId,
          'error': error.toString(),
        },
      );
    }
  }

  //
  Future<void> _stopConsumingWebcamStreams(String peerId) async {
    SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
      name: "stopConsumingWebcamStreams() Calling",
      component: ComponentCategory.meeting,
      attributes: {
        'peerId': peerId,
      },
    );
    try {
      if (_webSocket != null) {
        await _webSocket!
            .sendRequest("stopConsumingVideoStreams", {"peerId": peerId});
      } else {
        SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
          name: "stopConsumingWebcamStreams() Failed",
          component: ComponentCategory.meeting,
          attributes: {
            'peerId': peerId,
            'error': 'Websocket was null',
          },
        );
        return;
      }
    } catch (error) {
      SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
        name: "stopConsumingWebcamStreams() Failed",
        component: ComponentCategory.meeting,
        attributes: {
          'peerId': peerId,
          'error': error.toString(),
        },
      );
    }
  }

  //
  Future<void> _removePeer(String peerId) async {
    if (!_ensureJoined("participant.remove")) return;

    final participantSpan = _peerSpans[peerId];

    final removePeerSpan = SdkTracer.shared.startSpan(
      spanName: 'Removing peer $peerId',
      parentSpan: participantSpan,
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
    );

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('removePeer', {
          "peerId": peerId,
        });
      } else {
        //Silent: participant.remove() already reported this to the app.
        SdkTracer.shared.endSpan(
          removePeerSpan,
          success: false,
          message: 'Remove $peerId Peer Failed, websocket was null',
          category: EventCategory.error,
          attributes: {
            'peerId': peerId,
            'error': 'Websocket was null',
          },
        );
        return;
      }

      SdkTracer.shared.endSpan(
        removePeerSpan,
        message: 'Peer removed successfully',
      );
    } catch (error) {
      log("Error while removing peer $error");

      SdkTracer.shared.endSpan(
        removePeerSpan,
        success: false,
        message: "Error in participant's removePeer() -> ${error.toString()}",
        category: EventCategory.error,
        attributes: {
          'peerId': peerId,
          'error': error.toString(),
        },
      );
    }
  }

  Future<void> _discardLandedProducer(
      Producer producer, String source, SpanScope? parentSpan) async {
    SdkTracer.shared.traceEvent(
      spanName:
          'Discarding $source producer : device was turned off before it landed',
      parentScope: parentSpan,
      component: ComponentCategory.media,
      category: EventCategory.telemetry,
      attributes: {
        'producerId': producer.id,
      },
    );

    if (source == 'webcam') {
      //The producer that would have promoted a pending recycle is the one
      //being thrown away, so nothing is coming to consume it. _disableCamImpl
      //clears this too, but only the routes that go through it — a route that
      //drops intent without a teardown would otherwise leave it armed for an
      //unrelated later producer to promote.
      _codecRecyclePending = null;
    }

    try {
      producer.close();
    } catch (_) {}

    try {
      await _webSocket?.sendRequest('closeProducer', {
        'producerId': producer.id,
      });
    } catch (error) {
      SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
            name: 'Error discarding $source producer',
            attributes: {'error': error.toString()},
            success: false,
            parentScope: parentSpan,
          );
    }
  }

  Future<void> _addProducer(Producer producer, SpanScope? parentSpan) async {
    try {
      final Consumer consumer = Consumer(
        peerId: localParticipant.id,
        appData: producer.appData,
        localId: producer.localId,
        producerId: producer.id,
        id: producer.id,
        stream: producer.stream,
        rtpParameters: producer.rtpParameters,
        track: producer.track,
        closed: producer.closed,
        rtpReceiver: null,
      );

      switch (producer.source) {
        case 'mic':
          {
            if (!_micEnabled) {
              _micState = false;
              await _discardLandedProducer(producer, 'mic', parentSpan);
              break;
            }

            SdkTracer.shared.traceEvent(
              spanName: "Emitting STREAM_ENABLE Event",
              parentScope: parentSpan,
              attributes: {
                'kind': 'audio',
                'peerId': localParticipant.id,
              },
              category: EventCategory.telemetry,
              component: ComponentCategory.media,
            );
            _eventEmitter.emit(
              "stream-enabled-${localParticipant.id}",
              {
                "audio": consumer,
              },
            );

            Producer? oldProducer = _micProducer;

            _micProducer = producer;
            // disable the mic in Web if the input device get changed/disconnected
            if (kIsWeb) {
              _micProducer?.track.onEnded = () {
                _disableMic(trackEnded: true);
              };
            }

            if (oldProducer != null) {
              // oldProducer.track.stop();
              oldProducer.close();
            }

            unawaited(_setupProducerEncryption(_micProducer!));

            break;
          }
        case 'webcam':
          {
            if (!_camEnabled) {
              _camState = false;
              await _discardLandedProducer(producer, 'webcam', parentSpan);
              break;
            }
            final RTCVideoRenderer renderer = RTCVideoRenderer();
            await renderer.initialize();

            //initialize() is real platform work, so re-read intent after it.
            if (!_camEnabled) {
              _camState = false;
              await renderer.dispose();
              await _discardLandedProducer(producer, 'webcam', parentSpan);
              break;
            }

            renderer.srcObject = consumer.stream;

            _cameraRenderer = renderer;
            _cameraProducer = producer;

            SdkTracer.shared.traceEvent(
              spanName: "Emitting STREAM_ENABLE Event",
              parentScope: parentSpan,
              attributes: {
                'kind': 'video',
                'peerId': localParticipant.id,
              },
              category: EventCategory.telemetry,
              component: ComponentCategory.media,
            );
            _eventEmitter.emit(
              "stream-enabled-${localParticipant.id}",
              {
                "video": consumer,
                "renderer": renderer,
              },
            );

            //R8: commit the codec to the store only now, from the producer's
            //actual RTP parameters — never from a pre-produce guess. A failed
            //produce leaves the stored (requested) codec untouched, so the
            //next attempt re-runs the fallback logic from the real intent.
            final String? producedMime =
                producer.rtpParameters.codecs.isNotEmpty
                    ? producer.rtpParameters.codecs.first.mimeType.toLowerCase()
                    : null;
            final VideoCodec? producedCodec = _mimeToVideoCodec[producedMime];
            if (producedCodec != null &&
                producedCodec != _customVideoTrackConfig.codec) {
              _customVideoTrackConfig =
                  _customVideoTrackConfig.copyWith(codec: producedCodec);
            }

            //Promotes an in-flight recycle to "done" and clears the guard on
            //any other produce, in one assignment: _codecRecyclePending is
            //null unless a recycle is waiting on this producer.
            _codecRecycleFrom = _codecRecyclePending;
            _codecRecyclePending = null;

            unawaited(_setupProducerEncryption(_cameraProducer!));

            break;
          }
        case 'screen':
          {
            _screenshareRenderer = RTCVideoRenderer();
            await _screenshareRenderer!.initialize();

            _screenshareRenderer!.setSrcObject(
                stream: consumer.stream, trackId: consumer.track.id);
            SdkTracer.shared.traceEvent(
              spanName: "Emitting STREAM_ENABLE Event",
              parentScope: parentSpan,
              attributes: {
                'kind': 'share',
                'peerId': localParticipant.id,
              },
              category: EventCategory.telemetry,
              component: ComponentCategory.media,
            );
            _eventEmitter.emit(
              "stream-enabled-${localParticipant.id}",
              {
                "share": consumer,
                "shareRenderer": _screenshareRenderer as RTCVideoRenderer,
              },
            );

            _screenshareProducer = producer;

            unawaited(_setupProducerEncryption(_screenshareProducer!));

            break;
          }
        case 'screen-audio':
          {
            _screenShareAudioRenderer = RTCVideoRenderer();
            await _screenShareAudioRenderer!.initialize();

            _screenShareAudioRenderer!.srcObject = consumer.stream;
            SdkTracer.shared.traceEvent(
              spanName: "Emitting STREAM_ENABLE Event",
              parentScope: parentSpan,
              attributes: {
                'kind': 'share-audio',
                'peerId': localParticipant.id,
              },
              category: EventCategory.telemetry,
              component: ComponentCategory.media,
            );
            _eventEmitter.emit(
              "stream-enabled-${localParticipant.id}",
              {
                "share": consumer,
                "audioRenderer": _screenShareAudioRenderer as RTCVideoRenderer,
              },
            );
            _screenShareAudioProducer = producer;

            unawaited(_setupProducerEncryption(_screenShareAudioProducer!));

            break;
          }
      }
    } catch (e) {
      SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
        name: "Error in _addProducer()",
        attributes: {
          "error": e.toString(),
        },
      );
    }
  }

  Future<void> _setupProducerEncryption(Producer producer) async {
    if (VideoSDK.keyProvider == null || producer.rtpSender == null) {
      return;
    }

    SpanScope? producerEncryptionSpan;
    try {
      producerEncryptionSpan = SdkTracer.shared.startSpan(
        spanName: 'Encryption starting for ${producer.kind} Producer',
        parentSpan: _joinSpanScope,
        component: ComponentCategory.meeting,
        category: EventCategory.telemetry,
      );
    } catch (_) {}
    try {
      KeyProvider? _keyProvider;

      if (VideoSDK.e2eeType == 'meeting') {
        _keyProvider = VideoSDK.keyProvider!.keyProvider;
      } else if (VideoSDK.e2eeType == 'participant') {
        _keyProvider = VideoSDK.keyProvider!.keyMap[localParticipant.id];
      }

      if (_keyProvider == null) {
        log(
          "E2EE Error in _setupProducerEncryption(): KeyProvider is null for e2eeType '${VideoSDK.e2eeType}'",
        );
        return;
      }

      var frameCryptor =
          await frameCryptorFactory.createFrameCryptorForRtpSender(
        participantId: localParticipant.id,
        sender: producer.rtpSender!,
        algorithm: Algorithm.kAesGcm,
        keyProvider: _keyProvider,
      );

      final String kindToEmit =
          producer.appData['share'] == true ? 'share' : producer.kind;

      frameCryptor.onFrameCryptorStateChanged = (participantId, state) {
        switch (state) {
          case FrameCryptorState.FrameCryptorStateNew:
            log("Frame Cryptor in New state");
          case FrameCryptorState.FrameCryptorStateOk:
            Room.e2eeEvent.emit(
              'e2ee-state-$participantId',
              kindToEmit,
              E2EEState.EncryptionSucessed,
            );
          case FrameCryptorState.FrameCryptorStateEncryptionFailed:
            Room.e2eeEvent.emit(
              'e2ee-state-$participantId',
              kindToEmit,
              E2EEState.EncryptionFailed,
            );
          case FrameCryptorState.FrameCryptorStateDecryptionFailed:
            Room.e2eeEvent.emit(
              'e2ee-state-$participantId',
              kindToEmit,
              E2EEState.DecryptionFailed,
            );
          case FrameCryptorState.FrameCryptorStateMissingKey:
            log("Frame Cryptor in Missing Key state");
          case FrameCryptorState.FrameCryptorStateKeyRatcheted:
            log("Frame Cryptor in Key ratched state");
          case FrameCryptorState.FrameCryptorStateInternalError:
            Room.e2eeEvent.emit(
              'e2ee-state-$participantId',
              kindToEmit,
              E2EEState.InternalError,
            );
        }
      };

      await frameCryptor.setEnabled(true);

      SdkTracer.shared.endSpan(
        producerEncryptionSpan,
        message: "Encryption started for ${producer.kind} Producer",
      );
    } catch (e) {
      SdkTracer.shared.endSpan(
        producerEncryptionSpan,
        success: false,
        message:
            "Encryption failed for ${producer.kind} Producer. Error: ${e.toString()}",
      );
    }
  }

  void _removeProducer(
    Producer producer,
    _ProducerType type,
    SpanScope? parentSpan,
  ) {
    try {
      String? producerId = producer.id;

      switch (type) {
        case _ProducerType.micProducer:
          producer.close();

          //Everything past the close() is room-scoped — the state flag and an
          //event the app treats as "the local audio stream is gone". Running
          //it for a producer that has already been superseded would report
          //the live one as dead, so only the current producer carries it.
          //
          //A positive identity match, deliberately: an earlier
          //`_micProducer != null &&` prefix waved every producer through
          //while the field was null, which is the whole span of a rebuild.
          //Null means the room has no live mic, so there is nothing to
          //report as gone — and _micState = false written there would stick,
          //since only _enableMicImpl sets it back. Every caller that needs
          //this half passes _micProducer itself, so none of them are
          //affected.
          if (!identical(producer, _micProducer)) {
            break;
          }

          _micProducer = null;
          _micState = false;

          SdkTracer.shared.traceEvent(
            spanName: "Emitting STREAM_DISABLED Event",
            attributes: {
              "kind": producer.kind,
              "peerId": localParticipant.id,
            },
            parentScope: parentSpan,
            category: EventCategory.telemetry,
          );
          _eventEmitter.emit(
            "stream-disabled-${localParticipant.id}",
            {
              "audioConsumerId": producerId,
            },
          );

          break;
        case _ProducerType.cameraProducer:
          //
          producer.close();
          //drop them all rather than just the stale ones.
          if (!identical(producer, _cameraProducer)) {
            break;
          }

          //Handed to the event below because the app still needs the object it
          //was given at stream-enabled to release its side of the render, but
          //the field is cleared so leave()/softClose() cannot dispose it twice.
          final RTCVideoRenderer? removedRenderer = _cameraRenderer;

          _cameraRenderer = null;
          _cameraProducer = null;
          _camState = false;

          removedRenderer?.dispose();

          SdkTracer.shared.traceEvent(
            spanName: "Emitting STREAM_DISABLED Event",
            attributes: {
              "kind": producer.kind,
              "peerId": localParticipant.id,
            },
            parentScope: parentSpan,
            category: EventCategory.telemetry,
          );

          _eventEmitter.emit(
            "stream-disabled-${localParticipant.id}",
            {
              "renderer": removedRenderer,
              "videoConsumerId": producerId,
            },
          );
          break;
        case _ProducerType.screenshareProducer:

          //
          producer.close();
          _screenshareRenderer?.dispose();
          SdkTracer.shared.traceEvent(
            spanName: "Emitting STREAM_DISABLED Event",
            attributes: {
              "kind": 'share',
              "peerId": localParticipant.id,
            },
            parentScope: parentSpan,
            category: EventCategory.telemetry,
          );
          _eventEmitter.emit(
            "stream-disabled-${localParticipant.id}",
            {
              "shareRenderer": _screenshareRenderer,
              "shareConsumerId": producerId,
            },
          );
          break;
        case _ProducerType.screenShareAudioProducer:

          //
          producer.close();
          _screenShareAudioRenderer?.dispose();
          SdkTracer.shared.traceEvent(
            spanName: "Emitting STREAM_DISABLED Event",
            attributes: {
              "kind": 'shareAudio',
              "peerId": localParticipant.id,
            },
            parentScope: parentSpan,
            category: EventCategory.telemetry,
          );
          _eventEmitter.emit(
            "stream-disabled-${localParticipant.id}",
            {
              "audioRenderer": _screenShareAudioRenderer,
              "shareConsumerId": producerId,
            },
          );
          break;
      }
    } catch (e) {
      SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
            name: "Error in _removeProducer()",
            attributes: {
              "error": e.toString(),
            },
            success: false,
            parentScope: parentSpan,
          );
    }
  }

  // Peer
  //
  void _addPeer(Map<String, dynamic> newPeer, SpanScope? span) {
    try {
      final Peer peer = Peer.fromMap(newPeer);
      //
      _peers[peer.id] = peer;
      //
      _eventEmitter.emit("peers-bloc-participant-joined", peer);

      if (span != null) {
        SdkTracer.shared.traceEvent(
          spanName: 'Emitted `PARTICIPANT_JOINED` Event',
          parentScope: span as SpanScope?,
          component: ComponentCategory.meeting,
          category: EventCategory.telemetry,
        );
      }
    } catch (e) {
      SdkTracer.shared.error("Error in _addPeer() \n ${e.toString()}",
          component: ComponentCategory.meeting);
    }
  }

  void _addCharacterPeer(Map<String, dynamic> newPeer, SpanScope? span) {
    try {
      newPeer.addAll({"mode": Mode.SEND_AND_RECV.name});
      final Peer peer = Peer.fromMap(newPeer);
      //
      _peers[peer.id] = peer;
      //
      if (span != null) {
        SdkTracer.shared.traceEvent(
          spanName: 'Emitted `CHARACTER_PARTICIPANT_JOINED` Event',
          parentScope: span as SpanScope?,
          component: ComponentCategory.meeting,
        );
      }
    } catch (e) {
      SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
            name: "Error in _addCharacterPeer()",
            attributes: {
              "error": e.toString(),
            },
            success: false,
            parentScope: span,
          );
    }
  }

  //
  void __removePeer(String peerId, LeaveReason? reason, SpanScope? span) {
    try {
      final removedPeer = _peers.remove(peerId);

      if (removedPeer?.audio != null) {
        SdkTracer.shared.traceEvent(
          spanName: 'Emitting `STREAM_DISABLED` Event',
          component: ComponentCategory.meeting,
          category: EventCategory.telemetry,
          attributes: {
            'peerId': peerId,
            'kind': 'audio',
          },
        );
        _eventEmitter.emit("stream-disabled-$peerId",
            {"audioConsumerId": removedPeer?.audio?.id});
      }

      if (removedPeer?.video != null) {
        SdkTracer.shared.traceEvent(
          spanName: 'Emitting `STREAM_DISABLED` Event',
          component: ComponentCategory.meeting,
          category: EventCategory.telemetry,
          attributes: {
            'peerId': peerId,
            'kind': 'video',
          },
        );
        _eventEmitter.emit("stream-disabled-$peerId", {
          "videoConsumerId": removedPeer?.video?.id,
          "renderer": removedPeer?.renderer
        });
      }

      if (removedPeer?.share != null) {
        SdkTracer.shared.traceEvent(
          spanName: 'Emitting `STREAM_DISABLED` Event',
          component: ComponentCategory.meeting,
          category: EventCategory.telemetry,
          attributes: {
            'peerId': peerId,
            'kind': 'share',
          },
        );
        _eventEmitter.emit("stream-disabled-$peerId", {
          "shareConsumerId": removedPeer?.share?.id,
          "shareRenderer": removedPeer?.shareRenderer
        });
      }

      //presenter left
      if (peerId == _activePresenterId) {
        _eventEmitter.emit("peers-bloc-presenter-changed", null);
        SdkTracer.shared.traceEvent(
          spanName: 'Emitted `PRESENTER-CHANGED` Event',
          component: ComponentCategory.meeting,
          category: EventCategory.telemetry,
          attributes: {
            'peerId': null,
          },
        );
      }

      _eventEmitter.emit("peers-bloc-participant-left", peerId, reason);

      if (span != null) {
        SdkTracer.shared.traceEvent(
          spanName:
              'Emitted `PARTICIPANT_LEFT` Event with reason: ${reason!.message} and code: ${reason.code}',
          parentScope: span,
          component: ComponentCategory.meeting,
        );
      }
    } catch (e) {
      SdkTracer.shared.error("Error in __removePeer() \n ${e.toString()}",
          component: ComponentCategory.meeting);
    }
  }

  //
  Future<void> _addPeerConsumer(
      String peerId, Consumer consumer, SpanScope? span) async {
    try {
      //  log("_addPeerConsumer ${consumer.kind} $peerId ${consumer.appData['share']}");
      if (consumer.kind == 'video' && consumer.appData['share'] == true) {
        //
        _peers[peerId] = _peers[peerId]!.copyWith(
          shareRenderer: RTCVideoRenderer(),
          share: consumer,
        );

        await _peers[peerId]!.shareRenderer!.initialize();

        //
        _peers[peerId]!.shareRenderer!.setSrcObject(
            stream: _peers[peerId]!.share!.stream,
            trackId: _peers[peerId]!.share!.track.id);

        //
        _eventEmitter.emit("stream-enabled-$peerId", {
          "shareRenderer": _peers[peerId]!.shareRenderer,
          "share": _peers[peerId]!.share
        });
        SdkTracer.shared.traceEvent(
          spanName: 'Emitted STREAM-ENABLED Event',
          parentScope: span,
          attributes: {
            "peerId": peerId,
            "kind": consumer.kind,
          },
          category: EventCategory.telemetry,
          component: ComponentCategory.media,
        );
        //
        _eventEmitter.emit("peers-bloc-presenter-changed", peerId);
        SdkTracer.shared.traceEvent(
          spanName: 'Emitted `PRESENTER-CHANGED` Event',
          component: ComponentCategory.meeting,
          category: EventCategory.telemetry,
          attributes: {
            'peerId': peerId,
          },
        );

        unawaited(_setupConsumerDecryption(consumer, peerId));

        consumer.on('transportclose', () {
          try {
            _peers[peerId]?.shareRenderer?.dispose();
          } catch (error) {
            SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
                  name: "Error in consumer transportclose share",
                  attributes: {"error": error.toString()},
                  component: ComponentCategory.media,
                  success: false,
                );
          }
        });
      } else if (consumer.kind == 'video') {
        //
        _peers[peerId] = _peers[peerId]!.copyWith(
          renderer: RTCVideoRenderer(),
          video: consumer,
        );

        // A fresh renderer was just created for this peer; clear any stale
        // "disposed" marker so this renderer is disposed normally later.
        _disposedVideoRendererPeerIds.remove(peerId);

        //
        await _peers[peerId]!.renderer!.initialize();

        //
        _peers[peerId]!.renderer!.setSrcObject(
            stream: _peers[peerId]!.video!.stream,
            trackId: _peers[peerId]!.video!.track.id);

        _eventEmitter.emit("stream-enabled-$peerId", {
          "renderer": _peers[peerId]!.renderer,
          "video": _peers[peerId]!.video
        });
        SdkTracer.shared.traceEvent(
          spanName: 'Emitted STREAM-ENABLED Event',
          parentScope: span,
          attributes: {
            "peerId": peerId,
            "kind": consumer.kind,
          },
          category: EventCategory.telemetry,
          component: ComponentCategory.media,
        );

        unawaited(_setupConsumerDecryption(consumer, peerId));

        consumer.on('transportclose', () async {
          try {
            await _peers[peerId]?.renderer?.dispose();
            _disposedVideoRendererPeerIds.add(peerId);
          } catch (error) {
            _disposedVideoRendererPeerIds.add(peerId);
            SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
                  name: "Error in consumer transportclose video",
                  attributes: {"error": error.toString()},
                  parentScope: span,
                  component: ComponentCategory.media,
                  success: false,
                );
          }
        });
      } else if (consumer.kind == 'audio' &&
          consumer.appData['share'] == true) {
        _peers[peerId] = _peers[peerId]!.copyWith(
          audio: consumer,
          audioRenderer: RTCVideoRenderer(),
        );

        //
        await _peers[peerId]!.audioRenderer!.initialize();

        //
        _peers[peerId]!.audioRenderer!.srcObject =
            _peers[peerId]!.audio!.stream;

        //
        SdkTracer.shared.traceEvent(
          spanName: 'Emitted STREAM-ENABLED Event',
          parentScope: span,
          attributes: {
            "peerId": peerId,
            "kind": consumer.kind,
          },
          category: EventCategory.telemetry,
          component: ComponentCategory.media,
        );
        _eventEmitter.emit("stream-enabled-$peerId", {
          "audioRenderer": _peers[peerId]!.audioRenderer,
          "shareAudio": _peers[peerId]!.audio
        });

        if (_selectedAudioOutput != null) {
          _peers[peerId]!
              .audioRenderer!
              .audioOutput(_selectedAudioOutput!.deviceId);
        }

        unawaited(_setupConsumerDecryption(consumer, peerId));

        consumer.on('transportclose', () {
          try {
            _peers[peerId]?.audioRenderer?.dispose();
          } catch (error) {
            SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
                  name: "Error in consumer transportclose shareAudio",
                  attributes: {"error": error.toString()},
                  component: ComponentCategory.media,
                  parentScope: span,
                  success: false,
                );
          }
        });
      } else if (consumer.kind == 'audio') {
        if (kIsWeb) {
          _peers[peerId] = _peers[peerId]!.copyWith(
            audio: consumer,
            audioRenderer: RTCVideoRenderer(),
          );

          AudioHTMLInterface().startAudio(_peers[peerId]!.audio);

          SdkTracer.shared.traceEvent(
            spanName: 'Emitted STREAM-ENABLED Event',
            parentScope: span,
            attributes: {
              "peerId": peerId,
              "kind": consumer.kind,
            },
            category: EventCategory.telemetry,
            component: ComponentCategory.media,
          );
          _eventEmitter.emit("stream-enabled-$peerId", {
            "audioRenderer": _peers[peerId]!.audioRenderer,
            "audio": _peers[peerId]!.audio
          });

          if (_selectedAudioOutput != null) {
            AudioHTMLInterface()
                .setAudioOutputDevice(_selectedAudioOutput!.deviceId);
          }

          unawaited(_setupConsumerDecryption(consumer, peerId));

          consumer.on('transportclose', () {
            try {
              _peers[peerId]?.audioRenderer?.dispose();
            } catch (error) {
              SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
                    name: "Error in consumer transportclose audio",
                    attributes: {"error": error.toString()},
                    parentScope: span,
                    component: ComponentCategory.media,
                    success: false,
                  );
            }
          });
        } else {
          _peers[peerId] = _peers[peerId]!.copyWith(
            audio: consumer,
          );

          if (!kIsWeb) {
            if (Platform.isIOS) {
              if (_selectedAudioOutput != null) {
                switchAudioDevice(_selectedAudioOutput!);
              }
            }
          }

          SdkTracer.shared.traceEvent(
            spanName: 'Emitted STREAM-ENABLED Event',
            parentScope: span,
            attributes: {
              "peerId": peerId,
              "kind": consumer.kind,
            },
            component: ComponentCategory.media,
          );
          _eventEmitter.emit("stream-enabled-$peerId", {
            "audio": consumer,
          });

          unawaited(_setupConsumerDecryption(consumer, peerId));
        }
      }
    } catch (e) {
      SdkTracer.shared.traceEvent(
        spanName: "Error in addPeerConsumer()",
        attributes: {"error": e.toString()},
        parentScope: span,
        component: ComponentCategory.media,
        success: false,
      );
    }
  }

  Future<void> _setupConsumerDecryption(
      Consumer consumer, String participantId) async {
    if (VideoSDK.keyProvider == null || consumer.rtpReceiver == null) {
      return;
    }

    SpanScope? consumerDecryptionSpan;

    try {
      consumerDecryptionSpan = SdkTracer.shared.startSpan(
        spanName: 'Decryption Strating for ${consumer.kind} Consumer',
        parentSpan: _joinSpanScope,
        component: ComponentCategory.meeting,
      );
    } catch (_) {}

    try {
      KeyProvider? _keyProvider;

      if (VideoSDK.e2eeType == 'meeting') {
        _keyProvider = VideoSDK.keyProvider!.keyProvider;
      } else if (VideoSDK.e2eeType == 'participant') {
        _keyProvider = VideoSDK.keyProvider!.keyMap[participantId];
      }
      final String kindToEmit =
          consumer.appData['share'] == true ? 'share' : consumer.kind!;

      if (_keyProvider == null) {
        Room.e2eeEvent.emit(
          'e2ee-state-$participantId',
          kindToEmit,
          E2EEState.DecryptionFailed,
        );
        return;
      }

      var frameCryptor =
          await frameCryptorFactory.createFrameCryptorForRtpReceiver(
        participantId: participantId,
        receiver: consumer.rtpReceiver!,
        algorithm: Algorithm.kAesGcm,
        keyProvider: _keyProvider,
      );

      frameCryptor.onFrameCryptorStateChanged = (participantId, state) {
        switch (state) {
          case FrameCryptorState.FrameCryptorStateNew:
            log("Frame Cryptor in New state");
          case FrameCryptorState.FrameCryptorStateOk:
            Room.e2eeEvent.emit(
              'e2ee-state-$participantId',
              kindToEmit,
              E2EEState.DecryptionSucessed,
            );
          case FrameCryptorState.FrameCryptorStateEncryptionFailed:
            Room.e2eeEvent.emit(
              'e2ee-state-$participantId',
              kindToEmit,
              E2EEState.EncryptionFailed,
            );
          case FrameCryptorState.FrameCryptorStateDecryptionFailed:
            Room.e2eeEvent.emit(
              'e2ee-state-$participantId',
              kindToEmit,
              E2EEState.DecryptionFailed,
            );
          case FrameCryptorState.FrameCryptorStateMissingKey:
            log("Frame Cryptor in Missing Key state");
          case FrameCryptorState.FrameCryptorStateKeyRatcheted:
            log("Frame Cryptor in Key ratched state");
          case FrameCryptorState.FrameCryptorStateInternalError:
            Room.e2eeEvent.emit(
              'e2ee-state-$participantId',
              kindToEmit,
              E2EEState.InternalError,
            );
        }
      };

      await frameCryptor.setEnabled(true);

      try {
        if (consumerDecryptionSpan != null) {
          SdkTracer.shared.endSpan(
            consumerDecryptionSpan,
            message: "Decryption started for ${consumer.kind} Consumer.",
          );
        }
      } catch (_) {}
    } catch (e) {
      try {
        if (consumerDecryptionSpan != null) {
          SdkTracer.shared.endSpan(
            consumerDecryptionSpan,
            success: false,
            message:
                "Decryption failed for ${consumer.kind} Consumer. Error: ${e.toString()}",
          );
        }
      } catch (_) {}
    }
  }

  /// @nodoc
  bool get e2eeEnabled {
    if (VideoSDK.keyProvider == null) {
      return false;
    } else {
      return true;
    }
  }

  Future<void> _removePeerConsumer(String consumerId) async {
    try {
      final Peer? peer = _peers.values.firstWhereOrNull(
        (p) => p.consumers.contains(
          consumerId,
        ),
      );

      //
      if (peer != null) {
        if (peer.audio?.id == consumerId) {
          final consumer = peer.audio;
          if (kIsWeb) {
            AudioHTMLInterface().stopAudio(peer.audio!.track.id!);
          }

          _peers[peer.id] = _peers[peer.id]!.removeAudio();

          await consumer?.close();

          final Participant participant = participants[peer.id]!;
          var state = 'ended';
          var streamId = consumer!.track.id;
          participant.handleStreamStateChanged(state, streamId);
          SdkTracer.shared.traceEvent(
            spanName: "Emitting STREAM_DISABLE Event",
            attributes: {
              "kind": "audio",
              "peerId": peer.id,
            },
            component: ComponentCategory.participant,
            category: EventCategory.telemetry,
          );
          _eventEmitter.emit(
            "stream-disabled-${peer.id}",
            {
              "audioConsumerId": consumer.id,
            },
          );
        } else if (peer.video?.id == consumerId) {
          final consumer = peer.video;
          final renderer = peer.renderer;
          _peers[peer.id] = _peers[peer.id]!.removeVideoAndRenderer();

          await consumer?.close();
          if (!_disposedVideoRendererPeerIds.contains(peer.id)) {
            await renderer?.dispose();
          }
          _disposedVideoRendererPeerIds.remove(peer.id);

          final Participant participant = participants[peer.id]!;
          var state = 'ended';
          var streamId = consumer!.track.id;
          participant.handleStreamStateChanged(state, streamId);
          SdkTracer.shared.traceEvent(
            spanName: "Emitting STREAM_DISABLE Event",
            attributes: {
              "kind": "video",
              "peerId": peer.id,
            },
            component: ComponentCategory.participant,
            category: EventCategory.telemetry,
          );
          _eventEmitter.emit(
            "stream-disabled-${peer.id}",
            {
              "renderer": renderer,
              "videoConsumerId": consumer.id,
            },
          );
        } else if (peer.share?.id == consumerId) {
          final consumer = peer.share;
          final renderer = peer.shareRenderer;

          _peers[peer.id] = _peers[peer.id]!.removeShareAndRenderer();

          await consumer?.close();

          await renderer?.dispose();

          final Participant participant = participants[peer.id]!;
          var state = 'ended';
          var streamId = consumer!.track.id;
          participant.handleStreamStateChanged(state, streamId);

          SdkTracer.shared.traceEvent(
            spanName: "Emitting STREAM_DISABLE Event",
            attributes: {
              "kind": "share",
              "peerId": peer.id,
            },
            component: ComponentCategory.participant,
            category: EventCategory.telemetry,
          );

          _eventEmitter.emit(
            "stream-disabled-${peer.id}",
            {
              "shareRenderer": renderer,
              "shareConsumerId": consumer.id,
            },
          );

          _eventEmitter.emit("peers-bloc-presenter-changed");
          SdkTracer.shared.traceEvent(
            spanName: 'Emitted `PRESENTER-CHANGED` Event',
            component: ComponentCategory.meeting,
            category: EventCategory.telemetry,
            attributes: {
              'peerId': peer.id,
            },
          );
        }
      }
    } catch (e) {
      SdkTracer.shared.traceEvent(
        spanName: "Error in removePeerConsumer()",
        attributes: {"error": e.toString()},
        component: ComponentCategory.media,
        success: false,
      );
    }
  }

  //
  void _changePeerConsumerQuality(
    String consumerId, {
    required int spatialLayer,
    required int temporalLayer,
  }) {
    try {
      final Peer? peer = _peers.values.firstWhereOrNull(
        (p) => p.consumers.contains(
          consumerId,
        ),
      );

      //
      if (peer != null) {
        //
        if (peer.video?.id == consumerId) {
          //
          Peer newPeer = _peers[peer.id]!.copyWith(
              video: peer.video!.copyWith(
            spatialLayer: spatialLayer,
            temporalLayer: temporalLayer,
          ));

          //
          _peers[peer.id] = newPeer;

          String prevQuality = "";
          String currentQuality = "HIGH";

          int totalSpatialLayers = peer.video!.appData['encodings'].length;
          if (totalSpatialLayers > 1) {
            prevQuality = totalSpatialLayers - 1 - peer.video!.spatialLayer == 0
                ? "HIGH"
                : totalSpatialLayers - 1 - peer.video!.spatialLayer == 1
                    ? "MEDIUM"
                    : "LOW";
            currentQuality = totalSpatialLayers - 1 - spatialLayer == 0
                ? "HIGH"
                : totalSpatialLayers - 1 - spatialLayer == 1
                    ? "MEDIUM"
                    : "LOW";
          } else {
            prevQuality = "HIGH";
            currentQuality = "HIGH";
          }

          SdkTracer.shared.traceEvent(
            spanName:
                "Consumer Peer ${peer.id} changed to $currentQuality, previous quality was $prevQuality",
            attributes: {
              "spatialLayer": spatialLayer,
              "temporalLayer": temporalLayer,
              "prevQuality": prevQuality,
              "currentQuality": currentQuality,
            },
            component: ComponentCategory.media,
            success: true,
          );
          _eventEmitter.emit("quality-changed-${peer.id}", {
            "spatialLayer": spatialLayer,
            "temporalLayer": temporalLayer,
            "prevQuality": prevQuality,
            "currentQuality": currentQuality
          });
        }
      }
    } catch (e) {
      SdkTracer.shared.traceEvent(
        spanName: "Error in changePeerConsumerQuality()",
        attributes: {"error": e.toString()},
        component: ComponentCategory.media,
        success: false,
      );
    }
  }

  List<dynamic> _getStats(String id, String type) {
    try {
      if (type == "producer") {
        return _latestStats[id] ?? [];
      } else if (type == "consumer") {
        Consumer? consumer = _recvTransport?.consumers[id];

        if (consumer != null) {
          List<dynamic> stats = _latestStats[id] ?? [];
          if (consumer.track.kind == "video" && stats.isNotEmpty) {
            stats[0]['spatialLayer'] = consumer.spatialLayer;
            stats[0]['temporalLayer'] = consumer.temporalLayer;
          }
          return stats;
        } else {
          return [];
        }
      }
      return [];
    } catch (e) {
      SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
            name: "Error in getStats()",
            attributes: {"error": e.toString()},
            component: ComponentCategory.media,
            success: false,
          );
      return [];
    }
  }

  //
  void _producerCallback(Producer producer, [SpanScope? parentSpan]) {
    try {
      if (producer.source == 'mic') {
        producer.on('transportclose', () {
          //Use the callback's own producer: during a producer replacement two
          //producers briefly overlap, and _micProducer may already point at
          //the new one — the old producer's callback must not tear it down.
          _removeProducer(
            producer,
            _ProducerType.micProducer,
            parentSpan,
          );
        });

        producer.on('trackended', () {
          //Stale-callback guard: only the live producer's track may disable
          //the mic; a replaced producer's late event is ignored.
          if (!identical(producer, _micProducer)) return;
          _disableMic(trackEnded: true).catchError((data) {
            SdkTracer.shared.traceEvent(
              spanName: "Microphone track ended or Microphone disconnected!",
              attributes: {"error": data.toString()},
              component: ComponentCategory.media,
              success: false,
              category: EventCategory.error,
              parentScope: parentSpan,
            );
          });
        });
        _micInProgress = false;
      } else if (producer.source == 'webcam') {
        producer.on('transportclose', () {
          //Use the callback's own producer — see the mic handler above.
          _removeProducer(producer, _ProducerType.cameraProducer, parentSpan);
        });

        producer.on('trackended', () {
          //Stale-callback guard: codec replay overlaps two camera producers;
          //the replaced one's late trackended must not disable the new one.
          //A producer this room has already torn down is closed, and its
          //track ending is never news — that is the case the identity check
          //below cannot see, because _cameraProducer stays null for the whole
          //span of a recycle and would wave the old producer through.
          if (producer.closed) {
            return;
          }

          //A null _cameraProducer past that point means this handler is armed
          //but _addProducer has not assigned it yet — it awaits the renderer
          //first — so treat that as "this producer is the live one" rather
          //than dropping a genuine trackended and leaving a dead producer
          //reported as live.
          if (_cameraProducer != null &&
              !identical(producer, _cameraProducer)) {
            return;
          }
          _disableCamImpl().catchError((data) {
            SdkTracer.shared.traceEvent(
              spanName: "Camera track ended or Camera disconnected!",
              attributes: {"error": data.toString()},
              component: ComponentCategory.media,
              success: false,
              category: EventCategory.error,
              parentScope: parentSpan,
            );
          });
        });
        _cameraInProgress = false;
      } else if (producer.source == 'share') {
        producer.on('transportclose', () {
          _closeForegroundService();
          _removeProducer(_screenshareProducer!,
              _ProducerType.screenshareProducer, parentSpan);
        });

        producer.on('trackended', () {
          _closeForegroundService();
          disableScreenShare().catchError((data) {
            SdkTracer.shared.traceEvent(
              spanName:
                  "Screen share track ended or Screen share disconnected!",
              attributes: {"error": data.toString()},
              component: ComponentCategory.media,
              success: false,
              category: EventCategory.error,
              parentScope: parentSpan,
            );
          });
        });
        _screenShareInProgress = false;
      }
      _addProducer(producer, parentSpan);
    } catch (e) {
      SdkTracer.shared.traceEvent(
        spanName: "Error in producerCallback()",
        attributes: {"error": e.toString()},
        component: ComponentCategory.media,
        success: false,
        category: EventCategory.error,
        parentScope: parentSpan,
      );
    }
  }

  void _consumerCallback(Consumer consumer, [dynamic accept]) {
    accept({});
    SpanScope? consumerSpan = _consumerSpans[consumer.id];
    _addPeerConsumer(consumer.peerId, consumer, consumerSpan);
  }

  //Not using anymore.
  // Future<MediaStream> _createAudioStream() async {
  //   //
  //   Map<String, dynamic> mediaConstraints = {
  //     'audio': {
  //       'optional': [
  //         {
  //           'sourceId': _selectedAudioInput?.deviceId,
  //         },
  //       ],
  //     },
  //   };

  //   //
  //   MediaStream stream =
  //       await navigator.mediaDevices.getUserMedia(mediaConstraints);

  //   //
  //   return stream;
  // }

  //Not using anymore.
  // Future<MediaStream> _createVideoStream() async {
  //   //
  //   Map<String, dynamic> mediaConstraints = <String, dynamic>{
  //     'audio': false,
  //     'video': {
  //       'mandatory': {
  //         'minWidth':
  //             '1280', // Provide your own width, height and frame rate here
  //         'minHeight': '720',
  //         'minFrameRate': '30',
  //       },
  //       'optional': [
  //         {
  //           'sourceId': _selectedVideoInput?.deviceId,
  //         },
  //       ],
  //     },
  //   };
  //   //
  //   MediaStream stream =
  //       await navigator.mediaDevices.getUserMedia(mediaConstraints);

  //   //
  //   return stream;
  // }

  Future<MediaStream?> _createShareStream(SpanScope? span) async {
    try {
      //
      var mediaConstraints = <String, dynamic>{
        'audio': true,
        'video': _selectedScreenSource == null
            ? true
            : {
                'deviceId': {'exact': _selectedScreenSource!.id},
              }
      };

      if (!kIsWeb) {
        if (Platform.isIOS) {
          mediaConstraints['video'] = {'deviceId': 'broadcast'};
          mediaConstraints = {
            'video': {'deviceId': 'broadcast'}
          };
        }
      }
      //
      MediaStream? stream;

      final isWebMobile = kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android);

      if (isWebMobile) {
        SdkTracer.shared.endSpan(
          span,
          message: VideoSDKErrors[3015]!['message']!,
          success: false,
          category: EventCategory.error,
          dashboardLog: true,
          attributes: {
            " error":
                "Error in enableScreeshare() -> Stream Creation Failed due to unsupported platfrom"
          },
        );
        _eventEmitter.emit("error", VideoSDKErrors[3015]);
        return null;
      } else {
        stream = await navigator.mediaDevices.getDisplayMedia(mediaConstraints);
        stream.getVideoTracks().first.onEnded = () => disableScreenShare();
      }

      return stream;
    } catch (e) {
      SdkTracer.shared.endSpan(
        span,
        message: "Stream Creation Failed due to error : ${e.toString()}",
        category: EventCategory.error,
        success: false,
      );
      return null;
    }
  }

  // PubSub
  Future<void> _pubsubPublish({topic, message, options, payload}) async {
    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('pubsubPublish', {
          'topic': topic,
          'message': message,
          'options': options,
          'payload': payload
        });
      } else {
        //Silent: pubSub.publish() already reported this to the app.
        return;
      }
    } catch (error) {
      SdkTracer.shared.traceEvent(
        spanName: "Error in pubsubPublish() -> publish failed",
        success: false,
        category: EventCategory.error,
      );
    }
  }

  Future<dynamic> _pubsubSubscribe(topic) async {
    try {
      if (_webSocket != null) {
        var msgList =
            await _webSocket!.sendRequest('pubsubSubscribe', {'topic': topic});
        return msgList;
      } else {
        //Silent: pubSub.subscribe() already reported this to the app.
        return null;
      }
    } catch (error) {
      SdkTracer.shared.traceEvent(
        spanName: "Error in pubsubSubscribe() -> subscribe failed",
        success: false,
        category: EventCategory.error,
      );
    }
  }

  Future<void> _pubsubUnsubscribe(topic) async {
    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('pubsubUnsubscribe', {'topic': topic});
      } else {
        //Silent: pubSub.unsubscribe() already reported this to the app.
        return;
      }
    } catch (error) {
      SdkTracer.shared.traceEvent(
        spanName: "Error in pubsubUnsubscribe() ->  failed",
        success: false,
        category: EventCategory.error,
        attributes: {
          'error': error.toString(),
        },
      );
    }
  }

  void _handlePubSubMessage(data) {
    _topicEventEmitter.emit(
      data['topic'],
      PubSubMessage.fromJson(data),
    );
  }

  ///@nodoc

  Future<void> setConsumerQuality(consumerId, String quality) async {
    late int? spatialLayers;
    late int? temporalLayers;
    SpanScope? consumerSpan = _consumerSpans[consumerId];

    try {
      if (quality == 'low' || quality == 'med' || quality == 'high') {
        final layers = VIDEO_LAYERS[_maxResolution]![quality];
        spatialLayers = layers?['s'];
        temporalLayers = layers?['t'];
      } else {
        String sCh = quality[0];
        String tCh = quality[2];
        int s = int.parse(quality[1]);
        int t = int.parse(quality[3]);

        if (s > 2 || t > 2 || sCh != "s" || tCh != "t") {
          throw ("");
        }

        spatialLayers = s;
        temporalLayers = t;
      }

      try {
        SdkTracer.shared.traceEvent(
          spanName: 'Setting quality to $quality',
          parentScope: consumerSpan,
          component: ComponentCategory.participant,
          category: EventCategory.telemetry,
          attributes: {
            "spatialLayers": spatialLayers,
            "temporalLayers": temporalLayers,
          },
        );
      } catch (_) {}

      _setConsumerPreferredLayers(
          consumerId, spatialLayers, temporalLayers, consumerSpan!);
    } catch (error) {
      SdkTracer.shared.to(OutputTarget.toBackend).traceEvent(
        name: "setConsumerQuality failed due to : ${error.toString()}",
        category: EventCategory.error,
        success: false,
        attributes: {
          "consumerId": consumerId,
          "quality": quality,
        },
      );
    }
  }

  Future<void> _setConsumerPreferredLayers(
      consumerId, spatialLayer, temporalLayer, SpanScope? parentSpan) async {
    try {
      SpanScope internalSpan = SdkTracer.shared.startSpan(
          spanName: "Setting preferred spatial and temporal layers",
          parentSpan: parentSpan,
          component: ComponentCategory.participant,
          attributes: {
            "spatialLayer": spatialLayer,
            "temporalLayer": temporalLayer,
          });
      if (_webSocket != null) {
        await _webSocket!.sendRequest('setConsumerPreferredLayers', {
          "consumerId": consumerId,
          "spatialLayer": spatialLayer,
          "temporalLayer": temporalLayer,
        });
      } else {
        SdkTracer.shared.endSpan(
          internalSpan,
          message: "Failed to set preferred layers",
          success: false,
          category: EventCategory.error,
        );
        _eventEmitter.emit("error", VideoSDKErrors[3022]);
        SdkTracer.shared.endSpan(
          parentSpan,
          message: "Failed to set preferred layers",
          success: false,
          category: EventCategory.error,
        );
        log("An error occurred in setConsumerQuality(): the method was called while the meeting was in the connecting state. Please try again after joining the meeting.");
        return;
      }

      SdkTracer.shared.endSpan(
        parentSpan,
        message: "Preferred layers set successfully",
      );
    } catch (error) {
      SdkTracer.shared.endSpan(
        parentSpan,
        message:
            "Failed to set preferred spatial and temporal layers with error: ${error.toString()}",
        success: false,
        category: EventCategory.error,
      );
    }
  }

  ///@nodoc

  void setViewPort(
      consumerId, viewportWidth, viewportHeight, participantId) async {
    SpanScope? participantSpan = _peerSpans[participantId];
    try {
      Consumer? consumer = _recvTransport?.getConsumer(consumerId);
      if (consumer == null) {
        return;
      }

      SpanScope? viewportSpan = SdkTracer.shared.startSpan(
        spanName: "Setting ViewPort",
        parentSpan: participantSpan,
        component: ComponentCategory.participant,
        attributes: {
          "viewportWidth": "$viewportWidth",
          "viewportHeight": "$viewportHeight",
        },
      );

      SpanScope? layerSpan = SdkTracer.shared.startSpan(
        spanName: "Fetching spatial & temporal layer settings",
        parentSpan: viewportSpan,
        component: ComponentCategory.participant,
      );

      Map<String, dynamic>? layers = SdkCapabilities.getAdaptivePreferredLayers(
        consumer,
        viewportWidth,
        viewportHeight,
      );
      if (layers != null) {
        int newPreferredSpatialLayer = layers['newPreferredSpatialLayer'];
        int newPreferredTemporalLayer = layers['newPreferredTemporalLayer'];

        if (newPreferredSpatialLayer == consumer.spatialLayer &&
            newPreferredTemporalLayer == consumer.temporalLayer) {
          SdkTracer.shared.endSpan(
            layerSpan,
            message: "Viewport adaptation skipped (no change)",
          );
          SdkTracer.shared.endSpan(
            viewportSpan,
            message: "Viewport adaptation skipped (no change)",
          );
          return;
        }

        await _setConsumerPreferredLayers(
          consumerId,
          newPreferredSpatialLayer,
          newPreferredTemporalLayer,
          layerSpan,
        );
      } else {
        SdkTracer.shared.endSpan(
          layerSpan,
          success: false,
          message: "Failed to calculate layers",
        );
        SdkTracer.shared.endSpan(
          viewportSpan,
          success: false,
          message: "Failed to calculate layers",
        );
        return;
      }

      SdkTracer.shared.endSpan(
        viewportSpan,
        message: "Viewport set successfully",
      );
    } catch (e) {
      SdkTracer.shared.traceEvent(
        spanName: "Error in setViewPort()",
        category: EventCategory.error,
        attributes: {"error": e.toString()},
        parentScope: participantSpan,
        component: ComponentCategory.participant,
      );
    }
  }

  /// Registers an event listener for a specific meeting event.
  ///
  /// This method allows you to listen for SDK events such as participant
  /// updates, stream changes, or meeting lifecycle events. When the
  /// specified event occurs, the provided handler will be invoked.
  ///
  /// ### **Parameters**
  ///
  /// - [event]:
  ///   The [Events] type to listen for.
  ///
  /// - [handler]:
  ///   A callback function that will be executed when the event is emitted.
  ///   The callback may receive event-specific data as arguments.
  ///
  /// ### **Example**
  /// ```dart
  /// // Listen for participant joined event
  /// room.on(Events.participantJoined, (event) {
  ///   print('Participant joined: ${event.participantId}');
  /// });
  ///
  /// // Listen for room joined event
  /// room.on(Events.roomJoined, (_) {
  ///   print('Successfully joined the room');
  /// });
  /// ```
  void on(Events event, Function handler) => _on(event, handler);
  //
  void _on(Events event, Function handler) {
    _eventEmitter.on(event.parseToString(), handler);
  }

  /// Removes a previously registered event listener.
  ///
  /// - This method stops listening for the specified event and removes
  /// the associated handler. After removal, the handler will no longer
  /// be invoked when the event is emitted.
  ///
  /// ### **Parameters**
  ///
  /// - [event]:
  ///   The [Events] type for which the listener should be removed.
  ///
  /// - [handler]:
  ///   The same callback function that was previously registered using [on].
  ///
  /// ### **Example**
  /// ```dart
  /// void onParticipantLeft(event) {
  ///   print('Participant left: ${event.participantId}');
  /// }
  ///
  /// // Register event listener
  /// room.on(Events.participantLeft, onParticipantLeft);
  ///
  /// // Remove event listener
  /// room.off(Events.participantLeft, onParticipantLeft);
  /// ```
  ///
  void off(Events event, Function handler) => _off(event, handler);
  void _off(Events event, Function handler) {
    _eventEmitter.remove(event.parseToString(), handler);
  }

  /// @nodoc
  Character createCharacter({required CharacterConfig characterConfig}) {
    var character = Character(
        characterConfig: characterConfig,
        eventEmitter: _eventEmitter,
        enablePeerMic: _enablePeerMic,
        disablePeerMic: _disablePeerMic,
        enablePeerCamera: _enablePeerCamera,
        disablePeerCamera: _disablePeerCamera,
        joinCharacter: _joinCharacter,
        removeCharacter: _removeCharacter,
        sendMessage: _sendCharacterMessage,
        interruptCharacter: _interruptCharacter);

    return character;
  }

  dynamic _joinCharacter({CharacterConfig? characterConfig}) async {
    if (!_ensureJoined("character.join")) return false;

    SpanScope? joinCharacterSpan;
    Map<String, dynamic> data = {};
    if (characterConfig != null) data["config"] = characterConfig.toJson();

    joinCharacterSpan = SdkTracer.shared.startSpan(
      spanName: 'Join Character Requested',
      component: ComponentCategory.meeting,
      attributes: {
        'config': characterConfig != null
            ? jsonEncode(characterConfig.toJson())
            : "Config not specified",
      },
    );

    try {
      if (_webSocket != null) {
        var response = await _webSocket!.sendRequest("joinCharacter", data);

        SdkTracer.shared.endSpan(
          joinCharacterSpan,
          message: 'joinCharacter() End',
        );
        return response;
      } else {
        //Silent: character.join() already reported this to the app.
        SdkTracer.shared.endSpan(
          joinCharacterSpan,
          success: false,
          message: 'joinCharacter() Failed, websocket was null',
          category: EventCategory.error,
        );
        return false;
      }
    } catch (error) {
      log("Character join request failed due to an error : $error");

      SdkTracer.shared.endSpan(
        joinCharacterSpan,
        success: false,
        message: 'joinCharacter() Failed \n ${error.toString()}',
        category: EventCategory.error,
        attributes: {
          'error': error.toString(),
        },
      );
      return false;
    }
  }

  void _removeCharacter(config) async {
    if (!_ensureJoined("character.leave")) return;

    SpanScope? removeCharacterSpan;
    Map<String, dynamic> data = {};
    if (config != null) data["config"] = config;

    removeCharacterSpan = SdkTracer.shared.startSpan(
      spanName: 'Remove Character Requested',
      component: ComponentCategory.meeting,
      attributes: {
        'config': config != null ? jsonEncode(config) : "Config not specified",
      },
    );

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest("leaveCharacter", data);

        SdkTracer.shared.endSpan(
          removeCharacterSpan,
          message: 'removeCharacter() End',
        );
      } else {
        //Silent: character.leave() already reported this to the app.
        SdkTracer.shared.endSpan(
          removeCharacterSpan,
          success: false,
          message: 'removeCharacter() Failed, websocket was null',
          category: EventCategory.error,
        );
        return;
      }
    } catch (error) {
      log("Character leave request failed due to an error : $error");

      SdkTracer.shared.endSpan(
        removeCharacterSpan,
        success: false,
        message: 'removeCharacter() Failed \n ${error.toString()}',
        category: EventCategory.error,
        attributes: {
          'error': error.toString(),
        },
      );
    }
  }

  void _sendCharacterMessage(interactionId, text) async {
    if (!_ensureJoined("character.sendMessage")) return;

    final sendSpan = SdkTracer.shared.startSpan(
      spanName: 'Send Character Message Requested',
      component: ComponentCategory.meeting,
      attributes: {
        'interactionId': interactionId,
        'text': text,
      },
    );

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest("sendCharacterMessage",
            {"interactionId": interactionId, "text": text});

        SdkTracer.shared.endSpan(
          sendSpan,
          message: 'Character message sent successfully',
        );
      } else {
        //Silent: character.sendMessage() already reported this to the app.
        SdkTracer.shared.endSpan(
          sendSpan,
          success: false,
          message: 'Send Character Message Failed, websocket was null',
          category: EventCategory.error,
        );
        return;
      }
    } catch (error) {
      log("Character send message request failed due to an error : $error");

      SdkTracer.shared.endSpan(
        sendSpan,
        success: false,
        message: 'Send Character Message Failed: ${error.toString()}',
        category: EventCategory.error,
        attributes: {
          'error': error.toString(),
        },
      );
    }
  }

  void _interruptCharacter(interactionId) async {
    if (!_ensureJoined("character.interrupt")) return;

    final interruptSpan = SdkTracer.shared.startSpan(
      spanName: 'Interrupt Character Requested',
      component: ComponentCategory.meeting,
      attributes: {
        'interactionId': interactionId,
      },
    );

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest(
            "interruptCharacter", {"interactionId": interactionId});

        SdkTracer.shared.endSpan(
          interruptSpan,
          message: 'Character interrupted successfully',
        );
      } else {
        //Silent: character.interrupt() already reported this to the app.
        SdkTracer.shared.endSpan(
          interruptSpan,
          success: false,
          message: 'Interrupt Character Failed, websocket was null',
          category: EventCategory.error,
        );
        return;
      }
    } catch (error) {
      log("Character interrupt request failed due to an error : $error");

      SdkTracer.shared.endSpan(
        interruptSpan,
        success: false,
        message: 'Interrupt Character Failed: ${error.toString()}',
        category: EventCategory.error,
        attributes: {
          'error': error.toString(),
        },
      );
    }
  }

  /// It is used to initialize a whiteboard session.
  ///
  /// ### **Example**
  /// ```dart
  /// // start whiteBoard
  /// await room.startWhiteBoard();
  /// ```
  Future<void> startWhiteboard() async {
    if (!_ensureJoined("startWhiteboard")) return;
    await _startWhiteboard();
  }

  //
  Future<void> _startWhiteboard() async {
    SpanScope? startWBSpan;

    try {
      startWBSpan = SdkTracer.shared.startSpan(
        spanName: 'Start Whiteboard Requested',
        component: ComponentCategory.meeting,
        category: EventCategory.telemetry,
      );
    } catch (_) {}

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest("startWhiteboard", {
          "version": "v2",
        });

        if (startWBSpan != null) {
          SdkTracer.shared.endSpan(
            startWBSpan,
            message: 'Whiteboard start request sent successfully',
          );
        }
      } else {
        SdkTracer.shared.endSpan(
          startWBSpan,
          message: VideoSDKErrors[3022]!['message']!,
          success: false,
          category: EventCategory.error,
        );
        //Silent: startWhiteboard() already reported this to the app.
        return;
      }
    } catch (error) {
      //
      if (startWBSpan != null) {
        SdkTracer.shared.endSpan(
          startWBSpan,
          success: false,
          dashboardLog: true,
          message: 'Start whiteboard failed',
          attributes: {
            'error': "Error in startWhiteboard() -> ${error.toString()}",
          },
          category: EventCategory.error,
        );
      }
    }
  }

  ///  It is used to end a whiteboard session.
  ///
  /// ### **Example**
  /// ```dart
  /// // stop whiteBoard
  /// await room.stopWhiteboard();
  /// ```
  Future<void> stopWhiteboard() async {
    if (!_ensureJoined("stopWhiteboard")) return;
    await _stopWhiteboard();
  }

  //
  Future<void> _stopWhiteboard() async {
    SpanScope? stopWBSpan;
    try {
      stopWBSpan = SdkTracer.shared.startSpan(
        spanName: 'Stop Whiteboard Requested',
        component: ComponentCategory.meeting,
        category: EventCategory.telemetry,
      );
    } catch (_) {}

    try {
      if (_webSocket != null) {
        await _webSocket!.sendRequest('stopWhiteboard', {});

        if (stopWBSpan != null) {
          SdkTracer.shared.endSpan(
            stopWBSpan,
            message: 'Whiteboard stop request sent successfully',
          );
        }
      } else {
        SdkTracer.shared.endSpan(
          stopWBSpan,
          message: VideoSDKErrors[3022]!['message']!,
          success: false,
          category: EventCategory.error,
        );
        //Silent: stopWhiteboard() already reported this to the app.
        return;
      }
    } catch (error) {
      if (stopWBSpan != null) {
        SdkTracer.shared.endSpan(
          stopWBSpan,
          success: false,
          dashboardLog: true,
          message: 'Stop whiteboard failed',
          attributes: {
            'error': "Error in stopWhiteboard() -> ${error.toString()}",
          },
          category: EventCategory.error,
        );
      }
    }
  }

  /// @nodoc

  static String getParticipentId() {
    return localParticipantId;
  }

  /// Pauses active media streams in the current meeting.
  ///
  /// - This method allows you to pause media streams for the local participant.
  /// If no `kind` is provided, all active media streams (audio, video, and
  /// screen-sharing) will be paused.
  ///
  /// ### **Parameters**
  ///
  /// - [kind] *(optional)*:
  ///   Specifies the type of media stream to pause.
  ///   If omitted, all media streams will be paused.
  ///
  ///   Possible values:
  ///   - `"audio"`: Pauses audio streams
  ///   - `"video"`: Pauses video streams
  ///   - `"share"`: Pauses screen-sharing video streams
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Pause all media streams
  /// await meeting.pauseAllStreams();
  ///
  /// // Pause only audio streams
  /// await meeting.pauseAllStreams(kind: 'audio');
  ///
  /// // Pause only video streams
  /// await meeting.pauseAllStreams(kind: 'video');
  /// ```
  Future<void> pauseAllStreams({String? kind}) async {
    if (!_ensureJoined("pauseAllStreams")) return;
    await _pauseAllStreams(kind: kind);
  }

  Future<void> _pauseAllStreams({String? kind}) async {
    SpanScope? pauseConsumersSpan;

    kind = kind ?? "all";
    final label = kind == "all" ? "media" : kind;

    pauseConsumersSpan = SdkTracer.shared.startSpan(
      spanName: 'Pause all $label streams requested',
      parentSpan: _joinSpanScope,
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
      attributes: {
        'kind': kind,
      },
    );

    try {
      if (_webSocket != null) {
        var res = await _webSocket!.sendRequest(
          "pauseAllConsumers",
          {"kind": kind},
        );

        Map<String, dynamic> resObject = res as Map<String, dynamic>;
        List<dynamic>? consumersWithIssues = resObject['consumersWithIssues'];
        bool success = false;

        if (consumersWithIssues != null && consumersWithIssues.isNotEmpty) {
          var resRetry = await _webSocket!.sendRequest(
            "pauseAllConsumers",
            {"kind": kind},
          );

          resObject = resRetry as Map<String, dynamic>;
          consumersWithIssues = resObject['consumersWithIssues'];

          if (consumersWithIssues == null || consumersWithIssues.isEmpty) {
            success = true;
          } else {
            SdkTracer.shared.endSpan(
              pauseConsumersSpan,
              success: false,
              message: "Failed to pause all $label streams",
            );
            return;
          }
        } else {
          success = true;
        }

        if (success) {
          SdkTracer.shared.traceEvent(
            spanName: "Emitting PAUSED_ALL_STREAMS event",
            parentScope: pauseConsumersSpan,
            component: ComponentCategory.meeting,
            category: EventCategory.telemetry,
          );

          _eventEmitter.emit("paused-all-stream", kind);

          SdkTracer.shared.endSpan(
            pauseConsumersSpan,
            message: "All $kind streams paused successfully",
          );
        }
      }
    } catch (error) {
      SdkTracer.shared.endSpan(
        pauseConsumersSpan,
        success: false,
        message: "Error in pauseAllStreams() -> ${error.toString()}",
        category: EventCategory.error,
      );
    }
  }

  /// Resumes media streams that were previously paused in the meeting.
  ///
  /// - This method resumes paused media streams for the local participant.
  /// If no `kind` is provided, all paused media streams (audio, video, and
  /// screen-sharing) will be resumed.
  ///
  /// ### **Parameters**
  ///
  /// - [kind] *(optional)*:
  ///   Specifies the type of media stream to resume.
  ///   If omitted, all media streams will be resumed.
  ///
  ///   Possible values:
  ///   - `"audio"`: Resumes audio streams
  ///   - `"video"`: Resumes video streams
  ///   - `"share"`: Resumes screen-sharing video streams
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Resume all media streams
  /// await meeting.resumeAllStreams();
  ///
  /// // Resume only audio streams
  /// await meeting.resumeAllStreams(kind: 'audio');
  ///
  /// // Resume only video streams
  /// await meeting.resumeAllStreams(kind: 'video');
  /// ```
  Future<void> resumeAllStreams({String? kind}) async {
    if (!_ensureJoined("resumeAllStreams")) return;
    await _resumeAllStreams(kind: kind);
  }

  Future<void> _resumeAllStreams({String? kind}) async {
    SpanScope? resumeConsumersSpan;

    kind = kind ?? "all";
    final label = kind == "all" ? "media" : kind;

    resumeConsumersSpan = SdkTracer.shared.startSpan(
      spanName: 'Resume all $label streams requested',
      parentSpan: _joinSpanScope,
      component: ComponentCategory.meeting,
      category: EventCategory.telemetry,
      attributes: {
        'kind': kind,
      },
    );

    try {
      if (_webSocket != null) {
        var res = await _webSocket!.sendRequest(
          "resumeAllConsumers",
          {"kind": kind},
        );

        Map<String, dynamic> resObject = res as Map<String, dynamic>;
        List<dynamic>? consumersWithIssues = resObject['consumersWithIssues'];
        bool success = false;

        if (consumersWithIssues != null && consumersWithIssues.isNotEmpty) {
          var resRetry = await _webSocket!.sendRequest(
            "resumeAllConsumers",
            {"kind": kind},
          );

          resObject = resRetry as Map<String, dynamic>;
          consumersWithIssues = resObject['consumersWithIssues'];

          if (consumersWithIssues == null || consumersWithIssues.isEmpty) {
            success = true;
          } else {
            SdkTracer.shared.endSpan(
              resumeConsumersSpan,
              success: false,
              message: "Resume all $label streams failed",
            );
            return;
          }
        } else {
          success = true;
        }

        if (success) {
          SdkTracer.shared.traceEvent(
            spanName: "Emitting RESUMED_ALL_STREAMS event",
            parentScope: resumeConsumersSpan,
            component: ComponentCategory.meeting,
            category: EventCategory.telemetry,
          );

          _eventEmitter.emit("resumed-all-stream", kind);
        }

        SdkTracer.shared.endSpan(
          resumeConsumersSpan,
          message: "All $label streams resumed successfully",
        );
      }
    } catch (error) {
      SdkTracer.shared.endSpan(
        resumeConsumersSpan,
        success: false,
        message: "Error in resumeAllStreams() -> ${error.toString()}",
        category: EventCategory.error,
      );
    }
  }

  /// Uploads a Base64-encoded file to VideoSDK’s temporary storage.
  ///
  /// - This method uploads the provided Base64 file data to VideoSDK’s
  /// temporary storage system and returns a URL that can be used to
  /// retrieve the uploaded file.
  ///
  /// ### **Parameters**
  ///
  /// - [base64Data]:
  ///   The Base64-encoded string of the file to be uploaded.
  ///   Convert your file to Base64 and pass the encoded value here.
  ///
  /// - [token]:
  ///   Your VideoSDK authentication token.
  ///   Learn more about tokens:
  ///   https://docs.videosdk.live/flutter/guide/video-and-audio-calling-api-sdk/authentication-and-tokens
  ///
  /// - [fileName]:
  ///   The name of the file, including its extension
  ///   (for example, `myImage.jpeg`).
  ///
  /// ### Returns
  ///
  /// - A [String] representing the `fileUrl`, which can be used to retrieve
  ///   the file from VideoSDK’s storage system.
  ///
  /// ### **Example**
  /// ```dart
  /// final fileUrl = await room.uploadBase64File(
  ///   base64Data: '<Your file base64>',
  ///   token: '<VIDEOSDK_TOKEN>',
  ///   fileName: 'myImage.jpeg',
  /// );
  ///
  /// print('File URL: $fileUrl');
  /// ```
  Future<String?> uploadBase64File({
    required String base64Data,
    required String token,
    required String fileName,
  }) async {
    if (!_ensureJoined("uploadBase64File")) return null;
    return _uploadBase64File(
        base64Data: base64Data, token: token, fileName: fileName);
  }

  Future<String?> _uploadBase64File({
    required String base64Data,
    required String token,
    required String fileName,
  }) async {
    SpanScope? uploadBase64FileSpan;
    try {
      if (base64Data.isEmpty || token.isEmpty || fileName.isEmpty) {
        throw Exception("please provide base64Data, token and fileName");
      }

      uploadBase64FileSpan = SdkTracer.shared.startSpan(
        spanName: "Uploading Base64 File",
        component: ComponentCategory.media,
        category: EventCategory.telemetry,
        attributes: {
          'fileName': fileName,
        },
      );

      final url = Uri.parse("https://$baseUrl/base64-upload?roomId=$id");

      final body = jsonEncode({
        "fileName": fileName,
        "base64Data": base64Data,
      });

      final response = await http.post(
        url,
        body: body,
        headers: {
          "Content-Type": "application/json",
          "Authorization": token,
        },
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        SdkTracer.shared.endSpan(
          uploadBase64FileSpan,
          message: "Base64 File uploaded successfully",
        );
        return responseData['url'];
      } else {
        SdkTracer.shared.endSpan(
          uploadBase64FileSpan,
          success: false,
          message: "Failed to upload file: ${response.statusCode}",
        );
        throw Exception('Failed to upload file: ${response.statusCode}');
      }
    } catch (e) {
      SdkTracer.shared.endSpan(
        uploadBase64FileSpan,
        success: false,
        category: EventCategory.error,
        message: "Error while Uploading Base64 File",
      );
    }
    return null;
  }

  /// Retrieves a file from VideoSDK’s temporary storage as a Base64 string.
  ///
  /// - This method fetches a previously uploaded file using the `fileUrl`
  /// returned by [uploadBase64File] and returns the file data encoded
  /// as a Base64 string.
  ///
  /// ### **Parameters**
  ///
  /// - [url]:
  ///   The `fileUrl` returned by [uploadBase64File], used to locate
  ///   the file in VideoSDK’s temporary storage.
  ///
  /// - [token]:
  ///   Your VideoSDK authentication token.
  ///   Learn more about tokens:
  ///   https://docs.videosdk.live/flutter/guide/video-and-audio-calling-api-sdk/authentication-and-tokens
  ///
  /// ### Returns
  ///
  /// - A [String] containing the file data encoded in Base64 format.
  ///
  /// ### **Example**
  /// ```dart
  /// final base64 = await room.fetchBase64File(
  ///   url: '<Your fileUrl>',
  ///   token: '<VIDEOSDK_TOKEN>',
  /// );
  ///
  /// print('Base64 data: $base64');
  /// ```
  Future<String?> fetchBase64File({
    required String url,
    required String token,
  }) async {
    if (!_ensureJoined("fetchBase64File")) return null;
    return _fetchBase64File(url: url, token: token);
  }

  //
  Future<String?> _fetchBase64File({
    required String url,
    required String token,
  }) async {
    SpanScope? fetchBase64FileSpan;
    try {
      if (url.isEmpty || token.isEmpty) {
        throw Exception("please provide url and token");
      }

      fetchBase64FileSpan = SdkTracer.shared.startSpan(
        spanName: "Fetching Base64 File",
        component: ComponentCategory.media,
        category: EventCategory.telemetry,
        attributes: {
          'url': url,
        },
      );

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': token,
        },
      );

      if (response.statusCode != 200) {
        throw Exception("Failed to fetch file. Status: ${response.statusCode}");
      }

      Uint8List bytes = response.bodyBytes;
      String base64Data = base64Encode(bytes);

      SdkTracer.shared.endSpan(
        fetchBase64FileSpan,
        message: "Base64 File fetched successfully",
      );
      return base64Data;
    } catch (e) {
      SdkTracer.shared.endSpan(
        fetchBase64FileSpan,
        success: false,
        category: EventCategory.error,
        message: "Error in fetchBase64File() -> ${e.toString()}",
      );
    }
    return null;
  }

  ///@nodoc
  Future<void> startTranslation({Map<String, dynamic>? config}) async {
    if (!_ensureJoined("startTranslation")) return;

    SpanScope? startTranslationSpan;

    startTranslationSpan = SdkTracer.shared.startSpan(
      spanName: "Start Translation Requested",
      component: ComponentCategory.meeting,
      attributes: {
        "config": config != null
            ? jsonEncode(config)
            : "Translation configuration not specified",
      },
    );

    try {
      await _webSocket!.sendRequest("startTranslation", {
        "config": config,
      });

      SdkTracer.shared.endSpan(
        startTranslationSpan,
        message: "Meeting translation start request sent successfully",
      );
    } catch (error) {
      SdkTracer.shared.endSpan(
        startTranslationSpan,
        success: false,
        message: "Failed to send meeting translation start request.",
        category: EventCategory.error,
        attributes: {
          "error": error.toString(),
        },
      );

      _eventEmitter.emit("error", VideoSDKErrors[4042]);
      rethrow;
    }
  }

  ///@nodoc
  Future<void> changeTranslationLanguage(String language) async {
    if (!_ensureJoined("changeTranslationLanguage")) return;

    SpanScope? changeTranslationLanguageSpan;

    changeTranslationLanguageSpan = SdkTracer.shared.startSpan(
      spanName: "Requesting to change translation language",
      component: ComponentCategory.meeting,
      attributes: {
        "language": language,
      },
    );

    try {
      await _webSocket!.sendRequest(
        "changeTranslationLanguage",
        {"language": language},
      );

      SdkTracer.shared.endSpan(
        changeTranslationLanguageSpan,
        message: "Translation language change request sent successfully",
      );
    } catch (e) {
      SdkTracer.shared.endSpan(
        changeTranslationLanguageSpan,
        success: false,
        message: "Failed to send translation language change request",
        category: EventCategory.error,
        attributes: {
          "error": e.toString(),
        },
      );

      _eventEmitter.emit("error", VideoSDKErrors[4044]);
      rethrow;
    }
  }

  ///@nodoc
  void stopTranslation() async {
    if (!_ensureJoined("stopTranslation")) return;

    SpanScope? stopTranslationSpan;

    stopTranslationSpan = SdkTracer.shared.startSpan(
      spanName: "Stop Translation Requested",
      component: ComponentCategory.meeting,
    );

    try {
      await _webSocket!.sendRequest("stopTranslation", {});

      SdkTracer.shared.endSpan(
        stopTranslationSpan,
        message: "Meeting translation stop request sent successfully",
      );
    } catch (e) {
      SdkTracer.shared.endSpan(
        stopTranslationSpan,
        success: false,
        message: "Failed to send meeting translation stop request",
        category: EventCategory.error,
        attributes: {
          "error": e.toString(),
        },
      );

      _eventEmitter.emit("error", VideoSDKErrors[4043]);
      rethrow;
    }
  }
}

/// Defines the end-to-end encryption (E2EE) states for media streams.
///
/// - These states indicate whether media encryption or decryption
/// was successfully applied or if an error occurred during processing.
///
/// ### **Example**
/// ```dart
/// widget.participant.on(
///   Events.e2eeStateChanged,
///   (E2EEState state, Stream stream) {
///     print('$state occurred for ${stream.kind}');
///   },
/// );
/// ```
enum E2EEState {
  /// Media encryption was successfully applied to the outgoing stream.
  ///
  /// ### **Example**
  /// ```dart
  /// E2EEState.EncryptionSucessed
  /// ```
  EncryptionSucessed,

  /// Media encryption encountered an error.
  ///
  /// ### **Example**
  /// ```dart
  /// E2EEState.EncryptionFailed
  /// ```
  EncryptionFailed,

  /// Incoming media was successfully decrypted.
  ///
  /// ### **Example**
  /// ```dart
  /// E2EEState.DecryptionSucessed
  /// ```
  DecryptionSucessed,

  /// Media decryption encountered an error.
  ///
  /// ### **Example**
  /// ```dart
  /// E2EEState.DecryptionFailed
  /// ```
  DecryptionFailed,

  /// An internal encryption or decryption error occurred.
  ///
  /// ### **Example**
  /// ```dart
  /// E2EEState.InternalError
  /// ```
  InternalError,
}

enum _ProducerType {
  micProducer,
  cameraProducer,
  screenshareProducer,
  screenShareAudioProducer
}

/// Defines the connection states of a room.
///
/// - VideoSDK emits the [Events.roomStateChanged] event whenever the
/// room’s connection state changes. The current [RoomState] is
/// provided as a callback parameter.
///
/// ### **Example**
/// ```dart
/// room.on(Events.roomStateChanged, (RoomState state) {
///   print('Room state changed to: $state');
/// });
/// ```
enum RoomState {
  /// Indicates that the room is in the process of connecting.
  ///
  /// ### **Example**
  /// ```dart
  /// RoomState.connecting
  /// ```
  connecting,

  /// Indicates that the room is successfully connected.
  ///
  /// ### **Example**
  /// ```dart
  /// RoomState.connected
  /// ```
  connected,

  /// Indicates that the room connection was lost and is attempting
  /// to reconnect automatically.
  ///
  /// ### **Example**
  /// ```dart
  /// RoomState.reconnecting
  /// ```
  reconnecting,

  /// Indicates that the room is no longer connected — after [Room.leave] or
  /// [Room.end], after a failed join, or once reconnection attempts are
  /// exhausted — and cannot be rejoined.
  ///
  /// ### **Example**
  /// ```dart
  /// RoomState.disconnected
  /// ```
  disconnected,

  /// Indicates that the attempt to join the room failed and the SDK will not
  /// retry on its own.
  ///
  /// ### **Example**
  /// ```dart
  /// RoomState.failed
  /// ```
  failed,
}

///@nodoc

class OutboundTrace {
  final String? qualityLimitationReason;

  OutboundTrace({this.qualityLimitationReason});
}

///@nodoc

class RemoteInboundTrace {
  double totalRoundTripTime;
  int roundTripTimeMeasurements;

  RemoteInboundTrace({
    required this.totalRoundTripTime,
    required this.roundTripTimeMeasurements,
  });
}
