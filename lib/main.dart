import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_info.dart';
import 'core/store_scope.dart';
import 'core/theme.dart';
import 'services/runtime_paths.dart';
import 'services/spider_session.dart';
import 'services/store.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Initialise the libmpv backend shipped by media_kit_libs_video. No external
  // libmpv is passed, so the plugin's own stable build is used.
  MediaKit.ensureInitialized();

  // Load persisted state before the first frame so the pages open populated.
  final store = await AppStore.load();

  // Wire the catvod runtime when node.exe + cat_host.js are present, so search
  // and detail reach the real source. Absent binaries leave nothing to answer
  // spider requests, and the pages report that instead of showing samples.
  final runtime = RuntimePaths.resolve(
    executableDir: File(Platform.resolvedExecutable).parent.path,
  );
  if (runtime != null && runtime.available) {
    final appData = Platform.environment['APPDATA'];
    final catRoot = appData != null && appData.isNotEmpty
        ? '$appData${Platform.pathSeparator}LaiCuiBa'
              '${Platform.pathSeparator}LaiCuiBa'
              '${Platform.pathSeparator}cat'
        : '${Directory.systemTemp.path}${Platform.pathSeparator}lcb_cat';
    store.spider = SpiderSession(
      nodePath: runtime.node,
      hostScript: runtime.hostScript,
      bundleRoot: Directory(catRoot),
    );
    debugPrint('LcbSpider: runtime ready (${runtime.node})');
  } else {
    debugPrint('LcbSpider: runtime absent, spider features unavailable');
  }

  const options = WindowOptions(
    size: Size(1360, 860),
    minimumSize: Size(1040, 640),
    center: true,
    title: LcbAppInfo.name,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(LcbApp(store: store));
}

class LcbApp extends StatelessWidget {
  const LcbApp({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: MaterialApp(
        title: LcbAppInfo.name,
        debugShowCheckedModeBanner: false,
        theme: buildBclTheme(),
        home: const Shell(),
      ),
    );
  }
}
