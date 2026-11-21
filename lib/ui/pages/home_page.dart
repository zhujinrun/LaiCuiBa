import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/detail_nav.dart';
import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/source_catalogue.dart';
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
  /// The source the rails were requested from. Null while no source answers the
  /// home screen itself -- the state every source type that cannot run in the
  /// host leaves, and the state the bundled catalogue is drawn in.
  String? _askedId;

  /// True when the answer comes from a mount rather than a 猫源. A mount is an
  /// explicit user action, so its rails replace the catalogue immediately (with
  /// a placeholder while they load); a 猫源 answers in the background while the
  /// catalogue stays readable.
  bool _mount = false;

  /// The rails the source answered with, or null before it has answered. An
  /// empty list is a real answer ("the source has nothing right now"), which is
  /// why it cannot be conflated with "not answered yet".
  List<HomeSection>? _sections;

  /// Why the rails are empty, when the source said something specific.
  String? _feedError;

  bool _failed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncFeed(StoreScope.of(context));
  }

  /// Swaps the rails over when the active source starts (or stops) answering
  /// the home screen itself. The store notifies on selection and source edits,
  /// so this runs on every change that could matter.
  void _syncFeed(AppStore store) {
    final answers = store.hasMount || store.hasSpiderHome;
    final id = answers ? store.currentSource?.id : null;
    if (id == _askedId) return;
    setState(() {
      _askedId = id;
      _sections = null;
      _feedError = null;
      _failed = false;
      _mount = id != null && store.hasMount;
    });
    if (id != null) _loadFeed(store, id);
  }

  Future<void> _loadFeed(AppStore store, String id) async {
    if (store.hasMount) {
      final items = await store.mountLibrary(limit: 30);
      if (!mounted || _askedId != id) return;
      setState(() {
        _sections = items.isEmpty
            ? const <HomeSection>[]
            : [HomeSection(title: '影片库', items: items)];
      });
      return;
    }

    final feed = await store.spiderCatalogue();
    if (!mounted || _askedId != id) return;
    setState(() {
      if (feed == null || !feed.ok) {
        // A source that could not answer keeps the catalogue. Dropping the
        // front page to an error screen is how a transient network hiccup would
        // turn into "the app is broken"; 检测 is where a dead source is named.
        _failed = true;
        return;
      }
      _sections = feed.sections;
      _feedError = feed.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final continueWatching = store.continueWatching;
    final answered = _sections;
    // A mount says nothing but its own library: showing the bundled fixtures
    // while "客厅 Emby" is the active source would pass demo titles off as the
    // user's own. A 猫源 gets the same treatment once it answers, and keeps the
    // catalogue until then (or forever, if it never answers).
    final real = _askedId != null && (_mount || answered != null);
    final sections = real
        ? (answered ?? const <HomeSection>[])
        : store.homeSections;
    final hero = real
        ? (answered == null
              ? const <MediaItem>[]
              : CatalogueFeed.heroOf(answered))
        : store.heroItems;
    final loadingMount = _mount && answered == null && !_failed;

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (loadingMount)
              const _HeroPlaceholder()
            else if (hero.isNotEmpty)
              HeroBanner(items: hero),
            if (real && answered != null && answered.isEmpty)
              _EmptyCatalogue(spider: !_mount, reason: _feedError),
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

/// The hero's footprint while a source's first page is in flight, so the rails
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

/// Shown when the active source answered but had nothing to put on the home
/// screen. Says whose source it is and what to try next, because "nothing here"
/// on the front page otherwise reads like a bug.
class _EmptyCatalogue extends StatelessWidget {
  const _EmptyCatalogue({required this.spider, this.reason});

  final bool spider;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final source = StoreScope.of(context).currentSource;
    final name = source?.name ?? (spider ? '这个源' : '这个服务器');
    final head = spider ? '$name 的首页没有取到片单' : '$name 的影片库里还没有内容';
    final detail = spider
        ? (reason ?? '站点今天可能没有更新')
        : '在服务器上添加电影或剧集后，重新选择一次这个源即可刷新';
    final hint = spider ? '在资源页点「重新检测」可以确认它还能不能用' : null;

    return SizedBox(
      height: 260,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              head,
              style: const TextStyle(
                fontSize: 15,
                color: LcbColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: LcbColors.textSecondary.withValues(alpha: 0.75),
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 13,
                  color: LcbColors.textSecondary.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
