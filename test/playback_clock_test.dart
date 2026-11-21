import 'package:flutter_test/flutter_test.dart';
import 'package:lai_cui_ba/models/models.dart';
import 'package:lai_cui_ba/services/playback_clock.dart';

/// These cover the three original bugs from `ARCHITECTURE.md` §5: seeking
/// through an unknown duration, trusting a position measured on an ad-polluted
/// timeline, and a resume seek that cannot be told apart from a user scrub.
void main() {
  const film = Duration(minutes: 45); // 2 700 000 ms
  const ad = Duration(seconds: 15);

  group('PlaybackClock — opening resume', () {
    test('does nothing for a fresh play', () {
      final clock = PlaybackClock();
      clock.onDuration(film);
      clock.onPosition(const Duration(seconds: 3));
      expect(clock.pendingSeek(), isNull);
      expect(clock.recordable, isTrue);
    });

    test('waits for the duration before seeking', () {
      final clock = PlaybackClock(
        resume: const ResumePoint(positionMs: 720000, totalMs: 2700000),
      );
      // Position alone is not a scale: the clock must not convert anything yet.
      clock.onPosition(Duration.zero);
      expect(clock.pendingSeek(), isNull);

      clock.onDuration(film);
      expect(clock.pendingSeek(), const Duration(minutes: 12));
      // Taken once only — the caller pumps this on every stream event.
      expect(clock.pendingSeek(), isNull);
    });

    test('does not re-seek when mpv already honoured start', () {
      final clock = PlaybackClock(
        resume: const ResumePoint(positionMs: 720000, totalMs: 2700000),
      );
      clock.onDuration(film);
      // `start` applied: the player is at the target (give or take a tick).
      clock.onPosition(const Duration(minutes: 12, seconds: 1));
      expect(clock.pendingSeek(), isNull);
    });

    test('re-issues the seek when start was silently dropped', () {
      final clock = PlaybackClock(
        resume: const ResumePoint(positionMs: 720000, totalMs: 2700000),
      );
      clock.onDuration(film);
      clock.onPosition(const Duration(seconds: 2)); // started from the head
      expect(clock.pendingSeek(), const Duration(minutes: 12));
      expect(clock.pendingSeek(), isNull);
    });

    test('refuses a position recorded on a different timeline', () {
      final clock = PlaybackClock(
        // Recorded while a 15-second pre-roll was playing.
        resume: const ResumePoint(positionMs: 12000, totalMs: 15000),
      );
      clock.onDuration(film);
      clock.onPosition(Duration.zero);
      // Nothing to resume: no seek at all, playback simply stays at the head.
      expect(clock.pendingSeek(), isNull);
    });

    test('rewinds to the head when an untrustworthy position already moved us',
        () {
      final clock = PlaybackClock(
        resume: const ResumePoint(positionMs: 12000, totalMs: 15000),
      );
      clock.onDuration(film);
      clock.onPosition(const Duration(seconds: 30)); // `start` took, into the ad
      expect(clock.pendingSeek(), Duration.zero);
    });
  });

  group('PlaybackClock — scrubbing', () {
    test('holds a scrub until the timeline is known', () {
      final clock = PlaybackClock(
        resume: const ResumePoint(positionMs: 720000, totalMs: 2700000),
      );
      clock.requestSeek(const Duration(minutes: 20));

      // No duration yet: seeking now would land on zero.
      expect(clock.pendingSeek(), isNull);

      clock.onDuration(film);
      expect(clock.pendingSeek(), const Duration(minutes: 20));
    });

    test('a scrub supersedes the opening resume', () {
      final clock = PlaybackClock(
        resume: const ResumePoint(positionMs: 720000, totalMs: 2700000),
      );
      clock.onDuration(film);
      clock.requestSeek(const Duration(minutes: 30));
      expect(clock.pendingSeek(), const Duration(minutes: 30));
      // The resume must not come back after the user's own choice.
      expect(clock.pendingSeek(), isNull);
    });

    test('the last of several scrubs wins', () {
      final clock = PlaybackClock();
      clock.requestSeek(const Duration(minutes: 5));
      clock.requestSeek(const Duration(minutes: 9));
      clock.onDuration(film);
      expect(clock.pendingSeek(), const Duration(minutes: 9));
    });

    test('clamps a scrub past the end and before the start', () {
      final clock = PlaybackClock();
      clock.onDuration(film);
      clock.requestSeek(const Duration(hours: 2));
      expect(clock.pendingSeek(), film);

      clock.requestSeek(const Duration(seconds: -5));
      expect(clock.pendingSeek(), Duration.zero);
    });
  });

  group('PlaybackClock — timeline drift', () {
    test('flags an ad segment ending and re-judges the resume', () {
      final clock = PlaybackClock(
        resume: const ResumePoint(positionMs: 720000, totalMs: 2700000),
      );

      // The stream opens on the pre-roll: wrong timeline, position dropped.
      clock.onDuration(ad);
      clock.onPosition(Duration.zero);
      expect(clock.pendingSeek(), isNull);

      // The feature starts: same URL, a duration 180× longer.
      clock.onDuration(film);
      expect(clock.drifting, isTrue);
      clock.onPosition(Duration.zero);
      expect(clock.pendingSeek(), const Duration(minutes: 12));
    });

    test('does not persist a position measured across a drift', () {
      final clock = PlaybackClock(
        resume: const ResumePoint(positionMs: 720000, totalMs: 2700000),
      );
      clock.onDuration(film);
      clock.onPosition(const Duration(minutes: 13));
      expect(clock.recordable, isTrue);

      clock.onDuration(const Duration(minutes: 20));
      expect(clock.drifting, isTrue);
      expect(clock.recordable, isFalse);
    });

    test('tolerates a small re-measurement', () {
      final clock = PlaybackClock();
      clock.onDuration(const Duration(seconds: 100));
      clock.onDuration(const Duration(seconds: 110)); // 10%, inside tolerance
      expect(clock.drifting, isFalse);
      expect(clock.recordable, isTrue);
    });

    test('ignores a zero duration, which is just "not ready"', () {
      final clock = PlaybackClock();
      clock.onDuration(film);
      clock.onDuration(Duration.zero); // a live stream forgets its duration
      expect(clock.drifting, isFalse);
      expect(clock.duration, film);
    });
  });

  group('resolveResume', () {
    test('accepts a position on a matching timeline', () {
      expect(
        resolveResume(
          const ResumePoint(positionMs: 600000, totalMs: 2700000),
          film,
        ),
        const Duration(minutes: 10),
      );
    });

    test('rejects everything it cannot check', () {
      // Live stream: no duration to clamp against.
      expect(
        resolveResume(
          const ResumePoint(positionMs: 600000, totalMs: 0),
          Duration.zero,
        ),
        isNull,
      );
      // Never watched past the head.
      expect(
        resolveResume(const ResumePoint(positionMs: 0, totalMs: 0), film),
        isNull,
      );
      // Finished: within three seconds of the end.
      expect(
        resolveResume(
          const ResumePoint(positionMs: 2699000, totalMs: 2700000),
          film,
        ),
        isNull,
      );
    });

    test('treats a position longer than the real stream as finished', () {
      // The row was recorded on a longer cut, so the middle of it is past the
      // end of what actually opened. Restart rather than clamp to the credits.
      expect(
        resolveResume(
          const ResumePoint(positionMs: 3000000, totalMs: 0),
          film,
        ),
        isNull,
      );
    });

    test('a saved total of zero is not treated as a mismatch', () {
      // Old rows recorded before durations were captured.
      expect(
        resolveResume(const ResumePoint(positionMs: 60000, totalMs: 0), film),
        const Duration(minutes: 1),
      );
    });
  });

  group('timelinesAgree', () {
    test('compares relative drift', () {
      expect(timelinesAgree(2700, 2700), isTrue);
      expect(timelinesAgree(1080, 2700), isFalse);
      expect(timelinesAgree(2160, 2700), isTrue); // exactly 20%
      expect(timelinesAgree(0, 2700), isTrue); // nothing to compare
    });
  });
}
