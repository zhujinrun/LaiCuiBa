import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/detail_nav.dart';
import '../../core/resources_state.dart';
import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/store.dart';
import '../widgets/manage_folders_sheet.dart';
import '../widgets/media_card.dart';
import '../widgets/poster_art.dart';
import '../widgets/source_dialogs.dart';

/// 资源页：源订阅与网络挂载的列表。
///
/// The original shows each source as a white card with a light-grey icon that
/// varies with the source type (TVBox / 猫源 / Emby / 网盘挂载), a bold name, a
/// blue "当前使用 · N 部" status line, a red latency value on the right and a
/// "···" overflow button. The list is read from the store's persisted source
/// list and tapping a card switches the active source.
///
/// The header's three tool icons drive the view from here through [state]:
/// 三条滑块横线 toggles grouping, 放大镜 opens the filter row, 对勾圆圈 turns the
/// cards into checkboxes. None of them touch the stored sources — leaving the
/// mode puts the list straight back.
class ResourcesPage extends StatelessWidget {
  const ResourcesPage({super.key, required this.state});

  final LcbResources state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final store = StoreScope.of(context);
        final all = store.sources;
        if (all.isEmpty) {
          return const Center(
            child: _EmptyHint(
              icon: CupertinoIcons.tray_2,
              title: '还没有资源',
              subtitle: '点右上角的 + 添加一个源',
            ),
          );
        }

        final current = store.currentSourceId;
        final query = state.query.trim().toLowerCase();
        final visible = <SourceInfo>[
          for (final source in all)
            if (query.isEmpty || _matches(source, query)) source,
        ];

        const padding = EdgeInsets.fromLTRB(
          LcbMetrics.settingsPaddingLeft,
          6,
          LcbMetrics.settingsPaddingRight,
          40,
        );
        final searchBar = state.filtering
            ? _ResourceSearchBar(state: state, total: all.length)
            : null;
        final footer = state.selecting
            ? _SelectFooter(
                state: state,
                visibleIds: [for (final source in visible) source.id],
              )
            : null;

        // 平铺视图才让拖动改顺序：分组视图里卡片的邻居是别的组，拖过去没有
        // 唯一含义；多选时整张卡片要点来勾选，拖动手势会和它抢。
        if (!state.grouped && !state.selecting && visible.isNotEmpty) {
          return ScrollConfiguration(
            behavior: ScrollConfiguration.of(
              context,
            ).copyWith(scrollbars: false),
            child: ReorderableListView(
              padding: padding,
              header: searchBar,
              footer: footer,
              // Flutter's desktop default stacks an Icons.drag_handle (the
              // two bars in the screenshot) on every item's trailing edge.
              // The original has no handle: wrap the whole card in a delayed
              // drag listener instead, so long-press reordering still works
              // on every platform without the extra glyph.
              buildDefaultDragHandles: false,
              // onReorderItem already accounts for the removed row, so the
              // index pair needs no adjustment here.
              onReorderItem: (oldIndex, newIndex) =>
                  _reorder(context, all, visible, oldIndex, newIndex),
              children: [
                for (final (index, source) in visible.indexed)
                  ReorderableDelayedDragStartListener(
                    key: ValueKey('resource-drag-${source.id}'),
                    index: index,
                    child: _card(context, source, current),
                  ),
              ],
            ),
          );
        }

        final children = <Widget>[
          if (searchBar != null) searchBar,
          if (visible.isEmpty)
            _NoMatchHint(query: state.query)
          else if (state.grouped)
            ..._grouped(context, visible, current)
          else
            for (final source in visible) _card(context, source, current),
          if (footer != null) footer,
        ];

        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: ListView(padding: padding, children: children),
        );
      },
    );
  }

  /// One card, wired to whichever mode the page is in: switching the active
  /// source normally, ticking a checkbox while 多选 is on.
  Widget _card(BuildContext context, SourceInfo source, String? current) =>
      _SourceCard(
        key: ValueKey('resource-card-${source.id}'),
        source: source,
        selected: source.id == current,
        selecting: state.selecting,
        checked: state.selected.contains(source.id),
        onTap: state.selecting
            ? () => state.toggleSelected(source.id)
            : () => StoreScope.of(context).selectSource(source.id),
        onMenu: state.selecting ? null : () => showSourceMenu(context, source),
      );

  /// Moves the dragged card to the dropped card's slot and writes the new order
  /// back. Works off `all`, not the filter: dragging while a query is active
  /// still leaves the hidden sources where they were.
  ///
  /// Dragging is only offered in the flat view. In the grouped view a card's
  /// apparent neighbours belong to a different section, and "drop it here"
  /// would have no single meaning.
  void _reorder(
    BuildContext context,
    List<SourceInfo> all,
    List<SourceInfo> visible,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex == newIndex) return;
    final ids = [for (final source in all) source.id];
    final moved = visible[oldIndex].id;
    final target = visible[newIndex].id;
    final from = ids.indexOf(moved);
    final to = ids.indexOf(target);
    if (from < 0 || to < 0) return;
    ids.removeAt(from);
    ids.insert(to, moved);
    StoreScope.of(context).reorderSources(ids);
  }

  /// Groups the visible cards. A source the user put in their own group goes
  /// there; everything else falls back to its type, which is 原版
  /// 「留空按类型自动分组」. Only the first group starts expanded, matching
  /// 「默认打开第一个分组」; the rest start folded so a long list reads as a
  /// handful of rows.
  List<Widget> _grouped(
    BuildContext context,
    List<SourceInfo> visible,
    String? current,
  ) {
    final groups = <String, List<SourceInfo>>{};
    for (final source in visible) {
      final key = source.groupName.isNotEmpty
          ? source.groupName
          : source.type.sourceTypeLabel;
      groups.putIfAbsent(key, () => []).add(source);
    }
    final rows = <Widget>[];
    var first = true;
    groups.forEach((label, items) {
      // Capture per-iteration: `first` keeps mutating, and an onTap closure
      // reading the shared variable would see its *final* value (false) and
      // flip the wrong way on the first group.
      final opensFirst = first;
      final collapsed = state.isCollapsed(label, defaultCollapsed: !opensFirst);
      rows.add(
        _GroupHeader(
          key: ValueKey('resource-group-$label'),
          label: label,
          count: items.length,
          collapsed: collapsed,
          onTap: () =>
              state.toggleCollapsed(label, defaultCollapsed: !opensFirst),
          // 只有用户自己起的组名才有得管理：类型组的名字是从资源类型推出来
          // 的，改名或删除都没有意义。
          onManage: items.first.groupName.isEmpty
              ? null
              : () => showGroupManager(
                  context,
                  label: label,
                  count: items.length,
                ),
        ),
      );
      if (!collapsed) {
        for (final source in items) {
          rows.add(_card(context, source, current));
        }
      }
      first = false;
    });
    return rows;
  }

  /// Name, address, type label and the sites it declared — the four things a
  /// person would search by when looking for "that one source".
  static bool _matches(SourceInfo source, String query) {
    if (source.name.toLowerCase().contains(query)) return true;
    if (source.url.toLowerCase().contains(query)) return true;
    if (source.type.sourceTypeLabel.toLowerCase().contains(query)) return true;
    for (final site in source.sites) {
      if (site.name.toLowerCase().contains(query)) return true;
    }
    return false;
  }
}

/// The inline filter row that 放大镜 opens above the list.
class _ResourceSearchBar extends StatelessWidget {
  const _ResourceSearchBar({required this.state, required this.total});

  final LcbResources state;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: LcbColors.searchFill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.search,
              size: 15,
              color: LcbColors.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                autofocus: true,
                cursorColor: LcbColors.primary,
                onChanged: state.setQuery,
                style: const TextStyle(fontSize: 13.5, color: LcbColors.text),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '在 $total 个资源里查找',
                  hintStyle: const TextStyle(
                    fontSize: 13.5,
                    color: LcbColors.textTertiary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A folded group row: label, how many sources it holds, and a chevron.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    super.key,
    required this.label,
    required this.count,
    required this.collapsed,
    required this.onTap,
    this.onManage,
  });

  final String label;
  final int count;
  final bool collapsed;
  final VoidCallback onTap;

  /// Opens 重命名 / 删除. Null for a type group.
  final VoidCallback? onManage;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
          child: Row(
            children: [
              AnimatedRotation(
                turns: collapsed ? 0 : 0.25,
                duration: const Duration(milliseconds: 140),
                child: const Icon(
                  CupertinoIcons.chevron_right,
                  size: 13,
                  color: LcbColors.textTertiary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: LcbColors.textSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 12,
                  color: LcbColors.textTertiary,
                ),
              ),
              if (onManage != null) ...[
                const Spacer(),
                GestureDetector(
                  key: ValueKey('resource-group-menu-$label'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onManage,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Icon(
                      CupertinoIcons.ellipsis,
                      size: 14,
                      color: LcbColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The bar under the list while 多选 is on: 全选 / 已选 N / 删除.
class _SelectFooter extends StatelessWidget {
  const _SelectFooter({required this.state, required this.visibleIds});

  final LcbResources state;
  final List<String> visibleIds;

  @override
  Widget build(BuildContext context) {
    final count = state.selectedCount;
    final allPicked =
        visibleIds.isNotEmpty && count >= visibleIds.length;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          TextButton(
            onPressed: () => allPicked
                ? state.clearSelected()
                : state.selectAll(visibleIds),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              allPicked ? '取消全选' : '全选',
              style: const TextStyle(fontSize: 13.5, color: LcbColors.primary),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            '已选 $count 个',
            style: const TextStyle(
              fontSize: 13,
              color: LcbColors.textSecondary,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: count == 0 ? null : () => _confirmDelete(context),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              '删除',
              style: TextStyle(
                fontSize: 13.5,
                color: count == 0 ? LcbColors.textTertiary : LcbColors.sysRed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final store = StoreScope.of(context);
    final ids = state.selected.toList();
    final ok = await showDeleteSourcesConfirm(context, ids);
    if (ok != true) return;
    await store.removeSources(ids);
    state.clearSelected();
    state.toggleSelecting();
  }
}

/// 搜索没有命中时说的话，而不是留一片空白。
class _NoMatchHint extends StatelessWidget {
  const _NoMatchHint({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Icon(
            CupertinoIcons.search,
            size: 28,
            color: LcbColors.textTertiary,
          ),
          const SizedBox(height: 10),
          Text(
            '没有名字、地址或站点含「$query」的资源',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: LcbColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Icon + tint for each source type. The original's `flutter.sources` carries a
/// `type` discriminator (`tvbox` / `cat` / `emby` / `webdav` / `alist` /
/// `mount` / `hiker` / `kazumi` / `php`); each gets a distinct glyph so the
/// list is scannable without opening a card.
extension SourceTypeStyle on String {
  IconData get sourceIcon {
    switch (this) {
      case 'cat':
        return CupertinoIcons.square_grid_2x2;
      case 'emby':
        return CupertinoIcons.tv;
      case 'webdav':
      case 'alist':
      case 'mount':
        return CupertinoIcons.folder;
      case 'hiker':
      case 'kazumi':
        return CupertinoIcons.cloud;
      case 'php':
        return CupertinoIcons.gear;
      case 'py':
      case 'js':
        return CupertinoIcons.doc_text;
      case 'live':
        return CupertinoIcons.waveform_path_ecg;
      case 'jellyfin':
        return CupertinoIcons.tv;
      case 'tvbox':
      default:
        return CupertinoIcons.film;
    }
  }

  /// Human label for the type, shown as the small type tag on the card's right.
  String get sourceTypeLabel {
    switch (this) {
      case 'cat':
        return '猫源';
      case 'emby':
        return 'Emby';
      case 'webdav':
        return 'WebDAV';
      case 'alist':
        return 'AList';
      case 'mount':
        return '挂载';
      case 'hiker':
        return '海阔';
      case 'kazumi':
        return 'Kazumi';
      case 'php':
        return 'PHP';
      case 'py':
        return 'PY';
      case 'js':
        return 'JS';
      case 'live':
        return '直播';
      case 'jellyfin':
        return 'Jellyfin';
      case 'tvbox':
      default:
        return 'TVBox';
    }
  }
}

/// One source card: icon + name + status line, latency and overflow on the
/// right. The selected card uses the light blue outline matching the original.
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    super.key,
    required this.source,
    required this.selected,
    required this.onTap,
    required this.onMenu,
    this.selecting = false,
    this.checked = false,
  });

  final SourceInfo source;
  final bool selected;
  final VoidCallback onTap;

  /// Null while 多选 is on: the ⋯ menu would fight the checkbox for the tap.
  final VoidCallback? onMenu;

  /// 多选态：卡片左侧换成勾选框，整张卡片的点击用来勾选而不是切源。
  final bool selecting;
  final bool checked;

  /// What the card says under the name.
  ///
  /// 猫源 / py / js cards report the number of sites the config declares. A
  /// measured title count (first-screen sample) was tried and turned out to
  /// be meaningless on the card -- it is a partial count that changes with
  /// the upstream feed, so it says nothing about the source itself. Site
  /// count is stable and is what the user actually chooses from. Types with
  /// a real inventory (live channels, WebDAV/Emby libraries) keep theirs.
  String get _status {
    switch (source.type) {
      case 'live':
        // A live list has channels, not titles. Once 检测 has pulled and counted
        // it, the real number shows; a local file got its count at import time.
        if (source.channelCount > 0) {
          return '${selected ? '当前使用 · ' : ''}${source.channelCount} 个频道';
        }
        if (source.url.isEmpty) return '未设置地址';
        return selected ? '当前使用 · 待检测' : '未使用 · 待检测';
      case 'py':
        // A Python source is one file that is its own site; 检测 runs it.
        return _siteLine;
      case 'php':
        // No PHP runtime in this build, so the file is kept but never run.
        return '本地 spider 文件 · 无 PHP 运行时';
      case 'js':
        // A js source is either a local spider file or a subscription address;
        // only the latter can be booted. Either way the card shows sites.
        return _remote ? _siteLine : '本地 spider 文件 · 待宿主执行';
      case 'webdav':
        // A share has no login step to report: it either lists or it does not.
        // Folders and loose films are both "what this share has to show".
        if (source.url.isEmpty) return '未设置地址';
        if (source.movieCount > 0) {
          final prefix = selected ? '当前使用 · ' : '';
          return '$prefix${source.movieCount} 部';
        }
        if (source.showCount > 0) {
          final prefix = selected ? '当前使用 · ' : '';
          return '$prefix${source.showCount} 个目录';
        }
        return selected ? '当前使用 · 待检测' : '未使用 · 待检测';
      case 'emby':
      case 'jellyfin':
        // Logged-out and logged-in are different states, and a mount that has a
        // token but was never checked can still say whose account it is. Once
        // 检测 has read the library, the title count takes over -- the same
        // shape a 猫源 card shows.
        if (source.token.isEmpty) {
          return source.username.isEmpty
              ? '未连接 · 待登录'
              : '未连接 · ${source.username}';
        }
        if (source.movieCount > 0) {
          final prefix = selected ? '当前使用 · ' : '';
          return '$prefix${source.movieCount} 部';
        }
        if (!selected) return '已登录 · 未使用';
        return '当前使用 · 待检测';
      default:
        // Enabled sites only: a switched-off site is one the user chose not to
        // use, so counting it would overstate what this source actually does.
        return _siteLine;
    }
  }

  /// A subscription address can be booted; a local file cannot (yet).
  bool get _remote => source.url.trimLeft().toLowerCase().startsWith('http');

  /// Site count for the runnable spider types (猫源 / py / js): only sites that
  /// are switched on, i.e. the ones that take part in search and categories.
  String get _siteLine {
    final sites = source.searchableSites.length;
    // An address-only source says so even before it is selected: the user
    // just added it and needs to know why no sites appeared.
    final pending = sites == 0 && source.url.isNotEmpty;
    if (pending) {
      return selected ? '当前使用 · 待联网拉取' : '未使用 · 地址待拉取';
    }
    if (!selected) return '未使用';
    if (sites > 0) return '当前使用 · $sites 个站点';
    return selected ? '当前使用 · 待检测' : '未使用 · 待检测';
  }

  String get _latency {
    final ms = source.latencyMs;
    if (ms <= 0) return '—';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: LcbColors.card,
              borderRadius: BorderRadius.circular(
                LcbMetrics.settingsCardRadius,
              ),
              border: Border.all(
                color: selected
                    ? const Color(0xFF6FB2FC)
                    : const Color(0xFFE2EDF7),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                if (selecting) ...[
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: checked ? LcbColors.primary : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: checked
                            ? LcbColors.primary
                            : const Color(0xFFC7C7CC),
                        width: 1.5,
                      ),
                    ),
                    child: checked
                        ? const Icon(
                            CupertinoIcons.checkmark_alt,
                            size: 12,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                ],
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFEFF2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  // An applied 图标包 / 本地图标 is copied per source and wins;
                  // then a bundled-pack pick; then the type glyph.
                  child: source.iconPath.isNotEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(5),
                          child: Image.file(
                            File(source.iconPath),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Icon(
                              source.type.sourceIcon,
                              size: 20,
                              color: const Color(0xFF1D1D1F),
                            ),
                          ),
                        )
                      : source.iconId.isEmpty
                      ? Icon(
                          source.type.sourceIcon,
                          size: 20,
                          color: const Color(0xFF1D1D1F),
                        )
                      : Padding(
                          padding: const EdgeInsets.all(5),
                          child: Image.asset(
                            'assets/app_icons/${source.iconId}.webp',
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Icon(
                              source.type.sourceIcon,
                              size: 20,
                              color: const Color(0xFF1D1D1F),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: LcbColors.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _status,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: selected
                              ? LcbColors.sysBlueDark
                              : LcbColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  source.type.sourceTypeLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: LcbColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _latency,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: LcbColors.sysRed,
                  ),
                ),
                // Its own hit target, otherwise the card's onTap swallows the
                // tap and the menu never opens. Hidden in 多选 -- a menu and a
                // checkbox on the same row would be ambiguous to click.
                if (onMenu != null) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: onMenu,
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 6,
                      ),
                      child: Icon(
                        CupertinoIcons.ellipsis,
                        size: 18,
                        color: LcbColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 收藏页：收藏的影片与追更的剧集。
///
/// The 收藏 / 追剧 tabs live in the shell's top bar. The 收藏 body shows a
/// folder filter row (「全部 N」 + one chip per folder) above a poster grid,
/// matching the original's `flutter.favorites` + `flutter.favoriteFolders`
/// structure. 追剧 stays an empty state until its storage semantics are pinned
/// down.
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);

    // 追剧 tab: 原版在没登录 Trakt / Bangumi 时给出明确的空态和登录入口。
    if (store.favoritesTab != 0) {
      return Center(
        child: _EmptyHint(
          icon: CupertinoIcons.calendar,
          title: '还没有登录 Trakt 或 Bangumi',
          subtitle:
              '登录任意一个后，在影视详情页点「追更」把作品加入追更，更新会显示在这里的日历上。Bangumi 在 设置 → 账号管理 里登录。',
          action: Padding(
            padding: const EdgeInsets.only(top: 22),
            child: SizedBox(
              width: 168,
              height: 42,
              child: ElevatedButton(
                onPressed: () => showTraktLoginDialog(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: LcbColors.primaryDim,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '登录 Trakt',
                  style: TextStyle(fontSize: 15, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      );
    }

    final folders = store.favoriteFolders;
    final query = store.favoritesQuery.trim();
    final visible = query.isEmpty
        ? store.visibleFavorites
        : store.visibleFavorites
            .where((e) => e.title.contains(query))
            .toList();

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: visible.isEmpty
          ? Center(
              child: Transform.translate(
                offset: const Offset(0, -13),
                child: const _EmptyHint(
                  icon: CupertinoIcons.heart,
                  title: '这里还没有收藏',
                  subtitle: '在影视详情页点收藏、在直播首页长按频道，就会出现在这里。',
                ),
              ),
            )
          : _FavoritesBody(
              folders: folders,
              favorites: visible,
              total: store.favorites.length,
              selectedFolderId: store.favoriteFolderId,
              onFolderSelected: store.setFavoriteFolder,
              searchOpen: store.favoritesSearchOpen,
              query: store.favoritesQuery,
              onQuery: store.setFavoritesQuery,
            ),
    );
  }
}

/// The favourites body: a folder filter row on top, then the poster grid.
class _FavoritesBody extends StatelessWidget {
  const _FavoritesBody({
    required this.folders,
    required this.favorites,
    required this.total,
    required this.selectedFolderId,
    required this.onFolderSelected,
    required this.searchOpen,
    required this.query,
    required this.onQuery,
  });

  final List<FavoriteFolder> folders;
  final List<FavoriteEntry> favorites;
  final int total;
  final String? selectedFolderId;
  final ValueChanged<String?> onFolderSelected;
  final bool searchOpen;
  final String query;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (searchOpen)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LcbMetrics.pagePadding,
              12,
              LcbMetrics.pagePadding,
              0,
            ),
            child: TextField(
              autofocus: true,
              onChanged: onQuery,
              decoration: const InputDecoration(
                hintText: '在收藏中查找',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LcbMetrics.pagePadding,
            18,
            LcbMetrics.pagePadding,
            14,
          ),
          child: _FolderFilterRow(
            folders: folders,
            favorites: favorites,
            total: total,
            selectedFolderId: selectedFolderId,
            onSelected: onFolderSelected,
          ),
        ),
        Expanded(
          child: _FavoritesGrid(entries: favorites),
        ),
      ],
    );
  }
}

/// Horizontal row of folder chips: 「全部 N」 then one chip per folder.
class _FolderFilterRow extends StatelessWidget {
  const _FolderFilterRow({
    required this.folders,
    required this.favorites,
    required this.total,
    required this.selectedFolderId,
    required this.onSelected,
  });

  final List<FavoriteFolder> folders;
  final List<FavoriteEntry> favorites;
  final int total;
  final String? selectedFolderId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FolderChip(
            label: '全部',
            count: total,
            selected: selectedFolderId == null,
            onTap: () => onSelected(null),
          ),
          for (final folder in folders)
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: _FolderChip(
                label: folder.name,
                count: favorites.where((e) => e.folderId == folder.id).length,
                selected: selectedFolderId == folder.id,
                onTap: () => onSelected(folder.id),
              ),
            ),
        ],
      ),
    );
  }
}

/// A single filter chip. Selected = purple capsule with white text; unselected
/// = plain dark text. Both carry a trailing count.
class _FolderChip extends StatelessWidget {
  const _FolderChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = selected ? Colors.white : LcbColors.text;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? LcbColors.primaryDim : Colors.transparent,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(
          '$label $count',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

Future<void> _showFavoriteMenu(
  BuildContext context,
  FavoriteEntry entry,
  Offset position,
) async {
  final store = StoreScope.of(context);
  final picked = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      position.dx,
      position.dy,
    ),
    items: const [
      PopupMenuItem<String>(
        value: 'remove',
        child: Text(
          '取消收藏',
          style: TextStyle(color: Color(0xFFE5484D)),
        ),
      ),
    ],
  );
  if (picked == 'remove') {
    await store.toggleFavorite(entry);
  }
}

/// Responsive poster grid for the favourites page, reusing the home poster
/// card. The original shows 169px-wide vertical cards; the column count adapts
/// to the content width the same way the home sections do.
class _FavoritesGrid extends StatelessWidget {
  const _FavoritesGrid({required this.entries});

  final List<FavoriteEntry> entries;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gutter = LcbMetrics.posterGap;
        final columns =
            (constraints.maxWidth / (LcbMetrics.posterWidth + gutter))
                .floor()
                .clamp(3, 8);
        final cellWidth =
            (constraints.maxWidth - gutter * (columns - 1)) / columns;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            LcbMetrics.pagePadding,
            4,
            LcbMetrics.pagePadding,
            40,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 24,
            crossAxisSpacing: gutter,
            // PosterCard = poster (width*1.5) + 10 gap + one title line.
            // The title is a fixed 20px line; 2 extra pixels of headroom keep
            // the Column from overflowing regardless of the test font.
            mainAxisExtent: cellWidth * 1.5 + 32,
          ),
          itemCount: entries.length,
          itemBuilder: (_, i) {
            final entry = entries[i];
            final item = entry.toMediaItem();
            return PosterCard(
              item: item,
              width: cellWidth,
              onTap: () => LcbDetailScope.openOf(context, item),
              onMore: (position) =>
                  _showFavoriteMenu(context, entry, position),
            );
          },
        );
      },
    );
  }
}

/// 历史页：观看记录列表。
///
/// The header row (title + 清空) lives in the shell's top bar; the body is just
/// the watch-history list, one thumbnail + title + episode + source line per
/// entry.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final entries = store.history;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        if (entries.isEmpty) {
          return const Center(
            child: _EmptyHint(
              icon: CupertinoIcons.clock,
              title: '还没有观看记录',
              subtitle: '看过的影片会自动记在这里',
            ),
          );
        }
        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context)
              .copyWith(scrollbars: false),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              LcbMetrics.pagePadding,
              17,
              LcbMetrics.pagePadding,
              40,
            ),
            child: Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                for (final entry in entries) _HistoryRow(entry: entry),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

/// Centred empty state shared by the list pages. The original renders a bare
/// outline glyph in the sidebar-label grey with no tinted background chip.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 54, color: LcbColors.sidebarLabel),
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(
            fontFamily: LcbText.body,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: LcbColors.text,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: LcbColors.settingsQuiet,
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

/// One watch-history row: thumbnail, title, episode + progress line, a source
/// + time line, and a play button on the right. Hovering the card reveals a
/// delete button in its top-right corner.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final HistoryEntry entry;

  String get _progressLabel {
    final pct = (entry.progress * 100).round();
    return '看到 $pct%';
  }

  String _timeSourceLabel(AppStore store) {
    final days = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(entry.updatedAt))
        .inDays;
    final time = days <= 0
        ? '今天'
        : days == 1
        ? '昨天'
        : '$days 天前';
    final src = store.siteNameOf(
      entry.sourceId,
      entry.siteKey,
      fallback: entry.sourceName ?? '猫源',
    );
    return '$time · $src';
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final selected = store.selectedHistoryKeys.contains(entry.key);
    void openDetail() => LcbDetailScope.openOf(
      context,
      entry.toMediaItem(),
      episodeIndex: entry.episodeIndex,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTap: () => store.enterHistorySelection(entry.key),
        onTap: () {
          if (store.historySelecting) {
            store.toggleHistorySelection(entry.key);
          } else {
            openDetail();
          }
        },
        child: Container(
          width: 347,
          height: 104,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: LcbColors.card,
            borderRadius: BorderRadius.circular(LcbMetrics.cardRadius),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 80,
                  child: PosterArt(
                    seed: entry.title.hashCode,
                    image: entry.poster,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: LcbColors.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${entry.episode} · $_progressLabel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: LcbColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: const Color(0x33FFFFFF),
                        borderRadius: BorderRadius.circular(1),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: entry.progress.clamp(0.0, 1.0),
                        child: const ColoredBox(color: LcbColors.primaryDim),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _timeSourceLabel(store),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: LcbColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (store.historySelecting)
                Icon(
                  selected
                      ? CupertinoIcons.check_mark_circled_solid
                      : CupertinoIcons.circle,
                  size: 22,
                  color: selected ? LcbColors.primaryDim : LcbColors.textTertiary,
                )
              else
                _PlayButton(onTap: openDetail),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          color: LcbColors.primaryDim,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          CupertinoIcons.play_fill,
          size: 12,
          color: Colors.white,
        ),
      ),
    );
  }
}
