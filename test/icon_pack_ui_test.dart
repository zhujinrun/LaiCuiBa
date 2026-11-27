import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/core/store_scope.dart';
import 'package:lai_cui_ba/main.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/icon_packs.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/ui/widgets/source_icon_picker.dart';

Directory _dir() => Directory.systemTemp.createTempSync('lcb_iconui_');

final List<int> _png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

Future<IconPack> _pack(Directory dir, String name) async {
  IconPacks.directoryOverride = dir;
  final archive = Archive();
  final manifest = utf8.encode(jsonEncode({'id': 'pack_ui', 'name': name}));
  archive.addFile(ArchiveFile('icon-pack.json', manifest.length, manifest));
  archive.addFile(ArchiveFile('cat.webp', _png.length, _png));
  final zip = File('${dir.path}${Platform.pathSeparator}pack.zip');
  await zip.writeAsBytes(ZipEncoder().encode(archive));
  return IconPacks.importZip(zip.path);
}

/// Widget tests run in a fake-async zone, so real file I/O has to be pumped
/// through the real event loop before the page can see what was written.
Future<void> _flush(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

Future<void> _openIconPacksPage(WidgetTester tester, AppStore store) async {
  tester.view.physicalSize = const Size(1920, 1040);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(LcbApp(store: store));
  await tester.pump(const Duration(milliseconds: 900));
  await tester.tap(find.text('设置').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('数据与存储'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('源图标包'));
  await tester.pumpAndSettle();
  await _flush(tester);
}

void main() {
  late Directory dir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    dir = _dir();
  });

  tearDown(() {
    IconPacks.directoryOverride = null;
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } on Object {
      // Windows may still hold the last file handle for a moment; a temp
      // folder leak is preferable to flaking the whole suite.
    }
  });

  testWidgets('还没有图标包时给出空态和导入入口', (tester) async {
    IconPacks.directoryOverride = dir;
    final store = await AppStore.load();
    await _openIconPacksPage(tester, store);

    expect(find.text('导入 ZIP 图标包'), findsOneWidget);
    expect(find.text('还没有图标包'), findsOneWidget);
    expect(
      find.text('导入的图标包只保存在本机。编辑资源时选“图标包”，即可从这些包中选择。'),
      findsOneWidget,
    );
  });

  testWidgets('源图标包列表能命名，也能删：删除前先说清影响面', (tester) async {
    final pack = await tester.runAsync(() => _pack(dir, '猫咪'));
    expect(pack!.id, 'pack_ui');
    final store = await AppStore.load();
    await _openIconPacksPage(tester, store);

    expect(find.text('猫咪'), findsOneWidget);
    expect(find.text('1 个'), findsOneWidget);
    expect(
      find.text('1 个图标。名称只保存在本机，可以和 ZIP 内的建议名称不同。'),
      findsOneWidget,
    );

    await tester.tap(find.text('命名图标包'));
    await tester.pumpAndSettle();
    expect(find.text('图标包名称'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '我的猫');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    await _flush(tester);
    expect(find.text('我的猫'), findsOneWidget);
    expect(IconPacks.load().single.name, '我的猫');

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('将删除这个图标包的 1 个图标'), findsOneWidget);
    expect(
      find.text('1 个图标。已经设置到资源上的图标已单独保存，不受影响。'),
      findsOneWidget,
    );
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    await _flush(tester);
    expect(find.text('图标包已删除'), findsOneWidget);
    expect(find.text('还没有图标包'), findsOneWidget);
  });

  testWidgets('更换图标里有图标包分区、搜索和选择图标文件', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() => _pack(dir, '猫咪'));
    final store = await AppStore.load();
    const source = SourceInfo(
      id: 's1',
      type: 'tvbox',
      name: '甲源',
      url: 'https://example.com',
    );

    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showSourceIconPicker(context, source),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await _flush(tester);

    expect(find.text('更换图标'), findsOneWidget);
    expect(find.text('搜索图标名称'), findsOneWidget);
    expect(find.text('选择图标文件'), findsOneWidget);
    expect(find.text('内置图标'), findsOneWidget);
    expect(find.text('猫咪'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zzz-无此图标');
    await tester.pumpAndSettle();
    expect(find.text('没有找到图标'), findsOneWidget);
  });
}
