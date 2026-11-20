import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Application-wide persistent state: watch history, favourites (in their own
/// store, matching the original's `flutter.favorites` + `flutter.favoriteFolders`),
/// the source list and the active source. The on-disk format mirrors the
/// original's `shared_preferences` keys so behaviour stays comparable.
class AppStore extends ChangeNotifier {
  AppStore._(
    this._prefs,
    this._history,
    this._favorites,
    this._favoriteFolders,
    this._sources,
    this._current,
    this._settings,
  );

  final SharedPreferences _prefs;

  final List<HistoryEntry> _history;
  final List<FavoriteEntry> _favorites;
  final List<FavoriteFolder> _favoriteFolders;
  final List<SourceInfo> _sources;
  String? _current;
  AppSettings _settings;

  /// Active favourites sub-tab (0 = 收藏, 1 = 追剧). Kept here so the header
  /// tabs and the body stay in sync without threading a controller through.
  int favoritesTab = 0;

  /// Selected favourite folder; null = "全部". Persisted so the filter survives
  /// navigation.
  String? favoriteFolderId;

  // shared_preferences (Windows/Linux) auto-prefixes every key with "flutter.",
  // so these bare keys land at `flutter.history`, `flutter.favorites`, etc. —
  // exactly matching the original's shared_preferences.json layout.
  static const _kHistory = 'history';
  static const _kFavorites = 'favorites';
  static const _kFavoriteFolders = 'favoriteFolders';
  static const _kSources = 'sources';
  static const _kCurrent = 'current';
  static const _kSettings = 'settings';
  static const _kSeeded = 'seeded';

  // -------------------------------------------------------------------------
  // Load
  // -------------------------------------------------------------------------

  /// Loads persisted state. Call once before `runApp`.
  static Future<AppStore> load() async {
    final prefs = await SharedPreferences.getInstance();

    final history = _decodeList(
      prefs.getString(_kHistory),
      HistoryEntry.fromJson,
    );
    final favorites = _decodeList(
      prefs.getString(_kFavorites),
      FavoriteEntry.fromJson,
    );
    final folders = _decodeList(
      prefs.getString(_kFavoriteFolders),
      FavoriteFolder.fromJson,
    );
    final sources = _decodeList(
      prefs.getString(_kSources),
      SourceInfo.fromJson,
    );

    var current = prefs.getString(_kCurrent);
    if (current != null && current.length >= 2 && current.startsWith('"')) {
      current = jsonDecode(current) as String;
    }

    var settings = AppSettings.fromJson(
      _decodeMap(prefs.getString(_kSettings)),
    );

    // Seed demo data only on the true first launch, tracked by an explicit
    // flag. Seeding on "list is empty" would resurrect demo rows after the
    // user clears their history/favourites, so the flag is authoritative.
    final isFirstLaunch = !(prefs.getBool(_kSeeded) ?? false);
    if (isFirstLaunch) {
      if (sources.isEmpty) {
        sources.add(_demoSource());
      }
      if (history.isEmpty) {
        history.add(_demoHistoryEntry(sources.first.id, sources.first.name));
      }
      if (folders.isEmpty) {
        folders.add(_demoFolder());
      }
      if (favorites.isEmpty) {
        favorites.add(_demoFavorite(folders.first.id));
      }
      // Persist the seeded demo rows so a relaunch does not lose them (the
      // flag alone would skip seeding while the lists were never written).
      await prefs.setString(
        _kSources,
        jsonEncode(sources.map((e) => e.toJson()).toList()),
      );
      await prefs.setString(
        _kHistory,
        jsonEncode(history.map((e) => e.toJson()).toList()),
      );
      await prefs.setString(
        _kFavoriteFolders,
        jsonEncode(folders.map((e) => e.toJson()).toList()),
      );
      await prefs.setString(
        _kFavorites,
        jsonEncode(favorites.map((e) => e.toJson()).toList()),
      );
      await prefs.setBool(_kSeeded, true);
    }

    // Fall back to the first source so the resources page has a card to show.
    if (current == null || current.isEmpty) {
      current = sources.isNotEmpty ? sources.first.id : null;
      if (current != null) {
        await prefs.setString(_kCurrent, jsonEncode(current));
      }
    }

    return AppStore._(
      prefs,
      history,
      favorites,
      folders,
      sources,
      current,
      settings,
    );
  }

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return const {};
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
  // History
  // -------------------------------------------------------------------------

  List<HistoryEntry> get history => List.unmodifiable(_history);

  /// The home "继续观看" rail, derived from watch history (most recent first).
  /// Ties the home feed to the same store the history page reads, so clearing
  /// history also empties the rail — the Phase 1 data-loop goal.
  List<ContinueWatching> get continueWatching => [
    for (final e in _history)
      ContinueWatching(
        media: MediaItem(
          id: e.key,
          title: e.title,
          image: e.poster.isEmpty ? null : e.poster,
          posterSeed: e.key.hashCode,
        ),
        episodeLabel: e.episode,
        positionMs: e.positionMs,
        durationMs: e.durationMs,
      ),
  ];

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

  /// Removes a single history entry by key. No-op if absent.
  Future<void> removeHistory(String key) async {
    final before = _history.length;
    _history.removeWhere((e) => e.key == key);
    if (_history.length == before) return;
    await _persistHistory();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Favourites (own store, matching flutter.favorites / flutter.favoriteFolders)
  // -------------------------------------------------------------------------

  List<FavoriteEntry> get favorites => List.unmodifiable(_favorites);

  List<FavoriteFolder> get favoriteFolders =>
      List.unmodifiable(_favoriteFolders);

  /// Favourites filtered by the selected folder (null = "全部").
  List<FavoriteEntry> get visibleFavorites {
    final id = favoriteFolderId;
    if (id == null) return favorites;
    return _favorites.where((e) => e.folderId == id).toList();
  }

  void setFavoritesTab(int tab) {
    if (tab == favoritesTab) return;
    favoritesTab = tab;
    notifyListeners();
  }

  void setFavoriteFolder(String? folderId) {
    if (folderId == favoriteFolderId) return;
    favoriteFolderId = folderId;
    notifyListeners();
  }

  /// Adds or removes a favourite. When removing, the whole entry is dropped
  /// (the original has no per-entry favourite flag — it is its own record).
  Future<void> toggleFavorite(FavoriteEntry entry) async {
    final i = _favorites.indexWhere((e) => e.key == entry.key);
    if (i >= 0) {
      _favorites.removeAt(i);
    } else {
      _favorites.insert(0, entry);
    }
    await _persistFavorites();
    notifyListeners();
  }

  /// Creates a folder and persists it. The id mirrors the original's
  /// 13-digit millisecond timestamp (e.g. `1795101875822513`).
  Future<void> createFavoriteFolder(String name) async {
    _favoriteFolders.add(
      FavoriteFolder(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
      ),
    );
    await _persistFolders();
    notifyListeners();
  }

  /// Renames a folder in place. No-op if the id is unknown.
  Future<void> renameFavoriteFolder(String id, String name) async {
    final i = _favoriteFolders.indexWhere((f) => f.id == id);
    if (i < 0) return;
    _favoriteFolders[i] = FavoriteFolder(id: id, name: name);
    await _persistFolders();
    notifyListeners();
  }

  /// Deletes a folder and returns its favourites to the uncategorised pool
  /// (folderId → null). The folder id stays valid on the surviving entries'
  /// other fields.
  Future<void> deleteFavoriteFolder(String id) async {
    _favoriteFolders.removeWhere((f) => f.id == id);
    for (var i = 0; i < _favorites.length; i++) {
      if (_favorites[i].folderId == id) {
        _favorites[i] = _favorites[i].copyWithFolder(null);
      }
    }
    // If the deleted folder was the active filter, reset to 全部.
    if (favoriteFolderId == id) {
      favoriteFolderId = null;
    }
    await _persistFolders();
    await _persistFavorites();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Settings
  // -------------------------------------------------------------------------

  AppSettings get settings => _settings;

  /// Updates a subset of settings and persists the whole map under
  /// `flutter.settings`, mirroring the original's flat JSON blob.
  Future<void> updateSettings(AppSettings next) async {
    _settings = next;
    await _persistSettings();
    notifyListeners();
  }

  Future<void> _persistSettings() async {
    await _prefs.setString(_kSettings, jsonEncode(_settings.toJson()));
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

  /// Switches the active source and persists the choice. The original stores
  /// the id JSON-quoted under `flutter.current`; we keep the raw string here
  /// and only quote it when it is read back from disk.
  Future<void> selectSource(String id) async {
    if (id == _current) return;
    _current = id;
    await _prefs.setString(_kCurrent, jsonEncode(id));
    notifyListeners();
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

  Future<void> _persistFavorites() async {
    await _prefs.setString(
      _kFavorites,
      jsonEncode(_favorites.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _persistFolders() async {
    await _prefs.setString(
      _kFavoriteFolders,
      jsonEncode(_favoriteFolders.map((e) => e.toJson()).toList()),
    );
  }

  static SourceInfo _demoSource() => const SourceInfo(
    id: '1794457036493149',
    type: 'tvbox',
    name: '豆儿猫源',
    url:
        'https://gh-proxy.com/raw.githubusercontent.com/Darklessing/catvod/refs/heads/main/douer/index.js.md5',
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

  static FavoriteFolder _demoFolder() =>
      const FavoriteFolder(id: '1795101875822513', name: '好看的电影');

  static FavoriteEntry _demoFavorite(String folderId) => FavoriteEntry(
    key: '1794457036493149|nodejs_jianpian|575252',
    sourceId: '1794457036493149',
    title: '欢迎来龙餐馆',
    poster: 'assets/demo/b0.jpg',
    siteKey: 'nodejs_jianpian',
    vodId: '575252',
    folderId: folderId,
    latest: '共 2 集',
    addedAt: 1795101878495,
  );
}
