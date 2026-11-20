import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/detail_nav.dart';
import '../../core/search_state.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/search.dart';
import '../widgets/search_sources_dialog.dart';

/// The 搜索 page rendered into the content column while [LcbSearch.open] holds.
///
/// Three states, matching the original: nothing typed (explainer), typed but not
/// committed (suggestion drop-down), committed (per-site chip row + result rows).
class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: _states(context)),
        const Positioned(right: 24, bottom: 12, child: _SourceFab()),
      ],
    );
  }

  Widget _states(BuildContext context) {
    final search = LcbSearchScope.of(context);
    if (search.query.trim().isEmpty) return const _SearchEmpty();

    if (!search.submitted) {
      return _SuggestionPanel(suggestions: search.suggestions);
    }

    if (!search.anySource) return const _NoSourceNote();

    final outcome = search.outcome;
    if (outcome.isEmpty) return const _SearchNoResults();

    return _Results(search: search, outcome: outcome);
  }
}

/// The 56px circular source picker pinned to the bottom-right corner, as in the
/// original's search page.
class _SourceFab extends StatelessWidget {
  const _SourceFab();

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showSearchSourcesSheet(context),
        child: Container(
          width: 56,
          height: 56,
          decoration: const BoxDecoration(
            color: LcbColors.card,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            CupertinoIcons.square_grid_2x2_fill,
            size: 18,
            color: LcbColors.text,
          ),
        ),
      ),
    );
  }
}

/// Shown when every source was removed with 取消选择"全部": there is nothing left
/// to fan the query out to, so the results page says so instead of pretending
/// the query found nothing.
class _NoSourceNote extends StatelessWidget {
  const _NoSourceNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: _bodyPadding,
      child: _CenteredNote(
        icon: CupertinoIcons.tray_2,
        title: '未选择搜索源',
        subtitle: '点右下角按钮挑一个源，然后重新搜索。',
      ),
    );
  }
}

/// Body padding shared by every search state: the original starts its content at
/// 240 screen -- 16 past the 224px sidebar -- and stops 17 short of the window.
const EdgeInsets _bodyPadding = EdgeInsets.only(left: 16, right: 17);

class _SearchEmpty extends StatelessWidget {
  const _SearchEmpty();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: _bodyPadding,
      child: _CenteredNote(
        icon: CupertinoIcons.search,
        title: '搜索影视',
        subtitle: '会同时搜索影视源里的全部站点，结果按平台分组。',
      ),
    );
  }
}

/// Shown when a committed query comes back with nothing. The original's copy for
/// this state was not captured, so the wording here is ours.
class _SearchNoResults extends StatelessWidget {
  const _SearchNoResults();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: _bodyPadding,
      child: _CenteredNote(
        icon: CupertinoIcons.search,
        title: '没有找到相关影视',
        subtitle: '换个关键词，或关闭「严格」再试一次。',
      ),
    );
  }
}

/// The magnifier + headline + caption block, centred in the content column.
///
/// Measured at 1920x1040: the glyph inked 42x43, 28px down to a headline whose
/// ink is 20px, 15px down to a 13px caption. CupertinoIcons.search only inks
/// about 80% of its box, so the box is 53 to land the same 42px glyph.
class _CenteredNote extends StatelessWidget {
  const _CenteredNote({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 53, color: LcbColors.sidebarLabel),
          const SizedBox(height: 22),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.0,
              color: LcbColors.text,
            ),
          ),
          const SizedBox(height: 15),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 14,
              height: 1.0,
              color: LcbColors.settingsQuiet,
            ),
          ),
        ],
      ),
    );
  }
}

/// The drop-down under the field: one 42px row per suggestion.
class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({required this.suggestions});

  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    final search = LcbSearchScope.of(context);
    if (suggestions.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 17, top: 6),
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
          decoration: BoxDecoration(
            color: LcbColors.card,
            borderRadius: BorderRadius.circular(LcbMetrics.cardRadius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(LcbMetrics.cardRadius),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final suggestion in suggestions)
                  _SuggestionRow(
                    label: suggestion,
                    onTap: () => search.pickSuggestion(suggestion),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatefulWidget {
  const _SuggestionRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_SuggestionRow> createState() => _SuggestionRowState();
}

class _SuggestionRowState extends State<_SuggestionRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.only(left: 18),
          color: _hover ? LcbColors.hover : Colors.transparent,
          // The original's glyphs sit ~5px below the row's centre -- its line
          // box carries more leading than a height:1.0 TextStyle does here.
          child: Transform.translate(
            offset: const Offset(0, 5),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.search,
                  size: 13,
                  color: LcbColors.sidebarLabel,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.0,
                      color: LcbColors.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Chip row plus the grouped result rows.
class _Results extends StatelessWidget {
  const _Results({required this.search, required this.outcome});

  final LcbSearch search;
  final SearchOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final hits = search.visibleHits;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 17, top: 11),
          child: _SiteChips(search: search, outcome: outcome),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(left: 16, right: 17, bottom: 24),
            itemCount: hits.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _ResultCard(hit: hits[i]),
          ),
        ),
      ],
    );
  }
}

/// 全部 N, then one chip per site, then the 还有 N 个站点 tail and the expand
/// button on the right.
class _SiteChips extends StatelessWidget {
  const _SiteChips({required this.search, required this.outcome});

  final LcbSearch search;
  final SearchOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final shown = outcome.sites.take(searchSitesShown).toList(growable: false);
    final hidden = outcome.overflow(searchSitesShown);

    return SizedBox(
      height: 34,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _Chip(
                    label: '全部',
                    count: outcome.total,
                    selected: search.site == null,
                    onTap: () => search.selectSite(null),
                  ),
                  for (final site in shown) ...[
                    const SizedBox(width: 9),
                    _Chip(
                      label: '「盘」 ${site.site}',
                      count: site.count,
                      selected: search.site == site.site,
                      onTap: () => search.selectSite(site.site),
                    ),
                  ],
                  if (hidden > 0) ...[
                    const SizedBox(width: 16),
                    _OverflowLabel(hidden: hidden),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          const _ExpandButton(),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? LcbColors.primaryDim : LcbColors.card,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                  color: selected ? Colors.white : LcbColors.text,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                  color: selected ? Colors.white : LcbColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The  ✳ 还有 N 个站点 tail.
class _OverflowLabel extends StatelessWidget {
  const _OverflowLabel({required this.hidden});

  final int hidden;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          CupertinoIcons.sparkles,
          size: 13,
          color: LcbColors.textTertiary,
        ),
        const SizedBox(width: 8),
        Text(
          '还有 $hidden 个站点',
          style: const TextStyle(
            fontSize: 13,
            height: 1.0,
            color: LcbColors.settingsQuiet,
          ),
        ),
      ],
    );
  }
}

/// The 36px circular chevron on the right of the chip row.
class _ExpandButton extends StatelessWidget {
  const _ExpandButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: const BoxDecoration(
        color: LcbColors.card,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        CupertinoIcons.chevron_down,
        size: 12,
        color: LcbColors.text,
      ),
    );
  }
}

/// One result row: 60x90 poster, three text lines, trailing chevron.
class _ResultCard extends StatefulWidget {
  const _ResultCard({required this.hit});

  final SearchHit hit;

  @override
  State<_ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<_ResultCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final hit = widget.hit;
    final MediaItem item = hit.item;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: () => LcbDetailScope.openOf(context, item),
        child: Container(
          height: 108,
          padding: const EdgeInsets.only(left: 10, right: 12),
          decoration: BoxDecoration(
            color: _hover ? LcbColors.hover : LcbColors.card,
            borderRadius: BorderRadius.circular(LcbMetrics.cardRadius),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 60,
                  height: 90,
                  child: _Poster(item: item),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                // Fixed 108px card, so the three lines are placed from the top
                // instead of centred: measured 19 / 47 / 71 from the card edge.
                child: Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                          color: LcbColors.text,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        hit.remarks,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.0,
                          color: LcbColors.settingsQuiet,
                        ),
                      ),
                      const SizedBox(height: 13),
                      _SiteTag(site: hit.site),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Icon(
                CupertinoIcons.chevron_forward,
                size: 15,
                color: LcbColors.chevron,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final image = item.image;
    if (image == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              LcbColors.primaryContainer,
              LcbColors.primaryContainer.withValues(alpha: 0.4),
            ],
          ),
        ),
      );
    }
    return Image.asset(
      image,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const ColoredBox(color: LcbColors.card),
    );
  }
}

/// The small 「盘」 site pill under a result's remarks.
class _SiteTag extends StatelessWidget {
  const _SiteTag({required this.site});

  final String site;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: LcbColors.primaryContainer,
        borderRadius: BorderRadius.circular(LcbMetrics.chipRadius),
      ),
      // widthFactor keeps the pill hugging its text: a plain `alignment:` on the
      // Container would stretch it across the whole row instead.
      child: Center(
        widthFactor: 1,
        child: Text(
          '「盘」 $site',
          style: const TextStyle(
            fontSize: 11,
            height: 1.0,
            color: LcbColors.primaryDim,
          ),
        ),
      ),
    );
  }
}
