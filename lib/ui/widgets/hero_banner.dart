import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/models.dart';
import 'poster_art.dart';

/// Full-bleed hero carousel.
///
/// Height is adaptive, not fixed: the original resolves to
/// `min(contentWidth * 0.37, windowHeight * 0.54)`, which is 561px at
/// 1920x1040 and 430px at 1400x900. A fixed height makes the whole page read
/// wrong once the window is maximised.
class HeroBanner extends StatefulWidget {
  const HeroBanner({super.key, required this.items});

  final List<MediaItem> items;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
  }

  void _startAutoPlay() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.items.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _goTo(int i) {
    setState(() => _index = i);
    _startAutoPlay();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.items[_index];

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = _heroHeight(constraints.maxWidth, context);

        return SizedBox(
          height: height,
          width: double.infinity,
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0xFF14131A),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 700),
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [...previous, if (current != null) current],
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(item.id),
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                          child: Transform.scale(
                            scale: 1.6,
                            child: PosterArt(seed: item.posterSeed),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Directional scrim: keeps the headline legible over any artwork.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xE60A0A0E),
                        Color(0xA60A0A0E),
                        Color(0x140A0A0E)
                      ],
                      stops: [0.0, 0.46, 0.86],
                    ),
                  ),
                ),
                // Melt into the white page at the bottom edge.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x00FFFFFF),
                        Color(0x00FFFFFF),
                        Color(0x80FFFFFF),
                        Color(0xFFFFFFFF)
                      ],
                      stops: [0.0, 0.56, 0.82, 1.0],
                    ),
                  ),
                ),
                Positioned(
                  top: 18,
                  right: 76,
                  height: height * 0.827,
                  child: _HeroPoster(item: item, height: height * 0.827),
                ),
                Positioned(
                  left: 42,
                  top: 0,
                  bottom: 0,
                  right: 420,
                  child: Center(child: _HeroCopy(item: item)),
                ),
                Positioned(
                  left: 42,
                  right: 42,
                  bottom: 25,
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < widget.items.length; i++)
                          _Dot(active: i == _index, onTap: () => _goTo(i)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _heroHeight(double contentWidth, BuildContext context) {
    final byWidth = contentWidth * LcbMetrics.heroWidthFactor;
    final byHeight =
        MediaQuery.sizeOf(context).height * LcbMetrics.heroHeightFactor;
    return byWidth < byHeight ? byWidth : byHeight;
  }
}

class _HeroPoster extends StatelessWidget {
  const _HeroPoster({required this.item, required this.height});

  final MediaItem item;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Measured at 1920x1040: 327x460, i.e. 0.583 x 0.82 of the hero height.
      width: height * 0.71,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
              color: Color(0x59000000), blurRadius: 34, offset: Offset(0, 14)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: PosterArt(
        seed: item.posterSeed,
        title: item.title,
        showTitle: true,
        titleSize: 22,
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: serifStyle(44, height: 1.1).copyWith(
            color: Colors.white,
            shadows: const [
              Shadow(
                  color: Color(0x4D000000),
                  blurRadius: 18,
                  offset: Offset(0, 3))
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            if (item.score != null) _ScoreBadge(score: item.score!),
            if (item.score != null && item.tag != null)
              const SizedBox(width: 8),
            if (item.tag != null) _MetaTag(label: item.tag!),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            _PillButton(
              icon: Icons.play_arrow_rounded,
              label: '播放',
              filled: true,
              onTap: () {},
            ),
            const SizedBox(width: 12),
            _PillButton(
              icon: Icons.info_outline_rounded,
              label: '详情',
              filled: false,
              onTap: () {},
            ),
          ],
        ),
      ],
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  const _ScoreBadge({required this.score});

  final double score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: LcbColors.scoreGreen,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        score.toStringAsFixed(1),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.2,
        ),
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  const _MetaTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: LcbColors.text,
          height: 1.2,
        ),
      ),
    );
  }
}

class _PillButton extends StatefulWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final filled = widget.filled;
    final bg = filled
        ? (_hover ? const Color(0xFF6C58E8) : LcbColors.primary)
        : (_hover ? Colors.white : Colors.white.withValues(alpha: 0.88));
    final fg = filled ? Colors.white : LcbColors.text;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(9),
            boxShadow: filled
                ? const [
                    BoxShadow(
                        color: Color(0x4D6C58E8),
                        blurRadius: 16,
                        offset: Offset(0, 6))
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 20, color: fg),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: active ? LcbColors.primary : const Color(0xFFA2A2AC),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}
