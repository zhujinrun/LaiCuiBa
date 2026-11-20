import 'package:flutter/widgets.dart';

import '../models/models.dart';
import '../services/search.dart';

/// State behind the 搜索 mode: whether it is open, what has been typed, whether
/// the query has been committed, and the 严格 toggle.
///
/// The header field and the page body share this one object, which is why it is
/// exposed through [LcbSearchScope] rather than passed down: the field lives in
/// the shell's header while the results live in the content column.
class LcbSearch extends ChangeNotifier {
  LcbSearch({this.sitesProvider});

  /// Resolves "which sites should this fan out to" from the current selection.
  ///
  /// Injected rather than read from a global so the source list stays owned by
  /// the store: deleting a source, silencing one of its sites, or adding a
  /// freshly pasted config all change what the next search sees, with no
  /// rebuild plumbing in between.
  final List<SiteInfo> Function(Set<String>? selection)? sitesProvider;

  final TextEditingController text = TextEditingController();
  final FocusNode focus = FocusNode();

  bool _open = false;
  String _query = '';
  bool _strict = false;
  bool _submitted = false;
  String? _site;

  bool get isOpen => _open;
  String get query => _query;
  bool get strict => _strict;
  bool get submitted => _submitted;

  /// Non-null when one site's chip is selected; null means 全部.
  String? get site => _site;

  /// Which sources the fan-out should hit. Null means "all of them", which is
  /// the state the page starts in; an empty set means the user removed every
  /// source with 取消选择"全部", and then there is nothing to search.
  Set<String>? _sources;

  Set<String>? get selection => _sources;

  bool isSourceSelected(String id) => _sources?.contains(id) ?? true;

  bool get anySource => _sources == null || _sources!.isNotEmpty;

  /// Results for the committed query, recomputed on read. The catalogue is a
  /// few dozen titles, so caching would cost more than it saves.
  ///
  /// With no source selected there is nothing to fan out to, which the page
  /// reports as 未选择搜索源 rather than as an empty result set.
  SearchOutcome get outcome => _submitted && anySource
      ? searchCatalogue(
          _query,
          strict: _strict,
          sites: sitesProvider?.call(_sources) ?? const [],
        )
      : const SearchOutcome(hits: [], sites: []);

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
    _site = null;
    text.clear();
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _open = false;
    _query = '';
    _submitted = false;
    _site = null;
    text.clear();
    focus.unfocus();
    notifyListeners();
  }

  void setQuery(String value) {
    if (value == _query) return;
    _query = value;
    _submitted = false;
    _site = null;
    notifyListeners();
  }

  /// Commits the current query, which is what Enter and a suggestion tap do.
  void submit() {
    if (_query.trim().isEmpty) return;
    _submitted = true;
    focus.unfocus();
    notifyListeners();
  }

  void pickSuggestion(String suggestion) {
    text.text = suggestion;
    text.selection = TextSelection.collapsed(offset: suggestion.length);
    _query = suggestion;
    _submitted = true;
    _site = null;
    focus.unfocus();
    notifyListeners();
  }

  void toggleStrict() {
    _strict = !_strict;
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

  @override
  void dispose() {
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
