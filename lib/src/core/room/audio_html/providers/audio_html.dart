import 'package:videosdk/src/core/room/audio_html/audio_html_interface.dart';
import 'package:videosdk/src/core/webrtc/webrtc_client.dart';

class AudioHTML implements AudioHTMLInterface {
  @override
  Future startAudio(Consumer? audioConsumer) {
    // ToDo: implement startAudio
    throw UnimplementedError();
  }

  @override
  void stopAudio(String id) {
    // ToDo: implement stopAudio
    throw UnimplementedError();
  }

  @override
  void setAudioOutputDevice(String deviceId) {}
}

AudioHTMLInterface getInterface() => AudioHTML();
