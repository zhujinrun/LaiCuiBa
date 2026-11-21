import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/awake.dart';
import '../../services/playback_clock.dart';
import '../../services/skip_rule.dart';
import '../../services/track_choice.dart';
import '../../services/track_map.dart';
import '../widgets/track_panel.dart';

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
    this.skip = SkipRule.none,
    this.initialVolume = 100,
    this.initialRate = 1.0,
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

  /// How much of the head and tail the viewer asked to skip. [SkipRule.none]
  /// when the feature is off or nothing was configured — the player never
  /// guesses where an intro ends.
  final SkipRule skip;

  /// Volume (0-100) and speed to open with — the values the last session was
  /// left at, not a hardcoded 100 / 1.0×.
  final int initialVolume;
  final double initialRate;

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
    skip: widget.skip,
  );

  late final Awake _awake = widget.awake ?? SystemAwake();

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<double>? _rateSub;
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<Track>? _trackSub;

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

  bool _trackPanel = false;

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
    });

    // A viewer who starts an episode and walks away should come back to a
    // playing episode, not a locked screen.
    _awake.hold();
    _open();
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
    if (subtitle != null && subtitle != current.subtitle.id) {
      _setSubtitle(subtitle, remember: false);
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
    });
  }

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
    final intro = widget.skip.introFor(_clock.duration);
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
              fit: BoxFit.contain,
            ),
          ),
          if (_buffering)
            const Center(
              child: CircularProgressIndicator(color: LcbColors.primary),
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
                    _TracksButton(open: tracksOpen, onTap: onTracks),
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

class _TracksButton extends StatelessWidget {
  const _TracksButton({required this.open, required this.onTap});

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
                Icons.tune,
                size: 15,
                color: open ? LcbColors.primary : Colors.white,
              ),
              const SizedBox(width: 5),
              Text(
                '轨道',
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
