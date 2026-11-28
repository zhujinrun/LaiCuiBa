import 'dart:ui' show Size;

import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart'
    show
        Builder,
        Center,
        MaterialApp,
        Row,
        Scaffold,
        Text,
        TextButton,
        TextField;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/core/store_scope.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/store.dart';
import 'package:lai_cui_ba/ui/widgets/source_dialogs.dart';

/// 编辑资源弹框：改名称/地址要保存，但绝不能把下面站点开关的结果覆盖回去。
/// 站点开关是直接写进 store 的，保存若从弹框打开时的旧快照 copyWith，就会把
/// 刚关掉的 Emby / Alist 重新打开——这正是本测试要钉住的行为。
void main() {
  Future<AppStore> storeWithSource() async {
    SharedPreferences.setMockInitialValues({});
    final store = await AppStore.load();
    await store.addSource(
      const SourceInfo(
        id: 'edit-sites',
        type: 'tvbox',
        name: '豆儿猫源',
        url: 'https://example.com/config.js',
        homeSite: 'emby',
        sites: [
          SiteInfo(key: 'emby', name: 'Emby', api: 'emby', enabled: true),
          SiteInfo(key: 'alist', name: 'Alist', api: 'alist', enabled: true),
        ],
      ),
    );
    return store;
  }

  testWidgets('closing a site then saving keeps it disabled', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = await storeWithSource();
    final source = store.sources.firstWhere((s) => s.id == 'edit-sites');

    await tester.pumpWidget(
      StoreScope(
        store: store,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showEditSourceDialog(context, source),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Expand the site list, then switch off Emby by its row (not switch index,
    // since a parsed source can declare more sites than the two we seeded).
    await tester.tap(find.textContaining('站点'));
    await tester.pumpAndSettle();
    final embySwitch = find.descendant(
      of: find.ancestor(
        of: find.text('Emby'),
        matching: find.byType(Row),
      ),
      matching: find.byType(CupertinoSwitch),
    );
    expect(embySwitch, findsOneWidget);
    await tester.tap(embySwitch);
    await tester.pumpAndSettle();

    // Also rename the source so we prove name/url still save on the same path.
    final nameField = find.byWidgetPredicate(
      (w) => w is TextField && w.controller?.text == '豆儿猫源',
    );
    await tester.enterText(nameField, '改名后的源');
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final saved = store.sources.firstWhere((s) => s.id == 'edit-sites');
    expect(saved.name, '改名后的源');
    expect(
      saved.sites.firstWhere((s) => s.key == 'emby').enabled,
      isFalse,
      reason: '保存不能把刚关掉的 Emby 重新打开',
    );
    expect(
      saved.sites.firstWhere((s) => s.key == 'alist').enabled,
      isTrue,
    );
  });
}
