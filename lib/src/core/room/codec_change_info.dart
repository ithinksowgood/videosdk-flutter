import 'codec.dart';
import 'participant.dart';

/// Payload for the [Events.codecChanged] event.
///
/// Emitted when the local webcam codec is automatically switched (e.g., a
/// fallback to VP8 because a remote participant could not decode the codec
/// we were producing).
class CodecChangeInfo {
  /// The codec a remote peer could not decode.
  final VideoCodec unsupportedRemoteCodec;

  /// The codec we are now producing.
  final VideoCodec currentCodec;

  /// The codec we were producing before the switch.
  final VideoCodec previousCodec;

  /// The media kind. Currently always `'video'`.
  final String kind;

  /// The participant that triggered the switch, if known.
  final Participant? causedBy;

  const CodecChangeInfo({
    required this.unsupportedRemoteCodec,
    required this.currentCodec,
    required this.previousCodec,
    required this.kind,
    required this.causedBy,
  });
}
