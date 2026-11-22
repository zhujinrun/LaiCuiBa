// Live check: do the picture-adjust values really drive libmpv's
// brightness/contrast/saturation/hue/gamma?
//
//   dart run tool/verify_picture_live.dart "C:/path/to/clip.mp4"
//
// The widget tests prove the panel reports the right payload and the unit
// tests prove [PictureAdjust.mpvProperties] maps to these exact property
// names. This runs those names against libmpv — the only place that can prove
// the values actually land on mpv's eq properties and read back. It mirrors
// the player page's `_applyAdjust`, which writes the same `set <prop> <value>`
// commands, without importing flutter (the script must stay FFI-clean).
//
// Needs a small clip:
//   ffmpeg -f lavfi -i testsrc=duration=30:size=320x240:rate=25 \
//          -f lavfi -i sine=frequency=440:duration=30 \
//          -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest clip.mp4
//
// Writes nothing outside stdout and exits non-zero on the first failure.
import 'dart:io';

import 'package:media_kit/media_kit.dart';

const _libmpv = 'build/windows/x64/runner/Debug/libmpv-2.dll';

// Must match PictureAdjust.mpvProperties exactly; the unit test pins that.
const _props = [
  ('brightness', 20),
  ('contrast', -10),
  ('saturation', 5),
  ('hue', 15),
  ('gamma', 8),
];

var _failures = 0;

void _check(String what, bool ok, [String detail = '']) {
  stdout.writeln(
    '${ok ? 'ok  ' : 'FAIL'}  $what${detail.isEmpty ? '' : ' — $detail'}',
  );
  if (!ok) _failures++;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/verify_picture_live.dart <clip>');
    exit(2);
  }

  MediaKit.ensureInitialized(libmpv: _libmpv);

  final player = Player();
  await player.open(Media(args[0]), play: false);

  final platform = player.platform;
  if (platform is! NativePlayer) {
    stderr.writeln('expected a NativePlayer (libmpv) backend');
    exit(1);
  }

  for (final (prop, value) in _props) {
    await platform.command(['set', prop, '$value']);
  }

  var matched = 0;
  for (final (prop, value) in _props) {
    final got = await platform.getProperty(prop);
    // mpv reports these as float strings ("20.000000"), so compare numerically.
    final ok = double.tryParse(got) == value.toDouble();
    _check('$prop landed as $value', ok, 'got "$got"');
    if (ok) matched++;
  }

  // Reset to neutral and confirm 0 sticks (the "恢复原始画面" path).
  await platform.command(['set', 'brightness', '0']);
  final zero = await platform.getProperty('brightness');
  _check('brightness resets to 0', double.tryParse(zero) == 0, 'got "$zero"');

  await player.dispose();

  stdout.writeln(
    matched == _props.length && _failures == 0
        ? '\nall checks passed'
        : '\n$_failures failed',
  );
  exit(_failures == 0 ? 0 : 1);
}
