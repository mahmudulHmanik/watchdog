import 'package:watchdog/data/models.dart' show CategoryDraft, TitleKind;

/// How a category folder is laid out. Drives the crawl walker.
enum LayoutKind {
  /// `Category/(Year)/Title/files`; buckets are plain containers.
  yearBuckets,

  /// `Category/Title/files`.
  flat,

  /// `[Bucket/]Show/Season/files`; buckets (A-Z) are flattened.
  series,

  /// Event folders (WWE, awards): classified like movies, kind = event.
  events,
}

T _enumByName<T extends Enum>(List<T> values, Object? name, String what) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  throw FormatException('Unknown $what: $name');
}

/// One crawlable category folder on a server.
class CategoryConfig {
  const CategoryConfig({
    required this.name,
    required this.url,
    required this.layout,
    required this.kind,
    this.language,
    this.enabled = true,
  });

  final String name;

  /// Absolute root URL of the category folder (percent-encoded, trailing '/').
  final String url;
  final LayoutKind layout;
  final TitleKind kind;

  /// Lower-case language name, null for mixed/unknown.
  final String? language;
  final bool enabled;

  /// Crawl-side category descriptor (url normalised with a trailing '/').
  CategoryDraft toDraft(String host) => CategoryDraft(
    sourceHost: host,
    name: name,
    url: url.endsWith('/') ? url : '$url/',
    language: language,
  );

  CategoryConfig copyWith({
    String? name,
    String? url,
    LayoutKind? layout,
    TitleKind? kind,
    String? language,
    bool clearLanguage = false,
    bool? enabled,
  }) => CategoryConfig(
    name: name ?? this.name,
    url: url ?? this.url,
    layout: layout ?? this.layout,
    kind: kind ?? this.kind,
    language: clearLanguage ? null : (language ?? this.language),
    enabled: enabled ?? this.enabled,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'url': url,
    'layout': layout.name,
    'kind': kind.name,
    'language': language,
    'enabled': enabled,
  };

  factory CategoryConfig.fromJson(Map<String, Object?> j) => CategoryConfig(
    name: j['name'] as String,
    url: j['url'] as String,
    layout: _enumByName(LayoutKind.values, j['layout'], 'layout'),
    kind: _enumByName(TitleKind.values, j['kind'], 'kind'),
    language: j['language'] as String?,
    enabled: (j['enabled'] as bool?) ?? true,
  );
}

/// One media server (host) and its categories.
class ServerConfig {
  const ServerConfig({
    required this.host,
    this.enabled = true,
    this.categories = const [],
  });

  /// Host or host:port, no scheme (e.g. `172.16.50.7`).
  final String host;
  final bool enabled;
  final List<CategoryConfig> categories;

  /// Portal/root page used for reachability probes.
  Uri get rootUri => Uri.parse('http://$host/');

  ServerConfig copyWith({
    String? host,
    bool? enabled,
    List<CategoryConfig>? categories,
  }) => ServerConfig(
    host: host ?? this.host,
    enabled: enabled ?? this.enabled,
    categories: categories ?? this.categories,
  );

  Map<String, Object?> toJson() => {
    'host': host,
    'enabled': enabled,
    'categories': [for (final c in categories) c.toJson()],
  };

  factory ServerConfig.fromJson(Map<String, Object?> j) => ServerConfig(
    host: j['host'] as String,
    enabled: (j['enabled'] as bool?) ?? true,
    categories: [
      for (final c in (j['categories'] as List? ?? const []))
        CategoryConfig.fromJson((c as Map).cast<String, Object?>()),
    ],
  );
}

/// Editable server/category list. Defaults hold the public DhakaFlix layout
/// only; `.8` (games/software) and the `.10` Tutorial folder are left out.
class CrawlConfig {
  const CrawlConfig({this.servers = const []});

  static const currentVersion = 1;

  final List<ServerConfig> servers;

  /// Enabled categories on enabled servers, paired with their server.
  Iterable<(ServerConfig, CategoryConfig)> get enabledCategories sync* {
    for (final s in servers.where((s) => s.enabled)) {
      for (final c in s.categories.where((c) => c.enabled)) {
        yield (s, c);
      }
    }
  }

  CrawlConfig copyWith({List<ServerConfig>? servers}) =>
      CrawlConfig(servers: servers ?? this.servers);

  Map<String, Object?> toJson() => {
    'version': currentVersion,
    'servers': [for (final s in servers) s.toJson()],
  };

  factory CrawlConfig.fromJson(Map<String, Object?> j) => CrawlConfig(
    servers: [
      for (final s in (j['servers'] as List? ?? const []))
        ServerConfig.fromJson((s as Map).cast<String, Object?>()),
    ],
  );

  factory CrawlConfig.defaults() => _defaults;
}

CategoryConfig _movies(
  String name,
  String url, {
  String? language,
  LayoutKind layout = LayoutKind.yearBuckets,
}) => CategoryConfig(
  name: name,
  url: url,
  layout: layout,
  kind: TitleKind.movie,
  language: language,
);

const _s7 = 'http://172.16.50.7/DHAKA-FLIX-7/';
const _s10 = 'http://172.16.50.10/DHAKA-FLIX-10/';
const _s12 = 'http://172.16.50.12/DHAKA-FLIX-12/';
const _s14 = 'http://172.16.50.14/DHAKA-FLIX-14/';

final CrawlConfig _defaults = CrawlConfig(
  servers: [
    ServerConfig(
      host: '172.16.50.7',
      categories: [
        _movies(
          'English Movies',
          '${_s7}English%20Movies/',
          language: 'english',
        ),
        _movies(
          'Foreign Language Movies',
          '${_s7}Foreign%20Language%20Movies/',
          layout: LayoutKind.flat,
        ),
        _movies(
          'Kolkata Bangla Movies',
          '${_s7}Kolkata%20Bangla%20Movies/',
          language: 'bengali',
        ),
        _movies('3D Movies', '${_s7}3D%20Movies/', layout: LayoutKind.flat),
      ],
    ),
    ServerConfig(
      host: '172.16.50.10',
      categories: [
        const CategoryConfig(
          name: 'Anime & Cartoon',
          url: '${_s10}Anime%20%26%20Cartoon%20TV%20Series/',
          layout: LayoutKind.series,
          kind: TitleKind.series,
        ),
        _movies('Documentary', '${_s10}Documentary/', layout: LayoutKind.flat),
        const CategoryConfig(
          name: 'WWE & AEW',
          url: '${_s10}WWE%20%26%20AEW%20Wrestling/',
          layout: LayoutKind.events,
          kind: TitleKind.event,
          language: 'english',
        ),
        const CategoryConfig(
          name: 'Awards & TV Shows',
          url: '${_s10}Awards%20%26%20TV%20Shows/',
          layout: LayoutKind.events,
          kind: TitleKind.event,
        ),
      ],
    ),
    ServerConfig(
      host: '172.16.50.12',
      categories: [
        const CategoryConfig(
          name: 'TV & Web Series',
          url: '${_s12}TV-WEB-Series/',
          layout: LayoutKind.series,
          kind: TitleKind.series,
        ),
      ],
    ),
    ServerConfig(
      host: '172.16.50.14',
      categories: [
        _movies(
          'English Movies 1080p',
          '${_s14}English%20Movies%20%281080p%29/',
          language: 'english',
        ),
        _movies('Hindi Movies', '${_s14}Hindi%20Movies/', language: 'hindi'),
        _movies(
          'South Movies',
          '${_s14}SOUTH%20INDIAN%20MOVIES/South%20Movies/',
        ),
        _movies(
          'South Hindi Dubbed',
          '${_s14}SOUTH%20INDIAN%20MOVIES/Hindi%20Dubbed/',
          language: 'hindi',
        ),
        _movies('Animation Movies', '${_s14}Animation%20Movies/'),
        _movies(
          'Animation Movies 1080p',
          '${_s14}Animation%20Movies%20%281080p%29/',
          layout: LayoutKind.flat,
        ),
        _movies(
          'IMDb Top-250',
          '${_s14}IMDb%20Top-250%20Movies/',
          layout: LayoutKind.flat,
        ),
        const CategoryConfig(
          name: 'Korean TV & Web Series',
          url: '${_s14}KOREAN%20TV%20%26%20WEB%20Series/',
          layout: LayoutKind.series,
          kind: TitleKind.series,
          language: 'korean',
        ),
      ],
    ),
  ],
);
