import 'dart:async';
import 'package:videosdk/src/core/utils/event_emitter.dart';
// ignore: library_prefixes
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:videosdk/src/core/room/leave_reason.dart';

class WebSocket {
  final String peerId;
  final String meetingId;
  final String token;
  final String baseUrl;
  final String mode;
  String? socketUrl;
  String? socketPath;

  late IO.Socket _socket;
  Function()? onOpen;
  final _eventEmitter = EventEmitter();
  Function(dynamic)? onReconnection;
  Function()? onDisconnected;
  Function(dynamic data)? onClose;
  Function(
    dynamic request,
    dynamic accept,
    dynamic reject,
  )? onRequest; // request, accept, reject
  Function(dynamic notification)? onNotification;

  IO.Socket get socket => _socket;

  WebSocket({
    required this.peerId,
    required this.meetingId,
    required this.token,
    required this.baseUrl,
    required this.mode,
    required this.socketPath,
    required this.socketUrl,
  }) {
    _socket = IO.io(
      "https://${socketUrl ?? baseUrl}/socket.io?roomId=$meetingId&peerId=$peerId&secret=$token&mode=$mode&lib=socket",
      IO.OptionBuilder()
          .setQuery({
            'roomId': meetingId,
            'peerId': peerId,
            'secret': token,
            'mode': mode,
          })
          .setTransports(['websocket'])
          .enableReconnection()
          .setPath("${socketPath ?? ""}/socket.io")
          .setReconnectionAttempts(5)
          .setReconnectionDelay(5000)
          .build(),
    );

    _setupListeners();

    _socket.connect();
  }

  void _setupListeners() {
    _socket.on('connect', (_) {});

    _socket.on('connectionSuccess', (data) {
      onOpen?.call();
    });

    _socket.on('connect_error', (error) {});

    _socket.on('disconnect', (reason) {
      onDisconnected?.call();
    });

    _socket.io.on('reconnect_attempt', (val) {
      onReconnection?.call(val);
    });

    _socket.on('close', (data) {
      onClose?.call(data);
    });

    _socket.io.on('reconnect_failed', (_) {
      onClose?.call([
        {
          'reason': {
            'code': LeaveReason.websocketConnectionAttemptsExhausted.code,
            'message': LeaveReason.websocketConnectionAttemptsExhausted.message
          }
        }
      ]);
    });

    _socket.io.on(('reconnect'), (_) {});

    _socket.io.on('reconnect_error', (error) {});

    // socket.io delivers events synchronously inside its internal dispatch loop.
    // Wrapping each handler in scheduleMicrotask() returns control to that loop
    // immediately, so a slow onRequest callback cannot delay the next socket
    // event from being processed.
    _socket.on('newConsumer', (data) {
      if (data is List && data.isNotEmpty) {
        final firstItem = data.first;
        final ack = data.last is Function ? data.last as Function : null;
        scheduleMicrotask(() => onRequest?.call(
              firstItem,
              (responseData) {
                _socket.emit('response', {
                  'id': firstItem['id'],
                  'ok': true,
                  'data': responseData,
                });
                ack?.call("");
              },
              (errorCode, errorReason) {
                _socket.emit('response', {
                  'id': firstItem['id'],
                  'ok': false,
                  'errorCode': errorCode,
                  'errorReason': errorReason,
                });
                ack?.call("");
              },
            ));
      }
    });

    _socket.on('enableMic', (data) {
      if (data is List && data.isNotEmpty) {
        final firstItem = data.first;
        final ack = data.last is Function ? data.last as Function : null;
        scheduleMicrotask(() => onRequest?.call(
              firstItem,
              (responseData) {
                _socket.emit('response', {
                  'id': firstItem['id'],
                  'ok': true,
                  'data': responseData,
                });
                ack?.call("");
              },
              (errorCode, errorReason) {
                _socket.emit('response', {
                  'id': firstItem['id'],
                  'ok': false,
                  'errorCode': errorCode,
                  'errorReason': errorReason,
                });
                ack?.call("");
              },
            ));
      }
    });

    _socket.on('disableMic', (data) {
      if (data is List && data.isNotEmpty) {
        final firstItem = data.first;
        final ack = data.last is Function ? data.last as Function : null;
        scheduleMicrotask(() => onRequest?.call(
              firstItem,
              (responseData) {
                _socket.emit('response', {
                  'id': firstItem['id'],
                  'ok': true,
                  'data': responseData,
                });
                ack?.call("");
              },
              (errorCode, errorReason) {
                _socket.emit('response', {
                  'id': firstItem['id'],
                  'ok': false,
                  'errorCode': errorCode,
                  'errorReason': errorReason,
                });
                ack?.call("");
              },
            ));
      }
    });

    _socket.on('enableWebcam', (data) {
      if (data is List && data.isNotEmpty) {
        final firstItem = data.first;
        final ack = data.last is Function ? data.last as Function : null;
        scheduleMicrotask(() => onRequest?.call(
              firstItem,
              (responseData) {
                _socket.emit('response', {
                  'id': firstItem['id'],
                  'ok': true,
                  'data': responseData,
                });
                ack?.call("");
              },
              (errorCode, errorReason) {
                _socket.emit('response', {
                  'id': firstItem['id'],
                  'ok': false,
                  'errorCode': errorCode,
                  'errorReason': errorReason,
                });
                ack?.call("");
              },
            ));
      }
    });

    _socket.on('disableWebcam', (data) {
      if (data is List && data.isNotEmpty) {
        final firstItem = data.first;
        final ack = data.last is Function ? data.last as Function : null;
        scheduleMicrotask(() => onRequest?.call(
              firstItem,
              (responseData) {
                _socket.emit('response', {
                  'id': firstItem['id'],
                  'ok': true,
                  'data': responseData,
                });
                ack?.call("");
              },
              (errorCode, errorReason) {
                _socket.emit('response', {
                  'id': firstItem['id'],
                  'ok': false,
                  'errorCode': errorCode,
                  'errorReason': errorReason,
                });
                ack?.call("");
              },
            ));
      }
    });

    _socket.on('statsData', (data) {
      if (data is List && data.isNotEmpty) {
        final firstItem = data.first;
        final ack = data.last is Function ? data.last as Function : null;
        scheduleMicrotask(() => onRequest?.call(
              firstItem,
              (responseData) {
                _socket.emit('response', {
                  'id': firstItem['id'],
                  'ok': true,
                  'data': responseData,
                });
                ack?.call(responseData);
              },
              (errorCode, errorReason) {
                _socket.emit('response', {
                  'id': firstItem['id'],
                  'ok': false,
                  'errorCode': errorCode,
                  'errorReason': errorReason,
                });
                ack?.call("");
              },
            ));
      }
    });

    _socket.on('pinStateChanged', (data) {
      if (data is List && data.isNotEmpty) {
        final firstItem = data.first;
        final ack = data.last is Function ? data.last as Function : null;
        scheduleMicrotask(() => onRequest?.call(
              firstItem,
              (responseData) {
                _socket.emit('response', {
                  'id': firstItem['id'],
                  'ok': true,
                  'data': responseData,
                });
                ack?.call("");
              },
              (errorCode, errorReason) {
                _socket.emit('response', {
                  'id': firstItem['id'],
                  'ok': false,
                  'errorCode': errorCode,
                  'errorReason': errorReason,
                });
                ack?.call("");
              },
            ));
      }
    });

    _socket.on('notification', (data) {
      scheduleMicrotask(() => onNotification?.call(data));
    });
  }

  Future<dynamic> sendRequest(String method, dynamic data) {
    final request = {
      'method': method,
      'data': data,
    };
    final completer = Completer<dynamic>();

    _socket.emitWithAck('request', request, ack: (response) {
      if (response == null) {
        completer.completeError("No response received");
        return;
      }

      if (response['data']['status'] != 'error') {
        completer.complete(response['data']);
      } else {
        if (response['data']['errorReason'] != null) {
          _eventEmitter.emit(
            'error',
            response['data']['errorCode'],
            response['data']['errorReason'],
          );

          completer.completeError(
              response['data']['errorReason']); // Complete with error
        } else {
          final errorMessage = response['data']['message'] ?? "Unknown Error";
          _eventEmitter.emit(
            'error',
            response['data']['errorCode'],
            errorMessage,
          );

          completer.completeError(errorMessage);
        }
      }
    });

    return completer.future;
  }

  // Future<dynamic> sendRequest(String method, dynamic data,
  //     {int timeoutMs = 30000}) {
  //   final request = {
  //     'method': method,
  //     'data': data,
  //   };
  //   final completer = Completer<dynamic>();
  //   Timer? timeoutTimer;

  //   final startTime = DateTime.now();

  //   if (method == 'pubsubPublish') {
  //     timeoutTimer = Timer(Duration(milliseconds: timeoutMs), () {
  //       if (!completer.isCompleted) {
  //         completer.completeError(
  //             "Message publishing timed out. Please check your network connection and try again.");
  //       }
  //     });
  //   }

  //   _socket.emitWithAck('request', request, ack: (response) {
  //     timeoutTimer?.cancel();

  //     final elapsed = DateTime.now().difference(startTime).inMilliseconds;

  //     if (completer.isCompleted) {
  //       log('Ack received after timeout (${elapsed}ms). Ignoring late response.');
  //       return;
  //     }

  //     if (response == null) {
  //       completer.completeError("No response received");
  //       return;
  //     }

  //     if (response['data'] != null && response['data']['status'] != 'error') {
  //       completer.complete(response['data']);
  //     } else {
  //       _eventEmitter.emit(
  //         'error',
  //         response['data']?['errorCode'],
  //         response['data']?['errorReason'],
  //       );
  //       log("Error: ${response['data']?['errorReason']}");
  //       completer
  //           .completeError(response['data']?['errorReason'] ?? "Unknown error");
  //     }
  //   });

  //   return completer.future;
  // }

  void sendNotification(String method, dynamic data) {
    final notification = {
      'method': method,
      'data': data,
    };
    _socket.emit('notification', notification);
  }

  void close() {
    _socket.close();
  }
}
