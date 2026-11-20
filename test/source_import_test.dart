import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/source_import.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lcb-import-');
  });

  tearDown(() {
    if (root.existsSync()) {
      try {
        root.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows occasionally holds a handle for a moment; %TEMP% is fine.
      }
    }
  });

  File write(String relative, String content) {
    final file = File(
      '${root.path}${Platform.pathSeparator}'
      '${relative.replaceAll('/', Platform.pathSeparator)}',
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  test('a JSON config becomes a source carrying its sites', () async {
    final file = write(
      '我的配置.json',
      jsonEncode({
        'sites': [
          {'key': 'a', 'name': 'A 站', 'type': 3, 'api': 'https://a/api.php'},
          {'key': 'b', 'name': 'B 站', 'type': 1, 'api': 'https://b/api.php'},
        ],
      }),
    );

    final outcome = await importPaths([file.path]);

    expect(outcome.count, 1);
    expect(outcome.skipped, isEmpty);
    final source = outcome.sources.single;
    expect(source.type, 'tvbox');
    expect(source.name, '我的配置');
    expect(source.sites.map((site) => site.name), ['A 站', 'B 站']);
    // The imported source points its home feed at its own first site.
    expect(source.homeSite, 'a');
    // Kept so the card can say where it came from.
    expect(source.url, file.path);
  });

  test('a one-site-per-line txt is read as a TVBox list, not a live list',
      () async {
    final file = write('手写站点.txt', '甲站\$https://jia/api.php\$ext\n乙站\$https://yi/api.php');

    final outcome = await importPaths([file.path]);

    expect(outcome.count, 1);
    final source = outcome.sources.single;
    expect(source.type, 'tvbox');
    expect(source.sites, hasLength(2));
    expect(source.channelCount, 0);
  });

  test('an m3u list becomes a live source with its channel count', () async {
    final file = write(
      'iptv.m3u',
      '#EXTM3U\n'
      '#EXTINF:-1 tvg-name="CCTV1",CCTV1\nhttp://x/1.m3u8\n'
      '#EXTINF:-1 tvg-name="CCTV2",CCTV2\nhttp://x/2.m3u8\n'
      '#EXTINF:-1 tvg-name="湖南",湖南\nhttp://x/3.m3u8\n',
    );

    final outcome = await importPaths([file.path]);

    expect(outcome.count, 1);
    final source = outcome.sources.single;
    expect(source.type, 'live');
    expect(source.name, 'iptv');
    expect(source.channelCount, 3);
    expect(source.sites, isEmpty);
  });

  test('a plain URL txt counts as a live list too', () async {
    final file = write('频道.txt', 'http://a/1.m3u8\nhttp://a/2.m3u8\n');

    final outcome = await importPaths([file.path]);

    expect(outcome.sources.single.type, 'live');
    expect(outcome.sources.single.channelCount, 2);
  });

  test('a spider file is kept as a file-backed source', () async {
    final file = write('spider/我的源.py', 'class Spider:\n  pass\n');

    final outcome = await importPaths([file.path]);

    final source = outcome.sources.single;
    expect(source.type, 'py');
    expect(source.name, '我的源');
    expect(source.url, file.path);
    // Nothing is claimed about its sites: only a runtime can know them.
    expect(source.sites, isEmpty);
  });

  test('unknown and empty files are reported, not imported', () async {
    final readme = write('readme.md', '# 说明');
    final empty = write('空.json', '');
    final notConfig = write('数据.json', '{"hello": 1}');

    final outcome = await importPaths([readme.path, empty.path, notConfig.path]);

    expect(outcome.sources, isEmpty);
    expect(outcome.skipped, hasLength(3));
    expect(outcome.skipped.first, contains('readme.md'));
    expect(outcome.summary, contains('readme.md'));
    expect(outcome.count, 0);
  });

  test('a folder import walks subdirectories and skips the rest', () async {
    write(
      'conf/config.json',
      jsonEncode({
        'sites': [
          {'key': 'a', 'name': 'A', 'type': 3},
        ],
      }),
    );
    write('live/iptv.m3u', '#EXTM3U\n#EXTINF:-1,A\nhttp://a/1.m3u8\n');
    write('spiders/x.py', 'pass\n');
    write('notes.md', 'ignore me');

    final outcome = await importDirectory(root.path);

    expect(outcome.count, 3);
    expect(
      outcome.sources.map((source) => source.type).toSet(),
      {'tvbox', 'live', 'py'},
    );
    expect(outcome.skipped, isEmpty);
  });

  test('a missing folder explains itself instead of throwing', () async {
    final outcome = await importDirectory(
      '${root.path}${Platform.pathSeparator}nope',
    );
    expect(outcome.sources, isEmpty);
    expect(outcome.skipped.single, contains('不存在'));
  });

  test('a ZIP is unpacked and imported, and unsafe entries are dropped',
      () async {
    final archive = Archive();
    void add(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add(
      'pkg/config.json',
      jsonEncode({
        'sites': [
          {'key': 'z', 'name': 'Z 站', 'type': 3},
        ],
      }),
    );
    add('pkg/list.m3u', '#EXTM3U\n#EXTINF:-1,B\nhttp://b/1.m3u8\n');
    add('../escape.json', '{"sites":[]}');

    final zip = File('${root.path}${Platform.pathSeparator}本地包.zip');
    zip.writeAsBytesSync(ZipEncoder().encode(archive).toList());

    final target = Directory('${root.path}${Platform.pathSeparator}unpacked');
    final outcome = await importZip(zip.path, unpackTo: target);

    expect(outcome.count, 2);
    expect(outcome.sources.map((s) => s.name).toSet(), {'config', 'list'});
    // The `..` entry must not land outside the target directory.
    expect(
      File('${root.path}${Platform.pathSeparator}escape.json').existsSync(),
      isFalse,
    );
    expect(
      File(
        '${target.path}${Platform.pathSeparator}pkg'
        '${Platform.pathSeparator}config.json',
      ).existsSync(),
      isTrue,
    );
  });

  test('a non-zip file reports instead of crashing', () async {
    final fake = write('假的.zip', 'not a zip at all');

    final outcome = await importZip(
      fake.path,
      unpackTo: Directory('${root.path}${Platform.pathSeparator}u2'),
    );

    expect(outcome.sources, isEmpty);
    expect(outcome.skipped.single, contains('ZIP'));
  });

  test('channel counting prefers EXTINF over bare urls', () {
    expect(countLiveChannels(''), 0);
    expect(countLiveChannels('#EXTM3U\n'), 0);
    expect(
      countLiveChannels('#EXTM3U\n#EXTINF:-1,A\nhttp://a\n#EXTINF:-1,B\nhttp://b\n'),
      2,
    );
    expect(countLiveChannels('http://a\nhttp://b\nhttp://c\n'), 3);
  });
}
