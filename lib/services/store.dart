import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Application-wide persistent state: watch history (which also carries the
/// favourites/following flags), the source list and the active source. This is
/// the Phase-1 store that replaces the hard-coded fixtures; the on-disk format
/// mirrors the original's `shared_preferences` keys so behaviour stays
/// comparable frame by frame.
class AppStore extends ChangeNotifier {
  AppStore._(this._prefs, this._history, this._sources, this._current);

  final SharedPreferences _prefs;

  final List<HistoryEntry> _history;
  final List<SourceInfo> _sources;
  final String? _current;

  /// Active favourites sub-tab (0 = 收藏, 1 = 追剧). Kept here so the header
  /// tabs and the body stay in sync without threading a controller through.
  int favoritesTab = 0;

  static const _kHistory = 'flutter.history';
  static const _kSources = 'flutter.sources';
  static const _kCurrent = 'flutter.current';

  // -------------------------------------------------------------------------
  // Load
  // -------------------------------------------------------------------------

  /// Loads persisted state. Call once before `runApp`.
  static Future<AppStore> load() async {
    final prefs = await SharedPreferences.getInstance();

    final history = _decodeList(prefs.getString(_kHistory), HistoryEntry.fromJson);
    final sources = _decodeList(prefs.getString(_kSources), SourceInfo.fromJson);

    var current = prefs.getString(_kCurrent);
    if (current != null && current.length >= 2 && current.startsWith('"')) {
      current = jsonDecode(current) as String;
    }

    // Seed a single demo source + one history entry on first launch so the
    // rebuilt pages stay frame-comparable with the original's live session.
    if (sources.isEmpty) {
      sources.add(_demoSource());
    }
    if (history.isEmpty) {
      history.add(_demoHistoryEntry(sources.first.id, sources.first.name));
    }

    // Fall back to the first source so the resources page has a card to show.
    if (current == null || current.isEmpty) {
      current = sources.isNotEmpty ? sources.first.id : null;
    }

    return AppStore._(prefs, history, sources, current);
  }

  static List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null || raw.isEmpty) return <T>[];
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => fromJson((e as Map).cast<String, dynamic>()))
        .toList();
  }

  // -------------------------------------------------------------------------
  // History / favourites
  // -------------------------------------------------------------------------

  List<HistoryEntry> get history => List.unmodifiable(_history);

  List<HistoryEntry> get favorites =>
      _history.where((e) => e.isFavorite).toList();

  List<HistoryEntry> get following =>
      _history.where((e) => e.isFollowing).toList();

  void setFavoritesTab(int tab) {
    if (tab == favoritesTab) return;
    favoritesTab = tab;
    notifyListeners();
  }

  Future<void> toggleFavorite(String key) async {
    final i = _history.indexWhere((e) => e.key == key);
    if (i < 0) return;
    _history[i] = _history[i].copyWith(isFavorite: !_history[i].isFavorite);
    await _persistHistory();
    notifyListeners();
  }

  Future<void> toggleFollowing(String key) async {
    final i = _history.indexWhere((e) => e.key == key);
    if (i < 0) return;
    _history[i] = _history[i].copyWith(isFollowing: !_history[i].isFollowing);
    await _persistHistory();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history.clear();
    await _persistHistory();
    notifyListeners();
  }

  /// Upserts a history entry (the original records one row per watch).
  Future<void> putHistory(HistoryEntry entry) async {
    final i = _history.indexWhere((e) => e.key == entry.key);
    if (i >= 0) {
      _history[i] = entry;
    } else {
      _history.insert(0, entry);
    }
    await _persistHistory();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Sources
  // -------------------------------------------------------------------------

  List<SourceInfo> get sources => List.unmodifiable(_sources);

  String? get currentSourceId => _current;

  SourceInfo? get currentSource {
    for (final s in _sources) {
      if (s.id == _current) return s;
    }
    return _sources.isNotEmpty ? _sources.first : null;
  }

  // -------------------------------------------------------------------------
  // Persistence helpers
  // -------------------------------------------------------------------------

  Future<void> _persistHistory() async {
    await _prefs.setString(
      _kHistory,
      jsonEncode(_history.map((e) => e.toJson()).toList()),
    );
  }

  static SourceInfo _demoSource() => const SourceInfo(
        id: '1794457036493149',
        type: 'tvbox',
        name: '豆儿猫源',
        url: 'https://gh-proxy.com/raw.githubusercontent.com/Darklessing/catvod/refs/heads/main/douer/index.js.md5',
        latencyMs: 5000,
        movieCount: 58,
        showCount: 1,
      );

  static HistoryEntry _demoHistoryEntry(String sourceId, String sourceName) =>
      HistoryEntry(
        key: '$sourceId|nodejs_jianpian|575857',
        sourceId: sourceId,
        title: '尚公主',
        poster: 'assets/demo/cont0.webp',
        episode: '第39集',
        episodeIndex: 38,
        positionMs: 31840,
        durationMs: 2905400,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        siteKey: 'nodejs_jianpian',
        vodId: '575857',
        flag: 'LZ线路',
        sourceName: sourceName,
      );
}
