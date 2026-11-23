import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/picture.dart';
import 'package:lai_cui_ba/ui/widgets/aspect_panel.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    backgroundColor: Colors.black,
    body: Center(child: child),
  ),
);

void main() {
  testWidgets('列出六档画面比例，当前档打勾', (tester) async {
    await tester.pumpWidget(
      _wrap(const AspectPanel(mode: AspectMode.fit, onMode: _noop)),
    );

    expect(find.text('画面比例'), findsOneWidget);
    for (final m in AspectMode.values) {
      expect(find.text(m.label), findsOneWidget);
      expect(find.text(m.description), findsOneWidget);
    }
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('点一档比例上报那一档', (tester) async {
    AspectMode? picked;
    await tester.pumpWidget(
      _wrap(AspectPanel(mode: AspectMode.fit, onMode: (m) => picked = m)),
    );

    await tester.tap(find.text('拉伸全屏'));
    expect(picked, AspectMode.stretch);
  });
}

void _noop(AspectMode _) {}
