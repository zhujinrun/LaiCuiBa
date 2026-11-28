import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/ui/widgets/progress_snackbar.dart';

/// The progress SnackBar used to be a 2/10-minute bar closed by hand. If work
/// threw, or another notification cut into the queue, the bar stayed up for
/// minutes. These tests drive the real ScaffoldMessenger queue.
void main() {
  Future<ScaffoldMessengerState> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox.expand())),
    );
    return ScaffoldMessenger.of(tester.element(find.byType(Scaffold)));
  }

  testWidgets('progress is replaced by the result on success', (tester) async {
    final messenger = await pumpHost(tester);
    final gate = Completer<String>();

    final done = runProgressSnackBar(
      messenger,
      progress: '正在检测…',
      work: () => gate.future,
      progressDuration: const Duration(minutes: 2),
    );
    await tester.pump();
    expect(find.text('正在检测…'), findsOneWidget);

    gate.complete('检测完成');
    await done;
    await tester.pumpAndSettle();
    expect(find.text('正在检测…'), findsNothing);
    expect(find.text('检测完成'), findsOneWidget);
  });

  testWidgets('a throwing probe still clears the progress bar', (tester) async {
    final messenger = await pumpHost(tester);

    await runProgressSnackBar(
      messenger,
      progress: '正在检测…',
      progressDuration: const Duration(minutes: 2),
      work: () async => throw StateError('boom'),
      onError: (error) => '检测失败：$error',
    );
    await tester.pumpAndSettle();

    expect(find.text('正在检测…'), findsNothing);
    expect(find.text('检测失败：Bad state: boom'), findsOneWidget);
  });

  testWidgets('a notification raised mid-probe cannot let progress resurface',
      (tester) async {
    final messenger = await pumpHost(tester);

    final done = runProgressSnackBar(
      messenger,
      progress: '正在检测…',
      progressDuration: const Duration(minutes: 2),
      work: () async {
        // Runs while the progress bar is the visible SnackBar. A second
        // notification queues behind it; with hideCurrentSnackBar() the
        // progress bar would later take over the queue head again.
        messenger.showSnackBar(
          const SnackBar(content: Text('插队消息'), duration: Duration(seconds: 4)),
        );
        return '检测完成';
      },
    );
    await tester.pump();

    await done;
    await tester.pumpAndSettle();

    expect(find.text('正在检测…'), findsNothing);
    expect(find.text('插队消息'), findsNothing);
    expect(find.text('检测完成'), findsOneWidget);
  });

  testWidgets('progress has a finite fallback duration', (tester) async {
    final messenger = await pumpHost(tester);

    final never = Completer<String>();
    runProgressSnackBar(
      messenger,
      progress: '正在检测…',
      work: () => never.future,
    );
    await tester.pump();
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.duration, isNot(const Duration(minutes: 2)));
    expect(bar.duration, isNot(const Duration(minutes: 10)));
    expect(bar.duration.inSeconds, lessThan(120),
        reason: '卡住的探测不能把消息永久钉在屏幕上');

    // Let the helper's State go away cleanly rather than leave a pending future.
    never.complete('done');
    await tester.pumpAndSettle();
  });
}
