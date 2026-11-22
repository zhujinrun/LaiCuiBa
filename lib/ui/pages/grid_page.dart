import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/detail_nav.dart';
import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../widgets/media_card.dart';

/// One category, as a paged poster grid.
///
/// The original's 「查看全部」 on a home rail opens this, and so does the ⊞
/// browse panel with its picks as [filters]. The rail is a sample of page one,
/// and this is where the rest of the category lives. Paging stops at the page
/// count the source reports -- scrolling into a void and firing requests
/// forever is not paging.
class GridPage extends StatefulWidget {
  const GridPage({
    super.key,
    required this.title,
    required this.typeId,
    this.filters = const {},
  });

  /// The rail's title, which is also the category's display name.
  final String title;

  /// The site's category id behind that rail.
  final String typeId;

  /// The browse panel's narrowing picks (`class` / `area` / `year` / `by`).
  final Map<String, String> filters;

  @override
  State<GridPage> createState() => _GridPageState();
}

class _GridPageState extends State<GridPage> {
  final _scroll = ScrollController();

  final List<MediaItem> _items = [];
  final Set<String> _seen = {};

  /// Pages fetched so far, and how many the source said there are.
  int _page = 0;
  int _pageCount = 1;

  bool _loading = false;
  bool _failed = false;
  String? _error;

  /// The first fetch needs the store, so it waits for dependencies instead of
  /// running in [initState] where an inherited lookup is not allowed.
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _loadNext();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Fetches one more page. Safe to call while a page is in flight (it no-ops),
  /// and after the last page (it no-ops too).
  Future<void> _loadNext() async {
    if (_loading) return;
    if (_page > 0 && _page >= _pageCount) return;
    setState(() {
      _loading = true;
      _failed = false;
    });

    final store = StoreScope.of(context);
    final next = _page + 1;
    final page = await store.categoryPageReal(
      widget.typeId,
      page: next,
      filters: widget.filters,
    );
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (!page.ok) {
        // The first page failing is the page; a later page failing is a note
        // under what already loaded, so the reader keeps what they had.
        _failed = _page == 0;
        _error = page.error;
        return;
      }
      _page = page.page > 0 ? page.page : next;
      _pageCount = math.max(page.pageCount, _page);
      for (final item in page.items) {
        final key = item.id.isNotEmpty ? item.id : item.title;
        if (_seen.add(key)) _items.add(item);
      }
      // A source that says "1 of 1" but keeps handing out titles is common;
      // believing its count is what stops the endless fetch.
      if (page.items.isEmpty) _pageCount = _page;
    });
    _fillViewport();
  }

  /// A short first page never scrolls, so nothing would ask for page two.
  /// Asking here keeps paging working on a category with three titles.
  void _fillViewport() {
    if (_page >= _pageCount) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loading) return;
      if (!_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent > 0) return;
      _loadNext();
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.extentAfter > 720) return;
    _loadNext();
  }

  void _retry() {
    setState(() {
      _failed = false;
      _error = null;
    });
    _loadNext();
  }

  @override
  Widget build(BuildContext context) {
    // Reading the store here subscribes to it, so changing the site reloads
    // this page's header wording; the pages themselves come from the same
    // `homeSite` the rail came from.
    StoreScope.of(context);

    if (_items.isEmpty) {
      if (_failed) {
        return _Centred(
          title: '加载失败',
          subtitle: _error ?? '${widget.title} 没有答上来',
          onRetry: _retry,
        );
      }
      if (_loading) {
        return const Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: LcbColors.primary,
            ),
          ),
        );
      }
      return _Centred(
        // 「没有取到」而不是「没有」：源可能真的空，也可能是这一页没答上来，
        // 这一层分不清就不替它下结论。
        title: '${widget.title}下没有取到片单',
        subtitle: _error ?? '过一会儿再来看看，或者在首页换一个站点。',
        onRetry: _retry,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Measured off the original's category page: 9 covers across a 1920
        // window, each 175 wide with an 11 gutter and a 16 content inset. The
        // home rails breathe at 40/18, but this page packs them tighter so the
        // grid reads as a library rather than a shelf.
        const pad = 16.0;
        const gap = 11.0;
        const target = 175.0;
        final available = constraints.maxWidth - pad * 2;
        // Round, not floor: the sidebar plus the hairline leaves the content
        // column one pixel short of 9 x (175 + 11), and flooring there silently
        // drops a whole column. Rounding keeps the measured 9 across while
        // still giving up a column as the window narrows.
        final columns = math.max(
          2,
          ((available + gap) / (target + gap)).round(),
        );
        final width = (available - gap * (columns - 1)) / columns;

        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(pad, 0, pad, 12),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: gap,
                    // The original's rows sit 333px apart at this size: a
                    // 262.5 cover, a 30 caption block and 40 of air.
                    mainAxisSpacing: 40,
                    // Poster is 3:2 tall plus its caption.
                    childAspectRatio: width / (width * 3 / 2 + 30),
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => PosterCard(
                      item: _items[i],
                      width: width,
                      onTap: () =>
                          LcbDetailScope.openOf(context, _items[i]),
                    ),
                    childCount: _items.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 72,
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: LcbColors.primary,
                            ),
                          )
                        : (!_failed && _page >= _pageCount && _pageCount > 1
                              ? Text(
                                  '共 ${_items.length} 部',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: LcbColors.textTertiary,
                                  ),
                                )
                              : null),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// First-page states: nothing loaded, so the page says why instead of showing
/// an empty grid that reads like the category is empty.
class _Centred extends StatelessWidget {
  const _Centred({
    required this.title,
    required this.subtitle,
    required this.onRetry,
  });

  final String title;
  final String subtitle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, color: LcbColors.textSecondary),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 420,
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: LcbColors.textSecondary.withValues(alpha: 0.75),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
