import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/store_scope.dart';
import '../../models/models.dart';
import '../../services/ai/subtitle_translate.dart';
import '../../services/cast/dlna.dart';
import '../../services/awake.dart';
import '../../services/danmaku/danmaku_api.dart';
import '../../services/danmaku/source_danmaku.dart';
import '../../services/hls_clean_proxy.dart';
import '../../services/playback_clock.dart';
import '../../services/picture.dart';
import '../../services/player_info.dart';
import '../../services/player/boss_key.dart';
import '../../services/player/keyboard_shortcuts.dart';
import '../../services/player/subtitle_file.dart';
import '../../services/player/volume_step.dart';
import '../../services/skip_rule.dart';
import '../../services/subtitle/sites.dart';
import '../../services/track_choice.dart';
import '../../services/track_map.dart';
import '../widgets/skip_panel.dart';
import '../widgets/cast_sheet.dart';
import '../widgets/danmaku_panel.dart';
import '../widgets/info_panel.dart';
import '../widgets/comments_dialog.dart';
import '../widgets/kernel_dialog.dart';
import '../widgets/subtitle_search_dialog.dart';
import '../widgets/subtitle_style.dart';
import '../widgets/track_panel.dart';
import '../widgets/picture_panel.dart';
import '../widgets/danmaku_layer.dart';
import '../widgets/player_info_overlay.dart';
import '../widgets/aspect_panel.dart';
import '../widgets/player_bar.dart';
import '../widgets/rate_panel.dart';
import '../widgets/episode_panel.dart';
import '../widgets/playback_error_overlay.dart';
import '../widgets/subtitle_panel.dart';

/// 播放页 — 全屏视频播放。
///
/// Renders the video through media_kit's libmpv backend and paints a minimal
/// control bar on top: play/pause, a draggable seek bar with the position and
/// duration, a rate picker and a volume slider. The controls fade away while
/// playing and reappear on hover or click.
///
/// The URL is resolved *before* this page opens (see [PlayerPage.open]): the
/// caller hands in a concrete [url] from the detail's [MediaItem.playLines] or
/// from the source's `play` action, so this page stays a pure renderer with no
/// knowledge of the spider.
///
/// Every seek goes through a [PlaybackClock]: the bar cannot be dragged before
/// the duration is known, a resume position is checked against the real
/// duration before it is replayed, and the final position is only persisted
/// when the session's timeline never changed under it.
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.title,
    required this.url,
    this.subtitle,
    this.quality,
    this.headers = const {},
    this.episodes = const [],
    this.episodeIndex,
    this.resume,
    this.skipGlobal = SkipRule.none,
    this.skipOverride = SkipOverride.none,
    this.skipEnabled = true,
    this.onSkip,
    this.initialVolume = 100,
    this.initialRate = 1.0,
    this.aspectFit = 'fit',
    this.pictureAdjust = PictureAdjust.none,
    this.onAspectFit,
    this.onPictureAdjust,
    this.infoFields = const [],
    this.miniProgress = false,
    this.infoPositions = const {},
    this.onInfoPositionsChanged,
    this.onMiniProgressChanged,
    this.subtitlePref = SubtitlePref.auto,
    this.subtitleSize = LcbSubtitleStyle.standard,
    this.secondarySubtitle = SecondarySubtitle.off,
    this.initialSubtitleFile,
    this.danmakuSources = const [],
    this.danmakuEnabled = false,
    this.danmakuBlockTop = false,
    this.danmakuBlockBottom = false,
    this.onDanmakuBlockTop,
    this.onDanmakuBlockBottom,
    this.buttonsIcon = false,
    this.decoderMode = 'hardware',
    this.onDecoderModeChanged,
    this.onIntroEnd,
    this.onOutroLength,
    this.aiConfig,
    this.danmakuService,
    this.lines = const [],
    this.lineIndex = 0,
    this.trackKey,
    this.trackPrefs = TrackPrefs.empty,
    this.onLine,
    this.onTrackPrefs,
    this.onEpisode,
    this.onClose,
    this.onProgress,
    this.onPrefs,
    this.onOutro,
    this.onSubtitleFile,
    this.awake,
    this.bossKey,
  });

  /// Title shown in the top bar.
  final String title;

  /// The playable URL (m3u8 / mp4 / …) handed to the player.
  final String url;

  /// Secondary line under the title, e.g. the site or line name.
  final String? subtitle;

  /// Quality label the source reports (the catvod `vod_remarks` field), e.g.
  /// `1080P` / `高清`. Shown in the top-left subtitle line, next to the
  /// episode and the decoded resolution.
  final String? quality;

  /// Headers the request needs. A WebDAV share has no token in its URL, so the
  /// Basic credential has to ride along here; every other source passes none.
  final Map<String, String> headers;

  /// Episode labels for the next/prev controls and the title suffix. Empty for
  /// films.
  final List<String> episodes;

  /// Index of the episode currently playing, when [episodes] is non-empty.
  final int? episodeIndex;

  /// Where to seek on open, for 续播. Carries the total it was recorded against
  /// so the clock can refuse it when the stream is a different cut.
  final ResumePoint? resume;

  /// How much of the head and tail the viewer asked to skip, from the settings
  /// page — the value every work uses unless it has an [skipOverride] of its own.
  /// [SkipRule.none] when the feature is off or nothing was configured; the
  /// player never guesses where an intro ends.
  final SkipRule skipGlobal;

  /// What this work set for itself; [SkipOverride.none] means "follow global".
  /// The rule actually in force is `skipGlobal.mergeOverride(skipOverride)`,
  /// derived here so the two halves cannot drift out of sync in the caller.
  final SkipOverride skipOverride;

  /// The 跳过片头片尾 master switch, so the panel can explain why a pick would
  /// have no effect instead of silently doing nothing.
  final bool skipEnabled;

  /// Called when the viewer picks an intro/outro for this work. The caller
  /// persists it and rebuilds with the merged [skip], which the clock adopts
  /// mid-session.
  final ValueChanged<SkipOverride>? onSkip;

  /// Volume (0-100) and speed to open with — the values the last session was
  /// left at, not a hardcoded 100 / 1.0×.
  final int initialVolume;
  final double initialRate;

  /// 画面比例短码（`AspectMode.slug`）。映射成 `BoxFit` 交给 `Video`。
  final String aspectFit;

  /// 画面调节五个量的当前值（亮度/对比度/饱和度/色相/伽马），值域 -100..100。
  final PictureAdjust pictureAdjust;

  /// 改画面比例 / 调节时通知上层持久化。
  final ValueChanged<String>? onAspectFit;
  final ValueChanged<PictureAdjust>? onPictureAdjust;

  /// 常驻信息浮层要显示的信息（有序）。空 = 不显示。这些信息来自 mpv 内核，
  /// 帧率/码率拿不到时显示 `--`（原版 ExoPlayer 也是这么处理的）。
  final List<PlayerInfoField> infoFields;

  /// 画面最底下的「迷你进度条」：常驻细线（蓝=已播、浅蓝=已缓冲），不随
  /// 操作菜单隐藏。
  final bool miniProgress;
  final Map<String, String> infoPositions;
  final ValueChanged<Map<String, String>>? onInfoPositionsChanged;
  final ValueChanged<bool>? onMiniProgressChanged;

  /// 设置页里的默认字幕：新开一集时先按它挑一条。这部作品已经记住过一条
  /// （包括「关闭」）时以记住的为准，偏好不插手。
  final SubtitlePref subtitlePref;

  /// 字幕字号，见 [LcbSubtitleStyle]。media_kit 把字幕画成 Flutter 文本，
  /// 所以这个值直接进 `Video` 的 `subtitleViewConfiguration`。
  final int subtitleSize;

  /// 次字幕：显示在画面上方，和主字幕组成双语对照。关掉就一条都不画。
  final SecondarySubtitle secondarySubtitle;

  /// 这一集记着的本地字幕文件。null 表示没挂过；文件被删掉时由这里再核一次，
  /// 核不过就当作没记过，并把记忆清掉。
  final String? initialSubtitleFile;

  /// 弹幕源（内置源在前）与总开关。开关来自设置页，播放页底栏可以临时改；
  /// 关掉时一个请求都不发。
  final List<DanmakuSource> danmakuSources;
  final bool danmakuEnabled;
  final bool danmakuBlockTop;
  final bool danmakuBlockBottom;
  final ValueChanged<bool>? onDanmakuBlockTop;
  final ValueChanged<bool>? onDanmakuBlockBottom;

  /// 原版 player_buttons：文字还是图标。
  final bool buttonsIcon;

  /// 设置页选的 mpv 解码方式：hardware / software。
  final String decoderMode;
  final ValueChanged<String>? onDecoderModeChanged;
  final ValueChanged<Duration>? onIntroEnd;
  final ValueChanged<Duration>? onOutroLength;

  /// AI 字幕翻译配置；null 表示用户还没填 Key。
  final AiTranslationConfig? aiConfig;

  /// 取弹幕用。整个应用共用一个实例（store 持有），以便同一部剧换集时命中缓存。
  final DanmakuService? danmakuService;

  /// The lines the source offers for this work, and which one is playing.
  ///
  /// Stepping to another line is not a track change: it resolves a different
  /// URL through the source, so this page hands the decision (and where the
  /// viewer was) back to the caller instead of trying it itself.
  final List<String> lines;
  final int lineIndex;
  final void Function(int index, ResumePoint carry)? onLine;

  /// Identifies "this work on this line" for remembering track picks, e.g.
  /// `'<item id>|<line name>'`. Null disables the remembering.
  final String? trackKey;

  /// Tracks the viewer picked on this line last time.
  final TrackPrefs trackPrefs;

  /// Called when the viewer picks a track, so the caller can persist it.
  final void Function(String key, TrackPrefs prefs)? onTrackPrefs;

  /// Invoked with the next episode index when the user steps; null hides the
  /// step controls (films).
  final ValueChanged<int>? onEpisode;

  final VoidCallback? onClose;

  /// Reports the final playback position and total duration when the player is
  /// torn down, so the shell can persist it for 续播.
  final void Function(Duration position, Duration duration)? onProgress;

  /// Reports the volume and speed the session ended on.
  final void Function(int volume, double rate)? onPrefs;

  /// Called once when playback reaches the tail the viewer asked to skip. The
  /// shell decides what that means (next episode, or just finish); null leaves
  /// the stream playing to its natural end.
  final VoidCallback? onOutro;

  /// 挂上 / 取消外挂字幕时通知上层，让它把这件事记在这一集上（原版的说法是
  /// 「下载的字幕记在这一集上，下次播这一集会自动挂上」）。
  final ValueChanged<String?>? onSubtitleFile;

  /// Screen-sleep guard. The shell passes one shared instance so switching
  /// episodes — which mounts the next player before disposing this one — cannot
  /// end with the lock released. Null falls back to a private one.
  final Awake? awake;

  /// Ctrl+Alt+H signal from the shell. When it fires the player pauses before
  /// the shell minimizes the window, so coming back never auto-plays.
  final BossKeyNotifier? bossKey;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

/// 播放页右下角那几个互斥面板：字幕 / 轨道 / 片头片尾 / 比例 / 画面 / 选集。
///
/// 字幕、比例、画面是三个按钮，对应原版底栏的三个文字按钮；轨道只在这一条流
/// 真的有多条线路/画质/音轨可切时才出现。
enum _PlayerPanel {
  rate,
  subtitle,
  danmaku,
  info,
  tracks,
  skip,
  aspect,
  picture,
  episodes
}

class _PlayerPageState extends State<PlayerPage> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  /// Decides every seek this session makes. Fed from the two streams below.
  late final PlaybackClock _clock = PlaybackClock(
    resume: widget.resume,
    skip: _mergedSkip,
  );

  /// The rule in force right now, and the one the clock was last told about.
  ///
  /// The master switch gates the merge as well, so a work's own override can
  /// never outlive "跳过片头片尾: 关" — otherwise turning the feature off in
  /// settings would leave some shows still jumping.
  SkipRule get _mergedSkip => widget.skipEnabled
      ? widget.skipGlobal.mergeOverride(widget.skipOverride)
      : SkipRule.none;
  late SkipRule _appliedSkip = _mergedSkip;

  late final Awake _awake = widget.awake ?? SystemAwake();

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<Duration>? _bufferSub;
  StreamSubscription<VideoParams>? _videoParamsSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<double>? _rateSub;
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<Track>? _trackSub;
  StreamSubscription<List<String>>? _subtitleSub;
  StreamSubscription<String>? _errorSub;
  VoidCallback? _bossListener;

  /// media_kit's track objects, indexed by mpv's track id, plus the options the
  /// panel renders — one mapping serves both, see [MappedTracks].
  MappedTracks _mapped = MappedTracks(const Tracks());

  TrackChoices _choices = TrackChoices.none;

  /// What the viewer picked on this line, restored once the real list arrives.
  TrackPrefs _prefs = TrackPrefs.empty;

  /// The remembered picks are applied exactly once. mpv reports `auto` and then
  /// its own default; without this flag the second event would overwrite the
  /// viewer's choice right after they made it.
  bool _restored = false;

  /// 次字幕：mpv 用 `secondary-sid` 选第二条轨，当前这一句从 media_kit 的
  /// `secondary-sub-text` 报出来，我们照主字幕的字号在画面上方自己画——两条
  /// 字幕走同一个渲染器，字号设置对它们才是一致的。
  String _secondaryText = '';

  /// AI 翻译出来的那一行，画在画面上方；没有真实次字幕时接它的位置。
  String _aiText = '';
  String _aiLastSource = '';
  bool _aiOn = false;
  Timer? _aiTimer;
  String? _secondaryId;
  bool _secondaryNoticed = false;

  /// 外挂字幕：当前挂着的文件、它的显示名，以及是否已经交给 mpv。
  String? _externalPath;
  String? _externalLabel;
  bool _externalAttached = false;
  bool _pickingSubtitle = false;

  /// 右下角那一个槽位：字幕 / 轨道 / 片头片尾 / 比例 / 画面 / 选集同时只会开
  /// 一个，所以存的是「现在开着哪个」而不是六个各管各的 bool。
  ///
  /// 以前是三个 bool 各自在 setState 里把别人关掉，加一个面板就要改三处；
  /// 拆到六个之后这种写法一定会漏。
  _PlayerPanel? _panel;

  /// 常驻信息浮层的开关。字段由设置页决定；这里只管这一场看不看。

  /// 画面比例与调节的当前值。比例从 widget 进来，调节滑一下改一下（同时下发
  /// mpv 属性 + 通知上层持久化），不额外存一份会漂移的状态。
  late String _aspectFit = widget.aspectFit;
  late PictureAdjust _adjust = widget.pictureAdjust;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  bool _playing = true;
  bool _buffering = false;
  double _volume = 100;
  double _rate = 1.0;
  bool _seeking = false;
  double _seekValue = 0;

  /// 播放器报出来的、还没出画面时的那句话。非空时画面上盖一层「这一集打不开」，
  /// 而不是让一片黑和加载中长得一模一样。
  String? _openError;
  bool _retrying = false;

  /// 常驻信息浮层的数据来源。分辨率从 `video-params` 来（首次解码出帧才有），
  /// 帧率/码率走 mpv 属性（`estimated-vf-fps` / `video-bitrate`），都是异步、
  /// 拿不到就空——浮层用 `--` 表示「还没有」。
  int? _dw;
  int? _dh;
  String? _fps;
  bool _infoProbed = false;

  /// The tail cut-off already fired for this session, so the episode counts as
  /// finished rather than "stopped at 96%".
  bool _completed = false;
  bool _outroHandled = false;

  /// A short-lived line explaining an automatic jump, so the viewer is not left
  /// wondering why the picture moved on its own.
  String? _notice;
  Timer? _noticeTimer;

  /// 这一集的弹幕、开关状态，以及上一次去要弹幕的结果。
  ///
  /// 开关来自设置页（`显示弹幕`），底栏的按钮只改这一次播放；[_danmakuNote]
  /// 存「为什么没有」——没源、要凭据、没匹配到，都要能在画面上说出来。
  List<DanmakuComment> _danmaku = const [];
  bool _danmakuOn = false;
  bool _danmakuLoading = false;
  bool _danmakuAsked = false;
  String? _danmakuNote;

  bool _fullScreen = false;
  bool _miniWindow = false;
  bool _maximized = false;
  late String _decoderMode;
  double _danmakuOpacity = 0.92;
  double _danmakuFontSize = 22;
  DlnaDevice? _castDevice;
  Rect? _savedBounds;

  bool _controlsVisible = true;
  Timer? _hideTimer;

  bool get _hasNext =>
      widget.episodes.isNotEmpty && widget.episodeIndex != null;

  @override
  void initState() {
    super.initState();
    _decoderMode = widget.decoderMode;
    windowManager.isMaximized().then((value) {
      if (mounted) setState(() => _maximized = value);
    });
    _prefs = widget.trackPrefs;
    _positionSub = _player.stream.position.listen((d) {
      if (!_seeking) _position = d;
      _clock.onPosition(d);
      _pumpClock();
      if (_clock.takeOutro()) _fireOutro();
      if (mounted) setState(() {});
    });
    _durationSub = _player.stream.duration.listen((d) {
      _clock.onDuration(d);
      if (d > Duration.zero) {
        _duration = d;
        // 有时长说明这一集真的开了：之前那句失败信息（如果还在）已经过期。
        _openError = null;
        _retrying = false;
      }
      _pumpClock();
      if (mounted) setState(() {});
    });
    // 播放器 / mpv 的报错。以前只 debugPrint，打不开时画面一片黑，和加载中
    // 分不出来；现在没出画面就把它摆出来，让「打不开」和「在加载」长得不一样。
    _errorSub = _player.stream.error.listen(_onPlaybackError);
    _bufferSub = _player.stream.buffer.listen((d) {
      if (_buffer == d) return;
      _buffer = d;
      if (mounted) setState(() {});
    });
    // 分辨率：`video-params/dw × dh` 首次解码出帧才报，之前都是 null。
    // 帧率/码率拿不到（或 mpv 还没算出来）时浮层显示 `--`，与原版一致。
    _videoParamsSub = _player.stream.videoParams.listen((p) {
      if (_dw == p.dw && _dh == p.dh) return;
      _dw = p.dw;
      _dh = p.dh;
      if (mounted) setState(() {});
      _probeInfo();
    });
    _playingSub = _player.stream.playing.listen((p) {
      _playing = p;
      if (mounted) setState(() {});
    });
    _player.stream.buffering.listen((b) {
      _buffering = b;
      if (mounted) setState(() {});
    });
    _volumeSub = _player.stream.volume.listen((v) {
      _volume = v;
      if (mounted) setState(() {});
    });
    _rateSub = _player.stream.rate.listen((r) {
      _rate = r;
      if (mounted) setState(() {});
    });
    _tracksSub = _player.stream.tracks.listen(_onTracks);
    // [0] 是主字幕（Video 自己画），[1] 是 `secondary-sub-text`。次字幕只能由
    // 我们画：media_kit 只把主字幕交给 `SubtitleViewConfiguration`。
    _subtitleSub = _player.stream.subtitle.listen((lines) {
      if (!mounted) return;
      // mpv 关掉 `secondary-sid` 之后仍会保留最后一行 `secondary-sub-text`，
      // 所以「关」这件事由这里拦：没有选次字幕轨时，一个字段都不画。
      final text = _secondaryId == null
          ? ''
          : (lines.length > 1 ? lines[1] : '');
      if (text != _secondaryText) setState(() => _secondaryText = text);
      if (_aiOn && lines.isNotEmpty) _scheduleAi(lines[0]);
    });
    _externalPath = widget.initialSubtitleFile;
    _trackSub = _player.stream.track.listen((t) {
      if (!mounted) return;
      // Together with the empty track list, mpv resets the selection to
      // `auto` when it unloads a finished stream. Keeping the last real
      // selection is what makes the panel still show which track was playing
      // on a paused final frame.
      final unloaded =
          t.video.id == 'auto' &&
          t.audio.id == 'auto' &&
          t.subtitle.id == 'auto';
      if (unloaded && !_choices.isEmpty) return;
      setState(() {
        _choices = _choices.copyWith(
          videoId: t.video.id,
          audioId: t.audio.id,
          subtitleId: t.subtitle.id,
        );
      });
      // 主字幕变了，次字幕要重新核一遍——不能和主字幕用同一条轨。
      _applySecondary();
    });

    // 老板键：shell 发信号时先停住再让它最小化，回来保持暂停。
    final boss = widget.bossKey;
    if (boss != null) {
      _bossListener = () => _player.pause();
      boss.addListener(_bossListener!);
    }

    // A viewer who starts an episode and walks away should come back to a
    // playing episode, not a locked screen.
    _awake.hold();
    _open();
    // 弹幕高亮默认关着：进播放页不发任何弹幕请求。设置里的「显示弹幕」只是
    // 允许，真正开还是关由底栏按钮决定——原版进页面不会先弹一句要 AppId。
  }

  Future<void> _applyDecoder() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await platform.setProperty(
        'hwdec',
        _decoderMode == 'software' ? 'no' : 'auto-safe',
      );
    } on Object {
      // 不支持的属性交给 mpv 自己忽略；不能因为一个解码偏好挡住播放。
    }
  }

  /// 原版顶栏闪电：当场切硬解/软解，不弹面板。
  void _toggleDecoder() {
    final next = _decoderMode == 'software' ? 'hardware' : 'software';
    setState(() => _decoderMode = next);
    widget.onDecoderModeChanged?.call(next);
    unawaited(_applyDecoder());
    _showNotice(next == 'software' ? '硬解已关：软件解码' : '硬解已开：硬件解码');
  }

  /// 原版顶栏 |<：把当前播放点设为片头结束，全集共用。
  void _setIntroEnd() {
    if (_duration <= Duration.zero || _position <= Duration.zero) {
      _showNotice('还没有可设置的片头位置');
      return;
    }
    widget.onIntroEnd?.call(_position);
    _showNotice('片头：以后每集跳过到 ${_mmss(_position)}');
  }

  /// 原版顶栏 >|：把当前剩余时长设为片尾长度，全集共用。
  void _setOutroLength() {
    final remaining = _duration - _position;
    if (remaining <= Duration.zero) {
      _showNotice('已经没有片尾可设置');
      return;
    }
    widget.onOutroLength?.call(remaining);
    _showNotice('片尾：以后每集提前 ${remaining.inSeconds} 秒结束');
  }

  void _showComments() => showCommentsDialog(context);

  // ---------------------------------------------------------------------------
  // Danmaku (弹幕)
  // ---------------------------------------------------------------------------

  /// 这一集对应的剧集名：有集号就用集号那一条，电影退化成「1」。
  String get _episodeLabel {
    final index = widget.episodeIndex;
    if (index == null || widget.episodes.isEmpty) return '1';
    if (index < 0 || index >= widget.episodes.length) return '${index + 1}';
    return widget.episodes[index];
  }

  /// 去弹幕源要这一集的弹幕。失败也要留一句话，不能只是"什么都没发生"。
  Future<void> _loadDanmaku() async {
    if (_danmakuLoading) return;
    if (danmakuSourcesNeedCredentials(widget.danmakuSources)) return;
    final service = widget.danmakuService;
    if (service == null) {
      setState(() => _danmakuNote = '弹幕服务没有初始化');
      return;
    }
    setState(() {
      _danmakuLoading = true;
      _danmakuNote = null;
    });
    final outcome = await service.load(
      title: widget.title,
      episode: _episodeLabel,
      sources: widget.danmakuSources,
    );
    if (!mounted) return;
    setState(() {
      _danmakuLoading = false;
      _danmakuAsked = true;
      _danmaku = outcome.episode?.comments ?? const [];
      _danmakuNote = outcome.hasContent ? null : outcome.message;
    });
    if (outcome.hasContent) {
      _showNotice(
        '弹幕已开 · ${_danmaku.length} 条'
        '（${outcome.episode!.match.label}）',
      );
    } else {
      _showNotice(outcome.message);
    }
  }

  void _toggleDanmakuPanel() => _togglePanel(_PlayerPanel.danmaku);

  void _toggleDanmaku() {
    final next = !_danmakuOn;
    if (next && danmakuSourcesNeedCredentials(widget.danmakuSources)) {
      // 用户主动想开才说一次；没读到配置就直接拦住，不发注定 401 的请求。
      _showNotice(
        '弹弹play 要求 AppId/AppSecret：到 dandanplay 开发者后台申请，'
        '填到「设置 → 弹幕源」后再开',
      );
      return;
    }
    setState(() => _danmakuOn = next);
    if (!next) {
      _showNotice('弹幕已关');
      return;
    }
    if (_danmaku.isNotEmpty) {
      _showNotice('弹幕已开 · ${_danmaku.length} 条');
      return;
    }
    // 上次没要到（没源 / 没匹配到）时，重新打开就再试一次，别把失败记一辈子。
    if (_danmakuAsked && _danmakuNote != null) _danmakuAsked = false;
    unawaited(_loadDanmaku());
  }

  Future<void> _open() async {
    _openError = null;
    _retrying = true;
    if (mounted) setState(() {});
    try {
      // Both are mpv properties, so they hold across the upcoming load.
      // hwdec must be set here, after the native player exists; doing it from
      // initState could hand mpv a property write before its handle is ready.
      await _applyDecoder();
      await _player.setVolume(widget.initialVolume.toDouble());
      await _player.setRate(widget.initialRate);
      final headers = <String, String>{'User-Agent': _ua, ...widget.headers};
      // Some CDNs splice an ad pod into the same HLS playlist; when it ends mpv
      // reports a new timeline and the bar jumps back to 00:00. Serve the
      // playlist through our loopback cleaner instead of handing the polluted
      // one to mpv. Non-HLS URLs are returned unchanged.
      final url = await HlsCleanProxy.instance.wrap(
        widget.url,
        headers: headers,
      );
      // `start` is only a hint: mpv applies it while loading and drops it for
      // some HLS streams. The clock verifies the landing and re-issues the seek
      // when it did not take, so this stays a fast path rather than the truth.
      await _player.open(
        Media(
          url,
          start: widget.resume?.position,
          httpHeaders: headers,
        ),
        play: true,
      );
    } catch (e) {
      debugPrint('LcbPlayer: open failed: $e');
      _onPlaybackError('$e');
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
    _scheduleHide();
  }

  /// 播放器报错：还没出画面才算「这一集打不开」。
  ///
  /// 收流正常之后 mpv 仍会零星报一些非致命错误（封面、章节、某条轨），那些
  /// 不该盖住正在放的画面，所以有时长就把它们只记进日志。
  ///
  /// 每次打开只留**第一条**。实测（`tool/verify_playback_error_live.dart`）同一个
  /// 失败会连着报两句：先是一句具体的（`tcp: Connection … failed` /
  /// `Cannot open file …`），再补一句笼统的 `Failed to open <url>.`。留下第一句
  /// 才说得清是网络、是文件还是地址。
  void _onPlaybackError(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    if (_duration > Duration.zero) {
      debugPrint('LcbPlayer: non-fatal player error: $text');
      return;
    }
    if (_openError != null) {
      debugPrint('LcbPlayer: follow-up error (kept the first): $text');
      return;
    }
    if (!mounted) return;
    setState(() {
      _openError = text;
      _retrying = false;
    });
  }

  void _retryOpen() {
    unawaited(_open());
  }

  // ---------------------------------------------------------------------------
  // Tracks (画质 / 音轨 / 字幕轨)
  // ---------------------------------------------------------------------------

  /// The stream published its track list — map it into what the panel shows,
  /// then (once) put back what the viewer had chosen on this line.
  ///
  /// mpv's `auto` / `no` entries are dropped here: they are control verbs, not
  /// tracks. 「关闭」 is added by the panel itself, where it means something.
  void _onTracks(Tracks tracks) {
    if (!mounted) return;
    final mapped = MappedTracks(tracks);
    // mpv publishes an empty list when it unloads the stream (EOF, a new
    // `loadfile` in flight). That is "nothing is loaded right now", not "this
    // stream has no tracks", so the panel keeps the last real list instead of
    // collapsing into "没有可切换的轨道" over a paused last frame.
    if (mapped.isEmpty) return;
    _mapped = mapped;
    setState(() {
      _choices = mapped.choicesFor(_player.state.track);
    });
    _restorePicks();
    // 轨道到齐说明文件已经加载完，这时候 sub-add 才会被 mpv 接受。
    _attachExternalIfNeeded();
    _applySecondary();
  }

  /// Applies the remembered picks once, and only to tracks that still exist.
  ///
  /// A new episode on the same line usually numbers its tracks the same way,
  /// but nothing guarantees it: an id that is gone means "no opinion", so the
  /// player keeps its default instead of jumping to whatever now holds that
  /// number.
  void _restorePicks() {
    if (_restored || _choices.isEmpty) return;
    _restored = true;
    final current = _player.state.track;

    final video = _prefs.videoFor(_choices.video);
    if (video != null && video != current.video.id) {
      _setVideo(video, remember: false);
    }
    final audio = _prefs.audioFor(_choices.audio);
    if (audio != null && audio != current.audio.id) {
      _setAudio(audio, remember: false);
    }
    final subtitle = _prefs.subtitleFor(_choices.subtitle);
    // 这部作品记住过的选择（含「关闭」）优先；没有记忆时才用设置页的默认
    // 偏好。`null` 表示偏好也没有意见，交给播放器自己的默认。
    final wanted = subtitle ?? widget.subtitlePref.pick(_choices.subtitle);
    if (wanted != null && wanted != current.subtitle.id) {
      _setSubtitle(wanted, remember: false);
    }
  }

  void _setVideo(String id, {bool remember = true}) {
    final track = _mapped.videoTrack(id);
    if (track == null) return;
    _player.setVideoTrack(track);
    if (remember) _remember(_prefs.withVideo(id));
  }

  void _setAudio(String id, {bool remember = true}) {
    final track = _mapped.audioTrack(id);
    if (track == null) return;
    _player.setAudioTrack(track);
    if (remember) _remember(_prefs.withAudio(id));
  }

  void _setSubtitle(String id, {bool remember = true}) {
    final track = _mapped.subtitleTrack(id);
    if (track == null) return;
    _player.setSubtitleTrack(track);
    if (remember) _remember(_prefs.withSubtitle(id));
    // 主字幕换了，次字幕可能正好换成了同一条：同一句话画两遍没有意义。
    _applySecondary();
  }

  // ---------------------------------------------------------------------------
  // 次字幕（secondary-sub）
  // ---------------------------------------------------------------------------

  /// 按设置挑一条次字幕交给 mpv，再把它报出来的文字画在画面上方。
  ///
  /// 挑不到就什么都不做——宁可只显示主字幕，也不要拿一条错的语言凑数。
  void _applySecondary() {
    final want = widget.secondarySubtitle;
    if (want == SecondarySubtitle.off) {
      if (_secondaryText.isNotEmpty) setState(() => _secondaryText = '');
      if (_secondaryId != null) _setSecondary('no');
      return;
    }
    if (_choices.subtitle.isEmpty) return;
    final id = want.pick(_choices.subtitle, primaryId: _choices.subtitleId);
    if (id == null) {
      // 设了次字幕却挑不到，得说一声——否则观众只会以为设置没生效。
      if (!_secondaryNoticed) {
        _secondaryNoticed = true;
        _showNotice('这条流没有可用的次字幕');
      }
      return;
    }
    if (id == _secondaryId) return;
    _setSecondary(id);
  }

  void _setSecondary(String id) {
    _secondaryId = id == 'no' ? null : id;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    // media_kit 没有暴露次字幕轨的 API，但 mpv 的属性可以直接设。
    unawaited(
      platform.command(['set', 'secondary-sid', id]).catchError((Object e) {
        debugPrint('LcbPlayer: secondary-sid failed: $e');
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // 外挂字幕（本地文件）
  // ---------------------------------------------------------------------------

  /// 打开文件选择器，把挑中的字幕挂上去并记在这一集上。
  void _scheduleAi(String source) {
    final text = source.trim();
    if (text.isEmpty || text == _aiLastSource) return;
    _aiTimer?.cancel();
    _aiTimer = Timer(const Duration(milliseconds: 400), () {
      _aiLastSource = text;
      unawaited(_translateLine(text));
    });
  }

  Future<void> _translateLine(String text) async {
    final config = widget.aiConfig;
    if (config == null || !config.ready) {
      _showNotice('请先到设置配置 AI 大模型和 API Key');
      if (mounted) setState(() => _aiOn = false);
      return;
    }
    try {
      final translated = await AiSubtitleTranslator.translate([text], config);
      if (!mounted) return;
      setState(() => _aiText = translated.isEmpty ? '' : translated.first);
    } on FormatException catch (error) {
      if (!mounted) return;
      _showNotice(error.message);
    }
  }

  void _toggleAiTranslation() {
    final next = !_aiOn;
    setState(() {
      _aiOn = next;
      if (!next) {
        _aiTimer?.cancel();
        _aiText = '';
        _aiLastSource = '';
      }
    });
    _showNotice(next ? 'AI 翻译已开' : 'AI 翻译已关');
  }

  Future<void> _searchSubtitles() async {
    final sites = [
      for (final raw in StoreScope.of(context).settings.subtitleSites)
        if ((raw['id'] as String?)?.isNotEmpty ?? false)
          SubtitleSite.fromJson(raw),
    ];
    final picked = await showDialog<SubtitleFile>(
      context: context,
      builder: (_) => SubtitleSearchDialog(sites: sites),
    );
    if (picked == null || !mounted) return;
    await _useSubtitleFile(picked);
  }

  Future<void> _pickSubtitleFile() async {
    if (_pickingSubtitle) return;
    _pickingSubtitle = true;
    try {
      final path = await chooseSubtitlePath();
      if (path == null || !mounted) return;
      final files = await openSubtitleFiles(path);
      if (files.isEmpty || !mounted) return;
      final picked = files.length == 1
          ? files.first
          : await _chooseFromArchive(files);
      if (picked == null || !mounted) return;
      await _useSubtitleFile(picked);
    } on SubtitleFileException catch (e) {
      _showNotice(e.message);
    } catch (e) {
      debugPrint('LcbPlayer: subtitle file failed: $e');
      _showNotice('字幕文件读取失败');
    } finally {
      _pickingSubtitle = false;
    }
  }

  /// 压缩包里有不止一条字幕时让用户挑；取消返回 null。
  Future<SubtitleFile?> _chooseFromArchive(List<SubtitleFile> files) {
    return showDialog<SubtitleFile>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        title: Text(
          '这个字幕包里有 ${files.length} 个字幕',
          style: const TextStyle(fontSize: 15, color: Colors.white),
        ),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final f in files)
                ListTile(
                  dense: true,
                  title: Text(
                    f.label,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                  ),
                  onTap: () => Navigator.of(context).pop(f),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _useSubtitleFile(SubtitleFile file) async {
    setState(() => _panel = null);
    _externalPath = file.path;
    _externalAttached = false;
    _attachExternalIfNeeded();
    widget.onSubtitleFile?.call(file.path);
    _showNotice('已加载字幕，下次播这一集会自动用它');
  }

  /// 把 [_externalPath] 交给 mpv。文件不在了就如实说，并请上层把记忆清掉。
  void _attachExternalIfNeeded() {
    final path = _externalPath;
    if (path == null || _externalAttached) return;
    _externalAttached = true;
    if (!File(path).existsSync()) {
      _externalPath = null;
      setState(() => _externalLabel = null);
      widget.onSubtitleFile?.call(null);
      _showNotice('字幕文件已丢失，记得重新选一个');
      return;
    }
    final name = path.split(Platform.pathSeparator).last;
    _player.setSubtitleTrack(
      SubtitleTrack.uri(
        Uri.file(path).toString(),
        title: name,
        language: 'und',
      ),
    );
    setState(() => _externalLabel = name);
  }

  /// 不再用外挂字幕：关掉字幕显示，并把这一集的记忆清掉（文件本身不动）。
  void _clearSubtitleFile() {
    setState(() {
      _externalPath = null;
      _externalLabel = null;
      _externalAttached = true;
      _panel = null;
    });
    _player.setSubtitleTrack(SubtitleTrack.no());
    widget.onSubtitleFile?.call(null);
    _showNotice('已取消外挂字幕');
  }

  /// Remembers a pick for this work+line so the next episode opens the same
  /// way. Written through the caller, which owns the settings store.
  void _remember(TrackPrefs next) {
    setState(() => _prefs = next);
    final key = widget.trackKey;
    if (key == null || key.isEmpty) return;
    widget.onTrackPrefs?.call(key, next);
  }

  void _toggleRatePanel() => _togglePanel(_PlayerPanel.rate);

  void _toggleSubtitlePanel() => _togglePanel(_PlayerPanel.subtitle);

  void _toggleTrackPanel() => _togglePanel(_PlayerPanel.tracks);

  void _toggleSkipPanel() => _togglePanel(_PlayerPanel.skip);

  Future<void> _toggleFullScreen() async {
    final next = !_fullScreen;
    await windowManager.setFullScreen(next);
    if (mounted) setState(() => _fullScreen = next);
  }

  /// 小窗：缩小并置顶，再点一次还原到原来的窗口位置。
  Future<void> _toggleMiniWindow() async {
    if (_miniWindow) {
      final bounds = _savedBounds;
      if (bounds != null) await windowManager.setBounds(bounds);
      await windowManager.setAlwaysOnTop(false);
      if (mounted) setState(() => _miniWindow = false);
      return;
    }
    _savedBounds = await windowManager.getBounds();
    await windowManager.setSize(const Size(480, 270));
    await windowManager.setAlwaysOnTop(true);
    if (mounted) setState(() => _miniWindow = true);
  }

  Future<void> _cast() async {
    final device = await showCastSheet(context);
    if (device == null || !mounted) return;
    try {
      await Dlna.play(device, widget.url, title: widget.title);
      if (!mounted) return;
      setState(() => _castDevice = device);
      _showNotice('正在投屏到 ${device.name}');
    } on DlnaException catch (error) {
      _showNotice('投屏失败：${error.message}');
    }
  }

  Future<void> _stopCast() async {
    final device = _castDevice;
    if (device == null) return;
    try {
      await Dlna.stop(device);
      if (!mounted) return;
      setState(() => _castDevice = null);
      _showNotice('已退出投屏');
    } on DlnaException catch (error) {
      _showNotice('投屏失败：${error.message}');
    }
  }

  Future<void> _screenshot() async {
    try {
      final bytes = await _player.screenshot();
      if (bytes == null) {
        _showNotice('截图失败：内核没有返回画面');
        return;
      }
      final home = Platform.environment['USERPROFILE'] ?? Directory.current.path;
      final dir = Directory('$home${Platform.pathSeparator}Pictures');
      if (!dir.existsSync()) await dir.create(recursive: true);
      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        'lcb-${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      _showNotice('截图已保存：${file.path}');
    } on Object catch (error) {
      _showNotice('截图失败：$error');
    }
  }


  void _toggleAspectPanel() => _togglePanel(_PlayerPanel.aspect);

  void _togglePicturePanel() => _togglePanel(_PlayerPanel.picture);

  void _toggleEpisodePanel() => _togglePanel(_PlayerPanel.episodes);

  /// 六个面板共用一个右下角槽位：同时只会开一个，再点同一个就收起来。
  void _togglePanel(_PlayerPanel panel) {
    _hideTimer?.cancel();
    setState(() {
      _controlsVisible = true;
      _panel = _panel == panel ? null : panel;
    });
  }

  void _closePanels() {
    if (_panel == null) return;
    setState(() => _panel = null);
  }

  void _toggleInfoPanel() => _togglePanel(_PlayerPanel.info);

  /// ±10 秒。时长还没报上来时不给落点，所以按钮本身就是灰的（调用方传 null）。
  void _nudge(Duration delta) {
    if (_duration <= Duration.zero) return;
    final target = _position + delta;
    final landed = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    _seekTo(landed);
    _showNotice(delta.isNegative ? '倒退 10 秒' : '前进 10 秒');
  }

  /// 选集面板点了某一集：交给上层重新解析并开播，和详情页选集的出口一致。
  void _pickEpisode(int index) {
    setState(() => _panel = null);
    if (index == widget.episodeIndex) return;
    widget.onEpisode?.call(index);
  }

  /// 换倍速：立即下发，收起面板，并在画面上说一句（速度是听得出来的，但
  /// 不知道自己按到了几倍速才是最难受的）。
  void _pickRate(double rate) {
    _player.setRate(rate);
    setState(() => _panel = null);
    _showNotice('${rate}x 播放');
  }

  /// 换画面比例：立即改 `BoxFit`，并通知上层记住。
  void _pickAspect(AspectMode mode) {
    // 比例一改整块画面就变了，面板留着只会挡住它。
    setState(() {
      _aspectFit = mode.slug;
      _panel = null;
    });
    widget.onAspectFit?.call(mode.slug);
  }

  /// 画面调节变了：先下发 mpv 属性（亮度等），再通知上层持久化。
  ///
  /// 每个量都对应一个 mpv 属性（`brightness` / `contrast` / `saturation` /
  /// `hue` / `gamma`），`no` 之外的数值直接 set。gamma 用 `gamma` 属性（mpv
  /// 原生，0 为原始），不套 eq 滤镜字符串——这样恢复默认也简单。
  void _applyAdjust(PictureAdjust next) {
    setState(() => _adjust = next);
    final platform = _player.platform;
    if (platform is NativePlayer) {
      for (final (prop, value) in next.mpvProperties) {
        unawaited(
          platform.command(['set', prop, '$value']).catchError((Object e) {
            debugPrint('LcbPlayer: set $prop failed: $e');
          }),
        );
      }
    }
    widget.onPictureAdjust?.call(next);
  }

  /// 读一次帧率 / 码率，喂给常驻信息浮层。
  ///
  /// 这两个没有对应的 media_kit stream，只能走 mpv 属性。它们要等流真正开始
  /// 解码才有值，所以挂在「分辨率报上来」这件事之后触发；只读一次，之后的
  /// 值对同一集不会变（换集是重新 mount 一个 PlayerPage，会重新触发）。
  void _probeInfo() {
    if (_infoProbed) return;
    _infoProbed = true;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    unawaited(() async {
      for (final (prop, set) in [
        ('estimated-vf-fps', (String v) => _fps = v),
      ]) {
        try {
          final v = await platform.getProperty(prop);
          if (!mounted) return;
          set(v);
        } catch (e) {
          debugPrint('LcbPlayer: $prop probe failed: $e');
        }
      }
      if (mounted) setState(() {});
    }());
  }

  /// A pick in the skip panel: hand it up to be stored, and adopt it here right
  /// away so a viewer who sets "90 秒" while sitting at 0:05 sees the jump now
  /// rather than at the next episode.
  void _pickSkip(SkipOverride next) {
    final merged = widget.skipGlobal.mergeOverride(next);
    _appliedSkip = merged;
    _clock.updateSkip(merged);
    setState(() => _panel = null);
    widget.onSkip?.call(next);
    _pumpClock();
    _showNotice(
      next.isEmpty
          ? '已恢复跟随全局设置'
          : '已记住本剧：片头 ${_skipSeconds(merged.intro)} · 片尾 ${_skipSeconds(merged.outro)}',
    );
  }

  String _skipSeconds(Duration d) =>
      d <= Duration.zero ? '不跳' : '${d.inSeconds} 秒';

  /// Another line means another URL: the caller resolves it and reopens the
  /// page. The viewer's position rides along so the switch looks like a track
  /// change rather than a restart.
  void _switchLine(int index) {
    if (index == widget.lineIndex) {
      setState(() => _panel = null);
      return;
    }
    final carry = ResumePoint(
      positionMs: _position.inMilliseconds,
      totalMs: _duration.inMilliseconds,
    );
    setState(() => _panel = null);
    widget.onLine?.call(index, carry);
  }

  /// Asks the clock what seek is owed and performs it. Called on every duration
  /// and position event; the clock drops the request once it has been taken, so
  /// this never double-seeks.
  void _pumpClock() {
    final target = _clock.pendingSeek();
    if (target == null) return;
    _player.seek(target);
    // Show where we asked to be, not the frame the player was still painting —
    // the label would otherwise flash 0:00 over a resumed episode.
    _position = target;
    final intro = _clock.skip.introFor(_clock.duration);
    if (intro != null && target == intro) {
      _showNotice('已跳过片头 ${intro.inSeconds} 秒');
    }
  }

  /// 滚轮调音量：向上滚 +5，向下滚 -5，夹在 mpv 的 0-100 里。
  ///
  /// 音量本来有一根底栏滑杆，原版没有那根滑杆，所以它挪到了滚轮上——音量是
  /// 边看边试的，挪进设置页反而更难用。真实值仍然跟着设置存。
  void _nudgeVolume(double dy) {
    final next = steppedVolume(_volume, dy);
    if (next == _volume) return;
    _player.setVolume(next);
    _showNotice(next <= 0 ? '已静音' : '音量 ${next.round()}');
  }

  void _showNotice(String text) {
    if (!mounted) return;
    _noticeTimer?.cancel();
    setState(() => _notice = text);
    _noticeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  /// The tail cut-off the viewer configured was reached: pause here and let the
  /// shell wrap up (next episode or back out). Marked completed first, because
  /// the caller may dispose this page immediately and we must not record "stopped
  /// 90 seconds before the end" as a resume point.
  void _fireOutro() {
    if (_outroHandled) return;
    _showNotice('已跳过片尾');
    _outroHandled = true;
    _completed = true;
    _player.pause();
    final callback = widget.onOutro;
    if (callback == null) return;
    // Hand over after the current stream event, otherwise the shell's rebuild
    // disposes the player the event is still being read from.
    scheduleMicrotask(() {
      if (mounted) callback();
    });
  }

  /// Every seek made from the UI goes through here, so a drag that happens
  /// before the timeline is known is held instead of landing on zero.
  void _seekTo(Duration target) {
    _clock.requestSeek(target);
    _pumpClock();
    if (mounted) setState(() {});
  }

  static const _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0 Safari/537.36';

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_playing) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _playing && !_seeking) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHide();
  }

  /// 键盘动作和滚轮 / 底栏按钮共用同一套实现，避免两处音量或落点算法分叉。
  /// 上箭头对应滚轮上滚（dy<0），所以传 -5；±10 秒直接走 [`_nudge`]。
  void _runShortcut(PlayerShortcut shortcut) {
    switch (shortcut) {
      case PlayerShortcut.volumeUp:
        _nudgeVolume(-5);
      case PlayerShortcut.volumeDown:
        _nudgeVolume(5);
      case PlayerShortcut.seekBack:
        _nudge(const Duration(seconds: -10));
      case PlayerShortcut.seekForward:
        _nudge(const Duration(seconds: 10));
      case PlayerShortcut.miniWindow:
        _toggleMiniWindow();
    }
  }

  Map<ShortcutActivator, VoidCallback> get _shortcutBindings => {
    for (final entry in playerShortcutBindings.entries)
      entry.key: () => _runShortcut(entry.value),
  };

  void _togglePlay() {
    if (_playing) {
      _player.pause();
    } else {
      _player.play();
    }
    _scheduleHide();
  }

  String get _currentLabel {
    final i = widget.episodeIndex;
    if (i != null && i < widget.episodes.length) return widget.episodes[i];
    return '';
  }

  /// The top bar's main line is the bare title — the episode, resolution and
  /// quality live on the subtitle line, exactly like the original.
  String get _titleLine => widget.title;

  /// The secondary line under the title: `第39集 · 1920×1080 · 1080P`. Each
  /// segment is optional and only joins when it has a value; the resolution
  /// appears once the video has decoded its first frame.
  String get _subtitleLine {
    final parts = <String>[
      if (_currentLabel.isNotEmpty) _currentLabel,
      if (_dw != null && _dh != null) '$_dw×$_dh',
      if (formatQualityLabel(widget.quality).isNotEmpty)
        formatQualityLabel(widget.quality),
    ];
    return parts.join(' · ');
  }

  /// 按原版「信息显示」的角标位置渲染：每一项可以独立钉在四个角。
  List<PlayerInfoFact> _factsFor(String spot) {
    final facts = <PlayerInfoFact>[];
    for (final entry in widget.infoPositions.entries) {
      if (entry.value != spot) continue;
      final label = switch (entry.key) {
        'battery' => '电量',
        'clock' => '当前时间',
        'frameRate' => '视频帧率',
        'resolution' => '分辨率',
        'progress' => '播放进度',
        'speed' => '网速',
        _ => '',
      };
      if (label.isEmpty) continue;
      final now = DateTime.now();
      final value = switch (entry.key) {
        'clock' => '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}',
        'frameRate' => formatFrameRate(_fps),
        'resolution' => formatResolution(_dw, _dh),
        'progress' => '${_mmss(_position)} / ${_mmss(_duration)}',
        _ => null, // 桌面没有电量/网速读数，显示 -- 而不是编造。
      };
      facts.add(PlayerInfoFact(label, value));
    }
    return facts;
  }

  Widget _infoCorner(String spot) {
    final facts = _factsFor(spot);
    if (facts.isEmpty) return const SizedBox.shrink();
    final left = spot == 'topLeft' || spot == 'bottomLeft';
    final top = spot == 'topLeft' || spot == 'topRight';
    return Positioned(
      top: top ? 76 : null,
      bottom: top ? null : 110,
      left: left ? 24 : null,
      right: left ? null : 24,
      child: IgnorePointer(child: PlayerInfoOverlay(facts: facts)),
    );
  }

  /// The caller may hand in a different skip rule mid-session (the viewer set
  /// this work's intro from the panel, and the shell saved it). The clock has to
  /// adopt it — but [PlaybackClock.updateSkip] keeps the resume point untouched,
  /// so this never yanks a viewer back to where they stopped.
  @override
  void didUpdateWidget(PlayerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _mergedSkip;
    if (next != _appliedSkip) {
      _appliedSkip = next;
      _clock.updateSkip(next);
    }
    if (oldWidget.url != widget.url) {
      // Same state object, new stream: nothing about the old timeline carries
      // over, so drop the panels rather than leaving stale choices on screen.
      _panel = null;
      // 换集就是换一集弹幕：把上一集的留在这儿会让画面继续飘上一集的字。
      _danmaku = const [];
      _danmakuAsked = false;
      _danmakuNote = null;
      if (_danmakuOn) unawaited(_loadDanmaku());
      // 换集就是换一集的外挂字幕与次字幕：上一集的轨号在这条流里没有意义。
      _externalPath = widget.initialSubtitleFile;
      _externalLabel = null;
      _externalAttached = false;
      _secondaryText = '';
      _secondaryId = null;
    }
  }

  @override
  void dispose() {
    if (_bossListener != null) {
      widget.bossKey?.removeListener(_bossListener!);
    }
    _hideTimer?.cancel();
    _noticeTimer?.cancel();
    _aiTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferSub?.cancel();
    _videoParamsSub?.cancel();
    _playingSub?.cancel();
    _volumeSub?.cancel();
    _rateSub?.cancel();
    _tracksSub?.cancel();
    _trackSub?.cancel();
    _subtitleSub?.cancel();
    _errorSub?.cancel();
    // Report the final position before tearing the player down; this is the
    // single reliable moment to capture where the user left off. Skip it when
    // the timeline moved under us — that position belongs to an ad segment or
    // another cut, and writing it would resume the viewer in the wrong place.
    if (_clock.recordable) {
      // A tail cut-off means the viewer is done with this episode: record the
      // full duration so the store treats it as watched instead of offering a
      // resume point ninety seconds before the credits.
      widget.onProgress?.call(_completed ? _duration : _position, _duration);
    } else {
      debugPrint(
        'LcbPlayer: dropped position $_position/$_duration '
        '(timeline changed during playback)',
      );
    }
    widget.onPrefs?.call(_volume.round(), _rate);
    _awake.release();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 打不开的时候控制条如果正好自动隐藏了，错误浮层又盖住了整块画面，
    // 用户就只剩下「重试 / 下一集」，连返回都摸不到。失败时把常驻控件
    // 钉回来，等下一集真正开了（duration 到了会清掉 _openError）再恢复自动隐藏。
    final chromeVisible = _controlsVisible || _openError != null;
    // 播放页盖在 shell 之上，焦点必须落在这里，方向键才不会被 shell 的
    // Ctrl+K / Esc 绑定吃掉。autofocus 只在首次进入时抢一次，之后焦点随着
    // 面板里的输入框自然转移，打字时不会误触音量。
    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: _shortcutBindings,
        child: Scaffold(
          backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Video(
              controller: _controller,
              controls: NoVideoControls,
              fit: AspectMode.parse(_aspectFit).boxFit,
              subtitleViewConfiguration: LcbSubtitleStyle.of(
                widget.subtitleSize,
              ),
            ),
          ),
          // 弹幕压在画面上、控制条之下：开关关掉或者没要到时这一层根本不存在，
          // 不留一个透明的空壳在上面对着手势层捣乱。
          if (_danmakuOn && _danmaku.isNotEmpty)
            DanmakuLayer(
              comments: _danmaku,
              position: _position,
              playing: _playing,
              blockTop: widget.danmakuBlockTop,
              blockBottom: widget.danmakuBlockBottom,
              fontSize: _danmakuFontSize,
              opacity: _danmakuOpacity,
            ),
          // 次字幕：mpv 把它当成第二条轨，文字从 `secondary-sub-text` 报过来，
          // 这里照主字幕的字号画在画面上方，和主字幕组成双语对照。
          if (_aiText.isNotEmpty || _secondaryText.isNotEmpty)
            Positioned(
              top: 84,
              left: 24,
              right: 24,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Text(
                      _aiText.isNotEmpty ? _aiText : _secondaryText,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: LcbSubtitleStyle.secondaryOf(widget.subtitleSize),
                    ),
                  ),
                ),
              ),
            ),
          // A single full-surface tap layer toggles the controls; it sits under
          // the bars so the bars' own buttons still win the hit test. The wheel
          // rides on top of it: 底栏那根音量滑杆原版没有，音量改由「在画面上
          // 滚」来调，滚一下 5%。
          Positioned.fill(
            child: Listener(
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  _nudgeVolume(event.scrollDelta.dy);
                }
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleControls,
                // 原版小窗是双击画面还原；这里照办，不用再回面板找入口。
                onDoubleTap: _miniWindow ? _toggleMiniWindow : null,
              ),
            ),
          ),
          // 打不开的时候把原因和能做的动作摆在画面中间；控制条仍在上面一层，
          // 所以「返回」和「切换线路」都还能用。
          if (_openError != null)
            Positioned.fill(
              child: PlaybackErrorOverlay(
                raw: _openError!,
                retrying: _retrying,
                onRetry: _retryOpen,
                onSwitchLine: widget.lines.length > 1 &&
                        TrackPanel.worthShowing(
                          choices: _choices,
                          lines: widget.lines,
                          onLine: widget.onLine == null ? null : _switchLine,
                        )
                    ? _toggleTrackPanel
                    : null,
              ),
            ),
          if (_notice != null)
            Positioned(
              top: 76,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xB3000000),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _notice!,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _TopBar(
              title: _titleLine,
              subtitle: _subtitleLine,
              onClose: widget.onClose,
              visible: chromeVisible,
              onKernel: () => showKernelDialog(context),
              hardware: _decoderMode != 'software',
              onToggleHardware: _toggleDecoder,
              onIntro: _setIntroEnd,
              onSkipSettings: _toggleSkipPanel,
              onOutro: _setOutroLength,
              onComments: _showComments,
              maximized: _maximized,
            ),
          ),
          // 常驻信息浮层：选中的信息钉在画面右上角，不随操作菜单隐藏（原版
          // 「信息显示」）。控制条消失时它还在，所以放在 _TopBar 之后、不受
          // visible 约束。
          ...[
            _infoCorner('topLeft'),
            _infoCorner('topRight'),
            _infoCorner('bottomLeft'),
            _infoCorner('bottomRight'),
          ],
          // 迷你进度条：画面最底下一根细线，蓝色=已播、浅蓝=已缓冲，常驻。
          if (widget.miniProgress)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: MiniProgressBar(
                  position: _position,
                  buffer: _buffer,
                  duration: _duration,
                ),
              ),
            ),
          // Tapping anywhere outside the panel closes it; it sits under the
          // panel but over the video, so the bar below keeps working. One layer
          // for all six: whichever is up, a click outside puts it away.
          if (_panel != null)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closePanels,
              ),
            ),
          if (_panel == _PlayerPanel.rate)
            Positioned(
              right: 20,
              bottom: 132,
              child: RatePanel(rate: _rate, onRate: _pickRate),
            ),
          if (_panel == _PlayerPanel.subtitle)
            Positioned(
              right: 20,
              bottom: 132,
              child: SubtitlePanel(
                choices: _choices,
                onSubtitle: (t) => _setSubtitle(t.id),
                externalSubtitleLabel: _externalLabel,
                onPickSubtitleFile: _pickSubtitleFile,
                onSearchSubtitles: _searchSubtitles,
                aiOn: _aiOn,
                onToggleAi: _toggleAiTranslation,
                onClearSubtitleFile: _externalLabel == null
                    ? null
                    : _clearSubtitleFile,
              ),
            ),
          if (_panel == _PlayerPanel.info)
            Positioned(
              right: 20,
              bottom: 132,
              child: InfoPanel(
                positions: widget.infoPositions,
                onChanged: (value) =>
                    widget.onInfoPositionsChanged?.call(value),
                miniProgress: widget.miniProgress,
                onMiniProgress: (value) =>
                    widget.onMiniProgressChanged?.call(value),
              ),
            ),
          if (_panel == _PlayerPanel.danmaku)
            Positioned(
              right: 20,
              bottom: 132,
              child: DanmakuPanel(
                on: _danmakuOn,
                onToggle: _toggleDanmaku,
                blockTop: widget.danmakuBlockTop,
                onBlockTop: (value) => widget.onDanmakuBlockTop?.call(value),
                blockBottom: widget.danmakuBlockBottom,
                onBlockBottom: (value) =>
                    widget.onDanmakuBlockBottom?.call(value),
                opacity: _danmakuOpacity,
                onOpacity: (value) =>
                    setState(() => _danmakuOpacity = value),
                fontSize: _danmakuFontSize,
                onFontSize: (value) =>
                    setState(() => _danmakuFontSize = value),
                hasSource: widget.danmakuSources.isNotEmpty,
              ),
            ),
          if (_panel == _PlayerPanel.tracks)
            Positioned(
              right: 20,
              bottom: 132,
              child: TrackPanel(
                choices: _choices,
                lines: widget.lines,
                lineIndex: widget.lineIndex,
                onLine: widget.onLine == null ? null : _switchLine,
                onVideo: (t) => _setVideo(t.id),
                onAudio: (t) => _setAudio(t.id),
              ),
            ),
          if (_panel == _PlayerPanel.skip)
            Positioned(
              right: 20,
              bottom: 132,
              child: SkipPanel(
                global: widget.skipGlobal,
                own: widget.skipOverride,
                effective: _clock.skip,
                enabled: widget.skipEnabled,
                onPicked: _pickSkip,
              ),
            ),
          if (_panel == _PlayerPanel.aspect)
            Positioned(
              right: 20,
              bottom: 132,
              child: AspectPanel(
                mode: AspectMode.parse(_aspectFit),
                onMode: _pickAspect,
              ),
            ),
          if (_panel == _PlayerPanel.picture)
            Positioned(
              right: 20,
              bottom: 132,
              child: PicturePanel(
                adjust: _adjust,
                onAdjust: _applyAdjust,
                onFullScreen: _toggleFullScreen,
                onMiniWindow: _toggleMiniWindow,
                onScreenshot: _screenshot,
                fullScreen: _fullScreen,
                miniWindow: _miniWindow,
                casting: _castDevice != null,
                onCast: _cast,
                onStopCast: _stopCast,
                onTracks: TrackPanel.worthShowing(
                  choices: _choices,
                  lines: widget.lines,
                  onLine: widget.onLine == null ? null : _switchLine,
                )
                    ? _toggleTrackPanel
                    : null,
              ),
            ),
          if (_panel == _PlayerPanel.episodes)
            Positioned(
              right: 20,
              bottom: 132,
              child: EpisodePanel(
                episodes: widget.episodes,
                currentIndex: widget.episodeIndex ?? -1,
                onPick: _pickEpisode,
              ),
            ),
          PlayerBar(
            playing: _playing,
            buffering: _buffering,
            position: _position,
            duration: _duration,
            rate: _rate,
            visible: chromeVisible,
            onTogglePlay: _togglePlay,
            onSeekStart: () => setState(() => _seeking = true),
            onSeekEnd: () {
              _seeking = false;
              final total = _duration.inMilliseconds;
              if (total <= 0) return; // bar is disabled; nothing to land on
              _seekTo(Duration(milliseconds: (_seekValue * total).round()));
              _scheduleHide();
            },
            onSeekChanged: (v) => _seekValue = v,
            onRatePanel: _toggleRatePanel,
            rateOpen: _panel == _PlayerPanel.rate,
            onSubtitle: _toggleSubtitlePanel,
            subtitleOpen: _panel == _PlayerPanel.subtitle,
            onDanmaku: _toggleDanmakuPanel,
            danmakuOn: _danmakuOn,
            danmakuAsking: _danmakuLoading,
            iconMode: widget.buttonsIcon,
            volume: _volume,
            onVolumeChanged: (value) => _player.setVolume(value),
            onMiniWindow: _toggleMiniWindow,
            onFullScreen: _toggleFullScreen,
            miniWindow: _miniWindow,
            fullScreen: _fullScreen,
            // 原版底栏没有「轨道」这一项：一条流的常见情况下这里没得换，
            // 按钮就不出现。真的有多条线路/画质/音轨时才补一个。
            onTracks:
                TrackPanel.worthShowing(
                  choices: _choices,
                  lines: widget.lines,
                  onLine: widget.onLine == null ? null : _switchLine,
                )
                ? _toggleTrackPanel
                : null,
            tracksOpen: _panel == _PlayerPanel.tracks,
            onAspect: _toggleAspectPanel,
            aspectOpen: _panel == _PlayerPanel.aspect,
            onPicture: _togglePicturePanel,
            pictureOpen: _panel == _PlayerPanel.picture,
            onInfo: _toggleInfoPanel,
            infoOpen: _panel == _PlayerPanel.info,
            onEpisodes: _toggleEpisodePanel,
            episodesOpen: _panel == _PlayerPanel.episodes,
            episodeCount: widget.episodes.length,
            onSkipPanel: _toggleSkipPanel,
            onCast: _cast,
            casting: _castDevice != null,
            onBack10: _duration > Duration.zero
                ? () => _nudge(const Duration(seconds: -10))
                : null,
            onForward10: _duration > Duration.zero
                ? () => _nudge(const Duration(seconds: 10))
                : null,
            onNext: _hasNext
                ? () => widget.onEpisode!(widget.episodeIndex! + 1)
                : null,
            onPrev: (widget.episodeIndex != null && widget.episodeIndex! > 0)
                ? () => widget.onEpisode!(widget.episodeIndex! - 1)
                : null,
          ),
        ],
      ),
        ),
      ),
    );
  }
}

/// The top-left header: a bare back arrow plus the title and an optional
/// second line. The original keeps no dark gradient strip here — the text sits
/// directly on the video with a soft shadow for legibility — so the video runs
/// all the way up underneath it.
/// 原版顶栏：左边是返回箭头 + 标题 + 「第N集 · 分辨率 · 画质」，右边是
/// `MPV ⚡ |< >> >| 💬` 加窗口按钮。整条只在控制条显示时出现。
/// 原版顶栏六项，实测自 BieCuiLe 播放窗口：
/// `MPV`(播放内核) / 闪电(硬解开关) / |<(把当前点设为片头结束) /
/// 紫色 >>(自动跳过片头片尾设置) / >|(把当前剩余设为片尾长度) / 评论抽屉。
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onClose,
    required this.visible,
    required this.onKernel,
    required this.hardware,
    required this.onToggleHardware,
    required this.onIntro,
    required this.onSkipSettings,
    required this.onOutro,
    required this.onComments,
    required this.maximized,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  final bool visible;
  final VoidCallback onKernel;
  final bool hardware;
  final VoidCallback onToggleHardware;
  final VoidCallback onIntro;
  final VoidCallback onSkipSettings;
  final VoidCallback onOutro;
  final VoidCallback onComments;
  final bool maximized;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !visible,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 0, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BackArrow(
                onTap: onClose ?? () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Color(0x99000000), blurRadius: 4),
                        ],
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFE0E0E4),
                          shadows: [
                            Shadow(color: Color(0x99000000), blurRadius: 4),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onKernel,
                      child: const Text(
                        'MPV',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Color(0x99000000), blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    _TopIcon(
                      icon: hardware ? Icons.bolt : Icons.offline_bolt,
                      tooltip: hardware ? '硬解已开，点击关闭' : '硬解已关，点击开启',
                      onTap: onToggleHardware,
                    ),
                    const SizedBox(width: 10),
                    _TopIcon(
                      icon: Icons.skip_previous,
                      tooltip: '片头：把当前点设为片头结束',
                      onTap: onIntro,
                    ),
                    const SizedBox(width: 10),
                    _TopIcon(
                      icon: Icons.fast_forward,
                      tooltip: '自动跳过片头片尾',
                      color: const Color(0xFFC8B6FF),
                      onTap: onSkipSettings,
                    ),
                    const SizedBox(width: 10),
                    _TopIcon(
                      icon: Icons.skip_next,
                      tooltip: '片尾：把当前剩余设为片尾长度',
                      onTap: onOutro,
                    ),
                    const SizedBox(width: 10),
                    _TopIcon(
                      icon: Icons.chat_bubble,
                      tooltip: '评论',
                      onTap: onComments,
                    ),
                    const SizedBox(width: 14),
                    _SmallWinButton(
                      icon: Icons.remove,
                      tooltip: '最小化',
                      onTap: () => windowManager.minimize(),
                    ),
                    _SmallWinButton(
                      icon: maximized ? Icons.filter_none : Icons.crop_square,
                      tooltip: maximized ? '还原' : '最大化',
                      onTap: () async {
                        if (await windowManager.isMaximized()) {
                          await windowManager.unmaximize();
                        } else {
                          await windowManager.maximize();
                        }
                      },
                    ),
                    _SmallWinButton(
                      icon: Icons.close,
                      tooltip: '关闭',
                      danger: true,
                      onTap: () => windowManager.close(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopIcon extends StatefulWidget {
  const _TopIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;

  @override
  State<_TopIcon> createState() => _TopIconState();
}

class _TopIconState extends State<_TopIcon> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 24,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? const Color(0x33FFFFFF) : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              widget.icon,
              size: 17,
              color: _hover ? Colors.white : widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallWinButton extends StatefulWidget {
  const _SmallWinButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_SmallWinButton> createState() => _SmallWinButtonState();
}

class _SmallWinButtonState extends State<_SmallWinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 38,
            height: 30,
            color: _hover
                ? (widget.danger
                    ? const Color(0xFFE81123)
                    : const Color(0x33FFFFFF))
                : Colors.transparent,
            child: Icon(widget.icon, size: 14, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// A bare, background-less back arrow that lights up on hover — the original
/// has no round plate around it, unlike the bottom bar's round buttons.
class _BackArrow extends StatefulWidget {
  const _BackArrow({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_BackArrow> createState() => _BackArrowState();
}

class _BackArrowState extends State<_BackArrow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Icon(
          Icons.arrow_back,
          size: 24,
          color: _hover ? Colors.white : const Color(0xFFE8E8EC),
        ),
      ),
    );
  }
}

/// The dark bottom strip: seek bar, play/pause, time, step controls, rate and
/// volume.

String _mmss(Duration d) {
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
