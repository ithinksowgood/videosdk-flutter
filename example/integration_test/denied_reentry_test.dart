// The device half of the denied-re-entry experiment — finding 2.
//
// Sequence, orchestrated by drive_denied_reentry.sh:
//
//   1. this room joins on the device
//   2. the driver takes the radio away
//   3. the moderator (on the host, still online) removes this participant
//   4. the radio comes back and the SDK re-requests entry
//   5. we call a gated method and read the code that comes back
//
// The code is the whole answer:
//
//   3022  the server closed the socket after denying → onClose → _close()
//         cleared _rejoinInProgress → finding 2 is unreachable
//   3027  nothing reset the flag → the room reports "reconnecting" forever,
//         with leave() as the only way out → finding 2 is confirmed
//
// The test fails on the 3027 outcome, because that is the defect.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:videosdk/videosdk.dart';

const String kMeetingId = String.fromEnvironment('MEETING_ID');
const String kToken = String.fromEnvironment('MEETING_TOKEN');

const String kReconnecting = '3027';
const String kNotJoined = '3022';

/// Must match kTargetName in moderator_remove_test.dart.
const String kMyName = 'DropTarget';

void say(String msg) {
  // ignore: avoid_print
  print('DEVICE | $msg');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('a re-entry that the server refuses does not strand the room', () async {
    if (kMeetingId.isEmpty || kToken.isEmpty) {
      markTestSkipped('driven by drive_denied_reentry.sh only');
      return;
    }

    final Room room = VideoSDK.createRoom(
      roomId: kMeetingId,
      token: kToken,
      displayName: kMyName,
      micEnabled: false,
      camEnabled: false,
      signalingBaseUrl: '',
    );

    final List<String> errors = <String>[];
    final List<RoomState> states = <RoomState>[];
    bool joined = false;
    bool left = false;

    room.on(Events.error, (dynamic e) {
      if (e is Map) {
        errors.add('${e['code']}');
        say('error ${e['code']}');
      }
    });
    room.on(Events.roomStateChanged, (dynamic s) {
      if (s is RoomState) {
        states.add(s);
        say('state $s');
      }
    });
    room.on(Events.roomJoined, () {
      joined = true;
      say('joined');
    });
    room.on(Events.roomLeft, (dynamic _) {
      left = true;
      say('roomLeft');
    });

    await room.join();
    await Future<void>.delayed(const Duration(seconds: 18));
    expect(joined, isTrue, reason: 'never joined — cannot run the experiment');

    errors.clear();
    say('READY_FOR_DROP');

    // Offline, removed by the moderator, then back. Long enough for the
    // re-entry attempt, short enough not to exhaust the 5 reconnect attempts
    // (which would close the room for an unrelated reason).
    await Future<void>.delayed(const Duration(seconds: 50));

    say('states: $states');
    say('left=$left codes so far: $errors');

    // The reading that answers the question.
    errors.clear();
    await room.muteMic();
    await Future<void>.delayed(const Duration(seconds: 3));
    say('VERDICT codes after refused re-entry: $errors');

    if (errors.contains(kNotJoined)) {
      say('VERDICT 3022 — the room was torn down; finding 2 unreachable');
    } else if (errors.contains(kReconnecting)) {
      say('VERDICT 3027 — the room is stranded; finding 2 CONFIRMED');
    } else if (errors.isEmpty) {
      say('VERDICT no error — the server let us back in; the removal did not '
          'take effect, so this run does not answer the question');
    }

    expect(errors, isNot(contains(kReconnecting)),
        reason: 'the room reports 3027 after a refused re-entry and nothing '
            'clears _rejoinInProgress — finding 2 is real. Only leave() '
            'escapes from here.');

    await room.leave();
    await Future<void>.delayed(const Duration(seconds: 3));
  }, timeout: const Timeout(Duration(minutes: 5)));
}
