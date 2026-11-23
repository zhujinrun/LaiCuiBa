import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/player/playback_failure.dart';

void main() {
  test('建不出渲染上下文的失败，说清是这台机器的问题', () {
    for (final raw in [
      'mpv: Could not create window: 0x1',
      'vo/gpu: failed to create context',
      'OpenGL not supported',
      'D3D11 init failed',
      'eglCreateContext failed',
    ]) {
      expect(
        playbackFailureHint(raw),
        '无法创建播放画面：这台机器（或远程桌面）不支持当前的渲染方式',
        reason: raw,
      );
    }
  });

  test('鉴权类失败与「地址没了」分开说', () {
    expect(
      playbackFailureHint('HTTP error 403 Forbidden'),
      '源拒绝了这个地址：可能需要登录，或者不让外链播放',
    );
    expect(
      playbackFailureHint('Failed to open https://x/y.m3u8'),
      '这一集的地址打不开：源可能已经换了地址或者下架了',
    );
    expect(
      playbackFailureHint('404 Not Found'),
      '这一集的地址打不开：源可能已经换了地址或者下架了',
    );
  });

  test('网络没通和「地址没了」是两件事（原话取自真实 mpv）', () {
    // `tool/verify_playback_error_live.dart` 跑出来的两条原话：网络层先失败，
    // 紧接着 mpv 再补一句 Failed to open。前者要说网络，后者才是地址。
    expect(
      playbackFailureHint(
        'tcp: Connection to tcp://127.0.0.1:1 failed: Error number -138 occurred',
      ),
      '连不上这个地址：网络不通，或者源服务器不可达',
    );
    expect(
      playbackFailureHint("Cannot open file '\\\\?\\C:\\nope\\a.mkv': Invalid argument"),
      '打不开这个文件：路径不对，或者文件已经不在那个位置',
    );
  });

  test('服务器 5xx 单独一句，因为等一会儿重试就有用', () {
    expect(
      playbackFailureHint('server replied HTTP 502'),
      '源服务器出错了（HTTP 502），过一会儿再试',
    );
  });

  test('认不出来的原样回报，空话不编', () {
    expect(playbackFailureHint('something odd'), 'something odd');
    expect(playbackFailureHint('   '), '播放器没有给出原因');
  });
}
