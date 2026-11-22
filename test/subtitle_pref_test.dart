import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/track_choice.dart';
import 'package:lai_cui_ba/ui/widgets/subtitle_style.dart';

/// 设置页的「默认字幕」只做一件事：在观众还没选过的时候替他挑一条。
/// 挑错的代价是每次打开都要手动改回来，所以每条规则都单独钉住。
void main() {
  const chinese = TrackOption(id: '2', language: 'zh');
  const cantonese = TrackOption(id: '3', language: 'yue');
  const english = TrackOption(id: '4', language: 'eng');

  group('SubtitlePref.pick', () {
    test('auto leaves the choice to the player', () {
      expect(SubtitlePref.auto.pick(const [chinese, english]), isNull);
    });

    test('off turns subtitles off even when the stream has some', () {
      expect(SubtitlePref.off.pick(const [chinese, english]), 'no');
      expect(SubtitlePref.off.pick(const []), 'no');
    });

    test('chinese picks the first Chinese track, including Cantonese', () {
      expect(SubtitlePref.chinese.pick(const [english, chinese]), '2');
      // 粤语也算中文：观众要的是"看得懂"，不是普通话。
      expect(SubtitlePref.chinese.pick(const [english, cantonese]), '3');
    });

    test('english picks the English track wherever it sits', () {
      expect(SubtitlePref.english.pick(const [chinese, english]), '4');
    });

    test('no match means no opinion, not "pick something"', () {
      // 只有日语字幕时要「中文优先」，不该硬塞一条日语上去。
      expect(
        SubtitlePref.chinese.pick(const [TrackOption(id: '5', language: 'jpn')]),
        isNull,
      );
      expect(SubtitlePref.english.pick(const [chinese]), isNull);
    });

    test('a language code wins over a title that says otherwise', () {
      // 「中文音轨」+ language=eng 这类错配：码是可信的，标题不是。
      const lying = TrackOption(id: '6', title: '中文', language: 'eng');
      expect(SubtitlePref.chinese.pick(const [lying]), isNull);
      expect(SubtitlePref.english.pick(const [lying]), '6');
    });

    test('a title is used only when the stream forgot the language code', () {
      const unnamed = TrackOption(id: '7', title: '简体中文');
      const unnamedEn = TrackOption(id: '8', title: 'English SDH');
      expect(SubtitlePref.chinese.pick(const [unnamedEn, unnamed]), '7');
      expect(SubtitlePref.english.pick(const [unnamed, unnamedEn]), '8');
    });

    test('a track with neither code nor title is never guessed', () {
      expect(SubtitlePref.chinese.pick(const [TrackOption(id: '9')]), isNull);
      expect(SubtitlePref.english.pick(const [TrackOption(id: '9')]), isNull);
    });
  });

  group('SubtitlePref.parse', () {
    test('the stored short code round-trips', () {
      for (final p in SubtitlePref.values) {
        expect(SubtitlePref.parse(p.slug), p, reason: p.slug);
      }
    });

    test('the enum name is accepted too, so a hand-edited file still loads', () {
      expect(SubtitlePref.parse('chinese'), SubtitlePref.chinese);
      expect(SubtitlePref.parse('english'), SubtitlePref.english);
    });

    test('anything unreadable falls back to auto', () {
      expect(SubtitlePref.parse(null), SubtitlePref.auto);
      expect(SubtitlePref.parse(''), SubtitlePref.auto);
      expect(SubtitlePref.parse('zh-CN'), SubtitlePref.auto);
      expect(SubtitlePref.parse(3), SubtitlePref.auto);
    });
  });

  group('AppSettings subtitle fields', () {
    test('defaults are the ones the player already used', () {
      const s = AppSettings();
      expect(s.subtitlePref, 'auto');
      expect(s.subtitleSize, LcbSubtitleStyle.standard);
    });

    test('both fields survive a round-trip and land in extra-free JSON', () {
      const s = AppSettings(subtitlePref: 'zh', subtitleSize: 42);
      final back = AppSettings.fromJson(s.toJson());
      expect(back.subtitlePref, 'zh');
      expect(back.subtitleSize, 42);
      expect(back.extra, isEmpty);
    });

    test('a bad preference code falls back instead of failing the load', () {
      final back = AppSettings.fromJson(const {'subtitlePref': 'klingon'});
      expect(back.subtitlePref, 'auto');
    });

    test('a silly font size is clamped into a readable range', () {
      expect(AppSettings.fromJson(const {'subtitleSize': 4}).subtitleSize, 16);
      expect(AppSettings.fromJson(const {'subtitleSize': 400}).subtitleSize, 96);
      // 存进来的不是数字就用默认值。
      expect(
        AppSettings.fromJson(const {'subtitleSize': 'big'}).subtitleSize,
        LcbSubtitleStyle.standard,
      );
    });
  });

  group('LcbSubtitleStyle', () {
    test('the preset list is what the settings row shows', () {
      expect(LcbSubtitleStyle.presets[LcbSubtitleStyle.standard], '标准');
      expect(LcbSubtitleStyle.labelOf(32), '标准');
      expect(LcbSubtitleStyle.labelOf(24), '小');
      expect(LcbSubtitleStyle.labelOf(54), '特大');
    });

    test('an off-grid size is reported as the nearest preset', () {
      expect(LcbSubtitleStyle.labelOf(36), '标准');
      expect(LcbSubtitleStyle.labelOf(44), '大');
    });

    test('the size reaches the actual subtitle text style', () {
      // 这是字号真的生效的地方：media_kit 用这个 TextStyle 画字幕。
      expect(LcbSubtitleStyle.of(42).style.fontSize, 42);
      expect(LcbSubtitleStyle.of(42).style.color, const Color(0xffffffff));
      expect(LcbSubtitleStyle.of(24).style.fontSize, 24);
    });

    test('out-of-range values are clamped, not passed to layout', () {
      expect(LcbSubtitleStyle.of(0).style.fontSize, 16);
      expect(LcbSubtitleStyle.of(999).style.fontSize, 96);
    });
  });
}
