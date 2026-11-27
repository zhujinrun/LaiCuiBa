/// Removes ad pods that an upstream CDN splices into an HLS playlist.
///
/// The LZ line of 尚公主 currently serves a media playlist that literally
/// contains `# ppvod-ad-injected v1`, then seven TS segments from a different
/// video directory, then a second discontinuity. mpv honours that splice: it
/// shows the ad, reports a new timeline and the progress bar lands back at
/// 00:00. The stream itself is fine — only the playlist is polluted.
///
/// Two splice shapes are handled, both conservatively:
///
///  1. A marker plus segments hosted under a different directory prefix
///     (the LZ line of 尚公主). Drop the marker, the foreign-prefix segments,
///     and the adjacent discontinuities.
///  2. No marker and the ad lives in the same directory under hash-named
///     segments (the 高清线路1 of 尚公主). Here the ad is framed by a run of
///     discontinuities only 2-3 segments apart, while the show's own
///     discontinuities are always >= 5 segments apart. Drop that whole run.
///
/// In both cases the discontinuities around a removed pod go with it: the
/// show's TS timestamps already run on one continuous clock, and it is the
/// discontinuity that makes mpv restart its timeline at 00:00.
class HlsAdFilter {
  const HlsAdFilter();

  /// Cleans one playlist fetched from [source].
  ///
  /// [rewritePlaylist] is applied to nested master-playlist URLs so those are
  /// cleaned as well; media segment URLs are only made absolute, because
  /// proxying every TS chunk would double the hop count for no benefit.
  String clean(
    String text, {
    required Uri source,
    required String Function(Uri uri) rewritePlaylist,
  }) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    if (!lines.any((line) => line.startsWith('#EXTM3U'))) return text;

    final master = lines.any((line) => line.startsWith('#EXT-X-STREAM-INF'));
    if (master) return _cleanMaster(lines, source, rewritePlaylist);
    return _cleanMedia(lines, source);
  }

  String _cleanMaster(
    List<String> lines,
    Uri source,
    String Function(Uri uri) rewritePlaylist,
  ) {
    final out = <String>[];
    for (final raw in lines) {
      final line = raw.trimRight();
      if (line.startsWith('#')) {
        out.add(_rewriteUriAttribute(line, source, rewritePlaylist));
        continue;
      }
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        out.add(line);
        continue;
      }
      final uri = _resolve(source, trimmed);
      out.add(uri == null ? line : rewritePlaylist(uri));
    }
    return out.join('\n');
  }

  String _cleanMedia(List<String> lines, Uri source) {
    final remove = <int>{};

    for (var i = 0; i < lines.length; i++) {
      if (_isAdMarker(lines[i])) remove.add(i);
    }

    final segments = <({int info, int uri, Uri resolved})>[];
    for (var i = 0; i + 1 < lines.length; i++) {
      if (!lines[i].startsWith('#EXTINF:')) continue;
      final uri = _resolve(source, lines[i + 1].trim());
      if (uri != null) segments.add((info: i, uri: i + 1, resolved: uri));
    }

    if (segments.length >= 4) {
      final prefix = _dominantPrefix(
        segments.map((e) => e.resolved.toString()).toList(),
      );
      if (prefix.isNotEmpty) {
        for (final segment in segments) {
          if (!segment.resolved.toString().startsWith(prefix)) {
            remove.add(segment.info);
            remove.add(segment.uri);
          }
        }
      }
    }

    // Shape 2: no marker / no foreign prefix, but a tight run of
    // discontinuities (2-3 segments apart) frames an injected pod. The show's
    // own discontinuities are >= 5 segments apart, so this is unambiguous.
    _removeTightDiscontinuityPods(lines, remove);

    // A discontinuity that sits next to a dropped segment belongs to the ad
    // pod. Keeping it would tell mpv to restart its timeline for no reason.
    for (var i = 0; i < lines.length; i++) {
      if (remove.contains(i) || !lines[i].startsWith('#EXT-X-DISCONTINUITY')) {
        continue;
      }
      if (_touchesRemoved(remove, lines, i)) remove.add(i);
    }

    final out = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (remove.contains(i)) continue;
      final line = lines[i];
      if (!line.startsWith('#') && line.trim().isNotEmpty) {
        final uri = _resolve(source, line.trim());
        out.add(uri?.toString() ?? line);
      } else {
        out.add(_rewriteUriAttribute(line, source, (uri) => uri.toString()));
      }
    }
    return out.join('\n');
  }

  /// Shape 2: some CDNs splice the ad into the same directory with hash-named
  /// segments and no marker at all. The only trace is a run of discontinuities
  /// only 2-3 segments apart; the show's own boundaries are always >= 5
  /// segments apart (verified on 尚公主 高清线路1: 699 segments, 106
  /// discontinuities, two 3-disc runs at 297.88s and 1516s wrapping the
  /// 澳门新葡京 pods). Drop such a run and everything it wraps.
  static void _removeTightDiscontinuityPods(
    List<String> lines,
    Set<int> remove,
  ) {
    final discs = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('#EXT-X-DISCONTINUITY')) discs.add(i);
    }
    if (discs.length < 2) return;

    int gaps(int a, int b) {
      var n = 0;
      for (var i = a + 1; i < b; i++) {
        if (lines[i].startsWith('#EXTINF:')) n++;
      }
      return n;
    }

    var i = 0;
    while (i + 1 < discs.length) {
      final gap = gaps(discs[i], discs[i + 1]);
      if (gap < 1 || gap >= 5) {
        i++;
        continue;
      }
      var end = i + 1;
      while (end + 1 < discs.length) {
        final next = gaps(discs[end], discs[end + 1]);
        if (next < 1 || next >= 5) break;
        end++;
      }
      // Require a RUN of at least two tight gaps (3 discs). A lone short
      // gap is left alone so an unusual-but-legit boundary is never cut.
      if (end < i + 2) {
        i++;
        continue;
      }
      for (var d = i; d <= end; d++) {
        remove.add(discs[d]);
      }
      for (var line = discs[i] + 1; line < discs[end]; line++) {
        if (!lines[line].startsWith('#EXTINF:')) continue;
        remove.add(line);
        if (line + 1 < lines.length && !lines[line + 1].startsWith('#')) {
          remove.add(line + 1);
        }
      }
      i = end + 1;
    }
  }

  static bool _isAdMarker(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('#') || trimmed.startsWith('#EXTINF:')) {
      return false;
    }
    return RegExp(
      r'ppvod-ad-injected|ad[-_ ]?injected|ad[-_ ]?pod|mid[-_ ]?roll|广告注入',
      caseSensitive: false,
    ).hasMatch(trimmed);
  }

  static bool _touchesRemoved(Set<int> remove, List<String> lines, int index) {
    for (var i = index - 1; i >= (index - 3 < 0 ? 0 : index - 3); i--) {
      if (remove.contains(i)) return true;
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty || trimmed.startsWith('#EXTINF:')) continue;
      break;
    }
    for (var i = index + 1; i < lines.length && i <= index + 3; i++) {
      if (remove.contains(i)) return true;
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty || trimmed.startsWith('#EXTINF:')) continue;
      break;
    }
    return false;
  }

  /// The longest URI prefix shared by a clear majority of the segments.
  ///
  /// Using the first and last segment alone fails on a pre-roll ad; requiring
  /// 60% agreement makes a handful of injected chunks lose to the real video.
  static String _dominantPrefix(List<String> uris) {
    if (uris.isEmpty) return '';
    // Count the first URI itself as well; otherwise a playlist with just a
    // handful of real segments can fall below the majority threshold.
    final counts = <String, int>{uris.first: 1};
    for (final other in uris.skip(1)) {
      final prefix = _commonPrefix(uris.first, other);
      counts[prefix] = (counts[prefix] ?? 0) + 1;
    }
    // The first URI is the reference, so it is not one of the "other" votes.
    final needed = (uris.length * 0.6).ceil() - 1;
    var best = '';
    for (final entry in counts.entries) {
      if (entry.value < needed) continue;
      if (entry.key.length > best.length) best = entry.key;
    }
    return best;
  }

  static String _commonPrefix(String a, String b) {
    var i = 0;
    while (i < a.length && i < b.length && a.codeUnitAt(i) == b.codeUnitAt(i)) {
      i++;
    }
    return a.substring(0, i);
  }

  static Uri? _resolve(Uri source, String reference) {
    if (reference.isEmpty || reference.startsWith('#')) return null;
    return Uri.tryParse(reference)?.resolveUrisFromBase(source);
  }

  static String _rewriteUriAttribute(
    String line,
    Uri source,
    String Function(Uri uri) rewrite,
  ) {
    if (!line.startsWith('#') || !line.contains('URI="')) return line;
    return line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (match) {
      final uri = _resolve(source, match.group(1) ?? '');
      return uri == null ? match.group(0) ?? '' : 'URI="${rewrite(uri)}"';
    });
  }
}

extension on Uri {
  Uri resolveUrisFromBase(Uri base) => base.resolve(toString());
}
