// ignore_for_file: no_leading_underscores_for_local_identifiers, invalid_runtime_check_with_js_interop_types

import 'dart:developer';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:dart_webrtc/dart_webrtc.dart';
import 'package:videosdk/src/core/room/audio_html/audio_html_interface.dart';
import 'package:videosdk/src/core/room/audio_html/providers/js_error_name.dart';
import 'package:videosdk/src/core/webrtc/webrtc_client.dart';
import 'package:web/web.dart' as web;

class AudioHTMLWeb implements AudioHTMLInterface {
  final Map<String, web.Element> _audioElements = {};

  @override
  Future<dynamic> startAudio(Consumer? audioConsumer) async {
    // SowGood (2026-11-17): the caller does not await this, and it used to
    // end in `return audioElement.play()` - the browser's own promise, which
    // nothing handled. A refusal (Safari wants a tap for a page's first
    // sound) or an abort (the element stopped before it started) then
    // surfaced as an unhandled rejection with no user and no trail
    // (SOWGOOD-2RW / 2RY). play() is awaited here and a failure goes to
    // sowgoodAudioFailed; this method never throws.
    String? trackId;
    try {
      // ignore: unnecessary_null_comparison
      if (audioConsumer == null || audioConsumer.track == null) {
        return;
      }

      MediaStreamTrack track = audioConsumer.track;

      if (track is! MediaStreamTrackWeb) {
        return;
      }
      trackId = track.id;

      final elementId = "audio_${track.id}";
      var audioElement = web.document.getElementById(elementId);
      if (audioElement == null) {
        audioElement = web.HTMLAudioElement()
          ..id = elementId
          ..autoplay = true;
        findOrCreateAudioContainer().append(audioElement);
        _audioElements[track.id!] = audioElement;
      }

      if (audioElement is! web.HTMLAudioElement) {
        return;
      }
      var _srcObject = audioConsumer.stream as MediaStreamWeb;
      // ignore: unnecessary_null_comparison
      if (null != _srcObject) {
        if (audioConsumer.stream.getAudioTracks().isNotEmpty) {
          final audioStream = web.MediaStream();
          for (final track in _srcObject.jsStream.getAudioTracks().toDart) {
            audioStream.addTrack(track);
          }
          audioElement.srcObject = audioStream;
          final asked = DateTime.now();
          try {
            await audioElement.play().toDart;
          } catch (error) {
            _reportAudioFailure(
              'play',
              error,
              trackId: trackId,
              pending: DateTime.now().difference(asked),
            );
          }
        }
      } else {
        log("srcObject null");
      }
    } catch (error) {
      _reportAudioFailure('startAudio', error, trackId: trackId);
    }
  }

  web.HTMLDivElement findOrCreateAudioContainer() {
    var div = web.document.getElementById("videosdk_audio_container");
    if (div != null) {
      return div as web.HTMLDivElement;
    }

    div = web.HTMLDivElement()
      ..id = "videosdk_audio_container"
      ..style.display = 'none';
    web.document.body?.append(div);
    return div as web.HTMLDivElement;
  }

  @override
  void stopAudio(String id) {
    final audioElement = web.document.getElementById("audio_$id");
    if (audioElement != null) {
      if (audioElement is web.HTMLAudioElement) {
        audioElement.srcObject = null;
      }
      _audioElements.remove(id);
      audioElement.remove();
    }
  }

  @override
  void setAudioOutputDevice(String deviceId) {
    web.HTMLCollection audioElements =
        web.document.getElementsByTagName('audio');

    for (var i = 0; i < audioElements.length; i++) {
      if ((audioElements.item(i)!).hasProperty("setSinkId" as JSAny) as bool) {
        // SowGood (2026-11-17): setSinkId returns a promise, which was
        // dropped. Safari refuses the call outside a tap ("A user gesture is
        // required", SOWGOOD-2PD) and Chrome can abort it ("The operation
        // could not be performed and was aborted", SOWGOOD-7N); either one
        // surfaced as an unhandled rejection. The promise is handled and a
        // failure goes to sowgoodAudioFailed.
        final asked = DateTime.now();
        try {
          final result = audioElements
              .item(i)!
              .callMethod<JSAny?>("setSinkId".toJS, deviceId.toJS);
          if (result != null) {
            (result as JSPromise<JSAny?>).toDart.then<void>(
              (_) {},
              onError: (Object error) {
                _reportAudioFailure(
                  'setSinkId',
                  error,
                  pending: DateTime.now().difference(asked),
                );
              },
            );
          }
        } catch (error) {
          _reportAudioFailure('setSinkId', error);
        }
      }
    }
  }
}

/// Hands a failed browser call to the app's hook (sowgoodAudioFailed), or
/// logs it when no hook is set. Never throws: reporting must not break
/// playback.
void _reportAudioFailure(
  String operation,
  Object error, {
  String? trackId,
  Duration pending = Duration.zero,
}) {
  try {
    final text = '$error';
    final failure = SowgoodAudioFailure(
      operation: operation,
      // The error object's own name first; its text only as the fallback.
      errorName: sowgoodJsErrorName(error) ?? sowgoodDomErrorName(text),
      message: text,
      trackId: trackId,
      pending: pending,
    );
    final hook = sowgoodAudioFailed;
    if (hook != null) {
      hook(failure);
    } else {
      log('$failure');
    }
  } catch (_) {}
}

AudioHTMLInterface getInterface() => AudioHTMLWeb();
