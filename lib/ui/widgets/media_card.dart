import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import 'poster_art.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.onMore,
    this.moreLabel = '查看全部',
  });

  final String title;
  final VoidCallback? onMore;
  final String moreLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Measured ink height 18-19px for both 继续观看 and 电影, and the 电影
        // run is 35x18 — a 18px bold 微软雅黑 exactly, not the serif the hero
        // headline uses.
        Text(
          title,
          style: const TextStyle(
            fontFamily: LcbText.body,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: LcbColors.text,
            height: 1.15,
          ),
        ),
        const Spacer(),
        if (onMore != null) _MoreButton(label: moreLabel, onTap: onMore!),
      ],
    );
  }
}

class _MoreButton extends StatefulWidget {
  const _MoreButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_MoreButton> createState() => _MoreButtonState();
}

class _MoreButtonState extends State<_MoreButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 12.5,
                color: _hover ? LcbColors.primary : LcbColors.textSecondary,
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              CupertinoIcons.chevron_forward,
              size: 15,
              color: _hover ? LcbColors.primary : LcbColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 16:9 still used by "continue watching" rows.
///
/// Width is adaptive: the original resolves to
/// `min(contentWidth / 3.5, 360)`, giving 360 at 1680 and 331 at 1160.
class LandscapeCard extends StatefulWidget {
  const LandscapeCard({
    super.key,
    required this.item,
    required this.episodeLabel,
    required this.positionLabel,
    required this.width,
    this.progress = 0,
    this.onTap,
  });

  final MediaItem item;
  final String episodeLabel;
  final String positionLabel;
  final double width;
  final double progress;
  final VoidCallback? onTap;

  static double widthFor(double contentWidth) {
    return math.min(contentWidth / 3.5, 360);
  }

  @override
  State<LandscapeCard> createState() => _LandscapeCardState();
}

class _LandscapeCardState extends State<LandscapeCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final h = widget.width * 9 / 16;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: h,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(LcbMetrics.cardRadius),
                  boxShadow: _hover
                      ? const [
                          BoxShadow(
                            color: Color(0x26000000),
                            blurRadius: 18,
                            offset: Offset(0, 8),
                          ),
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedScale(
                      duration: const Duration(milliseconds: 220),
                      scale: _hover ? 1.04 : 1.0,
                      child: PosterArt(
                        seed: widget.item.posterSeed,
                        image: widget.item.image,
                        // The 2:3 art covers a 16:9 slot, so 337px of height is
                        // cropped. The original anchors the crop 93px down from
                        // the top (a template match lands at that offset), not at
                        // the centre: Alignment.y = 2 * 93 / 337 - 1.
                        alignment: const Alignment(0, -0.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.43,
                  fontWeight: FontWeight.w500,
                  color: LcbColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${widget.episodeLabel} · 看到 ${widget.positionLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.33,
                  color: LcbColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 2:3 vertical poster used by library rows. Fixed 196x294 with an 18 gutter,
/// which is why eight cards overflow a 1680 content column.
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.item,
    this.width = LcbMetrics.posterWidth,
    this.onTap,
  });

  final MediaItem item;
  final double width;
  final VoidCallback? onTap;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final h = widget.width * 3 / 2;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: h,
                transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: _hover
                      ? const [
                          BoxShadow(
                            color: Color(0x33000000),
                            blurRadius: 20,
                            offset: Offset(0, 10),
                          ),
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: PosterArt(
                  seed: widget.item.posterSeed,
                  image: widget.item.image,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                widget.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.43,
                  fontWeight: FontWeight.w500,
                  color: LcbColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
