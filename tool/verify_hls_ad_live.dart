// Live proof that the loopback playlist cleaner removes the ad pods from the
// stream LaiCuiBa is actually playing (尚公主 LZ line, episode 1).
//
//   dart run tool/verify_hls_ad_live.dart [master-url]
//
// Exits non-zero when the upstream no longer contains the known marker or when
// the cleaned playlist still carries any injected segment / discontinuity.
import 'dart:convert';
import 'dart:io';

import 'package:lai_cui_ba/services/hls_ad_filter.dart';
import 'package:lai_cui_ba/services/hls_clean_proxy.dart';

const _defaultUrl = 'https://v.lzcdn27.com/20261023/20013_b31b31e1/index.m3u8';
const _headers = {
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 9; V2196A Build/PQ3A.190705.08211809; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/91.0.4472.114 Mobile Safari/537.36;webank/h5face;webank/1.0;netType:NETWORK_WIFI;appVersion:416;packageName:com.jp3.xg3',
  'Referer': 'https://api.ztcgi.com',
};

var _failures = 0;

void _check(String what, bool ok, [String detail = '']) {
  stdout.writeln(
    '${ok ? 'ok  ' : 'FAIL'}  $what${detail.isEmpty ? '' : ' — $detail'}',
  );
  if (!ok) _failures++;
}

double _seconds(String playlist) {
  var total = 0.0;
  for (final line in playlist.split('\n')) {
    if (!line.startsWith('#EXTINF:')) continue;
    final raw = line.substring('#EXTINF:'.length).split(',').first.trim();
    total += double.tryParse(raw) ?? 0;
  }
  return total;
}

Future<String> _get(String url) async {
  final request = await HttpClient().getUrl(Uri.parse(url));
  request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
  for (final entry in _headers.entries) {
    request.headers.set(entry.key, entry.value);
  }
  final response = await request.close();
  return utf8.decode(
    await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    ),
    allowMalformed: true,
  );
}

Future<void> main(List<String> args) async {
  final master = args.isEmpty ? _defaultUrl : args.first;
  final originalMaster = await _get(master);
  _check('master playlist fetched', originalMaster.startsWith('#EXTM3U'));

  final variantLine = originalMaster
      .split('\n')
      .firstWhere((line) => line.endsWith('.m3u8'), orElse: () => '');
  _check(
    'master points to a media playlist',
    variantLine.isNotEmpty,
    variantLine,
  );
  final variant = Uri.parse(master).resolve(variantLine.trim()).toString();

  final original = await _get(variant);
  final cleaned = const HlsAdFilter().clean(
    original,
    source: Uri.parse(variant),
    rewritePlaylist: (uri) => uri.toString(),
  );

  _check(
    'upstream playlist carries the ad marker',
    original.contains('ppvod-ad-injected v1'),
  );
  _check(
    'cleaned playlist has no ad marker',
    !cleaned.contains('ppvod-ad-injected'),
  );
  _check(
    'cleaned playlist has no discontinuity',
    !cleaned.contains('#EXT-X-DISCONTINUITY'),
  );
  _check(
    'cleaned playlist has no ad segment',
    !cleaned.contains('/20261003/84_9109598f/'),
  );

  final originalSegments = original
      .split('\n')
      .where((l) => l.startsWith('#EXTINF:'))
      .length;
  final cleanedSegments = cleaned
      .split('\n')
      .where((l) => l.startsWith('#EXTINF:'))
      .length;
  _check(
    'both injected pods removed',
    originalSegments - cleanedSegments == 14,
    '$originalSegments -> $cleanedSegments segments',
  );
  _check(
    'timeline shortened by the two pods',
    (_seconds(original) - _seconds(cleaned) - 51.52).abs() < 0.2,
    '${_seconds(original).toStringAsFixed(2)} -> ${_seconds(cleaned).toStringAsFixed(2)} s',
  );

  // And the same answer through the URL the player actually opens.
  final wrapped = await HlsCleanProxy.instance.wrap(master, headers: _headers);
  final served = await _get(wrapped);
  _check(
    'loopback proxy returns a rewritten master',
    served.contains('/hls?u=') && served.contains('2000k'),
  );
  final nestedLine = served
      .split('\n')
      .firstWhere((l) => l.endsWith('.m3u8'), orElse: () => '');
  final nested = Uri.parse(wrapped).resolve(nestedLine.trim()).toString();
  final servedVariant = await _get(nested);
  _check(
    'loopback proxy returns the cleaned media playlist',
    !servedVariant.contains('ppvod-ad-injected') &&
        !servedVariant.contains('#EXT-X-DISCONTINUITY'),
  );

  exit(_failures > 0 ? 1 : 0);
}
