import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// One entry of the bundled 图标包 (`assets/app_icons/icons.json`).
///
/// The original ships the same pack and offers it as 原版「更换图标 → 内置图标」.
/// Ids are the file stems, so the asset path is derived rather than stored.
class AppIcon {
  const AppIcon({required this.id, required this.name, required this.group});

  final String id;
  final String name;

  /// The pack's own grouping (BieCuiLe / 线条 / 团子 / 水彩), kept as-is so the
  /// picker can draw the same sections the original does.
  final String group;

  String get assetPath => 'assets/app_icons/$id.webp';
}

List<AppIcon>? _cache;

/// Loads and caches the bundled pack. A broken or missing manifest yields an
/// empty list rather than throwing: a picker with nothing to show is a visible
/// problem, an exception on page build is not.
Future<List<AppIcon>> loadAppIcons() async {
  final cached = _cache;
  if (cached != null) return cached;
  try {
    final raw = await rootBundle.loadString('assets/app_icons/icons.json');
    final data = jsonDecode(raw);
    final icons = <AppIcon>[
      for (final entry in (data['icons'] as List? ?? const []))
        if (entry is Map)
          AppIcon(
            id: entry['id'] as String? ?? '',
            name: entry['name'] as String? ?? '',
            group: entry['group'] as String? ?? '',
          ),
    ]..removeWhere((icon) => icon.id.isEmpty);
    _cache = icons;
    return icons;
  } on Object {
    _cache = const [];
    return const [];
  }
}

/// Groups icons by the pack's own sections, preserving the manifest order.
Map<String, List<AppIcon>> groupAppIcons(List<AppIcon> icons) {
  final groups = <String, List<AppIcon>>{};
  for (final icon in icons) {
    groups.putIfAbsent(icon.group.isEmpty ? '图标' : icon.group, () => []).add(icon);
  }
  return groups;
}
