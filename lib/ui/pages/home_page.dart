import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
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
  /// home screen itself -- every source type that cannot run in the host leaves
  /// the page in that state, and it is shown as such rather than papered over.
  String? _askedId;

  /// True when the answer comes from a mount rather than a 猫源. Only used to
  /// word the empty and error states ("影片库" vs "首页片单"), since both types
  /// now own the page outright while they load.
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
    final answers = store.hasMount || store.hasSpiderHome || store.hasPyHome;
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

    // Either real runtime can answer the front page; which one is the source's
    // business, not the page's. Both return null when the source is not theirs.
    final feed = store.hasPyHome
        ? await store.pyCatalogue()
        : await store.spiderCatalogue();
    if (!mounted || _askedId != id) return;
    setState(() {
      if (feed == null || !feed.ok) {
        // Say it failed. Keeping fixtures on screen here was the old behaviour,
        // and it made a dead source look exactly like a working one -- the whole
        // reason the fixtures are off.
        _failed = true;
        _feedError = feed?.error ?? '源没有返回片单';
        return;
      }
      _sections = feed.sections;
      _feedError = feed.error;
    });
  }

  /// The active source's name, for the notices that name who did not answer.
  String _sourceNameOf(AppStore store) =>
      store.currentSource?.name ?? '当前来源';

  /// Re-asks the active source for its rails, after a failure.
  void _retry(AppStore store) {
    final id = _askedId;
    if (id == null) return;
    setState(() {
      _failed = false;
      _feedError = null;
      _sections = null;
    });
    _loadFeed(store, id);
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final continueWatching = store.continueWatching;
    final answered = _sections;
    // Every row here is an answer from the active source. While it is being
    // fetched the page holds its shape with a spinner and says nothing else;
    // when it fails or comes back empty the page says that too. There is no
    // fixture fallback, so nothing on this screen can be mistaken for content
    // the source does not actually have.
    final asked = _askedId != null;
    final sections = answered ?? const <HomeSection>[];
    final hero = answered == null
        ? const <MediaItem>[]
        : CatalogueFeed.heroOf(answered);
    final loading = asked && answered == null && !_failed;

    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (loading)
              const _HeroPlaceholder()
            else if (hero.isNotEmpty)
              HeroBanner(items: hero),
            if (!asked)
              const _HomeNotice(
                icon: CupertinoIcons.tray,
                title: '还没有可用的来源',
                subtitle: '在「资源」里添加一个猫源，它的首页片单会显示在这里。',
              )
            else if (_failed)
              _HomeNotice(
                icon: CupertinoIcons.exclamationmark_triangle,
                title: '${_sourceNameOf(store)} 没有答上来',
                subtitle: _feedError ?? '宿主请求超时，可能站点暂时不可用。',
                hint: '可以重试一次，或在「资源」里点「重新检测」确认它还能不能用。',
                onRetry: () => _retry(store),
              )
            else if (answered != null && answered.isEmpty)
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

/// What the home screen says when the source cannot fill it: no source at all,
/// or one that failed to answer. Both are stated plainly -- an empty page with
/// no explanation reads as a broken app, and fixtures read as working content.
class _HomeNotice extends StatelessWidget {
  const _HomeNotice({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.hint,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? hint;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 30,
              color: LcbColors.textSecondary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                color: LcbColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: LcbColors.textSecondary.withValues(alpha: 0.75),
              ),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: LcbColors.textSecondary.withValues(alpha: 0.6),
                ),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              TextButton(
                onPressed: onRetry,
                child: const Text('重试'),
              ),
            ],
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
