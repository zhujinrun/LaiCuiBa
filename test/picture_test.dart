import 'package:flutter/rendering.dart' show BoxFit;
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/services/picture.dart';

/// 画面比例 / 画面调节的纯逻辑：档位解析、调节值序列化与 mpv 属性映射。
void main() {
  group('AspectMode', () {
    test('six modes carry a slug, a label and a BoxFit', () {
      expect(AspectMode.values.length, 6);
      final bySlug = {
        for (final m in AspectMode.values) m.slug: m,
      };
      expect(bySlug.keys, [
        'fit',
        'stretch',
        'fill',
        'fitWidth',
        'fitHeight',
        'crop',
      ]);
      expect(AspectMode.fit.boxFit, BoxFit.contain);
      expect(AspectMode.stretch.boxFit, BoxFit.fill);
      expect(AspectMode.fill.boxFit, BoxFit.cover);
      expect(AspectMode.fitWidth.boxFit, BoxFit.fitWidth);
      expect(AspectMode.fitHeight.boxFit, BoxFit.fitHeight);
      expect(AspectMode.crop.boxFit, BoxFit.cover);
    });

    test('parse round-trips every slug and falls back to fit', () {
      for (final m in AspectMode.values) {
        expect(AspectMode.parse(m.slug), m);
      }
      expect(AspectMode.parse(null), AspectMode.fit);
      expect(AspectMode.parse('garbage'), AspectMode.fit);
    });
  });

  group('PictureAdjust', () {
    test('none is the neutral default', () {
      expect(PictureAdjust.none.isNeutral, isTrue);
      expect(PictureAdjust.none.brightness, 0);
      expect(PictureAdjust.none.gamma, 0);
    });

    test('copyWith overrides only the given field', () {
      final a = PictureAdjust.none.copyWith(brightness: 30);
      expect(a.brightness, 30);
      expect(a.contrast, 0);
      expect(a.isNeutral, isFalse);
    });

    test('round-trips through json', () {
      const a = PictureAdjust(
        brightness: -20,
        contrast: 10,
        saturation: 5,
        hue: 0,
        gamma: 15,
      );
      final back = PictureAdjust.fromJson(a.toJson());
      expect(back, a);
    });

    test('clamps out-of-range values and drops junk', () {
      final back = PictureAdjust.fromJson({
        'brightness': 500,
        'contrast': 'not a number',
        'saturation': -300,
      });
      expect(back.brightness, 100);
      expect(back.contrast, 0);
      expect(back.saturation, -100);
    });

    test('null json is neutral', () {
      expect(PictureAdjust.fromJson(null), PictureAdjust.none);
    });

    test('mpvProperties maps the five sliders to mpv property names', () {
      const a = PictureAdjust(
        brightness: 10,
        contrast: 20,
        saturation: 30,
        hue: 40,
        gamma: 50,
      );
      expect(a.mpvProperties, [
        ('brightness', 10),
        ('contrast', 20),
        ('saturation', 30),
        ('hue', 40),
        ('gamma', 50),
      ]);
    });
  });
}
