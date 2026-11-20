import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/store.dart';

HistoryEntry _entry({
  String key = 'src|nodejs_jianpian|1',
  String title = '尚公主',
  bool favorite = false,
  bool following = false,
  int positionMs = 31840,
  int durationMs = 2905400,
}) {
  return HistoryEntry(
    key: key,
    sourceId: 'src',
    title: title,
    poster: '',
    episode: '第39集',
    episodeIndex: 38,
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
      'seeds demo source, history, folder and favourite on first launch',
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

    test('seeded demo data survives a relaunch', () async {
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

    test('removeHistory drops one entry and persists; absent key is a no-op',
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
    });

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
  });
}
