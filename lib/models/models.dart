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
    this.playLines = const [],
    this.siteKey,
    this.sourceName,
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

  /// Playable lines (线路) and, within each, the play URL of every episode.
  /// Parsed from the catvod `vod_play_from` / `vod_play_url` fields a real
  /// detail payload carries. Empty until a real detail has been fetched; the
  /// demo catalogue has none.
  final List<PlayLine> playLines;

  /// Which site this record came from (`nodejs_jianpian`, …). Every card the
  /// pages render carries it, so the detail page can name the site in its
  /// 选集 filter row and history can say where a title was watched. Null only
  /// for fixtures that predate the source layer.
  final String? siteKey;

  /// Display name of the mount a record came from, for sources that have no
  /// site keys at all -- an Emby library has one library, not a list of sites.
  /// The detail page and the player print this instead of leaving the 选集 row
  /// saying 全部站点. Null for 猫源 records, whose [siteKey] resolves to a name.
  final String? sourceName;

  /// Same record, re-tagged with [siteKey]. Used when the store attributes
  /// fixture cards to the sites the config declared.
  MediaItem withSiteKey(String? siteKey) => MediaItem(
    id: id,
    title: title,
    subtitle: subtitle,
    score: score,
    tag: tag,
    year: year,
    overview: overview,
    posterSeed: posterSeed,
    image: image,
    latest: latest,
    area: area,
    categories: categories,
    actors: actors,
    episodes: episodes,
    playLines: playLines,
    siteKey: siteKey ?? this.siteKey,
    sourceName: sourceName,
  );

  /// Same record with the fields only a detail fetch can supply. Every
  /// argument is optional, so a caller fills in just what its source has --
  /// Emby, for instance, has no `vod_play_from` equivalent and only sets the
  /// play lines it synthesised.
  MediaItem withDetail({
    String? title,
    String? overview,
    String? latest,
    List<String>? categories,
    List<String>? actors,
    List<String>? episodes,
    List<PlayLine>? playLines,
  }) => MediaItem(
    id: id,
    title: title ?? this.title,
    subtitle: subtitle,
    score: score,
    tag: tag,
    year: year,
    overview: overview ?? this.overview,
    posterSeed: posterSeed,
    image: image,
    latest: latest ?? this.latest,
    area: area,
    categories: categories ?? this.categories,
    actors: actors ?? this.actors,
    episodes: episodes ?? this.episodes,
    playLines: playLines ?? this.playLines,
    siteKey: siteKey,
    sourceName: sourceName,
  );
}

/// One playable line (线路) of a title, e.g. 「直」蓝光 / 「盘」夸克. A source
/// detail payload lists every line in `vod_play_from` (separated by `$$$`) and
/// each line's episodes in the parallel `vod_play_url` field.
class PlayLine {
  const PlayLine({required this.name, this.episodes = const []});

  /// Line name as the source reports it, e.g. LZ线路.
  final String name;

  /// Playable episodes inside the line. Empty for a film, which carries a
  /// single entry (itself).
  final List<PlayEpisode> episodes;
}

/// One playable episode: a display label (第1集 / 正片) plus the URL that plays.
class PlayEpisode {
  const PlayEpisode({required this.label, required this.url});

  final String label;
  final String url;
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
    this.episodeIndex = 0,
  });

  final MediaItem media;
  final String episodeLabel;
  final int positionMs;
  final int durationMs;

  /// Which episode was being watched. Carried along so the card can reopen the
  /// work on that episode instead of always on the first one -- the label on
  /// the card says 第39集, and the detail page used to preselect 第1集.
  final int episodeIndex;

  double get progress =>
      durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  String get positionLabel {
    final total = positionMs ~/ 1000;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

/// A saved position that is worth resuming from, together with the total the
/// recording session measured.
///
/// The total travels with the position because a position only means something
/// against the timeline it was measured on. A source that splices a pre-roll ad
/// into the same stream records "12s of 15s"; replaying that as "seek to 12s"
/// against the real 42-minute feature drops the viewer into the ad break. Only
/// the player, which learns the real duration, can tell the two apart — see
/// `PlaybackClock` in `services/playback_clock.dart`.
class ResumePoint {
  const ResumePoint({required this.positionMs, required this.totalMs});

  final int positionMs;

  /// The duration the position was recorded against; 0 when the recording
  /// session never learned one.
  final int totalMs;

  Duration get position => Duration(milliseconds: positionMs);

  @override
  String toString() => 'ResumePoint($positionMs/$totalMs)';
}

class HomeSection {
  const HomeSection({required this.title, required this.items, this.typeId});

  final String title;
  final List<MediaItem> items;

  /// The site's own category id behind this rail, when it has one.
  ///
  /// 「查看全部」opens that category as a paged grid, and the grid is asked for
  /// by id, not by the rail's display name -- names repeat across sites and are
  /// localised. Null for a rail that is not a real category (a mount's 影片库).
  final String? typeId;
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
  ///
  /// The id is the source's vod id, not [key]: the key is `sourceId|site|vodId`
  /// and a detail lookup that sends it as `{id}` gets nothing back. Rows written
  /// before the vod id was stored fall back to the key, which is all they have.
  MediaItem toMediaItem() => MediaItem(
    id: vodId ?? key,
    title: title,
    tag: episode,
    image: poster.isEmpty ? null : poster,
    posterSeed: key.hashCode,
    siteKey: siteKey,
    sourceName: sourceName,
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

/// One site inside a source.
///
/// A TVBox / 猫源 source is not itself a site: it points at a config document
/// whose `sites` array lists the actual backends, and every search fans out to
/// those. The original never exposes them in the UI, which is why this rebuild
/// reads them out of the config instead of asking the user to type them.
///
/// [key] is the stable identifier the original also stores on history rows
/// (`flutter.history[].siteKey`), so it has to survive a config reload.
class SiteInfo {
  const SiteInfo({
    required this.key,
    required this.name,
    this.type = '',
    this.api = '',
    this.ext = '',
    this.enabled = true,
  });

  final String key;
  final String name;

  /// Raw catvod `type` (0 XML, 1 JSON, 3 spider, 4 …). Kept as text because the
  /// original writes it both ways.
  final String type;
  final String api;
  final String ext;

  /// Whether the site takes part in search. The original's config uses
  /// `searchable: 0` to opt out; parsed configs land here already filtered, but
  /// the user can still silence a noisy site from the editor.
  final bool enabled;

  SiteInfo copyWith({
    String? name,
    String? type,
    String? api,
    String? ext,
    bool? enabled,
  }) => SiteInfo(
    key: key,
    name: name ?? this.name,
    type: type ?? this.type,
    api: api ?? this.api,
    ext: ext ?? this.ext,
    enabled: enabled ?? this.enabled,
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    if (type.isNotEmpty) 'type': type,
    if (api.isNotEmpty) 'api': api,
    if (ext.isNotEmpty) 'ext': ext,
    if (!enabled) 'enabled': false,
  };

  factory SiteInfo.fromJson(Map<String, dynamic> json) => SiteInfo(
    key: json['key'] as String? ?? json['name'] as String? ?? '',
    name: json['name'] as String? ?? json['key'] as String? ?? '',
    type: '${json['type'] ?? ''}',
    api: json['api'] as String? ?? '',
    ext: json['ext'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
  );
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
    this.token = '',
    this.tokenUserId = '',
    this.latencyMs = 0,
    this.movieCount = 0,
    this.showCount = 0,
    this.checkedAt = 0,
    this.sites = const [],
    this.homeSite = '',
    this.channelCount = 0,
    this.groupName = '',
    this.iconId = '',
    this.iconPath = '',
  });

  final String id;
  final String type;
  final String name;
  final String url;
  final String username;
  final String password;

  /// The access token an Emby / Jellyfin login returned, plus the user id it
  /// belongs to. The password is never persisted -- a token is what the server
  /// actually re-uses, and it is revocable from the server side, which a stored
  /// password is not.
  final String token;
  final String tokenUserId;
  final int latencyMs;
  final int movieCount;
  final int showCount;
  final int checkedAt;

  /// The sites this source's config document declared. Empty until the config
  /// has been parsed (see `services/site_parser.dart`); every page that fans
  /// out over sites reads this rather than a hard-coded list.
  final List<SiteInfo> sites;

  /// Channels a local live list declared. Only `live` sources carry one; it is
  /// what the card shows instead of a site count.
  final int channelCount;

  /// The user's own group for this source. Empty means "group by type", which
  /// is what the original does when 分组名称 is left blank.
  final String groupName;

  /// An id from the bundled 图标包 (`assets/app_icons/icons.json`). Empty means
  /// "draw the glyph for this source's type", which is 原版's
  /// 「使用源自带图标；没有时显示默认图标」.
  final String iconId;

  /// An icon copied out of an imported 图标包 (or picked from a local file).
  /// It is stored per source on purpose: 原版 keeps applied icons after the
  /// pack is deleted, so the card must not point back into the pack folder.
  final String iconPath;

  /// The site the home feed is drawn from, matching the original's
  /// `homeSite` (`nodejs_jianpian`). Empty when the config has not named one;
  /// the store then falls back to the first active site.
  final String homeSite;

  /// Sites that should take part in search and category fetches.
  List<SiteInfo> get searchableSites =>
      sites.where((site) => site.enabled).toList(growable: false);

  SourceInfo copyWith({
    String? name,
    String? url,
    String? username,
    String? password,
    String? token,
    String? tokenUserId,
    int? latencyMs,
    int? movieCount,
    int? showCount,
    int? checkedAt,
    List<SiteInfo>? sites,
    String? homeSite,
    int? channelCount,
    String? groupName,
    String? iconId,
    String? iconPath,
  }) => SourceInfo(
    id: id,
    type: type,
    name: name ?? this.name,
    url: url ?? this.url,
    username: username ?? this.username,
    password: password ?? this.password,
    token: token ?? this.token,
    tokenUserId: tokenUserId ?? this.tokenUserId,
    latencyMs: latencyMs ?? this.latencyMs,
    movieCount: movieCount ?? this.movieCount,
    showCount: showCount ?? this.showCount,
    checkedAt: checkedAt ?? this.checkedAt,
    sites: sites ?? this.sites,
    homeSite: homeSite ?? this.homeSite,
    channelCount: channelCount ?? this.channelCount,
    groupName: groupName ?? this.groupName,
    iconId: iconId ?? this.iconId,
    iconPath: iconPath ?? this.iconPath,
  );

  /// Replaces one site by key, leaving the rest in order. Used by the editor to
  /// silence or re-enable a single site.
  SourceInfo withSite(SiteInfo updated) => copyWith(
    sites: [
      for (final site in sites)
        if (site.key == updated.key) updated else site,
    ],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'name': name,
    'url': url,
    'username': username,
    'password': password,
    // Omitted while empty: every source written before mounts existed keeps the
    // exact shape it had, and no other source type carries a token.
    if (token.isNotEmpty) 'token': token,
    if (tokenUserId.isNotEmpty) 'tokenUserId': tokenUserId,
    'latencyMs': latencyMs,
    'movieCount': movieCount,
    'showCount': showCount,
    'checkedAt': checkedAt,
    // Omitted while empty so sources written before sites existed keep the
    // exact shape the original produces.
    if (sites.isNotEmpty) 'sites': sites.map((e) => e.toJson()).toList(),
    if (homeSite.isNotEmpty) 'homeSite': homeSite,
    if (channelCount != 0) 'channelCount': channelCount,
    if (groupName.isNotEmpty) 'groupName': groupName,
    if (iconId.isNotEmpty) 'iconId': iconId,
    if (iconPath.isNotEmpty) 'iconPath': iconPath,
  };

  factory SourceInfo.fromJson(Map<String, dynamic> json) => SourceInfo(
    id: json['id'] as String,
    type: json['type'] as String? ?? 'tvbox',
    name: json['name'] as String? ?? '',
    url: json['url'] as String? ?? '',
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    token: json['token'] as String? ?? '',
    tokenUserId: json['tokenUserId'] as String? ?? '',
    latencyMs: json['latencyMs'] as int? ?? 0,
    movieCount: json['movieCount'] as int? ?? 0,
    showCount: json['showCount'] as int? ?? 0,
    checkedAt: json['checkedAt'] as int? ?? 0,
    sites: [
      for (final raw in (json['sites'] as List?) ?? const [])
        if (raw is Map) SiteInfo.fromJson(Map<String, dynamic>.from(raw)),
    ],
    homeSite: json['homeSite'] as String? ?? '',
    channelCount: json['channelCount'] as int? ?? 0,
    groupName: json['groupName'] as String? ?? '',
    iconId: json['iconId'] as String? ?? '',
    iconPath: json['iconPath'] as String? ?? '',
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
    id: vodId ?? key,
    title: title,
    tag: latest.isEmpty ? null : latest,
    image: poster.isEmpty ? null : poster,
    posterSeed: key.hashCode,
    siteKey: siteKey,
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
    this.introSkipMs = 0,
    this.outroSkipMs = 0,
    this.skipOverrides = const {},
    this.shortDramaPreload = false,
    this.secondHome = true,
    this.homeCategoryButton = true,
    this.homePlatformButton = true,
    this.homeSourceButton = true,
    this.navStyle = 'glass',
    this.navBehavior = 'always',
    this.tvClassicUi = false,
    this.tvKeyboard = false,
    this.playerVolume = 100,
    this.playerRate = 1.0,
    this.aspectFit = 'fit',
    this.pictureAdjust = const {},
    this.playerInfoFields = '',
    this.miniProgress = false,
    this.subtitlePref = 'auto',
    this.subtitleSize = 32,
    this.secondarySubtitle = 'off',
    this.externalSubtitles = const {},
    this.danmakuEnabled = true,
    this.danmakuBlockTop = false,
    this.danmakuBlockBottom = false,
    this.danmakuSources = const [],
    this.trackPrefs = const {},
    this.mediaBadgesEnabled = true,
    this.badgeSpot = 'leftTop',
    this.badgeText = false,
    this.badgeSpecs = const {},
    this.customPages = const [],
    this.homePageId = '',
    this.widgetRepos = const [],
    this.widgetItems = const [],
    this.widgetProxy = const {},
    this.tmdbApiKey = '',
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

  /// How long the intro and the credits are, in milliseconds, as the viewer
  /// told us once. Zero means "not set" — the app never guesses a cut point,
  /// because the sources do not report one.
  final int introSkipMs;
  final int outroSkipMs;

  /// 每个作品单独设的片头/片尾，按作品名索引：
  /// `{'三体': {'intro': 90000}}`。没在这张表里的作品用上面那一组全局值。
  ///
  /// 只存用户显式改过的那一半——`{'outro': 60000}` 表示片头仍跟随全局。
  /// 保持成原始 JSON 的原因和 [trackPrefs] 一样：模型层不能 import services，
  /// 语义解释（[SkipOverride]）在 `services/skip_rule.dart`。
  final Map<String, Map<String, int>> skipOverrides;

  final bool shortDramaPreload;
  final bool secondHome;
  final bool homeCategoryButton;
  final bool homePlatformButton;
  final bool homeSourceButton;
  final String navStyle;
  final String navBehavior;
  final bool tvClassicUi;
  final bool tvKeyboard;

  /// Volume (0-100) and speed the player opens with. Carried across sessions
  /// because a viewer who muted or slowed the last episode wants the same
  /// again for the next one, not a reset to 100 / 1.0×.
  final int playerVolume;
  final double playerRate;

  /// 画面比例短码（`fit` / `stretch` / `fill` / `fitWidth` / `fitHeight` /
  /// `crop`）。语义在 `services/picture.dart` 的 `AspectMode`，模型层只存短码。
  final String aspectFit;

  /// 画面调节五个量（亮度/对比度/饱和度/色相/伽马），`{'brightness': -20}`，
  /// 值域 -100..100，缺省 = 原始画面。语义在 `services/picture.dart` 的
  /// `PictureAdjust`，模型层只存原始 JSON。
  final Map<String, int> pictureAdjust;

  /// 播放页常驻信息浮层要显示哪些信息（`resolution` / `frameRate` /
  /// `bitrate`），逗号分隔、按此顺序排列。空串 = 不显示浮层。语义在
  /// `services/player_info.dart` 的 `PlayerInfoField`，模型层只存短码串。
  final String playerInfoFields;

  /// 播放页最底下的「迷你进度条」：一条常驻细线（蓝=已播、浅蓝=已缓冲），
  /// 不随操作菜单隐藏。原版在设置里叫「迷你进度条」。
  final bool miniProgress;

  /// 默认字幕偏好：`auto` / `zh` / `zh-en` / `multi` / `en` / `ja` / `ko` /
  /// `off`。语义在 `services/track_choice.dart` 的 `SubtitlePref`，模型层只存
  /// 这个短码。
  final String subtitlePref;

  /// 字幕文字大小（逻辑像素）。media_kit 在桌面上把字幕当 Flutter 文本画，
  /// 所以这是一个真实的排版值，不是 mpv 的属性。
  final int subtitleSize;

  /// 次字幕：`off` / `zh` / `en` / `ja` / `ko`。显示在画面上方，和主字幕组成
  /// 双语对照；语义在 `SecondarySubtitle`。
  final String secondarySubtitle;

  /// 这一集挂过的本地字幕文件：`{'<作品id>|ep<集>': 'D:/subs/01.ass'}`。
  ///
  /// 原版的说法是「下载的字幕记在这一集上，下次播这一集会自动挂上」，
  /// 所以这里按集存路径，不按作品。文件被删掉时播放页会当作没记过。
  final Map<String, String> externalSubtitles;

  /// 弹幕总开关。关掉之后播放页不再向弹幕源发请求，画面上也不再叠一层。
  final bool danmakuEnabled;

  /// 屏蔽顶部 / 底部固定弹幕——护住画面下沿的字幕和控制条。滚动弹幕不受影响。
  final bool danmakuBlockTop;
  final bool danmakuBlockBottom;

  /// 弹幕源表：`[{'id': 'mine', 'name': '自建', 'baseUrl': '…'}]`。
  ///
  /// 和 [trackPrefs] 一样保持原始 JSON：模型层不认识 `DanmakuSource`
  /// （`services/danmaku/danmaku_api.dart`），解析与校验都在服务层。
  final List<Map<String, Object?>> danmakuSources;

  /// 每条线路记住的轨道选择：`{'<作品id>|<线路名>': {'audio': '2'}}`。
  ///
  /// 存的是 mpv 的 track id，所以换集/换源之后由播放页核对一遍再用，见
  /// `services/track_choice.dart`。这里保持成原始 JSON，是因为 [AppSettings]
  /// 不依赖 services 层（模型包不能反过来 import 服务）。
  final Map<String, Map<String, String>> trackPrefs;

  /// 媒体规格徽章（4K、HDR10、杜比视界、DTS…）的显示开关与位置。
  /// 识别逻辑在 `services/badge_rule.dart`，这里只存「要不要显示」。
  final bool mediaBadgesEnabled;

  /// 徽章摆在海报的哪个角：`leftTop` / `rightTop` / `leftBottom` / `rightBottom`。
  final String badgeSpot;

  /// 徽章是否带文字（如「杜比视界」），否则只显示短标（如「DV」）。
  final bool badgeText;

  /// 各类规格的细开关：`{'hdr10': false}` 表示不显示 HDR10。缺省的键视为开。
  final Map<String, bool> badgeSpecs;

  /// 自定义页面表，保持原始 JSON：页面/组件区域的语义在
  /// `services/widgets/widget_models.dart`，模型包不反过来 import 服务。
  final List<Map<String, dynamic>> customPages;

  /// 首页当前显示的自定义页面 id。空表示用资源自己的首页。
  final String homePageId;

  /// 导入的组件仓库、组件元数据与本机代理配置，保持原始 JSON：
  /// 语义在 `services/widgets/widget_models.dart`。
  final List<Map<String, dynamic>> widgetRepos;
  final List<Map<String, dynamic>> widgetItems;
  final Map<String, dynamic> widgetProxy;

  /// 用户自己的 TMDB v3 Key，只保存在本机，不进备份（原版明文）。
  final String tmdbApiKey;

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
    int? introSkipMs,
    int? outroSkipMs,
    Map<String, Map<String, int>>? skipOverrides,
    bool? shortDramaPreload,
    bool? secondHome,
    bool? homeCategoryButton,
    bool? homePlatformButton,
    bool? homeSourceButton,
    String? navStyle,
    String? navBehavior,
    bool? tvClassicUi,
    bool? tvKeyboard,
    int? playerVolume,
    double? playerRate,
    String? aspectFit,
    Map<String, int>? pictureAdjust,
    String? playerInfoFields,
    bool? miniProgress,
    String? subtitlePref,
    int? subtitleSize,
    String? secondarySubtitle,
    Map<String, String>? externalSubtitles,
    bool? danmakuEnabled,
    bool? danmakuBlockTop,
    bool? danmakuBlockBottom,
    List<Map<String, Object?>>? danmakuSources,
    Map<String, Map<String, String>>? trackPrefs,
    bool? mediaBadgesEnabled,
    String? badgeSpot,
    bool? badgeText,
    Map<String, bool>? badgeSpecs,
    List<Map<String, dynamic>>? customPages,
    String? homePageId,
    List<Map<String, dynamic>>? widgetRepos,
    List<Map<String, dynamic>>? widgetItems,
    Map<String, dynamic>? widgetProxy,
    String? tmdbApiKey,
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
      introSkipMs: introSkipMs ?? this.introSkipMs,
      outroSkipMs: outroSkipMs ?? this.outroSkipMs,
      skipOverrides: skipOverrides ?? this.skipOverrides,
      shortDramaPreload: shortDramaPreload ?? this.shortDramaPreload,
      secondHome: secondHome ?? this.secondHome,
      homeCategoryButton: homeCategoryButton ?? this.homeCategoryButton,
      homePlatformButton: homePlatformButton ?? this.homePlatformButton,
      homeSourceButton: homeSourceButton ?? this.homeSourceButton,
      navStyle: navStyle ?? this.navStyle,
      navBehavior: navBehavior ?? this.navBehavior,
      tvClassicUi: tvClassicUi ?? this.tvClassicUi,
      tvKeyboard: tvKeyboard ?? this.tvKeyboard,
      playerVolume: playerVolume ?? this.playerVolume,
      playerRate: playerRate ?? this.playerRate,
      aspectFit: aspectFit ?? this.aspectFit,
      pictureAdjust: pictureAdjust ?? this.pictureAdjust,
      playerInfoFields: playerInfoFields ?? this.playerInfoFields,
      miniProgress: miniProgress ?? this.miniProgress,
      subtitlePref: subtitlePref ?? this.subtitlePref,
      subtitleSize: subtitleSize ?? this.subtitleSize,
      secondarySubtitle: secondarySubtitle ?? this.secondarySubtitle,
      externalSubtitles: externalSubtitles ?? this.externalSubtitles,
      danmakuEnabled: danmakuEnabled ?? this.danmakuEnabled,
      danmakuBlockTop: danmakuBlockTop ?? this.danmakuBlockTop,
      danmakuBlockBottom: danmakuBlockBottom ?? this.danmakuBlockBottom,
      danmakuSources: danmakuSources ?? this.danmakuSources,
      trackPrefs: trackPrefs ?? this.trackPrefs,
      mediaBadgesEnabled: mediaBadgesEnabled ?? this.mediaBadgesEnabled,
      badgeSpot: badgeSpot ?? this.badgeSpot,
      badgeText: badgeText ?? this.badgeText,
      badgeSpecs: badgeSpecs ?? this.badgeSpecs,
      customPages: customPages ?? this.customPages,
      homePageId: homePageId ?? this.homePageId,
      widgetRepos: widgetRepos ?? this.widgetRepos,
      widgetItems: widgetItems ?? this.widgetItems,
      widgetProxy: widgetProxy ?? this.widgetProxy,
      tmdbApiKey: tmdbApiKey ?? this.tmdbApiKey,
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
    'introSkipMs': introSkipMs,
    'outroSkipMs': outroSkipMs,
    'skipOverrides': skipOverrides,
    'shortDramaPreload': shortDramaPreload,
    'secondHome': secondHome,
    'homeCategoryButton': homeCategoryButton,
    'homePlatformButton': homePlatformButton,
    'homeSourceButton': homeSourceButton,
    'navStyle': navStyle,
    'navBehavior': navBehavior,
    'tvClassicUi': tvClassicUi,
    'tvKeyboard': tvKeyboard,
    'playerVolume': playerVolume,
    'playerRate': playerRate,
    'aspectFit': aspectFit,
    'pictureAdjust': pictureAdjust,
    'playerInfoFields': playerInfoFields,
    'miniProgress': miniProgress,
    'subtitlePref': subtitlePref,
    'subtitleSize': subtitleSize,
    'secondarySubtitle': secondarySubtitle,
    'externalSubtitles': externalSubtitles,
    'danmakuEnabled': danmakuEnabled,
    'danmakuBlockTop': danmakuBlockTop,
    'danmakuBlockBottom': danmakuBlockBottom,
    'danmakuSources': danmakuSources,
    'trackPrefs': trackPrefs,
    'mediaBadgesEnabled': mediaBadgesEnabled,
    'badgeSpot': badgeSpot,
    'badgeText': badgeText,
    'badgeSpecs': badgeSpecs,
    'customPages': [
      for (final page in customPages) Map<String, dynamic>.from(page),
    ],
    'homePageId': homePageId,
    'widgetRepos': [
      for (final repo in widgetRepos) Map<String, dynamic>.from(repo),
    ],
    'widgetItems': [
      for (final item in widgetItems) Map<String, dynamic>.from(item),
    ],
    'widgetProxy': Map<String, dynamic>.from(widgetProxy),
    'tmdbApiKey': tmdbApiKey,
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
      introSkipMs: pop('introSkipMs', 0),
      outroSkipMs: pop('outroSkipMs', 0),
      skipOverrides: _readSkipOverrides(extra.remove('skipOverrides')),
      shortDramaPreload: pop('shortDramaPreload', false),
      secondHome: pop('secondHome', true),
      homeCategoryButton: pop('homeCategoryButton', true),
      homePlatformButton: pop('homePlatformButton', true),
      homeSourceButton: pop('homeSourceButton', true),
      navStyle: pop('navStyle', 'glass'),
      navBehavior: pop('navBehavior', 'always'),
      tvClassicUi: pop('tvClassicUi', false),
      tvKeyboard: pop('tvKeyboard', false),
      playerVolume: pop('playerVolume', 100),
      playerRate: pop('playerRate', 1.0),
      aspectFit: pop('aspectFit', 'fit'),
      pictureAdjust: _readIntMap(extra.remove('pictureAdjust')),
      playerInfoFields: pop('playerInfoFields', ''),
      miniProgress: pop('miniProgress', false),
      subtitlePref: _readSubtitlePref(extra.remove('subtitlePref')),
      subtitleSize: _readSubtitleSize(extra.remove('subtitleSize')),
      secondarySubtitle: _readSecondarySubtitle(
        extra.remove('secondarySubtitle'),
      ),
      externalSubtitles: _readStringMap(extra.remove('externalSubtitles')),
      danmakuEnabled: pop('danmakuEnabled', true),
      danmakuBlockTop: pop('danmakuBlockTop', false),
      danmakuBlockBottom: pop('danmakuBlockBottom', false),
      danmakuSources: _readDanmakuSources(extra.remove('danmakuSources')),
      trackPrefs: _readTrackPrefs(extra.remove('trackPrefs')),
      mediaBadgesEnabled: pop('mediaBadgesEnabled', true),
      badgeSpot: pop('badgeSpot', 'leftTop'),
      badgeText: pop('badgeText', false),
      badgeSpecs: _readBadgeSpecs(extra.remove('badgeSpecs')),
      customPages: [
        for (final raw in (extra.remove('customPages') as List?) ?? const [])
          if (raw is Map) Map<String, dynamic>.from(raw),
      ],
      homePageId: pop('homePageId', ''),
      widgetRepos: [
        for (final raw in (extra.remove('widgetRepos') as List?) ?? const [])
          if (raw is Map) Map<String, dynamic>.from(raw),
      ],
      widgetItems: [
        for (final raw in (extra.remove('widgetItems') as List?) ?? const [])
          if (raw is Map) Map<String, dynamic>.from(raw),
      ],
      widgetProxy: _readStringMap(extra.remove('widgetProxy')),
      tmdbApiKey: pop('tmdbApiKey', ''),
      extra: extra,
    );
  }
}

/// 字幕偏好的合法短码。认不出的值退回 `auto`，写坏一个偏好不该拖垮设置。
const _subtitlePrefSlugs = {
  'auto',
  'zh',
  'zh-en',
  'multi',
  'en',
  'ja',
  'ko',
  'off',
};

String _readSubtitlePref(Object? raw) =>
    raw is String && _subtitlePrefSlugs.contains(raw) ? raw : 'auto';

const _secondarySubtitleSlugs = {'off', 'zh', 'en', 'ja', 'ko'};

String _readSecondarySubtitle(Object? raw) =>
    raw is String && _secondarySubtitleSlugs.contains(raw) ? raw : 'off';

/// 只收「键和值都是非空字符串」的条目；一张写坏的表退回空表，而不是让设置
/// 整体加载失败。
Map<String, String> _readStringMap(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, String>{};
  raw.forEach((k, v) {
    if (k is String && k.isNotEmpty && v is String && v.isNotEmpty) {
      out[k] = v;
    }
  });
  return out;
}

/// `{'brightness': -20}` → 强类型整数表。值钳到 -100..100（画面调节值域），
/// 非数值的键整条丢弃。
Map<String, int> _readIntMap(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, int>{};
  raw.forEach((k, v) {
    if (k is! String || k.isEmpty || v is! num) return;
    out[k] = v.toInt().clamp(-100, 100);
  });
  return out;
}

/// 字号限制在 16–96 之间：更小的看不清，更大的会盖住半个画面。
int _readSubtitleSize(Object? raw) {
  if (raw is! num) return 32;
  final v = raw.toInt();
  if (v < 16) return 16;
  if (v > 96) return 96;
  return v;
}

/// `{'<key>': {'audio': '2'}}` → 强类型。任何一层不是字符串就整条丢掉，
/// 一份坏掉的记忆只该让那条线路回到默认，不该让设置加载失败。
Map<String, Map<String, String>> _readTrackPrefs(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, Map<String, String>>{};
  raw.forEach((key, value) {
    if (key is! String || key.isEmpty || value is! Map) return;
    final entry = <String, String>{};
    value.forEach((k, v) {
      if (k is! String || k.isEmpty) return;
      if (v is String && v.isNotEmpty) {
        entry[k] = v;
      } else if (v is num) {
        entry[k] = v.toInt().toString();
      }
    });
    if (entry.isNotEmpty) out[key] = entry;
  });
  return out;
}

/// 弹幕源表。只有带 `id` 和 `name` 的条目才算数；`baseUrl` 缺省补官方地址。
/// 一条写坏的源只丢掉自己，不该让整份设置加载失败。
List<Map<String, Object?>> _readDanmakuSources(Object? raw) {
  if (raw is! List) return const [];
  final out = <Map<String, Object?>>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final id = '${item['id'] ?? ''}'.trim();
    final name = '${item['name'] ?? ''}'.trim();
    if (id.isEmpty || name.isEmpty) continue;
    out.add({
      'id': id,
      'name': name,
      'baseUrl': '${item['baseUrl'] ?? ''}',
      'appId': '${item['appId'] ?? ''}',
      'appSecret': '${item['appSecret'] ?? ''}',
      'enabled': item['enabled'] != false,
    });
  }
  return out;
}

/// `{'三体': {'intro': 90000}}` → 强类型。作品名为空、值不是正数、两个字段
/// 都没有的条目整条丢掉——一条坏掉的本剧设置只该让那部剧回到全局值。
Map<String, Map<String, int>> _readSkipOverrides(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, Map<String, int>>{};
  raw.forEach((key, value) {
    if (key is! String || key.isEmpty || value is! Map) return;
    final entry = <String, int>{};
    for (final field in const ['intro', 'outro']) {
      final v = value[field];
      if (v is num) {
        // 0 is meaningful here: "this work explicitly has no intro", which is
        // different from "inherit the global value".
        final ms = v.toInt();
        if (ms >= 0) entry[field] = ms;
      }
    }
    if (entry.isNotEmpty) out[key] = entry;
  });
  return out;
}

/// `{'hdr10': false}` → 强类型。坏值整条丢掉，一份坏掉的开关只该回到默认
/// 全开，不该让设置加载失败。
Map<String, bool> _readBadgeSpecs(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, bool>{};
  raw.forEach((key, value) {
    if (key is! String || key.isEmpty) return;
    if (value is bool) {
      out[key] = value;
    }
  });
  return out;
}
