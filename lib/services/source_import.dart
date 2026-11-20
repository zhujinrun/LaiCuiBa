import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/models.dart';
import 'site_parser.dart';

/// What one local import run produced.
///
/// Every entry is created from a file that was actually read: a config with
/// sites, a live list with channels, or a spider file kept for the runtime that
/// will execute it later. Nothing here talks to the network, which is why these
/// are the "添加资源" entries this build can make genuinely real.
class ImportOutcome {
  final List<SourceInfo> sources = [];

  /// Human-readable reason per file that produced nothing ("notes.mkv：不支持").
  final List<String> skipped = [];

  int get count => sources.length;
  bool get isEmpty => sources.isEmpty;

  /// One line the UI can drop in a toast.
  String get summary {
    if (sources.isEmpty) {
      return skipped.isEmpty ? '没有可导入的文件' : skipped.first;
    }
    final head = '导入了 ${sources.length} 个资源';
    if (skipped.isEmpty) return head;
    return '$head，跳过 ${skipped.length} 个：${skipped.first}';
  }
}

const _jsonExt = {'json'};
const _liveExt = {'m3u', 'm3u8'};
const _textExt = {'txt'};
const _spiderExt = {'py', 'php', 'js'};

/// Extensions the file picker offers for 导入文件.
const importableExtensions = [
  'json',
  'txt',
  'm3u',
  'm3u8',
  'py',
  'php',
  'js',
];

/// Imports each path independently and collects what worked.
Future<ImportOutcome> importPaths(Iterable<String> paths) async {
  final outcome = ImportOutcome();
  for (final path in paths) {
    await _importOne(path, outcome);
  }
  return outcome;
}

/// Recursively imports every source-shaped file under [dir].
///
/// This is the original's 导入文件夹里的源: a folder that holds a TVBox config
/// plus its `py` spiders becomes one config source and one source per spider.
Future<ImportOutcome> importDirectory(String dir, {int limit = 400}) async {
  final directory = Directory(dir);
  if (!directory.existsSync()) {
    final outcome = ImportOutcome()..skipped.add('文件夹不存在：$dir');
    return outcome;
  }

  final files = <String>[];
  for (final entity in directory.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    if (!_known(entity.path)) continue;
    files.add(entity.path);
    if (files.length >= limit) break;
  }
  files.sort();
  return importPaths(files);
}

/// Unpacks [zipPath] into the app's own folder, then imports the result.
///
/// Entries with `..` or an absolute path are dropped so a hostile archive cannot
/// write outside the target directory.
Future<ImportOutcome> importZip(String zipPath, {Directory? unpackTo}) async {
  final file = File(zipPath);
  if (!file.existsSync()) {
    final outcome = ImportOutcome()..skipped.add('ZIP 不存在：$zipPath');
    return outcome;
  }

  final stem = _stem(_baseName(zipPath));
  final target =
      unpackTo ??
      Directory(
        '${appDataDirectory().path}${Platform.pathSeparator}imported'
        '${Platform.pathSeparator}${_safeSegment(stem)}',
      );
  if (target.existsSync()) target.deleteSync(recursive: true);
  target.createSync(recursive: true);

  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(await file.readAsBytes());
  } on Object {
    final outcome = ImportOutcome()..skipped.add('不是有效的 ZIP：${_baseName(zipPath)}');
    return outcome;
  }

  var written = 0;
  for (final entry in archive) {
    if (!entry.isFile) continue;
    final name = entry.name.replaceAll('\\', '/');
    if (name.startsWith('/') || name.contains('..')) continue;
    final out = File(
      '${target.path}${Platform.pathSeparator}'
      '${name.replaceAll('/', Platform.pathSeparator)}',
    );
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(Uint8List.fromList(entry.content));
    written++;
  }
  final outcome = await importDirectory(target.path);
  if (written == 0 && outcome.skipped.isEmpty) {
    // A file that is not a zip decodes to an empty archive rather than throwing.
    outcome.skipped.add('ZIP 里没有可导入的文件：${_baseName(zipPath)}');
  }
  return outcome;
}

/// `%APPDATA%/LaiCuiBa/LaiCuiBa` on Windows -- the folder the preferences file
/// already lives in, so imported packages and backups sit together.
Directory appDataDirectory() {
  final sep = Platform.pathSeparator;
  final env = Platform.environment;
  if (Platform.isWindows) {
    return Directory(
      '${env['APPDATA'] ?? Directory.current.path}'
      '${sep}LaiCuiBa${sep}LaiCuiBa',
    );
  }
  final config =
      env['XDG_CONFIG_HOME'] ??
      '${env['HOME'] ?? Directory.current.path}$sep.config';
  return Directory('$config${sep}lai_cui_ba');
}

/// Counts channels in an M3U / TXT live list.
///
/// `#EXTINF` wins when present (each one is a channel); otherwise bare URLs are
/// counted, which is the shape a plain TXT list uses.
int countLiveChannels(String text) {
  var tagged = 0;
  var urls = 0;
  for (final line in const LineSplitter().convert(text)) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('#')) {
      if (trimmed.toUpperCase().startsWith('#EXTINF')) tagged++;
      continue;
    }
    if (trimmed.contains('://')) urls++;
  }
  return tagged > 0 ? tagged : urls;
}

Future<void> _importOne(String path, ImportOutcome outcome) async {
  final base = _baseName(path);
  final file = File(path);
  if (!file.existsSync()) {
    outcome.skipped.add('$base：文件不存在');
    return;
  }
  final ext = _extOf(path);
  if (!_known(path)) {
    outcome.skipped.add('$base：不支持的文件类型');
    return;
  }

  // A TVBox config can be a .json, or a .txt that is one site per line.
  if (_jsonExt.contains(ext) || _textExt.contains(ext)) {
    final raw = await _readText(file);
    final parsed = parseConfig(raw);
    if (parsed.ok && parsed.count > 0) {
      outcome.sources.add(
        SourceInfo(
          id: _newId(outcome),
          type: 'tvbox',
          name: _stem(base),
          url: path,
          sites: parsed.sites,
          homeSite: parsed.sites.first.key,
        ),
      );
      return;
    }
    if (_textExt.contains(ext)) {
      final channels = countLiveChannels(raw);
      if (channels > 0) {
        outcome.sources.add(
          SourceInfo(
            id: _newId(outcome),
            type: 'live',
            name: _stem(base),
            url: path,
            channelCount: channels,
          ),
        );
        return;
      }
    }
    outcome.skipped.add('$base：${parsed.error ?? '没有可用的站点'}');
    return;
  }

  if (_liveExt.contains(ext)) {
    final channels = countLiveChannels(await _readText(file));
    if (channels == 0) {
      outcome.skipped.add('$base：没读到频道');
      return;
    }
    outcome.sources.add(
      SourceInfo(
        id: _newId(outcome),
        type: 'live',
        name: _stem(base),
        url: path,
        channelCount: channels,
      ),
    );
    return;
  }

  // py / php / js: kept as a file-backed source. Which sites it declares is only
  // knowable once a spider host runs it, so the card says so instead of guessing.
  outcome.sources.add(
    SourceInfo(id: _newId(outcome), type: ext, name: _stem(base), url: path),
  );
}

bool _known(String path) {
  final ext = _extOf(path);
  return _jsonExt.contains(ext) ||
      _liveExt.contains(ext) ||
      _textExt.contains(ext) ||
      _spiderExt.contains(ext);
}

String _extOf(String path) {
  final name = _baseName(path);
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return '';
  return name.substring(dot + 1).toLowerCase();
}

String _baseName(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  return parts.isEmpty ? path : parts.last;
}

String _stem(String name) {
  final dot = name.lastIndexOf('.');
  return dot <= 0 ? name : name.substring(0, dot);
}

String _safeSegment(String value) {
  final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? 'package' : cleaned;
}

/// Microsecond stamps collide when a folder holds hundreds of files, so the
/// per-run index is folded in.
String _newId(ImportOutcome outcome) =>
    '${DateTime.now().microsecondsSinceEpoch}-${outcome.sources.length}';

Future<String> _readText(File file) async {
  final bytes = await file.readAsBytes();
  try {
    return utf8.decode(bytes);
  } on FormatException {
    // Plenty of local M3U lists in this market are GBK; latin1 keeps the
    // structure readable ("名称 + 一行一个地址") even when the names come out
    // garbled, which is enough to count channels and to keep the file.
    return latin1.decode(bytes);
  }
}
