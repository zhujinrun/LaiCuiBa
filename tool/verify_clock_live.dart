// Live check: does PlaybackClock drive a real mpv the way the tests assume?
//
//   dart run tool/verify_clock_live.dart "C:/path/to/clip.mp4"
//
// The unit tests feed the clock synthetic event sequences. This runs the same
// decisions against libmpv, which is the only place that can prove the things
// the tests cannot: that `start:` is a hint rather than a promise, that a seek
// issued once the duration is known actually lands, and that the intro/tail
// cut-offs fire on a real timeline rather than a synthetic one.
//
// Needs a plain video file with a known duration (any mp4). It writes nothing
// outside stdout and exits non-zero on the first failed expectation.
import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/playback_clock.dart';
import 'package:lai_cui_ba/services/skip_rule.dart';

const _libmpv = 'build/windows/x64/runner/Debug/libmpv-2.dll';

var _failures = 0;

void _check(String what, bool ok, [String detail = '']) {
  stdout.writeln('${ok ? 'ok  ' : 'FAIL'}  $what${detail.isEmpty ? '' : ' — $detail'}');
  if (!ok) _failures++;
}

/// Feeds a player into a clock and performs whatever seek it asks for, exactly
/// as `PlayerPage` does.
class _Session {
  _Session(this.player, this.clock) {
    _subs
      ..add(player.stream.duration.listen((d) {
        clock.onDuration(d);
        _pump();
      }))
      ..add(player.stream.position.listen((p) {
        clock.onPosition(p);
        _pump();
        if (clock.takeOutro()) outros++;
      }));
  }

  final Player player;
  final PlaybackClock clock;
  final seeks = <Duration>[];

  /// How many times the tail cut-off fired; must never exceed one.
  int outros = 0;

  final _subs = <StreamSubscription<dynamic>>[];

  void _pump() {
    final target = clock.pendingSeek();
    if (target == null) return;
    seeks.add(target);
    player.seek(target);
  }

  Future<void> close() async {
    for (final s in _subs) {
      await s.cancel();
    }
    await player.dispose();
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/verify_clock_live.dart <video>');
    exit(2);
  }
  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('no such file: ${file.path}');
    exit(2);
  }
  MediaKit.ensureInitialized(
    libmpv: File(_libmpv).existsSync() ? File(_libmpv).absolute.path : null,
  );
  final uri = file.absolute.uri.toString();

  // --- 1. a fresh play: nothing to seek, duration becomes known -------------
  {
    final player = Player();
    final session = _Session(player, PlaybackClock());
    await player.open(Media(uri));
    await _waitFor(() => session.clock.duration > Duration.zero);
    _check('duration is known', session.clock.ready,
        '${session.clock.duration}');
    _check('no seek for a fresh play', session.seeks.isEmpty);
    _check('position is recordable', session.clock.recordable);
    await session.close();
  }

  final total = await _measure(uri);
  stdout.writeln('--- clip duration: $total');

  // --- 2. resume into the middle: one seek, and it lands -------------------
  {
    final player = Player();
    final resume = ResumePoint(
      positionMs: 60000,
      totalMs: total.inMilliseconds,
    );
    final session = _Session(player, PlaybackClock(resume: resume));
    await player.open(Media(uri));
    await _waitFor(() => session.seeks.isNotEmpty);
    _check('resume issues a seek', session.seeks.length == 1,
        '${session.seeks}');
    _check('seek targets the saved position',
        session.seeks.first == const Duration(minutes: 1),
        '${session.seeks.isEmpty ? '-' : session.seeks.first}');
    await _waitFor(
      () => (session.clock.position - const Duration(minutes: 1)).abs() <
          const Duration(seconds: 3),
    );
    final landed = session.clock.position;
    _check('the seek lands', (landed - const Duration(minutes: 1)).abs() <
        const Duration(seconds: 3), '$landed');
    _check('only one seek was issued', session.seeks.length == 1,
        '${session.seeks}');
    await session.close();
  }

  // --- 3. mpv honoured start: no repair seek ------------------------------
  {
    final player = Player();
    final resume = ResumePoint(
      positionMs: 60000,
      totalMs: total.inMilliseconds,
    );
    final session = _Session(player, PlaybackClock(resume: resume));
    await player.open(Media(uri, start: resume.position));
    await _waitFor(() => session.clock.ready);
    await _settle();
    _check('a landing on target needs no repair seek', session.seeks.isEmpty,
        '${session.seeks}');
    await session.close();
  }

  // --- 4. a position from another cut is refused --------------------------
  {
    final player = Player();
    final session = _Session(
      player,
      // Recorded on a 15-second pre-roll.
      PlaybackClock(resume: const ResumePoint(positionMs: 5000, totalMs: 15000)),
    );
    await player.open(Media(uri));
    await _waitFor(() => session.clock.ready);
    await _settle();
    _check('an ad-polluted position is not replayed', session.seeks.isEmpty,
        '${session.seeks}');
    _check('the session is still recordable', session.clock.recordable);
    await session.close();
  }

  // --- 5. skip-intro lands on the real timeline ---------------------------
  {
    final intro = _share(total, 0.15);
    final player = Player();
    final session = _Session(player, PlaybackClock(skip: SkipRule(intro: intro)));
    await player.open(Media(uri));
    await _waitFor(() => session.seeks.isNotEmpty);
    _check('片头设置触发一次 seek', session.seeks.length == 1,
        '${session.seeks}');
    _check('片头 seek 落在设定处',
        session.seeks.isNotEmpty && session.seeks.first == intro,
        'want $intro, got ${session.seeks.isEmpty ? '-' : session.seeks.first}');
    await _waitFor(
      () => (session.clock.position - intro).abs() < const Duration(seconds: 3),
    );
    _check('片头 seek 真的落地',
        (session.clock.position - intro).abs() < const Duration(seconds: 3),
        '${session.clock.position}');
    _check('片头只跳一次', session.seeks.length == 1, '${session.seeks}');
    await session.close();
  }

  // --- 6. the tail cut-off fires once, on a real position ----------------
  {
    final outro = _share(total, 0.15);
    final player = Player();
    final session = _Session(player, PlaybackClock(skip: SkipRule(outro: outro)));
    await player.open(Media(uri));
    await _waitFor(() => session.clock.ready);
    // Land a few seconds before the tail so a real position event walks into it.
    final runway = total - outro - const Duration(seconds: 4);
    await player.seek(runway < Duration.zero ? Duration.zero : runway);
    await _waitFor(() => session.outros > 0);
    _check('进入片尾区间时报一次', session.outros == 1,
        'outros=${session.outros} at ${session.clock.position}');
    await _settle();
    _check('过冲之后不再重复报', session.outros == 1, 'outros=${session.outros}');
    await session.close();
  }

  stdout.writeln(_failures == 0 ? '\nall checks passed' : '\n$_failures failed');
  exit(_failures == 0 ? 0 : 1);
}

/// A slice of the clip long enough to be meaningful and short enough to stay
/// well inside [SkipRule]'s "under 40% of the feature" guard.
Duration _share(Duration total, double fraction) {
  final seconds = (total.inMilliseconds * fraction / 1000).round();
  return Duration(seconds: seconds.clamp(3, 180));
}

Future<Duration> _measure(String uri) async {
  final player = Player();
  final done = Completer<Duration>();
  final sub = player.stream.duration.listen((d) {
    if (d > Duration.zero && !done.isCompleted) done.complete(d);
  });
  await player.open(Media(uri));
  final total = await done.future.timeout(const Duration(seconds: 20));
  await sub.cancel();
  await player.dispose();
  return total;
}

Future<void> _waitFor(bool Function() condition,
    {Duration timeout = const Duration(seconds: 20)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// Gives the player time to emit whatever it was going to emit, so "no seek"
/// is a real observation rather than an early one.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 1500));
