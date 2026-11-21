import '../models/models.dart';
import 'skip_rule.dart';

/// Where a playback session's seek bar is allowed to take the viewer.
///
/// A player reports two numbers — position and duration — and both are
/// meaningless on their own: a position measured before the duration is known
/// has no scale to be a fraction of, and a position recorded against a
/// *different* timeline (a source that splices a pre-roll ad into the same
/// stream) points at the ad break, not the feature. The original app got this
/// wrong in three ways that all looked like "按右键跳回片头":
///
/// 1. it converted slider values through a duration that was still zero,
/// 2. it trusted a position recorded while an ad was playing,
/// 3. it let the automatic skip-intro seek and the resume seek fight over the
///    same jump.
///
/// [PlaybackClock] is the single place that turns "the player says it is at X
/// for Y" into "seek to Z, or do nothing". The page feeds it every duration and
/// position it sees and asks [pendingSeek] what, if anything, to do. Every seek
/// the session makes goes through there, so there is exactly one seek per
/// intent and none gets issued against an unknown timeline.
class PlaybackClock {
  PlaybackClock({
    this.resume,
    this.skip = SkipRule.none,
    this.tolerance = 0.2,
    this.landingSlack = const Duration(seconds: 8),
  });

  /// The position the session was asked to resume from, if any.
  final ResumePoint? resume;

  /// How much of the head and tail the viewer asked to have skipped.
  ///
  /// Folded into this clock rather than handled by a second timer on purpose:
  /// the opening resume and the automatic skip-intro want the same instant, and
  /// two independent seekers would race for it. Here they are one decision.
  final SkipRule skip;

  /// How much the duration may change before the timeline counts as a different
  /// one. 20% per the playback spec: an episode that suddenly claims to be
  /// three minutes shorter is a different cut (or an ad segment ending), not a
  /// measurement wobble.
  final double tolerance;

  /// How far the player may land from the requested target before the seek is
  /// re-issued. mpv's `start` is applied while loading and is silently dropped
  /// for some HLS streams, so "we asked" is not the same as "we are there".
  final Duration landingSlack;

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  Duration? _queued;
  bool _resumeSettled = false;
  bool _drifted = false;
  bool _outroFired = false;

  /// The timeline is known, so a seek has a scale to land on.
  bool get ready => _duration > Duration.zero;

  Duration get duration => _duration;
  Duration get position => _position;

  /// The duration jumped more than [tolerance] at some point: what the session
  /// measured on the old timeline cannot be persisted.
  bool get drifting => _drifted;

  /// Whether the final position is worth writing to history.
  bool get recordable => ready && !_drifted;

  void onDuration(Duration d) {
    if (d <= Duration.zero) return; // unknown / not ready yet
    if (ready && !timelinesAgree(_duration.inMilliseconds, d.inMilliseconds,
        tolerance)) {
      // The stream switched timelines under us — an ad segment ended, or the
      // source moved to another cut. Everything measured so far belongs to the
      // old one, so the opening resume has to be judged again. The outro moves
      // with the new duration too, so it gets a fresh chance to fire.
      _drifted = true;
      _resumeSettled = false;
      _outroFired = false;
    }
    _duration = d;
  }

  void onPosition(Duration p) => _position = p;

  /// A scrub the user made. Kept until the timeline is known: seeking through a
  /// zero duration would land on zero, which is the "jumped back to the head"
  /// bug this class exists to prevent.
  void requestSeek(Duration target) => _queued = _clamp(target);

  /// The seek this session still owes, or null when there is nothing to do.
  ///
  /// Taking a target clears it, so a caller may pump this on every stream event
  /// without ever double-seeking.
  Duration? pendingSeek() {
    if (!ready) return null;

    final queued = _queued;
    if (queued != null) {
      _queued = null;
      _resumeSettled = true; // an explicit choice supersedes the opening resume
      return queued;
    }

    if (_resumeSettled) return null;
    _resumeSettled = true;

    // One landing decision for the whole opening: where 续播 asked to be, then
    // out of the intro if that address sits inside it. Doing them separately
    // would mean seeking to the saved position first and to the intro a moment
    // later — a visible double jump for anyone who stopped in the first minute.
    final head = skip.introFor(_duration) ?? Duration.zero;
    var target = head;
    final saved = resume;
    if (saved != null) {
      // Nothing trustworthy to resume — a different timeline, or already
      // watched to the end. Start from the head instead of dropping the viewer
      // somewhere arbitrary. A known intro still moves that start forward.
      target = resolveResume(saved, _duration, tolerance: tolerance) ?? head;
    }
    if (target < head) target = head;

    // Already there: mpv honoured `start`, so re-issuing would be a pointless
    // second jump. This also covers a stream whose intro the viewer is past by
    // the time the duration finally arrives.
    if ((_position - target).abs() <= landingSlack) return null;
    return target;
  }

  /// True once, when playback has reached the tail the viewer asked to skip.
  ///
  /// The caller decides what "skipped" means — the next episode, or just
  /// counting this one as finished. Reported at most once per timeline.
  bool takeOutro() {
    if (!ready || _outroFired) return false;
    final start = skip.outroStartFor(_duration);
    if (start == null || _position < start) return false;
    _outroFired = true;
    return true;
  }

  Duration _clamp(Duration target) {
    if (target < Duration.zero) return Duration.zero;
    if (ready && target > _duration) return _duration;
    return target;
  }
}

/// The position [saved] may be replayed at against a stream that really lasts
/// [actual], or null when it cannot be trusted.
///
/// Null is not a failure — it means "start from the head". Cases:
///
/// * [actual] is unknown (a live stream never reports one),
/// * the saved total disagrees with the real duration beyond [tolerance], i.e.
///   the position was measured on a different timeline,
/// * the position is the end of the episode, so replaying it would immediately
///   finish again.
Duration? resolveResume(
  ResumePoint saved,
  Duration actual, {
  double tolerance = 0.2,
}) {
  if (actual <= Duration.zero) return null;
  if (saved.positionMs <= 0) return null;
  if (saved.totalMs > 0 &&
      !timelinesAgree(saved.totalMs, actual.inMilliseconds, tolerance)) {
    return null;
  }
  // Within three seconds of the end counts as finished (matches the store's
  // rule, which cannot see the real duration and so has to be lenient). This
  // also covers a position longer than the stream: it was measured on another
  // cut, and replaying it would only clamp to the end anyway.
  if (saved.positionMs >= actual.inMilliseconds - 3000) return null;
  return Duration(milliseconds: saved.positionMs);
}

/// Whether two duration readings describe the same timeline.
bool timelinesAgree(int a, int b, [double tolerance = 0.2]) {
  if (a <= 0 || b <= 0) return true; // nothing to compare yet
  final drift = (a - b).abs() / b;
  return drift <= tolerance;
}
