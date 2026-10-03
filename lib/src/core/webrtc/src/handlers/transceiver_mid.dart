import 'package:videosdk_webrtc/flutter_webrtc.dart';

/// The transceiver's mid, or null when the browser has none for it.
///
/// On the web, dart_webrtc (1.7.0, `rtc_rtp_transceiver_impl.dart:78`) reads
/// `mid` as `_jsTransceiver.mid!`, so reading the mid of a transceiver the
/// browser reports without one throws "Null check operator used on a null
/// value". SowGood, 2026-10-03: Safari (iPhone 26.6.1, iPad 18.5) threw there
/// at the first remote mic-on after a remote mic had gone off, inside
/// `receive()`'s search of `getTransceivers()`, and from then on no new remote
/// sound reached that listener; Chrome, in the same room, heard every cycle.
String? transceiverMidOrNull(RTCRtpTransceiver transceiver) {
  try {
    return transceiver.mid;
  } catch (_) {
    return null;
  }
}

/// The first of [transceivers] whose mid is [mid]. A transceiver without a
/// mid is passed over instead of failing the whole search.
RTCRtpTransceiver? transceiverWithMid(
  Iterable<RTCRtpTransceiver> transceivers,
  String mid,
) {
  for (final transceiver in transceivers) {
    if (transceiverMidOrNull(transceiver) == mid) return transceiver;
  }
  return null;
}
