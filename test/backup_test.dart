import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/services/backup.dart';
import 'package:lai_cui_ba/services/store.dart';

void main() {
  late Directory scratch;

  setUp(() {
    // Real files, scratch folder: a test run must never write into the user's
    // own %APPDATA%/LaiCuiBa/LaiCuiBa/backups.
    scratch = Directory.systemTemp.createTempSync('lcb-backup-');
    LcbBackup.overrideDirectory = scratch;
  });

  tearDown(() {
    LcbBackup.overrideDirectory = null;
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  test('an export writes a bundle the app can read back', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();

    final backup = await LcbBackup.write(store);

    expect(File(backup.path).existsSync(), isTrue);
    expect(backup.path, endsWith('.json'));
    expect(backup.name, startsWith('lcb-'));
    expect(backup.bytes, greaterThan(0));
    expect(backup.sizeLabel, isNotEmpty);

    final raw =
        jsonDecode(File(backup.path).readAsStringSync())
            as Map<String, dynamic>;
    expect(raw['app'], 'LaiCuiBa');
    expect(raw['exportedAt'], isA<String>());
    // The envelope carries the same keys the preferences store keeps.
    expect(raw['sources'], hasLength(1));
    expect(raw['history'], hasLength(1));
    expect(raw['favorites'], hasLength(1));
    expect(raw['favoriteFolders'], hasLength(1));
    expect((raw['sources'] as List).first['sites'], hasLength(59));

    final listed = await LcbBackup.list();
    expect(listed, hasLength(1));
    expect(listed.single.path, backup.path);
  });

  test('restore brings back sources, site switches and history', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    final backup = await LcbBackup.write(store);

    final sourceId = store.sources.first.id;
    await store.toggleSite(sourceId, 'nodejs_jianpian');
    await store.selectHomeSite('nodejs_duoduo');
    await store.clearHistory();
    expect(store.activeSites, hasLength(58));
    expect(store.history, isEmpty);
    expect(store.homeSite?.key, 'nodejs_duoduo');

    await LcbBackup.restore(store, backup.path);

    expect(store.activeSites, hasLength(59));
    expect(store.homeSite?.key, 'nodejs_jianpian');
    expect(store.history, hasLength(1));

    // Persisted, not merely patched in memory: a relaunch sees the same thing.
    final reloaded = await AppStore.load();
    expect(reloaded.activeSites, hasLength(59));
    expect(reloaded.homeSite?.key, 'nodejs_jianpian');
    expect(reloaded.history, hasLength(1));
  });

  test('restore replaces a bundle that was edited on disk', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    final backup = await LcbBackup.write(store);

    // Simulate a bundle from another machine: one source, no history.
    final raw =
        jsonDecode(File(backup.path).readAsStringSync())
            as Map<String, dynamic>;
    raw['sources'] = [
      {
        'id': 'pasted-9',
        'type': 'tvbox',
        'name': '别人的源',
        'url': '',
        'sites': [
          {'key': 'a', 'name': 'A 站', 'type': '3'},
        ],
      },
    ];
    raw['current'] = 'pasted-9';
    raw['history'] = [];
    raw['favorites'] = [];
    File(backup.path).writeAsStringSync(jsonEncode(raw));

    await LcbBackup.restore(store, backup.path);

    expect(store.sources, hasLength(1));
    expect(store.sources.single.name, '别人的源');
    // The restored current id is honoured when the source exists.
    expect(store.currentSource?.id, 'pasted-9');
    expect(store.history, isEmpty);
    expect(store.siteCount, 1);
  });

  test(
    'a file that is not a bundle is rejected without touching data',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await AppStore.load();

      final junk = File('${scratch.path}${Platform.pathSeparator}junk.json')
        ..writeAsStringSync('{"hello":1}');
      await expectLater(
        LcbBackup.restore(store, junk.path),
        throwsFormatException,
      );
      expect(store.sources, hasLength(1));
      expect(store.history, hasLength(1));

      // An empty bundle must not look like a successful restore either.
      final empty = File('${scratch.path}${Platform.pathSeparator}empty.json')
        ..writeAsStringSync('{"sources":[],"history":[],"favorites":[]}');
      await expectLater(
        LcbBackup.restore(store, empty.path),
        throwsFormatException,
      );
      expect(store.sources, hasLength(1));
    },
  );

  test('a backup that vanished reports instead of an OS error', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();

    await expectLater(
      LcbBackup.restore(
        store,
        '${scratch.path}${Platform.pathSeparator}gone.json',
      ),
      throwsFormatException,
    );
  });

  test('delete removes one file and leaves the rest', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    final first = await LcbBackup.write(store);
    final second = await LcbBackup.write(store);
    expect(await LcbBackup.list(), hasLength(2));

    await LcbBackup.delete(first);
    final left = await LcbBackup.list();
    expect(left, hasLength(1));
    expect(left.single.path, second.path);
  });
}
