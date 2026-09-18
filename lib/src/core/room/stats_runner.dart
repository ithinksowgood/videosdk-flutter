// Selects the correct stats runner at compile time.
// On web (dart4web) Isolate.run is unavailable, so the computation runs
// directly on the calling isolate. On native it runs in a background isolate.
export 'stats_runner_stub.dart'
    if (dart.library.isolate) 'stats_runner_native.dart';
