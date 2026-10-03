// ignore_for_file: cast_from_null_always_fails, unnecessary_null_comparison

import 'dart:developer';

import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:videosdk_webrtc/flutter_webrtc.dart';
import 'package:sdp_transform/sdp_transform.dart';

import '../ortc.dart';
import '../rtp_parameters.dart';
import '../scalability_modes.dart';
import '../sctp_parameters.dart';
import '../sdp_object.dart';
import '../transport.dart';
import 'handler_interface.dart';
import 'sdp/common_utils.dart';
import 'sdp/media_section.dart';
import 'sdp/remote_sdp.dart';
import 'sdp/unified_plan_utils.dart';
import 'transceiver_mid.dart';

// Top-level helpers required by compute() — must be top-level, not closures.
Map<String, dynamic> _parseSdp(String sdp) =>
    Map<String, dynamic>.from(parse(sdp));
String _writeSdp(Map<String, dynamic> map) => write(map, null);

// Logger _logger = Logger('Unified plan handler');

class UnifiedPlan extends HandlerInterface {
  // Handler direction.
  late Direction _direction;
  // Remote SDP handler.
  late RemoteSdp _remoteSdp;
  // Generic sending RTP parameters for audio and video.
  late Map<RTCRtpMediaType, RtpParameters> _sendingRtpParametersByKind;
  // Generic sending RTP parameters for audio and video suitable for the SDP
  // remote answer.
  late Map<RTCRtpMediaType, RtpParameters> _sendingRemoteRtpParametersByKind;
  // Initial server side DTLS role. If not 'auto', it will force the opposite
  // value in client side.
  DtlsRole? _forcedLocalDtlsRole;
  // RTCPeerConnection instance.
  RTCPeerConnection? _pc;
  // Map of RTCTransceivers indexed by MID.
  final Map<String, RTCRtpTransceiver> _mapMidTransceiver = {};
  // Whether a DataChannel m=application section has been created.
  bool _hasDataChannelMediaSection = false;
  // Sending DataChannel id value counter. Incremented for each new DataChannel.
  int _nextSendSctpStreamId = 0;
  // Got transport local and remote parameters.
  bool _transportReady = false;

  UnifiedPlan() : super();

  Future<void> _setupTransport({
    required DtlsRole localDtlsRole,
    SdpObject? localSdpObject,
  }) async {
    if (localSdpObject == null) {
      final setupLocalSdp = (await _pc!.getLocalDescription())!.sdp!;
      final setupSdpMap = await compute(_parseSdp, setupLocalSdp);
      localSdpObject = SdpObject.fromMap(setupSdpMap);
    }

    // Get our local DTLS parameters.
    DtlsParameters dtlsParameters =
        CommonUtils.extractDtlsParameters(localSdpObject);

    // Set our DTLS role.
    dtlsParameters.role = localDtlsRole;

    // Update the remote DTLC role in the SDP.
    _remoteSdp.updateDtlsRole(
      localDtlsRole == DtlsRole.client ? DtlsRole.server : DtlsRole.client,
    );

    // Need to tell the remote transport about our parameters.
    await safeEmitAsFuture('@connect', {
      'dtlsParameters': dtlsParameters,
    });

    _transportReady = true;
  }

  void _assertSendRirection() {
    if (_direction != Direction.send) {
      throw ('method can just be called for handlers with "send" direction');
    }
  }

  void _assertRecvDirection() {
    if (_direction != Direction.recv) {
      throw ('method can just be called for handlers with "recv" direction');
    }
  }

  @override
  Future<void> close() async {
    // _logger.debug('close()');

    // Close RTCPeerConnection.
    if (_pc != null) {
      try {
        await _pc!.close();
      } catch (error) {
        log('close() | pc.close() failed: $error');
      }
    }
  }

  @override
  Future<RtpCapabilities> getNativeRtpCapabilities() async {
    // _logger.debug('getNativeRtpCapabilities()');

    RTCPeerConnection pc = await createPeerConnection({
      'iceServers': [],
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'sdpSemantics': 'unified-plan',
    }, {
      'optional': [
        {'DtlsSrtpKeyAgreement': true},
      ],
    });

    try {
      await pc.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeAudio);
      await pc.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeVideo);

      RTCSessionDescription offer = await pc.createOffer({});
      final capOfferSdp = offer.sdp!;
      final parsedOffer = await compute(_parseSdp, capOfferSdp);
      SdpObject sdpObject = SdpObject.fromMap(parsedOffer);

      RtpCapabilities nativeRtpCapabilities =
          CommonUtils.extractRtpCapabilities(sdpObject);

      return nativeRtpCapabilities;
    } catch (error) {
      try {
        await pc.close();
      } catch (error2) {
        log('getNativeRtpCapabilities() | pc.close() failed: $error2');
      }

      rethrow;
    }
  }

  @override
  SctpCapabilities getNativeSctpCapabilities() {
    // _logger.debug('getNativeSctpCapabilities()');

    return SctpCapabilities(
        numStreams: NumSctpStreams(
      mis: SCTP_NUM_STREAMS.MIS,
      os: SCTP_NUM_STREAMS.OS,
    ));
  }

  @override
  Future<List<StatsReport>> getReceiverStats(String localId) async {
    _assertRecvDirection();

    RTCRtpTransceiver? transceiver = _mapMidTransceiver[localId];

    if (transceiver == null) {
      throw ('associated RTCRtpTransceiver not found');
    }

    return await transceiver.receiver.getStats();
  }

  @override
  Future<List<StatsReport>> getSenderStats(String localId) async {
    _assertSendRirection();

    RTCRtpTransceiver? transceiver = _mapMidTransceiver[localId];

    if (transceiver == null) {
      throw ('associated RTCRtpTransceiver not found');
    }

    return await transceiver.sender.getStats();
  }

  @override
  Future<List<StatsReport>> getTransportStats() async {
    return await _pc!.getStats();
  }

  @override
  String get name => 'Unified plan handler';
  @override
  Future<HandlerReceiveResult> receive(HandlerReceiveOptions options) async {
    _assertRecvDirection();

    String localId =
        options.rtpParameters.mid ?? _mapMidTransceiver.length.toString();

    try {
      _remoteSdp.receive(
        mid: localId,
        kind: options.kind,
        offerRtpParameters: options.rtpParameters,
        streamId: options.rtpParameters.rtcp!.cname ?? "",
        trackId: options.trackId,
      );

      RTCSessionDescription offer = RTCSessionDescription(
        _remoteSdp.getSdp(),
        'offer',
      );

      await _pc!.setRemoteDescription(offer);

      RTCSessionDescription answer = await _pc!.createAnswer({});

      final answerSdp = answer.sdp!;
      final answerSdpMap = await compute(_parseSdp, answerSdp);
      SdpObject localSdpObject = SdpObject.fromMap(answerSdpMap);

      MediaObject answerMediaObject = localSdpObject.media.firstWhere(
        (MediaObject m) => m.mid == localId,
        orElse: () => null as MediaObject,
      );

      // May need to modify codec parameters in the answer based on codec
      // parameters in the offer.

      CommonUtils.applyCodecParameters(
          options.rtpParameters, answerMediaObject);

      final answerSdpWriteMap = localSdpObject.toMap();
      answer = RTCSessionDescription(
        await compute(_writeSdp, answerSdpWriteMap),
        'answer',
      );

      if (!_transportReady) {
        await _setupTransport(
          localDtlsRole: DtlsRole.client,
          localSdpObject: localSdpObject,
        );
      } else {
        log('receive() - transport already ready');
      }

      await _pc!.setLocalDescription(answer);

      final transceivers = await _pc!.getTransceivers();

      // Not `t.mid == localId` over the whole list: on the web reading the mid
      // of a transceiver the browser keeps without one throws, and Safari
      // threw here after the first remote mic went off - every later receive
      // failed and no new remote sound arrived (SowGood, 2026-10-03; see
      // transceiver_mid.dart).
      RTCRtpTransceiver? transceiver =
          transceiverWithMid(transceivers, localId);

      if (transceiver == null) {
        throw ('new RTCRtpTransceiver not found');
      }

      // Store in the map.
      _mapMidTransceiver[localId] = transceiver;

      // getRemoteStreams() is a deprecated, Chrome-only API: Safari has no such
      // method, the call threw NoSuchMethodError inside the consume task, the
      // task queue swallowed it, and a Safari viewer never got a remote stream
      // (SowGood, 2026-09-18: an iPhone in Safari heard nothing from a room
      // VideoSDK's own JS player played fine). The stream is built from the
      // receiver's track below when the lookup yields nothing.
      List<MediaStream?> remoteStreams;
      try {
        remoteStreams = _pc!.getRemoteStreams();
      } catch (_) {
        remoteStreams = <MediaStream?>[];
      }

      // Try multiple methods to find or create the stream
      MediaStream? stream;

      //  Try to find by CNAME (original method)

      stream = remoteStreams
          .firstWhereOrNull((e) => e?.id == options.rtpParameters.rtcp!.cname);

      // If not found, try to find stream containing the track
      if (stream == null && transceiver.receiver.track != null) {
        String trackId = transceiver.receiver.track!.id!;

        stream = remoteStreams.firstWhereOrNull((s) {
          if (s == null) return false;
          final tracks = s.getTracks();
          bool hasTrack = tracks.any((t) => t.id == trackId);
          return hasTrack;
        });
      }

      // Method 3: Use the first non-probator stream
      if (stream == null && remoteStreams.isNotEmpty) {
        stream = remoteStreams
            .firstWhereOrNull((s) => s != null && s.id != 'probator');
      }

      // Method 4 (every browser): a stream carrying the receiver's track.
      if (stream == null && transceiver.receiver.track != null) {
        stream = await createLocalMediaStream(
          options.rtpParameters.rtcp?.cname ?? options.trackId ?? localId,
        );
        await stream.addTrack(transceiver.receiver.track!);
      }

      if (stream == null) {
        throw ('Stream not found');
      }

      return HandlerReceiveResult(
        localId: localId,
        track: transceiver.receiver.track!,
        rtpReceiver: transceiver.receiver,
        stream: stream,
      );
    } catch (e) {
      rethrow;
    }
  }

  // @override
  // Future<HandlerReceiveResult> receive(HandlerReceiveOptions options) async {
  //   _assertRecvDirection();

  //   // _logger.debug(
  //   //     'receive() [trackId:${options.trackId}, kind:${RTCRtpMediaTypeExtension.value(options.kind)}]');

  //   String localId =
  //       options.rtpParameters.mid ?? _mapMidTransceiver.length.toString();

  //   _remoteSdp.receive(
  //     mid: localId,
  //     kind: options.kind,
  //     offerRtpParameters: options.rtpParameters,
  //     streamId: options.rtpParameters.rtcp!.cname ?? "",
  //     trackId: options.trackId,
  //   );

  //   RTCSessionDescription offer = RTCSessionDescription(
  //     _remoteSdp.getSdp(),
  //     'offer',
  //   );

  //   // _logger.debug(
  //   //     'receive() | calling pc.setRemoteDescription() [offer:${offer.toMap()}]');

  //   await _pc!.setRemoteDescription(offer);

  //   RTCSessionDescription answer = await _pc!.createAnswer({});

  //   SdpObject localSdpObject = SdpObject.fromMap(parse(answer.sdp!));

  //   MediaObject answerMediaObject = localSdpObject.media.firstWhere(
  //     (MediaObject m) => m.mid == localId,
  //     orElse: () => null as MediaObject,
  //   );

  //   // May need to modify codec parameters in the answer based on codec
  //   // parameters in the offer.
  //   CommonUtils.applyCodecParameters(options.rtpParameters, answerMediaObject);

  //   answer = RTCSessionDescription(
  //     write(localSdpObject.toMap(), null),
  //     'answer',
  //   );

  //   if (!_transportReady) {
  //     await _setupTransport(
  //       localDtlsRole: DtlsRole.client,
  //       localSdpObject: localSdpObject,
  //     );
  //   }

  //   // _logger.debug(
  //   //     'receive() | calling pc.setLocalDescription() [answer:${answer.toMap()}]');

  //   await _pc!.setLocalDescription(answer);

  //   final transceivers = await _pc!.getTransceivers();

  //   RTCRtpTransceiver? transceiver = transceivers.firstWhereOrNull(
  //     (RTCRtpTransceiver t) => t.mid == localId,
  //     // orElse: () => null,
  //   );

  //   if (transceiver == null) {
  //     throw ('new RTCRtpTransceiver not found');
  //   }

  //   // Store in the map.
  //   _mapMidTransceiver[localId] = transceiver;

  //   final MediaStream? stream = _pc!
  //       .getRemoteStreams()
  //       .firstWhereOrNull((e) => e?.id == options.rtpParameters.rtcp!.cname);

  //   if (stream == null) {
  //     throw ('Stream not found');
  //   }

  //   return HandlerReceiveResult(
  //     localId: localId,
  //     track: transceiver.receiver.track!,
  //     rtpReceiver: transceiver.receiver,
  //     stream: stream,
  //   );
  // }

  @override
  Future<HandlerReceiveDataChannelResult> receiveDataChannel(
      HandlerReceiveDataChannelOptions options) async {
    _assertRecvDirection();

    RTCDataChannelInit initOptions = RTCDataChannelInit();
    initOptions.negotiated = true;
    initOptions.id = options.sctpStreamParameters.streamId;
    initOptions.ordered =
        options.sctpStreamParameters.ordered ?? initOptions.ordered;
    initOptions.maxRetransmitTime =
        options.sctpStreamParameters.maxPacketLifeTime ??
            initOptions.maxRetransmitTime;
    initOptions.maxRetransmits = options.sctpStreamParameters.maxRetransmits ??
        initOptions.maxRetransmits;
    initOptions.protocol = options.protocol;

    // _logger.debug('receiveDataChannel() [options:${initOptions.toMap()}]');

    RTCDataChannel dataChannel =
        await _pc!.createDataChannel(options.label, initOptions);

    // If this is the first DataChannel we need to create the SDP offer with
    // m=application section.
    if (!_hasDataChannelMediaSection) {
      _remoteSdp.receiveSctpAssociation();

      RTCSessionDescription offer =
          RTCSessionDescription(_remoteSdp.getSdp(), 'offer');

      // _logger.debug(
      //     'receiveDataChannel() | calling pc.setRemoteDescription() [offer:${offer.toMap()}]');

      await _pc!.setRemoteDescription(offer);

      RTCSessionDescription answer = await _pc!.createAnswer({});

      if (!_transportReady) {
        final dcAnswerSdp = answer.sdp!;
        final dcAnswerSdpMap = await compute(_parseSdp, dcAnswerSdp);
        SdpObject localSdpObject = SdpObject.fromMap(dcAnswerSdpMap);

        await _setupTransport(
          localDtlsRole: _forcedLocalDtlsRole ?? DtlsRole.client,
          localSdpObject: localSdpObject,
        );
      }

      // _logger.debug(
      //     'receiveDataChannel() | calling pc.setRemoteDescription() [answer: ${answer.toMap()}');

      await _pc!.setLocalDescription(answer);

      _hasDataChannelMediaSection = true;
    }

    return HandlerReceiveDataChannelResult(dataChannel: dataChannel);
  }

  @override
  Future<void> replaceTrack(ReplaceTrackOptions options) async {
    _assertSendRirection();

    // _logger.debug(
    //     'replaceTrack() [localId:${options.localId}, track.id: ${options.track.id}]');

    RTCRtpTransceiver? transceiver = _mapMidTransceiver[options.localId];

    if (transceiver == null) {
      throw ('associated RTCRtpTransceiver not found');
    }

    await transceiver.sender.replaceTrack(options.track);
    _mapMidTransceiver.remove(options.localId);
  }

  @override
  Future<void> restartIce(IceParameters iceParameters) async {
    // _logger.debug('restartIce()');

    // Provide the remote SDP handler with new remote Ice parameters.
    _remoteSdp.updateIceParameters(iceParameters);

    if (!_transportReady) {
      return;
    }

    if (_direction == Direction.send) {
      RTCSessionDescription offer =
          await _pc!.createOffer({'iceRestart': true});

      // _logger.debug(
      //     'restartIce() | calling pc.setLocalDescription() [offer:${offer.toMap()}]');

      await _pc!.setLocalDescription(offer);

      RTCSessionDescription answer =
          RTCSessionDescription(_remoteSdp.getSdp(), 'answer');

      // _logger.debug(
      //     'restartIce() | calling pc.setRemoteDescription() [answer:${answer.toMap()}]');

      await _pc!.setRemoteDescription(answer);
    } else {
      RTCSessionDescription offer =
          RTCSessionDescription(_remoteSdp.getSdp(), 'offer');

      // _logger.debug(
      //     'restartIce() | calling pc.setRemoteDescription() [offer:${offer.toMap()}]');

      await _pc!.setRemoteDescription(offer);

      RTCSessionDescription answer = await _pc!.createAnswer({});

      // _logger.debug(
      //     'restartIce() | calling pc.setLocalDescription() [answer:${answer.toMap()}]');

      await _pc!.setLocalDescription(answer);
    }
  }

  @override
  void run({required HandlerRunOptions options}) async {
    // _logger.debug('run()');

    _direction = options.direction;

    _remoteSdp = RemoteSdp(
      iceParameters: options.iceParameters,
      iceCandidates: options.iceCandidates,
      dtlsParameters: options.dtlsParameters,
      sctpParameters: options.sctpParameters,
    );

    _sendingRtpParametersByKind = {
      RTCRtpMediaType.RTCRtpMediaTypeAudio: Ortc.getSendingRtpParameters(
        RTCRtpMediaType.RTCRtpMediaTypeAudio,
        options.extendedRtpCapabilities,
      ),
      RTCRtpMediaType.RTCRtpMediaTypeVideo: Ortc.getSendingRtpParameters(
        RTCRtpMediaType.RTCRtpMediaTypeVideo,
        options.extendedRtpCapabilities,
      ),
    };

    _sendingRemoteRtpParametersByKind = {
      RTCRtpMediaType.RTCRtpMediaTypeAudio: Ortc.getSendingRemoteRtpParameters(
        RTCRtpMediaType.RTCRtpMediaTypeAudio,
        options.extendedRtpCapabilities,
      ),
      RTCRtpMediaType.RTCRtpMediaTypeVideo: Ortc.getSendingRemoteRtpParameters(
        RTCRtpMediaType.RTCRtpMediaTypeVideo,
        options.extendedRtpCapabilities,
      ),
    };

    if (options.dtlsParameters.role != DtlsRole.auto) {
      _forcedLocalDtlsRole = options.dtlsParameters.role == DtlsRole.server
          ? DtlsRole.client
          : DtlsRole.server;
    }

    // ignore: no_leading_underscores_for_local_identifiers
    final _constrains = options.proprietaryConstraints.isEmpty
        ? <String, dynamic>{
            'mandatory': {},
            'optional': [
              {'DtlsSrtpKeyAgreement': true},
            ],
          }
        : options.proprietaryConstraints;

    _constrains['optional'] = [
      ..._constrains['optional'],
      {'DtlsSrtpKeyAgreement': true}
    ];

    _pc = await createPeerConnection(
      {
        'iceServers':
            options.iceServers.map((RTCIceServer i) => i.toMap()).toList(),
        'iceTransportPolicy': options.iceTransportPolicy?.value ?? 'all',
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
        'sdpSemantics': 'unified-plan',
        ...options.additionalSettings,
      },
      _constrains,
    );

    // Handle RTCPeerConnection connection status.
    _pc!.onIceConnectionState = (RTCIceConnectionState state) {
      switch (_pc!.iceConnectionState) {
        case RTCIceConnectionState.RTCIceConnectionStateChecking:
          {
            emit('@connectionstatechange', {'state': 'connecting'});
            break;
          }
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          {
            emit('@connectionstatechange', {'state': 'connected'});
            break;
          }
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          {
            emit('@connectionstatechange', {'state': 'failed'});
            break;
          }
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          {
            emit('@connectionstatechange', {'state': 'disconnected'});
            break;
          }
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          {
            emit('@connectionstatechange', {'state': 'closed'});
            break;
          }

        default:
          break;
      }
    };
  }

  @override
  Future<HandlerSendResult> send(HandlerSendOptions options) async {
    _assertSendRirection();

    // _logger.debug(
    //     'send() [kind:${options.track.kind}, track.id:${options.track.id}');

    if (options.encodings.length > 1) {
      for (int idx = 0; idx < options.encodings.length; idx++) {
        options.encodings[idx].rid = 'r$idx';
      }
    }

    final String? codecMime = options.codec?.mimeType.toLowerCase();

    final bool isVp8 = codecMime == 'video/vp8';

    if (isVp8) {
      var nextRid = 1;
      for (var encoding in options.encodings) {
        encoding.rid = "r$nextRid";
        nextRid++;
        encoding.scalabilityMode = 'L1T3';
      }
    }

    RtpParameters sendingRtpParameters = RtpParameters.copy(
        _sendingRtpParametersByKind[
            RTCRtpMediaTypeExtension.fromString(options.track.kind!)]!);

    // This may throw.
    sendingRtpParameters.codecs =
        Ortc.reduceCodecs(sendingRtpParameters.codecs, options.codec);

    RtpParameters sendingRemoteRtpParameters = RtpParameters.copy(
        _sendingRemoteRtpParametersByKind[
            RTCRtpMediaTypeExtension.fromString(options.track.kind!)]!);

    // This may throw.
    sendingRemoteRtpParameters.codecs =
        Ortc.reduceCodecs(sendingRemoteRtpParameters.codecs, options.codec);

    MediaSectionIdx mediaSectionIdx = _remoteSdp.getNextMediaSectionIdx();

    RTCRtpTransceiver transceiver = await _pc!.addTransceiver(
      track: options.track,
      kind: RTCRtpMediaTypeExtension.fromString(options.track.kind!),
      init: RTCRtpTransceiverInit(
        direction: TransceiverDirection.SendOnly,
        streams: [options.stream],
        sendEncodings: options.encodings,
      ),
    );

    RTCSessionDescription offer = await _pc!.createOffer({});
    final offerSdp = offer.sdp!;
    final offerSdpMap = await compute(_parseSdp, offerSdp);
    SdpObject localSdpObject = SdpObject.fromMap(offerSdpMap);
    MediaObject offerMediaObject;

    if (!_transportReady) {
      // change dtls role from server to client as when server was there only Device(Source) was sending the transport-cc packets to server in case of client there is bi-directional flow of packets.
      await _setupTransport(
        localDtlsRole: DtlsRole.client,
        localSdpObject: localSdpObject,
      );
    }

    // Speacial case for VP9 with SVC.
    bool hackVp9Svc = false;

    ScalabilityMode layers = ScalabilityMode.parse((options.encodings.isNotEmpty
                ? options.encodings
                : [RtpEncodingParameters(scalabilityMode: '')])
            .first
            .scalabilityMode ??
        '');

    if (options.encodings.length == 1 &&
        layers.spatialLayers > 1 &&
        sendingRtpParameters.codecs.first.mimeType.toLowerCase() ==
            'video/vp9') {
      // _logger.debug('send() | enabling legacy simulcast for VP9 SVC');

      hackVp9Svc = true;
      final vp9OfferSdp = offer.sdp!;
      final vp9OfferSdpMap = await compute(_parseSdp, vp9OfferSdp);
      localSdpObject = SdpObject.fromMap(vp9OfferSdpMap);
      offerMediaObject = localSdpObject.media[mediaSectionIdx.idx];
      // RTCRtpParameters _parameters;
      // List<RTCRtpSender> Senders;
      // Senders = await _pc!.getSenders();
      // Senders.forEach((element) {
      //   _parameters = element.parameters;
      //   _parameters.degradationPreference =
      //       degradationPreferenceforString('maintain-framerate');
      //   element.setParameters(_parameters);
      // });

      UnifiedPlanUtils.addLegacySimulcast(
        offerMediaObject,
        layers.spatialLayers,
      );

      final vp9WriteMap = localSdpObject.toMap();
      offer =
          RTCSessionDescription(await compute(_writeSdp, vp9WriteMap), 'offer');
    }

    // _logger.debug(
    //     'send() | calling pc.setLocalDescription() [offer:${offer.toMap()}');

    await _pc!.setLocalDescription(offer);

    if (!kIsWeb) {
      final transceivers = await _pc!.getTransceivers();
      transceiver = transceivers.firstWhere(
        // ignore: no_leading_underscores_for_local_identifiers
        (_transceiver) =>
            _transceiver.sender.track?.id == options.track.id &&
            _transceiver.sender.track?.kind == options.track.kind,
        orElse: () => throw 'No transceiver found',
      );
    }

    // We can now get the transceiver.mid.
    String localId = transceiver.mid;

    // Set MID.
    sendingRtpParameters.mid = localId;

    final localDescSdp = (await _pc!.getLocalDescription())!.sdp!;
    final localDescSdpMap = await compute(_parseSdp, localDescSdp);
    localSdpObject = SdpObject.fromMap(localDescSdpMap);
    offerMediaObject = localSdpObject.media[mediaSectionIdx.idx];

    // Set RTCP CNAME.
    sendingRtpParameters.rtcp!.cname = CommonUtils.getCname(offerMediaObject);

    // Set RTP encdoings by parsing the SDP offer if no encoding are given.
    if (options.encodings.isEmpty) {
      sendingRtpParameters.encodings =
          UnifiedPlanUtils.getRtpEncodings(offerMediaObject);
    }
    // Set RTP encodings by parsing the SDP offer and complete them with given
    // one if just a single encoding has been given.
    else if (options.encodings.length == 1) {
      List<RtpEncodingParameters> newEncodings =
          UnifiedPlanUtils.getRtpEncodings(offerMediaObject);

      newEncodings[0] =
          RtpEncodingParameters.assign(newEncodings[0], options.encodings[0]);

      // Hack for VP9 SVC.
      if (hackVp9Svc) {
        newEncodings = [newEncodings[0]];
      }

      sendingRtpParameters.encodings = newEncodings;
    }
    // Otherwise if more than 1 encoding are given use them verbatim.
    else {
      sendingRtpParameters.encodings = options.encodings;
    }

    // If VP8 or H264 and there is effective simulcast, add scalabilityMode to
    // each encoding.
    if (sendingRtpParameters.encodings.length > 1 &&
        (sendingRtpParameters.codecs[0].mimeType.toLowerCase() == 'video/vp8' ||
            sendingRtpParameters.codecs[0].mimeType.toLowerCase() ==
                'video/h264')) {
      for (RtpEncodingParameters encoding in sendingRtpParameters.encodings) {
        encoding.scalabilityMode = 'S1T3';
      }
    }

    _remoteSdp.send(
      offerMediaObject: offerMediaObject,
      reuseMid: mediaSectionIdx.reuseMid,
      offerRtpParameters: sendingRtpParameters,
      answerRtpParameters: sendingRemoteRtpParameters,
      codecOptions: options.codecOptions,
      extmapAllowMixed: true,
    );

    RTCSessionDescription answer =
        RTCSessionDescription(_remoteSdp.getSdp(), 'answer');

    // _logger.debug(
    //     'send() | calling pc.setRemoteDescription() [answer:${answer.toMap()}]');

    await _pc!.setRemoteDescription(answer);

    // Store in the map.
    _mapMidTransceiver[localId] = transceiver;

    return HandlerSendResult(
      localId: localId,
      rtpParameters: sendingRtpParameters,
      rtpSender: transceiver.sender,
    );
  }

  @override
  Future<HandlerSendDataChannelResult> sendDataChannel(
      SendDataChannelArguments options) async {
    _assertSendRirection();

    RTCDataChannelInit initOptions = RTCDataChannelInit();
    initOptions.negotiated = true;
    initOptions.id = _nextSendSctpStreamId;
    initOptions.ordered = options.ordered ?? initOptions.ordered;
    initOptions.maxRetransmitTime =
        options.maxPacketLifeTime ?? initOptions.maxRetransmitTime;
    initOptions.maxRetransmits =
        options.maxRetransmits ?? initOptions.maxRetransmits;
    initOptions.protocol = options.protocol ?? initOptions.protocol;
    // initOptions.priority = options.priority;

    // _logger.debug('sendDataChannel() [options:${initOptions.toMap()}]');

    RTCDataChannel dataChannel =
        await _pc!.createDataChannel(options.label!, initOptions);

    // Increase next id.
    _nextSendSctpStreamId = ++_nextSendSctpStreamId % SCTP_NUM_STREAMS.MIS;

    // If this is the first DataChannel we need to create the SDP answer with
    // m=application section.
    if (!_hasDataChannelMediaSection) {
      RTCSessionDescription offer = await _pc!.createOffer({});
      final dcOfferSdp = offer.sdp!;
      final dcOfferSdpMap = await compute(_parseSdp, dcOfferSdp);
      SdpObject localSdpObject = SdpObject.fromMap(dcOfferSdpMap);
      MediaObject? offerMediaObject = localSdpObject.media.firstWhereOrNull(
        (MediaObject m) => m.type == 'application',
      );

      if (!_transportReady) {
        await _setupTransport(
          localDtlsRole: _forcedLocalDtlsRole ?? DtlsRole.client,
          localSdpObject: localSdpObject,
        );
      }

      // _logger.debug(
      //     'sendDataChannel() | calling pc.setLocalDescription() [offer:${offer.toMap()}');

      await _pc!.setLocalDescription(offer);

      _remoteSdp.sendSctpAssociation(offerMediaObject!);

      RTCSessionDescription answer =
          RTCSessionDescription(_remoteSdp.getSdp(), 'answer');

      // _logger.debug(
      //     'sendDataChannel() | calling pc.setRemoteDescription() [answer:${answer.toMap()}]');

      await _pc!.setRemoteDescription(answer);

      _hasDataChannelMediaSection = true;
    }

    SctpStreamParameters sctpStreamParameters = SctpStreamParameters(
      streamId: initOptions.id,
      ordered: initOptions.ordered,
      maxPacketLifeTime: initOptions.maxRetransmitTime,
      maxRetransmits: initOptions.maxRetransmits,
    );

    return HandlerSendDataChannelResult(
      dataChannel: dataChannel,
      sctpStreamParameters: sctpStreamParameters,
    );
  }

  @override
  Future<void> setMaxSpatialLayer(SetMaxSpatialLayerOptions options) async {
    _assertSendRirection();

    // _logger.debug(
    //     'setMaxSpatialLayer() [localId:${options.localId}, spatialLayer:${options.spatialLayer}');

    RTCRtpTransceiver? transceiver = _mapMidTransceiver[options.localId];

    if (transceiver == null) {
      throw ('associated RTCRtpTransceiver not found');
    }

    RTCRtpParameters parameters = transceiver.sender.parameters;

    int idx = 0;
    for (var encoding in parameters.encodings!) {
      if (idx <= options.spatialLayer) {
        encoding.active = true;
      } else {
        encoding.active = false;
      }
      idx++;
    }

    await transceiver.sender.setParameters(parameters);
  }

  @override
  Future<void> setRtpEncodingParameters(
      SetRtpEncodingParametersOptions options) async {
    _assertSendRirection();

    // _logger.debug(
    //     'setRtpEncodingParameters() [localId:${options.localId}, params:${options.params}]');

    RTCRtpTransceiver? transceiver = _mapMidTransceiver[options.localId];

    if (transceiver == null) {
      throw ('associated RTCRtpTransceiver not found');
    }

    RTCRtpParameters parameters = transceiver.sender.parameters;

    int idx = 0;
    for (var encoding in parameters.encodings!) {
      parameters.encodings![idx] = RTCRtpEncoding(
        active: options.params.active,
        maxBitrate: options.params.maxBitrate ?? encoding.maxBitrate,
        maxFramerate: options.params.maxFramerate ?? encoding.maxFramerate,
        minBitrate: options.params.minBitrate ?? encoding.minBitrate,
        numTemporalLayers:
            options.params.numTemporalLayers ?? encoding.numTemporalLayers,
        rid: options.params.rid ?? encoding.rid,
        scaleResolutionDownBy: options.params.scaleResolutionDownBy ??
            encoding.scaleResolutionDownBy,
        ssrc: options.params.ssrc ?? encoding.ssrc,
      );
      idx++;
    }

    await transceiver.sender.setParameters(parameters);
  }

  @override
  Future<void> stopReceiving(String localId) async {
    _assertRecvDirection();

    // _logger.debug('stopReceiving() [localId:$localId');

    RTCRtpTransceiver? transceiver = _mapMidTransceiver[localId];

    if (transceiver == null) {
      throw ('associated RTCRtpTransceiveer not found');
    }

    // localId is the mid the transceiver was stored under; reading
    // transceiver.mid again can throw on the web (transceiver_mid.dart).
    _remoteSdp.closeMediaSection(localId);

    RTCSessionDescription offer =
        RTCSessionDescription(_remoteSdp.getSdp(), 'offer');

    // _logger.debug(
    //     'stopReceiving() | calling pc.setRemoteDescription() [offer:${offer.toMap()}');

    await _pc!.setRemoteDescription(offer);

    RTCSessionDescription answer = await _pc!.createAnswer({});

    // _logger.debug(
    //     'stopReceiving() | calling pc.setLocalDescription() [answer:${answer.toMap()}');

    await _pc!.setLocalDescription(answer);
    _mapMidTransceiver.remove(localId);
  }

  @override
  Future<void> stopSending(String localId) async {
    _assertSendRirection();

    // _logger.debug('stopSending() [localId:$localId]');

    RTCRtpTransceiver? transceiver = _mapMidTransceiver[localId];

    if (transceiver == null) {
      throw ('associated RTCRtpTransceiver not found');
    }

    // await transceiver.sender.replaceTrack(null);
    await _pc!.removeTrack(transceiver.sender);
    // localId is the mid the transceiver was stored under (see stopReceiving).
    _remoteSdp.closeMediaSection(localId);

    RTCSessionDescription offer = await _pc!.createOffer({});

    // _logger.debug(
    //     'stopSending() | calling pc.setLocalDescription() [offer:${offer.toMap()}');

    await _pc!.setLocalDescription(offer);

    RTCSessionDescription answer =
        RTCSessionDescription(_remoteSdp.getSdp(), 'answer');

    // _logger.debug(
    //     'stopSending() | calling pc.setRemoteDescription() [answer:${answer.toMap()}');

    await _pc!.setRemoteDescription(answer);
    _mapMidTransceiver.remove(localId);
  }

  @override
  Future<void> updateIceServers(List<RTCIceServer> iceServers) async {
    // _logger.debug('updateIceServers()');

    Map<String, dynamic> configuration = _pc!.getConfiguration;

    configuration['iceServers'] =
        iceServers.map((RTCIceServer ice) => ice.toMap()).toList();

    await _pc!.setConfiguration(configuration);
  }
}

extension FirstWhereOrNullExtension<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E) test) {
    for (E element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
