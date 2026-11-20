import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/models.dart';
import '../services/search.dart';
import '../services/spider_session.dart';

/// State behind the 搜索 mode: whether it is open, what has been typed, whether
/// the query has been committed, and the 严格 toggle.
///
/// The header field and the page body share this one object, which is why it is
/// exposed through [LcbSearchScope] rather than passed down: the field lives in
/// the shell's header while the results live in the content column.
///
/// Search is async now: a committed query first shows the demo catalogue
/// instantly, then asks the real spider (when a runtime is wired) and swaps the
/// results in when they land. A failed or empty real search falls back to the
/// demo answers, so the page never goes blank.
class LcbSearch extends ChangeNotifier {
  LcbSearch({this.sitesProvider, this.realSearchStream});

  /// Resolves "which sites should this fan out to" from the current selection.
  ///
  /// Injected rather than read from a global so the source list stays owned by
  /// the store: deleting a source, silencing one of its sites, or adding a
  /// freshly pasted config all change what the next search sees, with no
  /// rebuild plumbing in between.
  final List<SiteInfo> Function(Set<String>? selection)? sitesProvider;

  /// Reaches the real spider as a stream that emits one site's hits at a time,
  /// in completion order, so the page can show each site's results as they
  /// arrive instead of waiting for the slowest site. Returns null when no
  /// runtime is wired, in which case the demo catalogue answers. Injected so
  /// the store owns the session.
  final Stream<SpiderSearchSite>? Function(String keyword, {bool strict})?
      realSearchStream;

  final TextEditingController text = TextEditingController();
  final FocusNode focus = FocusNode();

  bool _open = false;
  String _query = '';
  bool _strict = false;
  bool _submitted = false;
  bool _loading = false;
  String? _site;
  SearchOutcome _outcome = const SearchOutcome(hits: [], sites: []);

  /// Guards against a stale response overwriting a newer query: each submit
  /// bumps the generation and only the matching response is kept.
  int _generation = 0;

  /// The active stream subscription, cancelled when a newer submit supersedes
  /// it or the controller is disposed.
  StreamSubscription<SpiderSearchSite>? _searchSub;

  bool get isOpen => _open;
  String get query => _query;
  bool get strict => _strict;
  bool get submitted => _submitted;
  bool get loading => _loading;

  /// Non-null when one site's chip is selected; null means 全部.
  String? get site => _site;

  /// Which sources the fan-out should hit. Null means "all of them", which is
  /// the state the page starts in; an empty set means the user removed every
  /// source with 取消选择"全部", and then there is nothing to search.
  Set<String>? _sources;

  Set<String>? get selection => _sources;

  bool isSourceSelected(String id) => _sources?.contains(id) ?? true;

  bool get anySource => _sources == null || _sources!.isNotEmpty;

  /// Results for the committed query. Replaced in place once the real search
  /// lands; empty until the first commit.
  SearchOutcome get outcome => _outcome;

  /// Suggestions shown while typing, before the query is committed.
  List<String> get suggestions => _submitted ? const [] : suggestionsFor(_query);

  /// The chips plus the rows, after the site filter is applied.
  List<SearchHit> get visibleHits {
    final all = outcome.hits;
    if (_site == null) return all;
    return all.where((hit) => hit.site == _site).toList(growable: false);
  }

  int get visibleTotal => visibleHits.length;

  void open() {
    if (_open) return;
    _open = true;
    _query = '';
    _submitted = false;
    _loading = false;
    _site = null;
    _outcome = const SearchOutcome(hits: [], sites: []);
    text.clear();
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    _query = '';
    _submitted = false;
    _loading = false;
    _site = null;
    _outcome = const SearchOutcome(hits: [], sites: []);
    _cancelSearch();
    text.clear();
    focus.unfocus();
    notifyListeners();
  }

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    _submitted = false;
    _loading = false;
    _site = null;
    _outcome = const SearchOutcome(hits: [], sites: []);
    _cancelSearch();
    notifyListeners();
  }

  /// Cancels any in-flight streamed search, marking it superseded.
  void _cancelSearch() {
    _searchSub?.cancel();
    _searchSub = null;
  }

  /// Commits the current query, which is what Enter and a suggestion tap do.
  ///
  /// With a real spider wired, the demo catalogue must not flash first: its
  /// rows (except 尚公主) carry no episode data, so a user tapping one before
  /// the real results land would land on an empty detail page. Show the loading
  /// state until the first site responds, then append each subsequent site's
  /// hits as they arrive (谁先响应谁先显示), and only fall back to the demo
  /// catalogue when no runtime is present or every site came back empty.
  void submit() {
    if (_query.trim().isEmpty) return;
    _submitted = true;
    focus.unfocus();

    final gen = ++_generation;
    // Cancel any in-flight search from a previous submit.
    _cancelSearch();
    final streamFn = realSearchStream;
    if (streamFn == null) {
      _outcome = _demoOutcome(_query);
      _loading = false;
      notifyListeners();
      return;
    }
    // Real source available: hold the demo catalogue back so it cannot win the
    // race against a slow fan-out and hand the user an episode-less row.
    _outcome = const SearchOutcome(hits: [], sites: []);
    _loading = true;
    notifyListeners();

    final groups = <SpiderSearchSite>[];
    var gotAny = false;
    final stream = streamFn(_query, strict: _strict);
    if (stream == null) {
      _outcome = _demoOutcome(_query);
      _loading = false;
      notifyListeners();
      return;
    }
    _searchSub = stream.listen(
      (group) {
        if (gen != _generation || !_submitted) return;
        gotAny = true;
        groups.add(group);
        _outcome = _fromSpiderGroups(groups);
        _loading = false;
        notifyListeners();
      },
      onError: (Object _) {
        _finish(gen, groups, gotAny);
      },
      onDone: () {
        _finish(gen, groups, gotAny);
      },
      cancelOnError: true,
    );
  }

  /// Wraps up a streamed search: clear loading and, if nothing landed, fall
  /// back to the demo catalogue so the page never goes blank.
  void _finish(int gen, List<SpiderSearchSite> groups, bool gotAny) {
    if (gen != _generation || !_submitted) return;
    _loading = false;
    if (!gotAny) {
      _outcome = _demoOutcome(_query);
    }
    notifyListeners();
  }

  void pickSuggestion(String suggestion) {
    text.text = suggestion;
    text.selection = TextSelection.collapsed(offset: suggestion.length);
    _query = suggestion;
    _submitted = true;
    _site = null;
    focus.unfocus();
    submit();
  }

  void toggleStrict() {
    _strict = !_strict;
    // The result set is cached now, so flipping the toggle must re-run the
    // query (exact-match changes which titles come back).
    if (_submitted && _query.trim().isNotEmpty) {
      submit();
      return;
    }
    notifyListeners();
  }

  void selectSite(String? site) {
    if (site == _site) return;
    _site = site;
    notifyListeners();
  }

  /// Adds or removes one source from the fan-out.
  ///
  /// [all] is passed in rather than held here because the source list lives in
  /// the store and can change while the page is open.
  void toggleSource(String id, Iterable<String> all) {
    final next = _sources == null ? all.toSet() : Set<String>.from(_sources!);
    if (!next.remove(id)) next.add(id);
    _sources = next;
    notifyListeners();
  }

  /// 取消选择"全部" -- keeps the list but empties the selection.
  void clearSources() {
    _sources = <String>{};
    notifyListeners();
  }

  void selectAllSources() {
    _sources = null;
    notifyListeners();
  }

  void clearQuery() {
    text.clear();
    setQuery('');
  }

  /// The demo-catalogue answer, computed synchronously so results never lag.
  SearchOutcome _demoOutcome(String query) => _submitted && anySource
      ? searchCatalogue(
          query,
          strict: _strict,
          sites: sitesProvider?.call(_sources) ?? const [],
        )
      : const SearchOutcome(hits: [], sites: []);

  /// Maps a set of spider search groups onto the same shape the page renders.
  /// Takes the accumulated groups so each newly-arrived site simply appends.
  SearchOutcome _fromSpiderGroups(List<SpiderSearchSite> groups) {
    final hits = <SearchHit>[];
    final summaries = <SearchSiteSummary>[];
    for (final group in groups) {
      summaries.add(
        SearchSiteSummary(site: group.site, count: group.items.length),
      );
      for (final item in group.items) {
        hits.add(
          SearchHit(
            item: item,
            site: group.site,
            remarks: item.latest?.isNotEmpty == true ? item.latest! : '完结',
          ),
        );
      }
    }
    return SearchOutcome(hits: hits, sites: summaries);
  }

  @override
  void dispose() {
    _cancelSearch();
    text.dispose();
    focus.dispose();
    super.dispose();
  }
}

/// Makes [LcbSearch] reachable from the header and the content column.
class LcbSearchScope extends InheritedNotifier<LcbSearch> {
  const LcbSearchScope({
    super.key,
    required LcbSearch search,
    required super.child,
  }) : super(notifier: search);

  static LcbSearch of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LcbSearchScope>();
    assert(scope != null, 'LcbSearchScope missing above this widget');
    return scope!.notifier!;
  }
}
