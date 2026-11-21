// Live check: does the track panel's mapping drive a real mpv the way the unit
// tests assume?
//
//   dart run tool/verify_tracks_live.dart "C:/path/to/multi-track.mkv"
//
// The widget tests feed `TrackPanel` synthetic options. This runs the same
// mapping ([MappedTracks]) against libmpv, which is the only place that can
// prove the things those tests cannot: that mpv reports the tracks as
// `AudioTrack` / `SubtitleTrack` with a usable id and language, that switching
// through the mapped object really changes `state.track`, and that a remembered
// pick survives onto a freshly opened session.
//
// Needs a file with several audio/subtitle tracks, e.g.
//   ffmpeg -f lavfi -i testsrc2=size=640x360:duration=12 \
//          -f lavfi -i testsrc2=size=320x180:duration=12 \
//          -f lavfi -i sine=frequency=440:duration=12 \
//          -f lavfi -i sine=frequency=660:duration=12 \
//          -f lavfi -i sine=frequency=880:duration=12 \
//          -i zh.srt -i en.srt \
//          -map 0:v -map 2:a -map 3:a -map 4:a -map 1:v -map 5 -map 6 \
//          -c:v libx264 -c:a aac -c:s srt \
//          -metadata:s:a:0 language=zh -metadata:s:a:1 language=yue \
//          -metadata:s:a:2 language=eng \
//          -metadata:s:s:0 language=zh -metadata:s:s:1 language=eng \
//          sample.mkv
//
// Writes nothing outside stdout and exits non-zero on the first failed
// expectation.
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

/// Opens the sample and waits until mpv has published its real track list.
Future<(Player, MappedTracks)> _open(String uri) async {
  final player = Player();
  await player.open(Media(uri), play: false);
  var mapped = MappedTracks(const Tracks());
  final sub = player.stream.tracks.listen((t) {
    final m = MappedTracks(t);
    if (!m.isEmpty) mapped = m;
  });
  await _waitFor(() => !mapped.isEmpty);
  await sub.cancel();
  return (player, mapped);
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/verify_tracks_live.dart <video>');
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

  final (player, mapped) = await _open(uri);
  stdout.writeln('--- mpv reported: $mapped');

  // --- 1. the mapping keeps every real track and drops mpv's verbs ---------
  _check('two video tracks mapped', mapped.video.length == 2,
      '${mapped.video.map((t) => '${t.label}/${t.detail}').toList()}');
  _check('three audio tracks mapped', mapped.audio.length == 3, '${mapped.audio}');
  _check('two subtitle tracks mapped', mapped.subtitle.length == 2,
      '${mapped.subtitle}');

  final labels = mapped.audio.map((t) => t.label).toList();
  _check('audio languages are named, not numbered',
      labels.contains('中文') && labels.contains('粤语') && labels.contains('英语'),
      '$labels');

  final sizes = mapped.video.map((t) => t.detail).toList();
  _check('video resolutions are reported',
      sizes.any((d) => d != null && d.contains('640×360')) &&
          sizes.any((d) => d != null && d.contains('320×180')),
      '$sizes');

  // --- 2. a pick from the panel really switches the output -----------------
  final cantonese = mapped.audio.firstWhere((t) => t.label == '粤语');
  final cantoneseTrack = mapped.audioTrack(cantonese.id);
  _check('the mapped id resolves back to a real audio track',
      cantoneseTrack != null, cantonese.id);
  await player.setAudioTrack(cantoneseTrack!);
  await _waitFor(() => player.state.track.audio.id == cantonese.id);
  _check('switching audio takes effect',
      player.state.track.audio.id == cantonese.id,
      'now ${player.state.track.audio.id}');

  await player.setSubtitleTrack(mapped.subtitleTrack('no')!);
  await _waitFor(() => player.state.track.subtitle.id == 'no');
  _check('subtitles can be turned off', player.state.track.subtitle.id == 'no',
      'now ${player.state.track.subtitle.id}');

  final english = mapped.subtitle.firstWhere((t) => t.label == '英语');
  await player.setSubtitleTrack(mapped.subtitleTrack(english.id)!);
  await _waitFor(() => player.state.track.subtitle.id == english.id);
  _check('an embedded subtitle can be picked',
      player.state.track.subtitle.id == english.id,
      'now ${player.state.track.subtitle.id}');

  final small = mapped.video.firstWhere(
    (t) => t.detail != null && t.detail!.contains('320×180'),
  );
  await player.setVideoTrack(mapped.videoTrack(small.id)!);
  await _waitFor(() => player.state.track.video.id == small.id);
  _check('a lower-resolution video track can be picked',
      player.state.track.video.id == small.id,
      'now ${player.state.track.video.id}');

  await player.dispose();

  // --- 3. what the viewer picked comes back on the next open ---------------
  const remembered = TrackPrefs(audio: null, subtitle: 'no');
  final prefs = remembered.withAudio(cantonese.id);
  final (second, mapped2) = await _open(uri);
  final wantedAudio = prefs.audioFor(mapped2.audio);
  final wantedSub = prefs.subtitleFor(mapped2.subtitle);
  _check('the remembered audio id still exists on a fresh session',
      wantedAudio == cantonese.id, '$wantedAudio');

  // Exactly what `_restorePicks` does on the page.
  if (wantedAudio != null) {
    await second.setAudioTrack(mapped2.audioTrack(wantedAudio)!);
    await _waitFor(() => second.state.track.audio.id == wantedAudio);
  }
  if (wantedSub == 'no') {
    await second.setSubtitleTrack(SubtitleTrack.no());
    await _waitFor(() => second.state.track.subtitle.id == 'no');
  }
  _check('the remembered picks are applied after reopening',
      second.state.track.audio.id == cantonese.id &&
          second.state.track.subtitle.id == 'no',
      'audio ${second.state.track.audio.id}, '
      'subtitle ${second.state.track.subtitle.id}');

  final stale = const TrackPrefs(audio: '99').audioFor(mapped2.audio);
  _check('an id that no longer exists is ignored, not applied', stale == null,
      '$stale');

  await second.dispose();

  stdout.writeln(_failures == 0 ? '\nall checks passed' : '\n$_failures failed');
  exit(_failures == 0 ? 0 : 1);
}
