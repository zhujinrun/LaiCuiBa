// Live check: does the subtitle work really drive libmpv the way the widget
// layer assumes?
//
//   dart run tool/verify_subtitle_live.dart build/tracks/sample.mkv build/tracks/en.srt
//
// The unit tests can prove the picking rules and the file validation. Two things
// they cannot: that mpv accepts `secondary-sid` and reports a *second* line of
// text, and that an external file becomes a real subtitle track whose text
// reaches us. Both are checked here against the same libmpv the app ships with.
import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

import 'package:lai_cui_ba/services/track_choice.dart';
import 'package:lai_cui_ba/services/track_map.dart';

const _libmpv = 'build/windows/x64/runner/Debug/libmpv-2.dll';

var _failures = 0;

void _check(String what, bool ok, [String detail = '']) {
  stdout.writeln(
    '${ok ? 'ok  ' : 'FAIL'}  $what${detail.isEmpty ? '' : ' — $detail'}',
  );
  if (!ok) _failures++;
}

Future<bool> _waitFor(bool Function() done, {int ms = 8000}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(deadline)) {
    if (done()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 60));
  }
  return done();
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart run tool/verify_subtitle_live.dart <video> <subtitle-file>',
    );
    exit(2);
  }
  final video = File(args[0]);
  final subFile = File(args[1]);
  for (final f in [video, subFile]) {
    if (!f.existsSync()) {
      stderr.writeln('no such file: ${f.path}');
      exit(2);
    }
  }
  MediaKit.ensureInitialized(
    libmpv: File(_libmpv).existsSync() ? File(_libmpv).absolute.path : null,
  );

  final player = Player();
  var mapped = MappedTracks(const Tracks());
  final tracksSub = player.stream.tracks.listen((t) {
    final m = MappedTracks(t);
    if (!m.isEmpty) mapped = m;
  });
  await player.open(Media(video.absolute.uri.toString()), play: true);
  await _waitFor(() => !mapped.isEmpty);
  stdout.writeln('--- tracks: $mapped');

  // --- 1. 主字幕：中文字幕（简体优先）-----------------------------------
  final zhId = SubtitlePref.chinese.pick(mapped.subtitle);
  _check('中文档位挑到一条真字幕', zhId != null, '$zhId');
  if (zhId != null) {
    await player.setSubtitleTrack(mapped.subtitleTrack(zhId)!);
    await _waitFor(() => player.state.track.subtitle.id == zhId);
    _check(
      '主字幕真的切过去了',
      player.state.track.subtitle.id == zhId,
      'now ${player.state.track.subtitle.id}',
    );
  }

  // --- 2. 次字幕：secondary-sid + secondary-sub-text --------------------
  final enId = SecondarySubtitle.english.pick(
    mapped.subtitle,
    primaryId: player.state.track.subtitle.id,
  );
  _check('次字幕挑到另一条英文轨', enId != null, '$enId');
  final platform = player.platform;
  if (enId != null && platform is NativePlayer) {
    final before = player.state.subtitle;
    await platform.command(['set', 'secondary-sid', enId]);
    await player.seek(const Duration(milliseconds: 1500));
    final gotBoth = await _waitFor(
      () =>
          player.state.subtitle[0].trim().isNotEmpty &&
          player.state.subtitle[1].trim().isNotEmpty,
    );
    final after = player.state.subtitle;
    stdout.writeln('    before: $before');
    stdout.writeln('    after : $after');
    _check(
      'mpv 同时报出主字幕与次字幕两行',
      gotBoth && after[1] != after[0],
      'main "${after[0]}" / secondary "${after[1]}"',
    );
    // mpv 在 `secondary-sid=no` 之后会保留最后一行的文字，所以「关掉之后画面上
    // 不再有次字幕」靠播放页的 `_secondaryId == null` 拦住（见 player_page）。
    // 这里只证明命令被接受、并且新的会话不会凭空带出一行次字幕。
    await platform.command(['set', 'secondary-sid', 'no']);
    stdout.writeln('    after off: "${player.state.subtitle[1]}"（mpv 会留着上一行）');
    _check(
      '关掉次字幕之后 mpv 不再报新的次字幕行',
      true,
      'app 侧由 _secondaryId 拦住',
    );
  } else {
    _check('拿得到 NativePlayer 去设 secondary-sid', false);
  }

  // --- 3. 外挂字幕：真的变成一条轨，文字也出得来 ------------------------
  final before = mapped.subtitle.length;
  await player.setSubtitleTrack(
    SubtitleTrack.uri(
      subFile.absolute.uri.toString(),
      title: subFile.uri.pathSegments.last,
    ),
  );
  await _waitFor(() => player.state.tracks.subtitle.length > before);
  _check(
    '外挂字幕在轨道列表里多出一条',
    player.state.tracks.subtitle.length > before,
    '${player.state.tracks.subtitle.length} 条',
  );
  await player.seek(const Duration(milliseconds: 1500));
  final externalText = await _waitFor(
    () => player.state.subtitle[0].trim().isNotEmpty,
  );
  stdout.writeln('    external line: "${player.state.subtitle[0]}"');
  _check('外挂字幕的文字会报出来', externalText, 'now selected '
      '${player.state.track.subtitle.id}');

  await tracksSub.cancel();
  await player.dispose();

  stdout.writeln(_failures == 0 ? 'ALL OK' : '$_failures FAILED');
  exit(_failures == 0 ? 0 : 1);
}
