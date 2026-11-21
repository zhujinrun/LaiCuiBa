import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'catalog_sites.dart';
import 'demo_data.dart' as demo;
import 'emby_client.dart';
import 'source_catalogue.dart';
import 'source_probe.dart';
import 'spider_client.dart' show SpiderClass;
import 'spider_session.dart';

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

  /// Whether [source] is a media mount (Emby / Jellyfin) rather than a scraper.
  ///
  /// Kept as one predicate because three call sites must agree on it: which
  /// client answers a search, which one answers a detail, and whether 检测 runs
  /// the mount or pulls a config document. A source that disagrees with itself
  /// between those three is how "the card says 58 部 but search is empty" bugs
  /// happen.
  static bool isMountSource(SourceInfo? source) {
    if (source == null) return false;
    return source.type == 'emby' || source.type == 'jellyfin';
  }

  /// A client for [source]'s mount, or null when it is not a mount or has never
  /// logged in. The caller owns the result and must [EmbyClient.close] it --
  /// every call site is a short request, and leaking a socket per keystroke is
  /// not worth a connection pool this early.
  EmbyClient? mountClientOf(SourceInfo? source) {
    if (!isMountSource(source)) return null;
    if (source!.token.isEmpty || source.tokenUserId.isEmpty) return null;
    if (source.url.trim().isEmpty) return null;
    return EmbyClient(
      baseUrl: source.url,
      token: source.token,
      userId: source.tokenUserId,
      sourceName: source.name,
    );
  }

  /// Whether a real search is possible right now: a cat host to run the spider,
  /// a logged-in mount to query, or a stub standing in for either.
  bool get canSearchReal =>
      searchStub != null ||
      (spider != null && _jsSource() != null) ||
      mountClientOf(currentSource) != null;

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
    } on EmbyException {
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
    return SourceCatalogue(session).load(source: source, md5Url: address);
  }

  /// Runs a keyword search against every enabled site behind the active source.
  /// Returns null when the runtime is unavailable, which the search page reads
  /// as "this query cannot leave the machine" rather than "no results".
  Future<SpiderSearch?> searchReal(String keyword, {bool strict = false}) async {
    final mount = mountClientOf(currentSource);
    if (mount != null) {
      try {
        final items = _filterMountHits(await mount.search(keyword), strict, keyword);
        return SpiderSearch(
          groups: [
            SpiderSearchSite(site: currentSource!.name, items: items),
          ],
        );
      } on EmbyException catch (e) {
        return SpiderSearch.failure(e.message);
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
    EmbyClient client,
    String keyword,
    bool strict,
  ) async* {
    try {
      final hits = _filterMountHits(await client.search(keyword), strict, keyword);
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

  /// Applies 严格 to a mount's hits. Emby's `SearchTerm` is a fuzzy contains
  /// match, so strict has to be applied here or the toggle would do nothing on
  /// an Emby source. Comparison ignores spaces and case, because a library
  /// titled `流浪 地球` should still be an exact hit for `流浪地球`.
  List<MediaItem> _filterMountHits(
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

  /// Fetches the full record for [item] from its site. Returns null when the
  /// item carries no site key / vod id or the runtime is unavailable.
  Future<MediaItem?> detailReal(MediaItem item) async {
    final stub = detailStub;
    if (stub != null) return stub(item);

    final mount = mountClientOf(currentSource);
    if (mount != null) {
      try {
        return await mount.detail(item);
      } on EmbyException {
        // A detail that cannot be read leaves the list row on screen; the
        // player will say the URL is missing rather than the page dying.
        return null;
      } finally {
        mount.close();
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
        if (index >= 0 && index < episodes.length) {
          return episodes[index].url;
        }
        return mount.streamUrl(item.id);
      } finally {
        mount.close();
      }
    }

    final session = spider;
    final js = _jsSource();
    if (session == null || js == null) return null;
    final siteKey = item.siteKey;
    final site = siteKey == null ? null : siteOf(js.$1, siteKey);
    if (site == null) return null;
    final vodId = item.id;
    if (vodId.isEmpty) return null;
    return session.play(
      sourceId: js.$1,
      md5Url: js.$2,
      site: site,
      vodId: vodId,
      flag: flag,
      nid: nid,
    );
  }

  /// The saved playback position for [item], in milliseconds, for 续播.
  ///
  /// Matches a history row by title and, for a series, by the episode index;
  /// returns null when the title has never been watched or was finished. A
  /// resume position of zero (or a nearly-finished one) is not worth seeking
  /// to, so it is treated as absent.
  int? resumePositionFor(MediaItem item, {int? episodeIndex}) {
    for (final e in _history) {
      if (e.title != item.title) continue;
      if (episodeIndex != null && e.episodeIndex != episodeIndex) continue;
      final ms = e.positionMs;
      if (ms <= 0) continue;
      // Skip if it was watched to the end (a fresh play, not a resume).
      if (e.durationMs > 0 && ms >= e.durationMs - 3000) continue;
      return ms;
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
    return session.home(sourceId: js.$1, md5Url: js.$2, site: site);
  }

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
    for (final site in source.sites) {
      if (site.key == source.homeSite && site.enabled) return site;
    }
    final enabled = source.searchableSites;
    return enabled.isEmpty ? null : enabled.first;
  }

  /// One site of one source by key, enabled or not.
  SiteInfo? siteOf(String sourceId, String? siteKey) {
    if (siteKey == null || siteKey.isEmpty) return null;
    for (final source in _sources) {
      if (source.id != sourceId) continue;
      for (final site in source.sites) {
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
      for (final site in source.sites) {
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

  /// Writes a 检测 result onto one source and persists it.
  ///
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
  // Backup
  // -------------------------------------------------------------------------

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
