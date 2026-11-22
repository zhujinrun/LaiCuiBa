import 'dart:async';

import 'danmaku_api.dart';

/// 一集的弹幕，连同它是从哪个源、哪一集匹配来的。
class DanmakuEpisode {
  const DanmakuEpisode({
    required this.source,
    required this.match,
    required this.comments,
  });

  final DanmakuSource source;
  final DanmakuMatch match;
  final List<DanmakuComment> comments;

  int get count => comments.length;
}

/// 一次取弹幕的结果：要么拿到内容，要么拿到一句能读懂的原因。
///
/// 空结果也用 [message] 说明白（"没有匹配到"、"源要求 AppId"），播放页原样显示——
/// 不把"没弹幕"和"没接上"混成同一个沉默。
class DanmakuOutcome {
  const DanmakuOutcome._(this.episode, this.message);

  const DanmakuOutcome.ready(DanmakuEpisode episode) : this._(episode, '');

  const DanmakuOutcome.empty(String message) : this._(null, message);

  final DanmakuEpisode? episode;
  final String message;

  bool get hasContent => episode != null && episode!.count > 0;
}

/// 按「片名 + 集数」去弹幕源里找这一集。
///
/// 顺序与原版一致：先按片名和集数搜（播放页本来就知道这两样），搜不到再拿拼出来
/// 的文件名去 `/match`。一个源通了就不再问下一个；全部落空时把最有用的一句错误
/// 带上去（凭据问题比"没匹配到"更值得说）。
class DanmakuService {
  DanmakuService({
    DanmakuApi Function(DanmakuSource source)? apiFor,
    this.timeout = const Duration(seconds: 10),
  }) : _apiFor = apiFor ??
            ((source) => DanmakuApi(source, timeout: timeout));

  final DanmakuApi Function(DanmakuSource source) _apiFor;
  final Duration timeout;

  /// 同一个「片名|集数|源」只问一次。换集自然换 key，不做过期策略——
  /// 一集的弹幕在一场播放里不会变。
  final Map<String, DanmakuEpisode> _cache = {};

  /// 源按「内置在前的用户配置」顺序试，`enabled == false` 的直接跳过。
  Future<DanmakuOutcome> load({
    required String title,
    required String episode,
    required List<DanmakuSource> sources,
    String? fileHash,
    int? fileSize,
    int? durationMs,
  }) async {
    final usable = sources.where((s) => s.enabled).toList();
    if (usable.isEmpty) {
      return const DanmakuOutcome.empty('还没有可用的弹幕源，去 设置 → 弹幕 里加一个');
    }
    final number = episodeNumber(episode);
    final fileName = _fileName(title, episode);
    String? firstError;

    for (final source in usable) {
      final key = '$title|${number ?? episode}|${source.id}';
      final cached = _cache[key];
      if (cached != null) return DanmakuOutcome.ready(cached);

      final api = _apiFor(source);
      try {
        final match = await _match(api, title, episode, number, fileName,
            fileHash: fileHash, fileSize: fileSize, durationMs: durationMs);
        if (match == null) continue;
        final comments = await api.comments(match.episodeId);
        if (comments.isEmpty) continue;
        final hit = DanmakuEpisode(
          source: source,
          match: match,
          comments: comments,
        );
        _cache[key] = hit;
        return DanmakuOutcome.ready(hit);
      } on DanmakuException catch (e) {
        firstError ??= e.message;
      } on TimeoutException {
        firstError ??= '「${source.name}」超时了';
      } catch (e) {
        firstError ??= '「${source.name}」出错了：$e';
      } finally {
        api.close();
      }
    }
    return DanmakuOutcome.empty(
      firstError ?? '没有匹配到弹幕，可以换个片名再试，或在这集手动选一个',
    );
  }

  /// 换片名重试时把旧的否定结果一起丢掉。
  void clearCache() => _cache.clear();

  Future<DanmakuMatch?> _match(
    DanmakuApi api,
    String title,
    String episode,
    int? number,
    String fileName, {
    String? fileHash,
    int? fileSize,
    int? durationMs,
  }) async {
    if (number != null) {
      final found = await api.searchEpisodes(title, '$number');
      if (found.isNotEmpty) return found.first;
    }
    final matched = await api.matchFile(
      fileName: fileName,
      fileHash: fileHash,
      fileSize: fileSize,
      durationMs: durationMs,
    );
    return matched.isEmpty ? null : matched.first;
  }

  /// 拼一个"像文件名"的字符串给 `/match`：`[LaiCuiBa] 三体 - 第01集.mp4`。
  /// 服务器只认文件名里的片名与集数，扩展名随便给一个常见的即可。
  static String _fileName(String title, String episode) {
    final n = episodeNumber(episode);
    final ep = n == null ? episode : '第${n.toString().padLeft(2, '0')}集';
    return '[LaiCuiBa] $title - $ep.mp4';
  }
}
