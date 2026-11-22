import 'package:flutter/widgets.dart';

import '../models/models.dart';

/// Lets any page ask the shell to start playing a card.
///
/// The player is owned by the shell (it needs the store, the session keys and
/// the resume point in one place), so a hero's 播放 button cannot open it
/// itself. Without this the button existed and did nothing.
class LcbPlayScope extends InheritedWidget {
  const LcbPlayScope({super.key, required this.play, required super.child});

  /// Starts playback for [item], resolving its full record first.
  final void Function(MediaItem item) play;

  static LcbPlayScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LcbPlayScope>();

  /// No-op when no shell is above (widget tests that render a page alone).
  static void playOf(BuildContext context, MediaItem item) =>
      maybeOf(context)?.play(item);

  @override
  bool updateShouldNotify(LcbPlayScope oldWidget) => play != oldWidget.play;
}

/// Lets a page switch the sidebar's page (home → 历史, and back).
class LcbNavScope extends InheritedWidget {
  const LcbNavScope({super.key, required this.openPage, required super.child});

  final void Function(LcbPage page) openPage;

  static LcbNavScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LcbNavScope>();

  static void openOf(BuildContext context, LcbPage page) =>
      maybeOf(context)?.openPage(page);

  @override
  bool updateShouldNotify(LcbNavScope oldWidget) =>
      openPage != oldWidget.openPage;
}

/// Lets a rail's 「查看全部」open the category grid, and the browse panel hand
/// its picks to the same grid.
///
/// Opening is refused when there is no category id: a mount's 影片库 is not a
/// site category, and inventing an id for it would ask the source for
/// something that does not exist.
class LcbGridScope extends InheritedWidget {
  const LcbGridScope({super.key, required this.open, required super.child});

  final void Function(
    String title,
    String typeId,
    Map<String, String> filters,
  )
  open;

  static LcbGridScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LcbGridScope>();

  static void openOf(
    BuildContext context,
    String? title,
    String? typeId, {
    Map<String, String> filters = const {},
  }) {
    if (title == null || typeId == null || typeId.isEmpty) return;
    maybeOf(context)?.open(title, typeId, filters);
  }

  @override
  bool updateShouldNotify(LcbGridScope oldWidget) => open != oldWidget.open;
}
