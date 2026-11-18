import 'package:flutter_test/flutter_test.dart';
import 'package:videosdk/src/core/room/audio_html/audio_html_interface.dart';

// The error texts are the ones Sentry recorded at the 2026-11-17 event
// (SOWGOOD-2RW, 2RY, 7N, 2PD).
void main() {
  group('sowgoodDomErrorName', () {
    test('a refused play(): Safari\'s wording', () {
      expect(
        sowgoodDomErrorName(
          'NotAllowedError: The request is not allowed by the user agent or '
          'the platform in the current context, possibly because the user '
          'denied permission.',
        ),
        'NotAllowedError',
      );
    });

    test('an aborted play(), with the bare "Error:" some layers put first',
        () {
      expect(
        sowgoodDomErrorName('Error: AbortError: The operation was aborted.'),
        'AbortError',
      );
      expect(
        sowgoodDomErrorName(
          'AbortError: The operation could not be performed and was aborted',
        ),
        'AbortError',
      );
    });

    test('a refused setSinkId()', () {
      expect(
        sowgoodDomErrorName('NotAllowedError: A user gesture is required'),
        'NotAllowedError',
      );
    });

    test('no error name in the text', () {
      expect(sowgoodDomErrorName('something else went wrong'), 'unknown');
      expect(sowgoodDomErrorName('Error: no name here'), 'unknown');
    });
  });

  test('a failure prints what happened', () {
    const failure = SowgoodAudioFailure(
      operation: 'play',
      errorName: 'NotAllowedError',
      message: 'NotAllowedError: refused',
      trackId: 't1',
      pending: Duration(milliseconds: 12),
    );
    expect(
      '$failure',
      'SowgoodAudioFailure(play NotAllowedError, track t1, after 12 ms: '
      'NotAllowedError: refused)',
    );
  });
}
