import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/spider_client.dart';
import 'package:lai_cui_ba/ui/widgets/browse_dialog.dart';

/// 「浏览内容」面板：分类 + 每组筛选 + 一个查看按钮。面板交出去的结果就是分类页
/// 的入参，所以这里既测「选了之后按钮说什么」，也测「交出去的条件是什么」。
void main() {
  const home = SpiderHome(
    classes: [
      SpiderClass(typeId: '1', name: '电影'),
      SpiderClass(typeId: '2', name: '剧集'),
    ],
    filters: {
      '1': [
        SpiderFilterGroup(
          key: 'class',
          init: '',
          options: [
            SpiderFilterOption(label: '全部', value: ''),
            SpiderFilterOption(label: '喜剧', value: '喜剧'),
            SpiderFilterOption(label: '爱情', value: '爱情'),
          ],
        ),
        // The source's `by` group ships no 全部; the panel adds one.
        SpiderFilterGroup(
          key: 'by',
          init: 'time',
          options: [
            SpiderFilterOption(label: '时间', value: 'time'),
            SpiderFilterOption(label: '评分', value: 'score'),
          ],
        ),
      ],
      '2': [
        SpiderFilterGroup(
          key: 'class',
          init: '',
          options: [
            SpiderFilterOption(label: '全部', value: ''),
            SpiderFilterOption(label: '古装', value: '古装'),
          ],
        ),
      ],
    },
  );

  /// Pumps a page with one button that opens the panel, then taps it.
  Future<void> openPanel(
    WidgetTester tester,
    void Function(BrowseChoice?) onDone, {
    Future<SpiderHome?> Function()? load,
  }) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  onDone(
                    await showBrowseDialog(
                      context,
                      load: load ?? () async => home,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the categories, the filter rows and a 查看 button', (
    tester,
  ) async {
    await openPanel(tester, (_) {});

    expect(find.text('浏览内容'), findsOneWidget);
    expect(find.text('选好分类与筛选条件后查看'), findsOneWidget);
    expect(find.text('电影'), findsOneWidget);
    expect(find.text('剧集'), findsOneWidget);
    expect(find.text('喜剧'), findsOneWidget);
    // Two groups render 全部: the class row and the by row the panel filled in.
    expect(find.text('全部'), findsNWidgets(2));
    expect(find.text('查看电影'), findsOneWidget);
  });

  testWidgets('a picked filter changes the button and travels back', (
    tester,
  ) async {
    BrowseChoice? choice;
    await openPanel(tester, (c) => choice = c);

    await tester.tap(find.text('喜剧'));
    await tester.pumpAndSettle();
    expect(find.text('查看筛选项结果'), findsOneWidget);

    await tester.tap(find.text('查看筛选项结果'));
    await tester.pumpAndSettle();

    expect(choice, isNotNull);
    expect(choice!.title, '电影');
    expect(choice!.typeId, '1');
    expect(choice!.filters, {'class': '喜剧'});
    expect(find.text('浏览内容'), findsNothing);
  });

  testWidgets('picking 全部 again drops the condition', (tester) async {
    BrowseChoice? choice;
    await openPanel(tester, (c) => choice = c);

    await tester.tap(find.text('喜剧'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部').first);
    await tester.pumpAndSettle();
    expect(find.text('查看电影'), findsOneWidget);

    await tester.tap(find.text('查看电影'));
    await tester.pumpAndSettle();
    expect(choice!.filters, isEmpty);
  });

  testWidgets('switching category drops the old picks', (tester) async {
    await openPanel(tester, (_) {});

    await tester.tap(find.text('喜剧'));
    await tester.pumpAndSettle();
    expect(find.text('查看筛选项结果'), findsOneWidget);

    await tester.tap(find.text('剧集'));
    await tester.pumpAndSettle();
    // Back to the plain wording, and the new category's own group is shown.
    expect(find.text('查看剧集'), findsOneWidget);
    expect(find.text('古装'), findsOneWidget);
    expect(find.text('喜剧'), findsNothing);
  });

  testWidgets('a source that does not answer says so instead of an empty picker', (
    tester,
  ) async {
    await openPanel(tester, (_) {}, load: () async => null);

    expect(find.text('这个站点没有答上来'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('many options wrap onto rows so every chip is visible and tappable', (
    tester,
  ) async {
    // A source like 大师兄 ships 17 years; the old single-line scroll row hid
    // the tail with no way to reveal it, so those chips were unreachable.
    final years = List.generate(
      17,
      (i) => SpiderFilterOption(
        label: '${2026 - i}',
        value: '${2026 - i}',
      ),
    );
    final manyHome = SpiderHome(
      classes: const [SpiderClass(typeId: '1', name: '电影')],
      filters: {
        '1': [
          SpiderFilterGroup(
            key: 'year',
            init: '',
            options: [
              const SpiderFilterOption(label: '全部', value: ''),
              ...years,
            ],
          ),
        ],
      },
    );
    BrowseChoice? choice;
    await openPanel(tester, (c) => choice = c, load: () async => manyHome);

    // Every year is laid out — none is clipped off the end of a single row.
    for (final year in years) {
      expect(find.text(year.label), findsOneWidget,
          reason: '${year.label} 应可见，不能被单行截断');
    }

    // Chips keep their original content width inside the `Wrap`. A `Container`
    // with `alignment` would expand to the dialog's full inner width (547px),
    // making every chip take a whole row.
    final firstChip = find.ancestor(
      of: find.text('2026'),
      matching: find.byType(Container),
    ).first;
    final chipWidth = tester.getSize(firstChip).width;
    expect(chipWidth, lessThan(120),
        reason: '筛选按钮应保持内容宽度，而不是撑满整行 ($chipWidth)');
    final secondChip = find.ancestor(
      of: find.text('2025'),
      matching: find.byType(Container),
    ).first;
    expect(tester.getCenter(firstChip).dy, tester.getCenter(secondChip).dy,
        reason: '相邻两个筛选按钮应在同一行');

    // The last (previously unreachable) chip can now be tapped and travels
    // back as the chosen filter.
    await tester.tap(find.text('2010'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('查看筛选项结果'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看筛选项结果'));
    await tester.pumpAndSettle();
    expect(choice!.filters, {'year': '2010'});
  });
}
