import 'dart:math' as math;

import 'package:flutter/material.dart';

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
        // Measured ink height 18px for both 继续观看 and 电影.
        Text(title, style: serifStyle(20, height: 1.15)),
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
            Icon(
              Icons.chevron_right,
              size: 16,
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
                              offset: Offset(0, 8))
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
                      child: PosterArt(seed: widget.item.posterSeed),
                    ),
                    const Positioned(
                      left: 12,
                      bottom: 12,
                      child: _PlayGlyph(),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 3,
                        color: Colors.white.withValues(alpha: 0.28),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: widget.progress.clamp(0.0, 1.0),
                          child: const ColoredBox(color: LcbColors.primary),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    height: 1.43,
                    fontWeight: FontWeight.w500,
                    color: LcbColors.text),
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.episodeLabel} · 看到 ${widget.positionLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12,
                    height: 1.33,
                    color: LcbColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayGlyph extends StatelessWidget {
  const _PlayGlyph();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.play_arrow_rounded, size: 19, color: Colors.white),
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
                              offset: Offset(0, 10))
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterArt(seed: widget.item.posterSeed),
                    // Both chips sit together in the top-left corner.
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.item.score != null) ...[
                            _ScoreChip(score: widget.item.score!),
                            if (widget.item.tag != null)
                              const SizedBox(width: 4),
                          ],
                          if (widget.item.tag != null)
                            _TagChip(label: widget.item.tag!),
                        ],
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
                    color: LcbColors.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: LcbColors.scoreGreen,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        score.toStringAsFixed(1),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.15,
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.white,
          height: 1.15,
        ),
      ),
    );
  }
}
