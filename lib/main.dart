import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'core/app_info.dart';
import 'core/theme.dart';
import 'ui/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

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

  runApp(const LcbApp());
}

class LcbApp extends StatelessWidget {
  const LcbApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: LcbAppInfo.name,
      debugShowCheckedModeBanner: false,
      theme: buildBclTheme(),
      home: const Shell(),
    );
  }
}
