// Live proof that the loopback cleaner removes the ad pods from 尚公主
// FF线路 episode 2 — the shape with NO marker, no tight run and only 5
// discontinuities, where the ad is a short gap isolated between long shows.
//
//   dart run tool/verify_hls_ff_live.dart [master-url]
//
// Verified against the reported line: 699 -> 690 segments, both 澳门新葡京
// pods (gaps 5 and 4 segments at ~356s and ~1697s) gone, show segments kept.
import 'dart:convert';
import 'dart:io';

import 'package:lai_cui_ba/services/hls_clean_proxy.dart';

const _defaultUrl =
    'https://super.ffzy-online6.com/20261023/43934_7206ef1b/index.m3u8';
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

int _segments(String playlist) =>
    playlist.split('\n').where((l) => l.startsWith('#EXTINF:')).length;

/// Gaps (in segments) between consecutive discontinuities.
List<int> _discGaps(String playlist) {
  final lines = playlist.split('\n');
  final discs = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('#EXT-X-DISCONTINUITY')) discs.add(i);
  }
  final gaps = <int>[];
  for (var k = 0; k + 1 < discs.length; k++) {
    var gap = 0;
    for (var j = discs[k] + 1; j < discs[k + 1]; j++) {
      if (lines[j].startsWith('#EXTINF:')) gap++;
    }
    gaps.add(gap);
  }
  return gaps;
}

bool _hasShortPod(String playlist) {
  final gaps = _discGaps(playlist);
  for (var i = 0; i < gaps.length; i++) {
    if (gaps[i] < 2 || gaps[i] > 8) continue;
    final neighbours = <int>[];
    if (i > 0) neighbours.add(gaps[i - 1]);
    if (i + 1 < gaps.length) neighbours.add(gaps[i + 1]);
    if (neighbours.isNotEmpty && neighbours.every((n) => n >= 20)) return true;
  }
  return false;
}

Future<void> main(List<String> args) async {
  final master = args.isEmpty ? _defaultUrl : args.first;
  final rawMaster = await _get(master);
  _check('master fetched', rawMaster.startsWith('#EXTM3U'));

  // Resolve the (first) variant directly from the untouched master.
  final variantLine = rawMaster
      .split('\n')
      .firstWhere((l) => l.endsWith('.m3u8'), orElse: () => '');
  final variant = Uri.parse(master).resolve(variantLine.trim()).toString();
  final raw = await _get(variant);
  _check('upstream media fetched', raw.startsWith('#EXTM3U'));
  _check('upstream carries an isolated short pod', _hasShortPod(raw),
      'gaps=${_discGaps(raw)}');
  final rawSegs = _segments(raw);

  final wrapped = await HlsCleanProxy.instance.wrap(master, headers: _headers);
  _check('master wrapped through loopback', wrapped.contains('/hls?u='));
  final servedMaster = await _get(wrapped);
  final nestedLine = servedMaster
      .split('\n')
      .firstWhere((l) => l.contains('/hls?u='), orElse: () => '');
  _check('nested media rewritten to proxy', nestedLine.contains('/hls?u='));
  final nested = Uri.parse(wrapped).resolve(nestedLine.trim()).toString();
  final served = await _get(nested);

  _check('cleaned playlist is valid', served.startsWith('#EXTM3U'));
  _check('no isolated short pod remains', !_hasShortPod(served),
      'gaps=${_discGaps(served)}');
  final servedSegs = _segments(served);
  _check(
    'both ad pods removed (5 + 4 segments)',
    rawSegs - servedSegs == 9,
    '$rawSegs -> $servedSegs',
  );
  _check('show segments kept', served.contains('356109831f5a58cd19684d886b7a49c5'));

  exit(_failures > 0 ? 1 : 0);
}
