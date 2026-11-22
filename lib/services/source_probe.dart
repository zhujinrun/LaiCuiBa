import '../models/models.dart';
import 'spider_session.dart';

/// What one 检测 run measured on a source.
///
/// The card shows three numbers and the store keeps four, so every field here
/// is something the probe actually observed -- no defaults borrowed from the
/// original's cached values. A source that never ran reports zeroes.
class ProbeReport {
  const ProbeReport({
    required this.latencyMs,
    this.movieCount = 0,
    this.showCount = 0,
    this.siteCount = 0,
    this.error,
    this.note,
  });

  const ProbeReport.failure(String message, {this.latencyMs = 0})
    : movieCount = 0,
      showCount = 0,
      siteCount = 0,
      error = message,
      note = null;

  /// Wall-clock time from "start the source" to "first page in hand". This is
  /// what the card prints as `0.4s`, so it includes bundle resolution and the
  /// worker booting -- the wait a user actually feels, not just one HTTP hop.
  final int latencyMs;

  /// Distinct titles seen on the home screen (the first page of each of the
  /// first [SourceProbe.maxCategories] categories). The card prints this as
  /// `当前使用 · 58 部`; it is a first-screen count, not the library total,
  /// because a library total would mean paging through every category.
  final int movieCount;

  /// Categories the source's `home` declared (电影 / 电视剧 / 动漫 …).
  final int showCount;

  /// Enabled sites behind the source.
  final int siteCount;

  /// Why the check failed. Null on success.
  final String? error;

  /// Something true but not fatal: the source answered but had nothing to show.
  final String? note;

  bool get ok => error == null;

  /// True when the probe proved the source can actually serve content, not just
  /// that a process started.
  bool get usable => ok && movieCount > 0;
}

/// Measures whether a 猫源 is actually usable, by running it.
///
/// This is the honest replacement for "the config parsed, so it must work": it
/// boots the bundle in the host, asks for the home screen, walks the first few
/// categories and reports what came back. Everything is inert -- a dead source
/// comes back as a [ProbeReport] with an error, never an exception.
class SourceProbe {
  const SourceProbe(this.session);

  final SpiderSession session;

  /// How many of the home screen's categories are paged for the title count.
  /// The original's card number is a first-screen figure; walking all of them
  /// would take a minute per source and change nothing the user can see.
  static const maxCategories = 4;

  Future<ProbeReport> run({
    required SourceInfo source,
    required String md5Url,
  }) async {
    final sites = source.searchableSites;
    if (sites.isEmpty) {
      return const ProbeReport.failure('配置里没有启用的站点');
    }

    final watch = Stopwatch()..start();
    // force: true -- 检测 must re-resolve the bundle, otherwise a subscription
    // that published new code keeps answering from the cached worker and the
    // numbers describe the old build.
    final loaded = await session.ensureLoaded(
      id: source.id,
      md5Url: md5Url,
      force: true,
    );
    if (!loaded) {
      watch.stop();
      return ProbeReport.failure(
        session.lastError ?? '源没起来',
        latencyMs: watch.elapsedMilliseconds,
      );
    }

    final site = _pickSite(source, sites);
    final classes = await session.home(
          sourceId: source.id,
          md5Url: md5Url,
          site: site,
        ) ??
        const [];

    final titles = <String>{};
    for (final category in classes.take(maxCategories)) {
      final list = await session.category(
        sourceId: source.id,
        md5Url: md5Url,
        site: site,
        tid: category.typeId,
      );
      for (final item in list.items) {
        // vod_id can repeat across categories (a title filed under two of
        // them); the card counts titles, so dedupe on the id.
        if (item.id.isNotEmpty) titles.add(item.id);
      }
    }
    watch.stop();

    if (classes.isEmpty && titles.isEmpty) {
      return ProbeReport(
        latencyMs: watch.elapsedMilliseconds,
        siteCount: sites.length,
        error: '源起来了，但 ${site.name} 的首页没有返回分类或片单',
      );
    }

    return ProbeReport(
      latencyMs: watch.elapsedMilliseconds,
      movieCount: titles.length,
      showCount: classes.length,
      siteCount: sites.length,
      note: titles.isEmpty ? '首页给了 ${classes.length} 个分类，但分类下暂时没有片单' : null,
    );
  }

  /// The site the home screen is drawn from: the source's `homeSite` when it is
  /// enabled, otherwise the first enabled one -- the same rule the store uses
  /// for [AppStore.homeSite], so the probe measures what the user sees.
  SiteInfo _pickSite(SourceInfo source, List<SiteInfo> sites) {
    for (final site in sites) {
      if (site.key == source.homeSite) return site;
    }
    return sites.first;
  }
}
