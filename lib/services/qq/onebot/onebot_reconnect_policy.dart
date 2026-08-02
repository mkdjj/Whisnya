class OneBotReconnectPolicy {
  OneBotReconnectPolicy({List<Duration>? delays})
    : delays = delays ?? defaultDelays,
      assert(delays == null || delays.isNotEmpty);

  static const defaultDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  final List<Duration> delays;
  var _attempt = 0;

  Duration nextDelay() {
    final index = _attempt.clamp(0, delays.length - 1);
    _attempt++;
    return delays[index];
  }

  void reset() => _attempt = 0;
}
