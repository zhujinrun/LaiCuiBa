import 'package:flutter/widgets.dart';

/// Lets a page drive the shell's top bar.
///
/// The original's top bar is contextual: it shows the page title, plus a back
/// arrow on sub-pages (settings → 外观 renders `← 外观`). Pages therefore need
/// to own the title while the shell owns the chrome.
class LcbPageHeader extends ChangeNotifier {
  LcbPageHeader(this._title);

  String _title;
  VoidCallback? _onBack;

  String get title => _title;

  /// Non-null when the page is a sub-page and the bar should show a back arrow.
  VoidCallback? get onBack => _onBack;

  /// Shows a sub-page title with a back arrow.
  void push(String title, VoidCallback onBack) {
    if (_title == title && _onBack != null) return;
    _title = title;
    _onBack = onBack;
    notifyListeners();
  }

  /// Returns to a root-level title without a back arrow.
  void reset(String title) {
    if (_title == title && _onBack == null) return;
    _title = title;
    _onBack = null;
    notifyListeners();
  }

  void goBack() => _onBack?.call();
}

class LcbPageHeaderScope extends InheritedNotifier<LcbPageHeader> {
  const LcbPageHeaderScope({
    super.key,
    required LcbPageHeader controller,
    required super.child,
  }) : super(notifier: controller);

  static LcbPageHeader of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LcbPageHeaderScope>();
    assert(scope != null, 'LcbPageHeaderScope missing above this widget');
    return scope!.notifier!;
  }
}
