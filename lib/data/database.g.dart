// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $SourcesTable extends Sources with TableInfo<$SourcesTable, SourceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, host];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<SourceRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SourceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
    );
  }

  @override
  $SourcesTable createAlias(String alias) {
    return $SourcesTable(attachedDatabase, alias);
  }
}

class SourceRow extends DataClass implements Insertable<SourceRow> {
  final int id;
  final String host;
  const SourceRow({required this.id, required this.host});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['host'] = Variable<String>(host);
    return map;
  }

  SourcesCompanion toCompanion(bool nullToAbsent) {
    return SourcesCompanion(id: Value(id), host: Value(host));
  }

  factory SourceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourceRow(
      id: serializer.fromJson<int>(json['id']),
      host: serializer.fromJson<String>(json['host']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'host': serializer.toJson<String>(host),
    };
  }

  SourceRow copyWith({int? id, String? host}) =>
      SourceRow(id: id ?? this.id, host: host ?? this.host);
  SourceRow copyWithCompanion(SourcesCompanion data) {
    return SourceRow(
      id: data.id.present ? data.id.value : this.id,
      host: data.host.present ? data.host.value : this.host,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SourceRow(')
          ..write('id: $id, ')
          ..write('host: $host')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, host);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceRow && other.id == this.id && other.host == this.host);
}

class SourcesCompanion extends UpdateCompanion<SourceRow> {
  final Value<int> id;
  final Value<String> host;
  const SourcesCompanion({
    this.id = const Value.absent(),
    this.host = const Value.absent(),
  });
  SourcesCompanion.insert({
    this.id = const Value.absent(),
    required String host,
  }) : host = Value(host);
  static Insertable<SourceRow> custom({
    Expression<int>? id,
    Expression<String>? host,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (host != null) 'host': host,
    });
  }

  SourcesCompanion copyWith({Value<int>? id, Value<String>? host}) {
    return SourcesCompanion(id: id ?? this.id, host: host ?? this.host);
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourcesCompanion(')
          ..write('id: $id, ')
          ..write('host: $host')
          ..write(')'))
        .toString();
  }
}

class $CategoriesTable extends Categories
    with TableInfo<$CategoriesTable, CategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<int> sourceId = GeneratedColumn<int>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sources (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, sourceId, name, url, language];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'categories';
  @override
  VerificationContext validateIntegrity(
    Insertable<CategoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}source_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      ),
    );
  }

  @override
  $CategoriesTable createAlias(String alias) {
    return $CategoriesTable(attachedDatabase, alias);
  }
}

class CategoryRow extends DataClass implements Insertable<CategoryRow> {
  final int id;
  final int sourceId;
  final String name;
  final String url;
  final String? language;
  const CategoryRow({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.url,
    this.language,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['source_id'] = Variable<int>(sourceId);
    map['name'] = Variable<String>(name);
    map['url'] = Variable<String>(url);
    if (!nullToAbsent || language != null) {
      map['language'] = Variable<String>(language);
    }
    return map;
  }

  CategoriesCompanion toCompanion(bool nullToAbsent) {
    return CategoriesCompanion(
      id: Value(id),
      sourceId: Value(sourceId),
      name: Value(name),
      url: Value(url),
      language: language == null && nullToAbsent
          ? const Value.absent()
          : Value(language),
    );
  }

  factory CategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryRow(
      id: serializer.fromJson<int>(json['id']),
      sourceId: serializer.fromJson<int>(json['sourceId']),
      name: serializer.fromJson<String>(json['name']),
      url: serializer.fromJson<String>(json['url']),
      language: serializer.fromJson<String?>(json['language']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourceId': serializer.toJson<int>(sourceId),
      'name': serializer.toJson<String>(name),
      'url': serializer.toJson<String>(url),
      'language': serializer.toJson<String?>(language),
    };
  }

  CategoryRow copyWith({
    int? id,
    int? sourceId,
    String? name,
    String? url,
    Value<String?> language = const Value.absent(),
  }) => CategoryRow(
    id: id ?? this.id,
    sourceId: sourceId ?? this.sourceId,
    name: name ?? this.name,
    url: url ?? this.url,
    language: language.present ? language.value : this.language,
  );
  CategoryRow copyWithCompanion(CategoriesCompanion data) {
    return CategoryRow(
      id: data.id.present ? data.id.value : this.id,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      name: data.name.present ? data.name.value : this.name,
      url: data.url.present ? data.url.value : this.url,
      language: data.language.present ? data.language.value : this.language,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRow(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('language: $language')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sourceId, name, url, language);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRow &&
          other.id == this.id &&
          other.sourceId == this.sourceId &&
          other.name == this.name &&
          other.url == this.url &&
          other.language == this.language);
}

class CategoriesCompanion extends UpdateCompanion<CategoryRow> {
  final Value<int> id;
  final Value<int> sourceId;
  final Value<String> name;
  final Value<String> url;
  final Value<String?> language;
  const CategoriesCompanion({
    this.id = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.name = const Value.absent(),
    this.url = const Value.absent(),
    this.language = const Value.absent(),
  });
  CategoriesCompanion.insert({
    this.id = const Value.absent(),
    required int sourceId,
    required String name,
    required String url,
    this.language = const Value.absent(),
  }) : sourceId = Value(sourceId),
       name = Value(name),
       url = Value(url);
  static Insertable<CategoryRow> custom({
    Expression<int>? id,
    Expression<int>? sourceId,
    Expression<String>? name,
    Expression<String>? url,
    Expression<String>? language,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourceId != null) 'source_id': sourceId,
      if (name != null) 'name': name,
      if (url != null) 'url': url,
      if (language != null) 'language': language,
    });
  }

  CategoriesCompanion copyWith({
    Value<int>? id,
    Value<int>? sourceId,
    Value<String>? name,
    Value<String>? url,
    Value<String?>? language,
  }) {
    return CategoriesCompanion(
      id: id ?? this.id,
      sourceId: sourceId ?? this.sourceId,
      name: name ?? this.name,
      url: url ?? this.url,
      language: language ?? this.language,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<int>(sourceId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoriesCompanion(')
          ..write('id: $id, ')
          ..write('sourceId: $sourceId, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('language: $language')
          ..write(')'))
        .toString();
  }
}

class $TitlesTable extends Titles with TableInfo<$TitlesTable, TitleRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TitlesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<int> categoryId = GeneratedColumn<int>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES categories (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortKeyMeta = const VerificationMeta(
    'sortKey',
  );
  @override
  late final GeneratedColumn<String> sortKey = GeneratedColumn<String>(
    'sort_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<TitleKind, int> kind =
      GeneratedColumn<int>(
        'kind',
        aliasedName,
        false,
        type: DriftSqlType.int,
        requiredDuringInsert: true,
      ).withConverter<TitleKind>($TitlesTable.$converterkind);
  static const VerificationMeta _folderUrlMeta = const VerificationMeta(
    'folderUrl',
  );
  @override
  late final GeneratedColumn<String> folderUrl = GeneratedColumn<String>(
    'folder_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _yearMeta = const VerificationMeta('year');
  @override
  late final GeneratedColumn<int> year = GeneratedColumn<int>(
    'year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _yearEndMeta = const VerificationMeta(
    'yearEnd',
  );
  @override
  late final GeneratedColumn<int> yearEnd = GeneratedColumn<int>(
    'year_end',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _qualityMeta = const VerificationMeta(
    'quality',
  );
  @override
  late final GeneratedColumn<int> quality = GeneratedColumn<int>(
    'quality',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _posterUrlMeta = const VerificationMeta(
    'posterUrl',
  );
  @override
  late final GeneratedColumn<String> posterUrl = GeneratedColumn<String>(
    'poster_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _folderMtimeMeta = const VerificationMeta(
    'folderMtime',
  );
  @override
  late final GeneratedColumn<DateTime> folderMtime = GeneratedColumn<DateTime>(
    'folder_mtime',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seasonCountMeta = const VerificationMeta(
    'seasonCount',
  );
  @override
  late final GeneratedColumn<int> seasonCount = GeneratedColumn<int>(
    'season_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fileCountMeta = const VerificationMeta(
    'fileCount',
  );
  @override
  late final GeneratedColumn<int> fileCount = GeneratedColumn<int>(
    'file_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    categoryId,
    name,
    sortKey,
    kind,
    folderUrl,
    year,
    yearEnd,
    quality,
    tags,
    posterUrl,
    language,
    folderMtime,
    addedAt,
    seasonCount,
    fileCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'titles';
  @override
  VerificationContext validateIntegrity(
    Insertable<TitleRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_key')) {
      context.handle(
        _sortKeyMeta,
        sortKey.isAcceptableOrUnknown(data['sort_key']!, _sortKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_sortKeyMeta);
    }
    if (data.containsKey('folder_url')) {
      context.handle(
        _folderUrlMeta,
        folderUrl.isAcceptableOrUnknown(data['folder_url']!, _folderUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_folderUrlMeta);
    }
    if (data.containsKey('year')) {
      context.handle(
        _yearMeta,
        year.isAcceptableOrUnknown(data['year']!, _yearMeta),
      );
    }
    if (data.containsKey('year_end')) {
      context.handle(
        _yearEndMeta,
        yearEnd.isAcceptableOrUnknown(data['year_end']!, _yearEndMeta),
      );
    }
    if (data.containsKey('quality')) {
      context.handle(
        _qualityMeta,
        quality.isAcceptableOrUnknown(data['quality']!, _qualityMeta),
      );
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    }
    if (data.containsKey('poster_url')) {
      context.handle(
        _posterUrlMeta,
        posterUrl.isAcceptableOrUnknown(data['poster_url']!, _posterUrlMeta),
      );
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('folder_mtime')) {
      context.handle(
        _folderMtimeMeta,
        folderMtime.isAcceptableOrUnknown(
          data['folder_mtime']!,
          _folderMtimeMeta,
        ),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('season_count')) {
      context.handle(
        _seasonCountMeta,
        seasonCount.isAcceptableOrUnknown(
          data['season_count']!,
          _seasonCountMeta,
        ),
      );
    }
    if (data.containsKey('file_count')) {
      context.handle(
        _fileCountMeta,
        fileCount.isAcceptableOrUnknown(data['file_count']!, _fileCountMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TitleRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TitleRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}category_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sort_key'],
      )!,
      kind: $TitlesTable.$converterkind.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}kind'],
        )!,
      ),
      folderUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_url'],
      )!,
      year: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year'],
      ),
      yearEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}year_end'],
      ),
      quality: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}quality'],
      ),
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      )!,
      posterUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poster_url'],
      ),
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      ),
      folderMtime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}folder_mtime'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
      seasonCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season_count'],
      )!,
      fileCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_count'],
      )!,
    );
  }

  @override
  $TitlesTable createAlias(String alias) {
    return $TitlesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<TitleKind, int, int> $converterkind =
      const EnumIndexConverter<TitleKind>(TitleKind.values);
}

class TitleRow extends DataClass implements Insertable<TitleRow> {
  final int id;
  final int categoryId;
  final String name;

  /// Lower-cased name, indexed for ordering.
  final String sortKey;
  final TitleKind kind;
  final String folderUrl;
  final int? year;
  final int? yearEnd;
  final int? quality;

  /// JSON array of strings.
  final String tags;
  final String? posterUrl;

  /// Denormalised from the category.
  final String? language;
  final DateTime? folderMtime;
  final DateTime addedAt;
  final int seasonCount;
  final int fileCount;
  const TitleRow({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.sortKey,
    required this.kind,
    required this.folderUrl,
    this.year,
    this.yearEnd,
    this.quality,
    required this.tags,
    this.posterUrl,
    this.language,
    this.folderMtime,
    required this.addedAt,
    required this.seasonCount,
    required this.fileCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['category_id'] = Variable<int>(categoryId);
    map['name'] = Variable<String>(name);
    map['sort_key'] = Variable<String>(sortKey);
    {
      map['kind'] = Variable<int>($TitlesTable.$converterkind.toSql(kind));
    }
    map['folder_url'] = Variable<String>(folderUrl);
    if (!nullToAbsent || year != null) {
      map['year'] = Variable<int>(year);
    }
    if (!nullToAbsent || yearEnd != null) {
      map['year_end'] = Variable<int>(yearEnd);
    }
    if (!nullToAbsent || quality != null) {
      map['quality'] = Variable<int>(quality);
    }
    map['tags'] = Variable<String>(tags);
    if (!nullToAbsent || posterUrl != null) {
      map['poster_url'] = Variable<String>(posterUrl);
    }
    if (!nullToAbsent || language != null) {
      map['language'] = Variable<String>(language);
    }
    if (!nullToAbsent || folderMtime != null) {
      map['folder_mtime'] = Variable<DateTime>(folderMtime);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    map['season_count'] = Variable<int>(seasonCount);
    map['file_count'] = Variable<int>(fileCount);
    return map;
  }

  TitlesCompanion toCompanion(bool nullToAbsent) {
    return TitlesCompanion(
      id: Value(id),
      categoryId: Value(categoryId),
      name: Value(name),
      sortKey: Value(sortKey),
      kind: Value(kind),
      folderUrl: Value(folderUrl),
      year: year == null && nullToAbsent ? const Value.absent() : Value(year),
      yearEnd: yearEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(yearEnd),
      quality: quality == null && nullToAbsent
          ? const Value.absent()
          : Value(quality),
      tags: Value(tags),
      posterUrl: posterUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(posterUrl),
      language: language == null && nullToAbsent
          ? const Value.absent()
          : Value(language),
      folderMtime: folderMtime == null && nullToAbsent
          ? const Value.absent()
          : Value(folderMtime),
      addedAt: Value(addedAt),
      seasonCount: Value(seasonCount),
      fileCount: Value(fileCount),
    );
  }

  factory TitleRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TitleRow(
      id: serializer.fromJson<int>(json['id']),
      categoryId: serializer.fromJson<int>(json['categoryId']),
      name: serializer.fromJson<String>(json['name']),
      sortKey: serializer.fromJson<String>(json['sortKey']),
      kind: $TitlesTable.$converterkind.fromJson(
        serializer.fromJson<int>(json['kind']),
      ),
      folderUrl: serializer.fromJson<String>(json['folderUrl']),
      year: serializer.fromJson<int?>(json['year']),
      yearEnd: serializer.fromJson<int?>(json['yearEnd']),
      quality: serializer.fromJson<int?>(json['quality']),
      tags: serializer.fromJson<String>(json['tags']),
      posterUrl: serializer.fromJson<String?>(json['posterUrl']),
      language: serializer.fromJson<String?>(json['language']),
      folderMtime: serializer.fromJson<DateTime?>(json['folderMtime']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      seasonCount: serializer.fromJson<int>(json['seasonCount']),
      fileCount: serializer.fromJson<int>(json['fileCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'categoryId': serializer.toJson<int>(categoryId),
      'name': serializer.toJson<String>(name),
      'sortKey': serializer.toJson<String>(sortKey),
      'kind': serializer.toJson<int>($TitlesTable.$converterkind.toJson(kind)),
      'folderUrl': serializer.toJson<String>(folderUrl),
      'year': serializer.toJson<int?>(year),
      'yearEnd': serializer.toJson<int?>(yearEnd),
      'quality': serializer.toJson<int?>(quality),
      'tags': serializer.toJson<String>(tags),
      'posterUrl': serializer.toJson<String?>(posterUrl),
      'language': serializer.toJson<String?>(language),
      'folderMtime': serializer.toJson<DateTime?>(folderMtime),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'seasonCount': serializer.toJson<int>(seasonCount),
      'fileCount': serializer.toJson<int>(fileCount),
    };
  }

  TitleRow copyWith({
    int? id,
    int? categoryId,
    String? name,
    String? sortKey,
    TitleKind? kind,
    String? folderUrl,
    Value<int?> year = const Value.absent(),
    Value<int?> yearEnd = const Value.absent(),
    Value<int?> quality = const Value.absent(),
    String? tags,
    Value<String?> posterUrl = const Value.absent(),
    Value<String?> language = const Value.absent(),
    Value<DateTime?> folderMtime = const Value.absent(),
    DateTime? addedAt,
    int? seasonCount,
    int? fileCount,
  }) => TitleRow(
    id: id ?? this.id,
    categoryId: categoryId ?? this.categoryId,
    name: name ?? this.name,
    sortKey: sortKey ?? this.sortKey,
    kind: kind ?? this.kind,
    folderUrl: folderUrl ?? this.folderUrl,
    year: year.present ? year.value : this.year,
    yearEnd: yearEnd.present ? yearEnd.value : this.yearEnd,
    quality: quality.present ? quality.value : this.quality,
    tags: tags ?? this.tags,
    posterUrl: posterUrl.present ? posterUrl.value : this.posterUrl,
    language: language.present ? language.value : this.language,
    folderMtime: folderMtime.present ? folderMtime.value : this.folderMtime,
    addedAt: addedAt ?? this.addedAt,
    seasonCount: seasonCount ?? this.seasonCount,
    fileCount: fileCount ?? this.fileCount,
  );
  TitleRow copyWithCompanion(TitlesCompanion data) {
    return TitleRow(
      id: data.id.present ? data.id.value : this.id,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      name: data.name.present ? data.name.value : this.name,
      sortKey: data.sortKey.present ? data.sortKey.value : this.sortKey,
      kind: data.kind.present ? data.kind.value : this.kind,
      folderUrl: data.folderUrl.present ? data.folderUrl.value : this.folderUrl,
      year: data.year.present ? data.year.value : this.year,
      yearEnd: data.yearEnd.present ? data.yearEnd.value : this.yearEnd,
      quality: data.quality.present ? data.quality.value : this.quality,
      tags: data.tags.present ? data.tags.value : this.tags,
      posterUrl: data.posterUrl.present ? data.posterUrl.value : this.posterUrl,
      language: data.language.present ? data.language.value : this.language,
      folderMtime: data.folderMtime.present
          ? data.folderMtime.value
          : this.folderMtime,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      seasonCount: data.seasonCount.present
          ? data.seasonCount.value
          : this.seasonCount,
      fileCount: data.fileCount.present ? data.fileCount.value : this.fileCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TitleRow(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('name: $name, ')
          ..write('sortKey: $sortKey, ')
          ..write('kind: $kind, ')
          ..write('folderUrl: $folderUrl, ')
          ..write('year: $year, ')
          ..write('yearEnd: $yearEnd, ')
          ..write('quality: $quality, ')
          ..write('tags: $tags, ')
          ..write('posterUrl: $posterUrl, ')
          ..write('language: $language, ')
          ..write('folderMtime: $folderMtime, ')
          ..write('addedAt: $addedAt, ')
          ..write('seasonCount: $seasonCount, ')
          ..write('fileCount: $fileCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    categoryId,
    name,
    sortKey,
    kind,
    folderUrl,
    year,
    yearEnd,
    quality,
    tags,
    posterUrl,
    language,
    folderMtime,
    addedAt,
    seasonCount,
    fileCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TitleRow &&
          other.id == this.id &&
          other.categoryId == this.categoryId &&
          other.name == this.name &&
          other.sortKey == this.sortKey &&
          other.kind == this.kind &&
          other.folderUrl == this.folderUrl &&
          other.year == this.year &&
          other.yearEnd == this.yearEnd &&
          other.quality == this.quality &&
          other.tags == this.tags &&
          other.posterUrl == this.posterUrl &&
          other.language == this.language &&
          other.folderMtime == this.folderMtime &&
          other.addedAt == this.addedAt &&
          other.seasonCount == this.seasonCount &&
          other.fileCount == this.fileCount);
}

class TitlesCompanion extends UpdateCompanion<TitleRow> {
  final Value<int> id;
  final Value<int> categoryId;
  final Value<String> name;
  final Value<String> sortKey;
  final Value<TitleKind> kind;
  final Value<String> folderUrl;
  final Value<int?> year;
  final Value<int?> yearEnd;
  final Value<int?> quality;
  final Value<String> tags;
  final Value<String?> posterUrl;
  final Value<String?> language;
  final Value<DateTime?> folderMtime;
  final Value<DateTime> addedAt;
  final Value<int> seasonCount;
  final Value<int> fileCount;
  const TitlesCompanion({
    this.id = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.name = const Value.absent(),
    this.sortKey = const Value.absent(),
    this.kind = const Value.absent(),
    this.folderUrl = const Value.absent(),
    this.year = const Value.absent(),
    this.yearEnd = const Value.absent(),
    this.quality = const Value.absent(),
    this.tags = const Value.absent(),
    this.posterUrl = const Value.absent(),
    this.language = const Value.absent(),
    this.folderMtime = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.seasonCount = const Value.absent(),
    this.fileCount = const Value.absent(),
  });
  TitlesCompanion.insert({
    this.id = const Value.absent(),
    required int categoryId,
    required String name,
    required String sortKey,
    required TitleKind kind,
    required String folderUrl,
    this.year = const Value.absent(),
    this.yearEnd = const Value.absent(),
    this.quality = const Value.absent(),
    this.tags = const Value.absent(),
    this.posterUrl = const Value.absent(),
    this.language = const Value.absent(),
    this.folderMtime = const Value.absent(),
    required DateTime addedAt,
    this.seasonCount = const Value.absent(),
    this.fileCount = const Value.absent(),
  }) : categoryId = Value(categoryId),
       name = Value(name),
       sortKey = Value(sortKey),
       kind = Value(kind),
       folderUrl = Value(folderUrl),
       addedAt = Value(addedAt);
  static Insertable<TitleRow> custom({
    Expression<int>? id,
    Expression<int>? categoryId,
    Expression<String>? name,
    Expression<String>? sortKey,
    Expression<int>? kind,
    Expression<String>? folderUrl,
    Expression<int>? year,
    Expression<int>? yearEnd,
    Expression<int>? quality,
    Expression<String>? tags,
    Expression<String>? posterUrl,
    Expression<String>? language,
    Expression<DateTime>? folderMtime,
    Expression<DateTime>? addedAt,
    Expression<int>? seasonCount,
    Expression<int>? fileCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (categoryId != null) 'category_id': categoryId,
      if (name != null) 'name': name,
      if (sortKey != null) 'sort_key': sortKey,
      if (kind != null) 'kind': kind,
      if (folderUrl != null) 'folder_url': folderUrl,
      if (year != null) 'year': year,
      if (yearEnd != null) 'year_end': yearEnd,
      if (quality != null) 'quality': quality,
      if (tags != null) 'tags': tags,
      if (posterUrl != null) 'poster_url': posterUrl,
      if (language != null) 'language': language,
      if (folderMtime != null) 'folder_mtime': folderMtime,
      if (addedAt != null) 'added_at': addedAt,
      if (seasonCount != null) 'season_count': seasonCount,
      if (fileCount != null) 'file_count': fileCount,
    });
  }

  TitlesCompanion copyWith({
    Value<int>? id,
    Value<int>? categoryId,
    Value<String>? name,
    Value<String>? sortKey,
    Value<TitleKind>? kind,
    Value<String>? folderUrl,
    Value<int?>? year,
    Value<int?>? yearEnd,
    Value<int?>? quality,
    Value<String>? tags,
    Value<String?>? posterUrl,
    Value<String?>? language,
    Value<DateTime?>? folderMtime,
    Value<DateTime>? addedAt,
    Value<int>? seasonCount,
    Value<int>? fileCount,
  }) {
    return TitlesCompanion(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      sortKey: sortKey ?? this.sortKey,
      kind: kind ?? this.kind,
      folderUrl: folderUrl ?? this.folderUrl,
      year: year ?? this.year,
      yearEnd: yearEnd ?? this.yearEnd,
      quality: quality ?? this.quality,
      tags: tags ?? this.tags,
      posterUrl: posterUrl ?? this.posterUrl,
      language: language ?? this.language,
      folderMtime: folderMtime ?? this.folderMtime,
      addedAt: addedAt ?? this.addedAt,
      seasonCount: seasonCount ?? this.seasonCount,
      fileCount: fileCount ?? this.fileCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<int>(categoryId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortKey.present) {
      map['sort_key'] = Variable<String>(sortKey.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(
        $TitlesTable.$converterkind.toSql(kind.value),
      );
    }
    if (folderUrl.present) {
      map['folder_url'] = Variable<String>(folderUrl.value);
    }
    if (year.present) {
      map['year'] = Variable<int>(year.value);
    }
    if (yearEnd.present) {
      map['year_end'] = Variable<int>(yearEnd.value);
    }
    if (quality.present) {
      map['quality'] = Variable<int>(quality.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (posterUrl.present) {
      map['poster_url'] = Variable<String>(posterUrl.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (folderMtime.present) {
      map['folder_mtime'] = Variable<DateTime>(folderMtime.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (seasonCount.present) {
      map['season_count'] = Variable<int>(seasonCount.value);
    }
    if (fileCount.present) {
      map['file_count'] = Variable<int>(fileCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TitlesCompanion(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('name: $name, ')
          ..write('sortKey: $sortKey, ')
          ..write('kind: $kind, ')
          ..write('folderUrl: $folderUrl, ')
          ..write('year: $year, ')
          ..write('yearEnd: $yearEnd, ')
          ..write('quality: $quality, ')
          ..write('tags: $tags, ')
          ..write('posterUrl: $posterUrl, ')
          ..write('language: $language, ')
          ..write('folderMtime: $folderMtime, ')
          ..write('addedAt: $addedAt, ')
          ..write('seasonCount: $seasonCount, ')
          ..write('fileCount: $fileCount')
          ..write(')'))
        .toString();
  }
}

class $SeasonsTable extends Seasons with TableInfo<$SeasonsTable, SeasonRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeasonsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleIdMeta = const VerificationMeta(
    'titleId',
  );
  @override
  late final GeneratedColumn<int> titleId = GeneratedColumn<int>(
    'title_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES titles (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _languageMeta = const VerificationMeta(
    'language',
  );
  @override
  late final GeneratedColumn<String> language = GeneratedColumn<String>(
    'language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _folderUrlMeta = const VerificationMeta(
    'folderUrl',
  );
  @override
  late final GeneratedColumn<String> folderUrl = GeneratedColumn<String>(
    'folder_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ordMeta = const VerificationMeta('ord');
  @override
  late final GeneratedColumn<int> ord = GeneratedColumn<int>(
    'ord',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    titleId,
    number,
    label,
    language,
    folderUrl,
    ord,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'seasons';
  @override
  VerificationContext validateIntegrity(
    Insertable<SeasonRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title_id')) {
      context.handle(
        _titleIdMeta,
        titleId.isAcceptableOrUnknown(data['title_id']!, _titleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_titleIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('language')) {
      context.handle(
        _languageMeta,
        language.isAcceptableOrUnknown(data['language']!, _languageMeta),
      );
    }
    if (data.containsKey('folder_url')) {
      context.handle(
        _folderUrlMeta,
        folderUrl.isAcceptableOrUnknown(data['folder_url']!, _folderUrlMeta),
      );
    }
    if (data.containsKey('ord')) {
      context.handle(
        _ordMeta,
        ord.isAcceptableOrUnknown(data['ord']!, _ordMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SeasonRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SeasonRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      titleId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}title_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      language: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}language'],
      ),
      folderUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}folder_url'],
      ),
      ord: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ord'],
      )!,
    );
  }

  @override
  $SeasonsTable createAlias(String alias) {
    return $SeasonsTable(attachedDatabase, alias);
  }
}

class SeasonRow extends DataClass implements Insertable<SeasonRow> {
  final int id;
  final int titleId;
  final int number;
  final String label;
  final String? language;
  final String? folderUrl;

  /// Position in the crawl listing (draft order).
  final int ord;
  const SeasonRow({
    required this.id,
    required this.titleId,
    required this.number,
    required this.label,
    this.language,
    this.folderUrl,
    required this.ord,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title_id'] = Variable<int>(titleId);
    map['number'] = Variable<int>(number);
    map['label'] = Variable<String>(label);
    if (!nullToAbsent || language != null) {
      map['language'] = Variable<String>(language);
    }
    if (!nullToAbsent || folderUrl != null) {
      map['folder_url'] = Variable<String>(folderUrl);
    }
    map['ord'] = Variable<int>(ord);
    return map;
  }

  SeasonsCompanion toCompanion(bool nullToAbsent) {
    return SeasonsCompanion(
      id: Value(id),
      titleId: Value(titleId),
      number: Value(number),
      label: Value(label),
      language: language == null && nullToAbsent
          ? const Value.absent()
          : Value(language),
      folderUrl: folderUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(folderUrl),
      ord: Value(ord),
    );
  }

  factory SeasonRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SeasonRow(
      id: serializer.fromJson<int>(json['id']),
      titleId: serializer.fromJson<int>(json['titleId']),
      number: serializer.fromJson<int>(json['number']),
      label: serializer.fromJson<String>(json['label']),
      language: serializer.fromJson<String?>(json['language']),
      folderUrl: serializer.fromJson<String?>(json['folderUrl']),
      ord: serializer.fromJson<int>(json['ord']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'titleId': serializer.toJson<int>(titleId),
      'number': serializer.toJson<int>(number),
      'label': serializer.toJson<String>(label),
      'language': serializer.toJson<String?>(language),
      'folderUrl': serializer.toJson<String?>(folderUrl),
      'ord': serializer.toJson<int>(ord),
    };
  }

  SeasonRow copyWith({
    int? id,
    int? titleId,
    int? number,
    String? label,
    Value<String?> language = const Value.absent(),
    Value<String?> folderUrl = const Value.absent(),
    int? ord,
  }) => SeasonRow(
    id: id ?? this.id,
    titleId: titleId ?? this.titleId,
    number: number ?? this.number,
    label: label ?? this.label,
    language: language.present ? language.value : this.language,
    folderUrl: folderUrl.present ? folderUrl.value : this.folderUrl,
    ord: ord ?? this.ord,
  );
  SeasonRow copyWithCompanion(SeasonsCompanion data) {
    return SeasonRow(
      id: data.id.present ? data.id.value : this.id,
      titleId: data.titleId.present ? data.titleId.value : this.titleId,
      number: data.number.present ? data.number.value : this.number,
      label: data.label.present ? data.label.value : this.label,
      language: data.language.present ? data.language.value : this.language,
      folderUrl: data.folderUrl.present ? data.folderUrl.value : this.folderUrl,
      ord: data.ord.present ? data.ord.value : this.ord,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SeasonRow(')
          ..write('id: $id, ')
          ..write('titleId: $titleId, ')
          ..write('number: $number, ')
          ..write('label: $label, ')
          ..write('language: $language, ')
          ..write('folderUrl: $folderUrl, ')
          ..write('ord: $ord')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, titleId, number, label, language, folderUrl, ord);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SeasonRow &&
          other.id == this.id &&
          other.titleId == this.titleId &&
          other.number == this.number &&
          other.label == this.label &&
          other.language == this.language &&
          other.folderUrl == this.folderUrl &&
          other.ord == this.ord);
}

class SeasonsCompanion extends UpdateCompanion<SeasonRow> {
  final Value<int> id;
  final Value<int> titleId;
  final Value<int> number;
  final Value<String> label;
  final Value<String?> language;
  final Value<String?> folderUrl;
  final Value<int> ord;
  const SeasonsCompanion({
    this.id = const Value.absent(),
    this.titleId = const Value.absent(),
    this.number = const Value.absent(),
    this.label = const Value.absent(),
    this.language = const Value.absent(),
    this.folderUrl = const Value.absent(),
    this.ord = const Value.absent(),
  });
  SeasonsCompanion.insert({
    this.id = const Value.absent(),
    required int titleId,
    required int number,
    required String label,
    this.language = const Value.absent(),
    this.folderUrl = const Value.absent(),
    this.ord = const Value.absent(),
  }) : titleId = Value(titleId),
       number = Value(number),
       label = Value(label);
  static Insertable<SeasonRow> custom({
    Expression<int>? id,
    Expression<int>? titleId,
    Expression<int>? number,
    Expression<String>? label,
    Expression<String>? language,
    Expression<String>? folderUrl,
    Expression<int>? ord,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (titleId != null) 'title_id': titleId,
      if (number != null) 'number': number,
      if (label != null) 'label': label,
      if (language != null) 'language': language,
      if (folderUrl != null) 'folder_url': folderUrl,
      if (ord != null) 'ord': ord,
    });
  }

  SeasonsCompanion copyWith({
    Value<int>? id,
    Value<int>? titleId,
    Value<int>? number,
    Value<String>? label,
    Value<String?>? language,
    Value<String?>? folderUrl,
    Value<int>? ord,
  }) {
    return SeasonsCompanion(
      id: id ?? this.id,
      titleId: titleId ?? this.titleId,
      number: number ?? this.number,
      label: label ?? this.label,
      language: language ?? this.language,
      folderUrl: folderUrl ?? this.folderUrl,
      ord: ord ?? this.ord,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (titleId.present) {
      map['title_id'] = Variable<int>(titleId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (language.present) {
      map['language'] = Variable<String>(language.value);
    }
    if (folderUrl.present) {
      map['folder_url'] = Variable<String>(folderUrl.value);
    }
    if (ord.present) {
      map['ord'] = Variable<int>(ord.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeasonsCompanion(')
          ..write('id: $id, ')
          ..write('titleId: $titleId, ')
          ..write('number: $number, ')
          ..write('label: $label, ')
          ..write('language: $language, ')
          ..write('folderUrl: $folderUrl, ')
          ..write('ord: $ord')
          ..write(')'))
        .toString();
  }
}

class $FilesTable extends Files with TableInfo<$FilesTable, FileRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleIdMeta = const VerificationMeta(
    'titleId',
  );
  @override
  late final GeneratedColumn<int> titleId = GeneratedColumn<int>(
    'title_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES titles (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _seasonIdMeta = const VerificationMeta(
    'seasonId',
  );
  @override
  late final GeneratedColumn<int> seasonId = GeneratedColumn<int>(
    'season_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES seasons (id)',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _extMeta = const VerificationMeta('ext');
  @override
  late final GeneratedColumn<String> ext = GeneratedColumn<String>(
    'ext',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _playableMeta = const VerificationMeta(
    'playable',
  );
  @override
  late final GeneratedColumn<bool> playable = GeneratedColumn<bool>(
    'playable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("playable" IN (0, 1))',
    ),
  );
  static const VerificationMeta _episodeMeta = const VerificationMeta(
    'episode',
  );
  @override
  late final GeneratedColumn<int> episode = GeneratedColumn<int>(
    'episode',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _episodeEndMeta = const VerificationMeta(
    'episodeEnd',
  );
  @override
  late final GeneratedColumn<int> episodeEnd = GeneratedColumn<int>(
    'episode_end',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sizeKbMeta = const VerificationMeta('sizeKb');
  @override
  late final GeneratedColumn<int> sizeKb = GeneratedColumn<int>(
    'size_kb',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mtimeMeta = const VerificationMeta('mtime');
  @override
  late final GeneratedColumn<DateTime> mtime = GeneratedColumn<DateTime>(
    'mtime',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    titleId,
    seasonId,
    name,
    url,
    ext,
    playable,
    episode,
    episodeEnd,
    sizeKb,
    mtime,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'files';
  @override
  VerificationContext validateIntegrity(
    Insertable<FileRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title_id')) {
      context.handle(
        _titleIdMeta,
        titleId.isAcceptableOrUnknown(data['title_id']!, _titleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_titleIdMeta);
    }
    if (data.containsKey('season_id')) {
      context.handle(
        _seasonIdMeta,
        seasonId.isAcceptableOrUnknown(data['season_id']!, _seasonIdMeta),
      );
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('ext')) {
      context.handle(
        _extMeta,
        ext.isAcceptableOrUnknown(data['ext']!, _extMeta),
      );
    } else if (isInserting) {
      context.missing(_extMeta);
    }
    if (data.containsKey('playable')) {
      context.handle(
        _playableMeta,
        playable.isAcceptableOrUnknown(data['playable']!, _playableMeta),
      );
    } else if (isInserting) {
      context.missing(_playableMeta);
    }
    if (data.containsKey('episode')) {
      context.handle(
        _episodeMeta,
        episode.isAcceptableOrUnknown(data['episode']!, _episodeMeta),
      );
    }
    if (data.containsKey('episode_end')) {
      context.handle(
        _episodeEndMeta,
        episodeEnd.isAcceptableOrUnknown(data['episode_end']!, _episodeEndMeta),
      );
    }
    if (data.containsKey('size_kb')) {
      context.handle(
        _sizeKbMeta,
        sizeKb.isAcceptableOrUnknown(data['size_kb']!, _sizeKbMeta),
      );
    }
    if (data.containsKey('mtime')) {
      context.handle(
        _mtimeMeta,
        mtime.isAcceptableOrUnknown(data['mtime']!, _mtimeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FileRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FileRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      titleId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}title_id'],
      )!,
      seasonId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}season_id'],
      ),
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      ext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ext'],
      )!,
      playable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}playable'],
      )!,
      episode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode'],
      ),
      episodeEnd: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}episode_end'],
      ),
      sizeKb: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_kb'],
      ),
      mtime: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}mtime'],
      ),
    );
  }

  @override
  $FilesTable createAlias(String alias) {
    return $FilesTable(attachedDatabase, alias);
  }
}

class FileRow extends DataClass implements Insertable<FileRow> {
  final int id;
  final int titleId;
  final int? seasonId;
  final String name;
  final String url;
  final String ext;
  final bool playable;
  final int? episode;
  final int? episodeEnd;
  final int? sizeKb;
  final DateTime? mtime;
  const FileRow({
    required this.id,
    required this.titleId,
    this.seasonId,
    required this.name,
    required this.url,
    required this.ext,
    required this.playable,
    this.episode,
    this.episodeEnd,
    this.sizeKb,
    this.mtime,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title_id'] = Variable<int>(titleId);
    if (!nullToAbsent || seasonId != null) {
      map['season_id'] = Variable<int>(seasonId);
    }
    map['name'] = Variable<String>(name);
    map['url'] = Variable<String>(url);
    map['ext'] = Variable<String>(ext);
    map['playable'] = Variable<bool>(playable);
    if (!nullToAbsent || episode != null) {
      map['episode'] = Variable<int>(episode);
    }
    if (!nullToAbsent || episodeEnd != null) {
      map['episode_end'] = Variable<int>(episodeEnd);
    }
    if (!nullToAbsent || sizeKb != null) {
      map['size_kb'] = Variable<int>(sizeKb);
    }
    if (!nullToAbsent || mtime != null) {
      map['mtime'] = Variable<DateTime>(mtime);
    }
    return map;
  }

  FilesCompanion toCompanion(bool nullToAbsent) {
    return FilesCompanion(
      id: Value(id),
      titleId: Value(titleId),
      seasonId: seasonId == null && nullToAbsent
          ? const Value.absent()
          : Value(seasonId),
      name: Value(name),
      url: Value(url),
      ext: Value(ext),
      playable: Value(playable),
      episode: episode == null && nullToAbsent
          ? const Value.absent()
          : Value(episode),
      episodeEnd: episodeEnd == null && nullToAbsent
          ? const Value.absent()
          : Value(episodeEnd),
      sizeKb: sizeKb == null && nullToAbsent
          ? const Value.absent()
          : Value(sizeKb),
      mtime: mtime == null && nullToAbsent
          ? const Value.absent()
          : Value(mtime),
    );
  }

  factory FileRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FileRow(
      id: serializer.fromJson<int>(json['id']),
      titleId: serializer.fromJson<int>(json['titleId']),
      seasonId: serializer.fromJson<int?>(json['seasonId']),
      name: serializer.fromJson<String>(json['name']),
      url: serializer.fromJson<String>(json['url']),
      ext: serializer.fromJson<String>(json['ext']),
      playable: serializer.fromJson<bool>(json['playable']),
      episode: serializer.fromJson<int?>(json['episode']),
      episodeEnd: serializer.fromJson<int?>(json['episodeEnd']),
      sizeKb: serializer.fromJson<int?>(json['sizeKb']),
      mtime: serializer.fromJson<DateTime?>(json['mtime']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'titleId': serializer.toJson<int>(titleId),
      'seasonId': serializer.toJson<int?>(seasonId),
      'name': serializer.toJson<String>(name),
      'url': serializer.toJson<String>(url),
      'ext': serializer.toJson<String>(ext),
      'playable': serializer.toJson<bool>(playable),
      'episode': serializer.toJson<int?>(episode),
      'episodeEnd': serializer.toJson<int?>(episodeEnd),
      'sizeKb': serializer.toJson<int?>(sizeKb),
      'mtime': serializer.toJson<DateTime?>(mtime),
    };
  }

  FileRow copyWith({
    int? id,
    int? titleId,
    Value<int?> seasonId = const Value.absent(),
    String? name,
    String? url,
    String? ext,
    bool? playable,
    Value<int?> episode = const Value.absent(),
    Value<int?> episodeEnd = const Value.absent(),
    Value<int?> sizeKb = const Value.absent(),
    Value<DateTime?> mtime = const Value.absent(),
  }) => FileRow(
    id: id ?? this.id,
    titleId: titleId ?? this.titleId,
    seasonId: seasonId.present ? seasonId.value : this.seasonId,
    name: name ?? this.name,
    url: url ?? this.url,
    ext: ext ?? this.ext,
    playable: playable ?? this.playable,
    episode: episode.present ? episode.value : this.episode,
    episodeEnd: episodeEnd.present ? episodeEnd.value : this.episodeEnd,
    sizeKb: sizeKb.present ? sizeKb.value : this.sizeKb,
    mtime: mtime.present ? mtime.value : this.mtime,
  );
  FileRow copyWithCompanion(FilesCompanion data) {
    return FileRow(
      id: data.id.present ? data.id.value : this.id,
      titleId: data.titleId.present ? data.titleId.value : this.titleId,
      seasonId: data.seasonId.present ? data.seasonId.value : this.seasonId,
      name: data.name.present ? data.name.value : this.name,
      url: data.url.present ? data.url.value : this.url,
      ext: data.ext.present ? data.ext.value : this.ext,
      playable: data.playable.present ? data.playable.value : this.playable,
      episode: data.episode.present ? data.episode.value : this.episode,
      episodeEnd: data.episodeEnd.present
          ? data.episodeEnd.value
          : this.episodeEnd,
      sizeKb: data.sizeKb.present ? data.sizeKb.value : this.sizeKb,
      mtime: data.mtime.present ? data.mtime.value : this.mtime,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FileRow(')
          ..write('id: $id, ')
          ..write('titleId: $titleId, ')
          ..write('seasonId: $seasonId, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('ext: $ext, ')
          ..write('playable: $playable, ')
          ..write('episode: $episode, ')
          ..write('episodeEnd: $episodeEnd, ')
          ..write('sizeKb: $sizeKb, ')
          ..write('mtime: $mtime')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    titleId,
    seasonId,
    name,
    url,
    ext,
    playable,
    episode,
    episodeEnd,
    sizeKb,
    mtime,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FileRow &&
          other.id == this.id &&
          other.titleId == this.titleId &&
          other.seasonId == this.seasonId &&
          other.name == this.name &&
          other.url == this.url &&
          other.ext == this.ext &&
          other.playable == this.playable &&
          other.episode == this.episode &&
          other.episodeEnd == this.episodeEnd &&
          other.sizeKb == this.sizeKb &&
          other.mtime == this.mtime);
}

class FilesCompanion extends UpdateCompanion<FileRow> {
  final Value<int> id;
  final Value<int> titleId;
  final Value<int?> seasonId;
  final Value<String> name;
  final Value<String> url;
  final Value<String> ext;
  final Value<bool> playable;
  final Value<int?> episode;
  final Value<int?> episodeEnd;
  final Value<int?> sizeKb;
  final Value<DateTime?> mtime;
  const FilesCompanion({
    this.id = const Value.absent(),
    this.titleId = const Value.absent(),
    this.seasonId = const Value.absent(),
    this.name = const Value.absent(),
    this.url = const Value.absent(),
    this.ext = const Value.absent(),
    this.playable = const Value.absent(),
    this.episode = const Value.absent(),
    this.episodeEnd = const Value.absent(),
    this.sizeKb = const Value.absent(),
    this.mtime = const Value.absent(),
  });
  FilesCompanion.insert({
    this.id = const Value.absent(),
    required int titleId,
    this.seasonId = const Value.absent(),
    required String name,
    required String url,
    required String ext,
    required bool playable,
    this.episode = const Value.absent(),
    this.episodeEnd = const Value.absent(),
    this.sizeKb = const Value.absent(),
    this.mtime = const Value.absent(),
  }) : titleId = Value(titleId),
       name = Value(name),
       url = Value(url),
       ext = Value(ext),
       playable = Value(playable);
  static Insertable<FileRow> custom({
    Expression<int>? id,
    Expression<int>? titleId,
    Expression<int>? seasonId,
    Expression<String>? name,
    Expression<String>? url,
    Expression<String>? ext,
    Expression<bool>? playable,
    Expression<int>? episode,
    Expression<int>? episodeEnd,
    Expression<int>? sizeKb,
    Expression<DateTime>? mtime,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (titleId != null) 'title_id': titleId,
      if (seasonId != null) 'season_id': seasonId,
      if (name != null) 'name': name,
      if (url != null) 'url': url,
      if (ext != null) 'ext': ext,
      if (playable != null) 'playable': playable,
      if (episode != null) 'episode': episode,
      if (episodeEnd != null) 'episode_end': episodeEnd,
      if (sizeKb != null) 'size_kb': sizeKb,
      if (mtime != null) 'mtime': mtime,
    });
  }

  FilesCompanion copyWith({
    Value<int>? id,
    Value<int>? titleId,
    Value<int?>? seasonId,
    Value<String>? name,
    Value<String>? url,
    Value<String>? ext,
    Value<bool>? playable,
    Value<int?>? episode,
    Value<int?>? episodeEnd,
    Value<int?>? sizeKb,
    Value<DateTime?>? mtime,
  }) {
    return FilesCompanion(
      id: id ?? this.id,
      titleId: titleId ?? this.titleId,
      seasonId: seasonId ?? this.seasonId,
      name: name ?? this.name,
      url: url ?? this.url,
      ext: ext ?? this.ext,
      playable: playable ?? this.playable,
      episode: episode ?? this.episode,
      episodeEnd: episodeEnd ?? this.episodeEnd,
      sizeKb: sizeKb ?? this.sizeKb,
      mtime: mtime ?? this.mtime,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (titleId.present) {
      map['title_id'] = Variable<int>(titleId.value);
    }
    if (seasonId.present) {
      map['season_id'] = Variable<int>(seasonId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (ext.present) {
      map['ext'] = Variable<String>(ext.value);
    }
    if (playable.present) {
      map['playable'] = Variable<bool>(playable.value);
    }
    if (episode.present) {
      map['episode'] = Variable<int>(episode.value);
    }
    if (episodeEnd.present) {
      map['episode_end'] = Variable<int>(episodeEnd.value);
    }
    if (sizeKb.present) {
      map['size_kb'] = Variable<int>(sizeKb.value);
    }
    if (mtime.present) {
      map['mtime'] = Variable<DateTime>(mtime.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FilesCompanion(')
          ..write('id: $id, ')
          ..write('titleId: $titleId, ')
          ..write('seasonId: $seasonId, ')
          ..write('name: $name, ')
          ..write('url: $url, ')
          ..write('ext: $ext, ')
          ..write('playable: $playable, ')
          ..write('episode: $episode, ')
          ..write('episodeEnd: $episodeEnd, ')
          ..write('sizeKb: $sizeKb, ')
          ..write('mtime: $mtime')
          ..write(')'))
        .toString();
  }
}

class $WatchTable extends Watch with TableInfo<$WatchTable, WatchRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<int> fileId = GeneratedColumn<int>(
    'file_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES files (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _watchedMeta = const VerificationMeta(
    'watched',
  );
  @override
  late final GeneratedColumn<bool> watched = GeneratedColumn<bool>(
    'watched',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("watched" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    fileId,
    positionMs,
    durationMs,
    watched,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watch';
  @override
  VerificationContext validateIntegrity(
    Insertable<WatchRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('watched')) {
      context.handle(
        _watchedMeta,
        watched.isAcceptableOrUnknown(data['watched']!, _watchedMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fileId};
  @override
  WatchRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchRow(
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_id'],
      )!,
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      watched: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}watched'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WatchTable createAlias(String alias) {
    return $WatchTable(attachedDatabase, alias);
  }
}

class WatchRow extends DataClass implements Insertable<WatchRow> {
  final int fileId;
  final int positionMs;
  final int durationMs;
  final bool watched;
  final DateTime updatedAt;
  const WatchRow({
    required this.fileId,
    required this.positionMs,
    required this.durationMs,
    required this.watched,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['file_id'] = Variable<int>(fileId);
    map['position_ms'] = Variable<int>(positionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['watched'] = Variable<bool>(watched);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  WatchCompanion toCompanion(bool nullToAbsent) {
    return WatchCompanion(
      fileId: Value(fileId),
      positionMs: Value(positionMs),
      durationMs: Value(durationMs),
      watched: Value(watched),
      updatedAt: Value(updatedAt),
    );
  }

  factory WatchRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchRow(
      fileId: serializer.fromJson<int>(json['fileId']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      watched: serializer.fromJson<bool>(json['watched']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fileId': serializer.toJson<int>(fileId),
      'positionMs': serializer.toJson<int>(positionMs),
      'durationMs': serializer.toJson<int>(durationMs),
      'watched': serializer.toJson<bool>(watched),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  WatchRow copyWith({
    int? fileId,
    int? positionMs,
    int? durationMs,
    bool? watched,
    DateTime? updatedAt,
  }) => WatchRow(
    fileId: fileId ?? this.fileId,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    watched: watched ?? this.watched,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WatchRow copyWithCompanion(WatchCompanion data) {
    return WatchRow(
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      watched: data.watched.present ? data.watched.value : this.watched,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchRow(')
          ..write('fileId: $fileId, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('watched: $watched, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(fileId, positionMs, durationMs, watched, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchRow &&
          other.fileId == this.fileId &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.watched == this.watched &&
          other.updatedAt == this.updatedAt);
}

class WatchCompanion extends UpdateCompanion<WatchRow> {
  final Value<int> fileId;
  final Value<int> positionMs;
  final Value<int> durationMs;
  final Value<bool> watched;
  final Value<DateTime> updatedAt;
  const WatchCompanion({
    this.fileId = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.watched = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  WatchCompanion.insert({
    this.fileId = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.watched = const Value.absent(),
    required DateTime updatedAt,
  }) : updatedAt = Value(updatedAt);
  static Insertable<WatchRow> custom({
    Expression<int>? fileId,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<bool>? watched,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (fileId != null) 'file_id': fileId,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (watched != null) 'watched': watched,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  WatchCompanion copyWith({
    Value<int>? fileId,
    Value<int>? positionMs,
    Value<int>? durationMs,
    Value<bool>? watched,
    Value<DateTime>? updatedAt,
  }) {
    return WatchCompanion(
      fileId: fileId ?? this.fileId,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      watched: watched ?? this.watched,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fileId.present) {
      map['file_id'] = Variable<int>(fileId.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (watched.present) {
      map['watched'] = Variable<bool>(watched.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchCompanion(')
          ..write('fileId: $fileId, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('watched: $watched, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $WatchKeepTable extends WatchKeep
    with TableInfo<$WatchKeepTable, WatchKeepRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatchKeepTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMsMeta = const VerificationMeta(
    'positionMs',
  );
  @override
  late final GeneratedColumn<int> positionMs = GeneratedColumn<int>(
    'position_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _watchedMeta = const VerificationMeta(
    'watched',
  );
  @override
  late final GeneratedColumn<bool> watched = GeneratedColumn<bool>(
    'watched',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("watched" IN (0, 1))',
    ),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    url,
    positionMs,
    durationMs,
    watched,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watch_keep';
  @override
  VerificationContext validateIntegrity(
    Insertable<WatchKeepRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('position_ms')) {
      context.handle(
        _positionMsMeta,
        positionMs.isAcceptableOrUnknown(data['position_ms']!, _positionMsMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMsMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('watched')) {
      context.handle(
        _watchedMeta,
        watched.isAcceptableOrUnknown(data['watched']!, _watchedMeta),
      );
    } else if (isInserting) {
      context.missing(_watchedMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {url};
  @override
  WatchKeepRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WatchKeepRow(
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      positionMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position_ms'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      watched: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}watched'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $WatchKeepTable createAlias(String alias) {
    return $WatchKeepTable(attachedDatabase, alias);
  }
}

class WatchKeepRow extends DataClass implements Insertable<WatchKeepRow> {
  final String url;
  final int positionMs;
  final int durationMs;
  final bool watched;
  final DateTime updatedAt;
  const WatchKeepRow({
    required this.url,
    required this.positionMs,
    required this.durationMs,
    required this.watched,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['url'] = Variable<String>(url);
    map['position_ms'] = Variable<int>(positionMs);
    map['duration_ms'] = Variable<int>(durationMs);
    map['watched'] = Variable<bool>(watched);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  WatchKeepCompanion toCompanion(bool nullToAbsent) {
    return WatchKeepCompanion(
      url: Value(url),
      positionMs: Value(positionMs),
      durationMs: Value(durationMs),
      watched: Value(watched),
      updatedAt: Value(updatedAt),
    );
  }

  factory WatchKeepRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WatchKeepRow(
      url: serializer.fromJson<String>(json['url']),
      positionMs: serializer.fromJson<int>(json['positionMs']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      watched: serializer.fromJson<bool>(json['watched']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'url': serializer.toJson<String>(url),
      'positionMs': serializer.toJson<int>(positionMs),
      'durationMs': serializer.toJson<int>(durationMs),
      'watched': serializer.toJson<bool>(watched),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  WatchKeepRow copyWith({
    String? url,
    int? positionMs,
    int? durationMs,
    bool? watched,
    DateTime? updatedAt,
  }) => WatchKeepRow(
    url: url ?? this.url,
    positionMs: positionMs ?? this.positionMs,
    durationMs: durationMs ?? this.durationMs,
    watched: watched ?? this.watched,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  WatchKeepRow copyWithCompanion(WatchKeepCompanion data) {
    return WatchKeepRow(
      url: data.url.present ? data.url.value : this.url,
      positionMs: data.positionMs.present
          ? data.positionMs.value
          : this.positionMs,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      watched: data.watched.present ? data.watched.value : this.watched,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WatchKeepRow(')
          ..write('url: $url, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('watched: $watched, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(url, positionMs, durationMs, watched, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WatchKeepRow &&
          other.url == this.url &&
          other.positionMs == this.positionMs &&
          other.durationMs == this.durationMs &&
          other.watched == this.watched &&
          other.updatedAt == this.updatedAt);
}

class WatchKeepCompanion extends UpdateCompanion<WatchKeepRow> {
  final Value<String> url;
  final Value<int> positionMs;
  final Value<int> durationMs;
  final Value<bool> watched;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const WatchKeepCompanion({
    this.url = const Value.absent(),
    this.positionMs = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.watched = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatchKeepCompanion.insert({
    required String url,
    required int positionMs,
    required int durationMs,
    required bool watched,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : url = Value(url),
       positionMs = Value(positionMs),
       durationMs = Value(durationMs),
       watched = Value(watched),
       updatedAt = Value(updatedAt);
  static Insertable<WatchKeepRow> custom({
    Expression<String>? url,
    Expression<int>? positionMs,
    Expression<int>? durationMs,
    Expression<bool>? watched,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (url != null) 'url': url,
      if (positionMs != null) 'position_ms': positionMs,
      if (durationMs != null) 'duration_ms': durationMs,
      if (watched != null) 'watched': watched,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatchKeepCompanion copyWith({
    Value<String>? url,
    Value<int>? positionMs,
    Value<int>? durationMs,
    Value<bool>? watched,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return WatchKeepCompanion(
      url: url ?? this.url,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      watched: watched ?? this.watched,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (positionMs.present) {
      map['position_ms'] = Variable<int>(positionMs.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (watched.present) {
      map['watched'] = Variable<bool>(watched.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatchKeepCompanion(')
          ..write('url: $url, ')
          ..write('positionMs: $positionMs, ')
          ..write('durationMs: $durationMs, ')
          ..write('watched: $watched, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SourcesTable sources = $SourcesTable(this);
  late final $CategoriesTable categories = $CategoriesTable(this);
  late final $TitlesTable titles = $TitlesTable(this);
  late final $SeasonsTable seasons = $SeasonsTable(this);
  late final $FilesTable files = $FilesTable(this);
  late final $WatchTable watch = $WatchTable(this);
  late final $WatchKeepTable watchKeep = $WatchKeepTable(this);
  late final Index idxTitlesCatSort = Index(
    'idx_titles_cat_sort',
    'CREATE INDEX idx_titles_cat_sort ON titles (category_id, sort_key)',
  );
  late final Index idxTitlesSort = Index(
    'idx_titles_sort',
    'CREATE INDEX idx_titles_sort ON titles (sort_key)',
  );
  late final Index idxTitlesYear = Index(
    'idx_titles_year',
    'CREATE INDEX idx_titles_year ON titles (year)',
  );
  late final Index idxTitlesLanguage = Index(
    'idx_titles_language',
    'CREATE INDEX idx_titles_language ON titles (language)',
  );
  late final Index idxTitlesQuality = Index(
    'idx_titles_quality',
    'CREATE INDEX idx_titles_quality ON titles (quality)',
  );
  late final Index idxTitlesAdded = Index(
    'idx_titles_added',
    'CREATE INDEX idx_titles_added ON titles (added_at)',
  );
  late final Index idxSeasonsTitle = Index(
    'idx_seasons_title',
    'CREATE INDEX idx_seasons_title ON seasons (title_id)',
  );
  late final Index idxFilesTitle = Index(
    'idx_files_title',
    'CREATE INDEX idx_files_title ON files (title_id)',
  );
  late final Index idxFilesSeason = Index(
    'idx_files_season',
    'CREATE INDEX idx_files_season ON files (season_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    sources,
    categories,
    titles,
    seasons,
    files,
    watch,
    watchKeep,
    idxTitlesCatSort,
    idxTitlesSort,
    idxTitlesYear,
    idxTitlesLanguage,
    idxTitlesQuality,
    idxTitlesAdded,
    idxSeasonsTitle,
    idxFilesTitle,
    idxFilesSeason,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'categories',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('titles', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'titles',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('seasons', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'titles',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('files', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'files',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('watch', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$SourcesTableCreateCompanionBuilder = SourcesCompanion Function({
  Value<int> id,
  required String host,
});
typedef $$SourcesTableUpdateCompanionBuilder = SourcesCompanion Function({
  Value<int> id,
  Value<String> host,
});

final class $$SourcesTableReferences
    extends BaseReferences<_$AppDatabase, $SourcesTable, SourceRow> {
  $$SourcesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CategoriesTable, List<CategoryRow>>
  _categoriesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.categories,
    aliasName: 'sources__id__categories__source_id',
  );

  $$CategoriesTableProcessedTableManager get categoriesRefs {
    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.sourceId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_categoriesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SourcesTableFilterComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> categoriesRefs(
    Expression<bool> Function($$CategoriesTableFilterComposer f) f,
  ) {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.sourceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SourcesTableOrderingComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SourcesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SourcesTable> {
  $$SourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  Expression<T> categoriesRefs<T extends Object>(
    Expression<T> Function($$CategoriesTableAnnotationComposer a) f,
  ) {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.sourceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SourcesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SourcesTable,
          SourceRow,
          $$SourcesTableFilterComposer,
          $$SourcesTableOrderingComposer,
          $$SourcesTableAnnotationComposer,
          $$SourcesTableCreateCompanionBuilder,
          $$SourcesTableUpdateCompanionBuilder,
          (SourceRow, $$SourcesTableReferences),
          SourceRow,
          PrefetchHooks Function({bool categoriesRefs})
        > {
  $$SourcesTableTableManager(_$AppDatabase db, $SourcesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> host = const Value.absent(),
          }) => SourcesCompanion(id: id, host: host),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String host,
          }) => SourcesCompanion.insert(id: id, host: host),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SourcesTable, SourceRow>(table),
                  $$SourcesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({categoriesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (categoriesRefs) db.categories],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (categoriesRefs)
                    await $_getPrefetchedDataByColumns<
                      SourceRow,
                      $SourcesTable,
                      CategoryRow,
                      $CategoriesTable
                    >(
                      currentTable: table,
                      referencedTable: $$SourcesTableReferences
                          ._categoriesRefsTable(db),
                      managerFromTypedResult: (p0) => $$SourcesTableReferences(
                        db,
                        table,
                        p0,
                      ).categoriesRefs,
                      currentColumn: 'id',
                      referencedColumn: 'source_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SourcesTable,
      SourceRow,
      $$SourcesTableFilterComposer,
      $$SourcesTableOrderingComposer,
      $$SourcesTableAnnotationComposer,
      $$SourcesTableCreateCompanionBuilder,
      $$SourcesTableUpdateCompanionBuilder,
      (SourceRow, $$SourcesTableReferences),
      SourceRow,
      PrefetchHooks Function({bool categoriesRefs})
    >;
typedef $$CategoriesTableCreateCompanionBuilder = CategoriesCompanion Function({
  Value<int> id,
  required int sourceId,
  required String name,
  required String url,
  Value<String?> language,
});
typedef $$CategoriesTableUpdateCompanionBuilder = CategoriesCompanion Function({
  Value<int> id,
  Value<int> sourceId,
  Value<String> name,
  Value<String> url,
  Value<String?> language,
});

final class $$CategoriesTableReferences
    extends BaseReferences<_$AppDatabase, $CategoriesTable, CategoryRow> {
  $$CategoriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SourcesTable _sourceIdTable(_$AppDatabase db) =>
      db.sources.createAlias('categories__source_id__sources__id');

  $$SourcesTableProcessedTableManager get sourceId {
    final $_column = $_itemColumn<int>('source_id')!;

    final manager = $$SourcesTableTableManager(
      $_db,
      $_db.sources,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sourceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$TitlesTable, List<TitleRow>> _titlesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.titles,
    aliasName: 'categories__id__titles__category_id',
  );

  $$TitlesTableProcessedTableManager get titlesRefs {
    final manager = $$TitlesTableTableManager(
      $_db,
      $_db.titles,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_titlesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CategoriesTableFilterComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  $$SourcesTableFilterComposer get sourceId {
    final $$SourcesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceId,
      referencedTable: $db.sources,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourcesTableFilterComposer(
            $db: $db,
            $table: $db.sources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> titlesRefs(
    Expression<bool> Function($$TitlesTableFilterComposer f) f,
  ) {
    final $$TitlesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.titles,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TitlesTableFilterComposer(
            $db: $db,
            $table: $db.titles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  $$SourcesTableOrderingComposer get sourceId {
    final $$SourcesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceId,
      referencedTable: $db.sources,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourcesTableOrderingComposer(
            $db: $db,
            $table: $db.sources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CategoriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoriesTable> {
  $$CategoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  $$SourcesTableAnnotationComposer get sourceId {
    final $$SourcesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sourceId,
      referencedTable: $db.sources,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SourcesTableAnnotationComposer(
            $db: $db,
            $table: $db.sources,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> titlesRefs<T extends Object>(
    Expression<T> Function($$TitlesTableAnnotationComposer a) f,
  ) {
    final $$TitlesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.titles,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TitlesTableAnnotationComposer(
            $db: $db,
            $table: $db.titles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoriesTable,
          CategoryRow,
          $$CategoriesTableFilterComposer,
          $$CategoriesTableOrderingComposer,
          $$CategoriesTableAnnotationComposer,
          $$CategoriesTableCreateCompanionBuilder,
          $$CategoriesTableUpdateCompanionBuilder,
          (CategoryRow, $$CategoriesTableReferences),
          CategoryRow,
          PrefetchHooks Function({bool sourceId, bool titlesRefs})
        > {
  $$CategoriesTableTableManager(_$AppDatabase db, $CategoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> sourceId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String?> language = const Value.absent(),
              }) => CategoriesCompanion(
                id: id,
                sourceId: sourceId,
                name: name,
                url: url,
                language: language,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int sourceId,
                required String name,
                required String url,
                Value<String?> language = const Value.absent(),
              }) => CategoriesCompanion.insert(
                id: id,
                sourceId: sourceId,
                name: name,
                url: url,
                language: language,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CategoriesTable, CategoryRow>(table),
                  $$CategoriesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sourceId = false, titlesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (titlesRefs) db.titles],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sourceId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.sourceId,
                        referencedTable: $$CategoriesTableReferences
                            ._sourceIdTable(db),
                        referencedColumn: $$CategoriesTableReferences
                            ._sourceIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (titlesRefs)
                    await $_getPrefetchedDataByColumns<
                      CategoryRow,
                      $CategoriesTable,
                      TitleRow,
                      $TitlesTable
                    >(
                      currentTable: table,
                      referencedTable: $$CategoriesTableReferences
                          ._titlesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CategoriesTableReferences(db, table, p0).titlesRefs,
                      currentColumn: 'id',
                      referencedColumn: 'category_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$CategoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoriesTable,
      CategoryRow,
      $$CategoriesTableFilterComposer,
      $$CategoriesTableOrderingComposer,
      $$CategoriesTableAnnotationComposer,
      $$CategoriesTableCreateCompanionBuilder,
      $$CategoriesTableUpdateCompanionBuilder,
      (CategoryRow, $$CategoriesTableReferences),
      CategoryRow,
      PrefetchHooks Function({bool sourceId, bool titlesRefs})
    >;
typedef $$TitlesTableCreateCompanionBuilder = TitlesCompanion Function({
  Value<int> id,
  required int categoryId,
  required String name,
  required String sortKey,
  required TitleKind kind,
  required String folderUrl,
  Value<int?> year,
  Value<int?> yearEnd,
  Value<int?> quality,
  Value<String> tags,
  Value<String?> posterUrl,
  Value<String?> language,
  Value<DateTime?> folderMtime,
  required DateTime addedAt,
  Value<int> seasonCount,
  Value<int> fileCount,
});
typedef $$TitlesTableUpdateCompanionBuilder = TitlesCompanion Function({
  Value<int> id,
  Value<int> categoryId,
  Value<String> name,
  Value<String> sortKey,
  Value<TitleKind> kind,
  Value<String> folderUrl,
  Value<int?> year,
  Value<int?> yearEnd,
  Value<int?> quality,
  Value<String> tags,
  Value<String?> posterUrl,
  Value<String?> language,
  Value<DateTime?> folderMtime,
  Value<DateTime> addedAt,
  Value<int> seasonCount,
  Value<int> fileCount,
});

final class $$TitlesTableReferences
    extends BaseReferences<_$AppDatabase, $TitlesTable, TitleRow> {
  $$TitlesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoriesTable _categoryIdTable(_$AppDatabase db) =>
      db.categories.createAlias('titles__category_id__categories__id');

  $$CategoriesTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<int>('category_id')!;

    final manager = $$CategoriesTableTableManager(
      $_db,
      $_db.categories,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$SeasonsTable, List<SeasonRow>> _seasonsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.seasons,
    aliasName: 'titles__id__seasons__title_id',
  );

  $$SeasonsTableProcessedTableManager get seasonsRefs {
    final manager = $$SeasonsTableTableManager(
      $_db,
      $_db.seasons,
    ).filter((f) => f.titleId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_seasonsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$FilesTable, List<FileRow>> _filesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.files,
    aliasName: 'titles__id__files__title_id',
  );

  $$FilesTableProcessedTableManager get filesRefs {
    final manager = $$FilesTableTableManager(
      $_db,
      $_db.files,
    ).filter((f) => f.titleId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_filesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$TitlesTableFilterComposer
    extends Composer<_$AppDatabase, $TitlesTable> {
  $$TitlesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<TitleKind, TitleKind, int> get kind =>
      $composableBuilder(
        column: $table.kind,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<String> get folderUrl => $composableBuilder(
    column: $table.folderUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get yearEnd => $composableBuilder(
    column: $table.yearEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get posterUrl => $composableBuilder(
    column: $table.posterUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get folderMtime => $composableBuilder(
    column: $table.folderMtime,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seasonCount => $composableBuilder(
    column: $table.seasonCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileCount => $composableBuilder(
    column: $table.fileCount,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoriesTableFilterComposer get categoryId {
    final $$CategoriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableFilterComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> seasonsRefs(
    Expression<bool> Function($$SeasonsTableFilterComposer f) f,
  ) {
    final $$SeasonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.seasons,
      getReferencedColumn: (t) => t.titleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SeasonsTableFilterComposer(
            $db: $db,
            $table: $db.seasons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> filesRefs(
    Expression<bool> Function($$FilesTableFilterComposer f) f,
  ) {
    final $$FilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.files,
      getReferencedColumn: (t) => t.titleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FilesTableFilterComposer(
            $db: $db,
            $table: $db.files,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TitlesTableOrderingComposer
    extends Composer<_$AppDatabase, $TitlesTable> {
  $$TitlesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sortKey => $composableBuilder(
    column: $table.sortKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderUrl => $composableBuilder(
    column: $table.folderUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get year => $composableBuilder(
    column: $table.year,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get yearEnd => $composableBuilder(
    column: $table.yearEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get quality => $composableBuilder(
    column: $table.quality,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get posterUrl => $composableBuilder(
    column: $table.posterUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get folderMtime => $composableBuilder(
    column: $table.folderMtime,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seasonCount => $composableBuilder(
    column: $table.seasonCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileCount => $composableBuilder(
    column: $table.fileCount,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoriesTableOrderingComposer get categoryId {
    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableOrderingComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TitlesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TitlesTable> {
  $$TitlesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get sortKey =>
      $composableBuilder(column: $table.sortKey, builder: (column) => column);

  GeneratedColumnWithTypeConverter<TitleKind, int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get folderUrl =>
      $composableBuilder(column: $table.folderUrl, builder: (column) => column);

  GeneratedColumn<int> get year =>
      $composableBuilder(column: $table.year, builder: (column) => column);

  GeneratedColumn<int> get yearEnd =>
      $composableBuilder(column: $table.yearEnd, builder: (column) => column);

  GeneratedColumn<int> get quality =>
      $composableBuilder(column: $table.quality, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get posterUrl =>
      $composableBuilder(column: $table.posterUrl, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<DateTime> get folderMtime => $composableBuilder(
    column: $table.folderMtime,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<int> get seasonCount => $composableBuilder(
    column: $table.seasonCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fileCount =>
      $composableBuilder(column: $table.fileCount, builder: (column) => column);

  $$CategoriesTableAnnotationComposer get categoryId {
    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categories,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoriesTableAnnotationComposer(
            $db: $db,
            $table: $db.categories,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> seasonsRefs<T extends Object>(
    Expression<T> Function($$SeasonsTableAnnotationComposer a) f,
  ) {
    final $$SeasonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.seasons,
      getReferencedColumn: (t) => t.titleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SeasonsTableAnnotationComposer(
            $db: $db,
            $table: $db.seasons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> filesRefs<T extends Object>(
    Expression<T> Function($$FilesTableAnnotationComposer a) f,
  ) {
    final $$FilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.files,
      getReferencedColumn: (t) => t.titleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FilesTableAnnotationComposer(
            $db: $db,
            $table: $db.files,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$TitlesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TitlesTable,
          TitleRow,
          $$TitlesTableFilterComposer,
          $$TitlesTableOrderingComposer,
          $$TitlesTableAnnotationComposer,
          $$TitlesTableCreateCompanionBuilder,
          $$TitlesTableUpdateCompanionBuilder,
          (TitleRow, $$TitlesTableReferences),
          TitleRow,
          PrefetchHooks Function({
            bool categoryId,
            bool seasonsRefs,
            bool filesRefs,
          })
        > {
  $$TitlesTableTableManager(_$AppDatabase db, $TitlesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TitlesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TitlesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TitlesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> categoryId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> sortKey = const Value.absent(),
                Value<TitleKind> kind = const Value.absent(),
                Value<String> folderUrl = const Value.absent(),
                Value<int?> year = const Value.absent(),
                Value<int?> yearEnd = const Value.absent(),
                Value<int?> quality = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<String?> posterUrl = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<DateTime?> folderMtime = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> seasonCount = const Value.absent(),
                Value<int> fileCount = const Value.absent(),
              }) => TitlesCompanion(
                id: id,
                categoryId: categoryId,
                name: name,
                sortKey: sortKey,
                kind: kind,
                folderUrl: folderUrl,
                year: year,
                yearEnd: yearEnd,
                quality: quality,
                tags: tags,
                posterUrl: posterUrl,
                language: language,
                folderMtime: folderMtime,
                addedAt: addedAt,
                seasonCount: seasonCount,
                fileCount: fileCount,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int categoryId,
                required String name,
                required String sortKey,
                required TitleKind kind,
                required String folderUrl,
                Value<int?> year = const Value.absent(),
                Value<int?> yearEnd = const Value.absent(),
                Value<int?> quality = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<String?> posterUrl = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<DateTime?> folderMtime = const Value.absent(),
                required DateTime addedAt,
                Value<int> seasonCount = const Value.absent(),
                Value<int> fileCount = const Value.absent(),
              }) => TitlesCompanion.insert(
                id: id,
                categoryId: categoryId,
                name: name,
                sortKey: sortKey,
                kind: kind,
                folderUrl: folderUrl,
                year: year,
                yearEnd: yearEnd,
                quality: quality,
                tags: tags,
                posterUrl: posterUrl,
                language: language,
                folderMtime: folderMtime,
                addedAt: addedAt,
                seasonCount: seasonCount,
                fileCount: fileCount,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TitlesTable, TitleRow>(table),
                  $$TitlesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({categoryId = false, seasonsRefs = false, filesRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (seasonsRefs) db.seasons,
                    if (filesRefs) db.files,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (categoryId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.categoryId,
                            referencedTable: $$TitlesTableReferences
                                ._categoryIdTable(db),
                            referencedColumn: $$TitlesTableReferences
                                ._categoryIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (seasonsRefs)
                        await $_getPrefetchedDataByColumns<
                          TitleRow,
                          $TitlesTable,
                          SeasonRow,
                          $SeasonsTable
                        >(
                          currentTable: table,
                          referencedTable: $$TitlesTableReferences
                              ._seasonsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TitlesTableReferences(
                                db,
                                table,
                                p0,
                              ).seasonsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'title_id',
                          typedResults: items,
                        ),
                      if (filesRefs)
                        await $_getPrefetchedDataByColumns<
                          TitleRow,
                          $TitlesTable,
                          FileRow,
                          $FilesTable
                        >(
                          currentTable: table,
                          referencedTable: $$TitlesTableReferences
                              ._filesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$TitlesTableReferences(db, table, p0).filesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'title_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$TitlesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TitlesTable,
      TitleRow,
      $$TitlesTableFilterComposer,
      $$TitlesTableOrderingComposer,
      $$TitlesTableAnnotationComposer,
      $$TitlesTableCreateCompanionBuilder,
      $$TitlesTableUpdateCompanionBuilder,
      (TitleRow, $$TitlesTableReferences),
      TitleRow,
      PrefetchHooks Function({
        bool categoryId,
        bool seasonsRefs,
        bool filesRefs,
      })
    >;
typedef $$SeasonsTableCreateCompanionBuilder = SeasonsCompanion Function({
  Value<int> id,
  required int titleId,
  required int number,
  required String label,
  Value<String?> language,
  Value<String?> folderUrl,
  Value<int> ord,
});
typedef $$SeasonsTableUpdateCompanionBuilder = SeasonsCompanion Function({
  Value<int> id,
  Value<int> titleId,
  Value<int> number,
  Value<String> label,
  Value<String?> language,
  Value<String?> folderUrl,
  Value<int> ord,
});

final class $$SeasonsTableReferences
    extends BaseReferences<_$AppDatabase, $SeasonsTable, SeasonRow> {
  $$SeasonsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TitlesTable _titleIdTable(_$AppDatabase db) =>
      db.titles.createAlias('seasons__title_id__titles__id');

  $$TitlesTableProcessedTableManager get titleId {
    final $_column = $_itemColumn<int>('title_id')!;

    final manager = $$TitlesTableTableManager(
      $_db,
      $_db.titles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_titleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$FilesTable, List<FileRow>> _filesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.files,
    aliasName: 'seasons__id__files__season_id',
  );

  $$FilesTableProcessedTableManager get filesRefs {
    final manager = $$FilesTableTableManager(
      $_db,
      $_db.files,
    ).filter((f) => f.seasonId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_filesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SeasonsTableFilterComposer
    extends Composer<_$AppDatabase, $SeasonsTable> {
  $$SeasonsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get folderUrl => $composableBuilder(
    column: $table.folderUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get ord => $composableBuilder(
    column: $table.ord,
    builder: (column) => ColumnFilters(column),
  );

  $$TitlesTableFilterComposer get titleId {
    final $$TitlesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.titleId,
      referencedTable: $db.titles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TitlesTableFilterComposer(
            $db: $db,
            $table: $db.titles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> filesRefs(
    Expression<bool> Function($$FilesTableFilterComposer f) f,
  ) {
    final $$FilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.files,
      getReferencedColumn: (t) => t.seasonId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FilesTableFilterComposer(
            $db: $db,
            $table: $db.files,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SeasonsTableOrderingComposer
    extends Composer<_$AppDatabase, $SeasonsTable> {
  $$SeasonsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get language => $composableBuilder(
    column: $table.language,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get folderUrl => $composableBuilder(
    column: $table.folderUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get ord => $composableBuilder(
    column: $table.ord,
    builder: (column) => ColumnOrderings(column),
  );

  $$TitlesTableOrderingComposer get titleId {
    final $$TitlesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.titleId,
      referencedTable: $db.titles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TitlesTableOrderingComposer(
            $db: $db,
            $table: $db.titles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SeasonsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SeasonsTable> {
  $$SeasonsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get language =>
      $composableBuilder(column: $table.language, builder: (column) => column);

  GeneratedColumn<String> get folderUrl =>
      $composableBuilder(column: $table.folderUrl, builder: (column) => column);

  GeneratedColumn<int> get ord =>
      $composableBuilder(column: $table.ord, builder: (column) => column);

  $$TitlesTableAnnotationComposer get titleId {
    final $$TitlesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.titleId,
      referencedTable: $db.titles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TitlesTableAnnotationComposer(
            $db: $db,
            $table: $db.titles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> filesRefs<T extends Object>(
    Expression<T> Function($$FilesTableAnnotationComposer a) f,
  ) {
    final $$FilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.files,
      getReferencedColumn: (t) => t.seasonId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FilesTableAnnotationComposer(
            $db: $db,
            $table: $db.files,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SeasonsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SeasonsTable,
          SeasonRow,
          $$SeasonsTableFilterComposer,
          $$SeasonsTableOrderingComposer,
          $$SeasonsTableAnnotationComposer,
          $$SeasonsTableCreateCompanionBuilder,
          $$SeasonsTableUpdateCompanionBuilder,
          (SeasonRow, $$SeasonsTableReferences),
          SeasonRow,
          PrefetchHooks Function({bool titleId, bool filesRefs})
        > {
  $$SeasonsTableTableManager(_$AppDatabase db, $SeasonsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeasonsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeasonsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeasonsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> titleId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String?> language = const Value.absent(),
                Value<String?> folderUrl = const Value.absent(),
                Value<int> ord = const Value.absent(),
              }) => SeasonsCompanion(
                id: id,
                titleId: titleId,
                number: number,
                label: label,
                language: language,
                folderUrl: folderUrl,
                ord: ord,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int titleId,
                required int number,
                required String label,
                Value<String?> language = const Value.absent(),
                Value<String?> folderUrl = const Value.absent(),
                Value<int> ord = const Value.absent(),
              }) => SeasonsCompanion.insert(
                id: id,
                titleId: titleId,
                number: number,
                label: label,
                language: language,
                folderUrl: folderUrl,
                ord: ord,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SeasonsTable, SeasonRow>(table),
                  $$SeasonsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({titleId = false, filesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (filesRefs) db.files],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (titleId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.titleId,
                        referencedTable: $$SeasonsTableReferences._titleIdTable(
                          db,
                        ),
                        referencedColumn: $$SeasonsTableReferences
                            ._titleIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (filesRefs)
                    await $_getPrefetchedDataByColumns<
                      SeasonRow,
                      $SeasonsTable,
                      FileRow,
                      $FilesTable
                    >(
                      currentTable: table,
                      referencedTable: $$SeasonsTableReferences._filesRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$SeasonsTableReferences(db, table, p0).filesRefs,
                      currentColumn: 'id',
                      referencedColumn: 'season_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SeasonsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SeasonsTable,
      SeasonRow,
      $$SeasonsTableFilterComposer,
      $$SeasonsTableOrderingComposer,
      $$SeasonsTableAnnotationComposer,
      $$SeasonsTableCreateCompanionBuilder,
      $$SeasonsTableUpdateCompanionBuilder,
      (SeasonRow, $$SeasonsTableReferences),
      SeasonRow,
      PrefetchHooks Function({bool titleId, bool filesRefs})
    >;
typedef $$FilesTableCreateCompanionBuilder = FilesCompanion Function({
  Value<int> id,
  required int titleId,
  Value<int?> seasonId,
  required String name,
  required String url,
  required String ext,
  required bool playable,
  Value<int?> episode,
  Value<int?> episodeEnd,
  Value<int?> sizeKb,
  Value<DateTime?> mtime,
});
typedef $$FilesTableUpdateCompanionBuilder = FilesCompanion Function({
  Value<int> id,
  Value<int> titleId,
  Value<int?> seasonId,
  Value<String> name,
  Value<String> url,
  Value<String> ext,
  Value<bool> playable,
  Value<int?> episode,
  Value<int?> episodeEnd,
  Value<int?> sizeKb,
  Value<DateTime?> mtime,
});

final class $$FilesTableReferences
    extends BaseReferences<_$AppDatabase, $FilesTable, FileRow> {
  $$FilesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $TitlesTable _titleIdTable(_$AppDatabase db) =>
      db.titles.createAlias('files__title_id__titles__id');

  $$TitlesTableProcessedTableManager get titleId {
    final $_column = $_itemColumn<int>('title_id')!;

    final manager = $$TitlesTableTableManager(
      $_db,
      $_db.titles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_titleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SeasonsTable _seasonIdTable(_$AppDatabase db) =>
      db.seasons.createAlias('files__season_id__seasons__id');

  $$SeasonsTableProcessedTableManager? get seasonId {
    final $_column = $_itemColumn<int>('season_id');
    if ($_column == null) return null;
    final manager = $$SeasonsTableTableManager(
      $_db,
      $_db.seasons,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_seasonIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$WatchTable, List<WatchRow>> _watchRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.watch,
    aliasName: 'files__id__watch__file_id',
  );

  $$WatchTableProcessedTableManager get watchRefs {
    final manager = $$WatchTableTableManager(
      $_db,
      $_db.watch,
    ).filter((f) => f.fileId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_watchRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FilesTableFilterComposer extends Composer<_$AppDatabase, $FilesTable> {
  $$FilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ext => $composableBuilder(
    column: $table.ext,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get playable => $composableBuilder(
    column: $table.playable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get episodeEnd => $composableBuilder(
    column: $table.episodeEnd,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeKb => $composableBuilder(
    column: $table.sizeKb,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get mtime => $composableBuilder(
    column: $table.mtime,
    builder: (column) => ColumnFilters(column),
  );

  $$TitlesTableFilterComposer get titleId {
    final $$TitlesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.titleId,
      referencedTable: $db.titles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TitlesTableFilterComposer(
            $db: $db,
            $table: $db.titles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SeasonsTableFilterComposer get seasonId {
    final $$SeasonsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.seasonId,
      referencedTable: $db.seasons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SeasonsTableFilterComposer(
            $db: $db,
            $table: $db.seasons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> watchRefs(
    Expression<bool> Function($$WatchTableFilterComposer f) f,
  ) {
    final $$WatchTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.watch,
      getReferencedColumn: (t) => t.fileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WatchTableFilterComposer(
            $db: $db,
            $table: $db.watch,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FilesTableOrderingComposer
    extends Composer<_$AppDatabase, $FilesTable> {
  $$FilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ext => $composableBuilder(
    column: $table.ext,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get playable => $composableBuilder(
    column: $table.playable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episode => $composableBuilder(
    column: $table.episode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get episodeEnd => $composableBuilder(
    column: $table.episodeEnd,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeKb => $composableBuilder(
    column: $table.sizeKb,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get mtime => $composableBuilder(
    column: $table.mtime,
    builder: (column) => ColumnOrderings(column),
  );

  $$TitlesTableOrderingComposer get titleId {
    final $$TitlesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.titleId,
      referencedTable: $db.titles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TitlesTableOrderingComposer(
            $db: $db,
            $table: $db.titles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SeasonsTableOrderingComposer get seasonId {
    final $$SeasonsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.seasonId,
      referencedTable: $db.seasons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SeasonsTableOrderingComposer(
            $db: $db,
            $table: $db.seasons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FilesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FilesTable> {
  $$FilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get ext =>
      $composableBuilder(column: $table.ext, builder: (column) => column);

  GeneratedColumn<bool> get playable =>
      $composableBuilder(column: $table.playable, builder: (column) => column);

  GeneratedColumn<int> get episode =>
      $composableBuilder(column: $table.episode, builder: (column) => column);

  GeneratedColumn<int> get episodeEnd => $composableBuilder(
    column: $table.episodeEnd,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sizeKb =>
      $composableBuilder(column: $table.sizeKb, builder: (column) => column);

  GeneratedColumn<DateTime> get mtime =>
      $composableBuilder(column: $table.mtime, builder: (column) => column);

  $$TitlesTableAnnotationComposer get titleId {
    final $$TitlesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.titleId,
      referencedTable: $db.titles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TitlesTableAnnotationComposer(
            $db: $db,
            $table: $db.titles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SeasonsTableAnnotationComposer get seasonId {
    final $$SeasonsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.seasonId,
      referencedTable: $db.seasons,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SeasonsTableAnnotationComposer(
            $db: $db,
            $table: $db.seasons,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> watchRefs<T extends Object>(
    Expression<T> Function($$WatchTableAnnotationComposer a) f,
  ) {
    final $$WatchTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.watch,
      getReferencedColumn: (t) => t.fileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WatchTableAnnotationComposer(
            $db: $db,
            $table: $db.watch,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FilesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FilesTable,
          FileRow,
          $$FilesTableFilterComposer,
          $$FilesTableOrderingComposer,
          $$FilesTableAnnotationComposer,
          $$FilesTableCreateCompanionBuilder,
          $$FilesTableUpdateCompanionBuilder,
          (FileRow, $$FilesTableReferences),
          FileRow,
          PrefetchHooks Function({bool titleId, bool seasonId, bool watchRefs})
        > {
  $$FilesTableTableManager(_$AppDatabase db, $FilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> titleId = const Value.absent(),
                Value<int?> seasonId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> ext = const Value.absent(),
                Value<bool> playable = const Value.absent(),
                Value<int?> episode = const Value.absent(),
                Value<int?> episodeEnd = const Value.absent(),
                Value<int?> sizeKb = const Value.absent(),
                Value<DateTime?> mtime = const Value.absent(),
              }) => FilesCompanion(
                id: id,
                titleId: titleId,
                seasonId: seasonId,
                name: name,
                url: url,
                ext: ext,
                playable: playable,
                episode: episode,
                episodeEnd: episodeEnd,
                sizeKb: sizeKb,
                mtime: mtime,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int titleId,
                Value<int?> seasonId = const Value.absent(),
                required String name,
                required String url,
                required String ext,
                required bool playable,
                Value<int?> episode = const Value.absent(),
                Value<int?> episodeEnd = const Value.absent(),
                Value<int?> sizeKb = const Value.absent(),
                Value<DateTime?> mtime = const Value.absent(),
              }) => FilesCompanion.insert(
                id: id,
                titleId: titleId,
                seasonId: seasonId,
                name: name,
                url: url,
                ext: ext,
                playable: playable,
                episode: episode,
                episodeEnd: episodeEnd,
                sizeKb: sizeKb,
                mtime: mtime,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FilesTable, FileRow>(table),
                  $$FilesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({titleId = false, seasonId = false, watchRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [if (watchRefs) db.watch],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (titleId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.titleId,
                            referencedTable: $$FilesTableReferences
                                ._titleIdTable(db),
                            referencedColumn: $$FilesTableReferences
                                ._titleIdTable(db)
                                .id,
                          ) as T;
                        }
                        if (seasonId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.seasonId,
                            referencedTable: $$FilesTableReferences
                                ._seasonIdTable(db),
                            referencedColumn: $$FilesTableReferences
                                ._seasonIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (watchRefs)
                        await $_getPrefetchedDataByColumns<
                          FileRow,
                          $FilesTable,
                          WatchRow,
                          $WatchTable
                        >(
                          currentTable: table,
                          referencedTable: $$FilesTableReferences
                              ._watchRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$FilesTableReferences(db, table, p0).watchRefs,
                          currentColumn: 'id',
                          referencedColumn: 'file_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$FilesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FilesTable,
      FileRow,
      $$FilesTableFilterComposer,
      $$FilesTableOrderingComposer,
      $$FilesTableAnnotationComposer,
      $$FilesTableCreateCompanionBuilder,
      $$FilesTableUpdateCompanionBuilder,
      (FileRow, $$FilesTableReferences),
      FileRow,
      PrefetchHooks Function({bool titleId, bool seasonId, bool watchRefs})
    >;
typedef $$WatchTableCreateCompanionBuilder = WatchCompanion Function({
  Value<int> fileId,
  Value<int> positionMs,
  Value<int> durationMs,
  Value<bool> watched,
  required DateTime updatedAt,
});
typedef $$WatchTableUpdateCompanionBuilder = WatchCompanion Function({
  Value<int> fileId,
  Value<int> positionMs,
  Value<int> durationMs,
  Value<bool> watched,
  Value<DateTime> updatedAt,
});

final class $$WatchTableReferences
    extends BaseReferences<_$AppDatabase, $WatchTable, WatchRow> {
  $$WatchTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FilesTable _fileIdTable(_$AppDatabase db) =>
      db.files.createAlias('watch__file_id__files__id');

  $$FilesTableProcessedTableManager get fileId {
    final $_column = $_itemColumn<int>('file_id')!;

    final manager = $$FilesTableTableManager(
      $_db,
      $_db.files,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$WatchTableFilterComposer extends Composer<_$AppDatabase, $WatchTable> {
  $$WatchTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get watched => $composableBuilder(
    column: $table.watched,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$FilesTableFilterComposer get fileId {
    final $$FilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fileId,
      referencedTable: $db.files,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FilesTableFilterComposer(
            $db: $db,
            $table: $db.files,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WatchTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchTable> {
  $$WatchTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get watched => $composableBuilder(
    column: $table.watched,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$FilesTableOrderingComposer get fileId {
    final $$FilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fileId,
      referencedTable: $db.files,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FilesTableOrderingComposer(
            $db: $db,
            $table: $db.files,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WatchTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchTable> {
  $$WatchTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get watched =>
      $composableBuilder(column: $table.watched, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$FilesTableAnnotationComposer get fileId {
    final $$FilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fileId,
      referencedTable: $db.files,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FilesTableAnnotationComposer(
            $db: $db,
            $table: $db.files,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WatchTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WatchTable,
          WatchRow,
          $$WatchTableFilterComposer,
          $$WatchTableOrderingComposer,
          $$WatchTableAnnotationComposer,
          $$WatchTableCreateCompanionBuilder,
          $$WatchTableUpdateCompanionBuilder,
          (WatchRow, $$WatchTableReferences),
          WatchRow,
          PrefetchHooks Function({bool fileId})
        > {
  $$WatchTableTableManager(_$AppDatabase db, $WatchTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> fileId = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<bool> watched = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => WatchCompanion(
                fileId: fileId,
                positionMs: positionMs,
                durationMs: durationMs,
                watched: watched,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> fileId = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<bool> watched = const Value.absent(),
                required DateTime updatedAt,
              }) => WatchCompanion.insert(
                fileId: fileId,
                positionMs: positionMs,
                durationMs: durationMs,
                watched: watched,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WatchTable, WatchRow>(table),
                  $$WatchTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({fileId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (fileId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.fileId,
                        referencedTable: $$WatchTableReferences._fileIdTable(
                          db,
                        ),
                        referencedColumn: $$WatchTableReferences
                            ._fileIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$WatchTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WatchTable,
      WatchRow,
      $$WatchTableFilterComposer,
      $$WatchTableOrderingComposer,
      $$WatchTableAnnotationComposer,
      $$WatchTableCreateCompanionBuilder,
      $$WatchTableUpdateCompanionBuilder,
      (WatchRow, $$WatchTableReferences),
      WatchRow,
      PrefetchHooks Function({bool fileId})
    >;
typedef $$WatchKeepTableCreateCompanionBuilder = WatchKeepCompanion Function({
  required String url,
  required int positionMs,
  required int durationMs,
  required bool watched,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$WatchKeepTableUpdateCompanionBuilder = WatchKeepCompanion Function({
  Value<String> url,
  Value<int> positionMs,
  Value<int> durationMs,
  Value<bool> watched,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$WatchKeepTableFilterComposer
    extends Composer<_$AppDatabase, $WatchKeepTable> {
  $$WatchKeepTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get watched => $composableBuilder(
    column: $table.watched,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WatchKeepTableOrderingComposer
    extends Composer<_$AppDatabase, $WatchKeepTable> {
  $$WatchKeepTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get watched => $composableBuilder(
    column: $table.watched,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WatchKeepTableAnnotationComposer
    extends Composer<_$AppDatabase, $WatchKeepTable> {
  $$WatchKeepTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<int> get positionMs => $composableBuilder(
    column: $table.positionMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get watched =>
      $composableBuilder(column: $table.watched, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$WatchKeepTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WatchKeepTable,
          WatchKeepRow,
          $$WatchKeepTableFilterComposer,
          $$WatchKeepTableOrderingComposer,
          $$WatchKeepTableAnnotationComposer,
          $$WatchKeepTableCreateCompanionBuilder,
          $$WatchKeepTableUpdateCompanionBuilder,
          (
            WatchKeepRow,
            BaseReferences<_$AppDatabase, $WatchKeepTable, WatchKeepRow>,
          ),
          WatchKeepRow,
          PrefetchHooks Function()
        > {
  $$WatchKeepTableTableManager(_$AppDatabase db, $WatchKeepTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatchKeepTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatchKeepTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatchKeepTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> url = const Value.absent(),
                Value<int> positionMs = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<bool> watched = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WatchKeepCompanion(
                url: url,
                positionMs: positionMs,
                durationMs: durationMs,
                watched: watched,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String url,
                required int positionMs,
                required int durationMs,
                required bool watched,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => WatchKeepCompanion.insert(
                url: url,
                positionMs: positionMs,
                durationMs: durationMs,
                watched: watched,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WatchKeepTable, WatchKeepRow>(table),
                  BaseReferences<_$AppDatabase, $WatchKeepTable, WatchKeepRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WatchKeepTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WatchKeepTable,
      WatchKeepRow,
      $$WatchKeepTableFilterComposer,
      $$WatchKeepTableOrderingComposer,
      $$WatchKeepTableAnnotationComposer,
      $$WatchKeepTableCreateCompanionBuilder,
      $$WatchKeepTableUpdateCompanionBuilder,
      (
        WatchKeepRow,
        BaseReferences<_$AppDatabase, $WatchKeepTable, WatchKeepRow>,
      ),
      WatchKeepRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SourcesTableTableManager get sources =>
      $$SourcesTableTableManager(_db, _db.sources);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db, _db.categories);
  $$TitlesTableTableManager get titles =>
      $$TitlesTableTableManager(_db, _db.titles);
  $$SeasonsTableTableManager get seasons =>
      $$SeasonsTableTableManager(_db, _db.seasons);
  $$FilesTableTableManager get files =>
      $$FilesTableTableManager(_db, _db.files);
  $$WatchTableTableManager get watch =>
      $$WatchTableTableManager(_db, _db.watch);
  $$WatchKeepTableTableManager get watchKeep =>
      $$WatchKeepTableTableManager(_db, _db.watchKeep);
}
