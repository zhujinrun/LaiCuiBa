/// 自定义页面 / 组件区域的模型。
///
/// 原版对应 `services/widgets/widget_models.dart`。页面由「组件区域」组成，
/// 一个区域 = 展示方式 + 数据来源。文案取自 `so_strings_utf16.txt`：
/// `点下方 + 新增组件区域：先选展示方式，再选数据来自哪个组件仓库、TMDB 或资源的分类。`
library;

/// 区域展示方式，slug 会写进设置，中文只用于界面。
enum SectionView {
  rail('rail', '顶部横排'),
  grid('grid', '网格排列'),
  list('list', '列表排列'),
  hero('hero', '轮播图');

  const SectionView(this.slug, this.label);

  final String slug;
  final String label;

  static SectionView parse(String raw) =>
      SectionView.values.firstWhere(
        (view) => view.slug == raw,
        orElse: () => SectionView.rail,
      );
}

/// 区域数据来源。组件仓库和 TMDB 还没有真数据源时，界面照原版摆出这两个
/// 选项，但会明说「还没接」，不拿假数据冒充。
enum SectionSource {
  category('category', '资源分类'),
  widget('widget', '组件仓库'),
  tmdb('tmdb', 'TMDB');

  const SectionSource(this.slug, this.label);

  final String slug;
  final String label;

  static SectionSource parse(String raw) =>
      SectionSource.values.firstWhere(
        (source) => source.slug == raw,
        orElse: () => SectionSource.category,
      );
}

class PageSection {
  const PageSection({
    required this.id,
    this.title = '',
    this.view = SectionView.rail,
    this.source = SectionSource.category,
    this.categoryId = '',
    this.categoryName = '',
  });

  final String id;
  final String title;
  final SectionView view;
  final SectionSource source;

  /// 数据来源是资源分类时的 `type_id` 和界面上显示的分类名。
  final String categoryId;
  final String categoryName;

  PageSection copyWith({
    String? title,
    SectionView? view,
    SectionSource? source,
    String? categoryId,
    String? categoryName,
  }) => PageSection(
    id: id,
    title: title ?? this.title,
    view: view ?? this.view,
    source: source ?? this.source,
    categoryId: categoryId ?? this.categoryId,
    categoryName: categoryName ?? this.categoryName,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'view': view.slug,
    'source': source.slug,
    'categoryId': categoryId,
    'categoryName': categoryName,
  };

  factory PageSection.fromJson(Map<String, dynamic> json) => PageSection(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    view: SectionView.parse(json['view'] as String? ?? ''),
    source: SectionSource.parse(json['source'] as String? ?? ''),
    categoryId: json['categoryId'] as String? ?? '',
    categoryName: json['categoryName'] as String? ?? '',
  );
}

class CustomPage {
  const CustomPage({
    required this.id,
    this.name = '',
    this.iconId = '',
    this.translucent = false,
    this.sections = const [],
  });

  final String id;
  final String name;
  final String iconId;

  /// 原版「页面底色会变成半透明，背景图从下面透出来；…只保存在本机」。
  final bool translucent;
  final List<PageSection> sections;

  CustomPage copyWith({
    String? name,
    String? iconId,
    bool? translucent,
    List<PageSection>? sections,
  }) => CustomPage(
    id: id,
    name: name ?? this.name,
    iconId: iconId ?? this.iconId,
    translucent: translucent ?? this.translucent,
    sections: sections ?? this.sections,
  );

  String get displayName => name.trim().isEmpty ? '未命名页面' : name.trim();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'iconId': iconId,
    'translucent': translucent,
    'sections': [for (final section in sections) section.toJson()],
  };

  factory CustomPage.fromJson(Map<String, dynamic> json) => CustomPage(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    iconId: json['iconId'] as String? ?? '',
    translucent: json['translucent'] as bool? ?? false,
    sections: [
      for (final raw in (json['sections'] as List?) ?? const [])
        if (raw is Map) PageSection.fromJson(Map<String, dynamic>.from(raw)),
    ],
  );
}

String newPageId() => 'page-${DateTime.now().microsecondsSinceEpoch}';

String newSectionId() => 'section-${DateTime.now().microsecondsSinceEpoch}';
