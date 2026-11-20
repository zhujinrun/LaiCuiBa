import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/detail_nav.dart';
import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../services/demo_data.dart';
import '../widgets/hero_banner.dart';
import '../widgets/media_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  /// Poster rails shrink with the window: 196 wide at 1680 content, 161 at
  /// 1168. Fitted as `min(contentWidth / 7.25, 196)`, capped so a maximised
  /// window does not blow the covers up.
  static double posterWidthFor(double contentWidth) {
    return math.min(contentWidth / 7.25, LcbMetrics.posterWidth);
  }

  @override
  Widget build(BuildContext context) {
    final continueWatching = StoreScope.of(context).continueWatching;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HeroBanner(items: heroItems),
            LayoutBuilder(
              builder: (context, constraints) {
                final contentWidth = constraints.maxWidth;
                final landscapeWidth = LandscapeCard.widthFor(contentWidth);
                final landscapeHeight = landscapeWidth * 9 / 16;
                final posterWidth = posterWidthFor(contentWidth);

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
                      for (final section in homeSections) ...[
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

