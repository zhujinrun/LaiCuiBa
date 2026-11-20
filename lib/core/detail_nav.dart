import 'package:flutter/widgets.dart';

import '../models/models.dart';

/// Lets any page ask the shell to push the detail page.
///
/// The detail page lives in the content column (the sidebar stays visible), so
/// it is not a `Navigator` route — the shell owns the transition and this scope
/// exposes it downwards without threading callbacks through every page.
class LcbDetailScope extends InheritedWidget {
  const LcbDetailScope({super.key, required this.open, required super.child});

  final void Function(MediaItem item, {int? episodeIndex}) open;

  static LcbDetailScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LcbDetailScope>();

  /// Opens the detail page for [item]; no-op when no shell is above (tests).
  static void openOf(
    BuildContext context,
    MediaItem item, {
    int? episodeIndex,
  }) {
    maybeOf(context)?.open(item, episodeIndex: episodeIndex);
  }

  @override
  bool updateShouldNotify(LcbDetailScope oldWidget) => open != oldWidget.open;
}
