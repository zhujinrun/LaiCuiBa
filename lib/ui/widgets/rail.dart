import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// A horizontal rail of posters that can be paged with the mouse.
///
/// The original has no scrollbar here and Flutter's desktop defaults do not let
/// a mouse drag a list, so the arrows are the only way through a rail with a
/// mouse: they fade in while the pointer is over the rail and move by a screen
/// at a time. Measured from the shipped window (1920x1040): the disc is 38px,
/// its centre sits 32px from the rail's left and right edges and is vertically
/// centred on the artwork, not on the whole rail (the caption below the cover
/// does not count).
class LcbRail extends StatefulWidget {
  const LcbRail({
    super.key,
    required this.height,
    required this.artHeight,
    required this.cardWidth,
    required this.itemCount,
    required this.itemBuilder,
    this.gap = LcbMetrics.posterGap,
    this.leading = LcbMetrics.pagePadding,
  });

  /// Height of the rail including whatever sits under the artwork.
  final double height;

  /// Height of the artwork alone; the arrows centre on this.
  final double artHeight;

  /// Distance between the starts of two cards, used to page by whole cards.
  final double cardWidth;

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  final double gap;

  /// The page gutter. The card list is inset by this on BOTH sides so it
  /// stays inside the section's main band (section title .. 查看全部), which
  /// carry the same gutter. The paging discs remain on the rail edge.
  final double leading;

  /// Diameter of the paging disc, as measured on the original.
  static const double arrowSize = 38;

  /// Distance from a disc's centre to the rail edge.
  static const double arrowInset = 32;

  @override
  State<LcbRail> createState() => _LcbRailState();
}

class _LcbRailState extends State<LcbRail> {
  final _controller = ScrollController();
  bool _hover = false;
  double _offset = 0;
  double _max = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _sync(ScrollMetrics metrics) {
    if ((metrics.pixels - _offset).abs() < 0.5 &&
        (metrics.maxScrollExtent - _max).abs() < 0.5) {
      return;
    }
    setState(() {
      _offset = metrics.pixels;
      _max = metrics.maxScrollExtent;
    });
  }

  bool get _canGoLeft => _offset > 0.5;

  bool get _canGoRight => _max > 0.5 && _offset < _max - 0.5;

  /// Moves by as many whole cards as fit a screen, rounded up -- the original
  /// lands exactly one card past the last fully visible one, which is what
  /// keeps a cover from being left half cut at the left edge.
  void _page(int direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final step = widget.cardWidth + widget.gap;
    final perPage = (position.viewportDimension / step).ceil();
    final target = (position.pixels + perPage * step * direction)
        .clamp(0.0, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.5) return;
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Stack(
          children: [
            // Inset the scrollable list on both sides so its viewport matches
            // the section header's band (title .. 查看全部). Previously only
            // the left had a gutter and the cards bled off the right window
            // edge, so a paged rail looked ragged against the header above it.
            // The discs are siblings of this padding, so they still sit on the
            // full-width rail edge where the original measured them.
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.leading),
                // Both notifications matter: a scroll changes the offset,
                // while a resize or a feed swap changes the extent without
                // scrolling.
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: (n) {
                    _sync(n.metrics);
                    return false;
                  },
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      _sync(n.metrics);
                      return false;
                    },
                    child: ListView.separated(
                      controller: _controller,
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.itemCount,
                      separatorBuilder: (_, __) => SizedBox(width: widget.gap),
                      itemBuilder: widget.itemBuilder,
                    ),
                  ),
                ),
              ),
            ),
            _arrow(left: true, visible: _hover && _canGoLeft),
            _arrow(left: false, visible: _hover && _canGoRight),
          ],
        ),
      ),
    );
  }

  Widget _arrow({required bool left, required bool visible}) {
    const inset = LcbRail.arrowInset - LcbRail.arrowSize / 2;
    final top = (widget.artHeight - LcbRail.arrowSize) / 2;
    return Positioned(
      left: left ? inset : null,
      right: left ? null : inset,
      top: top < 0 ? 0 : top,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          key: left ? const ValueKey('rail-prev') : const ValueKey('rail-next'),
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: _RailArrow(
            left: left,
            onTap: () => _page(left ? -1 : 1),
          ),
        ),
      ),
    );
  }
}

class _RailArrow extends StatefulWidget {
  const _RailArrow({required this.left, required this.onTap});

  final bool left;
  final VoidCallback onTap;

  @override
  State<_RailArrow> createState() => _RailArrowState();
}

class _RailArrowState extends State<_RailArrow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    const size = LcbRail.arrowSize;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Sampled off the original: #2F2F32 at rest, a shade lighter under
            // the pointer, with a soft drop shadow to lift it off the covers.
            color: _hover ? const Color(0xFF4A4A4C) : const Color(0xFF2F2F32),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 10,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            widget.left ? CupertinoIcons.chevron_left : CupertinoIcons.chevron_right,
            size: 20,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
