import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../widgets/media_card.dart';
import '../widgets/poster_art.dart';

/// 资源页：源订阅与网络挂载的列表。
///
/// The original shows each source as a white card with a light-grey film-strip
/// icon, a bold name, a blue "当前使用 · N 部" status line, a red latency value
/// on the right and a "···" overflow button. The list is read from the store's
/// persisted source list.
class ResourcesPage extends StatelessWidget {
  const ResourcesPage({super.key});

  String _latencyLabel(int ms) {
    if (ms <= 0) return '—';
    return '${(ms / 1000).toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final sources = store.sources;
    final current = store.currentSourceId;

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
              name: s.name,
              status: s.id == current ? '当前使用 · ${s.movieCount} 部' : '未使用',
              latency: _latencyLabel(s.latencyMs),
              selected: s.id == current,
            ),
        ],
      ),
    );
  }
}

/// One source card: icon + name + status line, latency and overflow on the
/// right. The selected card uses the light blue outline matching the original.
class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.name,
    required this.status,
    required this.latency,
    required this.selected,
  });

  final String name;
  final String status;
  final String latency;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: LcbColors.card,
          borderRadius: BorderRadius.circular(LcbMetrics.settingsCardRadius),
          border: Border.all(
            color: selected ? const Color(0xFF6FB2FC) : const Color(0xFFE2EDF7),
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
              child: const Icon(
                CupertinoIcons.film,
                size: 20,
                color: Color(0xFF1D1D1F),
              ),
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
      ),
    );
  }
}

/// 收藏页：收藏的影片与追更的剧集。
///
/// The 收藏 / 追剧 tabs live in the shell's top bar; the body shows either the
/// favourites grid or the empty state. The data comes from the store's history
/// entries flagged as favourite / following (the original folds favourites into
/// history).
class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final entries = store.favoritesTab == 0 ? store.favorites : store.following;
    final items = entries.map((e) => e.toMediaItem()).toList();

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: items.isEmpty
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
          : _PosterGrid(items: items),
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

/// Responsive poster grid for the favourites page.
class _PosterGrid extends StatelessWidget {
  const _PosterGrid({required this.items});

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
            17,
            LcbMetrics.pagePadding,
            40,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 24,
            crossAxisSpacing: gutter,
            childAspectRatio: cellWidth / (cellWidth * 1.5 + 10 + 20),
          ),
          itemCount: items.length,
          itemBuilder: (_, i) =>
              PosterCard(item: items[i], width: cellWidth, onTap: () {}),
        );
      },
    );
  }
}

/// One watch-history row: thumbnail, title, episode + progress line, a source
/// + time line, and a play button on the right.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final HistoryEntry entry;

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
        child: Container(
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
