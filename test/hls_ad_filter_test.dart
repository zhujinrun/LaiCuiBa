import 'package:flutter_test/flutter_test.dart';
import 'package:lai_cui_ba/services/hls_ad_filter.dart';

void main() {
  const filter = HlsAdFilter();
  final source = Uri.parse(
    'https://v.example.com/20261023/title/2000k/hls/index.m3u8',
  );

  String rewrite(Uri uri) =>
      'http://127.0.0.1:49152/hls?u=${Uri.encodeQueryComponent(uri.toString())}';

  test('removes the injected pod and both discontinuity markers', () {
    const playlist = '''
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:8
#EXTINF:4.000000,
seg000.ts
#EXTINF:4.000000,
seg001.ts
#EXTINF:4.000000,
seg002.ts
# ppvod-ad-injected v1
#EXT-X-DISCONTINUITY
#EXTINF:4,
/20261003/84_9109598f/2000k/hls/ad000.ts
#EXTINF:4,
/20261003/84_9109598f/2000k/hls/ad001.ts
#EXTINF:1.76,
/20261003/84_9109598f/2000k/hls/ad002.ts
#EXT-X-DISCONTINUITY
#EXTINF:4.000000,
seg003.ts
#EXTINF:4.000000,
seg004.ts
#EXTINF:4.000000,
seg005.ts
#EXT-X-ENDLIST
''';

    final cleaned = filter.clean(
      playlist,
      source: source,
      rewritePlaylist: rewrite,
    );
    final lines = cleaned.split('\n');

    expect(lines.where((line) => line.startsWith('#EXTINF:')).length, 6);
    expect(cleaned, isNot(contains('ppvod-ad-injected')));
    expect(cleaned, isNot(contains('ad000.ts')));
    expect(cleaned, isNot(contains('#EXT-X-DISCONTINUITY')));
    expect(cleaned, contains('#EXT-X-ENDLIST'));
    // The proxy serves the playlist from loopback, so segments must be
    // absolute or mpv would ask 127.0.0.1 for them.
    expect(
      cleaned,
      contains('https://v.example.com/20261023/title/2000k/hls/seg003.ts'),
    );
    expect(
      cleaned,
      isNot(
        contains(
          'https://v.example.com/20261003/84_9109598f/2000k/hls/ad000.ts',
        ),
      ),
    );
  });

  test('rewrites nested master playlists through the cleaner endpoint', () {
    const master = '''
#EXTM3U
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=800000,RESOLUTION=1080x608
2000k/hls/index.m3u8
#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=400000,RESOLUTION=720x406
1000k/hls/index.m3u8
''';
    final cleaned = filter.clean(
      master,
      source: Uri.parse('https://v.example.com/20261023/title/index.m3u8'),
      rewritePlaylist: rewrite,
    );

    expect(
      cleaned,
      contains(
        'http://127.0.0.1:49152/hls?u=https%3A%2F%2Fv.example.com%2F20261023%2Ftitle%2F2000k%2Fhls%2Findex.m3u8',
      ),
    );
    expect(cleaned, contains('1000k%2Fhls%2Findex.m3u8'));
  });

  test(
    'keeps an ordinary discontinuity that is not next to a dropped segment',
    () {
      const playlist = '''
#EXTM3U
#EXTINF:4,
seg000.ts
#EXT-X-DISCONTINUITY
#EXTINF:4,
seg001.ts
#EXTINF:4,
seg002.ts
#EXTINF:4,
seg003.ts
''';
      final cleaned = filter.clean(
        playlist,
        source: source,
        rewritePlaylist: rewrite,
      );
      expect(cleaned, contains('#EXT-X-DISCONTINUITY'));
      expect(
        cleaned.split('\n').where((line) => line.startsWith('#EXTINF:')).length,
        4,
      );
    },
  );

  test('removes a tight-discontinuity ad pod with no marker', () {
    // 尚公主 高清线路1 serves hash-named segments from ONE directory (so the
    // dominant-prefix rule cannot see them) and no ad marker. The ad pod is
    // framed by three discontinuities only 2-3 segments apart, while the
    // show's own boundaries are 5 segments apart.
    final buf = StringBuffer('#EXTM3U\n#EXT-X-VERSION:3\n');
    var n = 0;
    void seg(String name) {
      buf.writeln('#EXTINF:4.000,');
      buf.writeln('$name.ts?hash=$n');
      n++;
    }

    for (var i = 0; i < 3; i++) {
      seg('show');
    }
    buf.writeln('#EXT-X-DISCONTINUITY'); // ad starts (no marker)
    seg('ad');
    seg('ad');
    seg('ad');
    buf.writeln('#EXT-X-DISCONTINUITY');
    seg('ad');
    seg('ad');
    buf.writeln('#EXT-X-DISCONTINUITY'); // ad ends
    for (var i = 0; i < 5; i++) {
      seg('show');
    }
    buf.writeln('#EXT-X-DISCONTINUITY'); // a real boundary (5 apart)
    for (var i = 0; i < 5; i++) {
      seg('show');
    }

    final cleaned = filter.clean(
      buf.toString(),
      source: source,
      rewritePlaylist: rewrite,
    );
    final lines = cleaned.split('\n');
    expect(lines.where((l) => l.startsWith('#EXTINF:')).length, 13);
    expect(cleaned, isNot(contains('ad.ts')));
    expect(cleaned, contains('show.ts'));
    // All 3 tight discs go; only the one real boundary (5 apart) survives.
    expect(
      lines.where((l) => l.startsWith('#EXT-X-DISCONTINUITY')).length,
      1,
    );
    // The show segment before the pod must now be directly followed by the
    // show segment after it, so PTS stays continuous (no timeline reset).
    final showLines = lines.where((l) => l.contains('show.ts')).toList();
    expect(showLines.length, 13);
  });

  test('removes an isolated short pod between long show stretches', () {
    // 尚公主 FF line: hash-named segments in one directory, no marker, and
    // only 5 discontinuities. The ad pods (5 and 4 segments) are isolated
    // between long show stretches, unlike a regular boundary pattern.
    final buf = StringBuffer('#EXTM3U\n#EXT-X-VERSION:3\n');
    var n = 0;
    void seg(String name) {
      buf.writeln('#EXTINF:4.000,');
      buf.writeln('$name.ts?hash=${n++}');
    }

    for (var i = 0; i < 20; i++) {
      seg('show');
    }
    buf.writeln('#EXT-X-DISCONTINUITY');
    for (var i = 0; i < 5; i++) {
      seg('ad');
    }
    buf.writeln('#EXT-X-DISCONTINUITY');
    for (var i = 0; i < 20; i++) {
      seg('show');
    }
    buf.writeln('#EXT-X-DISCONTINUITY');
    for (var i = 0; i < 4; i++) {
      seg('ad');
    }
    buf.writeln('#EXT-X-DISCONTINUITY');

    final cleaned = filter.clean(
      buf.toString(),
      source: source,
      rewritePlaylist: rewrite,
    );
    final lines = cleaned.split('\n');
    expect(lines.where((l) => l.startsWith('#EXTINF:')).length, 40);
    expect(cleaned, isNot(contains('ad.ts')));
    expect(cleaned, contains('show.ts'));
    // Only the two show boundaries survive; both ad gaps go with their discs.
    expect(
      lines.where((l) => l.startsWith('#EXT-X-DISCONTINUITY')).length,
      0,
    );
  });

  test('keeps regularly spaced short gaps (no long neighbours)', () {
    // 尚公主 RY line has 116 discontinuities exactly 6 segments apart. Every
    // gap is short, so none is "isolated between long stretches" and the whole
    // regular pattern must survive untouched.
    final buf = StringBuffer('#EXTM3U\n#EXT-X-VERSION:3\n');
    var n = 0;
    void seg(String name) {
      buf.writeln('#EXTINF:4.000,');
      buf.writeln('$name.ts?hash=${n++}');
    }

    for (var block = 0; block < 5; block++) {
      buf.writeln('#EXT-X-DISCONTINUITY');
      for (var i = 0; i < 6; i++) {
        seg('show');
      }
    }

    final cleaned = filter.clean(
      buf.toString(),
      source: source,
      rewritePlaylist: rewrite,
    );
    final lines = cleaned.split('\n');
    expect(lines.where((l) => l.startsWith('#EXTINF:')).length, 30);
    expect(
      lines.where((l) => l.startsWith('#EXT-X-DISCONTINUITY')).length,
      5,
    );
    expect(cleaned, isNot(contains('ad.ts')));
  });

  test('keeps normal discontinuities 5 segments apart', () {
    const playlist = '''
#EXTM3U
#EXTINF:4,
seg000.ts
#EXT-X-DISCONTINUITY
#EXTINF:4,
seg001.ts
#EXTINF:4,
seg002.ts
#EXTINF:4,
seg003.ts
#EXTINF:4,
seg004.ts
''';
    final cleaned = filter.clean(
      playlist,
      source: source,
      rewritePlaylist: rewrite,
    );
    // A single disc is not a tight run (>= 2 consecutive required), so it
    // stays even though its neighbouring gaps are short.
    expect(
      cleaned.split('\n').where((l) => l.startsWith('#EXT-X-DISCONTINUITY')).length,
      1,
    );
    expect(
      cleaned.split('\n').where((l) => l.startsWith('#EXTINF:')).length,
      5,
    );
  });
}
