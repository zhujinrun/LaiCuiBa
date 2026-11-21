import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/detail_nav.dart';
import '../core/search_state.dart';
import '../core/store_scope.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../services/demo_data.dart';
import '../services/store.dart';
import 'pages/common_pages.dart';
import 'pages/detail_page.dart';
import 'pages/home_page.dart';
import 'pages/player_page.dart';
import 'pages/search_page.dart';
import 'pages/settings_page.dart';
import 'page_header.dart';
import 'widgets/manage_folders_sheet.dart';
import 'widgets/search_sources_dialog.dart';
import 'widgets/shell_header.dart';
import 'widgets/add_source_menu.dart';
import 'widgets/site_picker_dialog.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  LcbPage _page = LcbPage.home;
  final _header = LcbPageHeader('首页');

  /// The store, captured here so the search mode can resolve which sites to fan
  /// out to. Assigned in didChangeDependencies, which also subscribes the shell
  /// to store changes -- that is what makes a newly added or deleted source
  /// reach the chip row without the search page knowing about sources at all.
  late AppStore _store;

  /// Owns the 搜索 mode: the field in the header and the results in the column.
  late final _search = LcbSearch(
    sitesProvider: (selection) => _store.sitesForSelection(selection),
    realSearchStream: (keyword, {strict = false}) =>
        _store.searchRealStream(keyword, strict: strict),
    canReachSource: () => _store.canSearchReal,
  );

  /// Non-null while the detail page is open in the content column.
  MediaItem? _detail;
  int? _detailEpisode;

  /// Non-null while the full-screen player is open on top of the shell.
  _PlayerSession? _player;

  static const _titles = {
    LcbPage.home: '首页',
    LcbPage.resources: '资源',
    LcbPage.favorites: '收藏',
    LcbPage.history: '历史',
    LcbPage.settings: '设置',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _store = StoreScope.of(context);
  }

  @override
  void dispose() {
    _header.dispose();
    _search.dispose();
    super.dispose();
  }

  void _select(LcbPage page) {
    setState(() {
      _page = page;
      _detail = null;
      _detailEpisode = null;
    });
    _search.close();
    _header.reset(_titles[page]!);
  }

  /// Enters 搜索 mode and puts the caret in the field.
  void _openSearch() {
    if (_search.isOpen) {
      _search.focus.requestFocus();
      return;
    }
    setState(() {
      _detail = null;
      _detailEpisode = null;
    });
    _search.open();
    _header.push('', () {}, showSearch: false);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _search.focus.requestFocus(),
    );
  }

  void _closeSearch() {
    if (!_search.isOpen) return;
    setState(() => _search.close());
    _header.reset(_titles[_page]!);
  }

  /// Pushes the detail page into the content column; the sidebar keeps its
  /// selection so the back arrow returns exactly where the user came from.
  void _openDetail(MediaItem item, {int? episodeIndex}) {
    final resolved = _store.detailOf(item);
    setState(() {
      _detail = resolved;
      _detailEpisode = episodeIndex;
    });
    _header.push(resolved.title, _closeDetail, showSearch: false);

    // Swap in the real record when the source has one; the row's own fields
    // render until then.
    _store.detailReal(item).then((full) {
      if (!mounted) return;
      if (full == null) return;
      if (_detail?.id != resolved.id) return; // user navigated away already
      setState(() => _detail = full);
    });
  }

  void _closeDetail() {
    if (!mounted) return;
    setState(() {
      _detail = null;
      _detailEpisode = null;
    });
    _header.reset(_titles[_page]!);
  }

  /// Resolves a playable URL for [item]'s chosen episode (on [lineIndex]) and
  /// opens the player, resuming from the saved position when there is one.
  ///
  /// Prefers the URLs the detail payload already carries ([MediaItem.playLines],
  /// the chosen line); falls back to the source's `play` action when they are
  /// absent (e.g. a row whose detail has not been fetched yet). Keeps
  /// the resolution async so the spider round-trip never blocks the tap.
  void _openPlayer(MediaItem item, int? episodeIndex, int lineIndex) {
    final lines = item.playLines;
    final line = (lineIndex >= 0 && lineIndex < lines.length)
        ? lines[lineIndex]
        : (lines.isNotEmpty ? lines.first : null);
    final eps = line?.episodes ?? const <PlayEpisode>[];

    String? url;
    if (eps.isNotEmpty) {
      final i = (episodeIndex ?? 0).clamp(0, eps.length - 1);
      url = eps[i].url;
    }

    if (url != null && url.isNotEmpty) {
      _showPlayer(item, episodeIndex, lineIndex, url);
      return;
    }

    // Fallback: ask the source's play action. 豆儿猫源 answers {parse:1} here
    // (its detail already carried the URLs), so this mainly serves other
    // source shapes.
    _store.playReal(item, flag: line?.name, nid: episodeIndex).then((resolved) {
      if (!mounted || resolved == null || resolved.isEmpty) return;
      if (_detail?.id != item.id) return; // user navigated away
      _showPlayer(item, episodeIndex, lineIndex, resolved);
    });
  }

  void _showPlayer(
    MediaItem item,
    int? episodeIndex,
    int lineIndex,
    String url,
  ) {
    // Resume from the saved position, but only when the requested episode is
    // the one the history row recorded (a fresh episode starts from zero).
    final resumeMs = episodeIndex == null
        ? null
        : _store.resumePositionFor(item, episodeIndex: episodeIndex);
    setState(() {
      _player = _PlayerSession(
        title: item.title,
        url: url,
        subtitle: StoreScope.of(context).siteNameOfKey(
          item.siteKey,
          fallback: item.sourceName ?? '',
        ),
        episodes: item.episodes,
        episodeIndex: episodeIndex,
        lineIndex: lineIndex,
        startAt: resumeMs == null ? null : Duration(milliseconds: resumeMs),
      );
    });
  }

  void _closePlayer() {
    if (!mounted) return;
    setState(() => _player = null);
  }

  /// Persists the final playback position when the player tears down. Only a
  /// position with a known duration is worth recording; a zero-length session
  /// (opened and closed instantly) is dropped rather than polluting history.
  void _recordProgress(
    _PlayerSession session, {
    required Duration position,
    required Duration duration,
  }) {
    final detail = _detail;
    if (detail == null) return;
    if (duration <= Duration.zero) return;

    final lines = detail.playLines;
    String lineName = '';
    if (session.lineIndex >= 0 && session.lineIndex < lines.length) {
      lineName = lines[session.lineIndex].name;
    }

    _store.recordPlayback(
      detail,
      episodeIndex: session.episodeIndex,
      positionMs: position.inMilliseconds,
      durationMs: duration.inMilliseconds,
      lineName: lineName,
    );
  }

  Widget _body() {
    final detail = _detail;
    if (detail != null) {
      return DetailPage(
        key: ValueKey('detail-${detail.id}'),
        item: detail,
        episodeIndex: _detailEpisode,
        onPlay: (i, line) => _openPlayer(detail, i, line),
      );
    }
    switch (_page) {
      case LcbPage.home:
        return const HomePage();
      case LcbPage.resources:
        return const ResourcesPage();
      case LcbPage.favorites:
        return const FavoritesPage();
      case LcbPage.history:
        return const HistoryPage();
      case LcbPage.settings:
        return const SettingsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Stack(
      children: [
        _buildScaffold(),
        if (player != null)
          PlayerPage(
            key: ValueKey('player-${player.url}'),
            title: player.title,
            subtitle: player.subtitle,
            url: player.url,
            episodes: player.episodes,
            episodeIndex: player.episodeIndex,
            startAt: player.startAt,
            onEpisode: (i) => _openPlayer(_detail!, i, player.lineIndex),
            onClose: _closePlayer,
            onProgress: (pos, dur) => _recordProgress(
              player,
              position: pos,
              duration: dur,
            ),
          ),
      ],
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      backgroundColor: LcbColors.surface,
      body: LcbSearchScope(
        search: _search,
        child: LcbDetailScope(
          open: _openDetail,
          child: LcbPageHeaderScope(
            controller: _header,
            child: CallbackShortcuts(
              bindings: {
                // The field advertises Ctrl+K, so it has to work from anywhere.
                const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                    _openSearch,
                const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
              },
              child: Focus(
                autofocus: true,
                child: Column(
                  children: [
                    ShellHeader(
                      content: _HeaderContent(
                        page: _page,
                        detail: _detail != null,
                        onOpenSearch: _openSearch,
                        onCloseSearch: _closeSearch,
                        onSelectPage: _select,
                      ),
                    ),
                    Expanded(
                      child: Row(
                        // Stretch, otherwise a page whose content is shorter
                        // than the viewport (the detail page) gets centred and
                        // floats down.
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Sidebar(current: _page, onSelect: _select),
                          Expanded(
                            child: Builder(
                              // Detail wins over search: tapping a result opens
                              // the detail page while the search stays open, so
                              // going back returns to the results.
                              builder: (ctx) => _detail != null
                                  ? _body()
                                  : (LcbSearchScope.of(ctx).isOpen
                                        ? const SearchPage()
                                        : _body()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The in-flight player session held by the shell while the full-screen player
/// is open. Carries everything [PlayerPage] needs; the shell owns it so the
/// detail page can keep the spider resolution out of its own render path.
class _PlayerSession {
  const _PlayerSession({
    required this.title,
    required this.url,
    required this.episodes,
    this.subtitle,
    this.episodeIndex,
    this.lineIndex = 0,
    this.startAt,
  });

  final String title;
  final String url;
  final String? subtitle;
  final List<String> episodes;
  final int? episodeIndex;

  /// The play line this URL came from; next/prev episode stays on it.
  final int lineIndex;

  /// Where to seek on open, for 续播.
  final Duration? startAt;
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, required this.onSelect});

  final LcbPage current;
  final ValueChanged<LcbPage> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: LcbMetrics.sidebarWidth,
      decoration: const BoxDecoration(
        color: LcbColors.page,
        border: Border(right: BorderSide(color: LcbColors.topBarBorder)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        children: [
          for (final (gi, group) in navGroups.indexed) ...[
            // Caption box is 18 high with the 11px copy centred, 8 of air below
            // it, and 18 above the next group. The first caption starts flush
            // with the header, so only later groups get the top gap.
            Padding(
              padding: EdgeInsets.fromLTRB(12, gi == 0 ? 0 : 18, 12, 8),
              child: SizedBox(
                height: 18,
                child: Align(
                  alignment: Alignment.centerLeft,
                  // The measured original sits one pixel above the optical
                  // centre of the caption box.
                  child: Transform.translate(
                    offset: const Offset(0, -1),
                    child: Text(
                      group.$1,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: LcbColors.sidebarLabel,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            for (final (ii, item) in group.$2.indexed)
              Padding(
                padding: EdgeInsets.only(
                  bottom: ii == group.$2.length - 1 ? 0 : 3,
                ),
                child: _NavItem(
                  icon: item.$1,
                  text: item.$2,
                  selected: item.$3 == current,
                  onTap: () => onSelect(item.$3),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bg = selected
        ? LcbColors.primaryContainer
        : (_hover ? LcbColors.hover : Colors.transparent);
    final fg = selected ? LcbColors.primaryDim : LcbColors.text;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: fg),
              const SizedBox(width: 12),
              Text(
                widget.text,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderContent extends StatelessWidget {
  const _HeaderContent({
    required this.page,
    this.detail = false,
    required this.onOpenSearch,
    required this.onCloseSearch,
    required this.onSelectPage,
  });

  final LcbPage page;

  /// True while the detail page is pushed: the bar collapses to a back arrow
  /// plus the title and drops the page controls and the search field.
  final bool detail;

  final VoidCallback onOpenSearch;
  final VoidCallback onCloseSearch;

  /// The home header's source chip jumps to 资源, the way the original's does.
  final ValueChanged<LcbPage> onSelectPage;

  @override
  Widget build(BuildContext context) {
    final header = LcbPageHeaderScope.of(context);
    final onBack = header.onBack;

    // Detail beats search: opening a detail from a search result shows the
    // back-arrow bar, not the search field.
    if (detail && onBack != null) {
      return Padding(
        padding: const EdgeInsets.only(left: 24),
        child: Row(
          children: [
            _BackButton(onTap: onBack, circle: 36, iconSize: 19),
            const SizedBox(width: 15),
            Text(
              header.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: LcbColors.text,
              ),
            ),
            const Expanded(child: HeaderDragGap()),
          ],
        ),
      );
    }

    // 搜索 mode owns the whole bar: an expanded field flush with the content
    // gutter, the 严格 toggle, the source picker and 取消. No title, no back.
    if (LcbSearchScope.of(context).isOpen) {
      return _SearchHeader(onClose: onCloseSearch);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 8, 0),
      // The whole strip sits 2px below the optical centre of the 60px header in
      // the original; YaHei UI centres it higher, so nudge the row down.
      child: Transform.translate(
        offset: const Offset(0, 2),
        child: Row(
          children: [
            if (onBack != null) ...[
              _BackButton(onTap: onBack),
              const SizedBox(width: 6),
            ],
            // Each page owns its own left-side header content.
            _buildHeaderLeft(context, page, header),
            const Expanded(child: HeaderDragGap()),
            if (header.showSearch) _SearchBox(onTap: onOpenSearch),
          ],
        ),
      ),
    );
  }

  /// Confirmation dialog before wiping the watch history, mirroring the
  /// original's guard on the destructive 清空 action.
  Future<void> _confirmClearHistory(BuildContext context) async {
    final store = StoreScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          '清空观看历史',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          '清空后将无法恢复，确定要删除全部观看记录吗？',
          style: TextStyle(fontSize: 13, color: LcbColors.settingsQuiet),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              '取消',
              style: TextStyle(color: LcbColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空', style: TextStyle(color: LcbColors.sysRed)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await store.clearHistory();
    }
  }

  Widget _buildHeaderLeft(
    BuildContext context,
    LcbPage page,
    LcbPageHeader header,
  ) {
    switch (page) {
      case LcbPage.home:
        return Row(
          children: [
            Text(
              header.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: LcbColors.text,
              ),
            ),
            const SizedBox(width: 16),
            _SourceChip(
              label: StoreScope.of(context).currentSource?.name ?? '未选择源',
              glyph: const _SourceGlyph(),
              onTap: () => onSelectPage(LcbPage.resources),
            ),
            const SizedBox(width: 8),
            _SourceChip(
              icon: CupertinoIcons.layers,
              iconSize: 15,
              // The site the cards and the detail page claim to come from --
              // real name from the config (`「直」荐片`), not a literal.
              label: StoreScope.of(context).homeSite?.name ?? '全部站点',
              labelGap: 5,
              onTap: () => showSitePicker(context),
            ),
            const SizedBox(width: 8),
            _IconGhost(icon: CupertinoIcons.square_grid_2x2, onTap: () {}),
          ],
        );
      case LcbPage.favorites:
        return const _FavoritesHeaderTabs();
      case LcbPage.history:
        return Row(
          children: [
            Text(
              header.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: LcbColors.text,
              ),
            ),
            const SizedBox(width: 27),
            TextButton(
              onPressed: () => _confirmClearHistory(context),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                '清空',
                style: TextStyle(fontSize: 15, color: LcbColors.primaryDim),
              ),
            ),
          ],
        );
      case LcbPage.resources:
        return Row(
          children: [
            Text(
              header.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: LcbColors.text,
              ),
            ),
            const SizedBox(width: 35),
            const _HeaderToolIcon(icon: CupertinoIcons.line_horizontal_3),
            const SizedBox(width: 11),
            const _HeaderToolIcon(icon: CupertinoIcons.search),
            const SizedBox(width: 11),
            _HeaderToolIcon(
              icon: CupertinoIcons.plus,
              onTap: () => showAddSourceMenu(context),
            ),
            const SizedBox(width: 11),
            const _HeaderToolIcon(icon: CupertinoIcons.checkmark_circle),
            const SizedBox(width: 11),
            const _HeaderToolIcon(icon: CupertinoIcons.waveform_path_ecg),
          ],
        );
      case LcbPage.settings:
        return Row(
          children: [
            Text(
              header.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: LcbColors.text,
              ),
            ),
            const SizedBox(width: 18),
            _HeaderGlyph(icon: CupertinoIcons.search, onTap: () {}),
          ],
        );
    }
  }
}

class _BackButton extends StatefulWidget {
  const _BackButton({required this.onTap, this.circle = 0, this.iconSize = 18});

  final VoidCallback onTap;

  /// Non-zero renders the detail page's filled circle instead of the bordered
  /// square tile the settings sub-pages use.
  final double circle;
  final double iconSize;

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isCircle = widget.circle > 0;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: isCircle ? widget.circle : 30,
          height: isCircle ? widget.circle : 30,
          decoration: BoxDecoration(
            color: isCircle
                ? (_hover ? const Color(0xFFE4E4E8) : LcbColors.searchFill)
                : (_hover ? LcbColors.hover : Colors.transparent),
            shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: isCircle ? null : BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.arrow_back,
            size: widget.iconSize,
            color: isCircle ? const Color(0xFF5A5A5D) : LcbColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// The mark on the first chip is a 10x7 pictogram that neither bundled icon font
/// carries: a hairline rounded frame holding two short bars. It is painted from
/// the measured pixels rather than approximated with a similar glyph.
class _SourceGlyph extends StatelessWidget {
  const _SourceGlyph();

  @override
  Widget build(BuildContext context) => const CustomPaint(
    size: Size(10, 7),
    painter: _SourceGlyphPainter(LcbColors.text),
  );
}

class _SourceGlyphPainter extends CustomPainter {
  const _SourceGlyphPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
        const Radius.circular(1.5),
      ),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final bar = Paint()..color = color;
    canvas.drawRect(const Rect.fromLTWH(3, 1, 4, 2), bar);
    canvas.drawRect(const Rect.fromLTWH(3, 4, 4, 2), bar);
  }

  @override
  bool shouldRepaint(_SourceGlyphPainter old) => old.color != color;
}

class _SourceChip extends StatefulWidget {
  const _SourceChip({
    required this.label,
    this.icon,
    this.iconSize = 16,
    this.glyph,
    this.labelGap = 8,
    this.onTap,
  });

  final IconData? icon;
  final String label;
  final double iconSize;

  /// Opens the source page (first chip) or the site picker (second chip).
  final VoidCallback? onTap;

  /// Replaces [icon] when the mark is not in any bundled icon font.
  final Widget? glyph;

  /// Air between the label and the chevron.
  final double labelGap;

  @override
  State<_SourceChip> createState() => _SourceChipState();
}

class _SourceChipState extends State<_SourceChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(left: 10, right: 9),
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFE8E8EC) : LcbColors.searchFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // Both chips reserve a 20 wide slot for their glyph so the labels
              // line up even though one mark is drawn much smaller than the other.
              SizedBox(
                width: 20,
                child: Center(
                  child:
                      widget.glyph ??
                      Icon(
                        widget.icon,
                        size: widget.iconSize,
                        color: LcbColors.text,
                      ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 12.5,
                  letterSpacing: -0.5,
                  color: LcbColors.text,
                ),
              ),
              SizedBox(width: widget.labelGap),
              const Icon(
                CupertinoIcons.chevron_compact_down,
                size: 12,
                color: LcbColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconGhost extends StatefulWidget {
  const _IconGhost({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_IconGhost> createState() => _IconGhostState();
}

class _IconGhostState extends State<_IconGhost> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFE8E8EC) : LcbColors.searchFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(widget.icon, size: 15, color: LcbColors.text),
        ),
      ),
    );
  }
}

/// A borderless header icon (the faded search glyph on non-home pages). The
/// original tints it with the muted primary (#9186C2), which is also what the
/// settings list uses for its 猫源 row.
class _HeaderGlyph extends StatefulWidget {
  const _HeaderGlyph({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_HeaderGlyph> createState() => _HeaderGlyphState();
}

class _HeaderGlyphState extends State<_HeaderGlyph> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFE8E8EC) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(widget.icon, size: 18, color: LcbColors.primaryDim),
        ),
      ),
    );
  }
}

/// Favorites' header tabs: plain text with no capsule, matching the original's
/// title-bar segmented control. The selected tab is dark + semibold, the other
/// is the settings-quiet grey. The active tab is kept in the store so the body
/// and the header stay in sync.
class _FavoritesHeaderTabs extends StatelessWidget {
  const _FavoritesHeaderTabs();

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final activeTab = store.favoritesTab;

    Widget tab(String label, int i) {
      final selected = i == activeTab;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => store.setFavoritesTab(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 18,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? LcbColors.text : LcbColors.settingsQuiet,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab('收藏', 0),
        const SizedBox(width: 19),
        tab('追剧', 1),
        const SizedBox(width: 36),
        const Icon(
          CupertinoIcons.search,
          size: 17,
          color: LcbColors.settingsQuiet,
        ),
        const SizedBox(width: 26),
        _HeaderIconButton(
          icon: CupertinoIcons.folder,
          onTap: () => showManageFoldersSheet(context),
        ),
        const SizedBox(width: 26),
        const Icon(
          CupertinoIcons.line_horizontal_3,
          size: 17,
          color: LcbColors.settingsQuiet,
        ),
      ],
    );
  }
}

/// A small square hoverable icon button used in the favourites header (folder
/// management). Mirrors the header tool icons' 32px rounded tile but without
/// the filled background so it sits flush with the plain text tabs.
class _HeaderIconButton extends StatefulWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: _hover ? LcbColors.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            widget.icon,
            size: 17,
            color: _hover ? LcbColors.text : LcbColors.settingsQuiet,
          ),
        ),
      ),
    );
  }
}

/// A square tool button used on the resources page header: a #F6F6F8 rounded
/// tile holding a dark glyph.
class _HeaderToolIcon extends StatelessWidget {
  const _HeaderToolIcon({required this.icon, this.onTap});

  final IconData icon;

  /// Null keeps the glyph decorative. The resource page wires `+` to the add
  /// dialog; the rest still have no behaviour behind them.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: LcbColors.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 17, color: LcbColors.text),
    );
    if (onTap == null) return box;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: box,
      ),
    );
  }
}

class _SearchBox extends StatefulWidget {
  const _SearchBox({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 232,
          height: 36,
          padding: const EdgeInsets.only(left: 12, right: 12),
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFE8E8EC) : LcbColors.searchFill,
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Row(
            children: [
              Icon(
                CupertinoIcons.search,
                size: 16,
                color: LcbColors.textSecondary,
              ),
              SizedBox(width: 8),
              Text(
                '搜索...',
                style: TextStyle(
                  fontSize: 12.5,
                  color: LcbColors.textSecondary,
                ),
              ),
              Spacer(),
              _KeyCap('Ctrl'),
              SizedBox(width: 4),
              _KeyCap('K'),
            ],
          ),
        ),
      ),
    );
  }
}

/// The header strip while 搜索 mode is open.
///
/// Measured at 1920x1040: the field runs 240..1625 (48 tall, 13px corners), 12px
/// to the 42x26 严格 pill, 21px to the 16px source glyph, then 取消 in the brand
/// violet ending at 1769.
class _SearchHeader extends StatelessWidget {
  const _SearchHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final search = LcbSearchScope.of(context);
    return Padding(
      // 16 = the content gutter; the trailing 8 matches the page headers.
      padding: const EdgeInsets.only(left: 16, right: 8, top: 2),
      child: Row(
        children: [
          Expanded(child: _SearchField(search: search)),
          const SizedBox(width: 12),
          _StrictPill(search: search),
          const SizedBox(width: 21),
          const _SourcePickerButton(),
          const SizedBox(width: 20),
          _CancelButton(onTap: onClose),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.search});

  final LcbSearch search;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        color: LcbColors.searchFill,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.search,
            size: 15,
            color: LcbColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: search.text,
              focusNode: search.focus,
              onChanged: search.setQuery,
              onSubmitted: (_) => search.submit(),
              cursorColor: LcbColors.primary,
              cursorWidth: 1.5,
              style: const TextStyle(
                fontSize: 15,
                height: 1.2,
                color: LcbColors.text,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '全网搜索影视',
                hintStyle: TextStyle(
                  fontSize: 15,
                  height: 1.2,
                  color: LcbColors.textSecondary,
                ),
              ),
            ),
          ),
          if (search.query.isNotEmpty)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: search.clearQuery,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: const BoxDecoration(
                    color: Color(0xFFBFBFC2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    CupertinoIcons.xmark,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The 严格 toggle: grey when off, brand violet with white text when on, which
/// turns the query from a contains-match into an exact-title match.
class _StrictPill extends StatelessWidget {
  const _StrictPill({required this.search});

  final LcbSearch search;

  @override
  Widget build(BuildContext context) {
    final on = search.strict;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: search.toggleStrict,
        child: Container(
          width: 42,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? LcbColors.primaryDim : LcbColors.searchFill,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(
            '严格',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.0,
              color: on ? Colors.white : LcbColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// 搜索哪些资源 -- the same picker the bottom-right corner button opens.
class _SourcePickerButton extends StatelessWidget {
  const _SourcePickerButton();

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => showSearchSourcesSheet(context),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(
            CupertinoIcons.square_grid_2x2,
            size: 16,
            color: LcbColors.text,
          ),
        ),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '取消',
            style: TextStyle(
              fontSize: 15,
              height: 1.0,
              color: LcbColors.primaryDim,
            ),
          ),
        ),
      ),
    );
  }
}

/// The little `Ctrl` / `K` keycaps inside the search field.
class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFDEDEE1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          height: 1,
          color: LcbColors.textSecondary,
        ),
      ),
    );
  }
}
