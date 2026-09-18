import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:videosdk_webrtc/flutter_webrtc.dart';

/// @nodoc
const defaultRatchetSalt = 'VideoSDKEncryptionRatchetSalt';

/// @nodoc
const defaultRatchetWindowSize = 0;

/// @nodoc
const defaultDiscardFrameWhenCryptorNotReady = false;

/// @nodoc
abstract class KeyProviderBase {
  /// Sets a shared encryption key that is used by all participants.
  Future<void> setSharedKey(String key);

  /// Sets an encryption key for a specific participant.
  Future<void> setKey(String participantId, String key);

  /// Returns the underlying [KeyProvider] instance.
  KeyProvider get keyProvider;
}

/// Default implementation of [KeyProviderBase] used for end-to-end encryption.
///
/// - This class manages shared and per-participant encryption keys
/// and provides a [KeyProvider] instance for frame-level encryption.
///
/// ### **Example**
/// ```dart
/// final BaseKeyProvider customKeyProvider = BaseKeyProvider();
///
/// // Set a shared key for all participants
/// await customKeyProvider.setSharedKey('my-secure-key');
///
/// // Set a key for a specific participant
/// await customKeyProvider.setKey('participantId', 'participant-secret-key');
/// ```
class BaseKeyProvider implements KeyProviderBase {
  Uint8List? _sharedKey;
  KeyProvider? _keyProvider;

  /// @nodoc
  @override
  String toString() {
    return super.toString();
  }

  /// @nodoc
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }

  /// @nodoc
  @override
  bool operator ==(Object other) {
    return super == other;
  }

  /// @nodoc
  @override
  int get hashCode => super.hashCode;

  /// Stores participant-specific key providers mapped by participant ID.
  final Map<String, KeyProvider> keyMap = {};

  Uint8List? _key;

  /// Returns the active [KeyProvider] instance.
  ///
  /// This provider is used internally by the SDK for frame encryption.
  ///
  /// ### Returns
  ///
  /// - [KeyProvider]
  @override
  KeyProvider get keyProvider => _keyProvider!;

  /// @nodoc
  BaseKeyProvider({
    bool discardFrameWhenCryptorNotReady =
        defaultDiscardFrameWhenCryptorNotReady,
  });

  /// Returns the currently configured shared encryption key.
  ///
  /// ### Type
  ///
  /// - `Uint8List?`
  Uint8List? get sharedKey => _sharedKey;

  /// Returns the most recently set participant-specific encryption key.
  ///
  /// ### Type
  ///
  /// - `Uint8List?`
  Uint8List? get key => _key;

  /// Sets a shared encryption key for all participants.
  ///
  /// - This method configures a shared key provider that uses the same
  /// encryption key across all participants in the meeting.
  ///
  /// ### **Parameters**
  ///
  /// - [key]:
  ///   A UTF-8 string representing the shared encryption key.
  ///
  /// ### **Example**
  /// ```dart
  /// await customKeyProvider.setSharedKey('shared-secret-key');
  /// ```
  @override
  Future<void> setSharedKey(String key) => _setSharedKey(key);
  Future<void> _setSharedKey(String key) async {
    _keyProvider = await frameCryptorFactory.createDefaultKeyProvider(
      KeyProviderOptions(
        sharedKey: true,
        ratchetSalt: Uint8List.fromList(defaultRatchetSalt.codeUnits),
        ratchetWindowSize: defaultRatchetWindowSize,
        discardFrameWhenCryptorNotReady: defaultDiscardFrameWhenCryptorNotReady,
      ),
    );

    _sharedKey = Uint8List.fromList(key.codeUnits);

    await _keyProvider!.setSharedKey(key: _sharedKey!, index: 0);
  }

  /// Sets an encryption key for a specific participant.
  ///
  /// - This method creates a dedicated key provider for the given participant
  /// and assigns an individual encryption key.
  ///
  /// ### **Parameters**
  ///
  /// - [participantId]:
  ///   The unique identifier of the participant.
  ///
  /// - [key]:
  ///   A UTF-8 string representing the participant-specific encryption key.
  ///
  /// ### **Example**
  /// ```dart
  /// await customKeyProvider.setKey(
  ///   'participant123',
  ///   'participant-secret-key',
  /// );
  /// ```
  @override
  Future<void> setKey(String participantId, String key) =>
      _setKey(participantId, key);
  Future<void> _setKey(String participantId, String key) async {
    KeyProvider keyProvider =
        await frameCryptorFactory.createDefaultKeyProvider(
      KeyProviderOptions(
        sharedKey: false,
        ratchetSalt: Uint8List.fromList(defaultRatchetSalt.codeUnits),
        ratchetWindowSize: defaultRatchetWindowSize,
        discardFrameWhenCryptorNotReady: defaultDiscardFrameWhenCryptorNotReady,
      ),
    );

    _key = Uint8List.fromList(key.codeUnits);

    keyMap[participantId] = keyProvider;

    await keyProvider.setKey(
      key: _key!,
      index: 0,
      participantId: participantId,
    );
  }
}
