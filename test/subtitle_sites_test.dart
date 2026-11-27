import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/subtitle/sites.dart';
import 'package:lai_cui_ba/ui/widgets/subtitle_search_dialog.dart';

void main() {
  test('字幕网站搜索与下载都走真 HTTP，结果落到本机文件', () async {
    HttpOverrides.global = null;
    final dir = Directory.systemTemp.createTempSync('lcb_subs_');
    SubtitleSiteService.directoryOverride = dir;
    final server = await HttpServer.bind('127.0.0.1', 0);
    final base = 'http://127.0.0.1:${server.port}';
    server.listen((request) {
      if (request.uri.path == '/search') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'results': [
              {
                'title': '测试字幕',
                'url': '$base/sub.srt',
                'language': 'zh-CN',
              },
            ],
          }),
        );
      } else {
        request.response.headers.contentType = ContentType('text', 'plain', charset: 'utf-8');
        request.response.write('1\n00:00:00,000 --> 00:00:02,000\n你好\n');
      }
      request.response.close();
    });

    try {
      final site = SubtitleSite(
        id: 's1',
        name: '测试站',
        urlTemplate: '$base/search?q={query}',
      );
      final hits = await SubtitleSiteService.search(site, '一部电影');
      expect(hits.length, 1);
      expect(hits.single.title, '测试字幕');
      expect(hits.single.language, 'zh-CN');

      final file = await SubtitleSiteService.download(hits.single);
      expect(file.existsSync(), isTrue);
      expect(await file.readAsString(), contains('你好'));
    } finally {
      await server.close();
      SubtitleSiteService.directoryOverride = null;
      dir.deleteSync(recursive: true);
    }
  });

  testWidgets('没有配字幕网站时按原版说明，不塞假结果', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SubtitleSearchDialog(sites: [])),
      ),
    );
    expect(find.text('没有可用的字幕网站，点这里设置'), findsOneWidget);
    expect(
      find.text(
        '字幕来自公开的字幕网站，仅供个人学习使用。下载后记在这一集上，下次播放自动挂上。',
      ),
      findsOneWidget,
    );
  });
}
