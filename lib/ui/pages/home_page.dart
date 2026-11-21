import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/detail_nav.dart';
import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/store.dart';
import '../widgets/hero_banner.dart';
import '../widgets/media_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  /// Poster rails shrink with the window: 196 wide at 1680 content, 161 at
  /// 1168. Fitted as `min(contentWidth / 7.25, 196)`, capped so a maximised
  /// window does not blow the covers up.
  static double posterWidthFor(double contentWidth) {
    return math.min(contentWidth / 7.25, LcbMetrics.posterWidth);
  }

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Which mount the rails below belong to. Null while the bundled catalogue is
  /// on screen -- the state every source type except a logged-in mount leaves.
  String? _mountId;

  /// The mount's titles, or null while the first page is still loading. An
  /// empty list is a real answer ("the library has nothing"), which is why it
  /// cannot be conflated with "not loaded yet".
  List<MediaItem>? _mountItems;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMount(StoreScope.of(context));
  }

  /// Swaps the rails over when the active source becomes a logged-in mount, and
  /// back when it stops being one. The store notifies on selection and source
  /// edits, so this runs on every change that could matter.
  void _syncMount(AppStore store) {
    if (!store.hasMount) {
      if (_mountId == null) return;
      setState(() {
        _mountId = null;
        _mountItems = null;
      });
      return;
    }
    final id = store.currentSource?.id;
    if (id == null || id == _mountId) return;
    setState(() {
      _mountId = id;
      _mountItems = null;
    });
    _loadMount(store, id);
  }

  Future<void> _loadMount(AppStore store, String id) async {
    final items = await store.mountLibrary(limit: 30);
    if (!mounted || _mountId != id) return;
    setState(() => _mountItems = items);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final continueWatching = store.continueWatching;
    // A mount answers for itself or not at all: showing the bundled fixtures
    // while "客厅 Emby" is the active source would pass demo titles off as the
    // user's own library. Non-mount sources keep the catalogue for now.
    final mount = _mountId != null;
    final items = _mountItems;
    final sections = mount
        ? (items == null
              ? const <HomeSection>[]
              : [HomeSection(title: '影片库', items: items)])
        : store.homeSections;
    final hero = mount
        ? (items == null ? const <MediaItem>[] : items.take(5).toList())
        : store.heroItems;

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mount && items == null)
              const _HeroPlaceholder()
            else if (hero.isNotEmpty)
              HeroBanner(items: hero),
            if (mount && items != null && items.isEmpty) const _EmptyLibrary(),
            LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = constraints.maxWidth;
                final landscapeWidth = LandscapeCard.widthFor(contentWidth);
                final landscapeHeight = landscapeWidth * 9 / 16;
                final posterWidth = HomePage.posterWidthFor(contentWidth);

                // The rails bleed all the way to the window edge: only the
                // section headers sit inside the 40px page gutter, the lists
                // carry that gutter as their own leading padding so the last
                // cover stays visible under the right edge.
                return Padding(
                  padding: const EdgeInsets.only(top: 17, bottom: 44),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 继续观看 only renders when there is watch history;
                      // the original hides the whole rail when it is empty.
                      if (continueWatching.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: LcbMetrics.pagePadding,
                          ),
                          child: SectionHeader(title: '继续观看', onMore: () {}),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: landscapeHeight + 9 + 20 + 4 + 16,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(
                              left: LcbMetrics.pagePadding,
                            ),
                            itemCount: continueWatching.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 18),
                            itemBuilder: (_, i) {
                              final c = continueWatching[i];
                              return LandscapeCard(
                                item: c.media,
                                episodeLabel: c.episodeLabel,
                                positionLabel: c.positionLabel,
                                progress: c.progress,
                                width: landscapeWidth,
                                onTap: () =>
                                    LcbDetailScope.openOf(context, c.media),
                              );
                            },
                          ),
                        ),
                      ],
                      for (final section in sections) ...[
                        const SizedBox(height: 35),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: LcbMetrics.pagePadding,
                          ),
                          child: SectionHeader(
                            title: section.title,
                            onMore: () {},
                          ),
                        ),
                        const SizedBox(height: 17),
                        SizedBox(
                          height: posterWidth * 1.5 + 10 + 20,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(
                              left: LcbMetrics.pagePadding,
                            ),
                            itemCount: section.items.length,
                            separatorBuilder: (_, __) => const SizedBox(
                                width: LcbMetrics.posterGap),
                            itemBuilder: (_, i) => PosterCard(
                              item: section.items[i],
                              width: posterWidth,
                              onTap: () => LcbDetailScope.openOf(
                                context,
                                section.items[i],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The hero's footprint while a mount's first page is in flight, so the rails
/// below do not jump up and then get pushed back down.
class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min(
          constraints.maxWidth * 0.37,
          MediaQuery.sizeOf(context).height * 0.54,
        );
        return Container(
          height: height,
          alignment: Alignment.center,
          child: const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: LcbColors.primary,
            ),
          ),
        );
      },
    );
  }
}

/// Shown when the mount answered with an empty library. Says whose library it
/// is, because "nothing here" on the home page otherwise reads like a bug.
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final name = StoreScope.of(context).currentSource?.name ?? '这个服务器';
    return SizedBox(
      height: 260,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$name 的影片库里还没有内容',
              style: const TextStyle(
                fontSize: 15,
                color: LcbColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '在服务器上添加电影或剧集后，重新选择一次这个源即可刷新',
              style: TextStyle(
                fontSize: 13,
                color: LcbColors.textSecondary.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
