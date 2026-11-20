import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Deterministic stand-in artwork so layout can be judged without real posters.
/// Real covers will replace this via `coverUrl` once the source layer lands.
class PosterPalette {
  const PosterPalette(this.top, this.bottom, this.accent);

  final Color top;
  final Color bottom;
  final Color accent;

  static const List<PosterPalette> all = [
    PosterPalette(Color(0xFF3E6E68), Color(0xFF16211F), Color(0xFFD94F45)),
    PosterPalette(Color(0xFF8E1B1B), Color(0xFF131A2B), Color(0xFFE2C044)),
    PosterPalette(Color(0xFFC8762A), Color(0xFF2A1810), Color(0xFFF3D9A4)),
    PosterPalette(Color(0xFFE0B325), Color(0xFF161514), Color(0xFFFFF0C2)),
    PosterPalette(Color(0xFF7A2130), Color(0xFF1B0D12), Color(0xFFE8C07A)),
    PosterPalette(Color(0xFF2C4A7C), Color(0xFF0F1621), Color(0xFF7FB2E5)),
    PosterPalette(Color(0xFF55407A), Color(0xFF14101C), Color(0xFFC9A6F0)),
    PosterPalette(Color(0xFF2B6B4F), Color(0xFF0E1A15), Color(0xFF9AD9B4)),
  ];

  static PosterPalette of(int seed) => all[seed.abs() % all.length];
}

/// Cover artwork for one title.
///
/// When [image] is set the bundled poster the original caches locally is drawn
/// with a cover fit; otherwise a deterministic gradient stands in so the layout
/// still reads correctly for entries whose artwork was never fetched.
class PosterArt extends StatelessWidget {
  const PosterArt({
    super.key,
    this.seed = 0,
    this.image,
    this.title,
    this.showTitle = false,
    this.titleSize,
    this.alignment = Alignment.topCenter,
    this.fit = BoxFit.cover,
  });

  final int seed;
  final String? image;
  final Alignment alignment;
  final BoxFit fit;
  final String? title;
  final bool showTitle;
  final double? titleSize;

  /// A network cover (real sources hand back an `http(s)` `vod_pic`) rather than
  /// a bundled `assets/` path.
  bool get _isNetwork => image != null && (image!.startsWith('http://') || image!.startsWith('https://'));

  @override
  Widget build(BuildContext context) {
    final path = image;
    if (path != null) {
      if (_isNetwork) {
        return Image.network(
          path,
          fit: fit,
          alignment: alignment,
          filterQuality: FilterQuality.medium,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _placeholder(),
          errorBuilder: (_, _, _) => _placeholder(),
        );
      }
      return Image.asset(
        path,
        fit: fit,
        alignment: alignment,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    final p = PosterPalette.of(seed);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.top, p.bottom],
          stops: const [0.0, 0.85],
        ),
      ),
      child: CustomPaint(
        painter: _PosterTexture(accent: p.accent),
        child: showTitle
            ? Padding(
                padding: const EdgeInsets.all(14),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    title ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'LcbSerif',
                      fontSize: titleSize ?? 22,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.95),
                      shadows: const [
                        Shadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 2)),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _PosterTexture extends CustomPainter {
  const _PosterTexture({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    // Soft light leak in one corner.
    final glow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.7, -0.8),
        radius: 1.1,
        colors: [accent.withValues(alpha: 0.34), Colors.transparent],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, glow);

    // Fine diagonal grain, reads as print texture at small sizes.
    final grain = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    final step = math.max(6.0, size.shortestSide / 26);
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), grain);
    }

    // Bottom vignette keeps overlaid text readable.
    final vignette = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.45)],
        stops: const [0.55, 1.0],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
  }

  @override
  bool shouldRepaint(_PosterTexture old) => old.accent != accent;
}
