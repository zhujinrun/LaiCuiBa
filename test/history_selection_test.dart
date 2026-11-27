import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lai_cui_ba/services/store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('右键进入批量选择，退出后不残留选中项', () async {
    final store = await AppStore.load();
    expect(store.historySelecting, isFalse);

    store.enterHistorySelection('row-1');
    expect(store.historySelecting, isTrue);
    expect(store.selectedHistoryKeys, {'row-1'});

    store.toggleHistorySelection('row-1');
    expect(store.selectedHistoryKeys, isEmpty);
    store.toggleHistorySelection('row-2');
    expect(store.selectedHistoryKeys, {'row-2'});

    store.exitHistorySelection();
    expect(store.historySelecting, isFalse);
    expect(store.selectedHistoryKeys, isEmpty);
  });
}
