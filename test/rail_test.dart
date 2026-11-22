import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lai_cui_ba/ui/widgets/rail.dart';

/// Feeds the rail a fixed row of boxes so paging can be reasoned about in
/// whole cards: 10 cards of 196 with an 18 gap.
const _cardWidth = 196.0;
const _gap = 18.0;
const _step = _cardWidth + _gap;

Widget _host({required int count, double width = 800}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: LcbRail(
            height: 320,
            artHeight: 294,
            cardWidth: _cardWidth,
            itemCount: count,
            itemBuilder: (_, i) => SizedBox(
              width: _cardWidth,
              height: 294,
              child: Text('card $i'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<TestGesture> _hoverRail(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(find.byType(LcbRail)));
  await tester.pumpAndSettle();
  return gesture;
}

double _arrowOpacity(WidgetTester tester, String key) {
  return tester
      .widget<AnimatedOpacity>(find.byKey(ValueKey(key)))
      .opacity;
}

double _offset(WidgetTester tester) {
  return tester.widget<ListView>(find.byType(ListView)).controller!.offset;
}

void main() {
  testWidgets('a rail that fits shows no arrows at all', (tester) async {
    await tester.pumpWidget(_host(count: 2));
    await tester.pumpAndSettle();
    await _hoverRail(tester);
    expect(_arrowOpacity(tester, 'rail-prev'), 0);
    expect(_arrowOpacity(tester, 'rail-next'), 0);
  });

  testWidgets('arrows wait for the pointer to come over the rail',
      (tester) async {
    await tester.pumpWidget(_host(count: 10));
    await tester.pumpAndSettle();
    // Nothing shows until the pointer is over it -- the original keeps the
    // covers clean.
    expect(_arrowOpacity(tester, 'rail-next'), 0);
    await _hoverRail(tester);
    expect(_arrowOpacity(tester, 'rail-next'), 1);
    // Nothing to go back to yet.
    expect(_arrowOpacity(tester, 'rail-prev'), 0);
  });

  testWidgets('one page is a whole screen of cards, rounded up', (tester) async {
    await tester.pumpWidget(_host(count: 10));
    await tester.pumpAndSettle();
    await _hoverRail(tester);
    final viewport = tester.getSize(find.byType(LcbRail)).width;
    final expected = (viewport / _step).ceil() * _step;
    await tester.tap(find.byKey(const ValueKey('rail-next')));
    await tester.pumpAndSettle();
    expect(_offset(tester), closeTo(expected, 0.6));
  });

  testWidgets('the left arrow appears once the rail has moved', (tester) async {
    await tester.pumpWidget(_host(count: 10));
    await tester.pumpAndSettle();
    await _hoverRail(tester);
    await tester.tap(find.byKey(const ValueKey('rail-next')));
    await tester.pumpAndSettle();
    expect(_arrowOpacity(tester, 'rail-prev'), 1);
    await tester.tap(find.byKey(const ValueKey('rail-prev')));
    await tester.pumpAndSettle();
    expect(_offset(tester), closeTo(0, 0.6));
    expect(_arrowOpacity(tester, 'rail-prev'), 0);
  });

  testWidgets('the right arrow goes away at the end of the rail',
      (tester) async {
    await tester.pumpWidget(_host(count: 10));
    await tester.pumpAndSettle();
    await _hoverRail(tester);
    var taps = 0;
    for (var i = 0; i < 6; i++) {
      // Once the arrow goes away there is nothing left to page.
      if (_arrowOpacity(tester, 'rail-next') == 0) break;
      await tester.tap(find.byKey(const ValueKey('rail-next')));
      await tester.pumpAndSettle();
      taps++;
    }
    expect(taps, 2, reason: '10 cards over 3-4 per screen is two pages');
    final position = tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(position.offset, closeTo(position.position.maxScrollExtent, 0.6));
    expect(_arrowOpacity(tester, 'rail-next'), 0);
  });

  testWidgets('a mouse wheel over the rail scrolls the page, not the rail',
      (tester) async {
    // The original leaves a wheel alone here: the covers stay put and the page
    // moves. Paging exists precisely because the wheel does not.
    await tester.pumpWidget(_host(count: 10));
    await tester.pumpAndSettle();
    await _hoverRail(tester);
    await tester.sendEventToBinding(
      const PointerScrollEvent(position: Offset(400, 160), scrollDelta: Offset(0, 120)),
    );
    await tester.pumpAndSettle();
    expect(_offset(tester), 0);
  });

  testWidgets('the discs sit on the artwork, not on the caption', (tester) async {
    await tester.pumpWidget(_host(count: 10));
    await tester.pumpAndSettle();
    await _hoverRail(tester);
    final rail = tester.getRect(find.byType(LcbRail));
    final disc = tester.getRect(find.byKey(const ValueKey('rail-next')));
    // 38px disc, centred 32px from the right edge of the rail.
    expect(disc.width, closeTo(LcbRail.arrowSize, 0.6));
    expect(rail.right - disc.center.dx, closeTo(LcbRail.arrowInset, 0.6));
    // Vertically it centres on the 294px artwork, not on the 320px rail.
    expect(disc.center.dy - rail.top, closeTo(294 / 2, 1.0));

    final prev = tester.getRect(find.byKey(const ValueKey('rail-prev')));
    expect(prev.center.dx - rail.left, closeTo(LcbRail.arrowInset, 0.6));
    expect(prev.center.dy, closeTo(disc.center.dy, 0.6));
  });

  testWidgets('inside a start-aligned Column the rail still fills the width',
      (tester) async {
    // HomePage puts the rail as a child of Column(crossAxisAlignment: start),
    // which hands it loose width constraints. If the rail shrink-wrapped, the
    // arrows would drift inwards from the page edge.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 700,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LcbRail(
                    height: 320,
                    artHeight: 294,
                    cardWidth: _cardWidth,
                    itemCount: 10,
                    itemBuilder: (_, i) => const SizedBox(width: _cardWidth, height: 294),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await _hoverRail(tester);
    final rail = tester.getRect(find.byType(LcbRail));
    expect(rail.width, 700);
    final disc = tester.getRect(find.byKey(const ValueKey('rail-next')));
    expect(rail.right - disc.right, closeTo(13, 0.6));
  });
}
