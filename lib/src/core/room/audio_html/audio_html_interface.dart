import 'package:videosdk/src/core/room/audio_html/audio_html_stub.dart'
    if (dart.library.io) 'package:videosdk/src/core/room/audio_html/providers/audio_html.dart'
    if (dart.library.html) 'package:videosdk/src/core/room/audio_html/providers/audio_html_web.dart';
import 'package:videosdk/src/core/webrtc/webrtc_client.dart';

// SowGood: the failure hook and its type (sowgood_audio_failure.dart).
export 'package:videosdk/src/core/room/audio_html/sowgood_audio_failure.dart';

abstract class AudioHTMLInterface {
  factory AudioHTMLInterface() => getInterface();

  Future<dynamic> startAudio(Consumer? audioConsumer);
  void stopAudio(String id);
  void setAudioOutputDevice(String deviceId);
}
