import 'package:flutter/material.dart';

/// Shows a progress message while [work] runs, then replaces it with the
/// result on every exit path -- success, exception, or an unmounted messenger.
///
/// The progress bar keeps a finite duration as a last-resort guarantee: a
/// probe that never returns must not leave a message pinned to the screen.
/// Finishing clears the whole queue with `clearSnackBars()` rather than
/// `hideCurrentSnackBar()`: any notification raised while [work] ran would push
/// the progress bar down the queue, and hiding only the head would let it
/// surface afterwards for its full duration.
Future<void> runProgressSnackBar(
  ScaffoldMessengerState messenger, {
  required String progress,
  required Future<String> Function() work,
  Duration progressDuration = const Duration(seconds: 60),
  Duration resultDuration = const Duration(seconds: 4),
  String Function(Object error)? onError,
}) async {
  // Drop anything left over from an earlier operation before showing ours, so
  // repeated taps cannot stack two long-lived progress bars in the queue.
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(content: Text(progress), duration: progressDuration),
  );

  late final String line;
  try {
    line = await work();
  } catch (error) {
    line = onError?.call(error) ?? '操作中断：$error';
  }

  if (!messenger.mounted) return;
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(content: Text(line), duration: resultDuration),
  );
}
