import 'package:flutter_test/flutter_test.dart';
import 'package:sdp_transform/sdp_transform.dart';
import 'package:videosdk/src/core/webrtc/src/handlers/sdp/media_section.dart';
import 'package:videosdk/src/core/webrtc/src/sdp_object.dart';

/// An offer shaped like Firefox's: `a=extmap-allow-mixed` inside the media
/// section (Chrome puts it at the session level, which SdpObject drops).
final String _firefoxOffer = [
  'v=0',
  'o=mozilla...THIS_IS_SDPARTA-99.0 6432939839406392437 0 IN IP4 0.0.0.0',
  's=-',
  't=0 0',
  'a=fingerprint:sha-256 2A:5B:3C:4D:5E:6F:70:81:92:A3:B4:C5:D6:E7:F8:09:1A:2B:3C:4D:5E:6F:70:81:92:A3:B4:C5:D6:E7:F8:09',
  'a=group:BUNDLE 0',
  'a=ice-options:trickle',
  'a=msid-semantic:WMS *',
  'm=audio 9 UDP/TLS/RTP/SAVPF 109',
  'c=IN IP4 0.0.0.0',
  'a=sendonly',
  'a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level',
  'a=extmap-allow-mixed',
  'a=ice-pwd:4c1d2e3f4a5b6c7d8e9f0a1b2c3d4e5f',
  'a=ice-ufrag:5a6b7c8d',
  'a=mid:0',
  'a=rtcp-mux',
  'a=rtpmap:109 opus/48000/2',
  'a=setup:actpass',
  'a=ssrc:3473846153 cname:{8b6d6d1a-1d2e-4c3f-9a8b-7c6d5e4f3a2b}',
  '',
].join('\r\n');

void main() {
  // SowGood, 2026-10-24: a viewer on Firefox accepted the host's invitation
  // to speak; the send() answer copied extmapAllowMixed = true from the offer
  // and write() threw "J.d1(...).av is not a function" (forEach on a bool):
  // her mic and camera never started (Sentry SOWGOOD-2R1).
  test('a media section with extmap-allow-mixed writes without throwing', () {
    final sdp = SdpObject.fromMap(parse(_firefoxOffer));
    expect(sdp.media.single.extmapAllowMixed, isTrue);
    expect(() => write(sdp.toMap(), null), returnsNormally);
  });

  test('the written section keeps a=extmap-allow-mixed and reads back', () {
    final written = write(SdpObject.fromMap(parse(_firefoxOffer)).toMap(), null);
    final mediaPart = written.substring(written.indexOf('m=audio'));
    expect(mediaPart, contains('a=extmap-allow-mixed\r\n'));
    expect(
      SdpObject.fromMap(parse(written)).media.single.extmapAllowMixed,
      isTrue,
    );
  });

  test('an answer section that allows mixed extensions writes the line', () {
    // AnswerMediaSection sets the flag when both sides allow it.
    final media = MediaObject.fromMap(parse(_firefoxOffer)['media'][0])
      ..extmapAllowMixed = true;
    final line = write({
      ...SdpObject.fromMap(parse(_firefoxOffer)).toMap(),
      'media': [media.toMap()],
    }, null);
    expect(line, contains('a=extmap-allow-mixed\r\n'));
  });

  test('a section without the attribute writes no such line (Chrome)', () {
    final chrome = _firefoxOffer.replaceFirst('a=extmap-allow-mixed\r\n', '');
    final sdp = SdpObject.fromMap(parse(chrome));
    expect(sdp.media.single.extmapAllowMixed, isNot(isTrue));
    expect(write(sdp.toMap(), null), isNot(contains('extmap-allow-mixed')));
  });
}
