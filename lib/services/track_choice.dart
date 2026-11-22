/// 画质 / 音轨 / 字幕轨的选择模型。
///
/// media_kit 把轨道暴露成 `AudioTrack` / `SubtitleTrack` / `VideoTrack`，每个
/// 都带一串 mpv 的原始字段（codec、demux-w、channels…），而这些字段大多是空的：
/// 一个 HLS 流只报 `codec`，本地 mp4 可能连 `language` 都没有。直接把它们铺到
/// 界面上就是一堆「1」「2」「3」。
///
/// 所以这里做两件事，都跟播放器无关、可以单测：
///
/// 1. [TrackOption] 把一条轨道压成「一行字 + 一行小字」——有标题用标题，没有就用
///    语言名，再没有才退回序号；分辨率、声道这些只在真有值时出现。
/// 2. [TrackPrefs] 记住「这条线路上次选的是哪条轨」，下一次打开同一个作品的同一
///    条线路时还原。记住的 id 在新的一条流里不存在就当作没记住（换集、换源之后
///    mpv 的轨道号不保证一致），绝不硬套。
library;

/// 一条可选轨道，去掉播放器类型后的纯数据。
class TrackOption {
  const TrackOption({
    required this.id,
    this.title,
    this.language,
    this.codec,
    this.channels,
    this.width,
    this.height,
    this.external = false,
  });

  /// mpv 的 track id（`1`、`2`…），或 media_kit 的 `auto` / `no`。
  final String id;

  /// 容器里写的轨道名，猫源/转码站常在这里写「国语」「粤语」。
  final String? title;

  /// ISO 639 语言码，可能是 `zh`、`chi`、`zho`、`cmn` 中的任意一种写法。
  final String? language;

  final String? codec;

  /// 音频声道数。
  final int? channels;

  /// 视频分辨率。
  final int? width;
  final int? height;

  /// 字幕是外挂的（源给的 `.srt` / `.ass` 网址），不是内嵌轨。
  final bool external;

  bool get isOff => id == 'no';
  bool get isAuto => id == 'auto';

  /// 面板上的主文字。
  String get label {
    final t = title?.trim();
    // 有些源把编码器名填进标题栏（"h264"、"AAC"），那不是给人看的标签。
    if (t != null && t.isNotEmpty && !_looksLikeCodec(t)) return t;
    final lang = _languageName(language);
    if (lang != null) return lang;
    // 外挂字幕的 id 是一整个 URL，念不出来；内嵌轨的 id 就是 mpv 的序号。
    if (int.tryParse(id) != null) return '轨道 $id';
    return external ? '外挂字幕' : '轨道';
  }

  /// 面板上的次要信息；没有任何可说的就返回 null（界面不留空位）。
  String? get detail {
    final parts = <String>[];
    if (width != null && height != null && width! > 0 && height! > 0) {
      parts.add('$width×$height');
    }
    final c = codec?.trim();
    if (c != null && c.isNotEmpty) parts.add(c.toUpperCase());
    if (channels != null && channels! > 0) parts.add('$channels 声道');
    if (external) parts.add('外挂');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  @override
  String toString() => 'TrackOption($id, $label${detail == null ? '' : ' · $detail'})';
}

/// 一条流当前能选的三组轨道，以及播放器正在用的那几条。
class TrackChoices {
  const TrackChoices({
    this.video = const [],
    this.audio = const [],
    this.subtitle = const [],
    this.videoId = 'auto',
    this.audioId = 'auto',
    this.subtitleId = 'auto',
  });

  /// 播放器还没报出轨道（打开的一瞬间）。
  static const TrackChoices none = TrackChoices();

  /// 真实轨道，不含 mpv 的 `auto` / `no` 占位。
  final List<TrackOption> video;
  final List<TrackOption> audio;
  final List<TrackOption> subtitle;

  final String videoId;
  final String audioId;
  final String subtitleId;

  /// 只有多于一条时才值得让用户选；一条视频轨的「画质」是个假选项。
  bool get hasVideoChoice => video.length > 1;
  bool get hasAudioChoice => audio.length > 1;

  /// 只要有字幕就值得给——「关闭」本身就是一个有用的选择。
  bool get hasSubtitleChoice => subtitle.isNotEmpty;

  bool get isEmpty => video.isEmpty && audio.isEmpty && subtitle.isEmpty;

  /// 当前字幕是不是关着的。
  bool get subtitleOff => subtitleId == 'no';

  TrackChoices copyWith({
    List<TrackOption>? video,
    List<TrackOption>? audio,
    List<TrackOption>? subtitle,
    String? videoId,
    String? audioId,
    String? subtitleId,
  }) {
    return TrackChoices(
      video: video ?? this.video,
      audio: audio ?? this.audio,
      subtitle: subtitle ?? this.subtitle,
      videoId: videoId ?? this.videoId,
      audioId: audioId ?? this.audioId,
      subtitleId: subtitleId ?? this.subtitleId,
    );
  }
}

/// 设置页里的「默认字幕」：新开一集、这部作品又没记住过选择时，先替观众挑
/// 哪一条字幕。
///
/// 它只是默认值，不是强制：观众在轨道面板里点过任何一条（包括「关闭」）之后，
/// 记住的是他点的那条（见 [TrackPrefs]），偏好不再插手。
enum SubtitlePref {
  /// 不动手，跟着播放器/容器的默认走。
  auto('auto'),

  /// 中文优先（含粤语）。
  chinese('zh'),

  english('en'),

  /// 默认不要字幕——内嵌字幕经常是硬塞进来的，不想看的人每次都要关。
  off('off');

  const SubtitlePref(this.slug);

  /// 存进设置里的值。用短码是因为它躺在 `shared_preferences` 的 JSON 里，
  /// 出问题时能直接读出来。
  final String slug;

  /// 认不出的值一律退回 [auto]：一份写坏的字幕偏好不该让播放失败。
  static SubtitlePref parse(Object? raw) {
    if (raw is SubtitlePref) return raw;
    if (raw is! String) return SubtitlePref.auto;
    for (final p in SubtitlePref.values) {
      if (p.slug == raw || p.name == raw) return p;
    }
    return SubtitlePref.auto;
  }

  /// 按偏好挑一条字幕，返回 mpv 的 track id；`null` 表示「没有意见」。
  ///
  /// `no` 在这里是一个合法的返回值——关掉字幕本身就是一种选择，播放页会把它
  /// 交给 `SubtitleTrack.no()`。
  String? pick(List<TrackOption> options) {
    switch (this) {
      case SubtitlePref.auto:
        return null;
      case SubtitlePref.off:
        return 'no';
      case SubtitlePref.chinese:
        return _firstMatching(options, const {'中文', '粤语'}, _chineseHints);
      case SubtitlePref.english:
        return _firstMatching(options, const {'英语'}, _englishHints);
    }
  }
}

/// 中文（含粤语）的常见写法。容器里 `language` 是空的，标题栏才写了「简体」。
const _chineseHints = ['中文', '简体', '繁体', '繁中', '简中', '粤语', 'chinese', 'chi', 'zho'];

const _englishHints = ['英文', '英语', 'english', 'eng'];

/// 先按 language 码认；码认出来了但语言不对就不再拿标题硬猜——那多半是
/// 「中文音轨 + 英文标题」这类错配，猜下去只会选错。
String? _firstMatching(
  List<TrackOption> options,
  Set<String> names,
  List<String> hints,
) {
  for (final o in options) {
    final lang = _languageName(o.language);
    if (lang != null) {
      if (names.contains(lang)) return o.id;
      continue;
    }
    final title = (o.title ?? '').trim().toLowerCase();
    if (title.isEmpty) continue;
    if (hints.any(title.contains)) return o.id;
  }
  return null;
}

/// 一条线路记住的轨道选择。
///
/// 存的是 mpv 的 track id。换一条线路、换一集之后 id 可能指向别的轨道，所以
/// 还原前必须用 [audioFor] / [subtitleFor] 核一遍：不在当前列表里就当没记住。
class TrackPrefs {
  const TrackPrefs({this.video, this.audio, this.subtitle});

  static const TrackPrefs empty = TrackPrefs();

  /// `null` 表示「跟着播放器默认走」，和「选了某一轨」是两件事。
  final String? video;
  final String? audio;
  final String? subtitle;

  bool get isEmpty => video == null && audio == null && subtitle == null;

  TrackPrefs withVideo(String? id) =>
      TrackPrefs(video: id, audio: audio, subtitle: subtitle);
  TrackPrefs withAudio(String? id) =>
      TrackPrefs(video: video, audio: id, subtitle: subtitle);
  TrackPrefs withSubtitle(String? id) =>
      TrackPrefs(video: video, audio: audio, subtitle: id);

  /// 记住的视频轨道 id，当前流里没有就返回 null。
  String? videoFor(List<TrackOption> options) => _present(video, options);

  String? audioFor(List<TrackOption> options) => _present(audio, options);

  /// 字幕额外认 `no`：关掉字幕是个合法状态，不该因为它不在列表里就丢掉。
  String? subtitleFor(List<TrackOption> options) {
    if (subtitle == 'no') return 'no';
    return _present(subtitle, options);
  }

  Map<String, String> toJson() => {
    if (video != null) 'video': video!,
    if (audio != null) 'audio': audio!,
    if (subtitle != null) 'subtitle': subtitle!,
  };

  /// 容错解析：一份坏掉的记忆只该让这一条线路回到默认，不该拖垮整个设置。
  factory TrackPrefs.fromJson(Object? raw) {
    if (raw is! Map) return TrackPrefs.empty;
    String? read(String key) {
      final v = raw[key];
      if (v is String && v.isNotEmpty) return v;
      if (v is num) return v.toInt().toString();
      return null;
    }

    return TrackPrefs(
      video: read('video'),
      audio: read('audio'),
      subtitle: read('subtitle'),
    );
  }

  @override
  String toString() =>
      'TrackPrefs(video: $video, audio: $audio, subtitle: $subtitle)';
}

String? _present(String? id, List<TrackOption> options) {
  if (id == null || id.isEmpty) return null;
  for (final o in options) {
    if (o.id == id) return id;
  }
  return null;
}

/// mpv 的 codec 短名，出现在标题栏时说明那不是一个人写的标签。
const _codecNames = {
  'h264',
  'h265',
  'hevc',
  'avc',
  'av1',
  'vp9',
  'vp8',
  'mpeg4',
  'aac',
  'ac3',
  'eac3',
  'ddp',
  'dts',
  'opus',
  'flac',
  'mp3',
  'vorbis',
  'truehd',
  'ass',
  'srt',
  'subrip',
  'webvtt',
  'pgs',
  'hdmv',
};

bool _looksLikeCodec(String s) {
  final t = s.trim().toLowerCase();
  if (_codecNames.contains(t)) return true;
  // "h264 (High)" / "AAC (LC)" 这类写法。
  final head = t.split(RegExp(r'[\s(]')).first;
  return _codecNames.contains(head);
}

/// ISO 639 语言码 → 中文名。认不出就返回 null，界面退回序号。
String? _languageName(String? code) {
  final c = code?.trim().toLowerCase();
  if (c == null || c.isEmpty || c == 'und' || c == 'unknown') return null;
  return switch (c) {
    'zh' || 'chi' || 'zho' || 'cmn' || 'chs' || 'cht' => '中文',
    'yue' || 'can' => '粤语',
    'en' || 'eng' => '英语',
    'ja' || 'jpn' => '日语',
    'ko' || 'kor' => '韩语',
    'fr' || 'fra' || 'fre' => '法语',
    'de' || 'deu' || 'ger' => '德语',
    'es' || 'spa' => '西班牙语',
    'ru' || 'rus' => '俄语',
    'th' || 'tha' => '泰语',
    'vi' || 'vie' => '越南语',
    'pt' || 'por' => '葡萄牙语',
    'it' || 'ita' => '意大利语',
    'ar' || 'ara' => '阿拉伯语',
    _ => null,
  };
}
