import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/playback_clock.dart';
import 'package:lai_cui_ba/services/skip_rule.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/services/track_choice.dart';

HistoryEntry _entry({
  String key = 'src|nodejs_jianpian|1',
  String title = '尚公主',
  bool favorite = false,
  bool following = false,
  int positionMs = 31840,
  int durationMs = 2905400,
  int episodeIndex = 38,
}) {
  return HistoryEntry(
    key: key,
    sourceId: 'src',
    title: title,
    poster: '',
    episode: '第${episodeIndex + 1}集',
    episodeIndex: episodeIndex,
    positionMs: positionMs,
    durationMs: durationMs,
    updatedAt: 0,
    siteKey: 'nodejs_jianpian',
    vodId: '1',
    flag: 'LZ线路',
    sourceName: '豆儿猫源',
    isFavorite: favorite,
    isFollowing: following,
  );
}

FavoriteEntry _fav({
  String key = 'src|nodejs_jianpian|9',
  String title = '欢迎来龙餐馆',
  String? folderId,
  String latest = '共 2 集',
}) {
  return FavoriteEntry(
    key: key,
    sourceId: 'src',
    title: title,
    poster: '',
    siteKey: 'nodejs_jianpian',
    vodId: '9',
    folderId: folderId,
    latest: latest,
    addedAt: 0,
  );
}

void main() {
  // The app does not seed a sample history or favourite any more; these tests
  // need rows to exercise those pages, so they opt in explicitly.
  setUpAll(() => AppStore.seedSampleUserData = true);

  group('HistoryEntry', () {
    test('round-trips through json preserving all fields', () {
      final e = _entry(favorite: true, following: true);
      final json = e.toJson();
      final back = HistoryEntry.fromJson(json);

      expect(back.key, e.key);
      expect(back.title, '尚公主');
      expect(back.episode, '第39集');
      expect(back.episodeIndex, 38);
      expect(back.positionMs, 31840);
      expect(back.durationMs, 2905400);
      expect(back.siteKey, 'nodejs_jianpian');
      expect(back.vodId, '1');
      expect(back.flag, 'LZ线路');
      expect(back.isFavorite, isTrue);
      expect(back.isFollowing, isTrue);
    });

    test('progress clamps to [0,1] and computes correctly', () {
      expect(_entry(positionMs: 0, durationMs: 100).progress, 0);
      expect(_entry(positionMs: 50, durationMs: 100).progress, 0.5);
      expect(_entry(positionMs: 200, durationMs: 100).progress, 1.0);
      expect(_entry(positionMs: 10, durationMs: 0).progress, 0);
    });

    test('copyWith only overrides the given flags', () {
      final e = _entry(favorite: false, following: false);
      final fav = e.copyWith(isFavorite: true);
      expect(fav.isFavorite, isTrue);
      expect(fav.isFollowing, isFalse);
      expect(fav.title, e.title);
      expect(fav.positionMs, e.positionMs);
    });

    test('toMediaItem maps key/title/episode/image', () {
      final e = _entry();
      final m = e.toMediaItem();
      expect(m.id, e.key);
      expect(m.title, '尚公主');
      expect(m.tag, '第39集');
    });
  });

  group('FavoriteEntry', () {
    test('round-trips through json preserving all fields', () {
      final e = _fav(folderId: 'folder1', latest: '共 2 集');
      final back = FavoriteEntry.fromJson(e.toJson());

      expect(back.key, e.key);
      expect(back.title, '欢迎来龙餐馆');
      expect(back.siteKey, 'nodejs_jianpian');
      expect(back.vodId, '9');
      expect(back.folderId, 'folder1');
      expect(back.latest, '共 2 集');
    });

    test('toMediaItem maps title/latest/image', () {
      final m = _fav().toMediaItem();
      expect(m.title, '欢迎来龙餐馆');
      expect(m.tag, '共 2 集');
    });
  });

  group('FavoriteFolder', () {
    test('round-trips through json', () {
      const f = FavoriteFolder(id: 'id1', name: '好看的电影');
      final back = FavoriteFolder.fromJson(f.toJson());
      expect(back.id, 'id1');
      expect(back.name, '好看的电影');
    });
  });

  group('SourceInfo', () {
    test('round-trips through json preserving all fields', () {
      const s = SourceInfo(
        id: '1794457036493149',
        type: 'tvbox',
        name: '豆儿猫源',
        url: 'https://example.com/index.js',
        username: 'u',
        password: 'p',
        latencyMs: 5000,
        movieCount: 58,
        showCount: 1,
        checkedAt: 123456,
      );
      final back = SourceInfo.fromJson(s.toJson());
      expect(back.id, s.id);
      expect(back.type, 'tvbox');
      expect(back.name, '豆儿猫源');
      expect(back.url, s.url);
      expect(back.latencyMs, 5000);
      expect(back.movieCount, 58);
      expect(back.showCount, 1);
    });
  });

  group('AppSettings', () {
    test('round-trips modelled fields and preserves unknown keys', () {
      final s = AppSettings.fromJson({
        'themeMode': 'dark',
        'liquidGlass': false,
        'adaptiveColor': true,
        'skipIntroOutro': false,
        'playerKernel': 'mpv', // unmodelled -> extra
        'danmaku': {'enabled': true},
      });

      expect(s.themeMode, 'dark');
      expect(s.liquidGlass, isFalse);
      expect(s.adaptiveColor, isTrue);
      expect(s.skipIntroOutro, isFalse);
      expect(s.extra['playerKernel'], 'mpv');
      expect(s.extra['danmaku'], {'enabled': true});

      // Round-trip keeps the unmodelled keys.
      final back = AppSettings.fromJson(s.toJson());
      expect(back.extra['playerKernel'], 'mpv');
      expect(back.liquidGlass, isFalse);
    });

    test('defaults when the map is empty', () {
      final s = AppSettings.fromJson({});
      expect(s.themeMode, 'system');
      expect(s.language, 'zh');
      expect(s.liquidGlass, isTrue);
      expect(s.extra, isEmpty);
    });

    test('copyWith overrides only the given fields', () {
      const s = AppSettings(liquidGlass: false);
      final next = s.copyWith(liquidGlass: true);
      expect(next.liquidGlass, isTrue);
      expect(next.hideStatusBar, isFalse); // untouched default
    });

    test('home/nav and playback fields round-trip with defaults', () {
      final s = AppSettings.fromJson({
        'homeBannerEnabled': false,
        'secondHome': false,
        'navStyle': 'solid',
        'navBehavior': 'scroll',
        'tvClassicUi': true,
        'shortDramaPreload': true,
      });
      expect(s.homeBannerEnabled, isFalse);
      expect(s.secondHome, isFalse);
      expect(s.navStyle, 'solid');
      expect(s.navBehavior, 'scroll');
      expect(s.tvClassicUi, isTrue);
      expect(s.shortDramaPreload, isTrue);

      final back = AppSettings.fromJson(s.toJson());
      expect(back.navStyle, 'solid');
      expect(back.shortDramaPreload, isTrue);
    });

    test('new fields default sensibly when absent', () {
      final s = AppSettings.fromJson({});
      expect(s.homeBannerEnabled, isTrue);
      expect(s.secondHome, isTrue);
      expect(s.navStyle, 'glass');
      expect(s.navBehavior, 'always');
      expect(s.tvClassicUi, isFalse);
      expect(s.shortDramaPreload, isFalse);
      expect(s.tvKeyboard, isFalse);
    });
  });

  group('AppStore', () {
    test(
      'seeds a sample source, history and favourite when the seam asks for them',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = await AppStore.load();

        expect(store.sources, isNotEmpty);
        expect(store.sources.first.name, '豆儿猫源');
        expect(store.history, isNotEmpty);
        expect(store.history.first.title, '尚公主');
        expect(store.favorites, isNotEmpty);
        expect(store.favorites.first.title, '欢迎来龙餐馆');
        expect(store.favoriteFolders, isNotEmpty);
        expect(store.favoriteFolders.first.name, '好看的电影');
        expect(store.currentSourceId, store.sources.first.id);
      },
    );

    test('seeded sample data survives a relaunch', () async {
      SharedPreferences.setMockInitialValues({});
      await AppStore.load(); // first launch seeds + persists

      // A fresh load (same prefs) must restore the seeded rows, not re-seed.
      final reloaded = await AppStore.load();
      expect(reloaded.sources, isNotEmpty);
      expect(reloaded.favorites, isNotEmpty);
      expect(reloaded.favoriteFolders, isNotEmpty);
      expect(reloaded.history, isNotEmpty);
      expect(reloaded.currentSourceId, reloaded.sources.first.id);
    });

    test('a real first launch starts with a source but no history', () async {
      // The shipping default: no sample history or favourite, because a row the
      // user never watched is indistinguishable from one they did.
      AppStore.seedSampleUserData = false;
      addTearDown(() => AppStore.seedSampleUserData = true);

      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();

      expect(store.sources, hasLength(1), reason: 'a source to point at');
      expect(store.history, isEmpty);
      expect(store.favorites, isEmpty);
      expect(store.favoriteFolders, isEmpty);
    });

    test('fixture rows left by an older build are dropped, real ones stay', () async {
      AppStore.seedSampleUserData = false;
      addTearDown(() => AppStore.seedSampleUserData = true);

      SharedPreferences.setMockInitialValues({
        'seeded': true,
        'history': jsonEncode([
          {
            'key': 'src|nodejs_jianpian|575987',
            'sourceId': 'src',
            'title': '谷雨',
            'poster': 'https://img.example/gy.webp',
            'episode': '第01集',
            'episodeIndex': 0,
            'positionMs': 72823,
            'durationMs': 2776586,
            'updatedAt': 1795177232674,
          },
          {
            'key': 'src|nodejs_jianpian|575857',
            'sourceId': 'src',
            'title': '尚公主',
            'poster': 'assets/demo/cont0.webp',
            'episode': '第39集',
            'episodeIndex': 38,
            'positionMs': 31840,
            'durationMs': 2905400,
            'updatedAt': 1795135664669,
          },
        ]),
        'favorites': jsonEncode([
          {
            'key': 'src|nodejs_jianpian|575252',
            'sourceId': 'src',
            'title': '欢迎来龙餐馆',
            'poster': 'assets/demo/b0.jpg',
            'vodId': '575252',
            'folderId': '1795101875822513',
            'addedAt': 1795101878495,
          },
        ]),
        'favoriteFolders': jsonEncode([
          {'id': '1795101875822513', 'name': '好看的电影'},
        ]),
      });

      final store = await AppStore.load();

      expect(store.history.map((e) => e.title), ['谷雨']);
      expect(store.favorites, isEmpty);
      expect(
        store.favoriteFolders,
        isEmpty,
        reason: 'the sample folder held nothing but the sample favourite',
      );
    });

    test('visibleFavorites returns all when no folder selected', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      // Seed has one favourite; no folder selected => all visible.
      expect(store.visibleFavorites, hasLength(1));
    });

    test('visibleFavorites filters by selected folder', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      final folderId = store.favoriteFolders.first.id;

      // Add a second favourite in a different folder.
      await store.toggleFavorite(
        _fav(
          key: 'src|nodejs_jianpian|10',
          title: '另一部',
          folderId: 'other-folder',
        ),
      );

      store.setFavoriteFolder(folderId);
      expect(store.visibleFavorites, hasLength(1));
      expect(store.visibleFavorites.first.title, '欢迎来龙餐馆');

      store.setFavoriteFolder(null);
      expect(store.visibleFavorites, hasLength(2));
    });

    test('toggleFavorite adds then removes an entry', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      final entry = _fav(key: 'src|nodejs_jianpian|11', title: '临时收藏');

      await store.toggleFavorite(entry);
      expect(store.favorites.any((e) => e.key == entry.key), isTrue);

      await store.toggleFavorite(entry);
      expect(store.favorites.any((e) => e.key == entry.key), isFalse);
    });

    test('clearHistory empties the list', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      expect(store.history, isNotEmpty);

      await store.clearHistory();
      expect(store.history, isEmpty);
    });

    test('continueWatching derives from history and clears with it', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      expect(store.continueWatching, isNotEmpty);
      expect(store.continueWatching.first.episodeLabel, '第39集');
      expect(store.continueWatching.first.media.title, '尚公主');

      await store.clearHistory();
      expect(store.continueWatching, isEmpty);
    });

    test('updateSettings persists and survives reload', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      await store.updateSettings(
        store.settings.copyWith(liquidGlass: false, adaptiveColor: true),
      );
      expect(store.settings.liquidGlass, isFalse);
      expect(store.settings.adaptiveColor, isTrue);

      final reloaded = await AppStore.load();
      expect(reloaded.settings.liquidGlass, isFalse);
      expect(reloaded.settings.adaptiveColor, isTrue);
    });

    test('selectSource switches current and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      final firstId = store.currentSourceId;

      // Add a second source so there is something to switch to.
      await store.selectSource('another-source');
      expect(store.currentSourceId, 'another-source');

      // Reloading from the same prefs restores the selection.
      final reloaded = await AppStore.load();
      expect(reloaded.currentSourceId, 'another-source');

      // Switching back to the seed id still works.
      await reloaded.selectSource(firstId!);
      expect(reloaded.currentSourceId, firstId);
    });

    test('createFavoriteFolder adds a folder with a fresh id', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      final before = store.favoriteFolders.length;

      await store.createFavoriteFolder('新收藏夹');
      expect(store.favoriteFolders, hasLength(before + 1));
      expect(store.favoriteFolders.last.name, '新收藏夹');
      expect(store.favoriteFolders.last.id, isNotEmpty);
    });

    test('renameFavoriteFolder renames in place', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      final id = store.favoriteFolders.first.id;

      await store.renameFavoriteFolder(id, '重命名后');
      expect(store.favoriteFolders.first.name, '重命名后');
      expect(store.favoriteFolders.first.id, id);
    });

    test(
      'deleteFavoriteFolder removes it and returns favourites to uncategorised',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = await AppStore.load();
        final folderId = store.favoriteFolders.first.id;
        // The seed favourite already belongs to this folder.
        expect(store.favorites.first.folderId, folderId);

        // Select the folder, then delete it.
        store.setFavoriteFolder(folderId);
        await store.deleteFavoriteFolder(folderId);

        expect(store.favoriteFolders, isEmpty);
        expect(store.favorites.first.folderId, isNull);
        // Active filter resets to 全部 after the folder disappears.
        expect(store.favoriteFolderId, isNull);
      },
    );

    test(
      'putHistory upserts by key (same key updates, new key prepends)',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = await AppStore.load();

        final first = _entry(key: 'src|nodejs_jianpian|5', title: 'A');
        await store.putHistory(first);
        await store.putHistory(
          _entry(key: 'src|nodejs_jianpian|6', title: 'B'),
        );

        // New entry prepends.
        expect(store.history.first.title, 'B');
        expect(store.history, hasLength(3)); // demo + A + B

        // Upsert same key updates in place without growing the list.
        await store.putHistory(
          _entry(key: 'src|nodejs_jianpian|6', title: 'B2'),
        );
        expect(store.history, hasLength(3));
        expect(store.history.first.title, 'B2');
      },
    );

    test(
      'removeHistory drops one entry and persists; absent key is a no-op',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = await AppStore.load();
        // Add an extra entry so removing one leaves the list non-empty (and the
        // first-launch seed does not kick back in on reload).
        await store.putHistory(
          _entry(key: 'src|nodejs_jianpian|7', title: 'Extra'),
        );
        final before = store.history.length;
        const targetKey = 'src|nodejs_jianpian|7';

        await store.removeHistory(targetKey);
        expect(store.history, hasLength(before - 1));
        expect(store.history.any((e) => e.key == targetKey), isFalse);

        // Reload restores the deletion.
        final reloaded = await AppStore.load();
        expect(reloaded.history.any((e) => e.key == targetKey), isFalse);

        // Removing an unknown key leaves the list unchanged.
        await store.removeHistory('no-such-key');
        expect(store.history, hasLength(before - 1));
      },
    );

    test('clearing history does not re-seed demo data on reload', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      expect(store.history, isNotEmpty); // demo seeded on first launch

      await store.clearHistory();
      expect(store.history, isEmpty);

      // The first-launch flag is now set, so an empty history stays empty.
      final reloaded = await AppStore.load();
      expect(reloaded.history, isEmpty);
    });

    test('resumePointFor returns the saved position and its total', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      // The demo history seeds 尚公主 at episodeIndex 38, positionMs 31840.
      const item = MediaItem(id: '575857', title: '尚公主');

      final resumed = store.resumePointFor(item, episodeIndex: 38);
      expect(resumed?.positionMs, 31840);
      // The total rides along: the player needs it to reject a position that
      // was recorded on a different cut.
      expect(resumed?.totalMs, 2905400);

      // A different episode has no saved position.
      expect(store.resumePointFor(item, episodeIndex: 0), isNull);

      // A different title has none either.
      expect(
        store.resumePointFor(
          const MediaItem(id: 'x', title: '不存在的剧'),
          episodeIndex: 38,
        ),
        isNull,
      );
    });

    test('resumePointFor skips a position watched to the end', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      await store.putHistory(
        _entry(
          key: 'src|nodejs_jianpian|99',
          title: '看完了',
          episodeIndex: 1,
          positionMs: 100000,
          durationMs: 100000,
        ),
      );
      expect(
        store.resumePointFor(
          const MediaItem(id: '99', title: '看完了'),
          episodeIndex: 1,
        ),
        isNull,
      );
    });

    test('a row recorded during a pre-roll is not replayed as a position',
        () async {
      // The ad-polluted row: 5s into what the session thought was a 15s
      // stream. The store can only check the row against itself, so it hands
      // the pair over; the player, which learns the real 45-minute duration,
      // is what refuses it and starts from the head instead.
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      await store.putHistory(
        _entry(
          key: 'src|nodejs_jianpian|98',
          title: '有贴片的片',
          episodeIndex: 0,
          positionMs: 5000,
          durationMs: 15000,
        ),
      );

      final point = store.resumePointFor(
        const MediaItem(id: '98', title: '有贴片的片'),
        episodeIndex: 0,
      );
      expect(point?.positionMs, 5000);
      expect(point?.totalMs, 15000);
      expect(
        resolveResume(point!, const Duration(minutes: 45)),
        isNull,
      );
    });

    test('recordPlayback upserts a history row with the saved position',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();

      // A series episode, on a real record carrying a site key.
      await store.recordPlayback(
        const MediaItem(
          id: '575857',
          title: '尚公主',
          siteKey: 'nodejs_jianpian',
          episodes: ['第1集', '第2集', '第3集'],
        ),
        episodeIndex: 1,
        positionMs: 45000,
        durationMs: 2700000,
        lineName: 'LZ线路',
      );

      final row = store.history.firstWhere((e) => e.vodId == '575857');
      expect(row.title, '尚公主');
      expect(row.episodeIndex, 1);
      expect(row.episode, '第2集');
      expect(row.positionMs, 45000);
      expect(row.durationMs, 2700000);
      expect(row.flag, 'LZ线路');
      expect(row.siteKey, 'nodejs_jianpian');

      // 续播 now resolves from the recorded row, total included.
      final resume = store.resumePointFor(
        const MediaItem(id: '575857', title: '尚公主'),
        episodeIndex: 1,
      );
      expect(resume?.positionMs, 45000);
      expect(resume?.totalMs, 2700000);
    });

    test('savePlaybackPrefs remembers the volume and speed', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      expect(store.settings.playerVolume, 100);
      expect(store.settings.playerRate, 1.0);

      await store.savePlaybackPrefs(volume: 45, rate: 1.25);
      expect(store.settings.playerVolume, 45);
      expect(store.settings.playerRate, 1.25);

      // Survives a restart: the next episode opens the way this one ended.
      final reloaded = await AppStore.load();
      expect(reloaded.settings.playerVolume, 45);
      expect(reloaded.settings.playerRate, 1.25);
    });

    test('track picks are remembered per line and survive a reload', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      expect(store.trackPrefsFor('575857|LZ线路').isEmpty, isTrue);

      await store.saveTrackPrefs(
        '575857|LZ线路',
        const TrackPrefs(audio: '2', subtitle: 'no'),
      );
      // Another line is a different memory, not a shared one.
      expect(store.trackPrefsFor('575857|快线').isEmpty, isTrue);

      final pick = store.trackPrefsFor('575857|LZ线路');
      expect(pick.audio, '2');
      expect(pick.subtitle, 'no');
      expect(pick.video, isNull);

      final reloaded = await AppStore.load();
      expect(reloaded.trackPrefsFor('575857|LZ线路').audio, '2');
      expect(reloaded.trackPrefsFor('575857|LZ线路').subtitle, 'no');
      expect(reloaded.trackPrefsFor('575857|快线').isEmpty, isTrue);
    });

    test('clearing every pick removes the entry instead of storing nulls', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      await store.saveTrackPrefs(
        'x|线路',
        const TrackPrefs(audio: '2'),
      );
      await store.saveTrackPrefs('x|线路', TrackPrefs.empty);

      expect(store.settings.trackPrefs.containsKey('x|线路'), isFalse);
      expect(store.trackPrefsFor('x|线路').isEmpty, isTrue);
    });

    test('an empty key is ignored rather than written under ""', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      await store.saveTrackPrefs('', const TrackPrefs(audio: '1'));
      expect(store.settings.trackPrefs, isEmpty);
    });

    test('resume survives a reload with its total intact', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      await store.recordPlayback(
        const MediaItem(id: '777', title: '跨重启'),
        episodeIndex: null,
        positionMs: 90000,
        durationMs: 2400000,
        lineName: '',
      );

      final reloaded = await AppStore.load();
      final point = reloaded.resumePointFor(
        const MediaItem(id: '777', title: '跨重启'),
      );
      expect(point?.positionMs, 90000);
      expect(point?.totalMs, 2400000);
    });

    test('recordPlayback labels a film with its own title', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();

      await store.recordPlayback(
        const MediaItem(id: '575252', title: '欢迎来龙餐馆'),
        episodeIndex: null, // film
        positionMs: 120000,
        durationMs: 5400000,
        lineName: '',
      );

      final row = store.history.firstWhere((e) => e.vodId == '575252');
      expect(row.episode, '欢迎来龙餐馆');
      expect(row.episodeIndex, 0);
      expect(row.flag, isNull);
    });

    test('HistoryEntry round-trips the cross-source locators', () {
      // The original stores sourceUrl/sourceType/sourceName next to each row so
      // a title can be resumed after the active source changes.
      const entry = HistoryEntry(
        key: 'src|nodejs_jianpian|575857',
        sourceId: 'src',
        title: '尚公主',
        poster: '',
        episode: '第39集',
        episodeIndex: 38,
        positionMs: 31840,
        durationMs: 2905400,
        updatedAt: 1794472323204,
        siteKey: 'nodejs_jianpian',
        vodId: '575857',
        flag: 'LZ线路',
        sourceName: '豆儿猫源',
        sourceUrl: 'https://example.com/douer/index.js.md5',
        sourceType: 'tvbox',
      );

      final back = HistoryEntry.fromJson(entry.toJson());
      expect(back.sourceUrl, 'https://example.com/douer/index.js.md5');
      expect(back.sourceType, 'tvbox');
      expect(back.sourceName, '豆儿猫源');
      expect(back.flag, 'LZ线路');
    });

    test('HistoryEntry survives rows written before the locators existed', () {
      // Older writes have no sourceUrl/sourceType: they must not throw.
      final legacy = {
        'key': 'src|site|1',
        'sourceId': 'src',
        'title': '尚公主',
        'poster': '',
        'episode': '第1集',
        'episodeIndex': 0,
        'positionMs': 0,
        'durationMs': 0,
        'updatedAt': 0,
        'payload': <String, dynamic>{},
      };
      final entry = HistoryEntry.fromJson(legacy);
      expect(entry.sourceUrl, isNull);
      expect(entry.sourceType, isNull);
    });

    // -----------------------------------------------------------------------
    // Sources -> sites: the junction every page reads from
    // -----------------------------------------------------------------------

    test('the home site resolves to the name the header shows', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();

      // `homeSite` mirrors the original's field, and the name comes from the
      // config rather than a literal in the header.
      expect(store.sources.first.homeSite, 'nodejs_jianpian');
      expect(store.homeSite?.key, 'nodejs_jianpian');
      expect(store.homeSite?.name, '「直」荐片');

      // Cards carry their own key now that they come from the source, so the
      // store only has to resolve one to a display name.
      expect(store.siteNameOfKey('nodejs_jianpian'), '「直」荐片');
      expect(store.siteNameOfKey('gone', fallback: '某站'), '某站');

      // The fixture rails are off at runtime: nothing here invents content.
      expect(store.heroItems, isEmpty);
      expect(store.homeSections, isEmpty);
    });

    test('a disabled home site falls back to the first enabled one', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      final id = store.sources.first.id;

      await store.toggleSite(id, 'nodejs_jianpian');
      expect(store.homeSite?.key, 'nodejs_duoduo');

      // Picking another site persists and reaches the cards.
      await store.selectHomeSite('nodejs_jianpian');
      expect(
        store.homeSite?.key,
        'nodejs_duoduo',
        reason: 'homeSite still points at a silenced site',
      );

      await store.toggleSite(id, 'nodejs_jianpian');
      await store.selectHomeSite('nodejs_guazi');
      final reloaded = await AppStore.load();
      expect(reloaded.sources.first.homeSite, 'nodejs_guazi');
      expect(reloaded.homeSite?.name, '「直」瓜子');
    });

    test('history resolves its site key to a display name', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();

      final name = store.siteNameOf(
        '1794457036493149',
        'nodejs_jianpian',
        fallback: '豆儿猫源',
      );
      expect(name, '「直」荐片');
      // Unknown key / unknown source keep the fallback instead of a raw key.
      expect(
        store.siteNameOf('1794457036493149', 'gone', fallback: '豆儿猫源'),
        '豆儿猫源',
      );
      expect(
        store.siteNameOf('no-such-source', 'nodejs_jianpian', fallback: '源'),
        '源',
      );
    });

    test(
      'the seeded source carries the 59 sites its config declares',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = await AppStore.load();

        expect(store.sources.first.sites, hasLength(59));
        expect(store.activeSites, hasLength(59));
        // The bundle's first meta block, not a made-up name.
        expect(store.activeSites.first.name, '「盘」多多');
        expect(store.activeSites.first.key, 'nodejs_duoduo');
        // The site the original's history rows point at has to be in there.
        expect(
          store.activeSites.any((site) => site.key == 'nodejs_jianpian'),
          isTrue,
        );
        expect(store.sitesForSelection(null), hasLength(59));
      },
    );

    test('silencing a site drops it from the fan-out and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      final id = store.sources.first.id;

      await store.toggleSite(id, 'nodejs_wanou');
      expect(store.activeSites, hasLength(58));
      expect(
        store.activeSites.any((site) => site.key == 'nodejs_wanou'),
        isFalse,
      );
      // What search actually fans out over shrinks with it.
      expect(store.sitesForSelection(null), hasLength(58));

      final reloaded = await AppStore.load();
      expect(reloaded.activeSites, hasLength(58));

      await reloaded.toggleSite(id, 'nodejs_wanou');
      expect(reloaded.activeSites, hasLength(59));
    });

    test('a pasted source joins the fan-out and leaves when deleted', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();

      final id = await store.addSource(
        const SourceInfo(
          id: 'pasted-1',
          type: 'tvbox',
          name: '粘贴的源',
          url: '',
          sites: [SiteInfo(key: 'p1', name: '我自己的站')],
        ),
      );
      expect(id, 'pasted-1');
      // With every source selected both configs contribute.
      expect(store.sitesForSelection(null), hasLength(60));
      expect(store.sitesForSelection({'pasted-1'}).single.name, '我自己的站');

      await store.removeSource('pasted-1');
      expect(store.sitesForSelection(null), hasLength(59));
      expect(store.sources.any((source) => source.id == 'pasted-1'), isFalse);
    });

    test('deleting the active source falls back to the next one', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      await store.addSource(
        const SourceInfo(id: 'b', type: 'tvbox', name: 'B', url: ''),
      );
      await store.selectSource('b');
      expect(store.currentSourceId, 'b');

      await store.removeSource('b');
      expect(store.sources.any((source) => source.id == 'b'), isFalse);
      expect(store.currentSourceId, store.sources.first.id);
    });

    test('SourceInfo round-trips sites and tolerates sources without any', () {
      const source = SourceInfo(
        id: 's',
        type: 'tvbox',
        name: '源',
        url: '',
        sites: [SiteInfo(key: 'a', name: '甲', type: '3', api: 'x')],
      );
      final back = SourceInfo.fromJson(source.toJson());
      expect(back.sites, hasLength(1));
      expect(back.sites.single.name, '甲');
      expect(back.sites.single.api, 'x');
      expect(back.sites.single.enabled, isTrue);

      // A source written before sites existed has no `sites` key at all.
      final legacy = SourceInfo.fromJson({
        'id': 'old',
        'type': 'tvbox',
        'name': '老源',
        'url': 'u',
      });
      expect(legacy.sites, isEmpty);
      expect(legacy.searchableSites, isEmpty);
    });

    test('replaceSites swaps the list but keeps the other fields', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      final before = store.sources.first;

      await store.replaceSites(before.id, const [
        SiteInfo(key: 'x', name: '新站'),
      ]);
      final after = store.sources.first;
      expect(after.sites.single.name, '新站');
      expect(after.name, before.name);
      expect(after.url, before.url);
      expect(after.movieCount, before.movieCount);
    });

    test(
      'a source written before sites existed is backfilled on upgrade',
      () async {
        // Legacy shape: the seeded id, no `sites` key, and the seed flag already
        // set so the first-launch path does not run. Without the migration the
        // fan-out would be empty for anyone who had run the previous build.
        SharedPreferences.setMockInitialValues({
          'seeded': true,
          'sources': jsonEncode([
            {
              'id': '1794457036493149',
              'type': 'tvbox',
              'name': '豆儿猫源',
              'url': 'https://example.com/douer/index.js.md5',
            },
          ]),
        });

        final store = await AppStore.load();
        expect(store.sources.first.sites, hasLength(59));
        expect(store.activeSites, hasLength(59));

        // The backfill is written back rather than recomputed every launch.
        final reloaded = await AppStore.load();
        expect(reloaded.sources.first.sites, hasLength(59));
        expect(reloaded.currentSourceId, '1794457036493149');
      },
    );

    test('a source stored before homeSite existed gets one', () async {
      // Install that already has the real 59 sites but no `homeSite`: without
      // the backfill the home chip falls back to 「盘」多多 instead of the site
      // the fixture feed actually came from.
      SharedPreferences.setMockInitialValues({
        'seeded': true,
        'sources': jsonEncode([
          {
            'id': '1794457036493149',
            'type': 'tvbox',
            'name': '豆儿猫源',
            'url': 'https://example.com/douer/index.js.md5',
            'sites': [
              {'key': 'nodejs_duoduo', 'name': '「盘」多多', 'type': '3'},
              {'key': 'nodejs_jianpian', 'name': '「直」荐片', 'type': '3'},
            ],
          },
        ]),
      });

      final store = await AppStore.load();
      expect(store.sources.first.homeSite, 'nodejs_jianpian');
      expect(store.homeSite?.name, '「直」荐片');
      // Written back, so the chip does not flip again on the next launch.
      final reloaded = await AppStore.load();
      expect(reloaded.sources.first.homeSite, 'nodejs_jianpian');
    });

    test('the twelve placeholder sites are upgraded, switches intact', () async {
      // Builds before the config bundle was mined seeded a dozen made-up names
      // (`wanou`, `naixi`, ...). They have to be replaced by the real 59 or the
      // user keeps searching a list that never existed.
      SharedPreferences.setMockInitialValues({
        'seeded': true,
        'sources': jsonEncode([
          {
            'id': '1794457036493149',
            'type': 'tvbox',
            'name': '豆儿猫源',
            'url': 'https://example.com/douer/index.js.md5',
            'sites': [
              {'key': 'wanou', 'name': '玩偶', 'type': '3', 'enabled': false},
              {'key': 'muou', 'name': '木偶', 'type': '3'},
              {'key': 'my-own', 'name': '我加的站', 'type': '3'},
            ],
          },
        ]),
      });

      final store = await AppStore.load();
      final sites = store.sources.first.sites;
      expect(sites, hasLength(60)); // 59 real + the one the user added
      expect(sites.last.name, '我加的站');
      expect(
        sites.firstWhere((site) => site.key == 'nodejs_wanou').enabled,
        isFalse,
        reason: 'a site the user silenced has to stay silenced',
      );
      expect(
        sites.firstWhere((site) => site.key == 'nodejs_muou').enabled,
        isTrue,
      );
    });
  });

  group('AppStore — 本剧片头片尾', () {
    Future<AppStore> fresh() async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      await store.updateSettings(
        store.settings.copyWith(introSkipMs: 90000, outroSkipMs: 60000),
      );
      return store;
    }

    test('没单独设过的剧用全局那一组', () async {
      final store = await fresh();
      final rule = store.skipRuleFor('三体');
      expect(rule.intro, const Duration(seconds: 90));
      expect(rule.outro, const Duration(seconds: 60));
      expect(store.skipOverrideCount, 0);
    });

    test('只改片头的那部剧，片尾还是全局的', () async {
      final store = await fresh();
      await store.setSkipOverride('三体', const SkipOverride(introMs: 15000));

      expect(store.skipRuleFor('三体').intro, const Duration(seconds: 15));
      expect(store.skipRuleFor('三体').outro, const Duration(seconds: 60));
      // 别的剧不受影响。
      expect(store.skipRuleFor('狂飙').intro, const Duration(seconds: 90));
      expect(store.skipOverrideCount, 1);
    });

    test('单独设置能跨重启留住', () async {
      final store = await fresh();
      await store.setSkipOverride('三体', const SkipOverride(introMs: 15000));

      final reloaded = await AppStore.load();
      expect(reloaded.skipOverrideFor('三体').introMs, 15000);
      expect(reloaded.skipRuleFor('三体').intro, const Duration(seconds: 15));
    });

    test('明确设 0 能让一部剧不跳，而不是回到全局', () async {
      final store = await fresh();
      await store.setSkipOverride('三体', const SkipOverride(introMs: 0));
      expect(store.skipRuleFor('三体').intro, Duration.zero);
      expect(store.skipRuleFor('三体').outro, const Duration(seconds: 60));
    });

    test('总开关关掉时本剧设置也不能绕过', () async {
      final store = await fresh();
      await store.setSkipOverride('三体', const SkipOverride(introMs: 15000));
      await store.updateSettings(
        store.settings.copyWith(skipIntroOutro: false),
      );

      expect(store.skipRuleFor('三体'), SkipRule.none);
      // 关掉不等于删掉：再打开还是原来那组。
      expect(store.skipOverrideCount, 1);
      await store.updateSettings(store.settings.copyWith(skipIntroOutro: true));
      expect(store.skipRuleFor('三体').intro, const Duration(seconds: 15));
    });

    test('清除本剧设置会整条删掉，不留空壳', () async {
      final store = await fresh();
      await store.setSkipOverride('三体', const SkipOverride(introMs: 15000));
      await store.setSkipOverride('狂飙', const SkipOverride(outroMs: 30000));
      expect(store.skipOverrideCount, 2);

      await store.setSkipOverride('三体', SkipOverride.none);
      expect(store.skipOverrideCount, 1);
      expect(store.skipRuleFor('三体').intro, const Duration(seconds: 90));

      await store.clearSkipOverrides();
      expect(store.skipOverrideCount, 0);
      expect(store.skipRuleFor('狂飙').outro, const Duration(seconds: 60));
    });

    test('作品名前后的空格不算另一部剧', () async {
      final store = await fresh();
      await store.setSkipOverride(' 三体 ', const SkipOverride(introMs: 15000));
      expect(store.skipOverrideFor('三体').introMs, 15000);
      expect(store.skipOverrideCount, 1);
    });
  });
}
