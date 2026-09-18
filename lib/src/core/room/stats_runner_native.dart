// Native implementation — offloads computation to a background Dart isolate.
import 'dart:isolate';

Future<T> runComputation<T>(T Function() computation) {
  return Isolate.run(computation);
}
