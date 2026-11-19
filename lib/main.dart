import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_info.dart';
import 'core/store_scope.dart';
import 'core/theme.dart';
import 'services/store.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Load persisted state before the first frame so the pages open populated.
  final store = await AppStore.load();

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
