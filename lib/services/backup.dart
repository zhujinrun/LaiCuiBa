import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/app_info.dart';
import 'store.dart';

/// One exported bundle sitting on disk.
class BackupFile {
  const BackupFile({
    required this.path,
    required this.modified,
    required this.bytes,
  });

  final String path;
  final DateTime modified;
  final int bytes;

  String get name => path.split(Platform.pathSeparator).last;

  /// `2.4 KB` / `860 B` -- the unit the original uses in 数据与存储.
  String get sizeLabel {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }
}

/// Local backup and restore.
///
/// The original's 备份与恢复 writes the whole local dataset to a file and reads
/// it back. Nothing leaves the machine, which is why the format is simply the
/// store's own JSON under a small envelope: restoring is "decode, replace every
/// list, persist once".
class LcbBackup {
  const LcbBackup._();

  static const _appFolder = 'LaiCuiBa';
  static const _backupFolder = 'backups';

  /// Points every operation at a scratch directory. Tests write real files, and
  /// they must never land in the user's own backup folder.
  @visibleForTesting
  static Directory? overrideDirectory;

  /// Same directory `shared_preferences.json` lives in, so a user looking for
  /// their data finds both in one place.
  static Directory directory() {
    final override = overrideDirectory;
    if (override != null) return override;
    final sep = Platform.pathSeparator;
    final env = Platform.environment;
    final String base;
    if (Platform.isWindows) {
      base =
          '${env['APPDATA'] ?? Directory.current.path}$sep$_appFolder'
          '$sep$_appFolder';
    } else {
      // XDG-ish; the project only ships a Windows build, this keeps the service
      // testable anywhere without inventing a Windows path.
      final config =
          env['XDG_CONFIG_HOME'] ??
          '${env['HOME'] ?? Directory.current.path}$sep.config';
      base = '$config${sep}lai_cui_ba';
    }
    return Directory('$base$sep$_backupFolder');
  }

  /// Writes a bundle and returns the file it created.
  static Future<BackupFile> write(AppStore store) async {
    final dir = directory();
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final now = DateTime.now();
    final stem = '${dir.path}${Platform.pathSeparator}lcb-${_stamp(now)}';
    // Two exports inside the same second must not overwrite each other.
    var file = File('$stem.json');
    var attempt = 2;
    while (file.existsSync()) {
      file = File('$stem-$attempt.json');
      attempt++;
    }
    final bundle = <String, dynamic>{
      'app': LcbAppInfo.name,
      'version': LcbAppInfo.version,
      'exportedAt': now.toIso8601String(),
      ...store.exportBundle(),
    };
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(bundle),
      flush: true,
    );
    return BackupFile(
      path: file.path,
      modified: file.lastModifiedSync(),
      bytes: file.lengthSync(),
    );
  }

  /// Newest first; empty when nothing was ever exported.
  static Future<List<BackupFile>> list() async {
    final dir = directory();
    if (!dir.existsSync()) return const [];
    final files = dir.listSync().whereType<File>().where(
      (file) => file.path.toLowerCase().endsWith('.json'),
    );
    final out = [
      for (final file in files)
        BackupFile(
          path: file.path,
          modified: file.lastModifiedSync(),
          bytes: file.lengthSync(),
        ),
    ];
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  static Future<void> delete(BackupFile backup) async {
    final file = File(backup.path);
    if (file.existsSync()) await file.delete();
  }

  /// Throws [FormatException] when the file is gone or is not a bundle; the
  /// caller shows the message and keeps the current data untouched.
  static Future<void> restore(AppStore store, String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw const FormatException('备份文件已不存在');
    }
    final Object? raw = jsonDecode(await file.readAsString());
    if (raw is! Map) {
      throw const FormatException('这不是一个有效的备份文件');
    }
    await store.importBundle(Map<String, dynamic>.from(raw));
  }

  static String _stamp(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}-'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}
