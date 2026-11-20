/// FNV-1a over UTF-16 code units.
///
/// Used wherever a fixture has to be pinned to one of the configured sites
/// without a server telling us which: the search fan-out decides "does this
/// title live on this site" with it, and the store attributes its demo cards to
/// the source's home site with the same idea. Deterministic on purpose, so
/// counts and labels do not shuffle between rebuilds.
int stableHash(String value) {
  var hash = 0x811C9DC5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}
