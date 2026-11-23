// Live check: does a real libmpv report its failures through the stream the
// playback error overlay listens to, and does our wording recognise them?
//
//   dart run tool/verify_playback_error_live.dart
//
// The unit tests feed `playbackFailureHint` strings that I *believed* mpv
// produces. This runs the real thing against two addresses that cannot open --
// a closed local port and a missing file -- and prints the message mpv actually
// emitted next to the line the overlay would show. It exits non-zero if mpv
// stayed silent (which would mean the overlay can never appear) or if neither
// failure was recognised.
import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart';

import 'package:lai_cui_ba/services/player/playback_failure.dart';

const _libmpv = 'build/windows/x64/runner/Debug/libmpv-2.dll';

var _failures = 0;

void _check(String what, bool ok, [String detail = '']) {
  stdout.writeln(
    '${ok ? 'ok  ' : 'FAIL'}  $what${detail.isEmpty ? '' : ' — $detail'}',
  );
  if (!ok) _failures++;
}

Future<bool> _waitFor(bool Function() done, {int ms = 12000}) async {
  final deadline = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(deadline)) {
    if (done()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }
  return done();
}

/// Opens [uri] and collects everything mpv says on its error stream.
Future<(List<String>, List<String>)> _open(String uri) async {
  final player = Player();
  final errors = <String>[];
  final logs = <String>[];
  player.stream.error.listen(errors.add);
  player.stream.log.listen((l) {
    if (l.level != 'error' && l.level != 'fatal') return;
    logs.add(l.prefix.isEmpty ? l.text : '${l.prefix}: ${l.text}');
  });
  try {
    await player.open(Media(uri), play: true);
  } catch (e) {
    errors.add('$e');
  }
  // Give mpv a moment: connection refused and missing files both resolve fast,
  // but the vo has to be brought up first on this machine.
  await _waitFor(() => errors.isNotEmpty, ms: 9000);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  await player.dispose();
  return (errors, logs);
}

Future<void> main() async {
  MediaKit.ensureInitialized(
    libmpv: File(_libmpv).existsSync() ? File(_libmpv).absolute.path : null,
  );

  // 1. A port nothing is listening on.
  final (netErrors, netLogs) = await _open('http://127.0.0.1:1/nope.mp4');
  stdout.writeln('--- closed port: ${netErrors.length} error(s)');
  for (final e in netErrors) {
    stdout.writeln('    raw : $e');
    stdout.writeln('    hint: ${playbackFailureHint(e)}');
  }
  for (final l in netLogs) {
    stdout.writeln('    log : $l');
  }
  _check(
    'mpv reports a closed port on the error stream',
    netErrors.isNotEmpty,
    '（若为空，播放页的「打不开」浮层永远不会出现）',
  );

  // 2. A file that is not there.
  final (fileErrors, fileLogs) = await _open(
    File('C:/definitely/not/here.mkv').absolute.uri.toString(),
  );
  stdout.writeln('--- missing file: ${fileErrors.length} error(s)');
  for (final e in fileErrors) {
    stdout.writeln('    raw : $e');
    stdout.writeln('    hint: ${playbackFailureHint(e)}');
  }
  for (final l in fileLogs) {
    stdout.writeln('    log : $l');
  }
  _check(
    'mpv reports a missing file on the error stream',
    fileErrors.isNotEmpty,
  );

  final all = [...netErrors, ...fileErrors];
  _check('every message maps to a non-empty hint', all.every(
    (e) => playbackFailureHint(e).trim().isNotEmpty,
  ));
  _check(
    'at least one failure is explained in our own words, not echoed raw',
    all.any((e) => playbackFailureHint(e) != e.trim()),
    '${all.map(playbackFailureHint).toSet()}',
  );

  stdout.writeln(_failures == 0 ? 'all checks passed' : '$_failures check(s) failed');
  exit(_failures == 0 ? 0 : 1);
}
