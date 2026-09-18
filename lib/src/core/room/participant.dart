// ignore_for_file: strict_top_level_inference

import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:videosdk/src/core/utils/event_emitter.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:videosdk/src/core/room/room.dart';
import 'package:videosdk/src/core/room/room_mode.dart';
import 'package:videosdk_webrtc/flutter_webrtc.dart';
import 'open_telemetry/Tracing/sdk_tracer.dart';
import 'open_telemetry/Tracing/component_category.dart';
import 'open_telemetry/Tracing/event_category.dart';
import 'open_telemetry/Tracing/span_scope.dart';

import 'events.dart';
import 'stream.dart';
import 'participant_pin_state.dart';

/// Represents a participant in the room and provides access to their media,
/// state, and event-related operations.
class Participant {
  late final EventEmitter _participantEventEmitter;
  late final EventEmitter _eventEmitter;
  int? _spatialLayer;
  int? _temporalLayer;

  String? _preferredQuality;

  /// The unique identifier of the participant who has joined the room.
  ///
  /// ### Type
  ///
  /// - `String`
  late String id;

  /// The display name of the participant who has joined the room.
  ///
  /// ### Type
  ///
  /// - `String`
  late String displayName;

  /// The media streams associated with this participant.
  ///
  /// This map contains the streams published by the participant,
  /// such as audio, video, or screen-sharing streams. Each entry
  /// is keyed by the stream type (for example, `audio`, `video`, or `share`).
  ///
  /// ### Type
  ///
  /// - `Map<String, Stream>`
  late Map<String, Stream> streams;

  /// Indicates whether this participant is the local participant.
  ///
  /// Returns `true` if the participant represents the
  /// [Participant] (you), and `false` if it represents
  /// a remote participant.
  ///
  /// ### Type
  ///
  /// - `bool`
  late bool isLocal;

  /// Represents the current mode of the participant.
  ///
  /// The participant mode defines how media is produced and/or consumed
  /// by the participant (for example, sending and receiving media,
  /// receiving only, or signaling only).
  ///
  /// ### Type
  ///
  /// - [Mode]
  ///
  /// ### **Example**
  ///
  /// ```dart
  /// // Access the participant's current mode
  /// Mode currentMode = participant.mode;
  ///
  /// if (currentMode == Mode.RECV_ONLY) {
  ///   print('Participant is in viewer mode');
  /// }
  ///
  /// // Change participant mode
  /// room.changeMode(Mode.SEND_AND_RECV);
  /// ```
  late Mode mode;

  late Function _enablePeerMic,
      _disablePeerMic,
      _enablePeerCamera,
      _disablePeerCamera,
      _setConsumerQuality,
      _setViewPortInternal,
      _getStats,
      _removePeer,
      _participantPinStateChanged;

  /// Represents the current pin state of the participant.
  ///
  /// This indicates whether the participant’s camera or screen-share
  /// stream is pinned. The [ParticipantPinState] contains the following
  /// boolean properties:
  /// - `cam`: Indicates whether the camera stream is pinned
  /// - `share`: Indicates whether the screen-share stream is pinned
  ///
  /// ### Type
  ///
  /// - `ParticipantPinState`

  late ParticipantPinState pinState;

  /// Additional metadata associated with the participant.
  ///
  /// This contains custom key-value information that was provided
  /// while creating or joining the room (for example, via `createRoom()`).
  ///
  /// ### Type
  ///
  /// - `Map<String, dynamic>?`
  Map<String, dynamic>? metaData;

  /// Whether this participant is an AI agent.
  ///
  /// Returns `false` for regular participants. Overridden to return `true`
  /// in [AgentParticipant].
  ///
  /// ### Type
  ///
  /// - `bool`
  bool get isAgent => false;

  Function? _consumeMicStreams,
      _stopConsumingMicStreams,
      _consumeWebcamStreams,
      _stopConsumingWebcamStreams;

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
  Participant(
      {required this.id,
      required this.displayName,
      required this.isLocal,
      required this.pinState,
      required this.mode,
      required EventEmitter eventEmitter,
      required Function enablePeerMic,
      required Function disablePeerMic,
      required Function enablePeerCamera,
      required Function disablePeerCamera,
      required Function setConsumerQuality,
      required Function getStats,
      required Function setViewPort,
      required Function removePeer,
      required Function participantPinStateChanged,
      Function? consumeMicStreams,
      Function? stopConsumingMicStreams,
      Function? consumeWebcamStreams,
      Function? stopConsumingWebcamStreams,
      this.metaData}) {
    //
    _eventEmitter = eventEmitter;
    //
    _enablePeerMic = enablePeerMic;
    //
    _disablePeerMic = disablePeerMic;
    //
    _enablePeerCamera = enablePeerCamera;
    //
    _disablePeerCamera = disablePeerCamera;
    //
    _setConsumerQuality = setConsumerQuality;
    //
    _getStats = getStats;
    //
    _setViewPortInternal = setViewPort;
    //
    _removePeer = removePeer;
    //
    _participantPinStateChanged = participantPinStateChanged;
    //
    _consumeMicStreams = consumeMicStreams;
    _stopConsumingMicStreams = stopConsumingMicStreams;
    _consumeWebcamStreams = consumeWebcamStreams;
    _stopConsumingWebcamStreams = stopConsumingWebcamStreams;
    //
    _participantEventEmitter = EventEmitter();
    //
    streams = {};

    // handle stream-enabled
    _eventEmitter.on(
      "stream-enabled-$id",
      (data) {
        if (data['audio'] != null) {
          final consumer = data["audio"];

          final Stream newStream = Stream(
            consumer: consumer,
            eventEmitter: _eventEmitter,
            isLocal: isLocal,
          );

          _addConsumer(newStream);
        } else if (data["renderer"] != null && data["video"] != null) {
          final consumer = data["video"];
          final renderer = data["renderer"];

          final Stream newStream = Stream(
            consumer: consumer,
            renderer: renderer,
            eventEmitter: _eventEmitter,
            isLocal: isLocal,
          );

          _addConsumer(newStream);
        } else if (data["shareRenderer"] != null && data["share"] != null) {
          final consumer = data["share"];
          final shareRenderer = data["shareRenderer"];

          final Stream newStream = Stream(
            consumer: consumer,
            renderer: shareRenderer,
            eventEmitter: _eventEmitter,
            isLocal: isLocal,
          );

          _addConsumer(newStream);
        }
      },
    );

    // handle stream-disabled
    _eventEmitter.on(
      "stream-disabled-$id",
      (data) {
        if (data['audioConsumerId'] != null) {
          final consumerId = data['audioConsumerId'];
          _removeConsumer(consumerId);
        } else if (data["renderer"] != null &&
            data["videoConsumerId"] != null) {
          final consumerId = data['videoConsumerId'];
          _removeConsumer(consumerId);
        } else if (data["shareRenderer"] != null &&
            data["shareConsumerId"] != null) {
          final consumerId = data['shareConsumerId'];
          _removeConsumer(consumerId);
        }
      },
    );

    // handle stream-paused
    _eventEmitter.on(
      "stream-paused-$id",
      (data) {
        String audioKeyType = 'audioConsumerId';
        String videoKeyType = 'videoConsumerId';
        String shareKeyType = 'shareConsumerId';

        if (data[audioKeyType] != null) {
          _pauseConsumer(audioKeyType, data);
        } else if (data[videoKeyType] != null) {
          _pauseConsumer(videoKeyType, data);
        } else if (data[shareKeyType] != null) {
          _pauseConsumer(shareKeyType, data);
        }
      },
    );

    // handle stream-resumed
    _eventEmitter.on(
      "stream-resumed-$id",
      (data) {
        String audioKeyType = 'audioConsumerId';
        String videoKeyType = 'videoConsumerId';
        String shareKeyType = 'shareConsumerId';

        if (data[audioKeyType] != null) {
          _resumeConsumer(audioKeyType, data);
        } else if (data[videoKeyType] != null) {
          _resumeConsumer(videoKeyType, data);
        } else if (data[shareKeyType] != null) {
          _resumeConsumer(shareKeyType, data);
        }
      },
    );

    // E2EE events
    Room.e2eeEvent.on('e2ee-state-$id', (String kind, E2EEState state) {
      // Find the stream that matches the kind
      Stream? stream = streams.values.firstWhere(
        (stream) => stream.kind == kind,
      );

      _participantEventEmitter.emit("e2ee-state-changed", state, stream);
    });

    // handle quality-changed
    _eventEmitter.on(
      "quality-changed-$id",
      (data) {
        _setLayers(data['spatialLayer'], data['temporalLayer'],
            data['prevQuality'], data['currentQuality']);
      },
    );

    _eventEmitter.on("pin-state-change-$id", (data) {
      _setPinState(data['state']);
    });

    _eventEmitter.on("participant-mode-changed-$id", (data) {
      mode = ModeExtension.parseToEnum(data['mode']);
      log("data :$data");
    });

    _eventEmitter.on("subs-manager-resumed-$id", (data) {
      var kind = data["kind"];
      var reason = data["reason"];
      _participantEventEmitter.emit("stream-resumed", kind, reason);
    });

    _eventEmitter.on("subs-manager-paused-$id", (data) {
      var kind = data["kind"];
      var reason = data["reason"];
      _participantEventEmitter.emit("stream-paused", kind, reason);
    });
  }

  /// @nodoc

  String? get quality => _preferredQuality;

  /// Registers an event listener for participant-related events.
  ///
  /// - This method allows you to listen to events associated with a
  /// [Participant], such as stream updates or state changes. When the
  /// specified event occurs, the provided handler will be invoked.
  ///
  /// ### **Parameters**
  ///
  /// - [event]:
  ///   The [Events] type to listen for.
  ///
  /// - [handler]:
  ///   A callback function that is executed whenever the specified
  ///   event is emitted. The callback may receive event-specific
  ///   data as arguments.
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// participant.on(Events.streamEnabled, (Stream stream) {
  ///   // Handle enabled stream
  /// });
  /// ```
  void on(Events event, Function handler) => _on(event, handler);

  _on(Events event, handler) {
    _participantEventEmitter.on(event.parseToString(), handler);
  }

  /// Removes a previously registered listener for a participant-related event.
  ///
  /// - This method stops listening for the specified [Participant] event
  /// and removes the associated handler. After removal, the handler
  /// will no longer be invoked when the event is emitted.
  ///
  /// ### **Parameters**
  ///
  /// - [event]:
  ///   The [Events] type for which the listener should be removed.
  ///
  /// - [handler]:
  ///   The same callback function that was previously registered
  ///   using [on].
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// void onStreamEnabled(Stream stream) {
  ///   // Handle enabled stream
  /// }
  ///
  /// // Register listener
  /// participant.on(Events.streamEnabled, onStreamEnabled);
  ///
  /// // Remove listener
  /// participant.off(Events.streamEnabled, onStreamEnabled);
  /// ```
  void off(Events event, Function handler) => _off(event, handler);
  _off(Events event, Function handler) {
    _participantEventEmitter.remove(event.parseToString(), handler);
  }

  _setLayers(int? spatialLayer, int? temporalLayer, String prevQuality,
      String currentQuality) {
    if (spatialLayer != null && temporalLayer != null) {
      _spatialLayer = spatialLayer;
      _temporalLayer = temporalLayer;
    }
    _participantEventEmitter.emit("video-quality-changed", <String, dynamic>{
      "prevQuality": prevQuality,
      "currentQuality": currentQuality,
    });
  }

  _pauseConsumer(String idKeyType, data) {
    final consumer = data['consumer'];

    Stream? stream = streams[data[idKeyType]];

    if (stream != null) {
      Stream newStream = stream.copyWith(track: consumer);

      streams[newStream.id] = newStream;

      _participantEventEmitter.emit(
        "stream-paused",
        newStream,
      );
    }
  }

  _resumeConsumer(String idKeyType, data) {
    final consumer = data['consumer'];

    Stream? stream = streams[data[idKeyType]];

    if (stream != null) {
      Stream newStream = stream.copyWith(track: consumer);

      streams[newStream.id] = newStream;

      _participantEventEmitter.emit(
        "stream-resumed",
        newStream,
      );
    }
  }

  _addConsumer(Stream stream) {
    streams[stream.id] = stream;

    if (stream.kind == 'video' &&
        !isLocal &&
        _spatialLayer != null &&
        _temporalLayer != null) {
      _setConsumerQuality(stream.id, "s${_spatialLayer}t$_temporalLayer");
    }

    _participantEventEmitter.emit(
      "stream-enabled",
      stream,
    );
    _eventEmitter.emit("stream-enabled-character-$id", stream);
  }

  _removeConsumer(String consumerId) {
    final Stream? streamToRemove = streams[consumerId];

    if (streamToRemove != null) {
      streams.remove(consumerId);

      _participantEventEmitter.emit(
        "stream-disabled",
        streamToRemove,
      );
      _eventEmitter.emit("stream-disabled-character-$id", streamToRemove);
    }
  }

  /// @nodoc

  handleStreamStateChanged(state, streamId) {
    final Stream? stream = streams[streamId];
    if (stream == null) return;

    if (stream.kind == 'video' || stream.kind == 'share') {
      stream.handleStateChanged(state);
    }
  }

  /// Enables the participant’s microphone.
  ///
  /// - Calling this method sends a microphone enable request to the participant.
  /// The participant will first receive a [Events.micRequested] event.
  /// Once the request is accepted, the microphone is enabled.
  ///
  /// - After the microphone is enabled, all participants in the room will receive
  /// a [Events.streamEnabled] event with the corresponding audio [Stream]
  /// object.
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Request the participant to enable their microphone
  /// participant.unmuteMic();
  /// ```
  unmuteMic() => _unmuteMic();
  _unmuteMic() => _enablePeerMic(id);

  /// Disables the participant’s microphone.
  ///
  /// Calling this method stops the participant’s microphone stream.
  /// Once the microphone is disabled, all participants in the room will receive
  /// a [Events.streamDisabled] event with the corresponding audio [Stream]
  /// object.
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Disable the participant's microphone
  /// participant.muteMic();
  /// ```
  muteMic() => _muteMic();
  _muteMic() => _disablePeerMic(id);

  /// Enables the participant’s camera.
  ///
  /// - Calling this method requests the participant to enable their camera.
  /// The participant will first receive a [Events.cameraRequested] event.
  /// Once the request is accepted, the camera device is enabled.
  ///
  /// - After the camera is enabled, all participants in the room will receive
  /// a [Events.streamEnabled] event with the corresponding video [Stream]
  /// object.
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Request the participant to enable their camera
  /// participant.enableCam();
  /// ```
  ///
  void enableCam() => _enableCam();
  _enableCam() => _enablePeerCamera(id);

  /// Disables the participant’s camera.
  ///
  /// - Calling this method stops the participant’s camera stream.
  /// Once the camera is disabled, all participants in the room will receive
  /// a [Events.streamDisabled] event with the corresponding video [Stream]
  /// object.
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Disable the participant's camera
  /// participant.disableCam();
  /// ```
  void disableCam() => _disableCam();
  _disableCam() => _disablePeerCamera(id);

  /// Pins the participant’s media streams.
  ///
  /// - This method allows you to pin the participant’s camera stream,
  /// screen-share stream, or both. Pinning a participant ensures that
  /// their selected media remains in focus (for example, in the UI layout).
  ///
  /// ### **Parameters**
  ///
  /// - [pinType] *(optional)*:
  ///   Specifies which media stream to pin.
  ///   Defaults to [PinType.SHARE_AND_CAM].
  ///
  ///   Possible values:
  ///   - [PinType.SHARE_AND_CAM]: Pins both camera and screen-share streams
  ///   - [PinType.CAM]: Pins only the camera stream
  ///   - [PinType.SHARE]: Pins only the screen-share stream
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Pin only the participant's camera
  /// participant.pin(PinType.CAM);
  ///
  /// // Pin both camera and screen share (default)
  /// participant.pin();
  /// ```
  pin([PinType pinType = PinType.SHARE_AND_CAM]) => _pin(pinType);
  _pin(PinType pinType) => _setPin(pinType);

  /// Unpins the participant’s media streams.
  ///
  /// - This method allows you to unpin the participant’s camera stream,
  /// screen-share stream, or both. Unpinning removes the participant’s
  /// media from the pinned state in the UI layout.
  ///
  /// ### **Parameters**
  ///
  /// - [pinType] *(optional)*:
  ///   Specifies which media stream to unpin.
  ///   Defaults to [PinType.SHARE_AND_CAM].
  ///
  ///   Possible values:
  ///   - [PinType.SHARE_AND_CAM]: Unpins both camera and screen-share streams
  ///   - [PinType.CAM]: Unpins only the camera stream
  ///   - [PinType.SHARE]: Unpins only the screen-share stream
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Unpin only the participant's camera
  /// participant.unpin(PinType.CAM);
  ///
  /// // Unpin both camera and screen share (default)
  /// participant.unpin();
  /// ```
  unpin([PinType pinType = PinType.SHARE_AND_CAM]) => _unpin(pinType);
  _unpin(PinType pinType) => _setUnPin(pinType);

  /// Starts consuming (subscribing to) this participant’s microphone (audio) streams.
  ///
  /// - This method is used when the room is created with `autoConsume: false`.
  /// Calling this explicitly allows you to start receiving the participant’s
  /// microphone audio stream on demand.
  ///
  /// - If the participant has an active microphone stream, it will be added to
  /// [Participant.streams] once consumption starts.
  ///
  /// This is useful for:
  /// - Selectively subscribing to audio streams
  /// - Reducing bandwidth usage
  /// - Implementing custom pin / focus logic
  void consumeMicStreams() => _consumeMicStreams?.call(id);

  /// Stops consuming (unsubscribing from) this participant’s microphone (audio) streams.
  ///
  /// After calling this method, the participant’s microphone audio stream
  /// will no longer be received, and the corresponding audio stream will be
  /// removed or stopped.
  ///
  /// This method has effect only when `autoConsume: false` is used.
  void stopConsumingMicStreams() => _stopConsumingMicStreams?.call(id);

  /// Starts consuming (subscribing to) this participant’s webcam (video) streams.
  ///
  /// - This method is used when the room is created with `autoConsume: false`.
  /// Calling this explicitly allows you to start receiving the participant’s
  /// webcam video stream on demand.
  ///
  /// - Once consumed, the video stream will be available in [Participant.streams]
  /// with `kind == 'video'`.
  ///
  /// This is useful for:
  /// - Lazy loading participant video
  /// - Pin-based or spotlight-based rendering
  /// - Optimizing bandwidth in large meetings
  void consumeWebcamStreams() => _consumeWebcamStreams?.call(id);

  /// Stops consuming (unsubscribing from) this participant’s webcam (video) streams.
  ///
  /// - After calling this method, the participant’s webcam video stream
  /// will no longer be received, and rendering can be safely stopped.
  ///
  /// - This method has effect only when `autoConsume: false` is used.
  void stopConsumingWebcamStreams() => _stopConsumingWebcamStreams?.call(id);

  _setPinState(data) {
    bool? cam = data['cam'];
    bool? share = data['share'];

    if (cam != null) {
      pinState.cam = cam;
    }
    if (share != null) {
      pinState.share = share;
    }
  }

  _setPin(PinType pinType) {
    switch (pinType) {
      case PinType.SHARE_AND_CAM:
        _setPinState({'share': true, 'cam': true});
        break;
      case PinType.CAM:
        _setPinState({'cam': true});

        break;
      case PinType.SHARE:
        _setPinState({'share': true});

        break;
    }
    _participantPinStateChanged(id, pinState);
  }

  _setUnPin(PinType pinType) {
    switch (pinType) {
      case PinType.SHARE_AND_CAM:
        _setPinState({'share': false, 'cam': false});
        break;
      case PinType.CAM:
        _setPinState({'cam': false});

        break;
      case PinType.SHARE:
        _setPinState({'share': false});

        break;
    }
    _participantPinStateChanged(id, pinState);
  }

  /// Retrieves real-time video statistics for the participant.
  ///
  /// - This method returns metrics related to the participant’s video stream,
  /// such as jitter, packet loss, bitrate, and round-trip time (RTT).
  /// The statistics represent the state of the video stream at the
  /// moment this method is called and do not reflect averaged data
  /// for the entire meeting.
  ///
  /// ### Returns
  ///
  /// - A `List<dynamic>?` containing video stream statistics objects,
  ///   or `null` if stats are unavailable. Each object may include:
  ///
  ///   - `jitter`:
  ///     Represents distortion in the video stream.
  ///
  ///   - `bitrate`:
  ///     The bitrate at which the video stream is being transmitted.
  ///
  ///   - `totalPackets`:
  ///     The total number of packets transmitted for the video stream.
  ///
  ///   - `packetsLost`:
  ///     The total number of packets lost during transmission.
  ///
  ///   - `rtt`:
  ///     The round-trip time (RTT) in milliseconds, representing the time
  ///     taken for the stream to travel from the server to the client.
  ///
  ///   - `codec`:
  ///     The codec used for encoding the video stream.
  ///
  ///   - `network`:
  ///     The network type used to transmit the stream.
  ///
  ///   - `size`:
  ///     An object containing the stream’s `width`, `height`, and
  ///     `frameRate`.
  ///
  /// ### Notes
  ///
  /// - The returned metrics represent **instantaneous values** at the time
  ///   of invocation and are not averaged over the entire meeting duration.
  ///
  /// - If the reported `rtt` is consistently greater than **300 ms**, it is
  ///   recommended to use a server region closer to the participant for
  ///   improved performance.
  ///
  /// ### **Example**
  /// ```dart
  /// // Fetch audio and video stats for a participant
  /// final audioStats = widget.participant.getAudioStats();
  /// final videoStats = widget.participant.getVideoStats();
  ///
  /// if (videoStats != null && videoStats.isNotEmpty) {
  ///   final stats = videoStats.first;
  ///   print('Video Bitrate: ${stats['bitrate']}');
  ///   print('Packet Loss: ${stats['packetsLost']}');
  ///   print('RTT: ${stats['rtt']} ms');
  /// }
  /// ```
  List<dynamic>? getVideoStats() => _getVideoStats();
  List<dynamic>? _getVideoStats() {
    if (isLocal) {
      for (var entry in streams.entries) {
        if (entry.value.kind == "video") {
          return _getStats(entry.key, "producer");
        }
      }
    } else {
      for (var entry in streams.entries) {
        if (entry.value.kind == "video") {
          return _getStats(entry.key, "consumer");
        }
      }
    }
    return null;
  }

  /// Retrieves real-time audio statistics for the participant.
  ///
  /// - This method returns metrics related to the participant’s audio stream,
  /// such as jitter, packet loss, bitrate, and round-trip time (RTT).
  /// The statistics represent the state of the audio stream at the
  /// moment this method is called and do not reflect averaged data
  /// for the entire meeting.
  ///
  /// ### Returns
  ///
  /// - A `List<dynamic>?` containing audio stream statistics objects,
  ///   or `null` if stats are unavailable. Each object may include:
  ///
  ///   - `jitter`:
  ///     Represents distortion in the audio stream.
  ///
  ///   - `bitrate`:
  ///     The bitrate at which the audio stream is being transmitted.
  ///
  ///   - `totalPackets`:
  ///     The total number of packets transmitted for the audio stream.
  ///
  ///   - `packetsLost`:
  ///     The total number of packets lost during transmission.
  ///
  ///   - `rtt`:
  ///     The round-trip time (RTT) in milliseconds, representing the time
  ///     taken for the stream to travel from the server to the client.
  ///
  ///   - `codec`:
  ///     The codec used for encoding the audio stream.
  ///
  ///   - `network`:
  ///     The network type used to transmit the stream.
  ///
  /// ### Notes
  ///
  /// - The returned metrics represent **instantaneous values** at the time
  ///   of invocation and are not averaged over the entire meeting duration.
  ///
  /// - If the reported `rtt` is consistently greater than **300 ms**, it is
  ///   recommended to use a server region closer to the participant for
  ///   improved performance.
  ///
  /// ### **Example**
  /// ```dart
  /// // Fetch audio and video stats for a participant
  /// final audioStats = widget.participant.getAudioStats();
  /// final videoStats = widget.participant.getVideoStats();
  ///
  /// if (audioStats != null && audioStats.isNotEmpty) {
  ///   final stats = audioStats.first;
  ///   print('Audio Bitrate: ${stats['bitrate']}');
  ///   print('Packet Loss: ${stats['packetsLost']}');
  ///   print('RTT: ${stats['rtt']} ms');
  /// }
  /// ```
  List<dynamic>? getAudioStats() => _getAudioStats();

  List<dynamic>? _getAudioStats() {
    if (isLocal) {
      for (var entry in streams.entries) {
        if (entry.value.kind == "audio") {
          return _getStats(entry.key, "producer");
        }
      }
    } else {
      for (var entry in streams.entries) {
        if (entry.value.kind == "audio") {
          return _getStats(entry.key, "consumer");
        }
      }
    }
    return null;
  }

  /// Retrieves real-time screen-share statistics for the participant.
  ///
  /// - This method returns metrics related to the participant’s screen-share
  /// video stream, such as jitter, packet loss, bitrate, and round-trip time (RTT).
  /// The statistics represent the state of the screen-share stream at the
  /// moment this method is called and do not reflect averaged data
  /// for the entire meeting.
  ///
  /// ### Returns
  ///
  /// - A `List<dynamic>?` containing screen-share stream statistics objects,
  ///   or `null` if stats are unavailable. Each object may include:
  ///
  ///   - `jitter`:
  ///     Represents distortion in the screen-share stream.
  ///
  ///   - `bitrate`:
  ///     The bitrate at which the screen-share stream is being transmitted.
  ///
  ///   - `totalPackets`:
  ///     The total number of packets transmitted for the screen-share stream.
  ///
  ///   - `packetsLost`:
  ///     The total number of packets lost during transmission.
  ///
  ///   - `rtt`:
  ///     The round-trip time (RTT) in milliseconds, representing the time
  ///     taken for the stream to travel from the server to the client.
  ///
  ///   - `codec`:
  ///     The codec used for encoding the screen-share stream.
  ///
  ///   - `network`:
  ///     The network type used to transmit the stream.
  ///
  ///   - `size`:
  ///     An object containing the stream’s `width`, `height`, and
  ///     `frameRate`.
  ///
  /// ### Notes
  ///
  /// - The returned metrics represent **instantaneous values** at the time
  ///   of invocation and are not averaged over the entire meeting duration.
  ///
  /// - If the reported `rtt` is consistently greater than **300 ms**, it is
  ///   recommended to use a server region closer to the participant for
  ///   improved performance.
  ///
  /// ### **Example**
  /// ```dart
  /// // Fetch screen-share stats for a participant
  /// final shareStats = widget.participant.getShareStats();
  ///
  /// if (shareStats != null && shareStats.isNotEmpty) {
  ///   final stats = shareStats.first;
  ///   print('Share Bitrate: ${stats['bitrate']}');
  ///   print('Packet Loss: ${stats['packetsLost']}');
  ///   print('RTT: ${stats['rtt']} ms');
  /// }
  /// ```
  List<dynamic>? getShareStats() => _getShareStats();
  List<dynamic>? _getShareStats() {
    if (isLocal) {
      for (var entry in streams.entries) {
        if (entry.value.kind == "share") {
          return _getStats(entry.key, "producer");
        }
      }
    } else {
      for (var entry in streams.entries) {
        if (entry.value.kind == "share") {
          return _getStats(entry.key, "consumer");
        }
      }
    }
    return null;
  }

  /// Sets the video quality for the participant’s video stream.
  ///
  /// - This method allows you to control the quality of the participant’s
  /// outgoing video stream, which can help optimize bandwidth usage
  /// and performance.
  ///
  /// ### **Parameters**
  ///
  /// - [quality]:
  ///   The desired video quality level.
  ///   Possible values:
  ///   - `"low"`
  ///   - `"med"`
  ///   - `"high"`
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Set participant video quality to high
  /// participant.setQuality('high');
  /// ```
  setQuality(quality) => _setQuality(quality);
  _setQuality(quality) {
    _preferredQuality = quality;
    streams.forEach((key, stream) {
      if (stream.kind == 'video' && !isLocal) {
        _setConsumerQuality(stream.id, quality);
      }
    });
  }

  /// Sets the video quality of the participant’s video stream
  /// based on the specified viewport dimensions.
  ///
  /// - This method adjusts the video stream quality dynamically
  /// according to the provided viewport width and height,
  /// helping optimize rendering quality and bandwidth usage.
  ///
  /// ### **Parameters**
  ///
  /// - [width]:
  ///   The width of the viewport in pixels.
  ///
  /// - [height]:
  ///   The height of the viewport in pixels.
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Set viewport size for participant video
  /// participant.setViewPort(480, 360);
  /// ```
  void setViewPort(width, height) => _setViewPort(width, height);

  void _setViewPort(width, height) {
    streams.forEach((key, stream) {
      if (stream.kind == 'video' && !isLocal) {
        _setViewPortInternal(stream.id, width, height, id);
      }
    });
  }

  /// Removes the participant from the room.
  ///
  /// - Calling this method forcefully removes the participant
  /// from the current room session.
  ///
  /// ### Returns
  ///
  /// - `void`
  ///
  /// ### **Example**
  /// ```dart
  /// // Remove participant from the room
  /// participant.remove();
  /// ```
  remove() => _remove();

  _remove() => _removePeer(id);

  /// Captures an image from the local participant’s current video stream.
  ///
  /// - This method captures a single frame from the active video stream
  /// of the local participant and returns the image encoded as a
  /// Base64 string.
  ///
  /// ### **Parameters**
  ///
  /// - [width] *(optional)*:
  ///   The desired width of the captured image in pixels.
  ///
  /// - [height] *(optional)*:
  ///   The desired height of the captured image in pixels.
  ///
  /// ### Returns
  ///
  /// - A [String] containing the captured image encoded in Base64 format,
  ///   or `null` if the image could not be captured.
  ///
  /// ### **Example**
  /// ```dart
  /// final base64Image = await room.captureImage(
  ///   width: 640,
  ///   height: 480,
  /// );
  ///
  /// if (base64Image != null) {
  ///   print('Captured image (base64 length): ${base64Image.length}');
  /// }
  /// ```
  Future<String?> captureImage({
    int? width,
    int? height,
  }) =>
      _captureImage(width: width, height: height);
  Future<String?> _captureImage({
    int? width,
    int? height,
  }) async {
    if (!isLocal) {
      throw Exception(
        "You can only capture a image of LocalParticipant.",
      );
    }

    SpanScope? captureSpan = SdkTracer.shared.startSpan(
      spanName: "Capturing image",
      category: EventCategory.telemetry,
      component: ComponentCategory.media,
      attributes: {
        "peerId": id,
        "height": height.toString(),
        "width": width.toString(),
      },
    );

    try {
      final double ratio;

      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        ratio = 4 / 3;
      } else {
        ratio = 16 / 9;
      }

      SpanScope? streamsSpan = SdkTracer.shared.startSpan(
        spanName: "Fetching available streams",
        parentSpan: captureSpan,
        component: ComponentCategory.media,
      );

      Stream? stream;
      try {
        stream = streams.values.firstWhere(
          (stream) => stream.kind == 'video',
          orElse: () => throw Exception(
            "Camera must be on to capture an image",
          ),
        );
      } catch (e) {
        SdkTracer.shared.endSpan(
          streamsSpan,
          message: "Capture image failed",
          success: false,
          category: EventCategory.error,
        );
        SdkTracer.shared.endSpan(
          captureSpan,
          message: "Error in captureImage() -> ${e.toString()}",
          category: EventCategory.error,
        );
        rethrow;
      }

      SdkTracer.shared.endSpan(
        streamsSpan,
        message: "Fetched available streams",
      );

      SpanScope? videoStreamSpan = SdkTracer.shared.startSpan(
        spanName: "Processing video stream for capture",
        parentSpan: captureSpan,
        component: ComponentCategory.media,
      );

      try {
        SpanScope? initElementsSpan = SdkTracer.shared.startSpan(
          spanName: "Initializing capture elements",
          parentSpan: videoStreamSpan,
          component: ComponentCategory.media,
        );

        MediaStream mediaStream = stream.track.stream;
        MediaStreamTrack? track = mediaStream.getVideoTracks().firstOrNull;

        if (track == null) {
          throw Exception("Camera must be on to capture an image");
        }

        SdkTracer.shared.endSpan(
          initElementsSpan,
          message: "Initialized video and canvas elements",
        );

        SpanScope? captureFrameSpan = SdkTracer.shared.startSpan(
          spanName: "Waiting for video frame to load",
          parentSpan: videoStreamSpan,
          component: ComponentCategory.media,
        );

        ByteBuffer buffer;
        try {
          buffer = await track.captureFrame();
          SdkTracer.shared.endSpan(
            captureFrameSpan,
            message: "Video frame loaded",
          );
        } catch (e) {
          SdkTracer.shared.endSpan(
            captureFrameSpan,
            success: false,
            message: "Error capturing frame: ${e.toString()}",
            category: EventCategory.error,
          );
          SdkTracer.shared.endSpan(
            videoStreamSpan,
            message: "Error in captureImage() -> ${e.toString()}",
            category: EventCategory.error,
          );
          SdkTracer.shared.endSpan(
            captureSpan,
            message: "Error in captureImage() -> ${e.toString()}",
            category: EventCategory.error,
          );
          rethrow;
        }

        SpanScope? processImageSpan = SdkTracer.shared.startSpan(
          spanName: "Drawing video frame to canvas",
          parentSpan: captureSpan,
          component: ComponentCategory.media,
        );

        try {
          Uint8List originalBytes = buffer.asUint8List();

          if (height == null && width == null) {
            String base64 = base64Encode(originalBytes);
            SdkTracer.shared.endSpan(
              processImageSpan,
              message: "Captured frame and generated base64 image",
            );
            SdkTracer.shared.endSpan(
              videoStreamSpan,
              message: "Video stream processed successfully",
            );
            SdkTracer.shared.endSpan(
              captureSpan,
              message: "Image captured successfully",
            );
            return base64;
          }

          img.Image? image = img.decodeImage(originalBytes);

          if (image == null) {
            throw Exception("Camera must be on to capture an image");
          }

          int originalWidth = image.width;
          int originalHeight = image.height;

          width = (width != null && (width <= 0 || width > originalWidth))
              ? originalWidth
              : width;
          height = (height != null && (height <= 0 || height > originalHeight))
              ? originalHeight
              : height;

          if (width != null && height == null) {
            height = (width / ratio).round();
          } else if (height != null && width == null) {
            width = (height * ratio).round();
          }

          img.Image resizedImage = img.copyResize(
            image,
            width: width,
            height: height,
            interpolation: img.Interpolation.cubic,
          );

          Uint8List resizedBytes = Uint8List.fromList(
            img.encodeJpg(resizedImage, quality: 90),
          );

          String base64Result = base64Encode(resizedBytes);
          SdkTracer.shared.endSpan(
            processImageSpan,
            message: "Captured frame and generated base64 image",
          );

          SdkTracer.shared.endSpan(
            videoStreamSpan,
            message: "Video stream processed successfully",
          );

          SdkTracer.shared.endSpan(
            captureSpan,
            message: "Image captured successfully",
          );

          return base64Result;
        } catch (error) {
          SdkTracer.shared.endSpan(
            processImageSpan,
            success: false,
            message: "Error processing image: ${error.toString()}",
            category: EventCategory.error,
          );
          SdkTracer.shared.endSpan(
            videoStreamSpan,
            message: "Error in captureImage() -> ${error.toString()}",
            category: EventCategory.error,
          );
          SdkTracer.shared.endSpan(
            captureSpan,
            message: "Error in captureImage() -> ${error.toString()}",
            category: EventCategory.error,
          );
          rethrow;
        }
      } catch (err) {
        SdkTracer.shared.endSpan(
          videoStreamSpan,
          success: false,
          message: "Error processing video stream: ${err.toString()}",
          category: EventCategory.error,
        );
        SdkTracer.shared.endSpan(
          captureSpan,
          message: "Error in captureImage() -> ${err.toString()}",
          category: EventCategory.error,
        );

        rethrow;
      }
    } catch (error) {
      SdkTracer.shared.endSpan(
        captureSpan,
        success: false,
        message: "Failed to capture image: ${error.toString()}",
        category: EventCategory.error,
      );
      // It is important to rethrow so the behavior remains consistent
      rethrow;
    }
  }
}
