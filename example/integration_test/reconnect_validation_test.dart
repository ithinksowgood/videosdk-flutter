// Reconnect behaviour on a real network drop.
//
// This is the half of the meeting-state work that no automated test has ever
// covered: 3027 firing, and _rejoinInProgress clearing once the room is back.
//
// It needs the network to actually go away, so it is driven from the host:
//
//   flutter test integration_test/reconnect_validation_test.dart -d <androidId>
//
// while the host toggles airplane mode with adb. The timings below are the
// contract between the two — change them here and in the driver script
// together.
//
// Timeline (seconds from the start of the test body):
//   0–20   join and settle
//   20–35  airplane mode ON  (host)
//   35     airplane mode OFF (host)
//   35–75  reconnect happens, then the assertions run

import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:videosdk/videosdk.dart';

const String kReconnecting = '3027';
const String kNotJoined = '3022';

/// Set by the driver script, which is the only thing that can take the network
/// away. Without it the whole body would pass trivially — nothing would ever
/// disconnect — so an undriven run skips instead of reporting a success it did
/// not earn.
///
///   flutter test ... --dart-define=RECONNECT_DRIVER=true
///
/// The driver in example/integration_test/drive_reconnect.sh passes it.
const bool kDriven = bool.fromEnvironment('RECONNECT_DRIVER');

Future<String?> readToken() async {
  if (!dotenv.isInitialized) {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      return null;
    }
  }
  final String? authToken = dotenv.env['AUTH_TOKEN'];
  if (authToken != null && authToken.isNotEmpty) return authToken;
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

  test('a real network drop reports 3027, then clears once rejoined', () async {
    if (!kDriven) {
      markTestSkipped('needs the host driver — run '
          'example/integration_test/drive_reconnect.sh, or pass '
          '--dart-define=RECONNECT_DRIVER=true while toggling the radio '
          'yourself. Without a real drop this test proves nothing.');
      return;
    }
    final String? token = await readToken();
    if (token == null || token.isEmpty) {
      markTestSkipped('no usable AUTH_TOKEN in .env');
      return;
    }
    final String? meetingId = await createMeetingId(token);
    if (meetingId == null || meetingId.isEmpty) {
      markTestSkipped('could not create a meeting — token may be expired');
      return;
    }

    final Room room = VideoSDK.createRoom(
      roomId: meetingId,
      token: token,
      displayName: 'ReconnectTest',
      micEnabled: false,
      camEnabled: false,
      signalingBaseUrl: '',
    );

    final List<String> errors = <String>[];
    final List<RoomState> states = <RoomState>[];
    bool joined = false;

    room.on(Events.error, (dynamic e) {
      if (e is Map) {
        errors.add('${e['code']}');
        // ignore: avoid_print
        print('RECONNECT_TEST | error ${e['code']}');
      }
    });
    room.on(Events.roomStateChanged, (dynamic s) {
      if (s is RoomState) {
        states.add(s);
        // ignore: avoid_print
        print('RECONNECT_TEST | state $s');
      }
    });
    room.on(Events.roomJoined, () {
      joined = true;
      // ignore: avoid_print
      print('RECONNECT_TEST | joined');
    });

    await room.join();

    // ── 0–20s: settle ──────────────────────────────────────────────────────
    await Future<void>.delayed(const Duration(seconds: 20));
    expect(joined, isTrue,
        reason: 'the room never joined — cannot test a drop');

    // Baseline: a gated call works while connected.
    errors.clear();
    await room.muteMic();
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(errors, isEmpty,
        reason: 'a joined room should accept muteMic before the drop');

    // ignore: avoid_print
    print('RECONNECT_TEST | READY_FOR_DROP');

    // ── 20–35s: the host has airplane mode ON. Prove 3027 fires. ───────────
    await Future<void>.delayed(const Duration(seconds: 8));
    errors.clear();
    await room.unmuteMic();
    await Future<void>.delayed(const Duration(seconds: 2));
    // ignore: avoid_print
    print('RECONNECT_TEST | during-drop codes: $errors');
    final bool saw3027 = errors.contains(kReconnecting);

    // The headline gap this file exists to close. Asserted, not just printed:
    // without it a mistimed or absent drop still reports success.
    expect(saw3027, isTrue,
        reason: 'the SDK never reported 3027 during the drop — either the '
            'gate did not engage or the drop was mistimed. Codes seen: '
            '$errors');

    // ── 35s+: the host has restored the network. Wait for the rejoin. ──────
    await Future<void>.delayed(const Duration(seconds: 40));

    // ignore: avoid_print
    print('RECONNECT_TEST | states seen: $states');

    // The finding-2 assertion: once back, gated calls must work again. If
    // _rejoinInProgress never cleared, this reports 3027 forever.
    errors.clear();
    await room.muteMic();
    await Future<void>.delayed(const Duration(seconds: 3));
    // ignore: avoid_print
    print('RECONNECT_TEST | after-reconnect codes: $errors');

    // Only the gate codes are asserted. A producer or codec error is plausible
    // right after a media rebuild, and failing on it here would point the
    // blame at the gate for something unrelated — so anything else is reported
    // and left alone.
    expect(errors, isNot(contains(kReconnecting)),
        reason: 'after a completed reconnect the gate must be open again — '
            '_rejoinInProgress did not clear');
    expect(errors, isNot(contains(kNotJoined)),
        reason: 'a rejoined room reported not-joined');

    final List<String> unrelated = errors
        .where((String c) => c != kReconnecting && c != kNotJoined)
        .toList();
    if (unrelated.isNotEmpty) {
      // ignore: avoid_print
      print('RECONNECT_TEST | note: unrelated codes after reconnect '
          '$unrelated — not a gate failure');
    }

    await room.leave();
    await Future<void>.delayed(const Duration(seconds: 3));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
