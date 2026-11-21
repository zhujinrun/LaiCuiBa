import 'package:flutter_test/flutter_test.dart';
import 'package:lai_cui_ba/services/badge_rule.dart';

void main() {
  List<String> slugs(String title, {String? remarks, String? tag}) =>
      BadgeRule.badgesOf(title, remarks: remarks, tag: tag)
          .map((b) => b.slug)
          .toList();

  group('识别规格', () {
    test('空文本不给徽章', () {
      expect(BadgeRule.badgesOf(''), isEmpty);
      expect(BadgeRule.badgesOf('三体'), isEmpty);
    });

    test('大小写不敏感，中文片名无规格就不显示', () {
      expect(slugs('Sample.2014.UHD.BluRay.2160p.REMUX.HDR10.HEVC.TrueHD.7.1.Atmos.mkv'),
          containsAll(['uhd', 'hdr10', 'truehd', 'atmos', 'bluray', 'remux', 'hevc']));
      expect(slugs('sample.2014.uhd.bluray.2160p.remux.hdr10.hevc.truehd.7.1.atmos.mkv'),
          containsAll(['uhd', 'hdr10']));
    });

    test('杜比视界与杜比数字是不同规格，各识别各的', () {
      final b = BadgeRule.badgesOf('xxx.2160p.DV.HDR10+.DDP5.1.Atmos.mkv');
      expect(b.map((e) => e.slug), contains('dolbyVision'));
      expect(b.map((e) => e.slug), contains('dolbyDigital'));
      expect(b.map((e) => e.slug), contains('hdr10plus'));
      expect(b.map((e) => e.slug), contains('atmos'));
      expect(b.map((e) => e.slug), isNot(contains('hdr10')));
    });

    test('HDR10+ 不重复算 HDR10', () {
      final b = slugs('x.HDR10+.mkv');
      expect(b, contains('hdr10plus'));
      expect(b, isNot(contains('hdr10')));
    });

    test('分辨率互斥：2160p 只算 4K，不再给 2160p', () {
      expect(slugs('x.2160p.mkv'), ['uhd']);
      expect(slugs('x.4K.mkv'), ['uhd']);
      expect(slugs('x.1080p.mkv'), ['q1080']);
      expect(slugs('x.720p.mkv'), ['q720']);
    });

    test('音轨识别 DTS / DTS-HD / DTS:X / 杜比数字', () {
      expect(slugs('x.DTS.mkv'), contains('dts'));
      expect(slugs('x.DTS-HD MA.mkv'), contains('dtshd'));
      expect(slugs('x.DTS:X.mkv'), contains('dtsx'));
      expect(slugs('x.Dolby Digital 5.1.mkv'), contains('dolbyDigital'));
      expect(slugs('x.AC3.mkv'), contains('dolbyDigital'));
    });

    test('编码与来源', () {
      expect(slugs('x.HEVC.mkv'), contains('hevc'));
      expect(slugs('x.x265.mkv'), contains('hevc'));
      expect(slugs('x.WEB-DL.mkv'), contains('webdl'));
      expect(slugs('x.BluRay.mkv'), contains('bluray'));
      expect(slugs('x.IMAX.mkv'), contains('imax'));
    });

    test('备注和 tag 也参与识别', () {
      expect(slugs('三体', remarks: '更新至40集'), isEmpty);
      expect(slugs('三体', tag: '4K杜比'), contains('uhd'));
      expect(slugs('某片', remarks: 'HDR'), contains('hdr'));
    });

    test('纯 HDR 算 HDR，HDR10 算 HDR10，不重复', () {
      expect(slugs('x.HDR.mkv'), ['hdr']);
      expect(slugs('x.HDR10.mkv'), ['hdr10']);
      expect(slugs('x.HDR10.mkv'), isNot(contains('hdr')));
    });

    test('顺序稳定：画质在前，HDR 其次，再音轨最后来源', () {
      final b = BadgeRule.badgesOf('x.2160p.HDR10.DTS.BluRay.mkv');
      final order = b.map((e) => e.slug).toList();
      expect(order.indexOf('uhd'), lessThan(order.indexOf('hdr10')));
      expect(order.indexOf('hdr10'), lessThan(order.indexOf('dts')));
      expect(order.indexOf('dts'), lessThan(order.indexOf('bluray')));
    });
  });

  group('徽章展示名', () {
    test('中文标签与短标', () {
      expect(BadgeRule.all.firstWhere((b) => b.slug == 'dolbyVision').label, '杜比视界');
      expect(BadgeRule.all.firstWhere((b) => b.slug == 'uhd').short, '4K');
      expect(BadgeRule.all.firstWhere((b) => b.slug == 'atmos').label, '杜比全景声');
    });
  });
}
