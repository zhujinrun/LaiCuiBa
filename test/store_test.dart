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
  });
}
