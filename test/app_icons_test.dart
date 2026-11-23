import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/app_icons.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the bundled 图标包 loads and keeps its own grouping', () async {
    final icons = await loadAppIcons();

    expect(icons, isNotEmpty);
    // A known id from the pack, so a renamed file would show up here.
    expect(icons.any((icon) => icon.id == 'line_cat'), isTrue);
    // Derived, not stored: the manifest ids are the file stems.
    expect(
      icons.first.assetPath,
      'assets/app_icons/${icons.first.id}.webp',
    );

    final groups = groupAppIcons(icons);
    expect(groups.keys, contains('线条'));
    expect(
      groups.values.fold<int>(0, (sum, list) => sum + list.length),
      icons.length,
    );
  });

  test('a second load is served from the cache', () async {
    final first = await loadAppIcons();
    final second = await loadAppIcons();
    expect(identical(first, second), isTrue);
  });
}
