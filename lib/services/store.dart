import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'catalog_sites.dart';
import 'config_fetcher.dart';
import 'danmaku/danmaku_api.dart';
import 'danmaku/source_danmaku.dart';
import 'demo_data.dart' as demo;
import 'emby_client.dart';
import 'source_catalogue.dart';
import 'source_import.dart' show countLiveChannels;
import 'source_probe.dart';
import 'media_mount.dart';
import 'picture.dart';
import 'play_target.dart';
import 'player_info.dart';
import 'skip_rule.dart';
import 'script_runtime.dart';
import 'spider_client.dart' show SpiderClass, SpiderHome, SpiderList;
import 'tvbox_catalogue.dart';
import 'tvbox_source.dart';
import 'webdav_client.dart';
import 'spider_session.dart';
import 'track_choice.dart';

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

  /// The catvod (猫源) runtime, wired up lazily on first use. Null when the
  /// app has no `js`-type source or the runtime paths were never configured --
  /// in which case nothing can answer a spider request, and the pages say so
  /// rather than filling in fixtures.
  SpiderSession? spider;

  /// The TVBox script runtimes (Python and js), also wired up lazily. Null when
  /// neither binary is present -- the same rule as [spider]: no runtime, no
  /// answer, and the pages say so.
  ScriptSources? scripts;

  /// Test seam: when set, [searchRealStream] answers from here instead of the
  /// cat host. The search page is worth exercising without node.exe, and a stub
  /// is the only way to do that -- a real session needs the runtime on disk.
  @visibleForTesting
  Stream<SpiderSearchSite>? Function(String keyword, {bool strict})? searchStub;

  /// Test seam: when set, [detailReal] answers from here instead of the cat
  /// host. Same reason as [searchStub]: the detail page's behaviour with a real
  /// record is worth covering without node.exe on the test machine.
  @visibleForTesting
  Future<MediaItem?> Function(MediaItem item)? detailStub;

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

  /// Set once the fixture rows left behind by earlier builds are gone.
  static const _kPurgedFixtures = 'purgedFixtureRows';

  /// Whether a first launch starts with a sample history row and favourite.
  ///
  /// Defaults to [demo.lcbSeedSampleUserData] (off). Tests that need rows to
  /// exercise the 历史 and 收藏 pages flip it in `setUpAll`, which keeps the
  /// fixtures out of the app while leaving the pages covered.
  @visibleForTesting
  static bool seedSampleUserData = demo.lcbSeedSampleUserData;

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
    final sitesBackfilled = _migrateDemoSource(sources);

    var current = prefs.getString(_kCurrent);
    if (current != null && current.length >= 2 && current.startsWith('"')) {
      current = jsonDecode(current) as String;
    }

    var settings = AppSettings.fromJson(
      _decodeMap(prefs.getString(_kSettings)),
    );

    // Seed on the true first launch only, tracked by an explicit flag. Seeding
    // on "list is empty" would resurrect rows after the user clears their
    // history/favourites, so the flag is authoritative.
    final isFirstLaunch = !(prefs.getBool(_kSeeded) ?? false);
    if (isFirstLaunch) {
      // The sample source is kept: it is a real subscription, not invented
      // content, and a fresh install needs something to point at.
      if (sources.isEmpty) {
        sources.add(_demoSource());
      }
      // A sample watch history and favourite are not kept: they read exactly
      // like something the user did, and there is no way to tell them apart on
      // the page.
      if (AppStore.seedSampleUserData) {
        if (history.isEmpty) {
          history.add(_demoHistoryEntry(sources.first.id, sources.first.name));
        }
        if (folders.isEmpty) {
          folders.add(_demoFolder());
        }
        if (favorites.isEmpty) {
          favorites.add(_demoFavorite(folders.first.id));
        }
      }
      // Persist the seeded state so a relaunch does not lose it (the flag alone
      // would skip seeding while the lists were never written).
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

    // Installs that ran while the fixture catalogue was live still carry a
    // sample watch history and favourite. They cannot be told apart from real
    // records on screen, so they are dropped once: a real record's poster is a
    // URL its source served, and `assets/demo/` was only ever the fixtures'.
    if (!AppStore.seedSampleUserData &&
        !(prefs.getBool(_kPurgedFixtures) ?? false)) {
      final beforeHistory = history.length;
      final beforeFavorites = favorites.length;
      history.removeWhere((e) => e.poster.startsWith('assets/demo/'));
      favorites.removeWhere((e) => e.poster.startsWith('assets/demo/'));
      // The demo folder only ever held that favourite; leave it if it has
      // anything real in it now.
      folders.removeWhere(
        (f) =>
            f.id == _demoFolderId &&
            !favorites.any((e) => e.folderId == f.id),
      );
      if (history.length != beforeHistory) {
        await prefs.setString(
          _kHistory,
          jsonEncode(history.map((e) => e.toJson()).toList()),
        );
      }
      if (favorites.length != beforeFavorites) {
        await prefs.setString(
          _kFavorites,
          jsonEncode(favorites.map((e) => e.toJson()).toList()),
        );
        await prefs.setString(
          _kFavoriteFolders,
          jsonEncode(folders.map((e) => e.toJson()).toList()),
        );
      }
      await prefs.setBool(_kPurgedFixtures, true);
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
  ///
  /// Each card is the history row's own record, so it carries the real vod id
  /// (detail lookups work) and the episode that was being watched (the card
  /// reopens that episode, not 第1集).
  List<ContinueWatching> get continueWatching => [
    for (final e in _history)
      ContinueWatching(
        media: e.toMediaItem(),
        episodeLabel: e.episode,
        episodeIndex: e.episodeIndex,
        positionMs: e.positionMs,
        durationMs: e.durationMs,
      ),
  ];

  /// The history row for [item], if it has been watched.
  ///
  /// Matched by the source's own vod id first (and site, when both sides name
  /// one), because that is the same identity the detail lookup uses. Rows from
  /// before the vod id was stored only have a title to go on, so they are a
  /// fallback -- and only those, otherwise a title clash across sites would
  /// resume the wrong work.
  HistoryEntry? historyFor(MediaItem item) {
    HistoryEntry? legacy;
    for (final e in _history) {
      final vod = e.vodId;
      if (vod == null || vod.isEmpty) {
        if (legacy == null && e.title == item.title) legacy = e;
        continue;
      }
      if (vod != item.id) continue;
      if (item.siteKey != null &&
          e.siteKey != null &&
          e.siteKey != item.siteKey) {
        continue;
      }
      return e;
    }
    return legacy;
  }

  /// Which episode 播放 opens for [item]: the one last watched, or the first.
  ///
  /// A hero card only shows a poster and a title, so pressing 播放 on a series
  /// used to start 第1集 even when the viewer was on 第39集. The recorded index
  /// is clamped to the episode list because a source can renumber between
  /// visits; an unknown count leaves the index alone.
  int startEpisodeFor(MediaItem item) {
    final row = historyFor(item);
    final index = row?.episodeIndex ?? 0;
    if (index <= 0) return 0;
    if (item.episodes.isEmpty) return index;
    return index < item.episodes.length ? index : item.episodes.length - 1;
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

  /// What the viewer asked to have skipped at the head and tail of an episode.
  ///
  /// Zero everywhere unless they set it, and [SkipRule.none] when the toggle is
  /// off — so a fresh install seeks nowhere rather than guessing an intro.
  SkipRule get skipRule {
    if (!_settings.skipIntroOutro) return SkipRule.none;
    final intro = _settings.introSkipMs;
    final outro = _settings.outroSkipMs;
    if (intro <= 0 && outro <= 0) return SkipRule.none;
    return SkipRule(
      intro: Duration(milliseconds: intro < 0 ? 0 : intro),
      outro: Duration(milliseconds: outro < 0 ? 0 : outro),
    );
  }

  /// 一部作品在「本剧设置」里的键。
  ///
  /// 用作品名而不是 vod id：同一部剧在不同站点有不同的 id，换了线路就认不出
  /// 是同一部剧了；而片头长短是作品自身的属性，跟从哪个站点播没关系。代价是
  /// 同名作品会共用一组设置——这比"换线路就丢设置"更少见，也不会造成实际伤害
  /// （[SkipRule] 的护栏会拦住对不上的秒数）。
  String skipKeyOf(String title) => title.trim();

  /// 这部作品自己设过的片头片尾，没设过就是空覆盖（全跟随全局）。
  SkipOverride skipOverrideFor(String title) {
    final raw = _settings.skipOverrides[skipKeyOf(title)];
    if (raw == null) return SkipOverride.none;
    return SkipOverride.fromJson(raw);
  }

  /// 这部作品实际生效的跳过规则：全局值 + 本剧覆盖，逐字段合并。
  ///
  /// 总开关关掉时一律 [SkipRule.none]——本剧覆盖不能绕过那个开关，否则用户
  /// 在设置里关掉"跳过片头片尾"之后，某些剧还会继续跳。
  SkipRule skipRuleFor(String title) {
    if (!_settings.skipIntroOutro) return SkipRule.none;
    return skipRule.mergeOverride(skipOverrideFor(title));
  }

  /// 记住本剧的片头片尾。两个字段都为空时等于"取消本剧设置"，会把条目删掉。
  Future<void> setSkipOverride(String title, SkipOverride override) async {
    final key = skipKeyOf(title);
    if (key.isEmpty) return;
    final next = Map<String, Map<String, int>>.from(_settings.skipOverrides);
    if (override.isEmpty) {
      if (!next.containsKey(key)) return;
      next.remove(key);
    } else {
      if (next[key] != null && _sameOverride(next[key]!, override)) return;
      next[key] = override.toJson();
    }
    await updateSettings(_settings.copyWith(skipOverrides: next));
  }

  /// 有多少部作品单独设过，设置页拿它显示条数。
  int get skipOverrideCount => _settings.skipOverrides.length;

  /// 把所有本剧设置清掉，全部回到全局那一组。
  Future<void> clearSkipOverrides() async {
    if (_settings.skipOverrides.isEmpty) return;
    await updateSettings(_settings.copyWith(skipOverrides: const {}));
  }

  bool _sameOverride(Map<String, int> raw, SkipOverride override) {
    final current = SkipOverride.fromJson(raw);
    return current == override;
  }

  /// Remembers the volume and speed the player was left at, so the next
  /// episode opens the same way. Written once when the player closes, not on
  /// every slider tick.
  Future<void> savePlaybackPrefs({
    required int volume,
    required double rate,
  }) async {
    if (volume == _settings.playerVolume && rate == _settings.playerRate) {
      return;
    }
    await updateSettings(
      _settings.copyWith(playerVolume: volume, playerRate: rate),
    );
  }

  /// 画面比例短码，`AspectMode.slug`。认不出退回 `fit`（原始比例）。
  String get aspectFit => _settings.aspectFit;

  /// 记住画面比例，跨会话沿用（同一部剧、不同剧都用同一档）。
  Future<void> saveAspectFit(String slug) async {
    if (slug == _settings.aspectFit) return;
    await updateSettings(_settings.copyWith(aspectFit: slug));
  }

  /// 画面调节五个量（亮度/对比度/饱和度/色相/伽马），值域 -100..100。
  PictureAdjust get pictureAdjust =>
      PictureAdjust.fromJson(_settings.pictureAdjust);

  /// 记住画面调节。原版「各资源记住自己调过的亮度」目前只做到全局一档，
  /// 不做按资源记忆——那是另一个维度，先对齐可见的画面调节本身。
  Future<void> savePictureAdjust(PictureAdjust adjust) async {
    final current = pictureAdjust;
    if (current == adjust) return;
    await updateSettings(_settings.copyWith(pictureAdjust: adjust.toJson()));
  }

  /// 播放页常驻信息浮层要显示的信息短码（有序），空列表 = 不显示浮层。
  List<PlayerInfoField> get playerInfoFields =>
      PlayerInfoField.parseList(_settings.playerInfoFields);

  /// 记住信息浮层显示哪些信息。原版「信息显示」是设置页多选，这里先落到
  /// 全局一档（跨剧沿用），不做按资源记忆。
  Future<void> savePlayerInfoFields(List<PlayerInfoField> fields) async {
    final next = fields.map((f) => f.slug).join(',');
    if (next == _settings.playerInfoFields) return;
    await updateSettings(_settings.copyWith(playerInfoFields: next));
  }

  /// 播放页最底下的「迷你进度条」开关（蓝=已播、浅蓝=已缓冲，常驻）。
  bool get miniProgress => _settings.miniProgress;

  Future<void> saveMiniProgress(bool on) async {
    if (on == _settings.miniProgress) return;
    await updateSettings(_settings.copyWith(miniProgress: on));
  }

  /// The tracks the viewer picked last time on the same work and line.
  ///
  /// Empty when nothing was ever picked, which the player reads as "follow
  /// mpv's default" rather than "turn everything off".
  TrackPrefs trackPrefsFor(String key) =>
      TrackPrefs.fromJson(_settings.trackPrefs[key]);

  /// Remembers a track pick for one line. Clearing every pick on that line
  /// removes the entry instead of storing three nulls.
  Future<void> saveTrackPrefs(String key, TrackPrefs prefs) async {
    if (key.isEmpty) return;
    final current = _settings.trackPrefs[key];
    final nextPick = prefs.isEmpty ? null : prefs.toJson();
    if (_sameTracks(current, nextPick)) return;

    final next = Map<String, Map<String, String>>.from(_settings.trackPrefs);
    if (nextPick == null) {
      next.remove(key);
    } else {
      next[key] = nextPick;
    }
    await updateSettings(_settings.copyWith(trackPrefs: next));
  }

  /// 有多少条线路记过轨道选择，设置页拿它显示条数。
  int get trackPrefCount => _settings.trackPrefs.length;

  /// 这一集挂过的外挂字幕（本地文件路径）。文件被删掉时返回 null——记着的
  /// 路径还在，但播放页不该拿一个不存在的文件去开。
  String? externalSubtitleFor(String key) {
    final path = _settings.externalSubtitles[key];
    if (path == null || path.isEmpty) return null;
    return File(path).existsSync() ? path : null;
  }

  /// 把字幕记在这一集上。传 null 表示「这一集不要外挂字幕了」。
  Future<void> saveExternalSubtitle(String key, String? path) async {
    if (key.isEmpty) return;
    final current = _settings.externalSubtitles;
    if (path == null || path.isEmpty) {
      if (!current.containsKey(key)) return;
      final next = Map<String, String>.from(current)..remove(key);
      await updateSettings(_settings.copyWith(externalSubtitles: next));
      return;
    }
    if (current[key] == path) return;
    final next = Map<String, String>.from(current)..[key] = path;
    await updateSettings(_settings.copyWith(externalSubtitles: next));
  }

  /// 有多少集的外挂字幕文件还在。文件被删掉的那些不算——设置页说的是
  /// 「下次打开会自己挂上」，已经不存在的文件不配这句话。
  int get externalSubtitleCount {
    var live = 0;
    for (final path in _settings.externalSubtitles.values) {
      if (path.isNotEmpty && File(path).existsSync()) live++;
    }
    return live;
  }

  /// 把所有记下来的外挂字幕清掉（文件本身不动）。
  Future<void> clearExternalSubtitles() async {
    if (_settings.externalSubtitles.isEmpty) return;
    await updateSettings(_settings.copyWith(externalSubtitles: const {}));
  }

  /// 把所有记住的轨道选择清掉，全部回到各线路的默认轨道。
  Future<void> clearTrackPrefs() async {
    if (_settings.trackPrefs.isEmpty) return;
    await updateSettings(_settings.copyWith(trackPrefs: const {}));
  }

  static bool _sameTracks(
    Map<String, String>? a,
    Map<String, String>? b,
  ) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  // -------------------------------------------------------------------------
  // Danmaku
  // -------------------------------------------------------------------------

  /// 弹幕源与缓存。整个应用共用一个实例，同一部剧换集时能命中它的缓存。
  final DanmakuService danmaku = DanmakuService();

  /// 弹幕源表，内置源永远排第一。
  ///
  /// 用户给内置源填过 AppId/AppSecret 时用的就是他填的那份配置（同一个 id），
  /// 没填过才是那个不带凭据的常量——否则设置里填的凭据永远不会生效。
  List<DanmakuSource> get danmakuSources {
    final parsed = <DanmakuSource>[];
    for (final raw in _settings.danmakuSources) {
      final s = DanmakuSource.fromJson(raw);
      if (s != null) parsed.add(s);
    }
    final builtin = parsed.firstWhere(
      (s) => s.isBuiltin,
      orElse: () => DanmakuSource.builtin,
    );
    return [
      builtin,
      for (final s in parsed)
        if (!s.isBuiltin) s,
    ];
  }

  /// 用户自己加的源（不计内置的那一条）。
  int get customDanmakuSourceCount =>
      danmakuSources.where((s) => !s.isBuiltin).length;

  /// 新增或按 id 覆盖一条源。内置源也能改（填凭据、停用），但删不掉。
  Future<void> saveDanmakuSource(DanmakuSource source) async {
    final next = <Map<String, Object?>>[];
    var replaced = false;
    for (final s in danmakuSources) {
      if (s.id == source.id) {
        next.add(source.toJson());
        replaced = true;
      } else {
        next.add(s.toJson());
      }
    }
    if (!replaced) next.add(source.toJson());
    await updateSettings(_settings.copyWith(danmakuSources: next));
    danmaku.clearCache();
  }

  /// 删掉一条用户源。内置源删不掉：删了以后播放页就没有任何可问的地址。
  Future<void> removeDanmakuSource(String id) async {
    if (id == DanmakuSource.builtin.id) return;
    final next = [
      for (final s in danmakuSources)
        if (s.id != id) s.toJson(),
    ];
    await updateSettings(_settings.copyWith(danmakuSources: next));
    danmaku.clearCache();
  }

  // -------------------------------------------------------------------------
  // Content
  //
  // The bundled fixture catalogue is only ever returned while
  // [lcbDemoCatalogue] is on. With it off -- the default -- these getters say
  // "nothing", which is the truth: no source has been asked yet at this layer.
  // The pages ask a source themselves ([spiderCatalogue], [mountLibrary]) and
  // render the answer; an empty answer stays empty rather than borrowing
  // fixtures, so what is on screen is always something a source said.
  // -------------------------------------------------------------------------

  /// Hero carousel entries, tagged with the site they came from.
  List<MediaItem> get heroItems =>
      demo.lcbDemoCatalogue ? _attribute(demo.heroItems) : const [];

  /// Category rows, in display order.
  List<HomeSection> get homeSections => demo.lcbDemoCatalogue
      ? [
          for (final section in demo.homeSections)
            HomeSection(title: section.title, items: _attribute(section.items)),
        ]
      : const [];

  /// Card definition -> the full record the detail page needs.
  ///
  /// Only the fixture catalogue has a "fuller" payload than its card; a real
  /// source's card already carries what its detail call returned, so this is a
  /// pass-through unless the fixtures are in use.
  MediaItem detailOf(MediaItem item) => demo.lcbDemoCatalogue
      ? demo.detailFor(item).withSiteKey(item.siteKey)
      : item;

  /// Pins a fixture to the site the home feed is supposed to come from.
  ///
  /// The bundled cards were transcribed from one live session on the source's
  /// home site, so that is what they claim -- not a per-title hash, which would
  /// have 尚公主 arrive from 「盘」夸克 in the detail page while history says it
  /// was watched on 「直」荐片. Real source responses will carry their own key
  /// and this becomes a no-op.
  List<MediaItem> _attribute(List<MediaItem> items) {
    final site = homeSite;
    if (site == null) return items;
    return [for (final item in items) item.withSiteKey(site.key)];
  }

  // -------------------------------------------------------------------------
  // Real source data (spider)
  //
  // These reach the catvod spider and are what the pages call to get content.
  // Every one degrades gracefully -- a missing session, a dead site or a failed
  // download returns nothing rather than throwing -- and nothing is substituted
  // for the missing answer.
  // -------------------------------------------------------------------------

  /// The subscription address a source can be booted from, or null when this
  /// source cannot run in the cat host at all.
  ///
  /// Strict on purpose: a catvod subscription is a directory holding
  /// `index.js` + `index.config.js`, addressed as `.../index.js.md5` or
  /// `.../index.js` -- exactly the two shapes [CatBundle] knows how to resolve.
  /// A TVBox config URL (`.../config.json`), an Emby mount, a live list and a
  /// local spider file are all addressed differently, and booting them as a
  /// bundle would only produce a download failure that reads like "source is
  /// broken" instead of "this kind of source is checked another way".
  String? spiderAddressOf(SourceInfo source) {
    if (source.type != 'js' && source.type != 'tvbox') return null;
    final url = source.url.trim();
    if (url.isEmpty) return null;
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return null;
    }
    if (!lower.endsWith('.md5') && !lower.endsWith('/index.js')) return null;
    return url;
  }

  /// The current source's id and subscription address, or null when the active
  /// source does not run in the cat host.
  ///
  /// Deliberately looser than [spiderAddressOf]: search is worth attempting for
  /// any `js`/`tvbox` source with a remote address, and a bundle that fails to
  /// resolve simply yields no hits.
  (String, String)? _jsSource() {
    final source = currentSource;
    if (source == null) return null;
    if (source.type != 'js' && source.type != 'tvbox') return null;
    final url = source.url.trim();
    if (url.isEmpty) return null;
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      return null;
    }
    return (source.id, url);
  }

  // -------------------------------------------------------------------------
  // Script (TVBox) sources
  //
  // Three shapes reach a script runtime: an imported `main.py` / `main.js`
  // (type `py` / `js`, its url is the file), a TVBox config whose sites point at
  // a `.py` or `.js` file (possibly remote), and the platforms an aggregate
  // Python file expands into. All of them are expressed as [SiteInfo] so
  // everything above this line -- routing, detail, play -- has one shape to
  // reason about; which runtime serves a site is decided by its api suffix.
  // -------------------------------------------------------------------------

  /// The sites of [source] a script host can run (`.py` or `.js`).
  ///
  /// A `py` source is one site that happens to be a single file: its own id is
  /// used as the site key, which keeps history rows and detail lookups stable
  /// without inventing a site that the user never saw. Once 检测 expands an
  /// aggregate file, the platforms it declares are stored as its sites and win.
  List<SiteInfo> scriptSitesOf(SourceInfo? source) {
    if (source == null) return const [];
    if (source.type == 'py' || source.type == 'js') {
      if (source.sites.isNotEmpty) return source.sites;
      if (!isScriptApi(source.url)) return const [];
      return [
        SiteInfo(key: source.id, name: source.name, api: source.url),
      ];
    }
    if (source.type == 'tvbox') {
      return [
        for (final site in source.sites)
          if (isScriptApi(site.api)) site,
      ];
    }
    return const [];
  }

  /// The site the home page should draw from: the one the config nominated,
  /// else the first enabled script site.
  SiteInfo? scriptHomeSiteOf(SourceInfo? source) {
    final sites = scriptSitesOf(source);
    if (sites.isEmpty) return null;
    final wanted = source?.homeSite ?? '';
    for (final site in sites) {
      if (site.key == wanted && site.enabled) return site;
    }
    for (final site in sites) {
      if (site.enabled) return site;
    }
    return sites.first;
  }

  /// True when the active source answers the home screen through a script host.
  bool get hasScriptHome {
    final source = currentSource;
    return scripts != null && source != null && scriptHomeSiteOf(source) != null;
  }

  /// True when the player must ask the source for its final URL instead of
  /// playing the address the detail handed out.
  ///
  /// TVBox's `playerContent` is what turns a `play_url` entry into an actual
  /// stream (and attaches the headers some CDNs require); playing the raw entry
  /// works only for the sources that already point at an m3u8.
  bool get resolvesPlayUrl {
    final source = currentSource;
    return scripts != null && scriptSitesOf(source).isNotEmpty;
  }

  /// The active source's home rails through its script host, or null when it
  /// does not run there.
  Future<CatalogueFeed?> scriptCatalogue() async {
    final runtime = scripts;
    final source = currentSource;
    if (runtime == null || source == null) return null;
    final site = scriptHomeSiteOf(source);
    if (site == null) return null;
    final client = await runtime.sourceFor(source: source, site: site);
    if (client == null) {
      return CatalogueFeed.failure(
        runtime.lastError ?? '脚本宿主没有启动',
        siteName: site.name,
      );
    }
    return TvBoxCatalogue(client, siteName: site.name).load();
  }

  /// The script client behind one [site] of the active source.
  Future<TvBoxSource?> _scriptClientFor(SourceInfo source, SiteInfo site) async {
    final runtime = scripts;
    if (runtime == null) return null;
    return runtime.sourceFor(source: source, site: site);
  }

  /// The site an item came back from. A `py` source has exactly one, so an
  /// untagged row (a favourite carried across a re-import, say) still resolves.
  SiteInfo? _scriptSiteOf(SourceInfo source, MediaItem item) {
    final sites = scriptSitesOf(source);
    if (sites.isEmpty) return null;
    final key = item.siteKey;
    if (key != null) {
      for (final site in sites) {
        if (site.key == key) return site;
      }
    }
    return sites.first;
  }

  /// Whether [source] is a media mount (Emby / Jellyfin) rather than a scraper.
  ///
  /// Kept as one predicate because three call sites must agree on it: which
  /// client answers a search, which one answers a detail, and whether 检测 runs
  /// the mount or pulls a config document. A source that disagrees with itself
  /// between those three is how "the card says 58 部 but search is empty" bugs
  /// happen.
  static bool isMountSource(SourceInfo? source) {
    if (source == null) return false;
    return source.type == 'emby' ||
        source.type == 'jellyfin' ||
        source.type == 'webdav';
  }

  /// A client for [source]'s mount, or null when it is not a mount or is not
  /// set up yet. The caller owns the result and must [MediaMount.close] it --
  /// every call site is a short request, and leaking a socket per keystroke is
  /// not worth a connection pool this early.
  ///
  /// Emby / Jellyfin need a token from a login; WebDAV needs the credential
  /// itself, because the protocol has no token exchange. That password is
  /// stored in the source record (local prefs, plain) -- the same place the
  /// original keeps it, and the only way a share can be reopened without asking
  /// the user every launch.
  MediaMount? mountClientOf(SourceInfo? source) {
    if (!isMountSource(source)) return null;
    if (source!.url.trim().isEmpty) return null;
    if (source.type == 'webdav') {
      return WebDavClient(
        baseUrl: source.url,
        username: source.username,
        password: source.password,
        sourceName: source.name,
      );
    }
    if (source.token.isEmpty || source.tokenUserId.isEmpty) return null;
    return EmbyClient(
      baseUrl: source.url,
      token: source.token,
      userId: source.tokenUserId,
      sourceName: source.name,
    );
  }

  /// Headers the player must send along with a stream URL from the current
  /// source. Empty for every source whose URL already carries its credential
  /// (spiders, Emby's `api_key`); a WebDAV share needs Basic auth here.
  Map<String, String> get playbackHeaders {
    final mount = mountClientOf(currentSource);
    if (mount == null) return const {};
    try {
      return mount.playbackHeaders;
    } finally {
      mount.close();
    }
  }

  /// Whether a real search is possible right now: a cat host to run the spider,
  /// a logged-in mount to query, or a stub standing in for either.
  bool get canSearchReal =>
      searchStub != null ||
      (spider != null && _jsSource() != null) ||
      mountClientOf(currentSource) != null ||
      (scripts != null && scriptSitesOf(currentSource).isNotEmpty);

  /// The active mount's library, newest first, for the home rails.
  ///
  /// Returns an empty list for "not a mount", "not logged in" and "the server
  /// did not answer" alike: the home page only needs to know what to draw, and
  /// it already has the source card to explain a broken mount. It is never
  /// replaced with sample rows: an empty library must look empty.
  Future<List<MediaItem>> mountLibrary({int limit = 24}) async {
    final mount = mountClientOf(currentSource);
    if (mount == null) return const [];
    try {
      return await mount.library(limit: limit);
    } on Object {
      // A mount that cannot be read draws an empty library; the source card is
      // where the reason belongs, and 检测 is where it gets written down.
      return const [];
    } finally {
      mount.close();
    }
  }

  /// True when the active source is a logged-in mount, i.e. the home page
  /// should draw the server's library rather than the bundled catalogue.
  bool get hasMount => mountClientOf(currentSource) != null;

  /// True when the active source can run in the cat host, i.e. the home page
  /// should draw the source's own rails rather than the bundled catalogue.
  ///
  /// Deliberately keyed on [spiderAddressOf] (strict) rather than the looser
  /// search rule: the front page is drawn from the source or not at all, and a
  /// TVBox config URL that cannot be booted has no rails to offer. Such a
  /// source leaves the page in its "no source" state.
  bool get hasSpiderHome {
    final source = currentSource;
    return source != null && spiderAddressOf(source) != null;
  }

  /// The active 猫源's home rails, or null when the active source does not run
  /// in the cat host.
  ///
  /// Null and an empty feed mean different things: null is "not a spider
  /// source at all", while an empty feed is "this source answered with
  /// nothing". Both are stated on the page, the second with the source's own
  /// site name, and neither is filled in with borrowed titles.
  Future<CatalogueFeed?> spiderCatalogue() async {
    final session = spider;
    final source = currentSource;
    if (session == null || source == null) return null;
    final address = spiderAddressOf(source);
    if (address == null) return null;
    // 首页画的就是 [homeSite] 这一个站点。换站之后这里跟着换，页面才不会一边
    // 顶着新站的名字、一边摆着旧站的片单。
    return SourceCatalogue(
      session,
    ).load(source: source, md5Url: address, site: homeSite);
  }

  /// Runs a keyword search against every enabled site behind the active source.
  /// Returns null when the runtime is unavailable, which the search page reads
  /// as "this query cannot leave the machine" rather than "no results".
  Future<SpiderSearch?> searchReal(String keyword, {bool strict = false}) async {
    final mount = mountClientOf(currentSource);
    if (mount != null) {
      try {
        final items = _applyStrict(await mount.search(keyword), strict, keyword);
        return SpiderSearch(
          groups: [
            SpiderSearchSite(site: currentSource!.name, items: items),
          ],
        );
      } on Object catch (e) {
        return SpiderSearch.failure('$e');
      } finally {
        mount.close();
      }
    }
    final session = spider;
    final js = _jsSource();
    if (session == null || js == null) return null;
    final sites = currentSource!.searchableSites;
    if (sites.isEmpty) return null;
    return session.search(
      sourceId: js.$1,
      md5Url: js.$2,
      sites: sites,
      keyword: keyword,
      strict: strict,
    );
  }

  /// Streams search results one site at a time, in completion order, so the UI
  /// can show each site's hits as soon as it responds. Returns null when the
  /// runtime is unavailable.
  Stream<SpiderSearchSite>? searchRealStream(
    String keyword, {
    bool strict = false,
  }) {
    final stub = searchStub;
    if (stub != null) return stub(keyword, strict: strict);

    // A mount answers as a single "site" named after the source, which is the
    // truth: one Emby box is one library, not a list of scraped sites. The
    // search page fans out over `SpiderSearchSite` groups without knowing
    // which kind of source produced them.
    final mount = mountClientOf(currentSource);
    if (mount != null) return _mountSearchStream(mount, keyword, strict);

    final pySites = scriptSitesOf(currentSource);
    if (scripts != null && pySites.isNotEmpty) {
      return _scriptSearchStream(currentSource!, pySites, keyword, strict);
    }

    final session = spider;
    final js = _jsSource();
    if (session == null || js == null) return null;
    final sites = currentSource!.searchableSites;
    if (sites.isEmpty) return null;
    return session.searchStream(
      sourceId: js.$1,
      md5Url: js.$2,
      sites: sites,
      keyword: keyword,
      strict: strict,
    );
  }

  /// One group, emitted once the library has answered. Cancelling the
  /// subscription still closes the client, because the whole body runs inside
  /// `try/finally` -- the search page cancels on every new keystroke.
  Stream<SpiderSearchSite> _mountSearchStream(
    MediaMount client,
    String keyword,
    bool strict,
  ) async* {
    try {
      final hits = _applyStrict(await client.search(keyword), strict, keyword);
      // Always one group, even when it is empty: an empty group says "your
      // library has nothing matching", which is a different statement from
      // "the search never ran".
      yield SpiderSearchSite(
        site: currentSource?.name ?? '影片库',
        items: hits,
      );
    } finally {
      client.close();
    }
  }

  /// Applies 严格 to hits the server matched fuzzily. Emby's `SearchTerm` and a
  /// TVBox source's `searchContent` both return contains-matches, so strict has
  /// to be applied here or the toggle would do nothing on those sources.
  /// Comparison ignores spaces and case, because a library titled `流浪 地球`
  /// should still be an exact hit for `流浪地球`.
  List<MediaItem> _applyStrict(
    List<MediaItem> items,
    bool strict,
    String keyword,
  ) {
    if (!strict) return items;
    final wanted = keyword.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (wanted.isEmpty) return items;
    return items
        .where(
          (item) =>
              item.title.toLowerCase().replaceAll(RegExp(r'\s+'), '') ==
              wanted,
        )
        .toList(growable: false);
  }

  /// One group per script site, emitted as each answers -- the same contract as
  /// the 猫源 stream, so the search page does not care which runtime produced
  /// the rows. A site that fails contributes no group (a dead site is not a
  /// statement that the title does not exist); cancel by unsubscribing, which
  /// closes the controller and stops waiting for the stragglers.
  Stream<SpiderSearchSite> _scriptSearchStream(
    SourceInfo source,
    List<SiteInfo> sites,
    String keyword,
    bool strict,
  ) {
    final controller = StreamController<SpiderSearchSite>();
    controller.onCancel = () {
      if (!controller.isClosed) controller.close();
    };
    Future<void>(() async {
      await Future.wait([
        for (final site in sites)
          _searchOneScriptSite(source, site, keyword, strict, controller),
      ]);
      if (!controller.isClosed) await controller.close();
    });
    return controller.stream;
  }

  Future<void> _searchOneScriptSite(
    SourceInfo source,
    SiteInfo site,
    String keyword,
    bool strict,
    StreamController<SpiderSearchSite> sink,
  ) async {
    try {
      final client = await _scriptClientFor(source, site);
      if (client == null) return;
      final page = await client.search(keyword);
      if (sink.isClosed) return;
      sink.add(
        SpiderSearchSite(
          site: site.name,
          items: _applyStrict(page.items, strict, keyword),
        ),
      );
    } on Object {
      // A source that raises is a source with nothing to show here; the other
      // sites' results still arrive.
    }
  }

  /// Fetches the full record for [item] from its site. Returns null when the
  /// item carries no site key / vod id or the runtime is unavailable.
  Future<MediaItem?> detailReal(MediaItem item) async {
    final stub = detailStub;
    if (stub != null) return stub(item);

    final mount = mountClientOf(currentSource);
    if (mount != null) {
      try {
        return await mount.detail(item);
      } on Object {
        // A detail that cannot be read leaves the list row on screen; the
        // player will say the URL is missing rather than the page dying.
        return null;
      } finally {
        mount.close();
      }
    }

    final pySites = scriptSitesOf(currentSource);
    if (scripts != null && pySites.isNotEmpty) {
      final source = currentSource!;
      final site = _scriptSiteOf(source, item);
      if (site == null) return null;
      try {
        final client = await _scriptClientFor(source, site);
        if (client == null) return null;
        return await client.detail(item);
      } on Object {
        // A TVBox source that cannot answer leaves the row on screen; the
        // player then says the URL is missing rather than the page dying.
        return null;
      }
    }

    final session = spider;
    final js = _jsSource();
    if (session == null || js == null) return null;
    final siteKey = item.siteKey;
    final site = siteKey == null ? null : siteOf(js.$1, siteKey);
    if (site == null) return null;
    // The search list's vod_id is the id the source uses for a detail lookup.
    final vodId = item.id;
    if (vodId.isEmpty) return null;
    return session.detail(
      sourceId: js.$1,
      md5Url: js.$2,
      site: site,
      vodId: vodId,
    );
  }

  /// Resolves the play URL for one episode of [item]. Returns null when the
  /// item carries no site / vod id or the runtime cannot produce a URL. The
  /// detail page prefers the URLs already parsed into [item.playLines]; this
  /// is the fallback that asks the source's `play` action directly.
  Future<String?> playReal(
    MediaItem item, {
    String? flag,
    int? nid,
  }) async {
    final target = await playTargetReal(item, flag: flag, nid: nid);
    return target?.url;
  }

  /// The URL **and** the headers the player must send to open one episode.
  ///
  /// Headers matter for two of the three source kinds and are empty for the
  /// third: a WebDAV share needs Basic auth, a TVBox source may demand the
  /// referer it scraped with, and an Emby stream carries its token in the URL.
  /// Returning them together is what lets the caller open the player once
  /// instead of resolving, then discovering a second answer.
  Future<PlayTarget?> playTargetReal(
    MediaItem item, {
    String? flag,
    int? nid,
  }) async {
    final mount = mountClientOf(currentSource);
    if (mount != null) {
      try {
        // `detail` already wrote every episode's URL into the play lines, and
        // the player prefers those. Reaching here means a card whose detail was
        // never fetched, so fall back to the item's own stream.
        final episodes = [
          for (final line in item.playLines) ...line.episodes,
        ];
        final index = nid ?? 0;
        final url = (index >= 0 && index < episodes.length)
            ? episodes[index].url
            : mount.streamUrl(item.id);
        if (url.isEmpty) return null;
        return PlayTarget(url: url, headers: mount.playbackHeaders);
      } finally {
        mount.close();
      }
    }

    final pySites = scriptSitesOf(currentSource);
    if (scripts != null && pySites.isNotEmpty) {
      return _scriptPlayTarget(currentSource!, item, flag: flag, nid: nid);
    }

    final session = spider;
    final js = _jsSource();
    if (session == null || js == null) return null;
    final siteKey = item.siteKey;
    final site = siteKey == null ? null : siteOf(js.$1, siteKey);
    if (site == null) return null;
    final vodId = item.id;
    if (vodId.isEmpty) return null;
    final url = await session.play(
      sourceId: js.$1,
      md5Url: js.$2,
      site: site,
      vodId: vodId,
      flag: flag,
      nid: nid,
    );
    if (url == null || url.isEmpty) return null;
    return PlayTarget(url: url);
  }

  /// Asks a TVBox source's `playerContent` about one episode.
  ///
  /// The id passed along is the episode's own address from the play line, which
  /// is what the source's `playerContent(flag, id, vipFlags)` expects -- its
  /// site key already rode along on the item, so no lookup is needed here.
  Future<PlayTarget?> _scriptPlayTarget(
    SourceInfo source,
    MediaItem item, {
    String? flag,
    int? nid,
  }) async {
    final site = _scriptSiteOf(source, item);
    if (site == null) return null;
    final lines = item.playLines;
    PlayLine? line;
    if (flag != null) {
      for (final candidate in lines) {
        if (candidate.name == flag) {
          line = candidate;
          break;
        }
      }
    }
    line ??= lines.isEmpty ? null : lines.first;
    if (line == null || line.episodes.isEmpty) return null;
    final index = (nid ?? 0).clamp(0, line.episodes.length - 1);
    final id = line.episodes[index].url;
    if (id.isEmpty) return null;
    try {
      final client = await _scriptClientFor(source, site);
      if (client == null) return null;
      final answer = await client.playTarget(flag: line.name, id: id);
      if (answer == null || answer.url.isEmpty) return null;
      return PlayTarget(url: answer.url, headers: answer.headers);
    } on Object {
      // A source that cannot answer leaves the player closed; the page already
      // owns the "cannot play this" wording.
      return null;
    }
  }

  /// The saved position for [item], for 续播, together with the duration it was
  /// recorded against.
  ///
  /// Matches a history row by title and, for a series, by the episode index;
  /// returns null when the title has never been watched or was finished. A
  /// resume position of zero (or a nearly-finished one) is not worth seeking
  /// to, so it is treated as absent.
  ///
  /// The total is handed along because the store cannot tell whether the row
  /// was recorded on the same cut the player is about to open; only the player
  /// learns the real duration. See `PlaybackClock`.
  ResumePoint? resumePointFor(MediaItem item, {int? episodeIndex}) {
    for (final e in _history) {
      if (e.title != item.title) continue;
      if (episodeIndex != null && e.episodeIndex != episodeIndex) continue;
      final ms = e.positionMs;
      if (ms <= 0) continue;
      // Skip if it was watched to the end (a fresh play, not a resume).
      if (e.durationMs > 0 && ms >= e.durationMs - 3000) continue;
      return ResumePoint(positionMs: ms, totalMs: e.durationMs);
    }
    return null;
  }

  /// Records (or updates) the watch history when the player closes, so 续播
  /// resumes from here next time. [episodeIndex] is null for a film; [lineName]
  /// is the play line's name (may be empty). A film's episode label is the title
  /// itself; a series uses its episode label from [item.episodes].
  Future<void> recordPlayback(
    MediaItem item, {
    required int? episodeIndex,
    required int positionMs,
    required int durationMs,
    required String lineName,
  }) async {
    final source = currentSource;
    if (source == null) return;
    final siteKey = item.siteKey;
    final vodId = item.id;

    // The history key needs a stable vod id; the demo catalogue's card id is
    // the fixture id, which is fine for demo continuity but won't match a real
    // source lookup. Real records carry the source's own vod_id in `id`.
    final key = '${source.id}|${siteKey ?? ''}|$vodId';

    String episodeLabel;
    if (episodeIndex == null) {
      episodeLabel = item.title; // film
    } else if (episodeIndex >= 0 && episodeIndex < item.episodes.length) {
      episodeLabel = item.episodes[episodeIndex];
    } else {
      episodeLabel = '第${episodeIndex + 1}集';
    }

    await putHistory(
      HistoryEntry(
        key: key,
        sourceId: source.id,
        title: item.title,
        poster: item.image ?? '',
        episode: episodeLabel,
        episodeIndex: episodeIndex ?? 0,
        positionMs: positionMs,
        durationMs: durationMs,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        siteKey: siteKey,
        vodId: vodId,
        flag: lineName.isEmpty ? null : lineName,
        sourceName: source.name,
      ),
    );
  }

  /// Home categories for the active home site, e.g. 电影 / 电视剧.
  Future<List<SpiderClass>> homeCategoriesReal() async {
    final session = spider;
    final js = _jsSource();
    final site = homeSite;
    if (session == null || js == null || site == null) return const [];
    return await session.home(
          sourceId: js.$1,
          md5Url: js.$2,
          site: site,
        ) ??
        const [];
  }

  /// The browse panel's data: the home site's categories and, per category, the
  /// filter groups it offers.
  ///
  /// This asks for the whole `home` answer rather than reusing [spiderCatalogue],
  /// because the catalogue only needs the rails and drops `filters` on the
  /// floor. Null when no site is selected or the source did not answer.
  Future<SpiderHome?> browseHome() async {
    final source = currentSource;
    final site = homeSite;
    if (source == null || site == null) return null;
    if (hasScriptHome) {
      final client = await _scriptClientFor(source, site);
      return client?.homeFull();
    }
    final session = spider;
    final js = _jsSource();
    if (session == null || js == null) return null;
    return session.homeFull(sourceId: js.$1, md5Url: js.$2, site: site);
  }

  /// One page of category [tid] on the home site, for the grid page.
  ///
  /// Both runtimes answer through this method -- which one serves the source is
  /// not the grid's business. Items carry their site key so a detail page
  /// opened from the grid plays from the same site the grid asked.
  ///
  /// [filters] are the browse panel's picks (`class` / `area` / `year` / `by`);
  /// an empty map asks for the category as-is.
  Future<CategoryPage> categoryPageReal(
    String tid, {
    int page = 1,
    Map<String, String> filters = const {},
  }) async {
    final source = currentSource;
    final site = homeSite;
    if (source == null || site == null) {
      return const CategoryPage.failure('没有可用的站点');
    }
    if (hasScriptHome) {
      final client = await _scriptClientFor(source, site);
      if (client == null) {
        return CategoryPage.failure(scripts?.lastError ?? '脚本宿主没有启动');
      }
      // A TVBox source takes the same conditions as its `extend`, with
      // `filter` telling it the conditions are real.
      return _pageOf(
        await client.category(
          tid,
          page: '$page',
          filter: filters.isNotEmpty,
          extend: filters,
        ),
        site.key,
      );
    }
    final session = spider;
    final js = _jsSource();
    if (session == null || js == null) {
      return const CategoryPage.failure('猫源宿主没有启动');
    }
    return _pageOf(
      await session.category(
        sourceId: js.$1,
        md5Url: js.$2,
        site: site,
        tid: tid,
        page: '$page',
        filters: filters,
      ),
      site.key,
    );
  }

  CategoryPage _pageOf(SpiderList list, String siteKey) => CategoryPage(
    items: [for (final item in list.items) item.withSiteKey(siteKey)],
    page: list.page,
    pageCount: list.pageCount,
    total: list.total,
  );

  /// Category feed for one `tid`. Empty when the upstream site has no fresh
  /// feed for that category.
  Future<List<MediaItem>> categoryReal(String tid) async {
    final session = spider;
    final js = _jsSource();
    final site = homeSite;
    if (session == null || js == null || site == null) return const [];
    final list = await session.category(
      sourceId: js.$1,
      md5Url: js.$2,
      site: site,
      tid: tid,
    );
    return [for (final item in list.items) item.withSiteKey(site.key)];
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

  /// The sites declared by one source's config, enabled or not.
  List<SiteInfo> sitesOf(String sourceId) {
    for (final source in _sources) {
      if (source.id == sourceId) return source.sites;
    }
    return const [];
  }

  /// Sites the active source contributes to search and to the category rows.
  List<SiteInfo> get activeSites => currentSource?.searchableSites ?? const [];

  /// The site the home feed claims to come from.
  ///
  /// The original stores this as `homeSite` on the source (`nodejs_jianpian`);
  /// when the config has not named one -- or the user disabled it -- the first
  /// enabled site stands in, which is also what the original does. Null means
  /// there is nothing to show a name for.
  SiteInfo? get homeSite {
    final source = currentSource;
    if (source == null) return null;
    // A single-file script source (`main.py`, `main.js`) declares no sites of
    // its own -- it *is* one site, synthesised by [scriptSitesOf]. Reading only
    // `source.sites` here left the header saying 「全部站点」 for a source that
    // was answering the front page from one perfectly real site.
    final declared = _declaredSites(source);
    for (final site in declared) {
      if (site.key == source.homeSite && site.enabled) return site;
    }
    final enabled = [
      for (final site in declared)
        if (site.enabled) site,
    ];
    return enabled.isEmpty ? null : enabled.first;
  }

  /// The sites a source really has: the declared list, or the single site a
  /// one-file script source stands for. Everything that resolves a key to a
  /// name goes through this, so a `main.py` source is not nameless everywhere
  /// except the header.
  List<SiteInfo> _declaredSites(SourceInfo source) =>
      source.sites.isNotEmpty ? source.sites : scriptSitesOf(source);

  /// One site of one source by key, enabled or not.
  SiteInfo? siteOf(String sourceId, String? siteKey) {
    if (siteKey == null || siteKey.isEmpty) return null;
    for (final source in _sources) {
      if (source.id != sourceId) continue;
      for (final site in _declaredSites(source)) {
        if (site.key == siteKey) return site;
      }
    }
    return null;
  }

  /// Display name for a `siteKey` that history / favourites / cards carry.
  /// Returns [fallback] when the key is unknown (its source was deleted, or the
  /// record predates sites) so callers never have to print a raw key.
  String siteNameOf(String sourceId, String? siteKey, {String fallback = ''}) {
    return siteOf(sourceId, siteKey)?.name ?? fallback;
  }

  /// Display name for a site key when the caller does not know the source --
  /// cards and favourites carry only `siteKey`. Falls back when the key is
  /// unknown (the source was deleted, or the record predates sites).
  String siteNameOfKey(String? siteKey, {String fallback = ''}) {
    if (siteKey == null || siteKey.isEmpty) return fallback;
    for (final source in _sources) {
      for (final site in _declaredSites(source)) {
        if (site.key == siteKey) return site.name;
      }
    }
    return fallback;
  }

  /// Points the home feed at another site, mirroring the original's `homeSite`.
  Future<void> selectHomeSite(String siteKey) async {
    final index = _sources.indexWhere((source) => source.id == _current);
    if (index < 0) return;
    if (_sources[index].homeSite == siteKey) return;
    _sources[index] = _sources[index].copyWith(homeSite: siteKey);
    await _persistSources();
    notifyListeners();
  }

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

  /// Runs 检测 against a spider source: boots it in the host, reads its home
  /// screen, writes the numbers back onto the source and returns the report so
  /// the caller can say what happened. Inert: a dead source comes back as a
  /// failed report, never an exception.
  ///
  /// A mount is checked by asking the server for its library counts, which is
  /// the same question ("does this source have anything to show?") answered the
  /// only way a mount can answer it. [md5Url] is ignored for those.
  Future<ProbeReport> probeSource(SourceInfo source, String md5Url) async {
    final mount = mountClientOf(source);
    if (mount != null) {
      try {
        final report = await mount.probe();
        await applyProbe(source.id, report);
        return report;
      } finally {
        mount.close();
      }
    }

    final runtime = scripts;
    if (runtime != null && scriptSitesOf(source).isNotEmpty) {
      // 检测是「这个源到底能给我什么」的唯一时机，也正好是展开聚合源的时机：
      // 一个 main.py 声明的平台只有跑起来才知道，展开后写回，站点 chip 与
      // 首页/搜索/详情才对得上。
      final effective = await _expandPySites(source);
      final sites = scriptSitesOf(effective);
      final site = scriptHomeSiteOf(effective) ?? sites.first;
      final client = await runtime.sourceFor(source: effective, site: site);
      if (client == null) {
        final failed = ProbeReport.failure(
          runtime.lastError ?? '脚本宿主没有启动',
        );
        await applyProbe(source.id, failed);
        return failed;
      }
      final report = await client.probe(siteCount: sites.length);
      await applyProbe(source.id, report);
      return report;
    }

    final session = spider;
    if (session == null) {
      return const ProbeReport.failure('没有可用的源运行时，先加载源文件');
    }
    final report = await SourceProbe(session).run(
      source: source,
      md5Url: md5Url,
    );
    await applyProbe(source.id, report);
    return report;
  }

  /// Expands an aggregate Python file into the platforms it declares and writes
  /// the result back, returning the source to use from here on.
  ///
  /// Nothing to expand (an ordinary single-site file, or a runtime that cannot
  /// be started right now) returns [source] unchanged -- 检测 then fails on its
  /// own terms instead of reporting a second, unrelated problem.
  Future<SourceInfo> _expandPySites(SourceInfo source) async {
    final runtime = scripts;
    if (runtime == null) return source;
    final sites = await runtime.expandSites(source);
    if (sites == null || sites.isEmpty) return source;
    final index = _sources.indexWhere((existing) => existing.id == source.id);
    if (index < 0) return source;
    // A home site that pointed at the file which just expanded no longer
    // exists; fall back to its first platform. An empty home site stays empty
    // -- [scriptHomeSiteOf] already knows how to pick one.
    final home = _sources[index].homeSite;
    final kept = home.isEmpty || sites.any((site) => site.key == home)
        ? home
        : _firstScriptKey(sites) ?? home;
    final updated = _sources[index].copyWith(sites: sites, homeSite: kept);
    _sources[index] = updated;
    await _persistSources();
    notifyListeners();
    return updated;
  }

  static String? _firstScriptKey(List<SiteInfo> sites) {
    for (final site in sites) {
      if (isScriptApi(site.api)) return site.key;
    }
    return null;
  }

  /// Writes a 检测 result onto one source and persists it.  ///
  /// A failed check keeps whatever latency it measured -- the user waited that
  /// long -- but drops the counts: leaving a stale `58 部` on a source that just
  /// failed is exactly the borrowed number the card must not show.
  Future<void> applyProbe(String sourceId, ProbeReport report) async {
    final index = _sources.indexWhere((source) => source.id == sourceId);
    if (index < 0) return;
    _sources[index] = _sources[index].copyWith(
      latencyMs: report.latencyMs,
      movieCount: report.ok ? report.movieCount : 0,
      showCount: report.ok ? report.showCount : 0,
      checkedAt: DateTime.now().millisecondsSinceEpoch,
    );
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
    await _persistSources();    notifyListeners();
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

  /// Removes several sources in one step, the way 勾选要删除的资源 does.
  ///
  /// One persist and one notify: removing them one by one would rebuild the
  /// list once per card and flash the page while the checkboxes are still up.
  Future<void> removeSources(Iterable<String> ids) async {
    final gone = ids.toSet();
    if (gone.isEmpty) return;
    _sources.removeWhere((source) => gone.contains(source.id));
    if (_current == null || gone.contains(_current)) {
      _current = _sources.isNotEmpty ? _sources.first.id : null;
      await _prefs.setString(_kCurrent, jsonEncode(_current));
    }
    await _persistSources();
    notifyListeners();
  }

  /// Puts the sources in [orderedIds] order; ids the list does not name keep
  /// their previous relative order at the end.
  ///
  /// 检测全部 uses this to sort by the latency it just measured, which is what
  /// the original means by「已按速度排序」. An id that no longer exists (it was
  /// deleted mid-check) simply drops out -- nothing is invented to fill a gap.
  Future<void> reorderSources(List<String> orderedIds) async {
    if (orderedIds.isEmpty) return;
    final rank = <String, int>{
      for (var i = 0; i < orderedIds.length; i++) orderedIds[i]: i,
    };
    final previous = <String, int>{
      for (var i = 0; i < _sources.length; i++) _sources[i].id: i,
    };
    final next = List<SourceInfo>.from(_sources);
    next.sort((a, b) {
      final ra = rank[a.id] ?? orderedIds.length;
      final rb = rank[b.id] ?? orderedIds.length;
      if (ra != rb) return ra.compareTo(rb);
      return (previous[a.id] ?? 0).compareTo(previous[b.id] ?? 0);
    });
    _sources
      ..clear()
      ..addAll(next);
    await _persistSources();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Backup
  // -------------------------------------------------------------------------

  /// Checks a 直播 source by pulling its list and counting channels.
  ///
  /// A live list answers a different question than a VOD source: it has no
  /// sites and no titles, only channels. So the count lands on [channelCount]
  /// (what the card prints) rather than on the title counts, and an empty list
  /// is a failure with the reason spelled out instead of a quiet zero.
  Future<ProbeReport> probeLiveSource(SourceInfo source) async {
    final result = await fetchPlainText(source.url);
    final channels = result.error == null && result.text != null
        ? countLiveChannels(result.text!)
        : 0;
    final index = _sources.indexWhere((existing) => existing.id == source.id);
    if (index >= 0) {
      _sources[index] = _sources[index].copyWith(
        latencyMs: result.latencyMs,
        channelCount: channels,
        checkedAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _persistSources();
      notifyListeners();
    }
    if (result.error != null) {
      return ProbeReport.failure(result.error!, latencyMs: result.latencyMs);
    }
    if (channels == 0) {
      return ProbeReport.failure(
        '没读到频道，确认这是 M3U 或 TXT 直播列表',
        latencyMs: result.latencyMs,
      );
    }
    return ProbeReport(latencyMs: result.latencyMs, showCount: channels);
  }

  /// Puts one source into the user's own [group]. An empty (or blank) name
  /// clears it, which is 原版's「分组名称（留空移出分组）」: the source goes back
  /// to being grouped by its type.
  Future<void> setSourceGroup(String sourceId, String group) async {
    final index = _sources.indexWhere((source) => source.id == sourceId);
    if (index < 0) return;
    final name = group.trim();
    if (_sources[index].groupName == name) return;
    _sources[index] = _sources[index].copyWith(groupName: name);
    await _persistSources();
    notifyListeners();
  }

  /// Renames a user group, or dissolves it when [to] is blank.
  ///
  /// Returns how many sources moved. Nothing is deleted: 原版 「个资源不会删除,
  /// 会回到按类型的分组」 -- a dissolved group's sources simply have no name any
  /// more, so the type grouping picks them up again.
  Future<int> renameGroup(String from, String to) async {
    final name = to.trim();
    if (from.trim().isEmpty || from == name) return 0;
    var moved = 0;
    for (var i = 0; i < _sources.length; i++) {
      if (_sources[i].groupName != from) continue;
      _sources[i] = _sources[i].copyWith(groupName: name);
      moved++;
    }
    if (moved == 0) return 0;
    await _persistSources();
    notifyListeners();
    return moved;
  }

  /// Every user-made group name, sorted. The 分组 sheet offers these so a
  /// rename can pick an existing name instead of splitting a group in two.
  List<String> get customGroups =>
      <String>{
        for (final source in _sources)
          if (source.groupName.isNotEmpty) source.groupName,
      }.toList()..sort();

  /// Gives one source an icon from the bundled pack. An empty id clears it,
  /// which puts the source back on the glyph for its type.
  Future<void> setSourceIcon(String sourceId, String iconId) async {
    final index = _sources.indexWhere((source) => source.id == sourceId);
    if (index < 0) return;
    if (_sources[index].iconId == iconId) return;
    _sources[index] = _sources[index].copyWith(iconId: iconId);
    await _persistSources();
    notifyListeners();
  }

  /// Total sites across every source -- what 数据与存储 reports and what the
  /// resource card counts.
  int get siteCount =>
      _sources.fold(0, (total, source) => total + source.sites.length);

  /// The whole local dataset in the shape the preferences store keeps it, so a
  /// backup can be read back key by key.
  Map<String, dynamic> exportBundle() => {
    'sources': [for (final source in _sources) source.toJson()],
    'current': _current,
    'history': [for (final entry in _history) entry.toJson()],
    'favorites': [for (final entry in _favorites) entry.toJson()],
    'favoriteFolders': [for (final entry in _favoriteFolders) entry.toJson()],
    'settings': _settings.toJson(),
  };

  /// Replaces every list with the bundle's and persists once.
  ///
  /// A bundle that would wipe everything is rejected rather than silently
  /// emptying the app: an empty or malformed file must never look like a
  /// successful restore.
  Future<void> importBundle(Map<String, dynamic> bundle) async {
    final sources = _listFrom(bundle['sources'], SourceInfo.fromJson);
    final history = _listFrom(bundle['history'], HistoryEntry.fromJson);
    final favorites = _listFrom(bundle['favorites'], FavoriteEntry.fromJson);
    final folders = _listFrom(
      bundle['favoriteFolders'],
      FavoriteFolder.fromJson,
    );
    if (sources.isEmpty && history.isEmpty && favorites.isEmpty) {
      throw const FormatException('备份里没有可恢复的源、收藏或历史');
    }

    final rawSettings = bundle['settings'];
    final settings = rawSettings is Map
        ? AppSettings.fromJson(Map<String, dynamic>.from(rawSettings))
        : _settings;

    _sources
      ..clear()
      ..addAll(sources);
    _history
      ..clear()
      ..addAll(history);
    _favorites
      ..clear()
      ..addAll(favorites);
    _favoriteFolders
      ..clear()
      ..addAll(folders);
    _settings = settings;

    final rawCurrent = bundle['current'];
    final validCurrent =
        rawCurrent is String && _sources.any((s) => s.id == rawCurrent);
    _current = validCurrent
        ? rawCurrent
        : (_sources.isEmpty ? null : _sources.first.id);
    favoriteFolderId = null;

    await _persistSources();
    await _persistHistory();
    await _persistFavorites();
    await _persistFolders();
    await _persistSettings();
    await _prefs.setString(_kCurrent, jsonEncode(_current));
    // A restored bundle is a populated install; without this the next launch
    // would run the first-launch seeding on top of it.
    await _prefs.setBool(_kSeeded, true);
    notifyListeners();
  }

  static List<T> _listFrom<T>(
    Object? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw is! List) return <T>[];
    return [
      for (final item in raw)
        if (item is Map) fromJson(Map<String, dynamic>.from(item)),
    ];
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

  static SourceInfo _demoSource() => const SourceInfo(
    id: _demoSourceId,
    type: 'tvbox',
    name: '豆儿猫源',
    url:
        'https://gh-proxy.com/raw.githubusercontent.com/Darklessing/catvod/refs/heads/main/douer/index.js.md5',
    latencyMs: 5000,
    movieCount: 58,
    showCount: 1,
    sites: catalogSites,
    homeSite: _demoHomeSite,
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

  /// The site the original keeps in `homeSite` for 豆儿猫源: its cached home
  /// feed (banners, 电影/电视剧 rows) was drawn from 荐片.
  static const _demoHomeSite = 'nodejs_jianpian';

  /// Brings the seeded source up to date on installs that already ran.
  ///
  /// Three shapes have shipped, and none of them may lose user intent:
  ///   * no `sites` at all -- seed the real list, or search goes blank;
  ///   * the twelve placeholder names -- swap in the real 59, keeping whichever
  ///     switches were flipped and any site the user added himself;
  ///   * no `homeSite` -- point it at 荐片, the site the fixture feed came from.
  ///
  /// Returns true when something changed so the caller can persist.
  static bool _migrateDemoSource(List<SourceInfo> sources) {
    var changed = false;
    for (var index = 0; index < sources.length; index++) {
      final before = sources[index];
      if (before.id != _demoSourceId) continue;
      var source = before;

      if (source.sites.isEmpty) {
        source = source.copyWith(sites: catalogSites);
      } else {
        final legacy = source.sites
            .where((site) => _legacyPlaceholderKeys.contains(site.key))
            .toList();
        final alreadyReal = source.sites.any(
          (site) => site.key.startsWith('nodejs_'),
        );
        if (legacy.isNotEmpty && !alreadyReal) {
          final off = {
            for (final site in legacy)
              if (!site.enabled) site.key,
          };
          final extras = source.sites
              .where((site) => !_legacyPlaceholderKeys.contains(site.key))
              .toList();
          source = source.copyWith(
            sites: [
              for (final site in catalogSites)
                off.contains(site.key.substring('nodejs_'.length))
                    ? site.copyWith(enabled: false)
                    : site,
              ...extras,
            ],
          );
        }
      }

      if (source.homeSite.isEmpty && source.sites.isNotEmpty) {
        source = source.copyWith(homeSite: _demoHomeSite);
      }

      if (!identical(source, before)) {
        sources[index] = source;
        changed = true;
      }
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

  static const _demoFolderId = '1795101875822513';

  static FavoriteFolder _demoFolder() =>
      const FavoriteFolder(id: _demoFolderId, name: '好看的电影');

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
