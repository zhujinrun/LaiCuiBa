import 'dart:convert';

import '../models/models.dart';

/// Turns a TVBox / catvod config document into the site list a source carries.
///
/// This is pure local parsing -- no network, no spider, no runtime. That matters
/// because it is the only part of "adding a source" that can be made genuinely
/// real today: the original pulls the same JSON over HTTP, but the shape it
/// parses is exactly what a user can paste in by hand or import from a file.
///
/// Accepted inputs:
///   * a full config object        `{"sites": [ ... ], "lives": [ ... ]}`
///   * a bare site array           `[{ "key": "x", "name": "x", ... }]`
///   * one site per line, JSON     `{"key":"x","name":"x","api":"..."}`
///   * one site per line, `$` form `站点名$https://example.com/api.php$ext`
///
/// Everything else (a URL, an empty paste) comes back as a [SiteParseFailure]
/// so the caller can say what went wrong instead of silently storing nothing.
class SiteParseResult {
  const SiteParseResult({
    required this.sites,
    this.silenced = 0,
    this.invalid = 0,
    this.error,
  });

  const SiteParseResult.failure(String message)
    : sites = const [],
      silenced = 0,
      invalid = 0,
      error = message;

  final List<SiteInfo> sites;

  /// Entries that declared `searchable: 0`. They are kept in [sites] with
  /// [SiteInfo.enabled] false so the editor can switch them back on, and
  /// counted here so the UI can explain a chip row shorter than the file.
  final int silenced;

  /// Entries that carried no usable name and were dropped.
  final int invalid;

  /// Non-null when nothing could be parsed.
  final String? error;

  bool get ok => error == null;
  int get count => sites.length;
  int get enabledCount => sites.where((site) => site.enabled).length;
}

/// Keys the various TVBox forks use for the same concept, most specific first.
const _nameKeys = ['name', 'title', 'siteName', 'show'];

/// Parses [raw] into sites. Never throws.
SiteParseResult parseConfig(String raw) {
  var text = raw.trim();
  if (text.isEmpty) {
    return const SiteParseResult.failure('配置为空');
  }
  // Windows clipboard and imported .json files both arrive with a BOM often
  // enough that stripping it is cheaper than debugging it later.
  if (text.codeUnitAt(0) == 0xFEFF) text = text.substring(1);
  if (text.isEmpty) {
    return const SiteParseResult.failure('配置为空');
  }

  // A URL is the most common mistake: the field wants the document, not its
  // address. Say so instead of reporting invalid JSON.
  final lower = text.toLowerCase();
  if (!lower.startsWith('{') && !lower.startsWith('[') &&
      (lower.startsWith('http://') || lower.startsWith('https://'))) {
    return const SiteParseResult.failure('这是网址，不是配置内容');
  }

  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return _parseLines(text);
  }

  return _fromDecoded(decoded);
}

/// Handles both real JSON and the `name$api$ext` one-per-line shorthand.
SiteParseResult _parseLines(String text) {
  final sites = <SiteInfo>[];
  var skipped = 0;
  for (final line in const LineSplitter().convert(text)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final one = jsonDecode(trimmed);
        final parsed = _siteFromMap(one);
        if (parsed == null) {
          skipped++;
        } else {
          sites.add(parsed);
        }
        continue;
      } on FormatException {
        // fall through to the $-form check
      }
    }

    final parts = trimmed.split(r'$');
    if (parts.length >= 2 && parts.first.trim().isNotEmpty) {
      final name = parts[0].trim();
      final api = parts[1].trim();
      if (api.isEmpty) {
        skipped++;
        continue;
      }
      sites.add(
        SiteInfo(
          key: _slug(name),
          name: name,
          api: api,
          ext: parts.length > 2 ? parts[2].trim() : '',
        ),
      );
      continue;
    }
    skipped++;
  }

  if (sites.isEmpty) {
    return const SiteParseResult.failure('不是合法的 JSON 或站点定义');
  }
  return SiteParseResult(sites: sites, invalid: skipped);
}

SiteParseResult _fromDecoded(Object? decoded) {
  if (decoded is List) {
    return _collect(decoded);
  }
  if (decoded is Map) {
    final map = Map<String, dynamic>.from(decoded);
    final sites = map['sites'];
    if (sites is List) {
      final result = _collect(sites);
      if (result.sites.isNotEmpty || result.invalid > 0) {
        return result;
      }
    }

    // Some forks wrap the real document one level down (`{"config": {...}}`),
    // and a multi-repo config points at further documents we cannot fetch here.
    for (final nested in ['config', 'data', 'result']) {
      final inner = map[nested];
      if (inner is Map) {
        final sub = Map<String, dynamic>.from(inner);
        if (sub['sites'] is List) {
          final result = _collect(sub['sites'] as List);
          if (result.sites.isNotEmpty) return result;
        }
      }
    }

    if ((sites is! List) && map.containsKey('urls')) {
      return const SiteParseResult.failure('这是多仓聚合地址，请贴单个仓库的配置');
    }

    // A single site object pasted on its own.
    final single = _siteFromMap(map);
    if (single != null) {
      return SiteParseResult(sites: [single]);
    }
    return const SiteParseResult.failure('配置里没有找到站点列表');
  }
  return const SiteParseResult.failure('不是合法的 JSON 或站点定义');
}

SiteParseResult _collect(List raw) {
  final sites = <SiteInfo>[];
  final seen = <String>{};
  var invalid = 0;
  var silenced = 0;
  for (final entry in raw) {
    final site = _siteFromMap(entry);
    if (site == null) {
      invalid++;
      continue;
    }
    // catvod requires keys to be unique; a config with duplicates would show
    // two identical chips and count the same rows twice.
    if (!seen.add(site.key)) {
      invalid++;
      continue;
    }
    if (!site.enabled) silenced++;
    sites.add(site);
  }
  if (sites.isEmpty) {
    return SiteParseResult(
      sites: const [],
      invalid: invalid,
      error: raw.isEmpty ? '配置里的站点列表是空的' : '站点条目都缺少名称',
    );
  }
  return SiteParseResult(sites: sites, silenced: silenced, invalid: invalid);
}

/// Reads one config entry, or null when it carries no usable name.
SiteInfo? _siteFromMap(Object? entry) {
  if (entry is! Map) return null;
  final map = Map<String, dynamic>.from(entry);

  final name = _firstString(map, _nameKeys);
  final key = _firstString(map, const ['key', 'id']);
  if (name == null && key == null) return null;
  final display = name ?? key!;

  // `searchable: 0` means "not in search" in catvod; such sites still appear in
  // the config, they just never answer a query. Dropping them here keeps the
  // chip row honest, and the count is reported so nothing vanishes silently.
  final searchable = map['searchable'];
  final isSearchable = searchable == null || searchable == true || '$searchable' != '0';
  if (!isSearchable) {
    return SiteInfo(
      key: key ?? _slug(display),
      name: display,
      type: '${map['type'] ?? ''}',
      api: '${map['api'] ?? ''}',
      ext: '${map['ext'] ?? ''}',
      enabled: false,
    );
  }

  return SiteInfo(
    key: key ?? _slug(display),
    name: display,
    type: '${map['type'] ?? ''}',
    api: '${map['api'] ?? ''}',
    ext: '${map['ext'] ?? ''}',
  );
}

String? _firstString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

/// Stable, ASCII-safe key for entries that only carry a display name.
String _slug(String value) {
  final buffer = StringBuffer();
  for (final rune in value.runes) {
    if (_isAsciiWord(rune)) {
      buffer.writeCharCode(rune);
    } else {
      // Non-ASCII names would collide once stripped, so encode the code unit.
      buffer.write('u${rune.toRadixString(16)}');
    }
  }
  return buffer.isEmpty ? 'site' : buffer.toString();
}

bool _isAsciiWord(int rune) =>
    (rune >= 0x30 && rune <= 0x39) ||
    (rune >= 0x41 && rune <= 0x5A) ||
    (rune >= 0x61 && rune <= 0x7A) ||
    rune == 0x5F;
