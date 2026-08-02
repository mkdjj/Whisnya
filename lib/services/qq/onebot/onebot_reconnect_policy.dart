class OneBotReconnectPolicy {
  static const _delays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
  ];

  var _attempt = 0;

  Duration nextDelay() {
    final index = _attempt.clamp(0, _delays.length - 1);
    _attempt++;
    return _delays[index];
  }

  void reset() => _attempt = 0;
}
