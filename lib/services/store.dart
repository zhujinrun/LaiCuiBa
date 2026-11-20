import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'demo_data.dart' as demo;

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

    // Installs that predate site lists keep a source with no sites at all,
    // which would leave the whole fan-out empty after the upgrade.
    final sitesBackfilled = _backfillDemoSites(sources);

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
    } else if (sitesBackfilled) {
      await prefs.setString(
        _kSources,
        jsonEncode(sources.map((e) => e.toJson()).toList()),
      );
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
  // Content
  //
  // Everything the pages render goes through these three getters instead of
  // reaching for the fixtures directly. That is the whole point of the
  // indirection: Phase 2 replaces the bodies with source requests and no page
  // changes at all.
  // -------------------------------------------------------------------------

  /// Hero carousel entries.
  List<MediaItem> get heroItems => demo.heroItems;

  /// Category rows, in display order.
  List<HomeSection> get homeSections => demo.homeSections;

  /// Card definition -> the full record the detail page needs.
  MediaItem detailOf(MediaItem item) => demo.detailFor(item);

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

  /// The sites declared by one source's config, enabled or not.
  List<SiteInfo> sitesOf(String sourceId) {
    for (final source in _sources) {
      if (source.id == sourceId) return source.sites;
    }
    return const [];
  }

  /// Sites the active source contributes to search and to the category rows.
  List<SiteInfo> get activeSites => currentSource?.searchableSites ?? const [];

  /// Sites behind [selection] (null = every source), de-duplicated by display
  /// name so two sources that both ship 玩偶 produce one chip, not two.
  ///
  /// This is the single junction every page reads from. Search fans out over
  /// it, and the resource page's counts come from it, so adding or deleting a
  /// source changes what the whole app sees without any page knowing how.
  List<SiteInfo> sitesForSelection(Set<String>? selection) {
    final out = <String, SiteInfo>{};
    for (final source in _sources) {
      if (selection != null && !selection.contains(source.id)) continue;
      for (final site in source.searchableSites) {
        out.putIfAbsent(site.name, () => site);
      }
    }
    return List.unmodifiable(out.values);
  }

  /// Silences or re-enables one site inside a source.
  Future<void> toggleSite(String sourceId, String siteKey) async {
    final index = _sources.indexWhere((source) => source.id == sourceId);
    if (index < 0) return;
    final source = _sources[index];
    final siteIndex = source.sites.indexWhere((site) => site.key == siteKey);
    if (siteIndex < 0) return;
    final updated = source.withSite(
      source.sites[siteIndex].copyWith(
        enabled: !source.sites[siteIndex].enabled,
      ),
    );
    _sources[index] = updated;
    await _persistSources();
    notifyListeners();
  }

  /// Replaces a source's site list wholesale -- what a successful config parse
  /// does. Keeps the source's other fields (name, url, metrics) untouched.
  Future<void> replaceSites(String sourceId, List<SiteInfo> sites) async {
    final index = _sources.indexWhere((source) => source.id == sourceId);
    if (index < 0) return;
    _sources[index] = _sources[index].copyWith(sites: sites);
    await _persistSources();
    notifyListeners();
  }

  /// Appends a source. Returns its id so the caller can select or edit it.
  Future<String> addSource(SourceInfo source) async {
    _sources.add(source);
    if (_current == null) {
      _current = source.id;
      await _prefs.setString(_kCurrent, jsonEncode(source.id));
    }
    await _persistSources();
    notifyListeners();
    return source.id;
  }

  Future<void> updateSource(SourceInfo source) async {
    final index = _sources.indexWhere((existing) => existing.id == source.id);
    if (index < 0) return;
    _sources[index] = source;
    await _persistSources();
    notifyListeners();
  }

  /// Removes a source. When it was the active one the next source (or nothing)
  /// takes over, so [currentSource] never points at a missing id.
  Future<void> removeSource(String id) async {
    final index = _sources.indexWhere((source) => source.id == id);
    if (index < 0) return;
    _sources.removeAt(index);
    if (_current == id) {
      _current = _sources.isNotEmpty ? _sources.first.id : null;
      await _prefs.setString(_kCurrent, jsonEncode(_current));
    }
    await _persistSources();
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

  Future<void> _persistSources() async {
    await _prefs.setString(
      _kSources,
      jsonEncode(_sources.map((e) => e.toJson()).toList()),
    );
  }

  /// The seeded source, carrying the site list its config bundle declares.
  ///
  /// 豆儿猫源 ships no JSON: its `index.js` is the catvod spider bundle itself,
  /// and every site is a `meta:{key,name,type}` block inside it. `tool/
  /// extract_config_sites.py` pulls those 61 blocks out and drops the two that
  /// are not content sites (`baseset` = the 「设」配置 panel, `webpage` = type 7
  /// 网页入口), leaving the 59 the original lists. Keys get the host's
  /// `nodejs_` prefix, exactly like the `homeSite: nodejs_jianpian` the original
  /// stores in its own preferences.
  static const _demoSourceId = '1794457036493149';

  static const List<SiteInfo> _demoSites = [
    SiteInfo(key: 'nodejs_duoduo', name: '「盘」多多', type: '3', api: 'nodejs_duoduo'),
    SiteInfo(key: 'nodejs_muou', name: '「盘」木偶', type: '3', api: 'nodejs_muou'),
    SiteInfo(key: 'nodejs_huajuan', name: '「盘」花卷', type: '3', api: 'nodejs_huajuan'),
    SiteInfo(key: 'nodejs_labi', name: '「盘」蜡笔', type: '3', api: 'nodejs_labi'),
    SiteInfo(key: 'nodejs_shandian', name: '「盘」闪电', type: '3', api: 'nodejs_shandian'),
    SiteInfo(key: 'nodejs_ouge', name: '「盘」欧歌', type: '3', api: 'nodejs_ouge'),
    SiteInfo(key: 'nodejs_myquark', name: '「盘」夸克', type: '3', api: 'nodejs_myquark'),
    SiteInfo(key: 'nodejs_mycloud', name: '「盘」我的', type: '3', api: 'nodejs_mycloud'),
    SiteInfo(key: 'nodejs_myali', name: '「盘」阿里', type: '3', api: 'nodejs_myali'),
    SiteInfo(key: 'nodejs_mytianyi', name: '「盘」天翼', type: '3', api: 'nodejs_mytianyi'),
    SiteInfo(key: 'nodejs_mybaidu', name: '「盘」百度', type: '3', api: 'nodejs_mybaidu'),
    SiteInfo(key: 'nodejs_my115', name: '「盘」115', type: '3', api: 'nodejs_my115'),
    SiteInfo(key: 'nodejs_my123', name: '「盘」123', type: '3', api: 'nodejs_my123'),
    SiteInfo(key: 'nodejs_123ypzysq', name: '「盘」123社区', type: '3', api: 'nodejs_123ypzysq'),
    SiteInfo(key: 'nodejs_guanying', name: '「盘」观影', type: '3', api: 'nodejs_guanying'),
    SiteInfo(key: 'nodejs_cloudseekr', name: '「盘」CLOUDSEEK', type: '3', api: 'nodejs_cloudseekr'),
    SiteInfo(key: 'nodejs_myguangyapan', name: '「盘」光鸭', type: '3', api: 'nodejs_myguangyapan'),
    SiteInfo(key: 'nodejs_huban', name: '「盘」虎斑', type: '3', api: 'nodejs_huban'),
    SiteInfo(key: 'nodejs_xiaoban', name: '「盘」小斑', type: '3', api: 'nodejs_xiaoban'),
    SiteInfo(key: 'nodejs_woniu', name: '「盘」蜗牛', type: '3', api: 'nodejs_woniu'),
    SiteInfo(key: 'nodejs_libvio', name: '「盘」立播', type: '3', api: 'nodejs_libvio'),
    SiteInfo(key: 'nodejs_wanou', name: '「盘」玩偶', type: '3', api: 'nodejs_wanou'),
    SiteInfo(key: 'nodejs_tgchannel', name: '「盘」TG搜', type: '3', api: 'nodejs_tgchannel'),
    SiteInfo(key: 'nodejs_tgsou', name: '「盘」TG搜²', type: '3', api: 'nodejs_tgsou'),
    SiteInfo(key: 'nodejs_tgfilebot', name: '「直」TGFileBot', type: '3', api: 'nodejs_tgfilebot'),
    SiteInfo(key: 'nodejs_tgvideo', name: '「直」TG视频', type: '3', api: 'nodejs_tgvideo'),
    SiteInfo(key: 'nodejs_douban', name: '「荐」豆瓣', type: '3', api: 'nodejs_douban'),
    SiteInfo(key: 'nodejs_doubi', name: '「直」豆哔', type: '3', api: 'nodejs_doubi'),
    SiteInfo(key: 'nodejs_push', name: '「推」推送', type: '4', api: 'nodejs_push'),
    SiteInfo(key: 'nodejs_pansou', name: '「盘」PanSou', type: '3', api: 'nodejs_pansou'),
    SiteInfo(key: 'nodejs_miniyingshi', name: '「盘」迷你影视', type: '3', api: 'nodejs_miniyingshi'),
    SiteInfo(key: 'nodejs_quanpansou', name: '「盘」全盘搜', type: '3', api: 'nodejs_quanpansou'),
    SiteInfo(key: 'nodejs_jjsou', name: '「盘」JJ搜', type: '3', api: 'nodejs_jjsou'),
    SiteInfo(key: 'nodejs_jutoushe', name: '「盘」剧透社', type: '3', api: 'nodejs_jutoushe'),
    SiteInfo(key: 'nodejs_rrdyw', name: '「盘」人人', type: '3', api: 'nodejs_rrdyw'),
    SiteInfo(key: 'nodejs_pomo', name: '「盘」Pomo', type: '3', api: 'nodejs_pomo'),
    SiteInfo(key: 'nodejs_xingya', name: '「直」星芽', type: '3', api: 'nodejs_xingya'),
    SiteInfo(key: 'nodejs_hongguo', name: '「直」红果', type: '3', api: 'nodejs_hongguo'),
    SiteInfo(key: 'nodejs_live2vod', name: '「直」直播', type: '3', api: 'nodejs_live2vod'),
    SiteInfo(key: 'nodejs_jinpai', name: '「直」金牌', type: '3', api: 'nodejs_jinpai'),
    SiteInfo(key: 'nodejs_jianpian', name: '「直」荐片', type: '3', api: 'nodejs_jianpian'),
    SiteInfo(key: 'nodejs_guazi', name: '「直」瓜子', type: '3', api: 'nodejs_guazi'),
    SiteInfo(key: 'nodejs_juzhi', name: '「直」橘汁', type: '3', api: 'nodejs_juzhi'),
    SiteInfo(key: 'nodejs_gulu', name: '「直」咕噜', type: '3', api: 'nodejs_gulu'),
    SiteInfo(key: 'nodejs_juxiafan', name: '「直」剧下饭', type: '3', api: 'nodejs_juxiafan'),
    SiteInfo(key: 'nodejs_dbku', name: '「直」独播库', type: '3', api: 'nodejs_dbku'),
    SiteInfo(key: 'nodejs_dashixiong', name: '「直」大师兄', type: '3', api: 'nodejs_dashixiong'),
    SiteInfo(key: 'nodejs_hanxiaoquan', name: '「直」韩小圈', type: '3', api: 'nodejs_hanxiaoquan'),
    SiteInfo(key: 'nodejs_ciyuancheng', name: '「直」次元城', type: '3', api: 'nodejs_ciyuancheng'),
    SiteInfo(key: 'nodejs_dmghg', name: '「直」动漫共和国', type: '3', api: 'nodejs_dmghg'),
    SiteInfo(key: 'nodejs_anich', name: '「直」AniCh', type: '3', api: 'nodejs_anich'),
    SiteInfo(key: 'nodejs_dmbus', name: '「直」动漫巴士', type: '3', api: 'nodejs_dmbus'),
    SiteInfo(key: 'nodejs_akianime', name: '「直」AkiAnime', type: '3', api: 'nodejs_akianime'),
    SiteInfo(key: 'nodejs_jiong', name: '「直」囧次元', type: '3', api: 'nodejs_jiong'),
    SiteInfo(key: 'nodejs_4kzn', name: '「盘」指南', type: '3', api: 'nodejs_4kzn'),
    SiteInfo(key: 'nodejs_kafei', name: '「直」咖啡', type: '3', api: 'nodejs_kafei'),
    SiteInfo(key: 'nodejs_emby', name: 'Emby', type: '3', api: 'nodejs_emby'),
    SiteInfo(key: 'nodejs_alist-video', name: 'Alist', type: '3', api: 'nodejs_alist-video'),
    SiteInfo(key: 'nodejs_fenxiang', name: '「盘」分享', type: '3', api: 'nodejs_fenxiang'),
  ];

  static SourceInfo _demoSource() => const SourceInfo(
    id: _demoSourceId,
    type: 'tvbox',
    name: '豆儿猫源',
    url:
        'https://gh-proxy.com/raw.githubusercontent.com/Darklessing/catvod/refs/heads/main/douer/index.js.md5',
    latencyMs: 5000,
    movieCount: 58,
    showCount: 1,
    sites: _demoSites,
  );

  /// Keys of the dozen made-up names that shipped before the real list above
  /// was extracted. Only used to recognise (and drop) that placeholder data.
  static const Set<String> _legacyPlaceholderKeys = {
    'wanou',
    'muou',
    'shandian',
    'duoduo',
    'ouge',
    'huajuan',
    'huban',
    'xiaoban',
    'woniu',
    'naixi',
    'xiaomao',
    'paopao',
  };

  /// Gives the seeded source its sites on installs that predate them, and
  /// upgrades the twelve placeholder names to the real 59.
  ///
  /// Without this, an existing `flutter.sources` keeps a source with no site
  /// list, `sitesForSelection` returns nothing, and search goes blank after the
  /// upgrade -- a regression that only shows up for anyone who already ran the
  /// app. The placeholder pass keeps whatever the user switched off, and leaves
  /// sites they added themselves in place. Returns true when something changed
  /// so the caller can persist.
  static bool _backfillDemoSites(List<SourceInfo> sources) {
    var changed = false;
    for (var index = 0; index < sources.length; index++) {
      final source = sources[index];
      if (source.id != _demoSourceId) continue;

      if (source.sites.isEmpty) {
        sources[index] = source.copyWith(sites: _demoSites);
        changed = true;
        continue;
      }

      final legacy = source.sites
          .where((site) => _legacyPlaceholderKeys.contains(site.key))
          .toList();
      if (legacy.isEmpty) continue;
      if (source.sites.any((site) => site.key.startsWith('nodejs_'))) continue;

      final off = {
        for (final site in legacy)
          if (!site.enabled) site.key,
      };
      final extras = source.sites
          .where((site) => !_legacyPlaceholderKeys.contains(site.key))
          .toList();
      sources[index] = source.copyWith(
        sites: [
          for (final site in _demoSites)
            off.contains(site.key.substring('nodejs_'.length))
                ? site.copyWith(enabled: false)
                : site,
          ...extras,
        ],
      );
      changed = true;
    }
    return changed;
  }

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
