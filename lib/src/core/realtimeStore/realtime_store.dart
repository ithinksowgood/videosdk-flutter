import 'dart:convert';

import 'package:videosdk/src/core/utils/event_emitter.dart';
import 'package:videosdk/videosdk.dart';

/// Represents a key-value store for realtime data synchronization in the room.
///
/// ## Usage
///
/// ```dart
/// // Set a value
/// await room.realtimeStore.setValue("key", "value");
///
/// // Get a value
/// var value = await room.realtimeStore.getValue("key");
///
/// // Observe a key
/// room.realtimeStore.observe("key", (value, updatedBy) {
///   print("Value changed: $value");
/// });
/// ```
class RealtimeStore {
  late Function _setValueInternal;
  late Function _getValueInternal;
  late Function _observeInternal;
  late Function _stopObserveInternal;
  late EventEmitter? _realtimeStoreEventEmitter;

  //Room's meeting-state gate. Every method here reaches the network, so a call
  //made before join used to throw "Null check operator used on a null value"
  //straight into the app instead of reporting the error.
  late bool Function(String methodName) _ensureJoined;

  // Store observers with their IDs using a Map
  final Map<String, Map<String, dynamic>> _observers = {};

  /// @nodoc
  RealtimeStore({
    required Function setValue,
    required Function getValue,
    required Function observe,
    required Function stopObserve,
    bool Function(String methodName)? ensureJoined,
    required realtimeStoreEventEmitter,
  }) {
    _realtimeStoreEventEmitter = realtimeStoreEventEmitter;
    _setValueInternal = setValue;
    _getValueInternal = getValue;
    _observeInternal = observe;
    _stopObserveInternal = stopObserve;
    _ensureJoined = ensureJoined ?? (String _) => true;
  }

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

  /// The `setValue()` method is used to store or update data in the RealtimeStore. If a key already exists, it will be overwritten with the new value. Passing `null` as the value deletes the key.
  ///
  /// Key Notes:
  /// * Supports **String** values only.
  /// * Each key can store up to **1 KB** of data.
  /// * A maximum of **100 keys** are allowed per session.
  /// * Deletion is performed by setting the value to `null`.
  /// * Throws an error if:
  ///   * The key is missing or empty.
  ///   * The request fails.
  ///   * The session exceeds the 100-key limit.
  ///
  /// ### **Parameters**:
  /// * [key] - The unique key to store the data under.
  /// * [value] - The string value to be stored. Pass `null` to delete the key.
  ///
  /// Returns:
  /// * [Future<void>]
  ///
  /// ### **Example**
  /// ```dart
  /// String key = "BLOCK_CHAT";
  /// String value = "true";
  /// try {
  ///   await room.realtimeStore.setValue(key, value);
  /// } catch(e) {
  ///   print("Error:$e");
  /// }
  /// ```
  Future<void> setValue(String key, String? value) => _setValue(key, value);
  Future<void> _setValue(String key, String? value) async {
    if (key.trim().isEmpty) {
      throw "The 'key' parameter is empty.";
    }
    if (value != null) {
      if (value.trim().isEmpty) {
        throw "The 'value' parameter is empty.";
      }
    }
    // Size validation (1 KB = 1024 bytes)
    if (value != null) {
      final int sizeInBytes = utf8.encode(value).length;
      if (sizeInBytes > 1024) {
        throw Exception(
          "Payload too large: $sizeInBytes bytes. Maximum allowed size is 1024 bytes (1KB).",
        );
      }
    }
    if (!_ensureJoined("realtimeStore.setValue")) return;
    // internal function call
    await _setValueInternal(key, value);
  }

  /// The `getValue()` method retrieves the current value associated with a given key.
  ///
  /// Key Notes:
  /// * Returns the current string value for the given key.
  /// * Useful for fetching shared state when joining a meeting or reloading a view.
  /// * Throws an error if the key is missing/empty or if the request fails.
  ///
  /// ### **Parameters**:
  /// * [key] - The key whose value you want to retrieve.
  ///
  /// Returns:
  /// * [Future<String?>] - The stored value or `null` if there was a problem fetching the value.
  ///
  /// ### **Example**
  /// ```dart
  /// String key = "BLOCK_CHAT";
  /// try {
  ///   String? response = await room.realtimeStore.getValue(key);
  ///   print("Realtime Store Get Value: $response");
  /// } catch(e) {
  ///   print("Error:$e");
  /// }
  /// ```
  Future<String?> getValue(String key) => _getValue(key);
  Future<String?> _getValue(String key) async {
    if (key.trim().isEmpty) return "The 'key' parameter is empty.";
    if (!_ensureJoined("realtimeStore.getValue")) return null;
    // internal function call
    String response = await _getValueInternal(key);
    // return the response to the user
    return response;
  }

  /// The `observe()` method subscribes to real-time updates for a given key. When the key’s value changes, a delegate method on your listener is automatically triggered for all connected participants.
  ///
  /// Key Notes:
  /// * Returns an `observerId` which you can later use to stop observing.
  /// * The callback receives the new value and information about who updated it.
  /// * Ideal for syncing live data like timers, shared notes, or agendas.
  ///
  /// ### **Parameters**:
  /// * [key] - The key to observe.
  /// * [callback] - Function triggered on each update. Receives:
  ///   * `value` (`String?`) → Updated value or `null` if deleted
  ///   * `updatedBy` (`Participant?`) → Object of participant who made the update
  ///
  /// Returns:
  /// * [Future<String>]
  ///
  /// ### **Example**
  /// ```dart
  /// String key = "BLOCK_CHAT";
  /// try {
  ///   var observerId = await room.realtimeStore.observe(key, (value, updatedBy) {
  ///     print("Updated by: ${updatedBy?.id}");
  ///   });
  /// } catch(e) {
  ///   print("Error:$e");
  /// }
  /// ```
  Future<String> observe(
    String key,
    Function(String? value, Participant? updatedBy) callback,
  ) =>
      _observe(key, callback);
  Future<String> _observe(
    String key,
    Function(String? value, Participant? updatedBy) callback,
  ) async {
    if (key.trim().isEmpty) return "The 'key' parameter is empty.";
    // return if _realtimeStoreEventEmitter is not initialized
    if (_realtimeStoreEventEmitter == null) {
      throw Exception("EventEmitter is not initialized");
    }
    //Rejected calls return an empty observerId — there is nothing to stop
    //observing later — after raising exactly one error.
    if (!_ensureJoined("realtimeStore.observe")) return "";
    // Allocate the observerID from a generateId function from current Date&Time
    final observerId = _generateObserverId();

    // when event emitted then provide the value on that callback
    listener(event, context) {
      if (event != null) {
        String? value = event['value'];
        final Participant? updatedBy = event['updatedBy'];
        callback(value, updatedBy);
      }
    }

    //Registered before the request goes out, then unwound if it fails. Awaiting
    //first would close the stale-observer hole but open another one: the server
    //can push the current value as soon as it acks the observe, and a listener
    //attached after the await misses it. Registering first and unwinding in the
    //catch closes both.
    _observers[observerId] = {
      'key': key,
      'callback': callback,
      //Kept so stopObserving() can remove exactly this listener instead of
      //every listener on the key.
      'listener': listener,
    };
    _realtimeStoreEventEmitter!.on(key, listener);

    try {
      await _observeInternal(key);
    } catch (_) {
      //Targeted remove, not off(key): another observer may be watching the same
      //key and must not lose its listener because this one failed.
      _realtimeStoreEventEmitter!.remove(key, listener);
      _observers.remove(observerId);
      rethrow;
    }

    // return observerId to the user for stop observing purpose
    return observerId;
  }

  /// The `stopObserving()` method is used to stop observing a specific key using the `observerId` returned by `observe()`.
  ///
  /// ### **Parameters**:
  /// * [observerId] - The ID of the observer to stop.
  ///
  /// Returns:
  /// * [Future<void>]
  ///
  /// ### **Example**
  /// ```dart
  /// await room.realtimeStore.stopObserving(observerId);
  /// ```
  ///
  Future<void> stopObserving(String observerId) => _stopObserving(observerId);
  Future<void> _stopObserving(String observerId) async {
    if (observerId.trim().isEmpty) return;
    // fetch the observer
    final observer = _observers[observerId];
    if (observer == null) return;
    // get the key
    final key = observer['key'] as String;
    //Removes only this observer's listener. off(key) dropped every listener on
    //the key, so stopping one of two observers on the same key silently killed
    //the other — and left the isEmpty check below always true, which then told
    //the server to stop pushing the key while someone was still watching it.
    final listener = observer['listener'] as Function?;
    if (listener != null) {
      _realtimeStoreEventEmitter?.remove(key, listener);
    }
    // remove the observerId
    _observers.remove(observerId);
    // checks if still any value in list for the listeners is there or it is empty. If empty then will return true or when null will set it as true.
    //Local cleanup above is unconditional, like pubSub.unsubscribe: the app
    //asked to stop listening and that always succeeds. Only the server
    //round-trip below needs a joined meeting.
    if (_realtimeStoreEventEmitter?.listeners(key).isEmpty ?? true) {
      if (!_ensureJoined("realtimeStore.stopObserving")) return;
      await _stopObserveInternal(key);
    }
  }

// for generating the observerId
  String _generateObserverId() {
    return DateTime.now().millisecondsSinceEpoch.toString() +
        (DateTime.now().microsecond % 1000).toString();
  }

// dispose the oservers
  /// @nodoc
  void dispose() {
    _observers.clear();
  }
}
