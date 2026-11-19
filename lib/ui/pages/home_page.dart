import 'dart:math' as math;

import 'package:flutter/material.dart';

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

                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    LcbMetrics.pagePadding,
                    16,
                    LcbMetrics.pagePadding,
                    44,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionHeader(title: '继续观看', onMore: () {}),
                      const SizedBox(height: 15),
                      SizedBox(
                        height: landscapeHeight + 9 + 20 + 4 + 16,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
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
                              onTap: () {},
                            );
                          },
                        ),
                      ),
                      for (final section in homeSections) ...[
                        const SizedBox(height: 33),
                        SectionHeader(title: section.title, onMore: () {}),
                        const SizedBox(height: 15),
                        SizedBox(
                          height: posterWidth * 1.5 + 10 + 20,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: section.items.length,
                            separatorBuilder: (_, __) => const SizedBox(
                                width: LcbMetrics.posterGap),
                            itemBuilder: (_, i) => PosterCard(
                              item: section.items[i],
                              width: posterWidth,
                              onTap: () {},
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

