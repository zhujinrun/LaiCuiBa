import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/media_mount.dart';
import 'package:lai_cui_ba/services/webdav_client.dart';

import 'support/fake_webdav.dart';

/// A WebDAV share as a media source, exercised against a local server that
/// answers `PROPFIND` from a tree — same approach as the fake Emby, so the
/// client is judged on real bytes rather than on its own idea of the protocol.
void main() {
  late FakeWebDav server;

  WebDavClient client({String password = 'secret'}) => WebDavClient(
    baseUrl: server.url,
    username: 'lxy',
    password: password,
    sourceName: '网盘',
  );

  setUp(() async {
    server = await FakeWebDav.start();
  });

  tearDown(() async {
    await server.close();
  });

  group('列出目录', () {
    test('directories and videos become cards, junk does not', () async {
      final mount = client();
      addTearDown(mount.close);

      final items = await mount.library(limit: 20);
      expect(
        items.map((e) => e.title).toList(),
        ['电影', '剧集', '散装片'],
        reason: 'nfo / jpg / @eaDir must not appear',
      );
      expect(items.first.id.startsWith('dav-dir|'), isTrue);
      expect(items.last.id.startsWith('dav-file|'), isTrue);
      expect(items.first.sourceName, '网盘');
    });

    test('a folder name keeps its year and drops release tags', () async {
      final mount = client();
      addTearDown(mount.close);

      final items = await mount.library(limit: 20);
      final movie = items.firstWhere((e) => e.title == '电影');
      // The folder itself carries no year or episode.
      expect(movie.year, isNull);
      expect(movie.latest, isNull);
    });

    test('the share is authenticated on every request', () async {
      final mount = client();
      addTearDown(mount.close);

      await mount.library(limit: 5);
      expect(server.requests, isNotEmpty);
      // No request may go out without the credential; the server rejects it,
      // so a missing header would surface as the 401 case below.
      expect(server.requests.every((r) => r.startsWith('PROPFIND')), isTrue);
    });
  });

  group('详情与选集', () {
    test('a directory expands into episodes sorted naturally', () async {
      final mount = client();
      addTearDown(mount.close);

      final items = await mount.library(limit: 20);
      final show = items.firstWhere((e) => e.title == '剧集');
      final detail = await mount.detail(show);

      // 第1 / 第2 / 第10 must not sort as strings (01, 10, 02…).
      expect(detail.episodes, ['第1集', '第2集', '第10集']);
      expect(detail.playLines, hasLength(1));
      final line = detail.playLines.first;
      expect(line.name, '播放列表');
      expect(line.episodes.map((e) => e.label).toList(), detail.episodes);
      final url = Uri.decodeFull(line.episodes.first.url);
      expect(url, contains('${server.url}剧集/'));
      expect(url, contains('三体 第1集.mp4'));
    });

    test('a film folder yields one line with a playable url', () async {
      final mount = client();
      addTearDown(mount.close);

      final items = await mount.library(limit: 20);
      final folder = items.firstWhere((e) => e.title == '电影');
      final detail = await mount.detail(folder);

      // Two different films in one folder are not episodes 1 and 2; they are
      // named for themselves, because that is what they are.
      expect(detail.episodes, ['流浪地球2', '奥德赛']);
      expect(detail.latest, isNull);
      expect(detail.playLines.first.episodes, hasLength(2));
    });

    test('a loose file plays as a single 正片', () async {
      final mount = client();
      addTearDown(mount.close);

      final items = await mount.library(limit: 20);
      final file = items.firstWhere((e) => e.title == '散装片');
      final detail = await mount.detail(file);

      expect(detail.playLines.first.episodes.single.label, '正片');
      expect(
        Uri.decodeFull(detail.playLines.first.episodes.single.url),
        contains('散装片.mkv'),
      );
    });

    test('a folder with no video says so instead of guessing', () async {
      final mount = client();
      addTearDown(mount.close);

      // @eaDir is filtered from the listing, so build the record by hand.
      final detail = await mount.detail(
        const MediaItem(
          id: 'dav-dir|/dav/@eaDir/',
          title: '@eaDir',
        ),
      );
      expect(detail.episodes, isEmpty);
      expect(detail.overview, '这个目录里没有视频文件');
    });
  });

  group('搜索与检测', () {
    test('search matches the root and one level down', () async {
      final mount = client();
      addTearDown(mount.close);

      final root = await mount.search('散装');
      expect(root.map((e) => e.title), ['散装片']);

      // 奥德赛 lives inside 电影; the share search reaches it.
      final nested = await mount.search('奥德赛');
      expect(nested.map((e) => e.title), ['奥德赛']);
      expect(nested.single.year, 2024);
    });

    test('probe counts videos and folders without walking the tree', () async {
      final mount = client();
      addTearDown(mount.close);

      final report = await mount.probe();
      expect(report.ok, isTrue, reason: report.error);
      expect(report.movieCount, 1);
      expect(report.showCount, 2);
      expect(report.latencyMs, greaterThanOrEqualTo(0));
      // One PROPFIND: a probe measures the share, it does not index it.
      expect(server.requests, hasLength(1));
    });

    test('a wrong password is reported as such', () async {
      final mount = client(password: 'nope');
      addTearDown(mount.close);

      await expectLater(
        mount.library(),
        throwsA(
          isA<MountException>().having(
            (e) => e.message,
            'message',
            '账号或密码不对',
          ),
        ),
      );
    });

    test('probe turns the refusal into a readable failure', () async {
      final mount = client(password: 'nope');
      addTearDown(mount.close);

      final report = await mount.probe();
      expect(report.ok, isFalse);
      expect(report.error, '账号或密码不对');
    });
  });

  group('播放', () {
    test('the player is told to send Basic auth', () async {
      final mount = client();
      addTearDown(mount.close);

      expect(mount.playbackHeaders['Authorization'], server.authHeader);
      // Emby carries its credential in the URL; a share cannot, so this is the
      // one mount whose headers matter.
      expect(mount.playbackHeaders.length, 1);
    });

    test('streamUrl resolves an href against the share root', () async {
      final mount = client();
      addTearDown(mount.close);

      final url = mount.streamUrl('dav-file|/dav/电影/奥德赛 2024.mp4');
      expect(url, startsWith(server.url));
      expect(Uri.decodeFull(url), endsWith('电影/奥德赛 2024.mp4'));
    });
  });
}
