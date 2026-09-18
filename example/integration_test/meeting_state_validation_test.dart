import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:videosdk/videosdk.dart';

/// ERROR_ACTION_PERFORMED_BEFORE_MEETING_JOINED
const String kNotJoined = '3022';

/// ERROR_JOINING_MEETING
const String kJoinFailed = '3023';

/// Nothing should take longer than this. A guard that fails to reject turns
/// into a hang (a screen-share prompt, a socket wait), so every call is bounded
/// and a timeout is reported as a failure rather than blocking the run.
const Duration kCallTimeout = Duration(seconds: 10);

/// Collects everything the room reports on [Events.error].
class ErrorLog {
  final List<Map<dynamic, dynamic>> seen = <Map<dynamic, dynamic>>[];

  void bind(Room room) {
    room.on(Events.error, (dynamic error) {
      if (error is Map) seen.add(Map<dynamic, dynamic>.from(error));
    });
  }

  void clear() => seen.clear();

  List<String> get codes =>
      seen.map((Map<dynamic, dynamic> e) => '${e['code']}').toList();
}

Room buildRoom({
  String roomId = 'aaaa-bbbb-cccc',
  String token = 'not-a-real-token',
  String signalingBaseUrl = '',
}) {
  return VideoSDK.createRoom(
    roomId: roomId,
    token: token,
    displayName: 'IntegrationTest',
    // Off so the suite never depends on camera/mic permission being granted.
    micEnabled: false,
    camEnabled: false,
    signalingBaseUrl: signalingBaseUrl,
  );
}

/// Runs [call] and asserts it was rejected with exactly one [kNotJoined] error.
///
/// The "exactly one" half is the point: internal implementations used to emit
/// their own copy of 3022, so a single rejected call could report twice.
Future<void> expectRejected(
  ErrorLog log,
  String label,
  Future<void> Function() call,
) async {
  log.clear();

  bool timedOut = false;
  await call().timeout(kCallTimeout, onTimeout: () => timedOut = true);

  expect(timedOut, isFalse,
      reason: '$label did not return within ${kCallTimeout.inSeconds}s — the '
          'guard let it through and it blocked on real work');
  expect(log.seen.length, 1,
      reason: '$label should emit exactly one error, got ${log.codes}');
  expect('${log.seen.first['code']}', kNotJoined,
      reason: '$label reported the wrong code');
  expect('${log.seen.first['name']}',
      'ERROR_ACTION_PERFORMED_BEFORE_MEETING_JOINED',
      reason: '$label reported the wrong name');
  expect('${log.seen.first['message']}'.trim(), isNotEmpty,
      reason: '$label carried an empty message');
}

/// Runs [call] and asserts it returned without reporting anything.
///
/// For the SDK's own internal entry points — the ones the platform
/// EventChannel drives, not the app. A rejection there would blame the app for
/// a call it never made, so these must bail silently rather than emit 3022.
Future<void> expectSilent(
  ErrorLog log,
  String label,
  Future<void> Function() call,
) async {
  log.clear();

  bool timedOut = false;
  await call().timeout(kCallTimeout, onTimeout: () => timedOut = true);

  expect(timedOut, isFalse,
      reason: '$label did not return within ${kCallTimeout.inSeconds}s — it '
          'was let through and blocked on real work');
  expect(log.seen, isEmpty,
      reason: '$label is an internal path and must stay silent, '
          'got ${log.codes}');
}

Future<String?> readToken() async {
  if (!dotenv.isInitialized) {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      return null;
    }
  }
  final String? authUrl = dotenv.env['AUTH_URL'];
  final String? authToken = dotenv.env['AUTH_TOKEN'];

  if (authToken != null && authToken.isNotEmpty) return authToken;

  if (authUrl != null && authUrl.isNotEmpty) {
    try {
      final http.Response res = await http.get(Uri.parse('$authUrl/get-token'));
      return json.decode(res.body)['token'] as String?;
    } catch (_) {
      return null;
    }
  }
  return null;
}

Future<String?> createMeetingId(String token) async {
  final String endpoint =
      dotenv.env['VIDEOSDK_API_ENDPOINT'] ?? 'https://api.videosdk.live/v2';
  try {
    final http.Response res = await http.post(
      Uri.parse('$endpoint/meetings'),
      headers: <String, String>{'Authorization': token},
    );
    return json.decode(res.body)['meetingId'] as String?;
  } catch (_) {
    return null;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('A · every meeting action is rejected before join', () {
    late Room room;
    late ErrorLog log;

    setUp(() {
      room = buildRoom();
      log = ErrorLog()..bind(room);
    });

    test('local media', () async {
      await expectRejected(log, 'muteMic', () => room.muteMic());
      await expectRejected(log, 'unmuteMic', () => room.unmuteMic());
      await expectRejected(log, 'enableCam', () => room.enableCam());
      await expectRejected(log, 'disableCam', () => room.disableCam());
    });

    test('screen share — rejected before any capture prompt', () async {
      await expectRejected(
          log, 'enableScreenShare', () => room.enableScreenShare());
      await expectRejected(
          log, 'disableScreenShare', () => room.disableScreenShare());
    });

    test('screen share — the platform entry points stay silent', () async {
      // enableShare()/disableShare() are what the iOS ReplayKit and Android
      // broadcast EventChannel calls when the user starts or stops sharing
      // from the system UI. They must do nothing, quietly — no error, and no
      // capture prompt.
      await expectSilent(log, 'enableShare', () => room.enableShare(null));
      await expectSilent(log, 'disableShare', () => room.disableShare());
    });

    test('session controls', () async {
      await expectRejected(log, 'end', () async => room.end());
      await expectRejected(log, 'leave', () => room.leave());
      await expectRejected(
          log, 'changeMode', () => room.changeMode(Mode.RECV_ONLY));
      await expectRejected(log, 'switchTo', () => room.switchTo('x-y-z'));
    });

    test('recording, livestream and HLS', () async {
      await expectRejected(log, 'startRecording', () => room.startRecording());
      await expectRejected(log, 'stopRecording', () => room.stopRecording());
      await expectRejected(
          log, 'startLivestream', () => room.startLivestream(<dynamic>[]));
      await expectRejected(log, 'stopLivestream', () => room.stopLivestream());
      await expectRejected(log, 'startHls', () => room.startHls());
      await expectRejected(log, 'stopHls', () => room.stopHls());
    });

    test('transcription and translation', () async {
      await expectRejected(
          log, 'startTranscription', () => room.startTranscription());
      await expectRejected(
          log, 'stopTranscription', () => room.stopTranscription());
      await expectRejected(
          log, 'startTranslation', () => room.startTranslation());
      await expectRejected(log, 'changeTranslationLanguage',
          () => room.changeTranslationLanguage('en'));
      await expectRejected(
          log, 'stopTranslation', () async => room.stopTranslation());
    });

    test('whiteboard and bulk stream control', () async {
      await expectRejected(
          log, 'startWhiteboard', () => room.startWhiteboard());
      await expectRejected(log, 'stopWhiteboard', () => room.stopWhiteboard());
      await expectRejected(
          log, 'pauseAllStreams', () => room.pauseAllStreams());
      await expectRejected(
          log, 'resumeAllStreams', () => room.resumeAllStreams());
    });

    test('media relay', () async {
      await expectRejected(
          log, 'requestMediaRelay', () => room.requestMediaRelay('x-y-z'));
      await expectRejected(log, 'enableRelayMedia',
          () => room.enableRelayMedia('x-y-z', <String>['audio']));
      await expectRejected(log, 'disableRelayMedia',
          () => room.disableRelayMedia('x-y-z', <String>['audio']));
    });

    test('file helpers return null instead of hitting an unset baseUrl',
        () async {
      log.clear();
      final String? uploaded = await room
          .uploadBase64File(base64Data: 'AAAA', token: 't', fileName: 'f.txt')
          .timeout(kCallTimeout, onTimeout: () => 'TIMEOUT');
      expect(uploaded, isNull, reason: 'uploadBase64File should return null');
      expect(log.codes, <String>[kNotJoined]);

      log.clear();
      final String? fetched = await room
          .fetchBase64File(url: 'https://example.com/f', token: 't')
          .timeout(kCallTimeout, onTimeout: () => 'TIMEOUT');
      expect(fetched, isNull, reason: 'fetchBase64File should return null');
      expect(log.codes, <String>[kNotJoined]);
    });

    test('device switching, when the device list is available', () async {
      final List<VideoDeviceInfo>? cams = await VideoSDK.getVideoDevices();
      if (cams != null && cams.isNotEmpty) {
        await expectRejected(
            log, 'changeCam', () => room.changeCam(cams.first));
      }

      final List<AudioDeviceInfo>? mics = await VideoSDK.getAudioDevices();
      if (mics != null && mics.isNotEmpty) {
        await expectRejected(
            log, 'changeMic', () => room.changeMic(mics.first));
      }
    });
  });

  group('B · owned objects and edge cases', () {
    late Room room;
    late ErrorLog log;

    setUp(() {
      room = buildRoom();
      log = ErrorLog()..bind(room);
    });

    // Regression: pin()/unpin() dereferenced the websocket and threw before
    // the guard existed.
    test('participant.pin / unpin report instead of crashing', () async {
      await expectRejected(
          log, 'participant.pin', () async => room.localParticipant.pin());
      await expectRejected(
          log, 'participant.unpin', () async => room.localParticipant.unpin());
    });

    test('pubSub publish is rejected', () async {
      await expectRejected(
          log, 'pubSub.publish', () => room.pubSub.publish('CHAT', 'hello'));
    });

    // Regression: subscribe used to register the handler even when the call
    // was rejected, so the topic started delivering once the room connected.
    test('pubSub subscribe is rejected and registers no listener', () async {
      log.clear();
      bool delivered = false;
      final PubSubMessages messages = await room.pubSub
          .subscribe('CHAT', (PubSubMessage _) => delivered = true)
          .timeout(kCallTimeout);

      expect(log.codes, <String>[kNotJoined]);
      expect(messages.messages, isEmpty,
          reason: 'a rejected subscribe should hand back no history');
      expect(delivered, isFalse);
    });

    test('pubSub unsubscribe is rejected', () async {
      await expectRejected(log, 'pubSub.unsubscribe',
          () => room.pubSub.unsubscribe('CHAT', (PubSubMessage _) {}));
    });

    // Regression: these reached the socket with no null check, so calling them
    // before join threw "Null check operator used on a null value" straight
    // into the app instead of reporting the error.
    test('realtimeStore is rejected without throwing', () async {
      await expectRejected(log, 'realtimeStore.setValue',
          () => room.realtimeStore.setValue('KEY', 'value'));

      log.clear();
      final String? value =
          await room.realtimeStore.getValue('KEY').timeout(kCallTimeout);
      expect(log.codes, <String>[kNotJoined]);
      expect(value, isNull,
          reason: 'a rejected getValue should hand back nothing');

      log.clear();
      final String observerId = await room.realtimeStore
          .observe('KEY', (String? _, Participant? __) {})
          .timeout(kCallTimeout);
      expect(log.codes, <String>[kNotJoined]);
      expect(observerId, isEmpty,
          reason: 'a rejected observe should hand back no observer id');
    });

    test('adaptive subscription is rejected', () async {
      await expectRejected(log, 'enableAdaptiveSubscription',
          () => room.enableAdaptiveSubscription());
      await expectRejected(log, 'disableAdaptiveSubscription',
          () => room.disableAdaptiveSubscription());
    });

    // Regression: the rejection path returned null, and Character.join() only
    // skips on exactly false — so it read fields off null and crashed.
    test('character.join is rejected without crashing', () async {
      log.clear();
      final Character character = room.createCharacter(
        characterConfig: CharacterConfig.newInteraction(
          characterId: 'test-character',
        ),
      );
      character.join();
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(log.codes, contains(kNotJoined));
    }, skip: 'enable once createCharacter is exercised on this account');

    test('a custom track handed to a rejected call is still released',
        () async {
      final CustomTrack? track = await VideoSDK.createMicrophoneAudioTrack();
      if (track == null) return; // no mic permission on this device

      log.clear();
      await room.unmuteMic(track).timeout(kCallTimeout);

      expect(log.codes, <String>[kNotJoined]);
      // The SDK owns a track once it is handed over; a rejected call must not
      // leak it. dispose() is what sets `ended`.
      expect(track.ended, isTrue,
          reason: 'the rejected call should have disposed the track');
    });

    test('repeated rejections stay one-error-per-call', () async {
      log.clear();
      await room.muteMic();
      await room.muteMic();
      await room.startRecording();
      expect(log.codes, <String>[kNotJoined, kNotJoined, kNotJoined],
          reason: 'three rejected calls must produce exactly three errors');
    });
  });

  group('C · a join that cannot be set up reports RoomState.failed', () {
    test('unreachable signalling host', () async {
      final Room room = buildRoom(signalingBaseUrl: 'unreachable.invalid');
      final ErrorLog log = ErrorLog()..bind(room);
      final List<RoomState> states = <RoomState>[];
      room.on(Events.roomStateChanged, (dynamic s) {
        if (s is RoomState) states.add(s);
      });

      try {
        await room.join().timeout(const Duration(seconds: 30));
      } catch (_) {
        // join() rethrows once the config fetch fails; the events are the
        // contract under test.
      }

      expect(states, contains(RoomState.failed),
          reason: 'a failed join must report RoomState.failed');
      expect(log.codes, contains(kJoinFailed),
          reason: 'a failed join must report ERROR_JOINING_MEETING');

      // And the room stays closed for business afterwards.
      await expectRejected(
          log, 'muteMic after failed join', () => room.muteMic());
    });
  });

  group('D · live meeting lifecycle', () {
    late String token;
    late String meetingId;
    bool credentialsReady = false;

    setUpAll(() async {
      final String? t = await readToken();
      if (t == null || t.isEmpty) return;
      final String? id = await createMeetingId(t);
      if (id == null || id.isEmpty) return;
      token = t;
      meetingId = id;
      credentialsReady = true;
    });

    test('join, act from the joined handler, leave, then reject again',
        () async {
      if (!credentialsReady) {
        markTestSkipped('no usable AUTH_TOKEN/AUTH_URL in .env');
        return;
      }

      final Room room = buildRoom(roomId: meetingId, token: token);
      final ErrorLog log = ErrorLog()..bind(room);

      // Regression: _joined was set after meeting-joined was emitted, and the
      // emitter is synchronous — so acting from this handler was rejected.
      final List<String> codesDuringHandler = <String>[];
      bool joined = false;
      room.on(Events.roomJoined, () {
        joined = true;
        log.clear();
        room.muteMic();
        codesDuringHandler.addAll(log.codes);
      });

      await room.join();
      await Future<void>.delayed(const Duration(seconds: 12));

      expect(joined, isTrue, reason: 'the room never reported roomJoined');
      expect(codesDuringHandler, isEmpty,
          reason: 'calling a method from the roomJoined handler must work');

      // Connected baseline — normal calls raise nothing.
      log.clear();
      await room.pubSub.publish('CHAT', 'integration-test');
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(log.codes, isEmpty,
          reason: 'a joined room should accept pubSub.publish');

      // Leave, then everything closes back up.
      bool left = false;
      room.on(Events.roomLeft, (dynamic _) => left = true);
      log.clear();
      await room.leave();
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(left, isTrue, reason: 'leave() did not complete');
      expect(log.codes, isEmpty, reason: 'leave() itself must not report');

      await expectRejected(log, 'muteMic after leave', () => room.muteMic());

      // end() after leave() reports rather than returning silently: _closed is
      // part of the teardown gate, so 3022 really does cover "after leave()".
      await expectRejected(log, 'end after leave', () async => room.end());

      // Leaving twice stays a silent no-op so apps can call it from dispose().
      log.clear();
      await room.leave();
      expect(log.codes, isEmpty, reason: 'a second leave() should stay silent');
    }, timeout: const Timeout(Duration(minutes: 3)));

    // Regression cover for the unsubscribe / stopObserving gate move.
    //
    // The bug itself — the local handler surviving an unsubscribe() made after
    // leave() — is not observable from here: once the room is closed no
    // delivery can arrive to prove the handler is still bound, so an
    // "assert nothing arrives" check passes either way. What this does lock in
    // is the half that a mistake in the gate move would break: that removing
    // the handler still works on the normal in-meeting path.
    test('unsubscribe and stopObserving really drop the local handler',
        () async {
      if (!credentialsReady) {
        markTestSkipped('no usable AUTH_TOKEN/AUTH_URL in .env');
        return;
      }

      final String? id = await createMeetingId(token);
      expect(id, isNotNull, reason: 'could not create a meeting for this test');

      final Room room = buildRoom(roomId: id!, token: token);
      final ErrorLog log = ErrorLog()..bind(room);

      bool joined = false;
      room.on(Events.roomJoined, () => joined = true);
      await room.join();
      await Future<void>.delayed(const Duration(seconds: 12));
      expect(joined, isTrue, reason: 'the room never reported roomJoined');

      // ── pubSub ──────────────────────────────────────────────────────────
      final List<String> received = <String>[];
      void handler(PubSubMessage m) => received.add(m.message);

      await room.pubSub.subscribe('REGRESSION', handler);
      await room.pubSub.publish('REGRESSION', 'before-unsubscribe');
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(received, contains('before-unsubscribe'),
          reason: 'a subscribed handler should receive published messages');

      await room.pubSub.unsubscribe('REGRESSION', handler);
      received.clear();
      await room.pubSub.publish('REGRESSION', 'after-unsubscribe');
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(received, isEmpty,
          reason: 'unsubscribe() must remove the local handler');

      // ── realtimeStore ───────────────────────────────────────────────────
      final List<String?> observed = <String?>[];
      final String observerId = await room.realtimeStore
          .observe('regression-key', (String? v, Participant? _) {
        observed.add(v);
      });
      expect(observerId, isNotEmpty,
          reason: 'observe() in a joined room should return an observerId');

      await room.realtimeStore.setValue('regression-key', 'before-stop');
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(observed, contains('before-stop'),
          reason: 'an observer should receive value changes');

      await room.realtimeStore.stopObserving(observerId);
      observed.clear();
      await room.realtimeStore.setValue('regression-key', 'after-stop');
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(observed, isEmpty,
          reason: 'stopObserving() must remove the local observer');

      // Two observers on one key: stopping one must not silence the other.
      // off(key) used to drop every listener on the key, so the survivor went
      // quiet with no error and its _observers entry still in place.
      final List<String?> first = <String?>[];
      final List<String?> second = <String?>[];
      final String idFirst = await room.realtimeStore
          .observe('shared-key', (String? v, Participant? _) => first.add(v));
      final String idSecond = await room.realtimeStore
          .observe('shared-key', (String? v, Participant? _) => second.add(v));
      expect(idFirst, isNot(equals(idSecond)),
          reason: 'each observe() should get its own observerId');

      await room.realtimeStore.stopObserving(idFirst);
      first.clear();
      second.clear();
      await room.realtimeStore.setValue('shared-key', 'still-watching');
      await Future<void>.delayed(const Duration(seconds: 3));

      expect(second, contains('still-watching'),
          reason: 'stopping one observer must not remove the other one on '
              'the same key');
      expect(first, isEmpty,
          reason: 'the stopped observer must not receive anything');

      await room.realtimeStore.stopObserving(idSecond);

      log.clear();
      await room.leave();
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(log.codes, isEmpty, reason: 'leave() itself must not report');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });
}
