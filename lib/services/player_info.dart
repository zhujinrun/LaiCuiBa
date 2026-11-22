/// Formats the live video parameters for the player's "信息显示" overlay.
///
/// The overlay is the original's 信息显示: a set of facts that stay pinned in a
/// corner of the picture and do not hide with the controls. Which facts show is
/// a per-viewer choice; what they render from is media_kit's `videoParams`
/// stream (resolution) and a handful of mpv properties (frame rate, bitrate).
///
/// Everything here is pure formatting so it can be unit-tested without a player.
library;

/// A single fact the overlay can pin to the picture corner.
enum PlayerInfoField {
  /// 1920×1080 — the display resolution mpv reports (`video-params/dw × dh`).
  resolution('resolution', '分辨率'),

  /// 23.976 fps — the estimated video frame rate (`estimated-vf-fps`).
  frameRate('frameRate', '帧率'),

  /// 2543 kbps — the video bitrate (`video-bitrate`), in kilobits.
  bitrate('bitrate', '码率');

  const PlayerInfoField(this.slug, this.label);

  /// Stable short code stored in settings.
  final String slug;

  /// Short name shown before the value.
  final String label;

  /// Parses the settings string (comma-separated slugs) back into fields,
  /// preserving order and dropping anything unrecognised — settings written by
  /// an older or newer build must never crash the player.
  static List<PlayerInfoField> parseList(String raw) {
    if (raw.isEmpty) return const [];
    final out = <PlayerInfoField>[];
    for (final part in raw.split(',')) {
      final slug = part.trim();
      for (final f in values) {
        if (f.slug == slug) {
          out.add(f);
          break;
        }
      }
    }
    return out;
  }
}

/// A resolved fact, ready to draw.
///
/// [label] is the short name (分辨率 / 帧率 / 码率); [value] is the rendered
/// text, or null when the source has not reported it yet — an unplayed stream
/// has no frame rate, and ExoPlayer-style kernels never report one (the original
/// shows `--` there, which we match).
class PlayerInfoFact {
  const PlayerInfoFact(this.label, this.value);

  final String label;
  final String? value;

  String get text => value ?? '--';

  @override
  String toString() => '$label $text';
}

/// Renders a resolution from display width/height (aspect-corrected).
///
/// `dw`/`dh` are null until the first decoded frame lands; before that there is
/// nothing to show.
String? formatResolution(int? dw, int? dh) {
  if (dw == null || dh == null || dw <= 0 || dh <= 0) return null;
  return '$dw×$dh';
}

/// Renders a frame rate from an mpv `estimated-vf-fps` string.
///
/// mpv answers like `23.976023`, `24.000000`, `0.000000` (unknown) or the empty
/// string. A zero / unparsable value means "no frame rate yet" and formats as
/// null — the caller then shows `--`.
String? formatFrameRate(String? raw) {
  if (raw == null) return null;
  final v = double.tryParse(raw.trim());
  if (v == null || v <= 0) return null;
  // Trim trailing noise: 23.976023 → 23.976, 24.000000 → 24.
  final rounded = double.parse(v.toStringAsFixed(3));
  final s = rounded == rounded.roundToDouble()
      ? rounded.round().toString()
      : rounded.toString();
  return '$s fps';
}

/// Renders a video bitrate from an mpv `video-bitrate` string (kilobits/sec).
///
/// Returns `2543 kbps`, or null when the property is absent/zero.
String? formatBitrate(String? raw) {
  if (raw == null) return null;
  final v = double.tryParse(raw.trim());
  if (v == null || v <= 0) return null;
  return '${v.round()} kbps';
}
