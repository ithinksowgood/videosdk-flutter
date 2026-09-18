// Web fallback — dart:isolate is unavailable on dart4web so the computation
// runs synchronously on the calling isolate (main thread).
//
// NOTE: This means RTT, producer, and consumer stats are computed on the main
// thread on web. For small meetings this is negligible. For large meetings
// (20+ participants) the consumer-stats loop may cause visible jank on
// low-end devices. A Web Worker solution would be needed to fix this fully.
Future<T> runComputation<T>(T Function() computation) async {
  return computation();
}
