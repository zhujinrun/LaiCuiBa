/// Product identity in one place, so the name never drifts between the window
/// title, the title bar and the about row in settings.
abstract final class LcbAppInfo {
  /// Product name shown to users. Dart package names stay snake_case, so the
  /// display name is kept here rather than derived from `package:` metadata.
  static const name = 'LaiCuiBa';
  static const version = '0.1.3';
  static const build = 4;
}
