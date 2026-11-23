import 'package:flutter/foundation.dart';

/// 资源页的共享状态：分组视图、搜索词、多选。
///
/// 顶栏的三横线 / 放大镜 / 对勾圆圈活在 shell 的 header 里，卡片列表活在内容
/// 列，两边共用这一个对象——所以由 shell 持有、各自读一份，不层层传参。
///
/// 三项都只影响「看到的列表」，不动任何源数据：退出多选、清空搜索、切回平铺
/// 都能立刻回到原样，不需要 store 参与。
class LcbResources extends ChangeNotifier {
  /// 分组视图。开着时按源的类型分组（默认展开第一组），关掉就平铺。
  ///
  /// 这是原版「关闭后资源页直接显示分组，默认打开第一个分组」的那条：
  /// 开着＝先看到分组、点开看某组；关掉＝所有卡片一屏铺开。
  bool _grouped = true;
  bool get grouped => _grouped;

  void toggleGrouped() {
    _grouped = !_grouped;
    notifyListeners();
  }

  /// 搜索条的展开态与输入内容。
  bool _filtering = false;
  bool get filtering => _filtering;

  String _query = '';
  String get query => _query;
  bool get hasQuery => _query.trim().isNotEmpty;

  void toggleFilter() {
    _filtering = !_filtering;
    // 收起时把词清掉：否则再打开会看见上一次的过滤结果，却以为列表短了。
    if (!_filtering) _query = '';
    notifyListeners();
  }

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    notifyListeners();
  }

  /// 多选删除态。
  bool _selecting = false;
  bool get selecting => _selecting;

  final Set<String> _selected = <String>{};
  Set<String> get selected => Set.unmodifiable(_selected);
  int get selectedCount => _selected.length;

  void toggleSelecting() {
    _selecting = !_selecting;
    if (!_selecting) _selected.clear();
    notifyListeners();
  }

  void toggleSelected(String id) {
    if (!_selected.remove(id)) _selected.add(id);
    notifyListeners();
  }

  void selectAll(Iterable<String> ids) {
    _selected
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  void clearSelected() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// 分组的展开/折叠。没有显式记录时由调用方给默认值——排在第一个的组默认
  /// 展开、其余默认折叠，就是原版「默认打开第一个分组」。
  final Map<String, bool> _collapsed = <String, bool>{};

  bool isCollapsed(String group, {bool defaultCollapsed = true}) =>
      _collapsed[group] ?? defaultCollapsed;

  void toggleCollapsed(String group, {bool defaultCollapsed = true}) {
    _collapsed[group] = !isCollapsed(group, defaultCollapsed: defaultCollapsed);
    notifyListeners();
  }

  /// Drops the transient view state when the page is left.
  ///
  /// 分组偏好留着（那是长期口味），但搜索词和多选只对离开前那一屏有意义：
  /// 回来时还看见被过滤的短列表、或者一屏勾选框，都会让人以为资源少了。
  void resetView() {
    var changed = false;
    if (_filtering || _query.isNotEmpty) {
      _filtering = false;
      _query = '';
      changed = true;
    }
    if (_selecting || _selected.isNotEmpty) {
      _selecting = false;
      _selected.clear();
      changed = true;
    }
    if (changed) notifyListeners();
  }
}
