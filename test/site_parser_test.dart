import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/site_parser.dart';

void main() {
  group('parseConfig', () {
    test('reads a standard catvod config', () {
      const config = '''
{
  "sites": [
    {"key": "wanou", "name": "玩偶", "type": 3, "api": "csp_WanOu", "searchable": 1},
    {"key": "muou", "name": "木偶", "type": 3, "api": "csp_MuOu"}
  ],
  "lives": [{"name": "央视", "url": "http://example.com/live.txt"}]
}
''';
      final result = parseConfig(config);
      expect(result.ok, isTrue, reason: result.error);
      expect(result.count, 2);
      expect(result.sites.map((s) => s.name), ['玩偶', '木偶']);
      expect(result.sites.first.key, 'wanou');
      // `type` arrives as an int in the document and is kept as text.
      expect(result.sites.first.type, '3');
      expect(result.sites.every((s) => s.enabled), isTrue);
    });

    test('accepts a bare site array', () {
      const config = '[{"key":"a","name":"甲"},{"key":"b","name":"乙"}]';
      final result = parseConfig(config);
      expect(result.ok, isTrue, reason: result.error);
      expect(result.count, 2);
    });

    test('accepts a nested document', () {
      const config = '{"config":{"sites":[{"key":"a","name":"甲"}]}}';
      final result = parseConfig(config);
      expect(result.ok, isTrue, reason: result.error);
      expect(result.count, 1);
    });

    test('keeps searchable:0 sites but marks them disabled', () {
      const config = '''
{"sites":[
  {"key":"a","name":"甲"},
  {"key":"b","name":"乙","searchable":0}
]}
''';
      final result = parseConfig(config);
      expect(result.count, 2, reason: 'silenced sites stay visible in the editor');
      expect(result.silenced, 1);
      expect(result.enabledCount, 1);
      expect(result.sites.last.enabled, isFalse);
    });

    test('parses one site per line in the name\$url form', () {
      const text = '玩偶\$https://a.example/api.php\$ext-one\n\n# 注释\n木偶\$https://b.example/api.php';
      final result = parseConfig(text);
      expect(result.ok, isTrue, reason: result.error);
      expect(result.count, 2);
      expect(result.sites.first.name, '玩偶');
      expect(result.sites.first.api, 'https://a.example/api.php');
      expect(result.sites.first.ext, 'ext-one');
      expect(result.sites.last.ext, isEmpty);
    });

    test('parses one site per line in JSON form', () {
      const text =
          '{"key":"a","name":"甲","api":"x"}\n{"key":"b","name":"乙","api":"y"}';
      final result = parseConfig(text);
      expect(result.ok, isTrue, reason: result.error);
      expect(result.count, 2);
    });

    test('drops duplicate keys so the chip row does not double count', () {
      const config = '[{"key":"a","name":"甲"},{"key":"a","name":"甲二"}]';
      final result = parseConfig(config);
      expect(result.count, 1);
      expect(result.invalid, 1);
    });

    test('derives a stable key when the entry only has a name', () {
      const config = '[{"name":"玩偶哥哥"}]';
      final result = parseConfig(config);
      expect(result.ok, isTrue, reason: result.error);
      expect(result.sites.single.key, isNotEmpty);
      // Two parses of the same document must agree.
      expect(parseConfig(config).sites.single.key, result.sites.single.key);
    });

    test('strips a byte order mark', () {
      const config = '\uFEFF{"sites":[{"key":"a","name":"甲"}]}';
      final result = parseConfig(config);
      expect(result.ok, isTrue, reason: result.error);
      expect(result.count, 1);
    });

    test('explains the common failure modes', () {
      expect(parseConfig('').error, '配置为空');
      expect(parseConfig('   ').error, '配置为空');
      expect(parseConfig('https://example.com/config.json').error, '这是网址，不是配置内容');
      expect(parseConfig('随便写点什么').ok, isFalse);
      expect(parseConfig('{"sites":[]}').error, hasLength(greaterThan(0)));
      expect(
        parseConfig('{"urls":[{"url":"https://a/b"}]}').error,
        '这是多仓聚合地址，请贴单个仓库的配置',
      );
    });

    test('entry with neither name nor key is skipped, not fatal', () {
      const config = '[{"key":"a","name":"甲"},{"type":3,"api":"x"}]';
      final result = parseConfig(config);
      expect(result.ok, isTrue);
      expect(result.count, 1);
      expect(result.invalid, 1);
    });
  });
}
