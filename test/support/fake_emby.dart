import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A stand-in Emby server for tests.
///
/// Emby's API is plain JSON over HTTP, so a real [HttpServer] on localhost is a
/// more honest peer than a mocked client object: the test exercises the client's
/// URL building, header handling, status decoding and JSON walking for real.
/// Only the four endpoints this app uses are implemented; anything else 404s so
/// a wrong path fails loudly instead of silently answering.
class FakeEmby {
  FakeEmby._(this._server, {required this.username, required this.password});

  final HttpServer _server;
  final String username;
  final String password;

  static const token = 'tok-test-1';
  static const userId = 'u1';
  static const serverName = '客厅 Emby';

  /// Every request the client made, in order: `METHOD path?query`. Assertions
  /// about `api_key` and search terms read this rather than scraping logs.
  final List<String> requests = [];

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  static Future<FakeEmby> start({
    String username = 'lxy',
    String password = 'secret',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeEmby._(
      server,
      username: username,
      password: password,
    );
    unawaited(fake._serve());
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _serve() async {
    await for (final request in _server) {
      try {
        await _handle(request);
      } catch (_) {
        // A malformed request must not take the fake down mid-test.
        request.response.statusCode = 500;
        await request.response.close();
      }
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    requests.add('${request.method} ${request.uri}');

    if (path == '/Users/AuthenticateByName' && request.method == 'POST') {
      final body = await utf8.decoder.bind(request).join();
      final json = body.isEmpty
          ? const <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
      if (json['Username'] != username || json['Pw'] != password) {
        return _json(request, 401, {
          'error': 'Invalid username/password',
        });
      }
      final header = request.headers.value('x-emby-authorization') ?? '';
      events.add(header);
      return _json(request, 200, {
        'User': {'Id': userId, 'Name': username},
        'AccessToken': token,
        'ServerId': 'srv-1',
        'ServerName': serverName,
      });
    }

    // Everything below requires the token the login handed out.
    if (request.uri.queryParameters['api_key'] != token) {
      return _json(request, 401, {'error': 'unauthorized'});
    }

    if (path == '/Items/Counts') {
      return _json(request, 200, {
        'MovieCount': movies.length,
        'SeriesCount': series.length,
        'EpisodeCount': episodes.length,
      });
    }

    if (path == '/Users/$userId/Items') {
      final term = (request.uri.queryParameters['SearchTerm'] ?? '').trim();
      final kinds = (request.uri.queryParameters['IncludeItemTypes'] ?? '')
          .split(',')
          .where((e) => e.isNotEmpty)
          .toSet();
      final rows = <Map<String, dynamic>>[
        for (final movie in movies)
          if (kinds.isEmpty || kinds.contains('Movie')) movie,
        for (final show in series)
          if (kinds.isEmpty || kinds.contains('Series')) show,
      ].where((row) {
        if (term.isEmpty) return true;
        return '${row['Name']}'.contains(term);
      }).toList();
      return _json(request, 200, {
        'Items': rows,
        'TotalRecordCount': rows.length,
      });
    }

    final episodeMatch = RegExp(r'^/Shows/([^/]+)/Episodes$').firstMatch(path);
    if (episodeMatch != null) {
      final showId = episodeMatch.group(1)!;
      final rows = episodes
          .where((e) => e['SeriesId'] == showId)
          .map(
            (e) => {
              'Id': e['Id'],
              'Name': e['Name'],
              'IndexNumber': e['IndexNumber'],
              'Type': 'Episode',
              'SeriesId': e['SeriesId'],
              'Overview': e['Overview'],
            },
          )
          .toList();
      return _json(request, 200, {'Items': rows, 'TotalRecordCount': rows.length});
    }

    return _json(request, 404, {'error': 'not found'});
  }

  /// Extra observations that are not request lines: the auth header the login
  /// sent, for instance.
  final List<String> events = [];

  Future<void> _json(
    HttpRequest request,
    int status,
    Map<String, dynamic> body,
  ) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  // ---------------------------------------------------------------------------
  // Fixture data
  // ---------------------------------------------------------------------------

  static final List<Map<String, dynamic>> movies = [
    {
      'Id': 'm1',
      'Name': '流浪地球',
      'Type': 'Movie',
      'ProductionYear': 2019,
      'CommunityRating': 8.2,
      'Overview': '太阳即将毁灭，人类带着地球去流浪。',
      'Genres': ['科幻', '灾难'],
      'ProductionLocations': ['中国大陆'],
      'ImageTags': {'Primary': 'tag-m1'},
      'People': [
        {'Name': '吴京', 'Type': 'Actor'},
        {'Name': '屈楚萧', 'Type': 'Actor'},
        {'Name': '郭帆', 'Type': 'Director'},
      ],
    },
    {
      'Id': 'm2',
      'Name': '让子弹飞',
      'Type': 'Movie',
      'ProductionYear': 2010,
      'CommunityRating': 9.1,
      'Overview': '麻匪进城。',
      'Genres': ['剧情', '喜剧'],
      'ImageTags': {'Primary': 'tag-m2'},
      'People': [
        {'Name': '姜文', 'Type': 'Actor'},
      ],
    },
  ];

  static final List<Map<String, dynamic>> series = [
    {
      'Id': 's1',
      'Name': '三体',
      'Type': 'Series',
      'ProductionYear': 2023,
      'CommunityRating': 8.7,
      'Overview': '物理学不存在了。',
      'Genres': ['科幻'],
      'ChildCount': 2,
      'ImageTags': {'Primary': 'tag-s1'},
      'People': [
        {'Name': '张鲁一', 'Type': 'Actor'},
      ],
    },
  ];

  static final List<Map<String, dynamic>> episodes = [
    {
      'Id': 'e1',
      'SeriesId': 's1',
      'Name': '第1集',
      'IndexNumber': 1,
      'Overview': '科学边界。',
    },
    {
      'Id': 'e2',
      'SeriesId': 's1',
      'Name': '第2集',
      'IndexNumber': 2,
      'Overview': '射手与农场主。',
    },
  ];
}
