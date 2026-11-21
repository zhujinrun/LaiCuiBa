import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Holds the machine awake while something is playing.
///
/// Split from the plugin call so the player can be exercised without a platform
/// channel: a test hands in a fake and asserts the hold/release pattern instead
/// of the widget tree.
abstract class Awake {
  /// Keeps the display (and the system) from going to sleep.
  Future<void> hold();

  /// Gives up one hold. Idempotent once the count reaches zero.
  Future<void> release();
}

/// [Awake] over `wakelock_plus`, which on Windows is a single
/// `SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED)` call.
///
/// Counting is not incidental. Switching episodes mounts the next player before
/// the previous one is disposed, so a `bool` would run enable → disable in that
/// order and hand back a sleeping screen for the episode that just started.
/// The shell shares one instance across players for exactly that reason.
class SystemAwake implements Awake {
  SystemAwake({Future<void> Function(bool on)? toggle})
    : _toggle = toggle ?? _platformToggle;

  final Future<void> Function(bool on) _toggle;

  int _holders = 0;

  static Future<void> _platformToggle(bool on) =>
      on ? WakelockPlus.enable() : WakelockPlus.disable();

  /// How many holders there are, for tests and for the diagnostics line.
  @visibleForTesting
  int get holders => _holders;

  @override
  Future<void> hold() async {
    _holders++;
    if (_holders == 1) await _apply(true);
  }

  @override
  Future<void> release() async {
    if (_holders == 0) return;
    _holders--;
    if (_holders == 0) await _apply(false);
  }

  /// A missing platform implementation must not take the player down with it:
  /// failing to hold the lock only means the screen may sleep.
  Future<void> _apply(bool on) async {
    try {
      await _toggle(on);
    } catch (e) {
      debugPrint('LcbAwake: ${on ? 'hold' : 'release'} failed: $e');
    }
  }
}
