import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/demo_data.dart';
import '../widgets/media_card.dart';
import '../widgets/poster_art.dart';

/// 资源页：源订阅与网络挂载的列表。
///
/// The original shows each source as a white card with a navy rounded icon, a
/// bold name, a blue "当前使用 · N 集" status line, a red latency value on the
/// right and a "···" overflow button. There is no data layer yet, so a single
/// fixture card stands in for the source list until the Phase 2 host populates
/// it.
class ResourcesPage extends StatelessWidget {
  const ResourcesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          LcbMetrics.settingsPaddingLeft,
          17,
          LcbMetrics.settingsPaddingRight,
          40,
        ),
        children: const [
          _SourceCard(
            icon: CupertinoIcons.book_fill,
            iconBg: Color(0xFF3A4A6B),
            name: '豆儿猫源',
            status: '当前使用 · 58 部',
            latency: '5.0s',
          ),
          SizedBox(height: 24),
          _AddCard(label: '添加资源'),
        ],
      ),
    );
  }
}

/// One source card: icon + name + status line, latency and overflow on the
/// right. The light blue outline matches the original's selected card.
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.iconBg,
    required this.name,
    required this.status,
    required this.latency,
  });

  final IconData icon;
  final Color iconBg;
  final String name;
  final String status;
  final String latency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: LcbColors.surface,
        borderRadius: BorderRadius.circular(LcbMetrics.settingsCardRadius),
        border: Border.all(color: const Color(0xFFBBD2F5), width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: LcbColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: LcbColors.sysBlueDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            latency,
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
    );
  }
}

/// 收藏页：收藏的影片与追更的剧集。
///
/// The 收藏 / 追剧 tabs live in the shell's top bar; the body shows either the
/// favourites grid or the empty state. Favourites are empty by default so the
/// page opens on the original's empty state.
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: _favoriteItems.isEmpty
          ? const Center(
              child: _EmptyHint(
                icon: CupertinoIcons.heart,
                title: '这里还没有收藏',
                subtitle: '在影视详情页点收藏、在直播首页长按频道，就会出现在这里。',
              ),
            )
          : _PosterGrid(items: _favoriteItems),
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
    final entries = _historyEntries;
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
// Favourites / follow fixtures
// ---------------------------------------------------------------------------

/// Favourite poster set. Empty by default so the page opens on the original's
/// empty state; the real favourites store will populate it in Phase 2.
final List<MediaItem> _favoriteItems = [];

// ---------------------------------------------------------------------------
// History fixtures
// ---------------------------------------------------------------------------

class _HistoryEntry {
  const _HistoryEntry(this.media, this.episodeLabel, this.progressLabel,
      this.progress, this.timeSourceLabel);

  final MediaItem media;
  final String episodeLabel;
  final String progressLabel;
  final double progress;
  final String timeSourceLabel;
}

final List<_HistoryEntry> _historyEntries = [
  for (final s in homeSections)
    for (final m in s.items.take(3))
      _HistoryEntry(
        m,
        '第${_epFor(m)}集',
        '看到 ${_pctFor(m)}',
        _progressFor(m),
        '${_daysAgo(m)} · ${_sourceName(m)}',
      ),
];

int _epFor(MediaItem m) => 3 + (m.id.hashCode.abs() % 40);

String _pctFor(MediaItem m) => '${(1 + m.id.hashCode.abs() % 90)}%';

double _progressFor(MediaItem m) =>
    (0.1 + (m.id.hashCode.abs() % 80) / 100.0).clamp(0.0, 0.9);

String _daysAgo(MediaItem m) =>
    m.id.hashCode % 3 == 0 ? '今天' : '${3 + m.id.hashCode.abs() % 30} 天前';

String _sourceName(MediaItem m) => const [
      '豆儿猫源',
      '猫源',
      '量子资源',
    ][m.id.hashCode.abs() % 3];

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
        Icon(icon, size: 44, color: LcbColors.sidebarLabel),
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

/// One watch-history row: thumbnail, title, episode + progress line, a source
/// + time line, and a play button on the right.
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
              width: 81,
              height: 92,
              child: PosterArt(
                seed: entry.media.posterSeed,
                image: entry.media.image,
              ),
            ),
          ),
          const SizedBox(width: 6),
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
                const SizedBox(height: 11),
                Text(
                  '${entry.episodeLabel} · ${entry.progressLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: LcbColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 15),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      value: entry.progress,
                      backgroundColor: LcbColors.searchFill,
                      valueColor: const AlwaysStoppedAnimation(
                        LcbColors.primaryDim,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  entry.timeSourceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: LcbColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _PlayButton(onTap: () {}),
        ],
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
