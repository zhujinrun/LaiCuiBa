import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/awake.dart';
import '../../services/danmaku/danmaku_api.dart';
import '../../services/danmaku/source_danmaku.dart';
import '../../services/playback_clock.dart';
import '../../services/picture.dart';
import '../../services/player/subtitle_file.dart';
import '../../services/skip_rule.dart';
import '../../services/track_choice.dart';
import '../../services/track_map.dart';
import '../widgets/skip_panel.dart';
import '../widgets/subtitle_style.dart';
import '../widgets/track_panel.dart';
import '../widgets/picture_panel.dart';
import '../widgets/danmaku_layer.dart';

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
    this.subtitlePref = SubtitlePref.auto,
    this.subtitleSize = LcbSubtitleStyle.standard,
    this.secondarySubtitle = SecondarySubtitle.off,
    this.initialSubtitleFile,
    this.danmakuSources = const [],
    this.danmakuEnabled = false,
    this.danmakuBlockTop = false,
    this.danmakuBlockBottom = false,
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
  });

  /// Title shown in the top bar.
  final String title;

  /// The playable URL (m3u8 / mp4 / …) handed to the player.
  final String url;

  /// Secondary line under the title, e.g. the site or line name.
  final String? subtitle;

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

  @override
  State<PlayerPage> createState() => _PlayerPageState();
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
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<double>? _rateSub;
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<Track>? _trackSub;
  StreamSubscription<List<String>>? _subtitleSub;

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
  String? _secondaryId;
  bool _secondaryNoticed = false;

  /// 外挂字幕：当前挂着的文件、它的显示名，以及是否已经交给 mpv。
  String? _externalPath;
  String? _externalLabel;
  bool _externalAttached = false;
  bool _pickingSubtitle = false;

  bool _trackPanel = false;

  /// The 本剧片头片尾 panel. Shares the slot with [_trackPanel]: both are bottom
  /// right pop-ups and stacking them would bury the lower one.
  bool _skipPanel = false;

  /// 画面面板（比例 + 调节）。和上面两个面板共用一个右下角槽位。
  bool _picturePanel = false;

  /// 画面比例与调节的当前值。比例从 widget 进来，调节滑一下改一下（同时下发
  /// mpv 属性 + 通知上层持久化），不额外存一份会漂移的状态。
  late String _aspectFit = widget.aspectFit;
  late PictureAdjust _adjust = widget.pictureAdjust;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = true;
  bool _buffering = false;
  double _volume = 100;
  double _rate = 1.0;
  bool _seeking = false;
  double _seekValue = 0;

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

  bool _controlsVisible = true;
  Timer? _hideTimer;

  bool get _hasNext => widget.episodes.isNotEmpty && widget.episodeIndex != null;

  @override
  void initState() {
    super.initState();
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
      if (d > Duration.zero) _duration = d;
      _pumpClock();
      if (mounted) setState(() {});
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
      if (text == _secondaryText) return;
      setState(() => _secondaryText = text);
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

    // A viewer who starts an episode and walks away should come back to a
    // playing episode, not a locked screen.
    _awake.hold();
    _open();
    if (widget.danmakuEnabled) {
      _danmakuOn = true;
      // 弹幕和视频是两条独立的路：视频先开，弹幕在后台去要，谁先到都不影响谁。
      unawaited(_loadDanmaku());
    }
  }

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
      _showNotice('弹幕已开 · ${_danmaku.length} 条'
          '（${outcome.episode!.match.label}）');
    } else {
      _showNotice(outcome.message);
    }
  }

  void _toggleDanmaku() {
    final next = !_danmakuOn;
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
    try {
      // Both are mpv properties, so they hold across the upcoming load.
      await _player.setVolume(widget.initialVolume.toDouble());
      await _player.setRate(widget.initialRate);
      // `start` is only a hint: mpv applies it while loading and drops it for
      // some HLS streams. The clock verifies the landing and re-issues the seek
      // when it did not take, so this stays a fast path rather than the truth.
      await _player.open(
        Media(
          widget.url,
          start: widget.resume?.position,
          httpHeaders: {'User-Agent': _ua, ...widget.headers},
        ),
        play: true,
      );
    } catch (e) {
      debugPrint('LcbPlayer: open failed: $e');
    }
    _scheduleHide();
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
    setState(() => _trackPanel = false);
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
      _trackPanel = false;
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

  void _toggleTrackPanel() {
    _hideTimer?.cancel();
    setState(() {
      _controlsVisible = true;
      _trackPanel = !_trackPanel;
      if (_trackPanel) {
        _skipPanel = false;
        _picturePanel = false;
      }
    });
  }

  void _toggleSkipPanel() {
    _hideTimer?.cancel();
    setState(() {
      _controlsVisible = true;
      _skipPanel = !_skipPanel;
      if (_skipPanel) {
        _trackPanel = false;
        _picturePanel = false;
      }
    });
  }

  void _togglePicturePanel() {
    _hideTimer?.cancel();
    setState(() {
      _controlsVisible = true;
      _picturePanel = !_picturePanel;
      if (_picturePanel) {
        _trackPanel = false;
        _skipPanel = false;
      }
    });
  }

  /// 换画面比例：立即改 `BoxFit`，并通知上层记住。
  void _pickAspect(AspectMode mode) {
    setState(() => _aspectFit = mode.slug);
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
          platform
              .command(['set', prop, '$value'])
              .catchError((Object e) {
                debugPrint('LcbPlayer: set $prop failed: $e');
              }),
        );
      }
    }
    widget.onPictureAdjust?.call(next);
  }

  /// A pick in the skip panel: hand it up to be stored, and adopt it here right
  /// away so a viewer who sets "90 秒" while sitting at 0:05 sees the jump now
  /// rather than at the next episode.
  void _pickSkip(SkipOverride next) {
    final merged = widget.skipGlobal.mergeOverride(next);
    _appliedSkip = merged;
    _clock.updateSkip(merged);
    setState(() => _skipPanel = false);
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
      setState(() => _trackPanel = false);
      return;
    }
    final carry = ResumePoint(
      positionMs: _position.inMilliseconds,
      totalMs: _duration.inMilliseconds,
    );
    setState(() => _trackPanel = false);
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

  String get _titleLine {
    final label = _currentLabel;
    if (label.isEmpty) return widget.title;
    return '${widget.title} · $label';
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
      _trackPanel = false;
      _skipPanel = false;
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
    _hideTimer?.cancel();
    _noticeTimer?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    _volumeSub?.cancel();
    _rateSub?.cancel();
    _tracksSub?.cancel();
    _trackSub?.cancel();
    _subtitleSub?.cancel();
    // Report the final position before tearing the player down; this is the
    // single reliable moment to capture where the user left off. Skip it when
    // the timeline moved under us — that position belongs to an ad segment or
    // another cut, and writing it would resume the viewer in the wrong place.
    if (_clock.recordable) {
      // A tail cut-off means the viewer is done with this episode: record the
      // full duration so the store treats it as watched instead of offering a
      // resume point ninety seconds before the credits.
      widget.onProgress?.call(
        _completed ? _duration : _position,
        _duration,
      );
    } else {
      debugPrint('LcbPlayer: dropped position $_position/$_duration '
          '(timeline changed during playback)');
    }
    widget.onPrefs?.call(_volume.round(), _rate);
    _awake.release();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Video(
              controller: _controller,
              controls: NoVideoControls,
              fit: AspectMode.parse(_aspectFit).boxFit,
              subtitleViewConfiguration: LcbSubtitleStyle.of(widget.subtitleSize),
            ),
          ),
          if (_buffering)
            const Center(
              child: CircularProgressIndicator(color: LcbColors.primary),
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
            ),
          // 次字幕：mpv 把它当成第二条轨，文字从 `secondary-sub-text` 报过来，
          // 这里照主字幕的字号画在画面上方，和主字幕组成双语对照。
          if (_secondaryText.isNotEmpty)
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
                      _secondaryText,
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
          // the bars so the bars' own buttons still win the hit test.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
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
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          _TopBar(
            title: _titleLine,
            subtitle: widget.subtitle,
            onClose: widget.onClose,
            visible: _controlsVisible,
          ),
          // Tapping anywhere outside the panel closes it; it sits under the
          // panel but over the video, so the bar below keeps working.
          if (_trackPanel)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _trackPanel = false),
              ),
            ),
          if (_skipPanel)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _skipPanel = false),
              ),
            ),
          if (_picturePanel)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _picturePanel = false),
              ),
            ),
          if (_trackPanel)
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
                onSubtitle: (t) => _setSubtitle(t.id),
                externalSubtitleLabel: _externalLabel,
                onPickSubtitleFile: _pickSubtitleFile,
                onClearSubtitleFile: _externalLabel == null
                    ? null
                    : _clearSubtitleFile,
              ),
            ),
          if (_skipPanel)
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
          if (_picturePanel)
            Positioned(
              right: 20,
              bottom: 132,
              child: PicturePanel(
                mode: AspectMode.parse(_aspectFit),
                adjust: _adjust,
                onMode: _pickAspect,
                onAdjust: _applyAdjust,
              ),
            ),
          _BottomBar(
            playing: _playing,
            buffering: _buffering,
            position: _position,
            duration: _duration,
            volume: _volume,
            rate: _rate,
            visible: _controlsVisible,
            hasNext: _hasNext,
            hasPrev:
                widget.episodeIndex != null && widget.episodeIndex! > 0,
            onTogglePlay: _togglePlay,
            onSeekStart: () => setState(() => _seeking = true),
            onSeekEnd: () {
              _seeking = false;
              final total = _duration.inMilliseconds;
              if (total <= 0) return; // bar is disabled; nothing to land on
              _seekTo(
                Duration(milliseconds: (_seekValue * total).round()),
              );
              _scheduleHide();
            },
            onSeekChanged: (v) => _seekValue = v,
            onVolume: (v) => _player.setVolume(v),
            onRate: (r) => _player.setRate(r),
            onTracks: _toggleTrackPanel,
            tracksOpen: _trackPanel,
            onDanmaku: _toggleDanmaku,
            danmakuOn: _danmakuOn,
            danmakuLabel: _danmakuLoading
                ? '弹幕…'
                : _danmakuOn
                    ? '弹幕 ${_danmaku.length}'
                    : '弹幕 关',
            onSkip: _toggleSkipPanel,
            skipOpen: _skipPanel,
            skipLabel: _clock.skip.intro > Duration.zero
                ? '片头 ${_clock.skip.intro.inSeconds}s'
                : '片头 关',
            onPicture: _togglePicturePanel,
            pictureOpen: _picturePanel,
            onNext: _hasNext
                ? () => widget.onEpisode!(widget.episodeIndex! + 1)
                : null,
            onPrev: (widget.episodeIndex != null && widget.episodeIndex! > 0)
                ? () => widget.onEpisode!(widget.episodeIndex! - 1)
                : null,
          ),
        ],
      ),
    );
  }
}

/// The dark top strip: close button, title, subtitle.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onClose,
    required this.visible,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onClose;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !visible,
        child: Container(
          height: 64,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xB3000000), Color(0x00000000)],
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              _RoundButton(
                icon: Icons.arrow_back,
                onTap: onClose ?? () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB8B8BE),
                        ),
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

/// The dark bottom strip: seek bar, play/pause, time, step controls, rate and
/// volume.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.playing,
    required this.buffering,
    required this.position,
    required this.duration,
    required this.volume,
    required this.rate,
    required this.visible,
    required this.hasNext,
    required this.hasPrev,
    required this.onTogglePlay,
    required this.onSeekStart,
    required this.onSeekEnd,
    required this.onSeekChanged,
    required this.onVolume,
    required this.onRate,
    required this.onTracks,
    required this.tracksOpen,
    required this.onDanmaku,
    required this.danmakuOn,
    required this.danmakuLabel,
    required this.onSkip,
    required this.skipOpen,
    required this.skipLabel,
    required this.onPicture,
    required this.pictureOpen,
    this.onNext,
    this.onPrev,
  });

  final bool playing;
  final bool buffering;
  final Duration position;
  final Duration duration;
  final double volume;
  final double rate;
  final bool visible;
  final bool hasNext;
  final bool hasPrev;
  final VoidCallback onTogglePlay;
  final VoidCallback onSeekStart;
  final VoidCallback onSeekEnd;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onVolume;
  final ValueChanged<double> onRate;
  final VoidCallback onTracks;
  final bool tracksOpen;

  /// 弹幕开关与它现在的状态：`弹幕 12` 表示开着且有 12 条，`弹幕 关` 表示关着，
  /// `弹幕…` 表示正在去源里要。标签直接说事实，不让人点开才知道有没有弹幕。
  final VoidCallback onDanmaku;
  final bool danmakuOn;
  final String danmakuLabel;

  /// Opens the 本剧片头片尾 panel, and the label it wears — `片头 90s` when one
  /// is in force for this work, `片头 关` when nothing is being skipped, so the
  /// bar states the current value instead of hiding it behind a menu.
  final VoidCallback onSkip;
  final bool skipOpen;
  final String skipLabel;

  /// Opens the 画面 panel (比例 + 调节).
  final VoidCallback onPicture;
  final bool pictureOpen;
  final VoidCallback? onNext;
  final VoidCallback? onPrev;

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final value = totalMs <= 0
        ? 0.0
        : (position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: IgnorePointer(
        ignoring: !visible,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xB3000000), Color(0x00000000)],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Seek bar row.
                Row(
                  children: [
                    Text(
                      _fmt(position),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFDDDDDD),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: value,
                        activeColor: LcbColors.primary,
                        inactiveColor: const Color(0x66FFFFFF),
                        // Dragging a bar whose scale is unknown can only land
                        // on zero, so it stays inert until the duration is in.
                        onChangeStart: totalMs <= 0 ? null : (_) => onSeekStart(),
                        onChanged: totalMs <= 0
                            ? null
                            : (v) {
                                onSeekChanged(v);
                                // Live-preview the scrub position in the label.
                              },
                        onChangeEnd: totalMs <= 0 ? null : (v) => onSeekEnd(),
                      ),
                    ),
                    Text(
                      _fmt(duration),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFDDDDDD),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (onPrev != null) ...[
                      _RoundButton(
                        icon: Icons.skip_previous,
                        onTap: onPrev,
                      ),
                      const SizedBox(width: 8),
                    ],
                    _RoundButton(
                      icon: playing
                          ? Icons.pause
                          : Icons.play_arrow,
                      onTap: onTogglePlay,
                    ),
                    if (onNext != null) ...[
                      const SizedBox(width: 8),
                      _RoundButton(
                        icon: Icons.skip_next,
                        onTap: onNext,
                      ),
                    ],
                    const SizedBox(width: 16),
                    if (buffering)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      ),
                    const Spacer(),
                    _PanelButton(
                      icon: Icons.content_cut,
                      label: skipLabel,
                      open: skipOpen,
                      onTap: onSkip,
                    ),
                    const SizedBox(width: 8),
                    _PanelButton(
                      icon: Icons.forum_outlined,
                      label: danmakuLabel,
                      open: danmakuOn,
                      onTap: onDanmaku,
                    ),
                    const SizedBox(width: 8),
                    _PanelButton(
                      icon: Icons.tune,
                      label: '轨道',
                      open: tracksOpen,
                      onTap: onTracks,
                    ),
                    const SizedBox(width: 8),
                    _PanelButton(
                      icon: Icons.aspect_ratio,
                      label: '画面',
                      open: pictureOpen,
                      onTap: onPicture,
                    ),
                    const SizedBox(width: 12),
                    _RateButton(rate: rate, onRate: onRate),
                    const SizedBox(width: 16),
                    VolumeControl(volume: volume, onVolume: onVolume),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _fmt(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

class _RoundButton extends StatefulWidget {
  const _RoundButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _hover ? const Color(0x33FFFFFF) : Colors.transparent,
            shape: BoxShape.circle,
          ),
          child: Icon(widget.icon, size: 24, color: Colors.white),
        ),
      ),
    );
  }
}

/// A pill in the bottom bar that opens a pop-up panel: an icon plus a short
/// label, filled purple while its panel is open. Used for 片头 and 轨道.
class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.icon,
    required this.label,
    required this.open,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: open ? const Color(0x337B68EE) : const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: open ? LcbColors.primary : Colors.white,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: open ? LcbColors.primary : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RateButton extends StatefulWidget {
  const _RateButton({required this.rate, required this.onRate});

  final double rate;
  final ValueChanged<double> onRate;

  @override
  State<_RateButton> createState() => _RateButtonState();
}

class _RateButtonState extends State<_RateButton> {
  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      initialValue: widget.rate,
      onSelected: widget.onRate,
      color: const Color(0xFF2A2A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      itemBuilder: (_) => [
        for (final r in _rates)
          PopupMenuItem(
            value: r,
            child: Text(
              r == 1.0 ? '${r.toStringAsFixed(1)} 倍速' : '$r 倍速',
              style: TextStyle(
                fontSize: 13,
                color: r == widget.rate ? LcbColors.primary : Colors.white,
              ),
            ),
          ),
      ],
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x1AFFFFFF),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          '${widget.rate} 倍速',
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
      ),
    );
  }
}

@visibleForTesting
class VolumeControl extends StatelessWidget {
  const VolumeControl({super.key, required this.volume, required this.onVolume});

  final double volume;
  final ValueChanged<double> onVolume;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          volume <= 0 ? Icons.volume_off : Icons.volume_up,
          size: 20,
          color: Colors.white,
        ),
        SizedBox(
          width: 90,
          child: Slider(
            // media_kit carries volume as 0-100; Slider wants 0-1. Mapping here
            // keeps the raw value in one place so a 100 never lands on a 0-1
            // slider (which asserts and, in a debug build, kills the app).
            value: volume / 100,
            activeColor: LcbColors.primary,
            inactiveColor: const Color(0x66FFFFFF),
            onChanged: (v) => onVolume(v * 100),
          ),
        ),
      ],
    );
  }
}
