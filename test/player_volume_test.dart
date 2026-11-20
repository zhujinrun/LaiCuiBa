import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/ui/pages/player_page.dart';

void main() {
  testWidgets(
    'VolumeControl maps media_kit 0-100 volume onto a 0-1 slider',
    (tester) async {
      double? reported;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VolumeControl(
              volume: 100, // media_kit's default, the value that used to crash
              onVolume: (v) => reported = v,
            ),
          ),
        ),
      );

      // 100 must land as 1.0 on the slider, never as an out-of-range 100 that
      // trips Slider's `value <= max` assert and kills a debug build.
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 1.0);
      expect(slider.min, 0.0);
      expect(slider.max, 1.0);
      expect(tester.takeException(), isNull);

      // Dragging back to the middle reports 50 back out (0-100 domain).
      slider.onChanged!(0.5);
      expect(reported, 50.0);
    },
  );
}
