import 'package:flutter_test/flutter_test.dart';
import 'package:videosdk/src/core/webrtc/src/handlers/transceiver_mid.dart';
import 'package:videosdk_webrtc/flutter_webrtc.dart';

/// A transceiver whose `mid` behaves like dart_webrtc's on the web:
/// `_jsTransceiver.mid!` - it throws when the browser has no mid for it.
class _Transceiver implements RTCRtpTransceiver {
  _Transceiver(this.browserMid);

  final String? browserMid;

  @override
  String get mid => browserMid!;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The search receive() made before 2026-10-03: `t.mid == localId` over the
/// whole list (firstWhereOrNull).
RTCRtpTransceiver? _oldSearch(List<RTCRtpTransceiver> transceivers, String mid) {
  for (final t in transceivers) {
    if (t.mid == mid) return t;
  }
  return null;
}

void main() {
  // Safari, 2026-10-03: after a remote mic went off, the list held a
  // transceiver without a mid ahead of the new one.
  final stopped = _Transceiver(null);
  final host = _Transceiver('0');
  final fresh = _Transceiver('3');
  final list = <RTCRtpTransceiver>[host, stopped, fresh];

  test('the old search throws at a transceiver without a mid (the bug)', () {
    expect(() => _oldSearch(list, '3'), throwsA(isA<Error>()));
  });

  test('transceiverWithMid passes over it and finds the new transceiver', () {
    expect(transceiverWithMid(list, '3'), same(fresh));
    expect(transceiverWithMid(list, '0'), same(host));
  });

  test('no transceiver with that mid gives null, not a throw', () {
    expect(transceiverWithMid(list, '7'), isNull);
    expect(transceiverWithMid(<RTCRtpTransceiver>[stopped], '3'), isNull);
  });

  test('transceiverMidOrNull reads a mid, and null where reading throws', () {
    expect(transceiverMidOrNull(fresh), '3');
    expect(transceiverMidOrNull(stopped), isNull);
  });
}
