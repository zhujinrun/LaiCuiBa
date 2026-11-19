import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/demo_data.dart';
import '../widgets/media_card.dart';
import '../widgets/poster_art.dart';

/// 资源页：源订阅与网络挂载的列表。
///
/// The original keeps every source behind one row with a type glyph, a name and
/// a status line, grouped under a caption. There is no data layer yet, so the
/// fixture below shows the shape (猫源 / TVBox / Emby / WebDAV / AList) that the
/// Phase 2 source host will populate.
class ResourcesPage extends StatelessWidget {
  const ResourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          LcbMetrics.settingsPaddingLeft,
          8,
          LcbMetrics.settingsPaddingRight,
          40,
        ),
        children: const [
          _EmptyHint(
            icon: CupertinoIcons.tray_2,
            title: '还没有资源',
            subtitle: '添加猫源、TVBox、Emby、WebDAV 或网盘挂载',
          ),
          _AddCard(label: '添加资源'),
        ],
      ),
    );
  }
}

/// 收藏页：收藏的影片与追更的剧集。
///
/// Two tabs — 收藏 / 追更 — then a poster grid. The grid reuses the home rail's
/// `PosterCard` so covers, corners and hover match the rest of the app.
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final items = _tab == 0
        ? _favoriteItems
        : homeSections
            .expand((s) => s.items)
            .where((m) => _followIds.contains(m.id))
            .toList();

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LcbMetrics.pagePadding,
              17,
              LcbMetrics.pagePadding,
              0,
            ),
            child: _Segmented(
              tabs: const ['收藏', '追更'],
              selected: _tab,
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: _EmptyHint(
                      icon: CupertinoIcons.heart,
                      title: '这里还没有收藏',
                      subtitle: '点影片详情页的心形收藏后，会出现在这里',
                    ),
                  )
                : _PosterGrid(items: items),
          ),
        ],
      ),
    );
  }
}

/// 历史页：观看记录列表。
///
/// Each entry is a small portrait thumbnail + title + episode + progress, the
/// same shape the original uses for "continue watching" but vertical. The
/// trailing chevron opens the detail page; the header holds 清空观看历史.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = _historyEntries;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              LcbMetrics.pagePadding,
              17,
              LcbMetrics.pagePadding,
              0,
            ),
            child: Row(
              children: [
                const Text(
                  '观看记录',
                  style: TextStyle(
                    fontFamily: LcbText.body,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: LcbColors.text,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(
                    CupertinoIcons.trash,
                    size: 15,
                    color: LcbColors.textSecondary,
                  ),
                  label: const Text(
                    '清空观看历史',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: LcbColors.textSecondary,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: entries.isEmpty
                ? const Center(
                    child: _EmptyHint(
                      icon: CupertinoIcons.clock,
                      title: '还没有观看记录',
                      subtitle: '看过的影片会自动记在这里',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LcbMetrics.pagePadding,
                      vertical: 4,
                    ),
                    itemCount: entries.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: 8),
                    itemBuilder: (_, i) => _HistoryRow(entry: entries[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Favourites / follow fixtures
// ---------------------------------------------------------------------------

/// Favourite poster set: the movie and drama rails of the home feed stand in
/// for the user's collected titles until the real storage lands.
final List<MediaItem> _favoriteItems = [
  for (final s in homeSections.take(2)) ...s.items.take(6),
];

const Set<String> _followIds = {
  'tv0',
  'tv1',
  'tv2',
  'tv3',
  'tv6',
  'tv8',
  'anime0',
  'anime1',
  'anime2',
  'anime3',
};

// ---------------------------------------------------------------------------
// History fixtures
// ---------------------------------------------------------------------------

class _HistoryEntry {
  const _HistoryEntry(this.media, this.episodeLabel, this.positionLabel,
      this.progress, this.timeLabel);

  final MediaItem media;
  final String episodeLabel;
  final String positionLabel;
  final double progress;
  final String timeLabel;
}

final List<_HistoryEntry> _historyEntries = [
  for (final s in homeSections)
    for (final m in s.items.take(3))
      _HistoryEntry(
        m,
        m.tag ?? '正片',
        _timeLabel(m),
        _progressFor(m),
        '今天',
      ),
];

String _timeLabel(MediaItem m) => m.id.hashCode % 2 == 0 ? '12:34' : '20:15';

double _progressFor(MediaItem m) =>
    (0.15 + (m.id.hashCode.abs() % 70) / 100.0).clamp(0.0, 0.85);

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

/// Centred empty state shared by the three list pages.
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
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: LcbColors.primaryContainer,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon, size: 28, color: LcbColors.primaryDim),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          style: const TextStyle(
            fontFamily: LcbText.body,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: LcbColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.6,
            color: LcbColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// A tappable dashed-less "add" tile used at the top of the sources list.
class _AddCard extends StatelessWidget {
  const _AddCard({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(LcbMetrics.settingsCardRadius),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: LcbColors.card,
            borderRadius: BorderRadius.circular(LcbMetrics.settingsCardRadius),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                CupertinoIcons.plus,
                size: 18,
                color: LcbColors.primaryDim,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: LcbColors.primaryDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// iOS-style segmented control (收藏 / 追更).
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.tabs,
    required this.selected,
    required this.onChanged,
  });

  final List<String> tabs;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: LcbColors.searchFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tabs.length; i++)
            GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                decoration: BoxDecoration(
                  color: selected == i ? LcbColors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: selected == i
                      ? const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected == i ? FontWeight.w600 : FontWeight.w400,
                    color: selected == i
                        ? LcbColors.text
                        : LcbColors.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Responsive poster grid for the favourites page.
class _PosterGrid extends StatelessWidget {
  const _PosterGrid({required this.items});

  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gutter = LcbMetrics.posterGap;
        final columns = (constraints.maxWidth / (LcbMetrics.posterWidth + gutter))
            .floor()
            .clamp(3, 8);
        final cellWidth =
            (constraints.maxWidth - gutter * (columns - 1)) / columns;

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(
            LcbMetrics.pagePadding,
            17,
            LcbMetrics.pagePadding,
            40,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 24,
            crossAxisSpacing: gutter,
            childAspectRatio:
                cellWidth / (cellWidth * 1.5 + 10 + 20),
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => PosterCard(
            item: items[i],
            width: cellWidth,
            onTap: () {},
          ),
        );
      },
    );
  }
}

/// One watch-history row: thumbnail, title, episode + progress, chevron.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final _HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 76,
              height: 76 * 3 / 2,
              child: PosterArt(
                seed: entry.media.posterSeed,
                image: entry.media.image,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.media.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: LcbColors.text,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${entry.episodeLabel} · 看到 ${entry.positionLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: LcbColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      value: entry.progress,
                      backgroundColor: LcbColors.divider,
                      valueColor: const AlwaysStoppedAnimation(
                        LcbColors.primaryDim,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                entry.timeLabel,
                style: const TextStyle(
                  fontSize: 12,
                  color: LcbColors.textTertiary,
                ),
              ),
              const SizedBox(height: 8),
              const Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: LcbColors.chevron,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
