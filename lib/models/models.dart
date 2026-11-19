/// A playable title: movie, series, variety show or anime.
class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.score,
    this.tag,
    this.year,
    this.overview,
    this.posterSeed = 0,
    this.image,
  });

  final String id;
  final String title;
  final String? subtitle;

  /// Rating shown in the green badge, e.g. 9.3
  final double? score;

  /// Quality / language chip, e.g. TC国语, TC中字, 枪版
  final String? tag;
  final int? year;
  final String? overview;

  /// Deterministic placeholder palette index used when [image] is null.
  final int posterSeed;

  /// Bundled cover artwork, mirroring the poster the original caches locally.
  final String? image;
}

class Episode {
  const Episode({required this.index, required this.title, this.durationMs = 0});

  final int index;
  final String title;
  final int durationMs;
}

class ContinueWatching {
  const ContinueWatching({
    required this.media,
    required this.episodeLabel,
    required this.positionMs,
    required this.durationMs,
  });

  final MediaItem media;
  final String episodeLabel;
  final int positionMs;
  final int durationMs;

  double get progress => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  String get positionLabel {
    final total = positionMs ~/ 1000;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class HomeSection {
  const HomeSection({required this.title, required this.items});

  final String title;
  final List<MediaItem> items;
}

enum LcbPage { home, resources, favorites, history, settings }
