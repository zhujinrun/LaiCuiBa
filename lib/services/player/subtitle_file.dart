/// 本地字幕文件：选、验、必要时解开压缩包，交给播放器挂上。
///
/// 对应原版的 `services/player/subtitle_file.dart`。原版是手机/桌面共用的，
/// 这里只管桌面这一条路：
///
/// * 直接是 `srt / ass / ssa / vtt` —— 原样交出去，mpv 自己解析；
/// * 是 zip —— 用 `archive` 解到应用数据目录再交出去（原版能解 zip，7z / RAR
///   在手机上解不开，这里也一样，并且要说清楚是哪一种，别让人以为是文件坏了）；
/// * 其它 —— 明说不是字幕文件，不猜。
///
/// 解析字幕文本是 mpv 的事：挂上之后 media_kit 会把当前这句通过
/// `sub-text` 报出来，播放页照自己设置的字号画，两边字号才一致。
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../source_import.dart' show appDataDirectory;

/// 能直接交给播放器的字幕扩展名。
const subtitleExtensions = {'.srt', '.ass', '.ssa', '.vtt', '.sub'};

/// 需要先解开的压缩包扩展名。
const archiveExtensions = {'.zip', '.7z', '.rar'};

/// 一条可挂上去的字幕。
class SubtitleFile {
  const SubtitleFile({
    required this.path,
    required this.label,
    this.fromArchive = false,
  });

  /// 磁盘上真实可读的路径。压缩包里的条目已经解到这里。
  final String path;

  /// 给人看的名字（压缩包里的条目只留文件名）。
  final String label;

  /// 是从压缩包里解出来的——这种文件记在「这一集」上仍然有效，因为我们解到
  /// 应用数据目录，而不是临时目录。
  final bool fromArchive;

  @override
  String toString() => 'SubtitleFile($label → $path)';
}

/// 选字幕时出的错，[message] 直接给用户看。
class SubtitleFileException implements Exception {
  const SubtitleFileException(this.message, {this.detail});

  /// 一句话说清为什么不行。
  final String message;

  /// 附带的细节（HTTP 码、异常原文），界面上如果有地方放就放在小字里。
  final String? detail;

  @override
  String toString() =>
      'SubtitleFileException($message${detail == null ? '' : ' · $detail'})';
}

/// 打开系统的文件选择器，返回选中的路径；取消返回 null。
Future<String?> chooseSubtitlePath() async {
  const group = XTypeGroup(
    label: '字幕文件',
    extensions: [
      'srt',
      'ass',
      'ssa',
      'vtt',
      'sub',
      'zip',
      '7z',
      'rar',
    ],
  );
  final file = await openFile(acceptedTypeGroups: [group]);
  return file?.path;
}

/// 校验一个路径并返回可挂的字幕（压缩包会返回多条，让调用方挑）。
///
/// 不抛通用异常：所有失败都变成 [SubtitleFileException]，界面拿到就能显示，
/// 不用再猜是「文件不存在」还是「格式不对」。
Future<List<SubtitleFile>> openSubtitleFiles(
  String path, {
  Directory? extractTo,
}) async {
  final file = File(path);
  if (!file.existsSync()) {
    throw const SubtitleFileException('字幕文件读取失败', detail: '文件不存在');
  }

  final ext = p.extension(path).toLowerCase();
  final header = await _header(file);

  // 先看魔数再看扩展名：有人把 .srt 存成了 .zip，也有人把 zip 改名成 .ass。
  if (_is7z(header)) {
    throw const SubtitleFileException(
      '这个字幕是 7z / RAR 压缩包，这台设备上解不开，请换一个',
    );
  }
  if (_isRar(header)) {
    throw const SubtitleFileException(
      '这个字幕是 7z / RAR 压缩包，这台设备上解不开，请换一个',
    );
  }
  final zipped = _isZip(header) || archiveExtensions.contains(ext);
  if (zipped) return _unzip(file, ext, extractTo);

  if (!subtitleExtensions.contains(ext)) {
    throw SubtitleFileException(
      '这不是字幕文件（支持 srt / ass / vtt）',
      detail: ext.isEmpty ? null : '扩展名 $ext',
    );
  }
  return [
    SubtitleFile(path: path, label: p.basename(path)),
  ];
}

/// 把压缩包里的字幕条目解到 `<应用数据>/subtitles/<包名>/` 并返回。
///
/// 解到应用数据目录而不是临时目录，这样「记在这一集上」下次开机还找得到。
Future<List<SubtitleFile>> _unzip(
  File file,
  String ext,
  Directory? extractTo,
) async {
  final bytes = await file.readAsBytes();
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (e) {
    throw SubtitleFileException(
      '压缩包打不开',
      detail: ext == '.zip' ? '$e' : '看起来不是 zip，目前只认 zip',
    );
  }

  final entries = [
    for (final entry in archive.files)
      if (entry.isFile && subtitleExtensions.contains(p.extension(entry.name).toLowerCase()))
        entry,
  ];
  if (entries.isEmpty) {
    throw const SubtitleFileException('压缩包里没有字幕文件');
  }
  // 文件名里带中文的压缩包在 Windows 上常见 GBK 编码，`archive` 解出来可能是
  // 乱码；这只影响显示的名字，不影响文件内容，所以照旧往下走。
  entries.sort((a, b) => a.name.compareTo(b.name));

  final base = p.basenameWithoutExtension(file.path);
  final dir = Directory(
    p.join((extractTo ?? appDataDirectory()).path, 'subtitles', _safeName(base)),
  );
  dir.createSync(recursive: true);

  final out = <SubtitleFile>[];
  for (final entry in entries) {
    // 条目名可能是 `../../x.srt`，只留文件名，别让它写出字幕目录。
    final name = _safeName(p.basename(entry.name));
    final data = entry.readBytes();
    if (data == null || data.isEmpty) continue;
    final target = File(p.join(dir.path, name));
    target.writeAsBytesSync(data);
    out.add(
      SubtitleFile(path: target.path, label: name, fromArchive: true),
    );
  }
  return out;
}

String _safeName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  return cleaned.isEmpty ? 'subtitle' : cleaned;
}

Future<List<int>> _header(File file) async {
  final raf = await file.open();
  try {
    return await raf.read(8);
  } finally {
    await raf.close();
  }
}

bool _isZip(List<int> h) =>
    h.length >= 4 && h[0] == 0x50 && h[1] == 0x4B && h[2] == 0x03 && h[3] == 0x04;

bool _is7z(List<int> h) =>
    h.length >= 6 &&
    h[0] == 0x37 &&
    h[1] == 0x7A &&
    h[2] == 0xBC &&
    h[3] == 0xAF &&
    h[4] == 0x27 &&
    h[5] == 0x1C;

bool _isRar(List<int> h) =>
    h.length >= 7 &&
    h[0] == 0x52 &&
    h[1] == 0x61 &&
    h[2] == 0x72 &&
    h[3] == 0x21 &&
    h[4] == 0x1A &&
    h[5] == 0x07;
