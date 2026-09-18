// The moderator half of the denied-re-entry experiment.
//
// Runs on the HOST (macOS), so it keeps its connection while the device under
// test loses the radio. It joins the same meeting, waits for a signal file the
// driver touches once the device is offline, then removes the device's
// participant. The device then tries to re-enter a meeting it is no longer
// allowed into — which is the case finding 2 is about.
//
// Driven by drive_denied_reentry.sh; not meant to be run on its own.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:videosdk/videosdk.dart';
import 'dart:io';

const String kMeetingId = String.fromEnvironment('MEETING_ID');
const String kToken = String.fromEnvironment('MEETING_TOKEN');
const String kSignalFile = String.fromEnvironment('SIGNAL_FILE');

/// Display name of the participant to remove — must match the device side.
const String kTargetName = 'DropTarget';

void say(String msg) {
  // ignore: avoid_print
  print('MODERATOR | $msg');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('moderator removes the offline participant', () async {
    if (kMeetingId.isEmpty || kToken.isEmpty || kSignalFile.isEmpty) {
      markTestSkipped('driven by drive_denied_reentry.sh only');
      return;
    }

    final Room room = VideoSDK.createRoom(
      roomId: kMeetingId,
      token: kToken,
      displayName: 'Moderator',
      micEnabled: false,
      camEnabled: false,
      signalingBaseUrl: '',
    );

    bool joined = false;
    room.on(Events.roomJoined, () {
      joined = true;
      say('joined');
    });
    room.on(Events.participantJoined, (Participant p) {
      say('sees participant ${p.displayName} (${p.id})');
    });

    await room.join();
    await Future<void>.delayed(const Duration(seconds: 15));
    expect(joined, isTrue, reason: 'moderator never joined');

    say('participants: '
        '${room.participants.values.map((Participant p) => p.displayName).toList()}');

    // Wait for the driver to confirm the device is offline.
    final File signal = File(kSignalFile);
    say('waiting for signal at $kSignalFile');
    bool signalled = false;
    for (int i = 0; i < 120; i++) {
      if (signal.existsSync()) {
        signalled = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    expect(signalled, isTrue,
        reason: 'driver never signalled — device offline?');
    say('signalled — removing $kTargetName');

    Participant? target;
    for (final Participant p in room.participants.values) {
      if (p.displayName == kTargetName) target = p;
    }

    if (target == null) {
      say('WARNING: $kTargetName not in the participant list; nothing to '
          'remove. The device may have already dropped out server-side.');
    } else {
      say('removing ${target.displayName} (${target.id})');
      target.remove();
      say('remove() issued');
    }

    // Stay in the meeting while the device tries to come back.
    await Future<void>.delayed(const Duration(seconds: 45));
    say('participants now: '
        '${room.participants.values.map((Participant p) => p.displayName).toList()}');

    await room.leave();
    await Future<void>.delayed(const Duration(seconds: 3));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
