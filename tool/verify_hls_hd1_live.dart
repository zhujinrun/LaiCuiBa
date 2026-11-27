// Live proof that the loopback cleaner removes the ad pods from 尚公主
// 高清线路1 episode 2 — the line/pod the user actually reported.
//
//   dart run tool/verify_hls_hd1_live.dart [master-url]
//
// That CDN (svip.dyttplay1.com) has NO ad marker and hash-named segments in
// one directory, so the marker/prefix rules cannot help. The pods are framed
// by tight runs of discontinuities; this script proves they are gone after
// the stream passes through HlsCleanProxy.
import 'dart:convert';
import 'dart:io';

import 'package:lai_cui_ba/services/hls_clean_proxy.dart';

const _defaultUrl =
    'https://svip.dyttplay1.com/20261023/42460_3de2f5d6/index.m3u8';
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

int _tightRuns(String playlist) {
  final lines = playlist.split('\n');
  final discs = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('#EXT-X-DISCONTINUITY')) discs.add(i);
  }
  var runs = 0;
  for (var k = 0; k + 1 < discs.length; k++) {
    var gap = 0;
    for (var j = discs[k] + 1; j < discs[k + 1]; j++) {
      if (lines[j].startsWith('#EXTINF:')) gap++;
    }
    if (gap >= 1 && gap < 5) runs++;
  }
  return runs;
}

Future<void> main(List<String> args) async {
  final master = args.isEmpty ? _defaultUrl : args.first;
  final rawMaster = await _get(master);
  _check('master fetched', rawMaster.startsWith('#EXTM3U'));
  final variantLine = rawMaster
      .split('\n')
      .firstWhere((l) => l.endsWith('.m3u8'), orElse: () => '');
  final variant = Uri.parse(master).resolve(variantLine.trim()).toString();
  final raw = await _get(variant);
  _check('upstream media fetched', raw.startsWith('#EXTM3U'));
  _check(
    'upstream carries the tight ad runs',
    _tightRuns(raw) >= 4,
    '${_tightRuns(raw)} tight gaps',
  );
  _check('upstream has the ad segments', raw.contains('b8350ea6'));

  final wrapped = await HlsCleanProxy.instance.wrap(master, headers: _headers);
  _check('master wrapped through loopback', wrapped.contains('/hls?u='));
  final servedMaster = await _get(wrapped);
  // The master's variant line is rewritten to a loopback URL ending in the
  // base64 `h=` query, so locate it by the `/hls?u=` marker, not `.m3u8`.
  final nestedLine = servedMaster
      .split('\n')
      .firstWhere((l) => l.contains('/hls?u='), orElse: () => '');
  _check('nested media rewritten to proxy', nestedLine.contains('/hls?u='));
  final nested = Uri.parse(wrapped).resolve(nestedLine.trim()).toString();
  final served = await _get(nested);

  _check('cleaned playlist is valid', served.startsWith('#EXTM3U'));
  _check('pod1 ad segments removed', !served.contains('b8350ea6'));
  _check('pod2 ad segments removed', !served.contains('48b3b56b'));
  _check('no tight discontinuity run remains', _tightRuns(served) == 0);
  _check('show segments kept', served.contains('1a55679c'));
  _check(
    'segment count dropped by the two pods',
    _segments(raw) - _segments(served) == 9,
    '${_segments(raw)} -> ${_segments(served)}',
  );

  exit(_failures > 0 ? 1 : 0);
}
