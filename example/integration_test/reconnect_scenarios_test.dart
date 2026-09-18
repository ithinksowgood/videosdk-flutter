// The three reconnect scenarios the design doc lists as never exercised.
//
// Host-driven, like reconnect_validation_test.dart: each test prints
// READY_FOR_DROP when it is settled, and the driver script toggles airplane
// mode on the device. Three drops, one per test, in order.
//
//   ./integration_test/drive_reconnect.sh scenarios
//
// Running flutter test directly skips every test: without the driver there is
// no drop, and each body would pass having proved nothing.
//
// Not covered here: enableShare() during a reconnect. Past the silent
// not-joined check it reaches real capture, which opens the system picker and
// would block the run. That one needs a human.

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:videosdk/videosdk.dart';

const String kReconnecting = '3027';
const String kNotJoined = '3022';

/// Set by drive_reconnect.sh. Without a real drop every test here passes
/// trivially, so an undriven run skips rather than reporting a false success.
const bool kDriven = bool.fromEnvironment('RECONNECT_DRIVER');

const String kSkipReason = 'needs the host driver — run '
    'example/integration_test/drive_reconnect.sh scenarios. Without a real '
    'drop these tests prove nothing.';

void say(String msg) {
  // ignore: avoid_print
  print('SCENARIO_TEST | $msg');
}

Future<String?> readToken() async {
  if (!dotenv.isInitialized) {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      return null;
    }
  }
  final String? t = dotenv.env['AUTH_TOKEN'];
  return (t != null && t.isNotEmpty) ? t : null;
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

/// Joins a fresh meeting and returns it once [Events.roomJoined] has fired.
Future<Room?> joinFreshRoom(
  String token,
  String label,
  List<String> errors,
  List<RoomState> states, {
  bool micEnabled = false,
}) async {
  final String? meetingId = await createMeetingId(token);
  if (meetingId == null || meetingId.isEmpty) return null;

  final Room room = VideoSDK.createRoom(
    roomId: meetingId,
    token: token,
    displayName: label,
    micEnabled: micEnabled,
    camEnabled: false,
    signalingBaseUrl: '',
  );

  bool joined = false;
  room.on(Events.error, (dynamic e) {
    if (e is Map) {
      errors.add('${e['code']}');
      say('$label error ${e['code']}');
    }
  });
  room.on(Events.roomStateChanged, (dynamic s) {
    if (s is RoomState) {
      states.add(s);
      say('$label state $s');
    }
  });
  room.on(Events.roomJoined, () {
    joined = true;
    say('$label joined');
  });

  await room.join();
  await Future<void>.delayed(const Duration(seconds: 16));
  return joined ? room : null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String token;
  bool ready = false;

  setUpAll(() async {
    final String? t = await readToken();
    if (t == null) return;
    token = t;
    ready = true;
  });

  // ── A ──────────────────────────────────────────────────────────────────
  // leave() while the connection is gone. This is the escape hatch: it used
  // to wait on definePeerLeftReason, an ack that a dead socket can never
  // send, so leave() hung exactly when a user most wants out.
  test('leave() during a reconnect returns promptly and does not hang',
      () async {
    if (!kDriven) {
      markTestSkipped(kSkipReason);
      return;
    }
    if (!ready) {
      markTestSkipped('no usable AUTH_TOKEN in .env');
      return;
    }
    final List<String> errors = <String>[];
    final List<RoomState> states = <RoomState>[];
    final Room? room = await joinFreshRoom(token, 'A', errors, states);
    expect(room, isNotNull, reason: 'could not join — cannot test the drop');

    bool left = false;
    room!.on(Events.roomLeft, (dynamic _) {
      left = true;
      say('A roomLeft');
    });

    say('READY_FOR_DROP');
    await Future<void>.delayed(const Duration(seconds: 6));

    // Mid-drop. leave() must come back quickly rather than block on an ack.
    errors.clear();
    final Stopwatch sw = Stopwatch()..start();
    bool timedOut = false;
    await room
        .leave()
        .timeout(const Duration(seconds: 15), onTimeout: () => timedOut = true);
    sw.stop();
    say('A leave() returned in ${sw.elapsedMilliseconds}ms, timedOut=$timedOut');

    expect(timedOut, isFalse,
        reason: 'leave() hung during a reconnect — the ack wait is back');
    expect(sw.elapsedMilliseconds, lessThan(10000),
        reason: 'leave() took ${sw.elapsedMilliseconds}ms; it should not be '
            'waiting on the network');

    await Future<void>.delayed(const Duration(seconds: 4));
    say('A left=$left codes=$errors');
    expect(left, isTrue, reason: 'leave() never emitted roomLeft');
    // Gate codes only: an unrelated teardown error should not read as the
    // gate having wrongly rejected leave().
    expect(errors, isNot(contains(kReconnecting)),
        reason: 'leave() must never be rejected for reconnecting');
    expect(errors, isNot(contains(kNotJoined)),
        reason: 'leave() on a joined room must not report not-joined');

    // Let the driver's radio-on land before the next test.
    await Future<void>.delayed(const Duration(seconds: 20));
  }, timeout: const Timeout(Duration(minutes: 4)));

  // ── B ──────────────────────────────────────────────────────────────────
  // Switching the mic, then a drop, with the mic live. The reconnect rebuilds
  // the audio producer internally; if any of those internal paths run through
  // an app-facing gate, the user gets spurious errors on every reconnect.
  test('switching the mic then reconnecting stays silent', () async {
    if (!kDriven) {
      markTestSkipped(kSkipReason);
      return;
    }
    if (!ready) {
      markTestSkipped('no usable AUTH_TOKEN in .env');
      return;
    }
    final List<String> errors = <String>[];
    final List<RoomState> states = <RoomState>[];
    final Room? room =
        await joinFreshRoom(token, 'B', errors, states, micEnabled: true);
    expect(room, isNotNull, reason: 'could not join — cannot test the drop');

    errors.clear();
    await room!.unmuteMic();
    await Future<void>.delayed(const Duration(seconds: 2));

    final List<AudioDeviceInfo>? mics = await VideoSDK.getAudioDevices();
    say('B audio devices: ${mics?.length ?? 0}');
    if (mics != null && mics.isNotEmpty) {
      // changeMic() throws "not supported for Mobile devices" — on mobile the
      // equivalent is switchAudioDevice(), which is what an app would call.
      await room.switchAudioDevice(mics.first);
      await Future<void>.delayed(const Duration(seconds: 3));
      say('B after switchAudioDevice codes=$errors');
    }
    errors.clear();

    say('READY_FOR_DROP');

    // Through the drop and back.
    await Future<void>.delayed(const Duration(seconds: 45));
    say('B states: $states');
    say('B codes across the drop: $errors');

    // 3027 for the unmuteMic below would be correct if we were still down, so
    // the assertion that matters is the state afterwards: gated calls work.
    errors.clear();
    await room.muteMic();
    await Future<void>.delayed(const Duration(seconds: 3));
    say('B after-reconnect codes=$errors');

    expect(errors, isNot(contains(kReconnecting)),
        reason: 'the gate stayed shut after the reconnect completed');
    expect(errors, isNot(contains(kNotJoined)),
        reason: 'a rejoined room reported not-joined');

    await room.leave();
    await Future<void>.delayed(const Duration(seconds: 3));
  }, timeout: const Timeout(Duration(minutes: 4)));

  // ── C ──────────────────────────────────────────────────────────────────
  // disableShare() is the STOP_SCREENSHARE platform callback — the SDK's own
  // EventChannel calls it when the user stops the broadcast from the system
  // UI. It is ungated on purpose, so mid-reconnect it must stay silent and
  // clean up rather than report an error the app never caused.
  test('disableShare() during a reconnect stays silent', () async {
    if (!kDriven) {
      markTestSkipped(kSkipReason);
      return;
    }
    if (!ready) {
      markTestSkipped('no usable AUTH_TOKEN in .env');
      return;
    }
    final List<String> errors = <String>[];
    final List<RoomState> states = <RoomState>[];
    final Room? room = await joinFreshRoom(token, 'C', errors, states);
    expect(room, isNotNull, reason: 'could not join — cannot test the drop');

    say('READY_FOR_DROP');
    await Future<void>.delayed(const Duration(seconds: 6));

    errors.clear();
    bool timedOut = false;
    await room!
        .disableShare()
        .timeout(const Duration(seconds: 15), onTimeout: () => timedOut = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    say('C mid-drop disableShare codes=$errors timedOut=$timedOut');

    expect(timedOut, isFalse, reason: 'disableShare() blocked during a drop');
    expect(errors, isEmpty,
        reason: 'disableShare() is an internal platform callback and must not '
            'report to the app, got $errors');

    // Back up: the room should still be usable.
    await Future<void>.delayed(const Duration(seconds: 35));
    say('C states: $states');
    errors.clear();
    await room.muteMic();
    await Future<void>.delayed(const Duration(seconds: 3));
    say('C after-reconnect codes=$errors');
    expect(errors, isNot(contains(kReconnecting)),
        reason: 'the gate stayed shut after the reconnect completed');

    await room.leave();
    await Future<void>.delayed(const Duration(seconds: 3));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
