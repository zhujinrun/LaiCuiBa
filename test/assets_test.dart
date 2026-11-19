import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lai_cui_ba/core/assets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('asset bundle ships the extracted resources', () async {
    for (final key in [
      LcbAssets.iconManifest,
      LcbAssets.pinyin,
      LcbAssets.torrentTrackers,
      LcbAssets.anime4k,
      LcbAssets.tvBackground,
      LcbAssets.loadingLunyi,
      LcbAssets.s2tTable,
      LcbAssets.widgetSamples,
    ]) {
      final data = await rootBundle.load(key);
      expect(data.lengthInBytes, greaterThan(0), reason: 'empty asset: $key');
    }
  });

  test('icon manifest parses and every icon file exists', () async {
    final raw = await rootBundle.loadString(LcbAssets.iconManifest);
    final manifest = jsonDecode(raw) as Map<String, dynamic>;
    final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();

    expect(icons, isNotEmpty);
    for (final icon in icons) {
      final id = icon['id'] as String;
      final data = await rootBundle.load(LcbAssets.icon(id));
      expect(data.lengthInBytes, greaterThan(0), reason: 'missing icon: $id');
    }
  });

  test('localisation files share one key set', () async {
    Future<Set<String>> keysOf(String locale) async {
      final raw = await rootBundle.loadString(LcbAssets.i18n(locale));
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return (map['strings'] as Map<String, dynamic>).keys.toSet();
    }

    final base = await keysOf('en');
    expect(base.length, greaterThan(150));
    for (final locale in LcbAssets.translatedLocales.where((l) => l != 'en')) {
      final keys = await keysOf(locale);
      expect(
        keys.difference(base),
        isEmpty,
        reason: '$locale has keys absent from en.json',
      );
    }
  });
}
