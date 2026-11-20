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
    this.latest,
    this.area,
    this.categories = const [],
    this.actors = const [],
    this.episodes = const [],
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

  /// Latest episode label as the source reports it, e.g. 第40集 / 全30集.
  final String? latest;

  /// Production region, e.g. 中国大陆.
  final String? area;

  /// Genre tags shown as chips, e.g. 剧情 / 爱情 / 古装.
  final List<String> categories;

  /// Cast names, shown in the detail page's 演员阵容 rail.
  final List<String> actors;

  /// Episode labels for series; empty for films.
  final List<String> episodes;
}

class Episode {
  const Episode({
    required this.index,
    required this.title,
    this.durationMs = 0,
  });

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

  double get progress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

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

// ---------------------------------------------------------------------------
// Persistence models (aligned with the original's shared_preferences keys)
// ---------------------------------------------------------------------------

/// One watch-history entry, matching the original's `flutter.history`. The
/// original keeps favourites in their own `flutter.favorites` store (see
/// [FavoriteEntry]); the legacy [isFavorite] / [isFollowing] flags here are
/// kept only for backward-compatible deserialization and are no longer used to
/// drive the favourites page.
class HistoryEntry {
  const HistoryEntry({
    required this.key,
    required this.sourceId,
    required this.title,
    required this.poster,
    required this.episode,
    required this.episodeIndex,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
    this.siteKey,
    this.vodId,
    this.flag,
    this.sourceName,
    this.sourceUrl,
    this.sourceType,
    this.isFavorite = false,
    this.isFollowing = false,
  });

  /// Composite id `sourceId|siteKey|vodId`, stable across sessions.
  final String key;
  final String sourceId;
  final String title;
  final String poster;
  final String episode;
  final int episodeIndex;
  final int positionMs;
  final int durationMs;
  final int updatedAt;

  /// Source payload, mirroring the original's `payload` object.
  final String? siteKey;
  final String? vodId;
  final String? flag;
  final String? sourceName;

  /// Cross-source locators the original stores alongside each history row so an
  /// entry can be resumed even after the active source changes.
  final String? sourceUrl;
  final String? sourceType;

  /// Favourites flags (the original folds favourites into history).
  final bool isFavorite;
  final bool isFollowing;

  double get progress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  /// A lightweight [MediaItem] view for grid rendering (favourites / follow).
  MediaItem toMediaItem() => MediaItem(
    id: key,
    title: title,
    tag: episode,
    image: poster.isEmpty ? null : poster,
    posterSeed: key.hashCode,
  );

  HistoryEntry copyWith({
    bool? isFavorite,
    bool? isFollowing,
    int? positionMs,
    int? updatedAt,
  }) {
    return HistoryEntry(
      key: key,
      sourceId: sourceId,
      title: title,
      poster: poster,
      episode: episode,
      episodeIndex: episodeIndex,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs,
      updatedAt: updatedAt ?? this.updatedAt,
      siteKey: siteKey,
      vodId: vodId,
      flag: flag,
      sourceName: sourceName,
      sourceUrl: sourceUrl,
      sourceType: sourceType,
      isFavorite: isFavorite ?? this.isFavorite,
      isFollowing: isFollowing ?? this.isFollowing,
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'sourceId': sourceId,
    'title': title,
    'poster': poster,
    'episode': episode,
    'episodeIndex': episodeIndex,
    'positionMs': positionMs,
    'durationMs': durationMs,
    'updatedAt': updatedAt,
    'payload': {
      if (siteKey != null) 'siteKey': siteKey,
      if (vodId != null) 'vodId': vodId,
      if (flag != null) 'flag': flag,
    },
    'sourceName': sourceName,
    if (sourceUrl != null) 'sourceUrl': sourceUrl,
    if (sourceType != null) 'sourceType': sourceType,
    if (isFavorite) 'favorite': true,
    if (isFollowing) 'following': true,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>? ?? const {};
    return HistoryEntry(
      key: json['key'] as String,
      sourceId: json['sourceId'] as String,
      title: json['title'] as String? ?? '',
      poster: json['poster'] as String? ?? '',
      episode: json['episode'] as String? ?? '',
      episodeIndex: json['episodeIndex'] as int? ?? 0,
      positionMs: json['positionMs'] as int? ?? 0,
      durationMs: json['durationMs'] as int? ?? 0,
      updatedAt: json['updatedAt'] as int? ?? 0,
      siteKey: payload['siteKey'] as String?,
      vodId: payload['vodId'] as String?,
      flag: payload['flag'] as String?,
      sourceName: json['sourceName'] as String?,
      sourceUrl: json['sourceUrl'] as String?,
      sourceType: json['sourceType'] as String?,
      isFavorite: json['favorite'] as bool? ?? false,
      isFollowing: json['following'] as bool? ?? false,
    );
  }
}

/// One content source (TVBox / 猫源 / Emby / WebDAV / AList), matching the
/// original's `flutter.sources` entries and its availability metrics.
class SourceInfo {
  const SourceInfo({
    required this.id,
    required this.type,
    required this.name,
    required this.url,
    this.username = '',
    this.password = '',
    this.latencyMs = 0,
    this.movieCount = 0,
    this.showCount = 0,
    this.checkedAt = 0,
  });

  final String id;
  final String type;
  final String name;
  final String url;
  final String username;
  final String password;
  final int latencyMs;
  final int movieCount;
  final int showCount;
  final int checkedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'name': name,
    'url': url,
    'username': username,
    'password': password,
    'latencyMs': latencyMs,
    'movieCount': movieCount,
    'showCount': showCount,
    'checkedAt': checkedAt,
  };

  factory SourceInfo.fromJson(Map<String, dynamic> json) => SourceInfo(
    id: json['id'] as String,
    type: json['type'] as String? ?? 'tvbox',
    name: json['name'] as String? ?? '',
    url: json['url'] as String? ?? '',
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    latencyMs: json['latencyMs'] as int? ?? 0,
    movieCount: json['movieCount'] as int? ?? 0,
    showCount: json['showCount'] as int? ?? 0,
    checkedAt: json['checkedAt'] as int? ?? 0,
  );
}

/// One favourite, matching the original's `flutter.favorites` array. The
/// original keeps favourites in their own store (NOT folded into history):
/// each entry references a [folderId] and carries a human-readable [latest]
/// label ("共 N 集") plus an [addedAt] timestamp.
class FavoriteEntry {
  const FavoriteEntry({
    required this.key,
    required this.sourceId,
    required this.title,
    required this.poster,
    this.siteKey,
    this.vodId,
    this.folderId,
    this.latest = '',
    this.addedAt = 0,
  });

  final String key;
  final String sourceId;
  final String title;
  final String poster;

  /// Source payload.
  final String? siteKey;
  final String? vodId;

  /// The folder this favourite belongs to (null = uncategorised).
  final String? folderId;

  /// Human-readable progress label, e.g. "共 2 集".
  final String latest;
  final int addedAt;

  MediaItem toMediaItem() => MediaItem(
    id: key,
    title: title,
    tag: latest.isEmpty ? null : latest,
    image: poster.isEmpty ? null : poster,
    posterSeed: key.hashCode,
  );

  /// Returns a copy moved to a different folder (null = uncategorised).
  FavoriteEntry copyWithFolder(String? folderId) => FavoriteEntry(
    key: key,
    sourceId: sourceId,
    title: title,
    poster: poster,
    siteKey: siteKey,
    vodId: vodId,
    folderId: folderId,
    latest: latest,
    addedAt: addedAt,
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'sourceId': sourceId,
    'title': title,
    'poster': poster,
    'payload': {
      if (siteKey != null) 'siteKey': siteKey,
      if (vodId != null) 'vodId': vodId,
    },
    if (folderId != null) 'folderId': folderId,
    'latest': latest,
    'addedAt': addedAt,
  };

  factory FavoriteEntry.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>? ?? const {};
    return FavoriteEntry(
      key: json['key'] as String,
      sourceId: json['sourceId'] as String,
      title: json['title'] as String? ?? '',
      poster: json['poster'] as String? ?? '',
      siteKey: payload['siteKey'] as String?,
      vodId: payload['vodId'] as String?,
      folderId: json['folderId'] as String?,
      latest: json['latest'] as String? ?? '',
      addedAt: json['addedAt'] as int? ?? 0,
    );
  }
}

/// A favourite folder (category), matching `flutter.favoriteFolders`. The
/// favourites page renders one tab per folder plus a leading "全部".
class FavoriteFolder {
  const FavoriteFolder({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory FavoriteFolder.fromJson(Map<String, dynamic> json) => FavoriteFolder(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
  );
}

/// Application settings, matching the original's `flutter.settings` map.
///
/// Only the fields the rebuilt UI currently reads/writes are modelled; the
/// rest of the original's ~80 keys are preserved verbatim in [extra] so a
/// round-trip never drops data the real source layer will need later.
class AppSettings {
  const AppSettings({
    this.themeMode = 'system',
    this.accent = '自定义',
    this.customAccent = 0,
    this.fontScale = 1.0,
    this.language = 'zh',
    this.liquidGlass = true,
    this.hideStatusBar = false,
    this.adaptiveColor = false,
    this.homeBannerEnabled = true,
    this.skipIntroOutro = true,
    this.shortDramaPreload = false,
    this.secondHome = true,
    this.homeCategoryButton = true,
    this.homePlatformButton = true,
    this.homeSourceButton = true,
    this.navStyle = 'glass',
    this.navBehavior = 'always',
    this.tvClassicUi = false,
    this.tvKeyboard = false,
    this.extra = const {},
  });

  final String themeMode;
  final String accent;
  final int customAccent;
  final double fontScale;
  final String language;
  final bool liquidGlass;
  final bool hideStatusBar;
  final bool adaptiveColor;
  final bool homeBannerEnabled;
  final bool skipIntroOutro;
  final bool shortDramaPreload;
  final bool secondHome;
  final bool homeCategoryButton;
  final bool homePlatformButton;
  final bool homeSourceButton;
  final String navStyle;
  final String navBehavior;
  final bool tvClassicUi;
  final bool tvKeyboard;

  /// Unmodelled keys carried through unchanged.
  final Map<String, dynamic> extra;

  AppSettings copyWith({
    String? themeMode,
    String? accent,
    int? customAccent,
    double? fontScale,
    String? language,
    bool? liquidGlass,
    bool? hideStatusBar,
    bool? adaptiveColor,
    bool? homeBannerEnabled,
    bool? skipIntroOutro,
    bool? shortDramaPreload,
    bool? secondHome,
    bool? homeCategoryButton,
    bool? homePlatformButton,
    bool? homeSourceButton,
    String? navStyle,
    String? navBehavior,
    bool? tvClassicUi,
    bool? tvKeyboard,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      accent: accent ?? this.accent,
      customAccent: customAccent ?? this.customAccent,
      fontScale: fontScale ?? this.fontScale,
      language: language ?? this.language,
      liquidGlass: liquidGlass ?? this.liquidGlass,
      hideStatusBar: hideStatusBar ?? this.hideStatusBar,
      adaptiveColor: adaptiveColor ?? this.adaptiveColor,
      homeBannerEnabled: homeBannerEnabled ?? this.homeBannerEnabled,
      skipIntroOutro: skipIntroOutro ?? this.skipIntroOutro,
      shortDramaPreload: shortDramaPreload ?? this.shortDramaPreload,
      secondHome: secondHome ?? this.secondHome,
      homeCategoryButton: homeCategoryButton ?? this.homeCategoryButton,
      homePlatformButton: homePlatformButton ?? this.homePlatformButton,
      homeSourceButton: homeSourceButton ?? this.homeSourceButton,
      navStyle: navStyle ?? this.navStyle,
      navBehavior: navBehavior ?? this.navBehavior,
      tvClassicUi: tvClassicUi ?? this.tvClassicUi,
      tvKeyboard: tvKeyboard ?? this.tvKeyboard,
      extra: extra,
    );
  }

  Map<String, dynamic> toJson() => {
    ...extra,
    'themeMode': themeMode,
    'accent': accent,
    'customAccent': customAccent,
    'fontScale': fontScale,
    'language': language,
    'liquidGlass': liquidGlass,
    'hideStatusBar': hideStatusBar,
    'adaptiveColor': adaptiveColor,
    'homeBannerEnabled': homeBannerEnabled,
    'skipIntroOutro': skipIntroOutro,
    'shortDramaPreload': shortDramaPreload,
    'secondHome': secondHome,
    'homeCategoryButton': homeCategoryButton,
    'homePlatformButton': homePlatformButton,
    'homeSourceButton': homeSourceButton,
    'navStyle': navStyle,
    'navBehavior': navBehavior,
    'tvClassicUi': tvClassicUi,
    'tvKeyboard': tvKeyboard,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    // The modelled keys are popped out; everything else survives in [extra].
    final extra = Map<String, dynamic>.from(json);
    T pop<T>(String key, T fallback) {
      if (extra.containsKey(key)) {
        final v = extra.remove(key);
        if (v is T) return v;
        if (v is num && T == double) return v.toDouble() as T;
        if (v is num && T == int) return v.toInt() as T;
      }
      return fallback;
    }

    return AppSettings(
      themeMode: pop('themeMode', 'system'),
      accent: pop('accent', '自定义'),
      customAccent: pop('customAccent', 0),
      fontScale: pop('fontScale', 1.0),
      language: pop('language', 'zh'),
      liquidGlass: pop('liquidGlass', true),
      hideStatusBar: pop('hideStatusBar', false),
      adaptiveColor: pop('adaptiveColor', false),
      homeBannerEnabled: pop('homeBannerEnabled', true),
      skipIntroOutro: pop('skipIntroOutro', true),
      shortDramaPreload: pop('shortDramaPreload', false),
      secondHome: pop('secondHome', true),
      homeCategoryButton: pop('homeCategoryButton', true),
      homePlatformButton: pop('homePlatformButton', true),
      homeSourceButton: pop('homeSourceButton', true),
      navStyle: pop('navStyle', 'glass'),
      navBehavior: pop('navBehavior', 'always'),
      tvClassicUi: pop('tvClassicUi', false),
      tvKeyboard: pop('tvKeyboard', false),
      extra: extra,
    );
  }
}
