import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/skip_rule.dart';
import '../widgets/media_badges.dart';
import '../widgets/skip_panel.dart';

/// 详情页 — 影片详情（hero + 选集 + 演员阵容 + 分类）。
///
/// Structure and metrics come from the original 1.0.6 TVBox detail page at
/// 1920x1040: a full-bleed blurred backdrop 386 high carrying the 204x306
/// poster and the title block, then the episode grid, the cast rail and the
/// category chips on white. The page is pushed into the content column, so the
/// sidebar stays visible and the shell header swaps in a back arrow.
///
/// Non-functional controls (换平台 / 下载 / 追更 / 评论 and the 选集 filters) are
/// rendered but inert: they need the source layer from Phase 2. 收藏 is live and
/// writes to `flutter.favorites`.
class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.item,
    this.episodeIndex,
    this.onPlay,
  });

  final MediaItem item;

  /// Episode the user last watched, used for the 「继续」 button and the
  /// highlighted chip. Null for films and for titles with no history.
  final int? episodeIndex;

  /// Invoked with the episode index the user chose to play (null for films) and
  /// the selected play line. The shell resolves the URL and opens the player;
  /// keeping the resolution there lets it fall back to the source's `play`
  /// action when the detail carries no play URLs.
  final void Function(int? episodeIndex, int lineIndex)? onPlay;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  /// Page of the episode grid currently shown (0-based). Opens on the page that
  /// holds the resume episode, matching the original.
  late int _range = _rangeOf(widget.episodeIndex);

  /// Selected play line (线路) index. When the detail carries [MediaItem.playLines],
  /// the episode grid renders that line's episodes; 0 otherwise.
  int _line = 0;

  static const _rangeSize = 20;

  int _rangeOf(int? index) =>
      index == null ? 0 : (index ~/ _rangeSize).clamp(0, 1 << 20);

  MediaItem get item => widget.item;

  /// Lines to choose from; empty when the record carries no play URLs, which is
  /// the state before the source's detail call lands.
  List<PlayLine> get lines => item.playLines;

  /// Episode labels for the selected line, falling back to [MediaItem.episodes]
  /// when the record carries no play URLs.
  List<String> get episodes {
    if (lines.isNotEmpty && _line < lines.length) {
      return [for (final e in lines[_line].episodes) e.label];
    }
    return item.episodes;
  }

  bool get _isFavorite =>
      StoreScope.of(context).favorites.any((e) => e.title == item.title);

  /// Label for the primary button: 「继续 第N集」 for series, 「播放」 for films.
  String get _resumeLabel {
    if (episodes.isEmpty) return '播放';
    final i = widget.episodeIndex;
    if (i != null && i < episodes.length) return '继续 ${episodes[i]}';
    return '继续 ${episodes.first}';
  }

  Future<void> _toggleFavorite() async {
    final store = StoreScope.of(context);
    final existing = store.favorites.where((e) => e.title == item.title);
    if (existing.isNotEmpty) {
      await store.toggleFavorite(existing.first);
      return;
    }
    await store.toggleFavorite(
      FavoriteEntry(
        key: '${store.currentSourceId ?? ''}|detail|${item.id}',
        sourceId: store.currentSourceId ?? '',
        title: item.title,
        poster: item.image ?? '',
        latest: item.latest ?? '',
        addedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// Primary button: plays the resume episode for series, the film itself
  /// otherwise.
  void _onPlayPrimary() {
    final cb = widget.onPlay;
    if (cb == null) return;
    if (episodes.isEmpty) {
      cb(null, _line); // film
      return;
    }
    final i = widget.episodeIndex;
    cb(i != null && i < episodes.length ? i : 0, _line);
  }

  /// Episode chip: plays the selected episode (its index within the full list).
  void _onPlayEpisode(int index) => widget.onPlay?.call(index, _line);

  /// Line chip: switches the selected play line and re-opens the grid on its
  /// first page.
  void _onSelectLine(int line) {
    setState(() {
      _line = line;
      _range = 0;
    });
  }

  String _skipLabel(int ms) =>
      ms <= 0 ? '不跳过' : '${ms ~/ 1000} 秒';

  Future<void> _openSkipSettings() async {
    final store = StoreScope.of(context);
    final own = store.skipOverrideFor(item.title);
    final chosen = await showDialog<SkipOverride>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xF21C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '本剧片头片尾',
                style: TextStyle(fontSize: 15, color: Colors.white),
              ),
              const SizedBox(height: 12),
              SkipPanel(
                global: store.skipRule,
                own: own,
                effective: store.skipRuleFor(item.title),
                enabled: store.settings.skipIntroOutro,
                onPicked: (value) => Navigator.of(context).pop(value),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (own.isNotEmpty)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(
                        SkipOverride.none,
                      ),
                      child: const Text('清除本剧设置'),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    await store.setSkipOverride(item.title, chosen);
  }

  @override
  Widget build(BuildContext context) {
    final ranges = <int>[
      for (var i = 0; i < (episodes.length / _rangeSize).ceil(); i++)
        i * _rangeSize,
    ];
    final start = _range * _rangeSize;
    final pageItems = episodes.skip(start).take(_rangeSize).toList();

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Hero(
              item: item,
              resumeLabel: _resumeLabel,
              favorite: _isFavorite,
              onFavorite: _toggleFavorite,
              onPlay: _onPlayPrimary,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                LcbMetrics.pagePadding,
                25,
                LcbMetrics.pagePadding,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 30),
                  const _SectionTitle('片头片尾'),
                  const SizedBox(height: 12),
                  _SkipRow(
                    intro: _skipLabel(
                      StoreScope.of(context)
                          .skipRuleFor(item.title)
                          .intro.inMilliseconds,
                    ),
                    outro: _skipLabel(
                      StoreScope.of(context)
                          .skipRuleFor(item.title)
                          .outro.inMilliseconds,
                    ),
                    own: StoreScope.of(context)
                        .skipOverrideFor(item.title)
                        .isNotEmpty,
                    onTap: _openSkipSettings,
                  ),
                  if (episodes.isNotEmpty) ...[
                    _EpisodeHeader(
                      ranges: ranges,
                      selectedRange: _range,
                      onRange: (r) => setState(() => _range = r),
                      total: episodes.length,
                      lineNames: [for (final l in lines) l.name],
                      selectedLine: _line,
                      onSelectLine: _onSelectLine,
                      // The real site the record came from; the original shows
                      // the same chip, only there it is `「直」荐片` because its
                      // home feed was drawn from that site.
                      siteLabel: StoreScope.of(context).siteNameOfKey(
                        item.siteKey,
                        fallback: item.sourceName ?? '全部站点',
                      ),
                    ),
                    const SizedBox(height: 10),
                    _EpisodeGrid(
                      labels: pageItems,
                      current: widget.episodeIndex,
                      offset: start,
                      onEpisode: _onPlayEpisode,
                    ),
                  ],
                  if (item.actors.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    const _SectionTitle('演员阵容'),
                    const SizedBox(height: 16),
                    _CastRail(names: item.actors),
                  ],
                  if (item.categories.isNotEmpty) ...[
                    const SizedBox(height: 41),
                    const _SectionTitle('分类'),
                    const SizedBox(height: 16),
                    _CategoryRow(categories: item.categories),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

/// Full-bleed backdrop: the cover blown up and blurred, a bottom white fade,
/// then the poster and the title block on top. Height is fixed at 386, which is
/// poster 306 + 40 top and bottom air in the original.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.item,
    required this.resumeLabel,
    required this.favorite,
    required this.onFavorite,
    required this.onPlay,
  });

  final MediaItem item;
  final String resumeLabel;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 386,
      child: Stack(
        children: [
          Positioned.fill(child: _Backdrop(image: item.image)),
          Positioned(
            left: LcbMetrics.pagePadding,
            top: 35,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 204,
                height: 306,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      item.image ?? '',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const ColoredBox(
                        color: Color(0xFF2B2B2E),
                      ),
                    ),
                    MediaBadgeRow(
                      item: item,
                      settings: StoreScope.of(context).settings,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // OverflowBox + ClipRect: the copy block is laid out at its natural
          // height and clipped to the band instead of tripping a RenderFlex
          // overflow when a test font or an extra-long synopsis runs long.
          Positioned(
            left: 276,
            top: 92,
            right: 40,
            bottom: 0,
            child: ClipRect(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                maxHeight: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 13),
                    _MetaChips(item: item),
                    if (item.overview != null && item.overview!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      // The synopsis column is far narrower than the band: the
                      // original wraps it at ~845 rather than at the window edge.
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 845),
                        child: Text(
                          item.overview!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.62,
                            color: Color(0xFFE2E2E2),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    _ActionRow(
                      resumeLabel: resumeLabel,
                      favorite: favorite,
                      onFavorite: onFavorite,
                      onPlay: onPlay,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The blurred cover with the bottom fade to white.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.image});

  final String? image;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null && image!.isNotEmpty)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Image.asset(image!, fit: BoxFit.cover),
            )
          else
            const ColoredBox(color: Color(0xFF2B2B2E)),
          // Slight darkening so white type keeps its contrast on bright covers.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0x9E000000), Color(0x6B000000)],
              ),
            ),
          ),
          // Bottom fade: the band dissolves into the page background.
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 120,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The meta row under the title: latest episode, year, region and genres.
class _MetaChips extends StatelessWidget {
  const _MetaChips({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      if (item.latest != null && item.latest!.isNotEmpty) item.latest!,
      if (item.year != null) '${item.year}',
      if (item.area != null && item.area!.isNotEmpty) item.area!,
      ...item.categories,
    ];
    return Wrap(
      spacing: 8,
      children: [
        for (final label in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }
}

/// 继续 + the five secondary actions. Heights and gaps are measured: 42 tall,
/// 13 between pills.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.resumeLabel,
    required this.favorite,
    required this.onFavorite,
    required this.onPlay,
  });

  final String resumeLabel;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _PillButton(
          label: resumeLabel,
          icon: CupertinoIcons.play_fill,
          primary: true,
          onTap: onPlay,
        ),
        const SizedBox(width: 13),
        const _PillButton(label: '换平台', icon: CupertinoIcons.shuffle),
        const SizedBox(width: 13),
        const _PillButton(label: '下载', icon: CupertinoIcons.arrow_down_to_line),
        const SizedBox(width: 13),
        _PillButton(
          label: '收藏',
          icon: favorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
          onTap: onFavorite,
        ),
        const SizedBox(width: 13),
        const _PillButton(label: '追更', icon: CupertinoIcons.book),
        const SizedBox(width: 13),
        const _PillButton(label: '评论', icon: CupertinoIcons.chat_bubble_2),
      ],
    );
  }
}

class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    this.primary = false,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback? onTap;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final primary = widget.primary;
    final bg = primary
        ? (_hover ? const Color(0xFF8678BC) : LcbColors.primaryDim)
        : (_hover ? const Color(0x33FFFFFF) : const Color(0x14FFFFFF));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap ?? () {},
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(21),
            border: Border.all(
              color: primary ? Colors.transparent : const Color(0x2EFFFFFF),
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 15, color: Colors.white),
              const SizedBox(width: 9),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: LcbColors.text,
        height: 1.2,
      ),
    );
  }
}

/// 选集 header: the title on the left, the (inert) source/episode filters and
/// the total on the right, then the 1-20 / 21-40 range pills.
class _EpisodeHeader extends StatelessWidget {
  const _EpisodeHeader({
    required this.ranges,
    required this.selectedRange,
    required this.onRange,
    required this.total,
    required this.siteLabel,
    required this.lineNames,
    required this.selectedLine,
    required this.onSelectLine,
  });

  final List<int> ranges;
  final int selectedRange;
  final ValueChanged<int> onRange;
  final int total;

  /// Name of the site this record came from, shown on the first filter chip.
  final String siteLabel;

  /// Names of the play lines (线路) the detail payload carried. Empty when the
  /// record has no play URLs, in which case the line chip stays inert.
  final List<String> lineNames;

  /// Index of the currently selected line in [lineNames].
  final int selectedLine;

  /// Invoked with the newly selected line index.
  final ValueChanged<int> onSelectLine;

  static const _pageSize = 20;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 32,
          child: Row(
            children: [
              const _SectionTitle('选集'),
              const Spacer(),
              _FilterChip(
                label: siteLabel,
                icon: CupertinoIcons.layers,
                caret: true,
              ),
              const SizedBox(width: 6),
              _LineChip(
                lineNames: lineNames,
                selectedLine: selectedLine,
                onSelectLine: onSelectLine,
              ),
              const SizedBox(width: 6),
              const _FilterChip(
                label: '原集名',
                icon: CupertinoIcons.arrow_right_arrow_left,
              ),
              const SizedBox(width: 6),
              const _FilterChip(
                label: '正序',
                icon: CupertinoIcons.arrow_up_arrow_down,
              ),
              const SizedBox(width: 6),
              const _FilterChip(label: '定位', icon: CupertinoIcons.scope),
              const SizedBox(width: 17),
              Text(
                '共 $total 集',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: LcbColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (ranges.length > 1) ...[
          const SizedBox(height: 13),
          Row(
            children: [
              for (final (i, start) in ranges.indexed) ...[
                if (i > 0) const SizedBox(width: 14),
                _RangePill(
                  label: '${start + 1}-${(start + _pageSize).clamp(0, total)}',
                  selected: i == selectedRange,
                  onTap: () => onRange(i),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _RangePill extends StatelessWidget {
  const _RangePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? LcbColors.primaryDim : LcbColors.searchFill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? Colors.white : LcbColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// The episode grid: fixed-width chips, as many columns as fit, 9px apart.
class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({
    required this.labels,
    required this.current,
    required this.offset,
    required this.onEpisode,
  });

  final List<String> labels;
  final int? current;

  /// Index of [labels]' first entry within the full episode list.
  final int offset;

  /// Invoked with the absolute episode index (offset + i) on tap.
  final ValueChanged<int> onEpisode;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 9.0;
        const minWidth = 92.0;
        final columns = ((constraints.maxWidth + gap) / (minWidth + gap))
            .floor()
            .clamp(1, labels.length);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: 10,
          children: [
            for (final (i, label) in labels.indexed)
              _EpisodeChip(
                label: label,
                width: width,
                selected: current != null && current == offset + i,
                onTap: () => onEpisode(offset + i),
              ),
          ],
        );
      },
    );
  }
}

class _EpisodeChip extends StatefulWidget {
  const _EpisodeChip({
    required this.label,
    required this.width,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_EpisodeChip> createState() => _EpisodeChipState();
}

class _EpisodeChipState extends State<_EpisodeChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bg = selected
        ? const Color(0xFFEDEBF5)
        : (_hover ? const Color(0xFFE6E6E6) : const Color(0xFFEFEFEF));

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: widget.width,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? LcbColors.primaryDim : LcbColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// 演员阵容: a horizontal rail of 60px discs with the name centred underneath.
class _CastRail extends StatelessWidget {
  const _CastRail({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 98,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: names.length,
        separatorBuilder: (_, __) => const SizedBox(width: 18),
        itemBuilder: (_, i) => SizedBox(
          width: 72,
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: LcbColors.card,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.person,
                  size: 30,
                  color: Color(0xFFC7C7CC),
                ),
              ),
              const SizedBox(height: 10),
              // Fixed 16px line box: 72 + 10 + 16 keeps the rail exactly 98 so
              // the sections below stay on their measured baselines.
              SizedBox(
                height: 16,
                child: Center(
                  child: Text(
                    names[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.0,
                      fontWeight: FontWeight.w600,
                      color: LcbColors.text,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.categories});

  final List<String> categories;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        for (final c in categories)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F2),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              c,
              style: const TextStyle(
                fontSize: 14,
                height: 1.3,
                color: LcbColors.text,
              ),
            ),
          ),
      ],
    );
  }
}

/// The line (线路) chip in the 选集 filter row. When the detail carries play
/// lines it shows the current line's name and opens a menu to switch; without
/// lines (no detail yet) it renders the original's literal `LZ线路` and stays
/// inert, since there is nothing to switch between.
class _LineChip extends StatefulWidget {
  const _LineChip({
    required this.lineNames,
    required this.selectedLine,
    required this.onSelectLine,
  });

  final List<String> lineNames;
  final int selectedLine;
  final ValueChanged<int> onSelectLine;

  @override
  State<_LineChip> createState() => _LineChipState();
}

class _LineChipState extends State<_LineChip> {
  bool _hover = false;

  String get _label {
    final names = widget.lineNames;
    if (names.isEmpty) return 'LZ线路';
    final i = widget.selectedLine;
    return (i >= 0 && i < names.length) ? names[i] : names.first;
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.lineNames;
    if (names.length < 2) {
      // One line (or none): no menu, just the label. Keep the caret for the
      // no-line case so the empty state still reads like the original.
      return _chip(onTap: null);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => _showMenu(context),
        child: _chip(onTap: () => _showMenu(context)),
      ),
    );
  }

  Widget _chip({VoidCallback? onTap}) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _hover ? const Color(0xFFE8E8EC) : LcbColors.searchFill,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.play_circle,
            size: 13,
            color: LcbColors.primaryDim,
          ),
          const SizedBox(width: 5),
          Text(
            _label,
            style: const TextStyle(fontSize: 12.5, color: LcbColors.text),
          ),
          const SizedBox(width: 3),
          const Icon(
            CupertinoIcons.chevron_compact_down,
            size: 12,
            color: LcbColors.textSecondary,
          ),
        ],
      ),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final names = widget.lineNames;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(topLeft.dx, topLeft.dy, box.size.width, box.size.height),
      Offset.zero & overlay.size,
    );

    final selected = await showMenu<int>(
      context: context,
      position: position,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        for (final (i, name) in names.indexed)
          PopupMenuItem<int>(
            value: i,
            child: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight:
                    i == widget.selectedLine ? FontWeight.w600 : FontWeight.w400,
                color: i == widget.selectedLine
                    ? LcbColors.primaryDim
                    : LcbColors.text,
              ),
            ),
          ),
      ],
    );
    if (selected != null && selected != widget.selectedLine) {
      widget.onSelectLine(selected);
    }
  }
}

/// A grey pill used by the 选集 filter row. Inert in Phase 1 — the values come
/// from the source's play-URL flags.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    this.caret = false,
  });

  final String label;
  final IconData icon;
  final bool caret;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: LcbColors.searchFill,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: LcbColors.primaryDim),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: LcbColors.text),
          ),
          if (caret) ...[
            const SizedBox(width: 3),
            const Icon(
              CupertinoIcons.chevron_compact_down,
              size: 12,
              color: LcbColors.textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

/// 详情页的「片头片尾」入口。原版把它放在作品自己的页里，而不是只让用户在
/// 播放中右键进度条碰运气；这里显示的永远是实际生效值（全局 + 本剧覆盖）。
class _SkipRow extends StatelessWidget {
  const _SkipRow({
    required this.intro,
    required this.outro,
    required this.own,
    required this.onTap,
  });

  final String intro;
  final String outro;
  final bool own;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: LcbColors.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.fast_forward,
              size: 18,
              color: LcbColors.sysPurple,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '片头 $intro · 片尾 $outro',
                    style: const TextStyle(
                      fontSize: 14,
                      color: LcbColors.text,
                    ),
                  ),
                  Text(
                    own ? '本剧单独设置过' : '跟随全局设置',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: LcbColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: LcbColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
