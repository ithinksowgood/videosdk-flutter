import 'dart:async';

import 'package:videosdk/src/core/utils/event_emitter.dart';

import 'logger.dart';

Logger _logger = Logger('EnhancedEventEmitter');

class EnhancedEventEmitter extends EventEmitter {
  EnhancedEventEmitter() : super();
  void safeEmit(String event, [Map<String, dynamic>? args]) {
    try {
      emit(event, args);
    } catch (error) {
      _logger.error(
        'safeEmit() event listener threw an error [event:$event]:$error',
      );
    }
  }

  Future<dynamic> safeEmitAsFuture(String event,
      [Map<String, dynamic>? args]) async {
    try {
      final Completer<dynamic> completer = Completer<dynamic>();
      // ignore: no_leading_underscores_for_local_identifiers
      Map<String, dynamic> _args = {
        'callback': completer.complete,
        'errback': completer.completeError,
        ...?args,
      };
      emitAsFuture(event, _args);
      return completer.future;
    } catch (error) {
      _logger.error(
        'safeEmitAsFuture() event listener threw an error [event:$event]:$error',
      );
    }
  }
}
