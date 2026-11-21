import 'dart:async';

/// Delays an action until calls stop for [delay] (e.g. search input).
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() => _timer?.cancel();

  void dispose() => cancel();
}

/// Guards an async action against concurrent re-entry (double taps,
/// repeated requests). While one call runs, further calls are ignored.
class SingleFlight {
  bool _running = false;

  bool get isRunning => _running;

  Future<T?> run<T>(Future<T> Function() action) async {
    if (_running) return null;
    _running = true;
    try {
      return await action();
    } finally {
      _running = false;
    }
  }
}
