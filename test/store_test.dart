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
    test('seeds demo source and history on first launch', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();

      expect(store.sources, isNotEmpty);
      expect(store.sources.first.name, '豆儿猫源');
      expect(store.history, isNotEmpty);
      expect(store.history.first.title, '尚公主');
      expect(store.currentSourceId, store.sources.first.id);
    });

    test('favorites filters only flagged history entries', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      // Seed has one history entry with no favorite flag.
      expect(store.favorites, isEmpty);

      await store.putHistory(_entry(
        key: 'src|nodejs_jianpian|2',
        title: '欢迎来龙餐馆',
        favorite: true,
      ));
      expect(store.favorites, hasLength(1));
      expect(store.favorites.first.title, '欢迎来龙餐馆');
    });

    test('following filters only following-flagged entries', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      expect(store.following, isEmpty);

      await store.putHistory(_entry(
        key: 'src|nodejs_jianpian|3',
        title: '追更剧',
        following: true,
      ));
      expect(store.following, hasLength(1));
      expect(store.favorites, isEmpty);
    });

    test('toggleFavorite flips the flag and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      await store.putHistory(_entry(key: 'src|nodejs_jianpian|4'));
      final key = 'src|nodejs_jianpian|4';

      expect(store.favorites, isEmpty);
      await store.toggleFavorite(key);
      expect(store.favorites, hasLength(1));

      await store.toggleFavorite(key);
      expect(store.favorites, isEmpty);
    });

    test('clearHistory empties the list', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();
      expect(store.history, isNotEmpty);

      await store.clearHistory();
      expect(store.history, isEmpty);
    });

    test('putHistory upserts by key (same key updates, new key prepends)', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();

      final first = _entry(key: 'src|nodejs_jianpian|5', title: 'A');
      await store.putHistory(first);
      await store.putHistory(_entry(key: 'src|nodejs_jianpian|6', title: 'B'));

      // New entry prepends.
      expect(store.history.first.title, 'B');
      expect(store.history, hasLength(3)); // demo + A + B

      // Upsert same key updates in place without growing the list.
      await store.putHistory(_entry(key: 'src|nodejs_jianpian|6', title: 'B2'));
      expect(store.history, hasLength(3));
      expect(store.history.first.title, 'B2');
    });
  });
}
