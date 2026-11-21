import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/models.dart';
import 'source_probe.dart' show ProbeReport;

/// A server that refused a request, carrying a message written for the UI.
///
/// The client never lets a raw [SocketException] / [FormatException] escape:
/// every caller is a page or a probe, and "Connection refused" is not something
/// a user can act on. [statusCode] is kept for tests and for telling "wrong
/// password" (401) apart from "server is down" (no code at all).
class EmbyException implements Exception {
  const EmbyException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// What a successful login produced. The password is not part of it.
class EmbyAuth {
  const EmbyAuth({
    required this.token,
    required this.userId,
    this.serverName = '',
  });

  final String token;
  final String userId;

  /// The server's reported name, shown on the source card when it has one.
  final String serverName;
}

/// Read-only client for an Emby / Jellyfin server.
///
/// Covers the four things this app needs: log in ([authenticate]), list the
/// library ([library] / [search]), read one title with its episodes ([detail]),
/// and build a direct-play URL ([streamUrl]). Everything is JSON over HTTP with
/// an `api_key` query parameter after login -- the same protocol Jellyfin
/// speaks, so one client serves both source types.
///
/// Deliberately stateless apart from [baseUrl] / [token] / [userId]: the store
/// builds one per request from the persisted source, so a re-login or an edited
/// address takes effect without any cache to invalidate.
class EmbyClient {
  /// [http] is only passed by tests: a shared client is then left open on
  /// [close], because the caller owns its lifetime.
  factory EmbyClient({
    required String baseUrl,
    required String token,
    required String userId,
    String sourceName = '',
    HttpClient? http,
    Duration timeout = const Duration(seconds: 10),
  }) => EmbyClient._(
    baseUrl: _normalize(baseUrl),
    token: token,
    userId: userId,
    sourceName: sourceName,
    http: http,
    ownsHttp: http == null,
    timeout: timeout,
  );

  EmbyClient._({
    required this.baseUrl,
    required this.token,
    required this.userId,
    required this.sourceName,
    required HttpClient? http,
    required bool ownsHttp,
    required this.timeout,
  }) : _http = http ?? HttpClient(),
       // ignore: prefer_initializing_formals
       _ownsHttp = ownsHttp;

  /// Address without a trailing slash, so every path join is `$base/x`.
  final String baseUrl;
  final String token;
  final String userId;
  final Duration timeout;

  /// The mount's display name, stamped onto every record this client produces
  /// so the detail page and the player can say where a title came from. A mount
  /// has no site keys to resolve a name from.
  final String sourceName;

  /// Owned only when the caller did not supply one, so a shared client passed
  /// in by tests is never closed from here.
  final HttpClient _http;
  final bool _ownsHttp;

  /// Logs in and exchanges a password for a long-lived token.
  ///
  /// This is the only call that sends the password; nothing stores it. A 401 is
  /// reported as "wrong account or password" rather than as a status code,
  /// because that is the one failure a user can fix.
  static Future<EmbyAuth> authenticate({
    required String baseUrl,
    required String username,
    required String password,
    HttpClient? http,
    Duration timeout = const Duration(seconds: 10),
    String deviceId = 'lai-cui-ba-windows',
  }) async {
    final base = _normalize(baseUrl);
    final client = EmbyClient._(
      baseUrl: base,
      token: '',
      userId: '',
      sourceName: '',
      http: http,
      ownsHttp: http == null,
      timeout: timeout,
    );
    try {
      final uri = Uri.parse('$base/Users/AuthenticateByName');
      final result = await client._send(
        'POST',
        uri,
        body: jsonEncode({'Username': username, 'Pw': password}),
        headers: {
          'Content-Type': 'application/json',
          'X-Emby-Authorization':
              'MediaBrowser Client="LaiCuiBa", Device="Windows", '
              'DeviceId="$deviceId", Version="1.0.0"',
        },
      );
      if (result.status == 401 || result.status == 403) {
        throw const EmbyException('账号或密码不对（服务器拒绝了登录）');
      }
      if (result.status < 200 || result.status >= 300) {
        throw EmbyException(_describeStatus(result.status));
      }
      final json = result.json;
      final token = '${json['AccessToken'] ?? ''}';
      final user = json['User'];
      final id = user is Map ? '${user['Id'] ?? ''}' : '';
      if (token.isEmpty || id.isEmpty) {
        throw const EmbyException('服务器没有返回令牌，可能不是 Emby / Jellyfin');
      }
      return EmbyAuth(
        token: token,
        userId: id,
        serverName: '${json['ServerName'] ?? ''}',
      );
    } finally {
      client.close();
    }
  }

  /// Movies and series, newest first. Used by the home rails.
  Future<List<MediaItem>> library({int limit = 24}) async {
    return _items(
      Uri.parse('$baseUrl/Users/$userId/Items').replace(
        queryParameters: {
          'api_key': token,
          'Recursive': 'true',
          'IncludeItemTypes': 'Movie,Series',
          'SortBy': 'DateCreated,SortName',
          'SortOrder': 'Descending',
          'Limit': '$limit',
          'ImageTypeLimit': '1',
          'Fields': _fields,
        },
      ),
    );
  }

  /// Titles whose name matches [term]. Empty string matches the whole library,
  /// which is what "show me everything" means here.
  Future<List<MediaItem>> search(String term, {int limit = 60}) async {
    final query = <String, String>{
      'api_key': token,
      'Recursive': 'true',
      'IncludeItemTypes': 'Movie,Series',
      'Limit': '$limit',
      'ImageTypeLimit': '1',
      'Fields': _fields,
    };
    if (term.trim().isNotEmpty) {
      query['SearchTerm'] = term.trim();
    } else {
      query['SortBy'] = 'DateCreated,SortName';
      query['SortOrder'] = 'Descending';
    }
    return _items(
      Uri.parse('$baseUrl/Users/$userId/Items').replace(
        queryParameters: query,
      ),
    );
  }

  /// Library size, for the source card's `当前使用 · N 部`.
  Future<({int movies, int series, int episodes})> counts() async {
    final json = await _get(
      Uri.parse('$baseUrl/Items/Counts').replace(
        queryParameters: {'api_key': token},
      ),
    );
    int at(String key) {
      final raw = json[key];
      if (raw is int) return raw;
      return int.tryParse('${raw ?? ''}') ?? 0;
    }

    return (
      movies: at('MovieCount'),
      series: at('SeriesCount'),
      episodes: at('EpisodeCount'),
    );
  }

  /// Fills in what a list row cannot carry: the overview, the cast, and -- for
  /// a series -- every episode's playable URL.
  ///
  /// The returned item keeps [item]'s title and poster, so the detail page
  /// never flashes an empty shell. A movie gets a single 正片 entry; a series
  /// gets one entry per episode, which is exactly the shape the 选集 row and
  /// the player's episode list already consume.
  Future<MediaItem> detail(MediaItem item) async {
    List<MediaItem> episodes = const [];
    if (item.latest != null && item.latest!.isNotEmpty) {
      // `latest` is set for a series by [_toItem]; fetch the real episode list.
      episodes = await _items(
        Uri.parse('$baseUrl/Shows/${item.id}/Episodes').replace(
          queryParameters: {
            'api_key': token,
            'UserId': userId,
            'Fields': 'Overview,PrimaryImageAspectRatio',
            'ImageTypeLimit': '0',
          },
        ),
        isEpisode: true,
      );
    }

    if (episodes.isEmpty) {
      return item.withDetail(
        playLines: [
          PlayLine(
            name: _lineName,
            episodes: [
              PlayEpisode(label: '正片', url: streamUrl(item.id)),
            ],
          ),
        ],
      );
    }

    final labels = <String>[];
    final plays = <PlayEpisode>[];
    for (var i = 0; i < episodes.length; i++) {
      final episode = episodes[i];
      final label = episode.title.isEmpty ? '第${i + 1}集' : episode.title;
      labels.add(label);
      plays.add(PlayEpisode(label: label, url: streamUrl(episode.id)));
    }
    return item.withDetail(
      overview: item.overview ?? episodes.first.overview,
      episodes: labels,
      playLines: [PlayLine(name: _lineName, episodes: plays)],
    );
  }

  /// Direct-play URL for one item. `static=true` asks the server to remux
  /// nothing and serve the file as stored, which is the only thing a local
  /// player can rely on across every container the server may hold.
  String streamUrl(String itemId) {
    final query = Uri(
      queryParameters: {
        'static': 'true',
        'MediaSourceId': itemId,
        'api_key': token,
      },
    ).query;
    return '$baseUrl/Videos/$itemId/stream?$query';
  }

  /// Measures the mount by listing its library, in the same shape a 猫源 probe
  /// reports, so the source card and `重新检测` treat both kinds alike.
  Future<ProbeReport> probe() async {
    final watch = Stopwatch()..start();
    try {
      final size = await counts();
      final items = await library(limit: 24);
      watch.stop();
      if (items.isEmpty) {
        return ProbeReport(
          latencyMs: watch.elapsedMilliseconds,
          movieCount: 0,
          showCount: size.series,
          note: '连上了，但影片库是空的',
        );
      }
      return ProbeReport(
        latencyMs: watch.elapsedMilliseconds,
        movieCount: size.movies,
        showCount: size.series,
      );
    } on EmbyException catch (e) {
      watch.stop();
      return ProbeReport.failure(
        e.message,
        latencyMs: watch.elapsedMilliseconds,
      );
    } catch (e) {
      watch.stop();
      return ProbeReport.failure(
        '连不上服务器：$e',
        latencyMs: watch.elapsedMilliseconds,
      );
    }
  }

  void close() {
    if (_ownsHttp) _http.close(force: true);
  }

  // ---------------------------------------------------------------------------
  // Plumbing
  // ---------------------------------------------------------------------------

  /// Fields a list row needs to render a card and a detail page. Asking for the
  /// cast and overview up front keeps the detail page from a second round-trip
  /// for a film (only series need one, for the episode list).
  static const _fields =
      'ProductionYear,CommunityRating,Overview,Genres,People,'
      'ProductionLocations,ProviderIds,ChildCount';

  /// The single line name every Emby title carries. Emby has no 线路 concept;
  /// one line keeps the detail page's 选集 row from looking broken.
  static const _lineName = '直连';

  Future<List<MediaItem>> _items(Uri uri, {bool isEpisode = false}) async {
    final json = await _get(uri);
    final raw = json['Items'];
    if (raw is! List) return const [];
    final out = <MediaItem>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = entry.cast<String, dynamic>();
      final id = '${map['Id'] ?? ''}';
      if (id.isEmpty) continue;
      out.add(isEpisode ? _toEpisode(map) : _toItem(map));
    }
    return out;
  }

  /// Maps one Emby row onto the app's card model.
  ///
  /// `latest` doubles as the "this is a series" marker: it is only set for
  /// `Type == Series`, and [detail] reads it to decide whether to fetch the
  /// episode list. Nothing else in the model needed a new field for that.
  MediaItem _toItem(Map<String, dynamic> map) {
    final type = '${map['Type'] ?? ''}';
    final isSeries = type == 'Series';
    final childCount = map['ChildCount'];
    final episodes = childCount is int && childCount > 0 ? childCount : null;
    final genres = _strings(map['Genres']);
    final cast = <String>[];
    final people = map['People'];
    if (people is List) {
      for (final person in people) {
        if (person is! Map) continue;
        if ('${person['Type'] ?? ''}' != 'Actor') continue;
        final name = '${person['Name'] ?? ''}';
        if (name.isNotEmpty && !cast.contains(name)) cast.add(name);
        if (cast.length >= 12) break;
      }
    }
    final regions = _strings(map['ProductionLocations']);
    final rating = map['CommunityRating'];
    return MediaItem(
      id: '${map['Id']}',
      title: '${map['Name'] ?? ''}',
      subtitle: isSeries ? '剧集' : '电影',
      score: rating is num ? rating.toDouble() : null,
      year: map['ProductionYear'] is int ? map['ProductionYear'] as int : null,
      overview: _text(map['Overview']),
      image: _poster(map),
      latest: isSeries
          ? (episodes == null ? '剧集' : '全$episodes集')
          : null,
      area: regions.isEmpty ? null : regions.first,
      categories: genres,
      actors: cast,
      sourceName: sourceName.isEmpty ? null : sourceName,
    );
  }

  MediaItem _toEpisode(Map<String, dynamic> map) {
    final index = map['IndexNumber'];
    final name = _text(map['Name']) ?? '';
    return MediaItem(
      id: '${map['Id']}',
      title: index is int ? '第$index集' : name,
      overview: _text(map['Overview']),
    );
  }

  /// The poster URL the server serves for this item, or null when it has none
  /// (an item without a `Primary` tag). Rendering falls back to the palette.
  String? _poster(Map<String, dynamic> map) {
    final tags = map['ImageTags'];
    final tag = tags is Map ? '${tags['Primary'] ?? ''}' : '';
    if (tag.isEmpty) return null;
    final query = Uri(
      queryParameters: {
        'maxHeight': '520',
        'quality': '90',
        'tag': tag,
        'api_key': token,
      },
    ).query;
    return '$baseUrl/Items/${map['Id']}/Images/Primary?$query';
  }

  Future<Map<String, dynamic>> _get(Uri uri) async {
    final result = await _send('GET', uri);
    if (result.status < 200 || result.status >= 300) {
      throw EmbyException(_describeStatus(result.status), statusCode: result.status);
    }
    return result.json;
  }

  Future<({int status, Map<String, dynamic> json})> _send(
    String method,
    Uri uri, {
    String? body,
    Map<String, String>? headers,
  }) async {
    final HttpClientRequest request;
    try {
      request = await _http.openUrl(method, uri).timeout(timeout);
    } on TimeoutException {
      throw EmbyException('服务器没有响应（超时 ${timeout.inSeconds}s）');
    } on SocketException catch (e) {
      throw EmbyException('连不上 ${uri.host}：${e.osError?.message ?? '网络不可达'}');
    }

    headers?.forEach(request.headers.set);
    if (body != null) request.add(utf8.encode(body));

    final HttpClientResponse response;
    try {
      response = await request.close().timeout(timeout);
    } on TimeoutException {
      throw EmbyException('服务器响应太慢（超时 ${timeout.inSeconds}s）');
    } on SocketException catch (e) {
      throw EmbyException('连接被断开：${e.message}');
    }

    final text = await utf8.decodeStream(response).timeout(
      timeout,
      onTimeout: () => '',
    );
    if (text.trim().isEmpty) {
      return (status: response.statusCode, json: const <String, dynamic>{});
    }
    try {
      final decoded = jsonDecode(text);
      return (
        status: response.statusCode,
        json: decoded is Map<String, dynamic>
            ? decoded
            : const <String, dynamic>{},
      );
    } on FormatException {
      // A reverse proxy in front of the server answers HTML on error pages.
      throw EmbyException(
        response.statusCode >= 400
            ? _describeStatus(response.statusCode)
            : '服务器返回的不是 JSON，地址可能指向了网页而不是 Emby',
        statusCode: response.statusCode,
      );
    }
  }

  /// Turns a status into something a user can act on.
  static String _describeStatus(int status) {
    // Post-login only: [authenticate] answers a 401 with its own wording, so
    // reaching here means a token the server no longer honours. There is no
    // refresh endpoint worth wiring for a mount the user can re-add in ten
    // seconds, so the message says what actually fixes it.
    if (status == 401 || status == 403) {
      return '登录已失效（服务器不认这个令牌了）；删掉这个源重新添加一次即可重新登录';
    }
    if (status == 404) return '接口不存在，地址可能不是 Emby 服务器';
    if (status >= 500) return '服务器内部错误（$status）';
    return '服务器返回 $status';
  }

  static String _normalize(String base) {
    var out = base.trim();
    while (out.endsWith('/')) {
      out = out.substring(0, out.length - 1);
    }
    if (!out.startsWith('http://') && !out.startsWith('https://')) {
      out = 'http://$out';
    }
    return out;
  }

  static List<String> _strings(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final value in raw)
        if ('$value'.trim().isNotEmpty) '$value',
    ];
  }

  static String? _text(Object? raw) {
    final text = '${raw ?? ''}'.trim();
    return text.isEmpty ? null : text;
  }
}
