// Top-level helper functions for offloading stats processing to a background
// isolate. All functions operate exclusively on plain Dart data types so they
// are sendable across isolate boundaries (no native handles, no Flutter types).
import 'stats_runner.dart';

// ─── 1. RTT / Congestion — called from Timer.periodic in _createSendTransport
//
// Inputs  : serialised StatsReport list + current trace state (plain maps)
// Returns : null when no RTT samples were collected this tick; otherwise a map
//           containing the computed average RTT, bandwidth/CPU limit flags, and
//           the updated trace state that the caller must write back.
// ---------------------------------------------------------------------------
Map<String, dynamic>? computeRttStats(
  List<Map<String, dynamic>> reports,
  Map<String, Map<String, dynamic>> outbTraces,
  Map<String, Map<String, dynamic>> remoteInbTraces,
) {
  final rttMeasurements = <double>[];

  for (final report in reports) {
    final type = report['type'] as String? ?? '';
    final id = report['id'] as String? ?? '';
    final values = report['values'] as Map<String, dynamic>? ?? {};

    if (type == 'outbound-rtp') {
      outbTraces[id] = {
        'qualityLimitationReason': values['qualityLimitationReason'],
      };
    }

    if (type == 'remote-inbound-rtp') {
      final totalRtt = values['totalRoundTripTime'];
      final measurements = values['roundTripTimeMeasurements'];
      if (totalRtt == null || measurements == null) continue;

      final prev = remoteInbTraces[id] ??
          {'totalRoundTripTime': 0.0, 'roundTripTimeMeasurements': 0};

      final diffMeasurements =
          (measurements as num) - (prev['roundTripTimeMeasurements'] as num);
      final diffTotal = (totalRtt as num) - (prev['totalRoundTripTime'] as num);

      if (diffMeasurements > 0 && diffTotal > 0) {
        rttMeasurements.add((diffTotal / diffMeasurements) * 1000);
        remoteInbTraces[id] = {
          'totalRoundTripTime': totalRtt,
          'roundTripTimeMeasurements': measurements,
        };
      }
    }
  }

  if (rttMeasurements.isEmpty) return null;

  final avg = rttMeasurements.reduce((a, b) => a + b) / rttMeasurements.length;

  return {
    'avgRttMs': avg,
    'isBandwidthLimited': outbTraces.values
        .any((t) => t['qualityLimitationReason'] == 'bandwidth'),
    'isCpuLimited':
        outbTraces.values.any((t) => t['qualityLimitationReason'] == 'cpu'),
    'outbTraces': outbTraces,
    'remoteInbTraces': remoteInbTraces,
  };
}

// ─── 2. Producer stats — called from the send-transport probe event handler
//
// Filters the raw probe report by track ID so the caller can update
// _latestStats and _stats['producerStats'] without touching native handles
// inside a background isolate.
// ---------------------------------------------------------------------------
Map<String, dynamic> computeProducerStats({
  required Map<String, dynamic> report,
  required String? micTrackId,
  required String? micProducerId,
  required String? cameraTrackId,
  required String? cameraProducerId,
  required String? shareTrackId,
  required String? shareProducerId,
  required int reportCounter,
}) {
  final latestMicStats = <dynamic>[];
  final latestCameraStats = <dynamic>[];
  final latestShareStats = <dynamic>[];
  dynamic audioStatToAdd;
  final bool shouldRecord = reportCounter % 5 == 0;

  for (final stat in (report['audio'] as List<dynamic>? ?? [])) {
    if (stat['trackId'] == micTrackId) {
      latestMicStats.add(stat);
      if (shouldRecord) audioStatToAdd = stat;
    }
  }

  for (final stat in (report['video'] as List<dynamic>? ?? [])) {
    if (stat['trackId'] == cameraTrackId) {
      latestCameraStats.add(stat);
    } else if (stat['trackId'] == shareTrackId) {
      latestShareStats.add(stat);
    }
  }

  return {
    'latestMicStats': latestMicStats,
    'latestCameraStats': latestCameraStats,
    'latestShareStats': latestShareStats,
    'audioStatToAdd': audioStatToAdd,
    'shouldRecord': shouldRecord,
  };
}

// ─── 3. Consumer stats — called from the recv-transport probe event handler
//
// Processes audio/video consumer stats, detects video stutter and freeze, and
// returns events that must be dispatched back on the main isolate (because
// Participant.handleStreamStateChanged references Flutter objects).
//
// consumerSnapshot  — plain-data copy of _recvTransport.consumers keyed by
//                     consumer.id, built on the main isolate before the call.
// traces            — stutter detection state, keyed by nativeTrackId.
// freezeTraces      — freeze detection state, keyed by consumer id.
// ---------------------------------------------------------------------------
Map<String, dynamic> computeConsumerStats({
  required Map<String, dynamic> report,
  required Map<String, Map<String, dynamic>> consumerSnapshot,
  required Map<dynamic, dynamic> traces,
  required Map<String, dynamic> freezeTraces,
  required Map<String, dynamic> freezeTimestamps,
  required Map<String, dynamic> freezeResolvedEmitted,
  required int reportCounter,
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final bool shouldRecord = reportCounter % 5 == 0;

  // Mutable copies — will be returned so caller can write them back.
  final updatedTraces = Map<dynamic, dynamic>.from(traces);
  final updatedFreezeTraces = Map<String, dynamic>.from(freezeTraces);
  final updatedFreezeTimestamps = Map<String, dynamic>.from(freezeTimestamps);
  final updatedFreezeResolved =
      Map<String, dynamic>.from(freezeResolvedEmitted);

  // statsToAdd  : entries to append to _stats['consumerStats'][peerId][type]
  final statsToAdd = <Map<String, dynamic>>[];
  // latestStatsUpdates : consumerId → single-element list for _latestStats
  final latestStatsUpdates = <String, List<dynamic>>{};
  // events : freeze / stutter actions for the main isolate to dispatch
  final events = <Map<String, dynamic>>[];

  // ── Audio ─────────────────────────────────────────────────────────────────
  for (final stat in (report['audio'] as List<dynamic>? ?? [])) {
    final trackId = stat['trackId'] as String?;
    if (trackId == null) continue;
    final consumer = consumerSnapshot[trackId];
    if (consumer == null) continue;

    final consumerId = consumer['id'] as String;
    final consumerType = _resolveConsumerType(consumer);

    latestStatsUpdates[consumerId] = [stat];
    if (shouldRecord) {
      statsToAdd.add({
        'peerId': consumer['peerId'],
        'type': consumerType,
        'stat': stat,
      });
    }
  }

  // ── Video ─────────────────────────────────────────────────────────────────
  for (final stat in (report['video'] as List<dynamic>? ?? [])) {
    final trackId = stat['trackId'] as String?;
    if (trackId == null) continue;
    final consumer = consumerSnapshot[trackId];
    if (consumer == null) continue;

    final consumerId = consumer['id'] as String;
    final consumerType = _resolveConsumerType(consumer);
    final nativeTrackId = consumer['nativeTrackId'] as String?;
    if (nativeTrackId == null) continue;
    final peerId = consumer['peerId'] as String;

    latestStatsUpdates[consumerId] = [stat];
    if (shouldRecord) {
      statsToAdd.add({
        'peerId': peerId,
        'type': consumerType,
        'stat': stat,
      });
    }

    // Stutter detection (bitrate == 0 for > 5 seconds)
    final bitrate = stat['bitrate'];
    if (bitrate != null && (bitrate as num) > 0) {
      updatedTraces.remove(nativeTrackId);
    } else {
      final trace = updatedTraces[nativeTrackId] as Map?;
      if (trace == null) {
        updatedTraces[nativeTrackId] = {'detected': now};
      } else if ((trace['detected'] as int) + 5000 < now) {
        events.add(
            {'action': 'stuck', 'peerId': peerId, 'streamId': nativeTrackId});
      }
    }

    // Freeze detection
    final freezeCount = stat['freezeCount'];
    final lastFreezeCount = updatedFreezeTraces[trackId];

    if (lastFreezeCount == null) {
      updatedFreezeTraces[trackId] = freezeCount;
      continue;
    }

    if (freezeCount != null &&
        (freezeCount as num) > (lastFreezeCount as num)) {
      events.add({
        'action': 'freeze-detected',
        'peerId': peerId,
        'streamId': nativeTrackId,
      });
      updatedFreezeTimestamps[trackId] = now;
      updatedFreezeResolved.remove(trackId);
    } else {
      final lastFreezeAt = updatedFreezeTimestamps[trackId] as int?;
      if (lastFreezeAt != null &&
          !updatedFreezeResolved.containsKey(trackId) &&
          now - lastFreezeAt > 5000) {
        events.add({
          'action': 'freeze-resolved',
          'peerId': peerId,
          'streamId': nativeTrackId,
        });
        updatedFreezeResolved[trackId] = true;
      }
    }
    updatedFreezeTraces[trackId] = freezeCount;
  }

  return {
    'statsToAdd': statsToAdd,
    'latestStatsUpdates': latestStatsUpdates,
    'events': events,
    'traces': updatedTraces,
    'freezeTraces': updatedFreezeTraces,
    'freezeTimestamps': updatedFreezeTimestamps,
    'freezeResolvedEmitted': updatedFreezeResolved,
  };
}

// ── Private helper ────────────────────────────────────────────────────────────
String _resolveConsumerType(Map<String, dynamic> consumer) {
  final isShare = consumer['appData']?['share'] == true;
  final kind = consumer['kind'] as String? ?? '';
  if (isShare) return kind == 'audio' ? 'shareAudio' : 'share';
  return kind;
}

// ─── Isolate-safe runners ─────────────────────────────────────────────────────
// These are TOP-LEVEL functions (no enclosing class, no `this`).
// The closures they create can therefore only capture the explicit plain-data
// parameters — they cannot accidentally capture a Room/Timer/native handle
// through an async-frame, which would make the message unsendable.

Future<Map<String, dynamic>?> runRttStats(
  List<Map<String, dynamic>> reports,
  Map<String, Map<String, dynamic>> outbTraces,
  Map<String, Map<String, dynamic>> remoteInbTraces,
) =>
    runComputation(() => computeRttStats(reports, outbTraces, remoteInbTraces));

Future<Map<String, dynamic>> runProducerStats({
  required Map<String, dynamic> report,
  required String? micTrackId,
  required String? micProducerId,
  required String? cameraTrackId,
  required String? cameraProducerId,
  required String? shareTrackId,
  required String? shareProducerId,
  required int reportCounter,
}) =>
    runComputation(
      () => computeProducerStats(
        report: report,
        micTrackId: micTrackId,
        micProducerId: micProducerId,
        cameraTrackId: cameraTrackId,
        cameraProducerId: cameraProducerId,
        shareTrackId: shareTrackId,
        shareProducerId: shareProducerId,
        reportCounter: reportCounter,
      ),
    );

Future<Map<String, dynamic>> runConsumerStats({
  required Map<String, dynamic> report,
  required Map<String, Map<String, dynamic>> consumerSnapshot,
  required Map<dynamic, dynamic> traces,
  required Map<String, dynamic> freezeTraces,
  required Map<String, dynamic> freezeTimestamps,
  required Map<String, dynamic> freezeResolvedEmitted,
  required int reportCounter,
}) =>
    runComputation(
      () => computeConsumerStats(
        report: report,
        consumerSnapshot: consumerSnapshot,
        traces: traces,
        freezeTraces: freezeTraces,
        freezeTimestamps: freezeTimestamps,
        freezeResolvedEmitted: freezeResolvedEmitted,
        reportCounter: reportCounter,
      ),
    );
