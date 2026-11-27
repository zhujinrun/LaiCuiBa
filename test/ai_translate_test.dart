import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/ai/subtitle_translate.dart';

void main() {
  test('用本地 OpenAI 兼容接口翻译，行数保持一一对应', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind('127.0.0.1', 0);
    String? seenAuth;
    String? seenBody;
    server.listen((request) {
      seenAuth = request.headers.value('authorization');
      request.cast<List<int>>().transform(utf8.decoder).join().then((body) {
        seenBody = body;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '你好世界\n第二行'},
              },
            ],
          }),
        );
        request.response.close();
      });
    });

    try {
      final translated = await AiSubtitleTranslator.translate(
        ['Hello world', 'Second line'],
        AiTranslationConfig(
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
          model: 'test-model',
          apiKey: 'secret',
          targetLang: '简体中文',
        ),
      );
      expect(translated, ['你好世界', '第二行']);
      expect(seenAuth, 'Bearer secret');
      expect(jsonDecode(seenBody!)['model'], 'test-model');
    } finally {
      await server.close();
    }
  });

  test('没配 Key 时不发请求，直接说要配置', () async {
    await expectLater(
      AiSubtitleTranslator.translate(
        ['Hello'],
        const AiTranslationConfig(
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-4o-mini',
          apiKey: '',
          targetLang: '简体中文',
        ),
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          '请先到设置配置 AI 大模型和 API Key',
        ),
      ),
    );
  });
}
