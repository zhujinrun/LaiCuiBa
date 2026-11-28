import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../widgets/comments_dialog.dart';
import '../widgets/detail_action_dialogs.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../widgets/media_badges.dart';
import '../widgets/poster_art.dart';

/// 详情页 — 影片详情（hero + 选集 + 演员阵容 + 分类）。
///
/// Structure and metrics come from the original 1.0.6 TVBox detail page at
/// 1920x1040: a full-bleed blurred backdrop 386 high carrying the 204x306
/// poster and the title block, then the episode grid, the cast rail and the
/// category chips on white. The page is pushed into the content column, so the
/// sidebar stays visible and the shell header swaps in a back arrow.
///
/// 换平台 / 下载 / 追更 / 评论 and the 选集 filters all have real dialogs or
/// honest empty states; 收藏 writes to `flutter.favorites`.
class DetailPage extends StatefulWidget {
  const DetailPage({
    super.key,
    required this.item,
    this.episodeIndex,
    this.onPlay,
    this.initialLine = 0,
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

  /// 上次实际能播的线路，由 Shell 从设置/历史解析后传入。
  final int initialLine;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  /// Page of the episode grid currently shown (0-based). Opens on the page that
  /// holds the resume episode, matching the original.
  late int _range = _rangeOf(widget.episodeIndex);

  /// Selected play line (线路) index. When the detail carries [MediaItem.playLines],
  /// the episode grid renders that line's episodes; 0 otherwise.
  late int _line = widget.initialLine;
  bool _lineChosen = false;
  bool _originalNames = false;
  bool _descending = false;

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
    final pick = await showFavoriteFolderDialog(context, store.favoriteFolders);
    if (pick == null) return;
    var folderId = pick.folderId;
    if (pick.newFolderName != null) {
      await store.createFavoriteFolder(pick.newFolderName!);
      folderId = store.favoriteFolders.last.id;
    }
    await store.toggleFavorite(
      FavoriteEntry(
        key: '${store.currentSourceId ?? ''}|detail|${item.id}',
        sourceId: store.currentSourceId ?? '',
        title: item.title,
        poster: item.image ?? '',
        latest: item.latest ?? '',
        folderId: folderId,
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
      _lineChosen = true;
      _range = 0;
    });
  }

  @override
  void didUpdateWidget(covariant DetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_lineChosen && widget.initialLine != oldWidget.initialLine) {
      setState(() => _line = widget.initialLine);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ranges = <int>[
      for (var i = 0; i < (episodes.length / _rangeSize).ceil(); i++)
        i * _rangeSize,
    ];
    final start = _range * _rangeSize;
    final ordered = [
      for (var i = 0; i < episodes.length; i++) i,
    ];
    if (_descending) ordered.sort((a, b) => b.compareTo(a));
    final pageIndices = ordered.skip(start).take(_rangeSize).toList();
    final pageItems = [
      for (final i in pageIndices)
        _originalNames ? '${item.title} S01E${i + 1}' : episodes[i],
    ];

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
              onPlatform: () => showPlatformDialog(context, item.title),
              onDownload: () => showDownloadDialog(context, episodes),
              onFollow: () => showFollowDialog(context, item.title),
              onComments: () => showCommentsDialog(context),
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
                  if (episodes.isNotEmpty) ...[
                    _EpisodeHeader(
                      ranges: ranges,
                      selectedRange: _range,
                      onRange: (r) => setState(() => _range = r),
                      total: episodes.length,
                      lineNames: [for (final l in lines) l.name],
                      selectedLine: _line,
                      onSelectLine: _onSelectLine,
                      onPlatform: () => showPlatformDialog(context, item.title),
                      originalNames: _originalNames,
                      onOriginalNames: () =>
                          setState(() => _originalNames = !_originalNames),
                      descending: _descending,
                      onDescending: () =>
                          setState(() => _descending = !_descending),
                      onLocate: () => setState(
                        () => _range = _rangeOf(widget.episodeIndex),
                      ),
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
                      indices: pageIndices,
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
    required this.onPlatform,
    required this.onDownload,
    required this.onFollow,
    required this.onComments,
  });

  final MediaItem item;
  final String resumeLabel;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onPlay;
  final VoidCallback onPlatform;
  final VoidCallback onDownload;
  final VoidCallback onFollow;
  final VoidCallback onComments;

  @override
  Widget build(BuildContext context) {
    // The hero was a fixed 386-high Stack with an OverflowBox-clipped copy
    // block. On a narrow window the six action pills overflowed their Row
    // (RenderFlex overflow — the yellow/black stripe in the screenshot), and
    // the clip hid the overflow rather than laying it out. Let the content
    // size the hero instead: the 204x306 poster with 35px top and 45px bottom
    // air still gives the original 386 at wide widths, while wrapped pills
    // grow the band and the Positioned.fill backdrop follows along.
    return Stack(
      children: [
        Positioned.fill(
          child: _Backdrop(image: item.image, seed: item.posterSeed),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            LcbMetrics.pagePadding,
            35,
            LcbMetrics.pagePadding,
            45,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 204,
                  height: 306,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PosterArt(
                        seed: item.posterSeed,
                        image: item.image,
                        fit: BoxFit.cover,
                      ),
                      MediaBadgeRow(
                        item: item,
                        settings: StoreScope.of(context).settings,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 32),
              // Copy block starts at y=92 (35 + 57) and x=276 (40 + 204 + 32),
              // matching the original's measured baseline at wide widths.
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 57),
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
                        onPlatform: onPlatform,
                        onDownload: onDownload,
                        onFollow: onFollow,
                        onComments: onComments,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The blurred cover with the bottom fade to white.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.image, required this.seed});

  final String? image;
  final int seed;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (image != null && image!.isNotEmpty)
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: PosterArt(
                seed: seed,
                image: image,
                fit: BoxFit.cover,
                plain: false,
              ),
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
/// 13 between pills. Wraps onto extra lines when the window is narrow instead
/// of overflowing the hero band.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.resumeLabel,
    required this.favorite,
    required this.onFavorite,
    required this.onPlay,
    required this.onPlatform,
    required this.onDownload,
    required this.onFollow,
    required this.onComments,
  });

  final String resumeLabel;
  final bool favorite;
  final VoidCallback onFavorite;
  final VoidCallback onPlay;
  final VoidCallback onPlatform;
  final VoidCallback onDownload;
  final VoidCallback onFollow;
  final VoidCallback onComments;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 13,
      runSpacing: 13,
      children: [
        _PillButton(
          label: resumeLabel,
          icon: CupertinoIcons.play_fill,
          primary: true,
          onTap: onPlay,
        ),
        _PillButton(
          label: '换平台',
          icon: CupertinoIcons.search,
          onTap: onPlatform,
        ),
        _PillButton(
          label: '下载',
          icon: CupertinoIcons.arrow_down_to_line,
          onTap: onDownload,
        ),
        _PillButton(
          label: '收藏',
          icon: favorite ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
          onTap: onFavorite,
        ),
        _PillButton(
          label: '追更',
          icon: CupertinoIcons.calendar,
          onTap: onFollow,
        ),
        _PillButton(
          label: '评论',
          icon: CupertinoIcons.chat_bubble_2,
          onTap: onComments,
        ),
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
            mainAxisSize: MainAxisSize.min,
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
    required this.onPlatform,
    required this.originalNames,
    required this.onOriginalNames,
    required this.descending,
    required this.onDescending,
    required this.onLocate,
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

  final VoidCallback onPlatform;
  final bool originalNames;
  final VoidCallback onOriginalNames;
  final bool descending;
  final VoidCallback onDescending;
  final VoidCallback onLocate;

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
                onTap: onPlatform,
              ),
              const SizedBox(width: 6),
              _LineChip(
                lineNames: lineNames,
                selectedLine: selectedLine,
                onSelectLine: onSelectLine,
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: '原集名',
                icon: CupertinoIcons.arrow_right_arrow_left,
                selected: originalNames,
                onTap: onOriginalNames,
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: descending ? '倒序' : '正序',
                icon: CupertinoIcons.arrow_up_arrow_down,
                selected: descending,
                onTap: onDescending,
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: '定位',
                icon: CupertinoIcons.scope,
                onTap: onLocate,
              ),
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
                  label: descending
                      ? '${(start + _pageSize).clamp(0, total)}-${start + 1}'
                      : '${start + 1}-${(start + _pageSize).clamp(0, total)}',
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

/// 选集网格：chip 宽度随文字长短自适应，最小 92px、最大 180px，
/// 9px 间隔，放不下就换行。
///
/// 以前在这里按可用宽度拉伸 chip：20 集时算出来正好 ~92px 看不出问题，
/// 但电影只有 2 个版本时每个会被撑到半屏宽。后来又固定成 92px，短集名
/// 没问题，但源站给的「模范家庭47号：AK47」这类长名字会在 chip 里折成
/// 两行、看起来像被压变形。现在改成按文字实测宽度取 92~180px，单行显示，
/// 超过上限才省略，长名字整体也能读完整。
class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({
    required this.labels,
    required this.current,
    required this.offset,
    required this.onEpisode,
    this.indices,
  });

  final List<String> labels;
  final List<int>? indices;
  final int? current;

  /// Index of [labels]' first entry within the full episode list.
  final int offset;

  /// Invoked with the absolute episode index (offset + i) on tap.
  final ValueChanged<int> onEpisode;

  static const _gap = 9.0;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: _gap,
      runSpacing: 10,
      children: [
        for (final (i, label) in labels.indexed)
          _EpisodeChip(
            key: ValueKey('episode-chip-${indices?[i] ?? i + offset}'),
            label: label,
            selected: current != null && current == (indices?[i] ?? i + offset),
            onTap: () => onEpisode(indices?[i] ?? i + offset),
          ),
      ],
    );
  }
}

class _EpisodeChip extends StatefulWidget {
  const _EpisodeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_EpisodeChip> createState() => _EpisodeChipState();
}

class _EpisodeChipState extends State<_EpisodeChip> {
  bool _hover = false;

  /// Short names keep the old 92px chip; long source names grow up to 180px
  /// so they stay on one line instead of wrapping into a squashed two-liner.
  static const _minWidth = 92.0;
  static const _maxWidth = 180.0;
  static const _horizontalPadding = 10.0;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bg = selected
        ? const Color(0xFFEDEBF5)
        : (_hover ? const Color(0xFFE6E6E6) : const Color(0xFFEFEFEF));
    final style = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: selected ? LcbColors.primaryDim : LcbColors.text,
    );

    final painter = TextPainter(
      text: TextSpan(text: widget.label, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = (painter.width + 2 * _horizontalPadding)
        .clamp(_minWidth, _maxWidth)
        .toDouble();
    painter.dispose();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: width,
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Tooltip(
            message: widget.label,
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ),
      ),
    );
  }
}

/// 演员阵容: 72px discs with the name centred underneath. Wraps onto as many
/// rows as fit — the same adaptive grid as 选集 — so a long cast is never cut
/// off at the edge of a narrow window.
class _CastRail extends StatelessWidget {
  const _CastRail({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 18,
      runSpacing: 22,
      children: [
        for (final name in names)
          SizedBox(
            width: 72,
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                // Fixed 16px line box keeps a single row at 98, matching the
                // original's measured baseline; extra rows add runSpacing.
                SizedBox(
                  height: 16,
                  child: Center(
                    child: Text(
                      name,
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
      ],
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
    this.selected = false,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool caret;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap ?? () {},
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected ? LcbColors.primaryDim : LcbColors.searchFill,
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
        ),
      ),
    );
  }
}
