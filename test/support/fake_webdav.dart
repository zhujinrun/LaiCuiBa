import 'dart:convert';
import 'dart:io';

/// One file or folder in the fake share.
class DavNode {
  const DavNode(this.name, {this.isDir = false, this.size = 0});

  final String name;
  final bool isDir;
  final int size;
}

/// A WebDAV server that answers `PROPFIND` from an in-memory tree.
///
/// The real client is judged on what it makes of a share's answers -- which
/// rows become cards, how names parse, how episodes sort -- and none of that
/// needs a NAS. Requests are authenticated the same way a real server does it,
/// so the Basic header and its failure mode are covered too.
class FakeWebDav {
  FakeWebDav._(this._server, this.username, this.password, this.tree);

  final HttpServer _server;
  final String username;
  final String password;

  /// Directory path (always leading and trailing slash) -> entries.
  final Map<String, List<DavNode>> tree;

  /// Requests seen, for assertions about fan-out and depth.
  final List<String> requests = [];

  static Future<FakeWebDav> start({
    String username = 'lxy',
    String password = 'secret',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeWebDav._(server, username, password, {
      '/dav/': const [
        DavNode('电影', isDir: true),
        DavNode('剧集', isDir: true),
        DavNode('散装片.mkv', size: 1024),
        // Rows that must never become cards.
        DavNode('散装片.nfo'),
        DavNode('poster.jpg'),
        DavNode('@eaDir', isDir: true),
      ],
      '/dav/电影/': const [
        DavNode('[小组] 流浪地球2.2023.2160p.mkv', size: 2048),
        DavNode('奥德赛 2024.mp4', size: 1024),
        DavNode('奥德赛 2024.ass'),
      ],
      '/dav/剧集/': const [
        DavNode('三体 第10集.mp4'),
        DavNode('三体 第2集.mp4'),
        DavNode('三体 第1集.mp4'),
      ],
      // A metadata folder: no video, so it must count as nothing.
      '/dav/@eaDir/': const [DavNode('random.srt'), DavNode('thumb.jpg')],
    });
    server.listen(fake._handle);
    return fake;
  }

  String get url => 'http://127.0.0.1:${_server.port}/dav/';

  String get authHeader =>
      'Basic ${base64Encode(utf8.encode('$username:$password'))}';

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    // `uri.path` arrives percent-decoded on some Dart versions and encoded on
    // others; decode once so the tree keys stay plain Chinese names.
    final path = _dirPath(Uri.decodeFull(request.uri.path));
    requests.add('${request.method} $path');

    if (request.headers.value(HttpHeaders.authorizationHeader) != authHeader) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.set(
        HttpHeaders.wwwAuthenticateHeader,
        'Basic realm="fake"',
      );
      await request.response.close();
      return;
    }

    final entries = tree[path];
    if (entries == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    request.response.statusCode = 207;
    request.response.headers.contentType = ContentType(
      'application',
      'xml',
      charset: 'utf-8',
    );
    request.response.write(_multistatus(path, entries));
    await request.response.close();
  }

  /// A directory always reads with a trailing slash, which is what a real
  /// server guarantees and what the client relies on to join hrefs.
  String _dirPath(String raw) {
    var path = raw;
    if (!path.startsWith('/')) path = '/$path';
    if (!path.endsWith('/')) path = '$path/';
    return path;
  }

  String _multistatus(String path, List<DavNode> entries) {
    final buffer = StringBuffer(
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:multistatus xmlns:d="DAV:">',
    );
    // The server echoes the directory itself first; the client must drop it.
    buffer.write(_response(path, path, isDir: true));
    for (final entry in entries) {
      buffer.write(
        _response(
          '$path${entry.name}${entry.isDir ? '/' : ''}',
          entry.name,
          isDir: entry.isDir,
          size: entry.size,
        ),
      );
    }
    buffer.write('</d:multistatus>');
    return buffer.toString();
  }

  String _response(
    String href,
    String name, {
    required bool isDir,
    int size = 0,
  }) {
    final encoded = href
        .split('/')
        .map((segment) => Uri.encodeComponent(segment))
        .join('/');
    final type = isDir
        ? '<d:resourcetype><d:collection/></d:resourcetype>'
        : '<d:resourcetype/>';
    return '<d:response>'
        '<d:href>$encoded</d:href>'
        '<d:propstat><d:prop>'
        '<d:displayname>${_escape(name)}</d:displayname>'
        '$type'
        '<d:getcontentlength>$size</d:getcontentlength>'
        '</d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>'
        '</d:response>';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
