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
}
