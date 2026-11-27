/// Removes ad pods that an upstream CDN splices into an HLS playlist.
///
/// The LZ line of 尚公主 currently serves a media playlist that literally
/// contains `# ppvod-ad-injected v1`, then seven TS segments from a different
/// video directory, then a second discontinuity. mpv honours that splice: it
/// shows the ad, reports a new timeline and the progress bar lands back at
/// 00:00. The stream itself is fine — only the playlist is polluted.
///
/// This filter is deliberately conservative: it only drops a segment when its
/// URI does not share the dominant prefix of the playlist, and it drops the
/// surrounding discontinuity markers with it so the remaining timeline stays
/// continuous.
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
