import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/store.dart';

import 'support/fake_webdav.dart';

/// A WebDAV share as seen by the store: the same four questions the pages ask
/// any source (首页 / 搜索 / 播放 / 检测), answered by a local fake share.
void main() {
  late FakeWebDav server;
  late AppStore store;

  setUp(() async {
    server = await FakeWebDav.start();
    SharedPreferences.setMockInitialValues({});
    store = await AppStore.load();
    await store.addSource(
      SourceInfo(
        id: 'dav-1',
        type: 'webdav',
        name: '家里网盘',
        url: server.url,
        username: 'lxy',
        password: 'secret',
      ),
    );
    await store.selectSource('dav-1');
  });

  tearDown(() async {
    await server.close();
  });

  test('a share counts as a mount, so 首页 draws its folders', () async {
    expect(AppStore.isMountSource(store.currentSource), isTrue);
    expect(store.hasMount, isTrue);
    expect(store.hasSpiderHome, isFalse);

    final items = await store.mountLibrary(limit: 10);
    expect(items.map((e) => e.title), ['电影', '剧集', '散装片']);
  });

  test('search fans out to the share as a single site named after it', () async {
    final groups = await store
        .searchRealStream('奥德赛', strict: false)!
        .toList();

    expect(groups, hasLength(1));
    expect(groups.single.site, '家里网盘');
    expect(groups.single.items.single.title, '奥德赛');
  });

  test('the player is handed the share credential', () async {
    expect(store.playbackHeaders['Authorization'], server.authHeader);
  });

  test('every other source needs no playback headers', () async {
    await store.selectSource(store.sources.first.id);
    expect(store.playbackHeaders, isEmpty);
  });

  test('检测 writes the share numbers onto the card', () async {
    final report = await store.probeSource(store.currentSource!, '');

    expect(report.ok, isTrue, reason: report.error);
    final source = store.sources.firstWhere((s) => s.id == 'dav-1');
    // One loose film at the root, two folders.
    expect(source.movieCount, 1);
    expect(source.showCount, 2);
    expect(source.checkedAt, greaterThan(0));
  });

  test('a share that refuses the password reports it, not an empty library', () async {
    await store.updateSource(
      store.currentSource!.copyWith(password: 'wrong'),
    );
    final report = await store.probeSource(store.currentSource!, '');

    expect(report.ok, isFalse);
    expect(report.error, '账号或密码不对');
    // The card must not keep claiming titles it could not read.
    final source = store.sources.firstWhere((s) => s.id == 'dav-1');
    expect(source.movieCount, 0);
    expect(source.showCount, 0);
  });

  test('a share answers detail with one line of episodes', () async {
    final items = await store.mountLibrary(limit: 10);
    final show = items.firstWhere((e) => e.title == '剧集');
    final detail = await store.detailReal(show);

    expect(detail, isNotNull);
    expect(detail!.episodes, ['第1集', '第2集', '第10集']);
    expect(detail.playLines.single.episodes, hasLength(3));
  });

  test('a share has nothing to do with spider search', () async {
    // No cat host is attached: the mount path must answer regardless.
    expect(store.spider, isNull);
    expect(store.canSearchReal, isTrue);
    final groups = await store.searchRealStream('散装')!.toList();
    expect(groups.single.items.single.title, '散装片');
  });
}
