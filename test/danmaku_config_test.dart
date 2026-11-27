import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/danmaku/danmaku_api.dart';

void main() {
  test('没有源或只有没凭据的官方源时，拦截开启而不是发注定 401 的请求', () {
    expect(danmakuSourcesNeedCredentials(const []), isTrue);
    expect(
      danmakuSourcesNeedCredentials([DanmakuSource.builtin]),
      isTrue,
    );
    expect(
      danmakuSourcesNeedCredentials([
        const DanmakuSource(
          id: 'custom',
          name: '自建',
          baseUrl: 'https://danmu.example.com',
        ),
      ]),
      isFalse,
      reason: '自建的 dandanplay 兼容服务不需要签名',
    );
  });

  test('填了凭据的官方源、或另有可用源，都可以开', () {
    expect(
      danmakuSourcesNeedCredentials([
        const DanmakuSource(
          id: 'dandanplay',
          name: '弹弹play',
          appId: 'id',
          appSecret: 'secret',
        ),
      ]),
      isFalse,
    );
    expect(
      danmakuSourcesNeedCredentials([
        DanmakuSource.builtin,
        const DanmakuSource(
          id: 'custom',
          name: '自建',
          baseUrl: 'https://danmu.example.com',
        ),
      ]),
      isFalse,
    );
    expect(
      danmakuSourcesNeedCredentials([
        const DanmakuSource(
          id: 'mirror',
          name: '官方镜像',
          baseUrl: DanmakuSource.officialBase,
        ),
      ]),
      isTrue,
    );
    expect(
      danmakuSourcesNeedCredentials([
        DanmakuSource.builtin.copyWith(enabled: false),
      ]),
      isTrue,
      reason: '禁用的源不能算可用源',
    );
  });
}
