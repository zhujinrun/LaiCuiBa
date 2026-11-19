/// Asset keys for the files carried over from the original bundle.
///
/// Keeping them here stops string literals from spreading through the UI layer
/// and makes a rename or a "replace the artwork" pass a single-file edit.
///
/// Provenance: everything under `assets/` except `assets/fonts/` was extracted
/// verbatim from `data/flutter_assets/` of the original 1.0.6 Windows build.
abstract final class LcbAssets {
  // Icon packs. `icons.json` is the manifest that groups the webp files.
  static const iconManifest = 'assets/app_icons/icons.json';
  static String icon(String id) => 'assets/app_icons/$id.webp';

  // Localisation. The original ships Chinese as the source language, so there
  // is no zh.json: `strings` keys are the Chinese text itself.
  static const i18nDir = 'assets/i18n';
  static const s2tTable = 'assets/i18n/s2t.txt';
  static String i18n(String locale) => '$i18nDir/$locale.json';

  // Lookup data.
  static const pinyin = 'assets/pinyin.txt';
  static const torrentTrackers = 'assets/torrent_trackers.txt';

  // Visual assets.
  static const anime4k = 'assets/shaders/Anime4K_Upscale_CNN_x2_S.glsl';
  static const tvBackground = 'assets/tv/bg.jpg';
  static const loadingLunyi = 'assets/loading/lunyi.webp';

  // Widget showcase samples, used by the desktop-widget picker.
  static const widgetSamples = 'assets/widget_samples/samples.json';

  /// Locales the original translated into. Chinese is the source language and
  /// therefore has no file of its own.
  static const translatedLocales = ['en', 'es', 'it', 'ja', 'ru'];
}
