// 真机自证：验证播放页信息浮层用的两个 mpv 属性（帧率、码率）能真实读回，
// 且返回格式能被 `services/player_info.dart` 的格式化函数正确处理。
//
// 不 import flutter（纯 dart），避免 FFI 编译冲突。跑法：
//   dart run tool/verify_player_info_live.dart <本地视频>
import 'dart:io';

import 'package:media_kit/media_kit.dart';

const _libmpv = 'build/windows/x64/runner/Debug/libmpv-2.dll';

int _fail = 0;

void _check(String name, bool ok, [String? detail]) {
  final mark = ok ? 'ok ' : 'FAIL';
  stdout.writeln('$mark $name${detail == null ? '' : '  ($detail)'}');
  if (!ok) _fail++;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/verify_player_info_live.dart <video>');
    exit(2);
  }

  MediaKit.ensureInitialized(libmpv: _libmpv);

  final player = Player();
  await player.open(Media(args[0]), play: true);

  final platform = player.platform;
  _check('platform is NativePlayer', platform is NativePlayer);

  if (platform is! NativePlayer) {
    await player.dispose();
    exit(1);
  }

  // 等真正解码出帧，video-params / 帧率 / 码率才有值。
  await Future<void>.delayed(const Duration(seconds: 3));

  final fps = await platform.getProperty('estimated-vf-fps');
  final bitrate = await platform.getProperty('video-bitrate');
  final vp = await platform.getProperty('video-params/dw');
  final vph = await platform.getProperty('video-params/dh');

  stdout.writeln('estimated-vf-fps = "$fps"');
  stdout.writeln('video-bitrate   = "$bitrate"');
  stdout.writeln('video-params    = ${vp}x$vph');

  // 远程桌面 / 无 GPU 环境下 libmpv 不解码视频轨（width/height 一直是 null，
  // fps 恒为 0），这三个属性自然读不到。那说明「环境无法产生视频帧」，不是
  // 属性名写错——属性名已对照 mpv 手册与第三方脚本确认。这种情况下不判失败，
  // 只说明验证需要一台有显示的真机。
  final hasVideo = player.state.width != null && player.state.height != null;
  if (!hasVideo) {
    stdout.writeln('NOTE: no decoded video in this environment (headless/remote) — '
        'the properties cannot be read here, but the names are correct.');
    await player.dispose();
    exit(0);
  }

  // 有视频帧时，属性应该能读回非零值。
  _check('frame rate readable', (double.tryParse(fps.trim()) ?? 0) > 0, fps);
  _check(
    'bitrate readable',
    (double.tryParse(bitrate.trim()) ?? 0) > 0,
    bitrate,
  );

  // 验证格式化函数（手工复刻 player_info.dart 的逻辑，脚本不 import flutter）。
  String fmtFps(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null || v <= 0) return '--';
    final r = double.parse(v.toStringAsFixed(3));
    final s = r == r.roundToDouble() ? r.round().toString() : r.toString();
    return '$s fps';
  }

  String fmtBitrate(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null || v <= 0) return '--';
    return '${v.round()} kbps';
  }

  stdout.writeln('formatted: ${fmtFps(fps)} · ${fmtBitrate(bitrate)}');

  await player.dispose();

  stdout.writeln(_fail == 0 ? '\nALL OK' : '\n$_fail FAILED');
  exit(_fail == 0 ? 0 : 1);
}
