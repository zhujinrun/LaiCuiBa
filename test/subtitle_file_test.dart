import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:lai_cui_ba/services/player/subtitle_file.dart';

/// 外挂字幕第一道关：文件到底是什么。
///
/// 这里全部用真文件：扩展名可以骗人，魔数不能，所以每条规则都对着磁盘上的
/// 字节验一遍，而不是对着一个 mock。
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('lcb-subs-test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File write(String name, List<int> bytes) {
    final f = File(p.join(root.path, name));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes);
    return f;
  }

  Archive zipOf(Map<String, String> entries) {
    final archive = Archive();
    entries.forEach((name, text) {
      final bytes = utf8.encode(text);
      archive.add(ArchiveFile.bytes(name, bytes));
    });
    return archive;
  }

  group('直接是字幕文件', () {
    test('srt / ass / vtt 原样交出去，名字用文件名', () async {
      for (final name in ['01.srt', '02.ass', '03.vtt', '04.SSA']) {
        final f = write(name, utf8.encode('1\n00:00:01,000 --> 00:00:02,000\nhi\n'));
        final files = await openSubtitleFiles(f.path, extractTo: root);
        expect(files, hasLength(1), reason: name);
        expect(files.single.path, f.path);
        expect(files.single.label, p.basename(f.path));
        expect(files.single.fromArchive, isFalse);
      }
    });

    test('不是字幕扩展名就明说，不猜', () async {
      final f = write('notes.txt', utf8.encode('hello'));
      await expectLater(
        openSubtitleFiles(f.path, extractTo: root),
        throwsA(
          isA<SubtitleFileException>().having(
            (e) => e.message,
            'message',
            contains('这不是字幕文件'),
          ),
        ),
      );
    });

    test('文件不在时说读取失败，而不是「格式不对」', () async {
      await expectLater(
        openSubtitleFiles(p.join(root.path, 'nope.srt'), extractTo: root),
        throwsA(
          isA<SubtitleFileException>().having(
            (e) => e.message,
            'message',
            '字幕文件读取失败',
          ),
        ),
      );
    });
  });

  group('压缩包', () {
    test('7z 和 RAR 如实说解不开，而不是报「文件坏了」', () async {
      final sevenZ = write(
        'subs.7z',
        [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, 0, 0],
      );
      final rar = write(
        'subs.rar',
        [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00, 0x00],
      );
      for (final f in [sevenZ, rar]) {
        await expectLater(
          openSubtitleFiles(f.path, extractTo: root),
          throwsA(
            isA<SubtitleFileException>().having(
              (e) => e.message,
              'message',
              contains('7z / RAR'),
            ),
          ),
        );
      }
    });

    test('zip 里的字幕解到指定目录，内容一字不差', () async {
      final f = write(
        'pack.zip',
        ZipEncoder().encode(
          zipOf({'subs/01.srt': '1\n00:00:01,000 --> 00:00:02,000\nhello\n'}),
        ),
      );
      final files = await openSubtitleFiles(f.path, extractTo: root);
      expect(files, hasLength(1));
      expect(files.single.fromArchive, isTrue);
      expect(files.single.label, '01.srt');
      expect(File(files.single.path).readAsStringSync(), contains('hello'));
      // 解出来的路径必须在给的目标目录下，不能跟着条目名跑出根目录。
      expect(
        p.isWithin(p.join(root.path, 'subtitles'), files.single.path),
        isTrue,
      );
    });

    test('包里有多条字幕时全部列出来，按名字排序', () async {
      final f = write(
        'pack.zip',
        ZipEncoder().encode(
          zipOf({
            'b.srt': 'b',
            'a.srt': 'a',
            'readme.txt': 'not a subtitle',
          }),
        ),
      );
      final files = await openSubtitleFiles(f.path, extractTo: root);
      expect(files.map((e) => e.label), ['a.srt', 'b.srt']);
    });

    test('压缩包里没有字幕文件时单独一句话', () async {
      final f = write(
        'pack.zip',
        ZipEncoder().encode(zipOf({'readme.txt': 'nothing here'})),
      );
      await expectLater(
        openSubtitleFiles(f.path, extractTo: root),
        throwsA(
          isA<SubtitleFileException>().having(
            (e) => e.message,
            'message',
            '压缩包里没有字幕文件',
          ),
        ),
      );
    });

    test('扩展名写错也按魔数认：.ass 里装的是 zip', () async {
      final f = write(
        'disguised.ass',
        ZipEncoder().encode(zipOf({'01.srt': 'x'})),
      );
      final files = await openSubtitleFiles(f.path, extractTo: root);
      expect(files.single.label, '01.srt');
    });

    test('条目名带路径穿越时只留文件名，不写出去', () async {
      final f = write(
        'evil.zip',
        ZipEncoder().encode(zipOf({'../../escape.srt': 'x'})),
      );
      final files = await openSubtitleFiles(f.path, extractTo: root);
      expect(p.basename(files.single.path), 'escape.srt');
      expect(
        p.isWithin(p.join(root.path, 'subtitles'), files.single.path),
        isTrue,
      );
    });
  });
}
