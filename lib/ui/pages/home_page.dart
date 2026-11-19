import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/demo_data.dart';
import '../widgets/hero_banner.dart';
import '../widgets/media_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HeroBanner(items: heroItems),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                LcbMetrics.pagePadding,
                4,
                LcbMetrics.pagePadding,
                44,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(title: '继续观看', onMore: () {}),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 320 * 9 / 16 + 48,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: continueWatching.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 16),
                      itemBuilder: (_, i) {
                        final c = continueWatching[i];
                        return LandscapeCard(
                          item: c.media,
                          episodeLabel: c.episodeLabel,
                          positionLabel: c.positionLabel,
                          progress: c.progress,
                          onTap: () {},
                        );
                      },
                    ),
                  ),
                  for (final section in homeSections) ...[
                    const SizedBox(height: 32),
                    SectionHeader(title: section.title, onMore: () {}),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 112 * 1.5 + 30,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: section.items.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => PosterCard(item: section.items[i], onTap: () {}),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
