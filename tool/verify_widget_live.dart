// Live check of the CapyPlayer-compatible widget host against real node.exe.
//
//   dart run tool/verify_widget_live.dart
//
// No network is involved: the fixture returns its own MediaItem[] and logs.
// Widget tests cover the Dart side with a fake; this proves the actual bridge,
// WidgetMetadata validation and function call all work on the shipped runtime.
// Exits non-zero on the first failure.
import 'dart:io';

import 'package:lai_cui_ba/services/runtime_paths.dart';
import 'package:lai_cui_ba/services/widgets/widget_runtime.dart';

int _failures = 0;

void _check(String what, bool ok, [String detail = '']) {
  stdout.writeln('${ok ? 'ok  ' : 'FAIL'}  $what${detail.isEmpty ? '' : ' — $detail'}');
  if (!ok) _failures++;
}

Future<void> main() async {
  final paths = RuntimePaths.resolve();
  if (paths == null || !paths.widgetAvailable) {
    stderr.writeln('node.exe / widget_host.js 未就位，先跑 tool/sync_runtime.sh');
    exit(2);
  }

  const fixture = 'test/fixtures/widget_sample.js';
  if (!File(fixture).existsSync()) {
    stderr.writeln('缺少组件夹具：$fixture');
    exit(2);
  }

  final runtime = WidgetRuntime(
    nodePath: paths.node,
    hostScript: paths.widgetHost,
  );
  try {
    final meta = await runtime.meta(fixture);
    _check('WidgetMetadata 读到标题', meta.title == '测试组件', meta.title);
    _check('模块函数被认出', meta.modules.single.functionName == 'getPopular');
    _check('组件编号来自脚本', meta.id == 'fixture_widget', meta.id);
    _check('组件图标读进来', meta.icon.contains('widget.png'), meta.icon);

    final answer = await runtime.load(fixture, 'getPopular', {'page': 1});
    _check('数据源返回数组', answer.items.length == 2, '${answer.items.length} 条');
    final first = answer.items.first;
    _check('海报字段按优先级映射', '${first['image']}'.contains('1.webp'));
    _check('直链字段按优先级映射', '${first['videoUrl']}'.contains('1.m3u8'));
    final second = answer.items.last;
    _check('name 兜底到 title', '${second['title']}' == '夹具影片二');
    _check('media_type 兜底', '${second['mediaType']}' == 'tv');
    _check('组件日志带回来', answer.logs.any((line) => line.contains('widget fixture')));

    final detail = await runtime.detail(
      fixture,
      'https://example.com/detail/2',
    );
    _check('loadDetail 被调用', detail != null);
    _check('详情标题来自组件', detail?.title == '夹具详情', detail?.title ?? '');
    _check('多季多集被归一', detail?.episodes.length == 2, '${detail?.episodes.length}');
    _check(
      '播放线路来自组件',
      detail?.episodes.first.url.contains('s1e1-line1') ?? false,
    );
    _check('标签与演员带回来', detail?.tags.length == 2 && detail?.cast.length == 1);

    try {
      await runtime.load(fixture, 'noSuchFunction', {});
      _check('不存在的函数会失败', false);
    } on Object catch (error) {
      _check('不存在的函数会失败', '$error'.contains('Data source function not found'));
    }
  } finally {
    await runtime.dispose();
  }

  if (_failures > 0) exit(1);
  stdout.writeln('组件宿主自检通过');
}
