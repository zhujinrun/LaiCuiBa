import '../models/models.dart';
import 'source_probe.dart' show ProbeReport;

/// What a media mount can answer, regardless of the protocol behind it.
///
/// Two kinds of source are "mounts": an Emby / Jellyfin server (JSON API) and a
/// WebDAV share such as AList, 群晖 or 坚果云 (PROPFIND). They have nothing in
/// common at the wire level, but the app only ever asks four questions -- list
/// the library, search it, expand one title, and give me a playable URL -- so
/// the pages and the store talk to this interface instead of either client.
///
/// Deliberately narrow: anything a mount cannot answer (no `home` categories,
/// no `play` action, no spider bundle) stays out, which is what keeps the mount
/// path from growing a second copy of the 猫源 code.
abstract class MediaMount {
  /// Display name, stamped onto every record this mount produces so the detail
  /// page and the player can say where a title came from.
  String get sourceName;

  /// Top-level entries, newest first. Used by the home rails.
  Future<List<MediaItem>> library({int limit = 24});

  /// Titles matching [keyword]; an empty keyword means "everything".
  Future<List<MediaItem>> search(String keyword, {int limit = 60});

  /// Fills in what a list row cannot carry: overview, cast, and the episode
  /// list with playable URLs.
  Future<MediaItem> detail(MediaItem item);

  /// Measures the mount for `重新检测`, in the same shape a 猫源 probe reports.
  Future<ProbeReport> probe();

  /// Playable URL for one record id.
  String streamUrl(String itemId);

  /// Extra headers the player needs to fetch [streamUrl].
  ///
  /// Emby puts its token in the query string, so it needs nothing; WebDAV
  /// authenticates on every request and returns a Basic header here. Kept on
  /// the mount rather than on [MediaItem] so a credential never rides along in
  /// a poster record that may be persisted.
  Map<String, String> get playbackHeaders => const {};

  /// Releases whatever the client holds. Called by the caller after every use;
  /// a mount client is built per request from the persisted source.
  void close();
}

/// A mount that refused a request, with wording fit for the UI.
class MountException implements Exception {
  const MountException(this.message);

  /// Already in the user's language: "账号或密码不对", "路径不存在", …
  final String message;

  @override
  String toString() => message;
}
