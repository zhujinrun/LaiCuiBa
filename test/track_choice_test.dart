import 'package:flutter_test/flutter_test.dart';

import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/track_choice.dart';

void main() {
  group('TrackOption', () {
    test('a written title wins over the language code', () {
      const t = TrackOption(id: '2', title: '国语', language: 'zh');
      expect(t.label, '国语');
    });

    test('a codec name in the title slot is not a label', () {
      // Some muxes put "h264" / "AAC (LC)" where the name goes; showing that
      // as the track name would tell the viewer nothing.
      const video = TrackOption(id: '1', title: 'h264', codec: 'h264');
      expect(video.label, '轨道 1');
      const audio = TrackOption(id: '2', title: 'AAC (LC)', language: 'en');
      expect(audio.label, '英语');
    });

    test('the language code is translated, unknown codes fall back to the id', () {
      expect(const TrackOption(id: '2', language: 'eng').label, '英语');
      expect(const TrackOption(id: '3', language: 'cmn').label, '中文');
      expect(const TrackOption(id: '4', language: 'yue').label, '粤语');
      expect(const TrackOption(id: '5', language: 'und').label, '轨道 5');
      expect(const TrackOption(id: '6', language: 'tlh').label, '轨道 6');
    });

    test('an external subtitle id (a URL) gets a readable label', () {
      const t = TrackOption(
        id: 'https://cdn.example.com/sub/1.srt',
        external: true,
      );
      expect(t.label, '外挂字幕');
    });

    test('detail lists only what the stream actually reported', () {
      const video = TrackOption(
        id: '1',
        width: 1920,
        height: 1080,
        codec: 'hevc',
      );
      expect(video.detail, '1920×1080 · HEVC');

      const audio = TrackOption(id: '2', codec: 'aac', channels: 2);
      expect(audio.detail, 'AAC · 2 声道');

      const sub = TrackOption(id: '3', codec: 'subrip', external: true);
      expect(sub.detail, 'SUBRIP · 外挂');

      // Nothing known → no second line at all, rather than an empty gap.
      expect(const TrackOption(id: '9').detail, isNull);
    });

    test('zero resolution is treated as unknown', () {
      expect(const TrackOption(id: '1', width: 0, height: 0).detail, isNull);
    });
  });

  group('TrackChoices', () {
    test('a single track is not a choice', () {
      const one = TrackChoices(
        video: [TrackOption(id: '1')],
        audio: [TrackOption(id: '2')],
      );
      expect(one.hasVideoChoice, isFalse);
      expect(one.hasAudioChoice, isFalse);
      // A lone subtitle still deserves a switch, because 「关闭」 is a choice.
      expect(one.hasSubtitleChoice, isFalse);
      expect(
        one.copyWith(subtitle: const [TrackOption(id: '3')]).hasSubtitleChoice,
        isTrue,
      );
    });

    test('empty means the player has not reported anything yet', () {
      expect(TrackChoices.none.isEmpty, isTrue);
      expect(
        TrackChoices.none
            .copyWith(audio: const [TrackOption(id: '2')])
            .isEmpty,
        isFalse,
      );
    });
  });

  group('TrackPrefs', () {
    test('survives a JSON round trip', () {
      const prefs = TrackPrefs(video: '1', audio: '2', subtitle: 'no');
      final back = TrackPrefs.fromJson(prefs.toJson());
      expect(back.video, '1');
      expect(back.audio, '2');
      expect(back.subtitle, 'no');
    });

    test('null means "no opinion", an empty map means the same', () {
      const empty = TrackPrefs.empty;
      expect(empty.isEmpty, isTrue);
      expect(TrackPrefs.fromJson(const {}).isEmpty, isTrue);
      expect(TrackPrefs.fromJson(null).isEmpty, isTrue);
    });

    test('a remembered id that is gone from this stream is dropped', () {
      const prefs = TrackPrefs(audio: '4', video: '2');
      const options = [
        TrackOption(id: '1'),
        TrackOption(id: '2'),
      ];
      expect(prefs.audioFor(options), isNull);
      expect(prefs.videoFor(options), '2');
    });

    test('"subtitles off" is remembered even though it is not a track', () {
      const prefs = TrackPrefs(subtitle: 'no');
      expect(prefs.subtitleFor(const [TrackOption(id: '3')]), 'no');
      // And a real subtitle id still has to exist.
      expect(
        const TrackPrefs(subtitle: '7').subtitleFor(const [TrackOption(id: '3')]),
        isNull,
      );
    });

    test('broken JSON only loses the entry, it does not throw', () {
      expect(TrackPrefs.fromJson('nonsense').isEmpty, isTrue);
      expect(TrackPrefs.fromJson([1, 2]).isEmpty, isTrue);
      // Numeric ids are what an older writer would have produced.
      final numeric = TrackPrefs.fromJson(const {'audio': 3});
      expect(numeric.audio, '3');
      // Empty strings are not a pick.
      expect(TrackPrefs.fromJson(const {'audio': ''}).audio, isNull);
    });

    test('a copy only changes the track it was asked to', () {
      const base = TrackPrefs(audio: '2', subtitle: '3');
      final next = base.withSubtitle('no');
      expect(next.audio, '2');
      expect(next.video, isNull);
      expect(next.subtitle, 'no');
      expect(base.subtitle, '3'); // immutable
    });
  });

  group('AppSettings.trackPrefs', () {
    test('nested picks round trip through the settings blob', () {
      final settings = const AppSettings().copyWith(
        trackPrefs: const {
          'item-1|线路一': {'audio': '2', 'subtitle': 'no'},
        },
      );
      final back = AppSettings.fromJson(settings.toJson());
      expect(back.trackPrefs['item-1|线路一'], {'audio': '2', 'subtitle': 'no'});
    });

    test('a malformed entry does not sink the whole settings blob', () {
      final back = AppSettings.fromJson(const {
        'playerVolume': 42,
        'trackPrefs': {
          'good': {'audio': '1'},
          'not-a-map': 'oops',
          'empty': <String, String>{},
          'wrong-types': {'audio': true},
        },
      });
      expect(back.playerVolume, 42);
      expect(back.trackPrefs['good'], {'audio': '1'});
      expect(back.trackPrefs.containsKey('not-a-map'), isFalse);
      expect(back.trackPrefs.containsKey('empty'), isFalse);
      expect(back.trackPrefs.containsKey('wrong-types'), isFalse);
    });

    test('settings without the key parse to an empty map', () {
      expect(AppSettings.fromJson(const {'playerRate': 1.5}).trackPrefs, isEmpty);
    });
  });
}
