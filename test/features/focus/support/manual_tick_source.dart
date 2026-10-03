import 'dart:async';

import 'package:self_improvement/features/focus/application/focus_countdown.dart';

/// A deterministic [FocusTickSource]: the test pushes the monotonic readings,
/// nothing ever sleeps for real.
final class ManualTickSource implements FocusTickSource {
  StreamController<Duration>? _current;
  var _active = 0;

  /// How many measurements (foreground phases) were started so far.
  int phasesStarted = 0;

  /// Called whenever a new measurement starts (the countdown began a phase).
  void Function()? onStart;

  /// How many measurements are currently listened to.
  int get activeSubscriptions => _active;

  @override
  Stream<Duration> ticks() {
    phasesStarted++;
    onStart?.call();
    late final StreamController<Duration> controller;
    controller = StreamController<Duration>(
      sync: true,
      onListen: () => _active++,
      onCancel: () {
        _active--;
        return controller.close();
      },
    );
    _current = controller;
    return controller.stream;
  }

  /// Delivers the monotonic reading [monotonic] to the newest measurement, if
  /// something still listens to it.
  void emit(Duration monotonic) {
    final controller = _current;
    if (controller != null && controller.hasListener) {
      controller.add(monotonic);
    }
  }

  /// [emit] with whole [seconds].
  void emitSeconds(int seconds) => emit(Duration(seconds: seconds));

  /// Closes the newest measurement (like a stopped ticker).
  Future<void> close() async {
    final controller = _current;
    _current = null;
    await controller?.close();
  }
}

/// Lets pending microtasks and zero-duration timers run (database streams,
/// provider updates). Deterministic: no real waiting.
Future<void> settle([int turns = 10]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
