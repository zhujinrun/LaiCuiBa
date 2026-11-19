import 'package:flutter/widgets.dart';

import '../services/store.dart';

/// Exposes the [AppStore] down the widget tree via an [InheritedNotifier],
/// so any page can read it and rebuild on changes without pulling in a
/// third-party state-management package.
class StoreScope extends InheritedNotifier<AppStore> {
  const StoreScope({
    super.key,
    required AppStore store,
    required super.child,
  }) : super(notifier: store);

  static AppStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StoreScope>();
    assert(scope != null, 'StoreScope not found in the widget tree');
    return scope!.notifier!;
  }
}
