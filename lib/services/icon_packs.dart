import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

import 'source_import.dart' show appDataDirectory;

/// One imported 图标包. The pack lives under the app's own data folder; only
/// the names are stored in `packs.json`, so deleting a ZIP afterwards is safe.
class IconPack {
  const IconPack({
    required this.id,
    required this.name,
    required this.suggestedName,
    required this.files,
  });

  /// The `id` from `icon-pack.json`, not a filesystem name we invented.
  final String id;

  /// The name shown in the settings page — always editable, always local.
  final String name;

  /// The name the ZIP asked for. Renaming never overwrites this.
  final String suggestedName;

  /// Image file names inside the pack directory, in import order.
  final List<String> files;

  int get count => files.length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'suggestedName': suggestedName,
    'files': files,
  };

  factory IconPack.fromJson(Map<String, dynamic> json) => IconPack(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    suggestedName: json['suggestedName'] as String? ?? '',
    files: [
      for (final file in (json['files'] as List?) ?? const [])
        if (file is String) file,
    ],
  );

  IconPack copyWith({String? name, List<String>? files}) => IconPack(
    id: id,
    name: name ?? this.name,
    suggestedName: suggestedName,
    files: files ?? this.files,
  );
}

/// A validation failure whose message is the original's own wording — the
/// settings page prints it as-is instead of inventing a friendlier lie.
class IconPackException implements Exception {
  const IconPackException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Imports, names and deletes 源图标包.
///
/// Layout (next to `shared_preferences.json`, see [appDataDirectory]):
///
/// ```
/// icon_packs/packs.json             pack metadata
/// icon_packs/packs/<id>/<file>      extracted images
/// icon_packs/custom/<sourceId>.ext  icons already applied to a source
/// ```
///
/// An applied icon is copied out of the pack before it is written to a source.
/// That is 原版's 「已经设置到资源上的图标已单独保存，不受影响」: deleting a
/// pack never leaves a resource pointing at a file that no longer exists.
class IconPacks {
  IconPacks._();

  /// Test seam — keeps unit tests off the user's real APPDATA folder.
  static Directory? directoryOverride;

  static const maxZipBytes = 100 * 1024 * 1024;
  static const maxFiles = 500;
  static const maxUncompressedBytes = 200 * 1024 * 1024;

  static final RegExp _packId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
  static const _imageExts = {'webp', 'png', 'jpg', 'jpeg', 'gif', 'bmp'};

  static Directory directory() {
    final base = directoryOverride ?? appDataDirectory();
    return Directory('${base.path}${Platform.pathSeparator}icon_packs');
  }

  static File _manifestFile() =>
      File('${directory().path}${Platform.pathSeparator}packs.json');

  static Directory _packDir(String id) =>
      Directory('${directory().path}${Platform.pathSeparator}packs'
      '${Platform.pathSeparator}$id');

  static Directory _customDir() =>
      Directory('${directory().path}${Platform.pathSeparator}custom');

  /// The manifest is a few kilobytes, so it is read synchronously: a settings
  /// page must have its pack list on the first frame, not one I/O turn later.
  static List<IconPack> load() {
    final file = _manifestFile();
    if (!file.existsSync()) return <IconPack>[];
    try {
      final data = jsonDecode(file.readAsStringSync());
      final packs = <IconPack>[
        for (final raw in (data is Map ? data['packs'] : null) ?? const [])
          if (raw is Map)
            IconPack.fromJson(Map<String, dynamic>.from(raw)),
      ]..removeWhere((pack) => pack.id.isEmpty);
      return packs;
    } on Object {
      // A corrupt manifest is a visible empty list, never a crash on settings.
      return <IconPack>[];
    }
  }

  static Future<void> _save(List<IconPack> packs) async {
    final dir = directory();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _manifestFile().writeAsStringSync(
      jsonEncode({'packs': [for (final pack in packs) pack.toJson()]}),
      flush: true,
    );
  }

  /// Validates and extracts one ZIP. Same `id` merges into the existing pack
  /// (原版「合并」), keeping the local name the user already chose.
  static Future<IconPack> importZip(String zipPath) async {
    final source = File(zipPath);
    if (!source.existsSync()) {
      throw const IconPackException('图标包读取失败');
    }
    if (source.lengthSync() > maxZipBytes) {
      throw const IconPackException('图标包不能超过 100 MB');
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(
        await source.readAsBytes(),
        verify: true,
      );
    } on Object {
      throw const IconPackException('图标包读取失败');
    }

    final manifestEntry = archive.files.firstWhere(
      (file) => file.isFile && file.name == 'icon-pack.json',
      orElse: () => throw const IconPackException('ZIP 根目录缺少 icon-pack.json'),
    );
    Map<String, dynamic> manifest;
    try {
      final decoded = jsonDecode(utf8.decode(manifestEntry.content as List<int>));
      if (decoded is! Map) throw const FormatException();
      manifest = Map<String, dynamic>.from(decoded);
    } on Object {
      throw const IconPackException('icon-pack.json 格式不正确');
    }
    final id = manifest['id'] as String? ?? '';
    if (!_packId.hasMatch(id)) {
      throw const IconPackException('图标包编号不正确');
    }
    final kind = manifest['kind'] as String?;
    if (kind != null && kind != 'source-icons') {
      throw const IconPackException('不是本应用的源图标包');
    }
    final suggested = (manifest['name'] as String? ?? '').trim();
    final suggestedName = suggested.isEmpty ? '未命名图标包' : suggested;

    final images = <ArchiveFile>[];
    final seen = <String>{};
    var uncompressed = 0;
    for (final file in archive.files) {
      if (!file.isFile || file.name == 'icon-pack.json') continue;
      final name = _safeName(file.name);
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      if (!_imageExts.contains(ext)) continue;
      if (seen.contains(name)) {
        throw const IconPackException('图标包包含重复文件');
      }
      seen.add(name);
      uncompressed += file.size;
      if (uncompressed > maxUncompressedBytes) {
        throw const IconPackException('图标包解压后过大');
      }
      if (images.length >= maxFiles) {
        throw const IconPackException('图标包文件数量过多');
      }
      images.add(file);
    }
    if (images.isEmpty) {
      throw const IconPackException('图标包里没有有效图片');
    }

    final packs = load();
    final index = packs.indexWhere((pack) => pack.id == id);
    final existing = index >= 0 ? packs[index] : null;
    final files = <String>[...(existing?.files ?? const <String>[])];
    final used = files.toSet();
    var written = 0;
    final packDir = _packDir(id);
    if (!packDir.existsSync()) await packDir.create(recursive: true);
    for (final file in images) {
      final base = _safeName(file.name).split('.').first;
      var stored = '${written.toString().padLeft(3, '0')}_$base.${_extOf(file.name)}';
      while (used.contains(stored)) {
        written++;
        stored = '${written.toString().padLeft(3, '0')}_$base.${_extOf(file.name)}';
      }
      used.add(stored);
      final bytes = file.content as List<int>;
      await File('${packDir.path}${Platform.pathSeparator}$stored')
          .writeAsBytes(bytes, flush: true);
      files.add(stored);
      written++;
    }

    final pack = IconPack(
      id: id,
      name: existing?.name ?? suggestedName,
      suggestedName: suggestedName,
      files: files,
    );
    if (index >= 0) {
      packs[index] = pack;
    } else {
      packs.add(pack);
    }
    await _save(packs);
    return pack;
  }

  static Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const IconPackException('请填写图标包名称');
    }
    final packs = load();
    final index = packs.indexWhere((pack) => pack.id == id);
    if (index < 0) return;
    packs[index] = packs[index].copyWith(name: trimmed);
    await _save(packs);
  }

  static Future<void> delete(String id) async {
    final packs = load();
    packs.removeWhere((pack) => pack.id == id);
    await _save(packs);
    final dir = _packDir(id);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }

  /// Copies an image out of its pack into the per-source slot, so an applied
  /// icon survives 图标包已删除. Returns the path to store on [SourceInfo].
  static Future<String> applyPackIcon(
    String sourceId,
    IconPack pack,
    String file,
  ) async {
    final source = File('${_packDir(pack.id).path}${Platform.pathSeparator}$file');
    if (!source.existsSync()) {
      throw const IconPackException('图标选择失败：');
    }
    return _copyToSource(sourceId, source);
  }

  /// Applies a local image file (原版「选择图标文件」).
  static Future<String> applyFile(String sourceId, String filePath) async {
    final source = File(filePath);
    if (!source.existsSync() || !_imageExts.contains(_extOf(filePath))) {
      throw const IconPackException('图标选择失败：');
    }
    return _copyToSource(sourceId, source);
  }

  static Future<String> _copyToSource(String sourceId, File source) async {
    final dir = _customDir();
    if (!dir.existsSync()) await dir.create(recursive: true);
    final safe = sourceId.isEmpty
        ? 'source'
        : sourceId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final target = File(
      '${dir.path}${Platform.pathSeparator}$safe.${_extOf(source.path)}',
    );
    await source.copy(target.path);
    return target.path;
  }

  /// Rejects traversal, absolute paths and Windows drive prefixes before any
  /// entry is written. Backslashes in ZIPs are always a trick, not a separator.
  static String _safeName(String raw) {
    final name = raw.replaceAll('\\', '/');
    final segments = name.split('/');
    if (segments.any((part) => part == '..' || part == '.' || part.isEmpty)) {
      throw const IconPackException('图标包包含不安全的路径');
    }
    if (name.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(name)) {
      throw const IconPackException('图标包包含不安全的路径');
    }
    return segments.last;
  }

  static String _extOf(String name) {
    final base = name.split('/').last;
    if (!base.contains('.')) return 'webp';
    return base.split('.').last.toLowerCase();
  }
}
