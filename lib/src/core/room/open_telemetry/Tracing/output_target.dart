enum OutputTarget {
  toConsole(1 << 0),
  toClientConsole(1 << 1),
  toTelemetry(1 << 2),
  toInspector(1 << 3),
  toBackend(1 << 4),
  none(0);

  final int rawValue;
  const OutputTarget(this.rawValue);

  static int mask(List<OutputTarget> targets) {
    var m = 0;
    for (final t in targets) {
      m |= t.rawValue;
    }
    return m;
  }
}
