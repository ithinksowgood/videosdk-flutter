// SowGood (2026-11-17): on the web each remote speaker plays through an
// <audio> element, and two browser calls on it return a promise the SDK
// dropped: play() (startAudio) and setSinkId() (setAudioOutputDevice). A
// refusal or an abort then surfaced as an unhandled promise rejection - an
// error with no user and no trail (SOWGOOD-2RW, 2RY, 2PD, 7N). Both promises
// are handled now and a failure is handed to this hook.
//
// This file imports nothing, on purpose: it compiles on every platform and
// can be compiled alone for a browser probe.

/// A browser call on a remote audio element that did not succeed.
class SowgoodAudioFailure {
  const SowgoodAudioFailure({
    required this.operation,
    required this.errorName,
    required this.message,
    this.trackId,
    this.pending = Duration.zero,
  });

  /// 'play' (the element's play() was refused or aborted), 'setSinkId' (the
  /// speaker could not be set on an element) or 'startAudio' (an error in
  /// the SDK's own code around the element).
  final String operation;

  /// The browser's error name: 'NotAllowedError' (it wanted a tap first),
  /// 'AbortError' (the element was stopped or given another stream before
  /// the call finished), ... or 'unknown'.
  final String errorName;
  final String message;

  /// The remote audio track, when the call was about one.
  final String? trackId;

  /// How long the call was pending before it failed.
  final Duration pending;

  @override
  String toString() =>
      'SowgoodAudioFailure($operation $errorName${trackId == null ? '' : ', track $trackId'}, '
      'after ${pending.inMilliseconds} ms: $message)';
}

/// Set by the app to hear about such a failure. Null = it is only logged.
void Function(SowgoodAudioFailure failure)? sowgoodAudioFailed;

final RegExp _domErrorName = RegExp('[A-Za-z]+Error');

/// The browser's error name out of an error's TEXT ("NotAllowedError: The
/// request is not allowed ...", "Error: AbortError: The operation was
/// aborted."): the first word that ends in "Error" and is more than the bare
/// word "Error"; 'unknown' when there is none. The fallback for an error
/// that is not a JavaScript object with a `name` (js_error_name.dart reads
/// that first).
String sowgoodDomErrorName(String text) =>
    _domErrorName.firstMatch(text)?.group(0) ?? 'unknown';
