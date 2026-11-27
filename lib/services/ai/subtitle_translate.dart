import 'dart:convert';
import 'dart:io';

/// AI 字幕翻译：只走用户自己填的 OpenAI 兼容接口。
/// Key 不随应用分发，也不进备份；没填就别发请求。
class AiTranslationConfig {
  const AiTranslationConfig({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    required this.targetLang,
  });

  final String baseUrl;
  final String model;
  final String apiKey;
  final String targetLang;

  bool get ready => apiKey.trim().isNotEmpty && baseUrl.trim().isNotEmpty;
}

class AiSubtitleTranslator {
  AiSubtitleTranslator._();

  static const maxLinesPerRequest = 20;

  static Future<List<String>> translate(
    List<String> lines,
    AiTranslationConfig config,
  ) async {
    if (lines.isEmpty) return const [];
    if (!config.ready) {
      throw const FormatException('请先到设置配置 AI 大模型和 API Key');
    }
    final result = <String>[];
    for (var start = 0; start < lines.length; start += maxLinesPerRequest) {
      final batch = lines.sublist(
        start,
        (start + maxLinesPerRequest).clamp(0, lines.length),
      );
      result.addAll(await _batch(batch, config));
    }
    return result;
  }

  static Future<List<String>> _batch(
    List<String> lines,
    AiTranslationConfig config,
  ) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    final uri = Uri.parse(
      '${config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '')}/chat/completions',
    );
    final body = jsonEncode({
      'model': config.model.trim().isEmpty ? 'gpt-4o-mini' : config.model.trim(),
      'temperature': 0.2,
      'messages': [
        {
          'role': 'system',
          'content':
              'Translate each subtitle line into ${config.targetLang}. '
              'Keep the same number of lines and the original order. '
              'Output only the translations, one per line, without numbering.',
        },
        {'role': 'user', 'content': lines.join('\n')},
      ],
    });
    try {
      final request = await client.postUrl(uri);
      request.headers
        ..set('content-type', 'application/json')
        ..set('authorization', 'Bearer ${config.apiKey.trim()}');
      final bytes = utf8.encode(body);
      request.headers.set('content-length', bytes.length);
      request.add(bytes);
      final response = await request.close().timeout(const Duration(seconds: 30));
      final raw = await response.transform(utf8.decoder).join();
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const FormatException('AI API Key 无效或没有权限');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw FormatException('AI 翻译失败，HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(raw);
      final choices = decoded is Map ? decoded['choices'] : null;
      final first = choices is List && choices.isNotEmpty ? choices[0] : null;
      final message = first is Map ? first['message'] : null;
      final content = message is Map ? message['content'] : null;
      if (content is! String) {
        throw const FormatException('AI 没有给出翻译内容');
      }
      final translated = content
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (translated.length != lines.length) {
        throw const FormatException('AI 翻译返回的行数不对，已经丢弃这一批');
      }
      return translated;
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw FormatException('AI 翻译接口打不开：$error');
    } finally {
      client.close();
    }
  }
}
