/// What the player needs to open one episode: the URL and whatever headers the
/// source requires alongside it.
///
/// Kept as one value rather than two calls because the two answers come from the
/// same place -- a mount's Basic auth, a TVBox source's `header` field -- and
/// resolving them separately would either open the player twice or play the
/// first second without the header the CDN wants.
class PlayTarget {
  const PlayTarget({required this.url, this.headers = const {}});

  final String url;
  final Map<String, String> headers;
}
