import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../widgets/media_card.dart';
import '../widgets/poster_art.dart';

/// 资源页：源订阅与网络挂载的列表。
///
/// The original shows each source as a white card with a light-grey icon that
/// varies with the source type (TVBox / 猫源 / Emby / 网盘挂载), a bold name, a
/// blue "当前使用 · N 部" status line, a red latency value on the right and a
/// "···" overflow button. The list is read from the store's persisted source
/// list and tapping a card switches the active source.
class ResourcesPage extends StatelessWidget {
  const ResourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final sources = store.sources;
    final current = store.currentSourceId;

    if (sources.isEmpty) {
      return const Center(
        child: _EmptyHint(
          icon: CupertinoIcons.tray_2,
          title: '还没有资源',
          subtitle: '点右上角的 + 添加一个源',
        ),
      );
    }

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          LcbMetrics.settingsPaddingLeft,
          6,
          LcbMetrics.settingsPaddingRight,
          40,
        ),
        children: [
          for (final s in sources)
            _SourceCard(
              source: s,
              selected: s.id == current,
              onTap: () => store.selectSource(s.id),
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
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final SourceInfo source;
  final bool selected;
  final VoidCallback onTap;

  String get _status {
    final count = source.movieCount + source.showCount;
    if (!selected) return '未使用';
    return '当前使用 · $count 部';
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
              borderRadius: BorderRadius.circular(LcbMetrics.settingsCardRadius),
              border: Border.all(
                color: selected
                    ? const Color(0xFF6FB2FC)
                    : const Color(0xFFE2EDF7),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFEFF2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    source.type.sourceIcon,
                    size: 20,
                    color: const Color(0xFF1D1D1F),
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
                const SizedBox(width: 8),
                const Icon(
                  CupertinoIcons.ellipsis,
                  size: 18,
                  color: LcbColors.textTertiary,
                ),
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

    // 追剧 tab: no data model yet — show the empty state.
    if (store.favoritesTab != 0) {
      return const Center(
        child: _EmptyHint(
          icon: CupertinoIcons.heart,
          title: '还没有追剧',
          subtitle: '关注的剧集更新后会出现在这里',
        ),
      );
    }

    final folders = store.favoriteFolders;
    final visible = store.visibleFavorites;

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
  });

  final List<FavoriteFolder> folders;
  final List<FavoriteEntry> favorites;
  final int total;
  final String? selectedFolderId;
  final ValueChanged<String?> onFolderSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          child: _FavoritesGrid(
            items: favorites.map((e) => e.toMediaItem()).toList(),
          ),
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

/// Responsive poster grid for the favourites page, reusing the home poster
/// card. The original shows 169px-wide vertical cards; the column count adapts
/// to the content width the same way the home sections do.
class _FavoritesGrid extends StatelessWidget {
  const _FavoritesGrid({required this.items});

  final List<MediaItem> items;

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
          itemCount: items.length,
          itemBuilder: (_, i) =>
              PosterCard(item: items[i], width: cellWidth, onTap: () {}),
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
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: entries.isEmpty
          ? const Center(
              child: _EmptyHint(
                icon: CupertinoIcons.clock,
                title: '还没有观看记录',
                subtitle: '看过的影片会自动记在这里',
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                LcbMetrics.pagePadding,
                17,
                LcbMetrics.pagePadding,
                40,
              ),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _HistoryRow(entry: entries[i]),
            ),
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
  });

  final IconData icon;
  final String title;
  final String subtitle;

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
      ],
    );
  }
}

/// One watch-history row: thumbnail, title, episode + progress line, a source
/// + time line, and a play button on the right. Hovering the card reveals a
/// delete button in its top-right corner.
class _HistoryRow extends StatefulWidget {
  const _HistoryRow({required this.entry});

  final HistoryEntry entry;

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _hover = false;

  HistoryEntry get entry => widget.entry;

  String get _progressLabel {
    final pct = (entry.progress * 100).round();
    return '看到 $pct%';
  }

  String get _timeSourceLabel {
    final days = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(entry.updatedAt))
        .inDays;
    final time = days <= 0
        ? '今天'
        : days == 1
        ? '昨天'
        : '$days 天前';
    final src = entry.sourceName ?? '猫源';
    return '$time · $src';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: Stack(
            children: [
              Container(
                width: 395,
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
                        height: 90,
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
                          const SizedBox(height: 14),
                          Text(
                            '${entry.episode} · $_progressLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: LcbColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _timeSourceLabel,
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
                    _PlayButton(onTap: () {}),
                  ],
                ),
              ),
              if (_hover)
                Positioned(
                  top: 6,
                  right: 6,
                  child: _DeleteButton(onTap: () {
                    StoreScope.of(context).removeHistory(entry.key);
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small circular delete affordance shown on hover, matching the app's
/// quiet grey-on-card idiom.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: LcbColors.card,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE2EDF7)),
          ),
          child: const Icon(
            CupertinoIcons.trash,
            size: 13,
            color: LcbColors.sysRed,
          ),
        ),
      ),
    );
  }
}

/// The original's trailing control on a history row is a round play button in
/// the primary tint, not a chevron.
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
