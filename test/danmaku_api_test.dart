import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lai_cui_ba/services/danmaku/danmaku_api.dart';

import 'support/fake_danmaku.dart';

void main() {
  group('parseDanmaku', () {
    test('reads the JSON shape dandanplay returns', () {
      final list = parseDanmaku(jsonEncode({
        'errorCode': 0,
        'comments': [
          {'cid': 1, 'p': '12.5,1,16777215,u1', 'm': '前面的别走'},
          {'cid': 2, 'p': '13,5,16711680,u2', 'm': '顶部'},
        ],
      }));
      expect(list, hasLength(2));
      expect(list.first.timeMs, 12500);
      expect(list.first.mode, DanmakuComment.scroll);
      expect(list.first.color, 0xFFFFFF);
      expect(list[1].mode, DanmakuComment.top);
      expect(list[1].color, 0xFF0000);
      expect(list[1].text, '顶部');
    });

    test('reads the XML shape and unescapes entities', () {
      final list = parseDanmaku(
        '<i><d p="1.5,1,16777215,abc">A &amp; B &lt;3</d>'
        '<d p="2,4,65280,def">底部</d></i>',
      );
      expect(list, hasLength(2));
      expect(list.first.text, 'A & B <3');
      expect(list.last.mode, DanmakuComment.bottom);
    });

    test('drops entries whose p is truncated instead of inventing a time', () {
      final list = parseDanmaku('<i><d p="not-a-time,1,0,x">坏</d>'
          '<d p="1.0,1,0,x">好</d></i>');
      expect(list.map((c) => c.text), ['好']);
    });

    test('an unrecognised body is empty, not an exception', () {
      expect(parseDanmaku('<html>403</html>'), isEmpty);
      expect(parseDanmaku(''), isEmpty);
      expect(parseDanmaku('{"comments": "nope"}'), isEmpty);
    });

    test('unknown modes fall back to scrolling so nothing is lost', () {
      final list = parseDanmaku('<i><d p="1,7,0,x">高级弹幕</d></i>');
      expect(list.single.isScroll, isTrue);
    });
  });

  group('episodeNumber', () {
    test('reads the usual episode labels', () {
      expect(episodeNumber('第3集'), 3);
      expect(episodeNumber('EP12'), 12);
      expect(episodeNumber('三体 08'), 8);
      expect(episodeNumber('12'), 12);
    });

    test('a label with no number stays null rather than guessing 1', () {
      expect(episodeNumber('预告'), isNull);
      expect(episodeNumber(''), isNull);
      // 第 0 集不是合法集数，宁可退回文件名匹配。
      expect(episodeNumber('第0集'), isNull);
    });
  });

  group('DanmakuSource', () {
    test('keeps credentials out of the defaults', () {
      expect(DanmakuSource.builtin.hasCredentials, isFalse);
      expect(DanmakuSource.builtin.baseUrl, DanmakuSource.officialBase);
      expect(DanmakuSource.builtin.isBuiltin, isTrue);
    });

    test('a broken entry is dropped, not turned into a half source', () {
      expect(DanmakuSource.fromJson({'id': 'x'}), isNull);
      expect(DanmakuSource.fromJson({'name': 'x'}), isNull);
      expect(DanmakuSource.fromJson('nope'), isNull);
      final ok = DanmakuSource.fromJson({
        'id': 'mine',
        'name': '自建',
        'baseUrl': 'https://api.example.com/',
        'appId': 'a',
        'appSecret': 'b',
      });
      expect(ok, isNotNull);
      expect(ok!.baseUrl, 'https://api.example.com');
      expect(ok.hasCredentials, isTrue);
    });

    test('a missing baseUrl falls back to the official host', () {
      final s = DanmakuSource.fromJson({'id': 'm', 'name': 'm'})!;
      expect(s.baseUrl, DanmakuSource.officialBase);
    });
  });

  group('danmakuSignature', () {
    test('is stable for the same inputs and changes with the path', () {
      final a = danmakuSignature(
        appId: 'id',
        appSecret: 'sec',
        timestamp: 1700000000,
        path: '/api/v2/match',
      );
      final b = danmakuSignature(
        appId: 'id',
        appSecret: 'sec',
        timestamp: 1700000000,
        path: '/api/v2/match',
      );
      final c = danmakuSignature(
        appId: 'id',
        appSecret: 'sec',
        timestamp: 1700000000,
        path: '/api/v2/comment/1',
      );
      expect(a, b);
      expect(a, isNot(c));
      // base64 of a sha256 digest is always 44 chars with the trailing '='.
      expect(a, hasLength(44));
    });
  });

  group('DanmakuApi against a local server', () {
    late FakeDanmaku fake;

    tearDown(() async => fake.close());

    test('searches by title and episode, then loads that episode', () async {
      fake = await FakeDanmaku.start();
      final api = DanmakuApi(fake.source());
      addTearDown(api.close);

      final matches = await api.searchEpisodes(FakeDanmaku.anime, '3');
      expect(matches, hasLength(1));
      expect(matches.single.episodeId, FakeDanmaku.episodeId);
      expect(matches.single.label, contains('第3话'));

      final comments = await api.comments(FakeDanmaku.episodeId);
      expect(comments.map((c) => c.text), ['第一条', '顶部', '底部']);
      expect(comments.first.timeMs, 1500);

      expect(fake.requests.first, contains('/api/v2/search/episodes'));
      expect(fake.requests.last, contains('/api/v2/comment/1043721'));
      expect(fake.requests.last, contains('withRelated=false'));
    });

    test('a search with no hit returns an empty list, not an error', () async {
      fake = await FakeDanmaku.start();
      final api = DanmakuApi(fake.source());
      addTearDown(api.close);
      expect(await api.searchEpisodes('不存在的片', '99'), isEmpty);
    });

    test('/match sends fileNameOnly when there is no hash', () async {
      fake = await FakeDanmaku.start();
      final api = DanmakuApi(fake.source());
      addTearDown(api.close);
      final found = await api.matchFile(
        fileName: '${FakeDanmaku.anime} - 第03集.mp4',
        durationMs: 1440000,
      );
      expect(found, hasLength(1));
      expect(fake.requests.single, contains('/api/v2/match'));
    });

    test('parses the XML body the same way as JSON', () async {
      fake = await FakeDanmaku.start();
      fake.commentFormat = 'xml';
      final api = DanmakuApi(fake.source());
      addTearDown(api.close);
      final comments = await api.comments(FakeDanmaku.episodeId);
      expect(comments.map((c) => c.text), ['第一条 & 转义', '顶部', '底部']);
      expect(comments.first.color, 0xFFFFFF);
      expect(comments.last.mode, DanmakuComment.bottom);
    });

    test('signs requests only when credentials are configured', () async {
      fake = await FakeDanmaku.start(mode: 'signed');
      final api = DanmakuApi(fake.source(withCredentials: true));
      addTearDown(api.close);

      await api.searchEpisodes(FakeDanmaku.anime, '3');
      expect(fake.lastAuth.keys.toSet(), {'x-appid', 'x-timestamp', 'x-signature'});
      expect(fake.lastAuth['x-appid'], 'app-1');
    });

    test('a 401 becomes a sentence about AppId/AppSecret', () async {
      fake = await FakeDanmaku.start(mode: 'signed');
      final api = DanmakuApi(fake.source());
      addTearDown(api.close);

      await expectLater(
        api.searchEpisodes(FakeDanmaku.anime, '3'),
        throwsA(isA<DanmakuException>().having(
          (e) => e.message,
          'message',
          contains('AppId/AppSecret'),
        )),
      );
    });

    test('an HTML body says "not a danmaku endpoint" instead of "no hit"',
        () async {
      fake = await FakeDanmaku.start();
      fake.garbageComments = true;
      final api = DanmakuApi(fake.source());
      addTearDown(api.close);
      await expectLater(
        api.comments(1),
        throwsA(isA<DanmakuException>().having(
          (e) => e.message,
          'message',
          contains('不是弹幕接口格式'),
        )),
      );
    });
  });
}
