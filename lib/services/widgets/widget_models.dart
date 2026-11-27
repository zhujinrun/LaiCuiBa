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
    this.widgetId = '',
    this.moduleId = '',
  });

  final String id;
  final String title;
  final SectionView view;
  final SectionSource source;

  /// 数据来源是资源分类时的 `type_id` 和界面上显示的分类名。
  final String categoryId;
  final String categoryName;

  /// 数据来源是组件仓库时的组件 id 与模块 id。
  final String widgetId;
  final String moduleId;

  PageSection copyWith({
    String? title,
    SectionView? view,
    SectionSource? source,
    String? categoryId,
    String? categoryName,
    String? widgetId,
    String? moduleId,
  }) => PageSection(
    id: id,
    title: title ?? this.title,
    view: view ?? this.view,
    source: source ?? this.source,
    categoryId: categoryId ?? this.categoryId,
    categoryName: categoryName ?? this.categoryName,
    widgetId: widgetId ?? this.widgetId,
    moduleId: moduleId ?? this.moduleId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'view': view.slug,
    'source': source.slug,
    'categoryId': categoryId,
    'categoryName': categoryName,
    'widgetId': widgetId,
    'moduleId': moduleId,
  };

  factory PageSection.fromJson(Map<String, dynamic> json) => PageSection(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    view: SectionView.parse(json['view'] as String? ?? ''),
    source: SectionSource.parse(json['source'] as String? ?? ''),
    categoryId: json['categoryId'] as String? ?? '',
    categoryName: json['categoryName'] as String? ?? '',
    widgetId: json['widgetId'] as String? ?? '',
    moduleId: json['moduleId'] as String? ?? '',
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

/// 一个组件仓库：脚本地址、JSON 索引或本地导入的文件，最终都落到本机脚本副本。
class WidgetRepo {
  const WidgetRepo({
    required this.id,
    required this.address,
    this.name = '',
    this.localPath = '',
    this.widgetIds = const [],
  });

  final String id;
  final String address;
  final String name;
  final String localPath;
  final List<String> widgetIds;

  String get displayName => name.trim().isEmpty ? '未命名组件仓库' : name.trim();

  Map<String, dynamic> toJson() => {
    'id': id,
    'address': address,
    'name': name,
    'localPath': localPath,
    'widgetIds': widgetIds,
  };

  factory WidgetRepo.fromJson(Map<String, dynamic> json) => WidgetRepo(
    id: json['id'] as String? ?? '',
    address: json['address'] as String? ?? '',
    name: json['name'] as String? ?? '',
    localPath: json['localPath'] as String? ?? '',
    widgetIds: [
      for (final raw in (json['widgetIds'] as List?) ?? const [])
        if (raw is String) raw,
    ],
  );
}

class WidgetModule {
  const WidgetModule({
    required this.id,
    required this.title,
    required this.functionName,
    this.type = 'media_list',
  });

  final String id;
  final String title;
  final String functionName;
  final String type;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'functionName': functionName,
    'type': type,
  };

  factory WidgetModule.fromJson(Map<String, dynamic> json) => WidgetModule(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    functionName: json['functionName'] as String? ?? '',
    type: json['type'] as String? ?? 'media_list',
  );
}

/// 仓库里的一只组件（脚本 + 从 WidgetMetadata 读出的模块列表）。
class WidgetInfo {
  const WidgetInfo({
    required this.id,
    required this.repoId,
    required this.scriptPath,
    this.title = '',
    this.description = '',
    this.version = '',
    this.author = '',
    this.group = '',
    this.modules = const [],
  });

  final String id;
  final String repoId;
  final String scriptPath;
  final String title;
  final String description;
  final String version;
  final String author;
  final String group;
  final List<WidgetModule> modules;

  String get displayName => title.trim().isEmpty ? '未命名组件' : title.trim();

  WidgetInfo copyWith({String? group}) => WidgetInfo(
    id: id,
    repoId: repoId,
    scriptPath: scriptPath,
    title: title,
    description: description,
    version: version,
    author: author,
    group: group ?? this.group,
    modules: modules,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'repoId': repoId,
    'scriptPath': scriptPath,
    'title': title,
    'description': description,
    'version': version,
    'author': author,
    'group': group,
    'modules': [for (final module in modules) module.toJson()],
  };

  factory WidgetInfo.fromJson(Map<String, dynamic> json) => WidgetInfo(
    id: json['id'] as String? ?? '',
    repoId: json['repoId'] as String? ?? '',
    scriptPath: json['scriptPath'] as String? ?? '',
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    version: json['version'] as String? ?? '',
    author: json['author'] as String? ?? '',
    group: json['group'] as String? ?? '',
    modules: [
      for (final raw in (json['modules'] as List?) ?? const [])
        if (raw is Map) WidgetModule.fromJson(Map<String, dynamic>.from(raw)),
    ],
  );
}

/// 组件代理。配置只保存在本机，不随备份同步（原版同一句说明）。
class WidgetProxy {
  const WidgetProxy({this.url = '', this.username = '', this.password = ''});

  final String url;
  final String username;
  final String password;

  bool get enabled => url.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'url': url,
    'username': username,
    'password': password,
  };

  factory WidgetProxy.fromJson(Map<String, dynamic> json) => WidgetProxy(
    url: json['url'] as String? ?? '',
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
  );
}
