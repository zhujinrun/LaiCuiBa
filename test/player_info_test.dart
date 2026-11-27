import 'package:flutter_test/flutter_test.dart';
import 'package:lai_cui_ba/services/player_info.dart';

void main() {
  group('PlayerInfoField', () {
    test('parseList keeps order and drops unknowns', () {
      expect(
        PlayerInfoField.parseList('frameRate,resolution,bitrate'),
        [
          PlayerInfoField.frameRate,
          PlayerInfoField.resolution,
          PlayerInfoField.bitrate,
        ],
      );
      expect(PlayerInfoField.parseList(''), isEmpty);
      expect(PlayerInfoField.parseList('resolution,garbage,bitrate'), [
        PlayerInfoField.resolution,
        PlayerInfoField.bitrate,
      ]);
    });

    test('slugs round-trip', () {
      for (final f in PlayerInfoField.values) {
        expect(PlayerInfoField.parseList(f.slug), [f]);
      }
    });
  });

  group('formatResolution', () {
    test('renders dw×dh', () {
      expect(formatResolution(1920, 1080), '1920×1080');
    });

    test('null or zero is unavailable', () {
      expect(formatResolution(null, 1080), isNull);
      expect(formatResolution(0, 0), isNull);
      expect(formatResolution(-1, 1080), isNull);
    });
  });

  group('formatFrameRate', () {
    test('trims mpv noise', () {
      expect(formatFrameRate('23.976023'), '23.976 fps');
      expect(formatFrameRate('24.000000'), '24 fps');
    });

    test('zero / empty / garbage is unavailable', () {
      expect(formatFrameRate('0.000000'), isNull);
      expect(formatFrameRate(''), isNull);
      expect(formatFrameRate('abc'), isNull);
      expect(formatFrameRate(null), isNull);
    });
  });

  group('formatBitrate', () {
    test('renders kbps', () {
      expect(formatBitrate('2543.4'), '2543 kbps');
    });

    test('zero / garbage is unavailable', () {
      expect(formatBitrate('0'), isNull);
      expect(formatBitrate(''), isNull);
      expect(formatBitrate(null), isNull);
    });
  });

  group('formatQualityLabel', () {
    test('集数标签改成原版的「共N集」', () {
      for (final raw in [
        '第30集',
        '30集',
        '全30集',
        '第30集全',
        '更新至第30集',
        '更新至30集',
      ]) {
        expect(formatQualityLabel(raw), '共30集', reason: raw);
      }
    });

    test('画质与语言标签保持原样', () {
      for (final raw in ['1080P', 'TC国语', '枪版', '4K HDR']) {
        expect(formatQualityLabel(raw), raw, reason: raw);
      }
    });

    test('空值不会拼出分隔段', () {
      expect(formatQualityLabel(null), '');
      expect(formatQualityLabel('  '), '');
    });
  });
}
