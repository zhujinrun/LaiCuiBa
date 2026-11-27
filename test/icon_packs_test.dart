import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/icon_packs.dart';

Directory _dir() => Directory.systemTemp.createTempSync('lcb_iconpacks_');

List<int> _zip(Map<String, List<int>> files, {String? manifest}) {
  final archive = Archive();
  if (manifest != null) {
    final bytes = utf8.encode(manifest);
    archive.addFile(ArchiveFile('icon-pack.json', bytes.length, bytes));
  }
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return ZipEncoder().encode(archive);
}

final List<int> _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

String _manifest(String id, [String? name]) => jsonEncode({
  'id': id,
  if (name != null) 'name': name,
});

void main() {
  late Directory dir;
  late File zip;

  setUp(() {
    dir = _dir();
    IconPacks.directoryOverride = dir;
    zip = File('${dir.path}${Platform.pathSeparator}pack.zip');
  });

  tearDown(() {
    IconPacks.directoryOverride = null;
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> writeZip(
    Map<String, List<int>> files, {
    String? manifest,
  }) async {
    await zip.writeAsBytes(_zip(files, manifest: manifest));
  }

  test('导入 ZIP：按包内编号和建议名称落盘，名字可以之后改', () async {
    await writeZip(
      {'cat.webp': _png, 'dog.png': _png},
      manifest: _manifest('pack_1', '猫狗'),
    );

    final pack = await IconPacks.importZip(zip.path);
    expect(pack.id, 'pack_1');
    expect(pack.name, '猫狗');
    expect(pack.suggestedName, '猫狗');
    expect(pack.count, 2);
    expect(IconPacks.load().single.name, '猫狗');
    expect(
      Directory('${dir.path}${Platform.pathSeparator}icon_packs'
              '${Platform.pathSeparator}packs${Platform.pathSeparator}pack_1')
          .listSync()
          .length,
      2,
    );

    await IconPacks.rename('pack_1', '我的图标');
    expect(IconPacks.load().single.name, '我的图标');
    expect(IconPacks.load().single.suggestedName, '猫狗');
  });

  test('同一编号再次导入是合并，不覆盖用户起的本地名字', () async {
    await writeZip({'cat.webp': _png}, manifest: _manifest('pack_1', '第一批'));
    await IconPacks.importZip(zip.path);
    await IconPacks.rename('pack_1', '我自己的名字');

    await writeZip({'dog.webp': _png}, manifest: _manifest('pack_1', '第二批'));
    final merged = await IconPacks.importZip(zip.path);
    expect(merged.count, 2);
    expect(merged.name, '我自己的名字');
    expect(IconPacks.load().length, 1);
  });

  test('删包之后，已经用到资源上的图标仍旧在', () async {
    await writeZip({'cat.webp': _png}, manifest: _manifest('pack_1', '猫'));
    final pack = await IconPacks.importZip(zip.path);
    final applied = await IconPacks.applyPackIcon('source-1', pack, pack.files.single);

    await IconPacks.delete('pack_1');
    expect(File(applied).existsSync(), isTrue);
    expect(IconPacks.load(), isEmpty);
    expect(
      Directory('${dir.path}${Platform.pathSeparator}icon_packs'
              '${Platform.pathSeparator}packs${Platform.pathSeparator}pack_1')
          .existsSync(),
      isFalse,
    );
  });

  test('缺清单、编号错、路径不安全、重名、没图片都无法导入', () async {
    await writeZip({'cat.webp': _png});
    await expectLater(
      IconPacks.importZip(zip.path),
      throwsA(isA<IconPackException>().having(
        (e) => e.message,
        'message',
        'ZIP 根目录缺少 icon-pack.json',
      )),
    );

    await writeZip({'cat.webp': _png}, manifest: _manifest('../bad'));
    await expectLater(
      IconPacks.importZip(zip.path),
      throwsA(isA<IconPackException>().having(
        (e) => e.message,
        'message',
        '图标包编号不正确',
      )),
    );

    await writeZip(
      {'../cat.webp': _png},
      manifest: _manifest('pack_1', '猫'),
    );
    await expectLater(
      IconPacks.importZip(zip.path),
      throwsA(isA<IconPackException>().having(
        (e) => e.message,
        'message',
        '图标包包含不安全的路径',
      )),
    );

    await writeZip(
      {'a/cat.webp': _png, 'b/cat.webp': _png},
      manifest: _manifest('pack_1', '猫'),
    );
    await expectLater(
      IconPacks.importZip(zip.path),
      throwsA(isA<IconPackException>().having(
        (e) => e.message,
        'message',
        '图标包包含重复文件',
      )),
    );

    await writeZip({'readme.txt': [1, 2, 3]}, manifest: _manifest('pack_1', '猫'));
    await expectLater(
      IconPacks.importZip(zip.path),
      throwsA(isA<IconPackException>().having(
        (e) => e.message,
        'message',
        '图标包里没有有效图片',
      )),
    );
  });

  test('起名字不能留空', () async {
    await writeZip({'cat.webp': _png}, manifest: _manifest('pack_1', '猫'));
    await IconPacks.importZip(zip.path);
    await expectLater(
      IconPacks.rename('pack_1', '   '),
      throwsA(isA<IconPackException>().having(
        (e) => e.message,
        'message',
        '请填写图标包名称',
      )),
    );
  });

  test('文件数上限是 500，不是随手定的数字', () {
    expect(IconPacks.maxFiles, 500);
    expect(IconPacks.maxZipBytes, 100 * 1024 * 1024);
  });
}
