// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $SeriesTable extends Series with TableInfo<$SeriesTable, Sery> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'series';
  @override
  VerificationContext validateIntegrity(
    Insertable<Sery> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Sery map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Sery(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $SeriesTable createAlias(String alias) {
    return $SeriesTable(attachedDatabase, alias);
  }
}

class Sery extends DataClass implements Insertable<Sery> {
  final String id;
  final String name;
  const Sery({required this.id, required this.name});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    return map;
  }

  SeriesCompanion toCompanion(bool nullToAbsent) {
    return SeriesCompanion(id: Value(id), name: Value(name));
  }

  factory Sery.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Sery(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
    };
  }

  Sery copyWith({String? id, String? name}) =>
      Sery(id: id ?? this.id, name: name ?? this.name);
  Sery copyWithCompanion(SeriesCompanion data) {
    return Sery(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Sery(')
          ..write('id: $id, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Sery && other.id == this.id && other.name == this.name);
}

class SeriesCompanion extends UpdateCompanion<Sery> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> rowid;
  const SeriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SeriesCompanion.insert({
    required String id,
    required String name,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Sery> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SeriesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? rowid,
  }) {
    return SeriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BooksTable extends Books with TableInfo<$BooksTable, Book> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _subtitleMeta = const VerificationMeta(
    'subtitle',
  );
  @override
  late final GeneratedColumn<String> subtitle = GeneratedColumn<String>(
    'subtitle',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isbnMeta = const VerificationMeta('isbn');
  @override
  late final GeneratedColumn<String> isbn = GeneratedColumn<String>(
    'isbn',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publisherMeta = const VerificationMeta(
    'publisher',
  );
  @override
  late final GeneratedColumn<String> publisher = GeneratedColumn<String>(
    'publisher',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _publishedYearMeta = const VerificationMeta(
    'publishedYear',
  );
  @override
  late final GeneratedColumn<int> publishedYear = GeneratedColumn<int>(
    'published_year',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageCountMeta = const VerificationMeta(
    'pageCount',
  );
  @override
  late final GeneratedColumn<int> pageCount = GeneratedColumn<int>(
    'page_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _coverPathMeta = const VerificationMeta(
    'coverPath',
  );
  @override
  late final GeneratedColumn<String> coverPath = GeneratedColumn<String>(
    'cover_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _spineStyleMeta = const VerificationMeta(
    'spineStyle',
  );
  @override
  late final GeneratedColumn<String> spineStyle = GeneratedColumn<String>(
    'spine_style',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seriesIdMeta = const VerificationMeta(
    'seriesId',
  );
  @override
  late final GeneratedColumn<String> seriesId = GeneratedColumn<String>(
    'series_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES series (id)',
    ),
  );
  static const VerificationMeta _seriesIndexMeta = const VerificationMeta(
    'seriesIndex',
  );
  @override
  late final GeneratedColumn<double> seriesIndex = GeneratedColumn<double>(
    'series_index',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readingProgressMeta = const VerificationMeta(
    'readingProgress',
  );
  @override
  late final GeneratedColumn<double> readingProgress = GeneratedColumn<double>(
    'reading_progress',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastReadPageMeta = const VerificationMeta(
    'lastReadPage',
  );
  @override
  late final GeneratedColumn<int> lastReadPage = GeneratedColumn<int>(
    'last_read_page',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastReadAtMeta = const VerificationMeta(
    'lastReadAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastReadAt = GeneratedColumn<DateTime>(
    'last_read_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readerNotesMeta = const VerificationMeta(
    'readerNotes',
  );
  @override
  late final GeneratedColumn<String> readerNotes = GeneratedColumn<String>(
    'reader_notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readerNotesUpdatedAtMeta =
      const VerificationMeta('readerNotesUpdatedAt');
  @override
  late final GeneratedColumn<DateTime> readerNotesUpdatedAt =
      GeneratedColumn<DateTime>(
        'reader_notes_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _readerNotesNeedsPushMeta =
      const VerificationMeta('readerNotesNeedsPush');
  @override
  late final GeneratedColumn<bool> readerNotesNeedsPush = GeneratedColumn<bool>(
    'reader_notes_needs_push',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("reader_notes_needs_push" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sourceMetadataMeta = const VerificationMeta(
    'sourceMetadata',
  );
  @override
  late final GeneratedColumn<String> sourceMetadata = GeneratedColumn<String>(
    'source_metadata',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _needsPushMeta = const VerificationMeta(
    'needsPush',
  );
  @override
  late final GeneratedColumn<bool> needsPush = GeneratedColumn<bool>(
    'needs_push',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_push" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _coverEtagMeta = const VerificationMeta(
    'coverEtag',
  );
  @override
  late final GeneratedColumn<String> coverEtag = GeneratedColumn<String>(
    'cover_etag',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _needsProgressPushMeta = const VerificationMeta(
    'needsProgressPush',
  );
  @override
  late final GeneratedColumn<bool> needsProgressPush = GeneratedColumn<bool>(
    'needs_progress_push',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_progress_push" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unread'),
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
    'rating',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> finishedAt = GeneratedColumn<DateTime>(
    'finished_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _readCountMeta = const VerificationMeta(
    'readCount',
  );
  @override
  late final GeneratedColumn<int> readCount = GeneratedColumn<int>(
    'read_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncExcludedMeta = const VerificationMeta(
    'syncExcluded',
  );
  @override
  late final GeneratedColumn<bool> syncExcluded = GeneratedColumn<bool>(
    'sync_excluded',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sync_excluded" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _addedByMeta = const VerificationMeta(
    'addedBy',
  );
  @override
  late final GeneratedColumn<String> addedBy = GeneratedColumn<String>(
    'added_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    subtitle,
    description,
    isbn,
    publisher,
    publishedYear,
    pageCount,
    coverPath,
    spineStyle,
    seriesId,
    seriesIndex,
    readingProgress,
    lastReadPage,
    lastReadAt,
    readerNotes,
    readerNotesUpdatedAt,
    readerNotesNeedsPush,
    sourceMetadata,
    createdAt,
    updatedAt,
    needsPush,
    coverEtag,
    needsProgressPush,
    status,
    rating,
    startedAt,
    finishedAt,
    readCount,
    deletedAt,
    syncExcluded,
    addedBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<Book> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('subtitle')) {
      context.handle(
        _subtitleMeta,
        subtitle.isAcceptableOrUnknown(data['subtitle']!, _subtitleMeta),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('isbn')) {
      context.handle(
        _isbnMeta,
        isbn.isAcceptableOrUnknown(data['isbn']!, _isbnMeta),
      );
    }
    if (data.containsKey('publisher')) {
      context.handle(
        _publisherMeta,
        publisher.isAcceptableOrUnknown(data['publisher']!, _publisherMeta),
      );
    }
    if (data.containsKey('published_year')) {
      context.handle(
        _publishedYearMeta,
        publishedYear.isAcceptableOrUnknown(
          data['published_year']!,
          _publishedYearMeta,
        ),
      );
    }
    if (data.containsKey('page_count')) {
      context.handle(
        _pageCountMeta,
        pageCount.isAcceptableOrUnknown(data['page_count']!, _pageCountMeta),
      );
    }
    if (data.containsKey('cover_path')) {
      context.handle(
        _coverPathMeta,
        coverPath.isAcceptableOrUnknown(data['cover_path']!, _coverPathMeta),
      );
    }
    if (data.containsKey('spine_style')) {
      context.handle(
        _spineStyleMeta,
        spineStyle.isAcceptableOrUnknown(data['spine_style']!, _spineStyleMeta),
      );
    }
    if (data.containsKey('series_id')) {
      context.handle(
        _seriesIdMeta,
        seriesId.isAcceptableOrUnknown(data['series_id']!, _seriesIdMeta),
      );
    }
    if (data.containsKey('series_index')) {
      context.handle(
        _seriesIndexMeta,
        seriesIndex.isAcceptableOrUnknown(
          data['series_index']!,
          _seriesIndexMeta,
        ),
      );
    }
    if (data.containsKey('reading_progress')) {
      context.handle(
        _readingProgressMeta,
        readingProgress.isAcceptableOrUnknown(
          data['reading_progress']!,
          _readingProgressMeta,
        ),
      );
    }
    if (data.containsKey('last_read_page')) {
      context.handle(
        _lastReadPageMeta,
        lastReadPage.isAcceptableOrUnknown(
          data['last_read_page']!,
          _lastReadPageMeta,
        ),
      );
    }
    if (data.containsKey('last_read_at')) {
      context.handle(
        _lastReadAtMeta,
        lastReadAt.isAcceptableOrUnknown(
          data['last_read_at']!,
          _lastReadAtMeta,
        ),
      );
    }
    if (data.containsKey('reader_notes')) {
      context.handle(
        _readerNotesMeta,
        readerNotes.isAcceptableOrUnknown(
          data['reader_notes']!,
          _readerNotesMeta,
        ),
      );
    }
    if (data.containsKey('reader_notes_updated_at')) {
      context.handle(
        _readerNotesUpdatedAtMeta,
        readerNotesUpdatedAt.isAcceptableOrUnknown(
          data['reader_notes_updated_at']!,
          _readerNotesUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('reader_notes_needs_push')) {
      context.handle(
        _readerNotesNeedsPushMeta,
        readerNotesNeedsPush.isAcceptableOrUnknown(
          data['reader_notes_needs_push']!,
          _readerNotesNeedsPushMeta,
        ),
      );
    }
    if (data.containsKey('source_metadata')) {
      context.handle(
        _sourceMetadataMeta,
        sourceMetadata.isAcceptableOrUnknown(
          data['source_metadata']!,
          _sourceMetadataMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('needs_push')) {
      context.handle(
        _needsPushMeta,
        needsPush.isAcceptableOrUnknown(data['needs_push']!, _needsPushMeta),
      );
    }
    if (data.containsKey('cover_etag')) {
      context.handle(
        _coverEtagMeta,
        coverEtag.isAcceptableOrUnknown(data['cover_etag']!, _coverEtagMeta),
      );
    }
    if (data.containsKey('needs_progress_push')) {
      context.handle(
        _needsProgressPushMeta,
        needsProgressPush.isAcceptableOrUnknown(
          data['needs_progress_push']!,
          _needsProgressPushMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    }
    if (data.containsKey('read_count')) {
      context.handle(
        _readCountMeta,
        readCount.isAcceptableOrUnknown(data['read_count']!, _readCountMeta),
      );
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('sync_excluded')) {
      context.handle(
        _syncExcludedMeta,
        syncExcluded.isAcceptableOrUnknown(
          data['sync_excluded']!,
          _syncExcludedMeta,
        ),
      );
    }
    if (data.containsKey('added_by')) {
      context.handle(
        _addedByMeta,
        addedBy.isAcceptableOrUnknown(data['added_by']!, _addedByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Book map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Book(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      subtitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}subtitle'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      isbn: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}isbn'],
      ),
      publisher: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}publisher'],
      ),
      publishedYear: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}published_year'],
      ),
      pageCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page_count'],
      ),
      coverPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_path'],
      ),
      spineStyle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}spine_style'],
      ),
      seriesId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_id'],
      ),
      seriesIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}series_index'],
      ),
      readingProgress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}reading_progress'],
      ),
      lastReadPage: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_read_page'],
      ),
      lastReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_read_at'],
      ),
      readerNotes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reader_notes'],
      ),
      readerNotesUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}reader_notes_updated_at'],
      ),
      readerNotesNeedsPush: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}reader_notes_needs_push'],
      )!,
      sourceMetadata: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_metadata'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      needsPush: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_push'],
      )!,
      coverEtag: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cover_etag'],
      ),
      needsProgressPush: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_progress_push'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating'],
      ),
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      ),
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}finished_at'],
      ),
      readCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}read_count'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      syncExcluded: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sync_excluded'],
      )!,
      addedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}added_by'],
      ),
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }
}

class Book extends DataClass implements Insertable<Book> {
  final String id;
  final String title;
  final String? subtitle;
  final String? description;
  final String? isbn;
  final String? publisher;
  final int? publishedYear;
  final int? pageCount;
  final String? coverPath;
  final String? spineStyle;
  final String? seriesId;
  final double? seriesIndex;
  final double? readingProgress;
  final int? lastReadPage;
  final DateTime? lastReadAt;
  final String? readerNotes;

  /// The private note's own clock and outbox flag.
  ///
  /// Separate from the book's `updatedAt`/`needsPush` because the note does not
  /// travel with the book: it goes to `/api/notes`, a per-user table, so that a
  /// library shared with someone else does not hand them your notes. Editing a
  /// note must therefore not look like editing the catalogue entry.
  final DateTime? readerNotesUpdatedAt;
  final bool readerNotesNeedsPush;
  final String? sourceMetadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool needsPush;
  final String? coverEtag;
  final bool needsProgressPush;
  final String status;

  /// 1–5, or null for unrated.
  final int? rating;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// How many times this book has been finished, for re-reads.
  final int readCount;

  /// When this book was moved to the trash, or null for a live book.
  ///
  /// **App-local, and deliberately so.** A trashed book is not deleted — no
  /// tombstone is written, its files stay on disk, and the server is told
  /// nothing — it is only hidden here until the grace period expires and the
  /// real delete runs. Mirroring the column would make one device's second
  /// thoughts another device's deletion, which is the opposite of the point.
  ///
  /// Everything that reads the library filters on `deleted_at IS NULL`;
  /// [LibraryQueries] does it centrally for the shelf, and the push side
  /// skips trashed rows so a book on its way out never reaches the server.
  final DateTime? deletedAt;

  /// Keep this book on this device only: no push, no pull, no covers or files
  /// either way.
  ///
  /// **App-local, and deliberately so** — like [deletedAt] above. It is a
  /// statement about *this* device's appetite, not about the book: mirroring it
  /// would let one device decide what another one is allowed to see, and a
  /// shared library would inherit one person's shyness about a title.
  ///
  /// Excluding a book that was already pushed does **not** take it off the
  /// server. Deleting it there removes it for everyone the library is shared
  /// with, which is a different intent with its own button; this one only stops
  /// the traffic from here.
  final bool syncExcluded;

  /// Who added this book, as the server names them — their display name, or
  /// their email if they never set one.
  ///
  /// **App-local, and derived rather than owned.** The server holds the truth
  /// (`book.owner_id`); this is the readable form of it, cached at pull time so
  /// a book's page can say "Added by Ana" without a lookup per book. Never
  /// pushed: it is the server's answer, and a client asserting it would be
  /// claiming to know something it was told. Null for a book added here, on a
  /// library with no server, or by an account since removed.
  final String? addedBy;
  const Book({
    required this.id,
    required this.title,
    this.subtitle,
    this.description,
    this.isbn,
    this.publisher,
    this.publishedYear,
    this.pageCount,
    this.coverPath,
    this.spineStyle,
    this.seriesId,
    this.seriesIndex,
    this.readingProgress,
    this.lastReadPage,
    this.lastReadAt,
    this.readerNotes,
    this.readerNotesUpdatedAt,
    required this.readerNotesNeedsPush,
    this.sourceMetadata,
    required this.createdAt,
    required this.updatedAt,
    required this.needsPush,
    this.coverEtag,
    required this.needsProgressPush,
    required this.status,
    this.rating,
    this.startedAt,
    this.finishedAt,
    required this.readCount,
    this.deletedAt,
    required this.syncExcluded,
    this.addedBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || subtitle != null) {
      map['subtitle'] = Variable<String>(subtitle);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || isbn != null) {
      map['isbn'] = Variable<String>(isbn);
    }
    if (!nullToAbsent || publisher != null) {
      map['publisher'] = Variable<String>(publisher);
    }
    if (!nullToAbsent || publishedYear != null) {
      map['published_year'] = Variable<int>(publishedYear);
    }
    if (!nullToAbsent || pageCount != null) {
      map['page_count'] = Variable<int>(pageCount);
    }
    if (!nullToAbsent || coverPath != null) {
      map['cover_path'] = Variable<String>(coverPath);
    }
    if (!nullToAbsent || spineStyle != null) {
      map['spine_style'] = Variable<String>(spineStyle);
    }
    if (!nullToAbsent || seriesId != null) {
      map['series_id'] = Variable<String>(seriesId);
    }
    if (!nullToAbsent || seriesIndex != null) {
      map['series_index'] = Variable<double>(seriesIndex);
    }
    if (!nullToAbsent || readingProgress != null) {
      map['reading_progress'] = Variable<double>(readingProgress);
    }
    if (!nullToAbsent || lastReadPage != null) {
      map['last_read_page'] = Variable<int>(lastReadPage);
    }
    if (!nullToAbsent || lastReadAt != null) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt);
    }
    if (!nullToAbsent || readerNotes != null) {
      map['reader_notes'] = Variable<String>(readerNotes);
    }
    if (!nullToAbsent || readerNotesUpdatedAt != null) {
      map['reader_notes_updated_at'] = Variable<DateTime>(readerNotesUpdatedAt);
    }
    map['reader_notes_needs_push'] = Variable<bool>(readerNotesNeedsPush);
    if (!nullToAbsent || sourceMetadata != null) {
      map['source_metadata'] = Variable<String>(sourceMetadata);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['needs_push'] = Variable<bool>(needsPush);
    if (!nullToAbsent || coverEtag != null) {
      map['cover_etag'] = Variable<String>(coverEtag);
    }
    map['needs_progress_push'] = Variable<bool>(needsProgressPush);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || rating != null) {
      map['rating'] = Variable<int>(rating);
    }
    if (!nullToAbsent || startedAt != null) {
      map['started_at'] = Variable<DateTime>(startedAt);
    }
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<DateTime>(finishedAt);
    }
    map['read_count'] = Variable<int>(readCount);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    map['sync_excluded'] = Variable<bool>(syncExcluded);
    if (!nullToAbsent || addedBy != null) {
      map['added_by'] = Variable<String>(addedBy);
    }
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      title: Value(title),
      subtitle: subtitle == null && nullToAbsent
          ? const Value.absent()
          : Value(subtitle),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      isbn: isbn == null && nullToAbsent ? const Value.absent() : Value(isbn),
      publisher: publisher == null && nullToAbsent
          ? const Value.absent()
          : Value(publisher),
      publishedYear: publishedYear == null && nullToAbsent
          ? const Value.absent()
          : Value(publishedYear),
      pageCount: pageCount == null && nullToAbsent
          ? const Value.absent()
          : Value(pageCount),
      coverPath: coverPath == null && nullToAbsent
          ? const Value.absent()
          : Value(coverPath),
      spineStyle: spineStyle == null && nullToAbsent
          ? const Value.absent()
          : Value(spineStyle),
      seriesId: seriesId == null && nullToAbsent
          ? const Value.absent()
          : Value(seriesId),
      seriesIndex: seriesIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(seriesIndex),
      readingProgress: readingProgress == null && nullToAbsent
          ? const Value.absent()
          : Value(readingProgress),
      lastReadPage: lastReadPage == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadPage),
      lastReadAt: lastReadAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadAt),
      readerNotes: readerNotes == null && nullToAbsent
          ? const Value.absent()
          : Value(readerNotes),
      readerNotesUpdatedAt: readerNotesUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(readerNotesUpdatedAt),
      readerNotesNeedsPush: Value(readerNotesNeedsPush),
      sourceMetadata: sourceMetadata == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceMetadata),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      needsPush: Value(needsPush),
      coverEtag: coverEtag == null && nullToAbsent
          ? const Value.absent()
          : Value(coverEtag),
      needsProgressPush: Value(needsProgressPush),
      status: Value(status),
      rating: rating == null && nullToAbsent
          ? const Value.absent()
          : Value(rating),
      startedAt: startedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(startedAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
      readCount: Value(readCount),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      syncExcluded: Value(syncExcluded),
      addedBy: addedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(addedBy),
    );
  }

  factory Book.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Book(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      subtitle: serializer.fromJson<String?>(json['subtitle']),
      description: serializer.fromJson<String?>(json['description']),
      isbn: serializer.fromJson<String?>(json['isbn']),
      publisher: serializer.fromJson<String?>(json['publisher']),
      publishedYear: serializer.fromJson<int?>(json['publishedYear']),
      pageCount: serializer.fromJson<int?>(json['pageCount']),
      coverPath: serializer.fromJson<String?>(json['coverPath']),
      spineStyle: serializer.fromJson<String?>(json['spineStyle']),
      seriesId: serializer.fromJson<String?>(json['seriesId']),
      seriesIndex: serializer.fromJson<double?>(json['seriesIndex']),
      readingProgress: serializer.fromJson<double?>(json['readingProgress']),
      lastReadPage: serializer.fromJson<int?>(json['lastReadPage']),
      lastReadAt: serializer.fromJson<DateTime?>(json['lastReadAt']),
      readerNotes: serializer.fromJson<String?>(json['readerNotes']),
      readerNotesUpdatedAt: serializer.fromJson<DateTime?>(
        json['readerNotesUpdatedAt'],
      ),
      readerNotesNeedsPush: serializer.fromJson<bool>(
        json['readerNotesNeedsPush'],
      ),
      sourceMetadata: serializer.fromJson<String?>(json['sourceMetadata']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      needsPush: serializer.fromJson<bool>(json['needsPush']),
      coverEtag: serializer.fromJson<String?>(json['coverEtag']),
      needsProgressPush: serializer.fromJson<bool>(json['needsProgressPush']),
      status: serializer.fromJson<String>(json['status']),
      rating: serializer.fromJson<int?>(json['rating']),
      startedAt: serializer.fromJson<DateTime?>(json['startedAt']),
      finishedAt: serializer.fromJson<DateTime?>(json['finishedAt']),
      readCount: serializer.fromJson<int>(json['readCount']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      syncExcluded: serializer.fromJson<bool>(json['syncExcluded']),
      addedBy: serializer.fromJson<String?>(json['addedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'subtitle': serializer.toJson<String?>(subtitle),
      'description': serializer.toJson<String?>(description),
      'isbn': serializer.toJson<String?>(isbn),
      'publisher': serializer.toJson<String?>(publisher),
      'publishedYear': serializer.toJson<int?>(publishedYear),
      'pageCount': serializer.toJson<int?>(pageCount),
      'coverPath': serializer.toJson<String?>(coverPath),
      'spineStyle': serializer.toJson<String?>(spineStyle),
      'seriesId': serializer.toJson<String?>(seriesId),
      'seriesIndex': serializer.toJson<double?>(seriesIndex),
      'readingProgress': serializer.toJson<double?>(readingProgress),
      'lastReadPage': serializer.toJson<int?>(lastReadPage),
      'lastReadAt': serializer.toJson<DateTime?>(lastReadAt),
      'readerNotes': serializer.toJson<String?>(readerNotes),
      'readerNotesUpdatedAt': serializer.toJson<DateTime?>(
        readerNotesUpdatedAt,
      ),
      'readerNotesNeedsPush': serializer.toJson<bool>(readerNotesNeedsPush),
      'sourceMetadata': serializer.toJson<String?>(sourceMetadata),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'needsPush': serializer.toJson<bool>(needsPush),
      'coverEtag': serializer.toJson<String?>(coverEtag),
      'needsProgressPush': serializer.toJson<bool>(needsProgressPush),
      'status': serializer.toJson<String>(status),
      'rating': serializer.toJson<int?>(rating),
      'startedAt': serializer.toJson<DateTime?>(startedAt),
      'finishedAt': serializer.toJson<DateTime?>(finishedAt),
      'readCount': serializer.toJson<int>(readCount),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'syncExcluded': serializer.toJson<bool>(syncExcluded),
      'addedBy': serializer.toJson<String?>(addedBy),
    };
  }

  Book copyWith({
    String? id,
    String? title,
    Value<String?> subtitle = const Value.absent(),
    Value<String?> description = const Value.absent(),
    Value<String?> isbn = const Value.absent(),
    Value<String?> publisher = const Value.absent(),
    Value<int?> publishedYear = const Value.absent(),
    Value<int?> pageCount = const Value.absent(),
    Value<String?> coverPath = const Value.absent(),
    Value<String?> spineStyle = const Value.absent(),
    Value<String?> seriesId = const Value.absent(),
    Value<double?> seriesIndex = const Value.absent(),
    Value<double?> readingProgress = const Value.absent(),
    Value<int?> lastReadPage = const Value.absent(),
    Value<DateTime?> lastReadAt = const Value.absent(),
    Value<String?> readerNotes = const Value.absent(),
    Value<DateTime?> readerNotesUpdatedAt = const Value.absent(),
    bool? readerNotesNeedsPush,
    Value<String?> sourceMetadata = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? needsPush,
    Value<String?> coverEtag = const Value.absent(),
    bool? needsProgressPush,
    String? status,
    Value<int?> rating = const Value.absent(),
    Value<DateTime?> startedAt = const Value.absent(),
    Value<DateTime?> finishedAt = const Value.absent(),
    int? readCount,
    Value<DateTime?> deletedAt = const Value.absent(),
    bool? syncExcluded,
    Value<String?> addedBy = const Value.absent(),
  }) => Book(
    id: id ?? this.id,
    title: title ?? this.title,
    subtitle: subtitle.present ? subtitle.value : this.subtitle,
    description: description.present ? description.value : this.description,
    isbn: isbn.present ? isbn.value : this.isbn,
    publisher: publisher.present ? publisher.value : this.publisher,
    publishedYear: publishedYear.present
        ? publishedYear.value
        : this.publishedYear,
    pageCount: pageCount.present ? pageCount.value : this.pageCount,
    coverPath: coverPath.present ? coverPath.value : this.coverPath,
    spineStyle: spineStyle.present ? spineStyle.value : this.spineStyle,
    seriesId: seriesId.present ? seriesId.value : this.seriesId,
    seriesIndex: seriesIndex.present ? seriesIndex.value : this.seriesIndex,
    readingProgress: readingProgress.present
        ? readingProgress.value
        : this.readingProgress,
    lastReadPage: lastReadPage.present ? lastReadPage.value : this.lastReadPage,
    lastReadAt: lastReadAt.present ? lastReadAt.value : this.lastReadAt,
    readerNotes: readerNotes.present ? readerNotes.value : this.readerNotes,
    readerNotesUpdatedAt: readerNotesUpdatedAt.present
        ? readerNotesUpdatedAt.value
        : this.readerNotesUpdatedAt,
    readerNotesNeedsPush: readerNotesNeedsPush ?? this.readerNotesNeedsPush,
    sourceMetadata: sourceMetadata.present
        ? sourceMetadata.value
        : this.sourceMetadata,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    needsPush: needsPush ?? this.needsPush,
    coverEtag: coverEtag.present ? coverEtag.value : this.coverEtag,
    needsProgressPush: needsProgressPush ?? this.needsProgressPush,
    status: status ?? this.status,
    rating: rating.present ? rating.value : this.rating,
    startedAt: startedAt.present ? startedAt.value : this.startedAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
    readCount: readCount ?? this.readCount,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
    syncExcluded: syncExcluded ?? this.syncExcluded,
    addedBy: addedBy.present ? addedBy.value : this.addedBy,
  );
  Book copyWithCompanion(BooksCompanion data) {
    return Book(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      subtitle: data.subtitle.present ? data.subtitle.value : this.subtitle,
      description: data.description.present
          ? data.description.value
          : this.description,
      isbn: data.isbn.present ? data.isbn.value : this.isbn,
      publisher: data.publisher.present ? data.publisher.value : this.publisher,
      publishedYear: data.publishedYear.present
          ? data.publishedYear.value
          : this.publishedYear,
      pageCount: data.pageCount.present ? data.pageCount.value : this.pageCount,
      coverPath: data.coverPath.present ? data.coverPath.value : this.coverPath,
      spineStyle: data.spineStyle.present
          ? data.spineStyle.value
          : this.spineStyle,
      seriesId: data.seriesId.present ? data.seriesId.value : this.seriesId,
      seriesIndex: data.seriesIndex.present
          ? data.seriesIndex.value
          : this.seriesIndex,
      readingProgress: data.readingProgress.present
          ? data.readingProgress.value
          : this.readingProgress,
      lastReadPage: data.lastReadPage.present
          ? data.lastReadPage.value
          : this.lastReadPage,
      lastReadAt: data.lastReadAt.present
          ? data.lastReadAt.value
          : this.lastReadAt,
      readerNotes: data.readerNotes.present
          ? data.readerNotes.value
          : this.readerNotes,
      readerNotesUpdatedAt: data.readerNotesUpdatedAt.present
          ? data.readerNotesUpdatedAt.value
          : this.readerNotesUpdatedAt,
      readerNotesNeedsPush: data.readerNotesNeedsPush.present
          ? data.readerNotesNeedsPush.value
          : this.readerNotesNeedsPush,
      sourceMetadata: data.sourceMetadata.present
          ? data.sourceMetadata.value
          : this.sourceMetadata,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      needsPush: data.needsPush.present ? data.needsPush.value : this.needsPush,
      coverEtag: data.coverEtag.present ? data.coverEtag.value : this.coverEtag,
      needsProgressPush: data.needsProgressPush.present
          ? data.needsProgressPush.value
          : this.needsProgressPush,
      status: data.status.present ? data.status.value : this.status,
      rating: data.rating.present ? data.rating.value : this.rating,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
      readCount: data.readCount.present ? data.readCount.value : this.readCount,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      syncExcluded: data.syncExcluded.present
          ? data.syncExcluded.value
          : this.syncExcluded,
      addedBy: data.addedBy.present ? data.addedBy.value : this.addedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Book(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('subtitle: $subtitle, ')
          ..write('description: $description, ')
          ..write('isbn: $isbn, ')
          ..write('publisher: $publisher, ')
          ..write('publishedYear: $publishedYear, ')
          ..write('pageCount: $pageCount, ')
          ..write('coverPath: $coverPath, ')
          ..write('spineStyle: $spineStyle, ')
          ..write('seriesId: $seriesId, ')
          ..write('seriesIndex: $seriesIndex, ')
          ..write('readingProgress: $readingProgress, ')
          ..write('lastReadPage: $lastReadPage, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('readerNotes: $readerNotes, ')
          ..write('readerNotesUpdatedAt: $readerNotesUpdatedAt, ')
          ..write('readerNotesNeedsPush: $readerNotesNeedsPush, ')
          ..write('sourceMetadata: $sourceMetadata, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('needsPush: $needsPush, ')
          ..write('coverEtag: $coverEtag, ')
          ..write('needsProgressPush: $needsProgressPush, ')
          ..write('status: $status, ')
          ..write('rating: $rating, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('readCount: $readCount, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncExcluded: $syncExcluded, ')
          ..write('addedBy: $addedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    title,
    subtitle,
    description,
    isbn,
    publisher,
    publishedYear,
    pageCount,
    coverPath,
    spineStyle,
    seriesId,
    seriesIndex,
    readingProgress,
    lastReadPage,
    lastReadAt,
    readerNotes,
    readerNotesUpdatedAt,
    readerNotesNeedsPush,
    sourceMetadata,
    createdAt,
    updatedAt,
    needsPush,
    coverEtag,
    needsProgressPush,
    status,
    rating,
    startedAt,
    finishedAt,
    readCount,
    deletedAt,
    syncExcluded,
    addedBy,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Book &&
          other.id == this.id &&
          other.title == this.title &&
          other.subtitle == this.subtitle &&
          other.description == this.description &&
          other.isbn == this.isbn &&
          other.publisher == this.publisher &&
          other.publishedYear == this.publishedYear &&
          other.pageCount == this.pageCount &&
          other.coverPath == this.coverPath &&
          other.spineStyle == this.spineStyle &&
          other.seriesId == this.seriesId &&
          other.seriesIndex == this.seriesIndex &&
          other.readingProgress == this.readingProgress &&
          other.lastReadPage == this.lastReadPage &&
          other.lastReadAt == this.lastReadAt &&
          other.readerNotes == this.readerNotes &&
          other.readerNotesUpdatedAt == this.readerNotesUpdatedAt &&
          other.readerNotesNeedsPush == this.readerNotesNeedsPush &&
          other.sourceMetadata == this.sourceMetadata &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.needsPush == this.needsPush &&
          other.coverEtag == this.coverEtag &&
          other.needsProgressPush == this.needsProgressPush &&
          other.status == this.status &&
          other.rating == this.rating &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt &&
          other.readCount == this.readCount &&
          other.deletedAt == this.deletedAt &&
          other.syncExcluded == this.syncExcluded &&
          other.addedBy == this.addedBy);
}

class BooksCompanion extends UpdateCompanion<Book> {
  final Value<String> id;
  final Value<String> title;
  final Value<String?> subtitle;
  final Value<String?> description;
  final Value<String?> isbn;
  final Value<String?> publisher;
  final Value<int?> publishedYear;
  final Value<int?> pageCount;
  final Value<String?> coverPath;
  final Value<String?> spineStyle;
  final Value<String?> seriesId;
  final Value<double?> seriesIndex;
  final Value<double?> readingProgress;
  final Value<int?> lastReadPage;
  final Value<DateTime?> lastReadAt;
  final Value<String?> readerNotes;
  final Value<DateTime?> readerNotesUpdatedAt;
  final Value<bool> readerNotesNeedsPush;
  final Value<String?> sourceMetadata;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> needsPush;
  final Value<String?> coverEtag;
  final Value<bool> needsProgressPush;
  final Value<String> status;
  final Value<int?> rating;
  final Value<DateTime?> startedAt;
  final Value<DateTime?> finishedAt;
  final Value<int> readCount;
  final Value<DateTime?> deletedAt;
  final Value<bool> syncExcluded;
  final Value<String?> addedBy;
  final Value<int> rowid;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.subtitle = const Value.absent(),
    this.description = const Value.absent(),
    this.isbn = const Value.absent(),
    this.publisher = const Value.absent(),
    this.publishedYear = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.spineStyle = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.seriesIndex = const Value.absent(),
    this.readingProgress = const Value.absent(),
    this.lastReadPage = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.readerNotes = const Value.absent(),
    this.readerNotesUpdatedAt = const Value.absent(),
    this.readerNotesNeedsPush = const Value.absent(),
    this.sourceMetadata = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.coverEtag = const Value.absent(),
    this.needsProgressPush = const Value.absent(),
    this.status = const Value.absent(),
    this.rating = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.readCount = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncExcluded = const Value.absent(),
    this.addedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BooksCompanion.insert({
    required String id,
    required String title,
    this.subtitle = const Value.absent(),
    this.description = const Value.absent(),
    this.isbn = const Value.absent(),
    this.publisher = const Value.absent(),
    this.publishedYear = const Value.absent(),
    this.pageCount = const Value.absent(),
    this.coverPath = const Value.absent(),
    this.spineStyle = const Value.absent(),
    this.seriesId = const Value.absent(),
    this.seriesIndex = const Value.absent(),
    this.readingProgress = const Value.absent(),
    this.lastReadPage = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.readerNotes = const Value.absent(),
    this.readerNotesUpdatedAt = const Value.absent(),
    this.readerNotesNeedsPush = const Value.absent(),
    this.sourceMetadata = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.coverEtag = const Value.absent(),
    this.needsProgressPush = const Value.absent(),
    this.status = const Value.absent(),
    this.rating = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.readCount = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.syncExcluded = const Value.absent(),
    this.addedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title);
  static Insertable<Book> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? subtitle,
    Expression<String>? description,
    Expression<String>? isbn,
    Expression<String>? publisher,
    Expression<int>? publishedYear,
    Expression<int>? pageCount,
    Expression<String>? coverPath,
    Expression<String>? spineStyle,
    Expression<String>? seriesId,
    Expression<double>? seriesIndex,
    Expression<double>? readingProgress,
    Expression<int>? lastReadPage,
    Expression<DateTime>? lastReadAt,
    Expression<String>? readerNotes,
    Expression<DateTime>? readerNotesUpdatedAt,
    Expression<bool>? readerNotesNeedsPush,
    Expression<String>? sourceMetadata,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? needsPush,
    Expression<String>? coverEtag,
    Expression<bool>? needsProgressPush,
    Expression<String>? status,
    Expression<int>? rating,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? finishedAt,
    Expression<int>? readCount,
    Expression<DateTime>? deletedAt,
    Expression<bool>? syncExcluded,
    Expression<String>? addedBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (subtitle != null) 'subtitle': subtitle,
      if (description != null) 'description': description,
      if (isbn != null) 'isbn': isbn,
      if (publisher != null) 'publisher': publisher,
      if (publishedYear != null) 'published_year': publishedYear,
      if (pageCount != null) 'page_count': pageCount,
      if (coverPath != null) 'cover_path': coverPath,
      if (spineStyle != null) 'spine_style': spineStyle,
      if (seriesId != null) 'series_id': seriesId,
      if (seriesIndex != null) 'series_index': seriesIndex,
      if (readingProgress != null) 'reading_progress': readingProgress,
      if (lastReadPage != null) 'last_read_page': lastReadPage,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (readerNotes != null) 'reader_notes': readerNotes,
      if (readerNotesUpdatedAt != null)
        'reader_notes_updated_at': readerNotesUpdatedAt,
      if (readerNotesNeedsPush != null)
        'reader_notes_needs_push': readerNotesNeedsPush,
      if (sourceMetadata != null) 'source_metadata': sourceMetadata,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (needsPush != null) 'needs_push': needsPush,
      if (coverEtag != null) 'cover_etag': coverEtag,
      if (needsProgressPush != null) 'needs_progress_push': needsProgressPush,
      if (status != null) 'status': status,
      if (rating != null) 'rating': rating,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (readCount != null) 'read_count': readCount,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (syncExcluded != null) 'sync_excluded': syncExcluded,
      if (addedBy != null) 'added_by': addedBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BooksCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String?>? subtitle,
    Value<String?>? description,
    Value<String?>? isbn,
    Value<String?>? publisher,
    Value<int?>? publishedYear,
    Value<int?>? pageCount,
    Value<String?>? coverPath,
    Value<String?>? spineStyle,
    Value<String?>? seriesId,
    Value<double?>? seriesIndex,
    Value<double?>? readingProgress,
    Value<int?>? lastReadPage,
    Value<DateTime?>? lastReadAt,
    Value<String?>? readerNotes,
    Value<DateTime?>? readerNotesUpdatedAt,
    Value<bool>? readerNotesNeedsPush,
    Value<String?>? sourceMetadata,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? needsPush,
    Value<String?>? coverEtag,
    Value<bool>? needsProgressPush,
    Value<String>? status,
    Value<int?>? rating,
    Value<DateTime?>? startedAt,
    Value<DateTime?>? finishedAt,
    Value<int>? readCount,
    Value<DateTime?>? deletedAt,
    Value<bool>? syncExcluded,
    Value<String?>? addedBy,
    Value<int>? rowid,
  }) {
    return BooksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      description: description ?? this.description,
      isbn: isbn ?? this.isbn,
      publisher: publisher ?? this.publisher,
      publishedYear: publishedYear ?? this.publishedYear,
      pageCount: pageCount ?? this.pageCount,
      coverPath: coverPath ?? this.coverPath,
      spineStyle: spineStyle ?? this.spineStyle,
      seriesId: seriesId ?? this.seriesId,
      seriesIndex: seriesIndex ?? this.seriesIndex,
      readingProgress: readingProgress ?? this.readingProgress,
      lastReadPage: lastReadPage ?? this.lastReadPage,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      readerNotes: readerNotes ?? this.readerNotes,
      readerNotesUpdatedAt: readerNotesUpdatedAt ?? this.readerNotesUpdatedAt,
      readerNotesNeedsPush: readerNotesNeedsPush ?? this.readerNotesNeedsPush,
      sourceMetadata: sourceMetadata ?? this.sourceMetadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      needsPush: needsPush ?? this.needsPush,
      coverEtag: coverEtag ?? this.coverEtag,
      needsProgressPush: needsProgressPush ?? this.needsProgressPush,
      status: status ?? this.status,
      rating: rating ?? this.rating,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      readCount: readCount ?? this.readCount,
      deletedAt: deletedAt ?? this.deletedAt,
      syncExcluded: syncExcluded ?? this.syncExcluded,
      addedBy: addedBy ?? this.addedBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (subtitle.present) {
      map['subtitle'] = Variable<String>(subtitle.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (isbn.present) {
      map['isbn'] = Variable<String>(isbn.value);
    }
    if (publisher.present) {
      map['publisher'] = Variable<String>(publisher.value);
    }
    if (publishedYear.present) {
      map['published_year'] = Variable<int>(publishedYear.value);
    }
    if (pageCount.present) {
      map['page_count'] = Variable<int>(pageCount.value);
    }
    if (coverPath.present) {
      map['cover_path'] = Variable<String>(coverPath.value);
    }
    if (spineStyle.present) {
      map['spine_style'] = Variable<String>(spineStyle.value);
    }
    if (seriesId.present) {
      map['series_id'] = Variable<String>(seriesId.value);
    }
    if (seriesIndex.present) {
      map['series_index'] = Variable<double>(seriesIndex.value);
    }
    if (readingProgress.present) {
      map['reading_progress'] = Variable<double>(readingProgress.value);
    }
    if (lastReadPage.present) {
      map['last_read_page'] = Variable<int>(lastReadPage.value);
    }
    if (lastReadAt.present) {
      map['last_read_at'] = Variable<DateTime>(lastReadAt.value);
    }
    if (readerNotes.present) {
      map['reader_notes'] = Variable<String>(readerNotes.value);
    }
    if (readerNotesUpdatedAt.present) {
      map['reader_notes_updated_at'] = Variable<DateTime>(
        readerNotesUpdatedAt.value,
      );
    }
    if (readerNotesNeedsPush.present) {
      map['reader_notes_needs_push'] = Variable<bool>(
        readerNotesNeedsPush.value,
      );
    }
    if (sourceMetadata.present) {
      map['source_metadata'] = Variable<String>(sourceMetadata.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (needsPush.present) {
      map['needs_push'] = Variable<bool>(needsPush.value);
    }
    if (coverEtag.present) {
      map['cover_etag'] = Variable<String>(coverEtag.value);
    }
    if (needsProgressPush.present) {
      map['needs_progress_push'] = Variable<bool>(needsProgressPush.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<DateTime>(finishedAt.value);
    }
    if (readCount.present) {
      map['read_count'] = Variable<int>(readCount.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (syncExcluded.present) {
      map['sync_excluded'] = Variable<bool>(syncExcluded.value);
    }
    if (addedBy.present) {
      map['added_by'] = Variable<String>(addedBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('subtitle: $subtitle, ')
          ..write('description: $description, ')
          ..write('isbn: $isbn, ')
          ..write('publisher: $publisher, ')
          ..write('publishedYear: $publishedYear, ')
          ..write('pageCount: $pageCount, ')
          ..write('coverPath: $coverPath, ')
          ..write('spineStyle: $spineStyle, ')
          ..write('seriesId: $seriesId, ')
          ..write('seriesIndex: $seriesIndex, ')
          ..write('readingProgress: $readingProgress, ')
          ..write('lastReadPage: $lastReadPage, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('readerNotes: $readerNotes, ')
          ..write('readerNotesUpdatedAt: $readerNotesUpdatedAt, ')
          ..write('readerNotesNeedsPush: $readerNotesNeedsPush, ')
          ..write('sourceMetadata: $sourceMetadata, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('needsPush: $needsPush, ')
          ..write('coverEtag: $coverEtag, ')
          ..write('needsProgressPush: $needsProgressPush, ')
          ..write('status: $status, ')
          ..write('rating: $rating, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('readCount: $readCount, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('syncExcluded: $syncExcluded, ')
          ..write('addedBy: $addedBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AuthorsTable extends Authors with TableInfo<$AuthorsTable, Author> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AuthorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'authors';
  @override
  VerificationContext validateIntegrity(
    Insertable<Author> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Author map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Author(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $AuthorsTable createAlias(String alias) {
    return $AuthorsTable(attachedDatabase, alias);
  }
}

class Author extends DataClass implements Insertable<Author> {
  final String id;
  final String name;
  const Author({required this.id, required this.name});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    return map;
  }

  AuthorsCompanion toCompanion(bool nullToAbsent) {
    return AuthorsCompanion(id: Value(id), name: Value(name));
  }

  factory Author.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Author(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
    };
  }

  Author copyWith({String? id, String? name}) =>
      Author(id: id ?? this.id, name: name ?? this.name);
  Author copyWithCompanion(AuthorsCompanion data) {
    return Author(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Author(')
          ..write('id: $id, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Author && other.id == this.id && other.name == this.name);
}

class AuthorsCompanion extends UpdateCompanion<Author> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> rowid;
  const AuthorsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AuthorsCompanion.insert({
    required String id,
    required String name,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Author> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AuthorsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? rowid,
  }) {
    return AuthorsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AuthorsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookAuthorsTable extends BookAuthors
    with TableInfo<$BookAuthorsTable, BookAuthor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookAuthorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id)',
    ),
  );
  static const VerificationMeta _authorIdMeta = const VerificationMeta(
    'authorId',
  );
  @override
  late final GeneratedColumn<String> authorId = GeneratedColumn<String>(
    'author_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES authors (id)',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [bookId, authorId, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_authors';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookAuthor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('author_id')) {
      context.handle(
        _authorIdMeta,
        authorId.isAcceptableOrUnknown(data['author_id']!, _authorIdMeta),
      );
    } else if (isInserting) {
      context.missing(_authorIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId, authorId};
  @override
  BookAuthor map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookAuthor(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      authorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}author_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $BookAuthorsTable createAlias(String alias) {
    return $BookAuthorsTable(attachedDatabase, alias);
  }
}

class BookAuthor extends DataClass implements Insertable<BookAuthor> {
  final String bookId;
  final String authorId;
  final int position;
  const BookAuthor({
    required this.bookId,
    required this.authorId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['author_id'] = Variable<String>(authorId);
    map['position'] = Variable<int>(position);
    return map;
  }

  BookAuthorsCompanion toCompanion(bool nullToAbsent) {
    return BookAuthorsCompanion(
      bookId: Value(bookId),
      authorId: Value(authorId),
      position: Value(position),
    );
  }

  factory BookAuthor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookAuthor(
      bookId: serializer.fromJson<String>(json['bookId']),
      authorId: serializer.fromJson<String>(json['authorId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'authorId': serializer.toJson<String>(authorId),
      'position': serializer.toJson<int>(position),
    };
  }

  BookAuthor copyWith({String? bookId, String? authorId, int? position}) =>
      BookAuthor(
        bookId: bookId ?? this.bookId,
        authorId: authorId ?? this.authorId,
        position: position ?? this.position,
      );
  BookAuthor copyWithCompanion(BookAuthorsCompanion data) {
    return BookAuthor(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      authorId: data.authorId.present ? data.authorId.value : this.authorId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookAuthor(')
          ..write('bookId: $bookId, ')
          ..write('authorId: $authorId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookId, authorId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookAuthor &&
          other.bookId == this.bookId &&
          other.authorId == this.authorId &&
          other.position == this.position);
}

class BookAuthorsCompanion extends UpdateCompanion<BookAuthor> {
  final Value<String> bookId;
  final Value<String> authorId;
  final Value<int> position;
  final Value<int> rowid;
  const BookAuthorsCompanion({
    this.bookId = const Value.absent(),
    this.authorId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookAuthorsCompanion.insert({
    required String bookId,
    required String authorId,
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       authorId = Value(authorId);
  static Insertable<BookAuthor> custom({
    Expression<String>? bookId,
    Expression<String>? authorId,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (authorId != null) 'author_id': authorId,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookAuthorsCompanion copyWith({
    Value<String>? bookId,
    Value<String>? authorId,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return BookAuthorsCompanion(
      bookId: bookId ?? this.bookId,
      authorId: authorId ?? this.authorId,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (authorId.present) {
      map['author_id'] = Variable<String>(authorId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookAuthorsCompanion(')
          ..write('bookId: $bookId, ')
          ..write('authorId: $authorId, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GenresTable extends Genres with TableInfo<$GenresTable, Genre> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GenresTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'genres';
  @override
  VerificationContext validateIntegrity(
    Insertable<Genre> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Genre map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Genre(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $GenresTable createAlias(String alias) {
    return $GenresTable(attachedDatabase, alias);
  }
}

class Genre extends DataClass implements Insertable<Genre> {
  final String id;
  final String name;
  const Genre({required this.id, required this.name});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    return map;
  }

  GenresCompanion toCompanion(bool nullToAbsent) {
    return GenresCompanion(id: Value(id), name: Value(name));
  }

  factory Genre.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Genre(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
    };
  }

  Genre copyWith({String? id, String? name}) =>
      Genre(id: id ?? this.id, name: name ?? this.name);
  Genre copyWithCompanion(GenresCompanion data) {
    return Genre(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Genre(')
          ..write('id: $id, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Genre && other.id == this.id && other.name == this.name);
}

class GenresCompanion extends UpdateCompanion<Genre> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> rowid;
  const GenresCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GenresCompanion.insert({
    required String id,
    required String name,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Genre> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GenresCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? rowid,
  }) {
    return GenresCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GenresCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookGenresTable extends BookGenres
    with TableInfo<$BookGenresTable, BookGenre> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookGenresTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id)',
    ),
  );
  static const VerificationMeta _genreIdMeta = const VerificationMeta(
    'genreId',
  );
  @override
  late final GeneratedColumn<String> genreId = GeneratedColumn<String>(
    'genre_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES genres (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [bookId, genreId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_genres';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookGenre> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('genre_id')) {
      context.handle(
        _genreIdMeta,
        genreId.isAcceptableOrUnknown(data['genre_id']!, _genreIdMeta),
      );
    } else if (isInserting) {
      context.missing(_genreIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId, genreId};
  @override
  BookGenre map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookGenre(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      genreId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}genre_id'],
      )!,
    );
  }

  @override
  $BookGenresTable createAlias(String alias) {
    return $BookGenresTable(attachedDatabase, alias);
  }
}

class BookGenre extends DataClass implements Insertable<BookGenre> {
  final String bookId;
  final String genreId;
  const BookGenre({required this.bookId, required this.genreId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['genre_id'] = Variable<String>(genreId);
    return map;
  }

  BookGenresCompanion toCompanion(bool nullToAbsent) {
    return BookGenresCompanion(bookId: Value(bookId), genreId: Value(genreId));
  }

  factory BookGenre.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookGenre(
      bookId: serializer.fromJson<String>(json['bookId']),
      genreId: serializer.fromJson<String>(json['genreId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'genreId': serializer.toJson<String>(genreId),
    };
  }

  BookGenre copyWith({String? bookId, String? genreId}) => BookGenre(
    bookId: bookId ?? this.bookId,
    genreId: genreId ?? this.genreId,
  );
  BookGenre copyWithCompanion(BookGenresCompanion data) {
    return BookGenre(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      genreId: data.genreId.present ? data.genreId.value : this.genreId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookGenre(')
          ..write('bookId: $bookId, ')
          ..write('genreId: $genreId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookId, genreId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookGenre &&
          other.bookId == this.bookId &&
          other.genreId == this.genreId);
}

class BookGenresCompanion extends UpdateCompanion<BookGenre> {
  final Value<String> bookId;
  final Value<String> genreId;
  final Value<int> rowid;
  const BookGenresCompanion({
    this.bookId = const Value.absent(),
    this.genreId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookGenresCompanion.insert({
    required String bookId,
    required String genreId,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       genreId = Value(genreId);
  static Insertable<BookGenre> custom({
    Expression<String>? bookId,
    Expression<String>? genreId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (genreId != null) 'genre_id': genreId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookGenresCompanion copyWith({
    Value<String>? bookId,
    Value<String>? genreId,
    Value<int>? rowid,
  }) {
    return BookGenresCompanion(
      bookId: bookId ?? this.bookId,
      genreId: genreId ?? this.genreId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (genreId.present) {
      map['genre_id'] = Variable<String>(genreId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookGenresCompanion(')
          ..write('bookId: $bookId, ')
          ..write('genreId: $genreId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookFilesTable extends BookFiles
    with TableInfo<$BookFilesTable, BookFile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookFilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id)',
    ),
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeBytesMeta = const VerificationMeta(
    'sizeBytes',
  );
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
    'size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sha256Meta = const VerificationMeta('sha256');
  @override
  late final GeneratedColumn<String> sha256 = GeneratedColumn<String>(
    'sha256',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    format,
    path,
    sizeBytes,
    sha256,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_files';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookFile> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    } else if (isInserting) {
      context.missing(_formatMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('size_bytes')) {
      context.handle(
        _sizeBytesMeta,
        sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('sha256')) {
      context.handle(
        _sha256Meta,
        sha256.isAcceptableOrUnknown(data['sha256']!, _sha256Meta),
      );
    } else if (isInserting) {
      context.missing(_sha256Meta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookFile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookFile(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      sizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size_bytes'],
      )!,
      sha256: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sha256'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $BookFilesTable createAlias(String alias) {
    return $BookFilesTable(attachedDatabase, alias);
  }
}

class BookFile extends DataClass implements Insertable<BookFile> {
  final String id;
  final String bookId;
  final String format;
  final String path;
  final int sizeBytes;
  final String sha256;
  final DateTime addedAt;
  const BookFile({
    required this.id,
    required this.bookId,
    required this.format,
    required this.path,
    required this.sizeBytes,
    required this.sha256,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['format'] = Variable<String>(format);
    map['path'] = Variable<String>(path);
    map['size_bytes'] = Variable<int>(sizeBytes);
    map['sha256'] = Variable<String>(sha256);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  BookFilesCompanion toCompanion(bool nullToAbsent) {
    return BookFilesCompanion(
      id: Value(id),
      bookId: Value(bookId),
      format: Value(format),
      path: Value(path),
      sizeBytes: Value(sizeBytes),
      sha256: Value(sha256),
      addedAt: Value(addedAt),
    );
  }

  factory BookFile.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookFile(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      format: serializer.fromJson<String>(json['format']),
      path: serializer.fromJson<String>(json['path']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      sha256: serializer.fromJson<String>(json['sha256']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'format': serializer.toJson<String>(format),
      'path': serializer.toJson<String>(path),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'sha256': serializer.toJson<String>(sha256),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  BookFile copyWith({
    String? id,
    String? bookId,
    String? format,
    String? path,
    int? sizeBytes,
    String? sha256,
    DateTime? addedAt,
  }) => BookFile(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    format: format ?? this.format,
    path: path ?? this.path,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    sha256: sha256 ?? this.sha256,
    addedAt: addedAt ?? this.addedAt,
  );
  BookFile copyWithCompanion(BookFilesCompanion data) {
    return BookFile(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      format: data.format.present ? data.format.value : this.format,
      path: data.path.present ? data.path.value : this.path,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      sha256: data.sha256.present ? data.sha256.value : this.sha256,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookFile(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('format: $format, ')
          ..write('path: $path, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('sha256: $sha256, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, bookId, format, path, sizeBytes, sha256, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookFile &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.format == this.format &&
          other.path == this.path &&
          other.sizeBytes == this.sizeBytes &&
          other.sha256 == this.sha256 &&
          other.addedAt == this.addedAt);
}

class BookFilesCompanion extends UpdateCompanion<BookFile> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String> format;
  final Value<String> path;
  final Value<int> sizeBytes;
  final Value<String> sha256;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const BookFilesCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.format = const Value.absent(),
    this.path = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.sha256 = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookFilesCompanion.insert({
    required String id,
    required String bookId,
    required String format,
    required String path,
    required int sizeBytes,
    required String sha256,
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId),
       format = Value(format),
       path = Value(path),
       sizeBytes = Value(sizeBytes),
       sha256 = Value(sha256);
  static Insertable<BookFile> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? format,
    Expression<String>? path,
    Expression<int>? sizeBytes,
    Expression<String>? sha256,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (format != null) 'format': format,
      if (path != null) 'path': path,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (sha256 != null) 'sha256': sha256,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookFilesCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<String>? format,
    Value<String>? path,
    Value<int>? sizeBytes,
    Value<String>? sha256,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return BookFilesCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      format: format ?? this.format,
      path: path ?? this.path,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (sha256.present) {
      map['sha256'] = Variable<String>(sha256.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookFilesCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('format: $format, ')
          ..write('path: $path, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('sha256: $sha256, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PhysicalCopiesTable extends PhysicalCopies
    with TableInfo<$PhysicalCopiesTable, PhysicalCopy> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PhysicalCopiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id)',
    ),
  );
  static const VerificationMeta _locationMeta = const VerificationMeta(
    'location',
  );
  @override
  late final GeneratedColumn<String> location = GeneratedColumn<String>(
    'location',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _conditionMeta = const VerificationMeta(
    'condition',
  );
  @override
  late final GeneratedColumn<String> condition = GeneratedColumn<String>(
    'condition',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _needsPushMeta = const VerificationMeta(
    'needsPush',
  );
  @override
  late final GeneratedColumn<bool> needsPush = GeneratedColumn<bool>(
    'needs_push',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_push" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    location,
    condition,
    notes,
    updatedAt,
    needsPush,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'physical_copies';
  @override
  VerificationContext validateIntegrity(
    Insertable<PhysicalCopy> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('location')) {
      context.handle(
        _locationMeta,
        location.isAcceptableOrUnknown(data['location']!, _locationMeta),
      );
    }
    if (data.containsKey('condition')) {
      context.handle(
        _conditionMeta,
        condition.isAcceptableOrUnknown(data['condition']!, _conditionMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('needs_push')) {
      context.handle(
        _needsPushMeta,
        needsPush.isAcceptableOrUnknown(data['needs_push']!, _needsPushMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PhysicalCopy map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PhysicalCopy(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      location: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location'],
      ),
      condition: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}condition'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      needsPush: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_push'],
      )!,
    );
  }

  @override
  $PhysicalCopiesTable createAlias(String alias) {
    return $PhysicalCopiesTable(attachedDatabase, alias);
  }
}

class PhysicalCopy extends DataClass implements Insertable<PhysicalCopy> {
  final String id;
  final String bookId;
  final String? location;
  final String? condition;
  final String? notes;
  final DateTime updatedAt;
  final bool needsPush;
  const PhysicalCopy({
    required this.id,
    required this.bookId,
    this.location,
    this.condition,
    this.notes,
    required this.updatedAt,
    required this.needsPush,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    if (!nullToAbsent || location != null) {
      map['location'] = Variable<String>(location);
    }
    if (!nullToAbsent || condition != null) {
      map['condition'] = Variable<String>(condition);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['needs_push'] = Variable<bool>(needsPush);
    return map;
  }

  PhysicalCopiesCompanion toCompanion(bool nullToAbsent) {
    return PhysicalCopiesCompanion(
      id: Value(id),
      bookId: Value(bookId),
      location: location == null && nullToAbsent
          ? const Value.absent()
          : Value(location),
      condition: condition == null && nullToAbsent
          ? const Value.absent()
          : Value(condition),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      updatedAt: Value(updatedAt),
      needsPush: Value(needsPush),
    );
  }

  factory PhysicalCopy.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PhysicalCopy(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      location: serializer.fromJson<String?>(json['location']),
      condition: serializer.fromJson<String?>(json['condition']),
      notes: serializer.fromJson<String?>(json['notes']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      needsPush: serializer.fromJson<bool>(json['needsPush']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'location': serializer.toJson<String?>(location),
      'condition': serializer.toJson<String?>(condition),
      'notes': serializer.toJson<String?>(notes),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'needsPush': serializer.toJson<bool>(needsPush),
    };
  }

  PhysicalCopy copyWith({
    String? id,
    String? bookId,
    Value<String?> location = const Value.absent(),
    Value<String?> condition = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    DateTime? updatedAt,
    bool? needsPush,
  }) => PhysicalCopy(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    location: location.present ? location.value : this.location,
    condition: condition.present ? condition.value : this.condition,
    notes: notes.present ? notes.value : this.notes,
    updatedAt: updatedAt ?? this.updatedAt,
    needsPush: needsPush ?? this.needsPush,
  );
  PhysicalCopy copyWithCompanion(PhysicalCopiesCompanion data) {
    return PhysicalCopy(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      location: data.location.present ? data.location.value : this.location,
      condition: data.condition.present ? data.condition.value : this.condition,
      notes: data.notes.present ? data.notes.value : this.notes,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      needsPush: data.needsPush.present ? data.needsPush.value : this.needsPush,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PhysicalCopy(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('location: $location, ')
          ..write('condition: $condition, ')
          ..write('notes: $notes, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('needsPush: $needsPush')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, bookId, location, condition, notes, updatedAt, needsPush);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PhysicalCopy &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.location == this.location &&
          other.condition == this.condition &&
          other.notes == this.notes &&
          other.updatedAt == this.updatedAt &&
          other.needsPush == this.needsPush);
}

class PhysicalCopiesCompanion extends UpdateCompanion<PhysicalCopy> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String?> location;
  final Value<String?> condition;
  final Value<String?> notes;
  final Value<DateTime> updatedAt;
  final Value<bool> needsPush;
  final Value<int> rowid;
  const PhysicalCopiesCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.location = const Value.absent(),
    this.condition = const Value.absent(),
    this.notes = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PhysicalCopiesCompanion.insert({
    required String id,
    required String bookId,
    this.location = const Value.absent(),
    this.condition = const Value.absent(),
    this.notes = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId);
  static Insertable<PhysicalCopy> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? location,
    Expression<String>? condition,
    Expression<String>? notes,
    Expression<DateTime>? updatedAt,
    Expression<bool>? needsPush,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (location != null) 'location': location,
      if (condition != null) 'condition': condition,
      if (notes != null) 'notes': notes,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (needsPush != null) 'needs_push': needsPush,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PhysicalCopiesCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<String?>? location,
    Value<String?>? condition,
    Value<String?>? notes,
    Value<DateTime>? updatedAt,
    Value<bool>? needsPush,
    Value<int>? rowid,
  }) {
    return PhysicalCopiesCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      location: location ?? this.location,
      condition: condition ?? this.condition,
      notes: notes ?? this.notes,
      updatedAt: updatedAt ?? this.updatedAt,
      needsPush: needsPush ?? this.needsPush,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (location.present) {
      map['location'] = Variable<String>(location.value);
    }
    if (condition.present) {
      map['condition'] = Variable<String>(condition.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (needsPush.present) {
      map['needs_push'] = Variable<bool>(needsPush.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PhysicalCopiesCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('location: $location, ')
          ..write('condition: $condition, ')
          ..write('notes: $notes, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('needsPush: $needsPush, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LoansTable extends Loans with TableInfo<$LoansTable, Loan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LoansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _copyIdMeta = const VerificationMeta('copyId');
  @override
  late final GeneratedColumn<String> copyId = GeneratedColumn<String>(
    'copy_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES physical_copies (id)',
    ),
  );
  static const VerificationMeta _borrowerMeta = const VerificationMeta(
    'borrower',
  );
  @override
  late final GeneratedColumn<String> borrower = GeneratedColumn<String>(
    'borrower',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _loanedAtMeta = const VerificationMeta(
    'loanedAt',
  );
  @override
  late final GeneratedColumn<DateTime> loanedAt = GeneratedColumn<DateTime>(
    'loaned_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _returnedAtMeta = const VerificationMeta(
    'returnedAt',
  );
  @override
  late final GeneratedColumn<DateTime> returnedAt = GeneratedColumn<DateTime>(
    'returned_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _needsPushMeta = const VerificationMeta(
    'needsPush',
  );
  @override
  late final GeneratedColumn<bool> needsPush = GeneratedColumn<bool>(
    'needs_push',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_push" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _dueAtMeta = const VerificationMeta('dueAt');
  @override
  late final GeneratedColumn<DateTime> dueAt = GeneratedColumn<DateTime>(
    'due_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _borrowerContactMeta = const VerificationMeta(
    'borrowerContact',
  );
  @override
  late final GeneratedColumn<String> borrowerContact = GeneratedColumn<String>(
    'borrower_contact',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reminderSentAtMeta = const VerificationMeta(
    'reminderSentAt',
  );
  @override
  late final GeneratedColumn<DateTime> reminderSentAt =
      GeneratedColumn<DateTime>(
        'reminder_sent_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    copyId,
    borrower,
    loanedAt,
    returnedAt,
    updatedAt,
    needsPush,
    dueAt,
    borrowerContact,
    notes,
    reminderSentAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'loans';
  @override
  VerificationContext validateIntegrity(
    Insertable<Loan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('copy_id')) {
      context.handle(
        _copyIdMeta,
        copyId.isAcceptableOrUnknown(data['copy_id']!, _copyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_copyIdMeta);
    }
    if (data.containsKey('borrower')) {
      context.handle(
        _borrowerMeta,
        borrower.isAcceptableOrUnknown(data['borrower']!, _borrowerMeta),
      );
    } else if (isInserting) {
      context.missing(_borrowerMeta);
    }
    if (data.containsKey('loaned_at')) {
      context.handle(
        _loanedAtMeta,
        loanedAt.isAcceptableOrUnknown(data['loaned_at']!, _loanedAtMeta),
      );
    }
    if (data.containsKey('returned_at')) {
      context.handle(
        _returnedAtMeta,
        returnedAt.isAcceptableOrUnknown(data['returned_at']!, _returnedAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('needs_push')) {
      context.handle(
        _needsPushMeta,
        needsPush.isAcceptableOrUnknown(data['needs_push']!, _needsPushMeta),
      );
    }
    if (data.containsKey('due_at')) {
      context.handle(
        _dueAtMeta,
        dueAt.isAcceptableOrUnknown(data['due_at']!, _dueAtMeta),
      );
    }
    if (data.containsKey('borrower_contact')) {
      context.handle(
        _borrowerContactMeta,
        borrowerContact.isAcceptableOrUnknown(
          data['borrower_contact']!,
          _borrowerContactMeta,
        ),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('reminder_sent_at')) {
      context.handle(
        _reminderSentAtMeta,
        reminderSentAt.isAcceptableOrUnknown(
          data['reminder_sent_at']!,
          _reminderSentAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Loan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Loan(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      copyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}copy_id'],
      )!,
      borrower: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}borrower'],
      )!,
      loanedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}loaned_at'],
      )!,
      returnedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}returned_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      needsPush: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_push'],
      )!,
      dueAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_at'],
      ),
      borrowerContact: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}borrower_contact'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
      reminderSentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}reminder_sent_at'],
      ),
    );
  }

  @override
  $LoansTable createAlias(String alias) {
    return $LoansTable(attachedDatabase, alias);
  }
}

class Loan extends DataClass implements Insertable<Loan> {
  final String id;
  final String copyId;
  final String borrower;
  final DateTime loanedAt;
  final DateTime? returnedAt;
  final DateTime updatedAt;
  final bool needsPush;
  final DateTime? dueAt;

  /// Free text — a phone number, an email, "Ana from book club".
  final String? borrowerContact;
  final String? notes;

  /// When a due reminder was last raised, so it isn't raised twice.
  final DateTime? reminderSentAt;
  const Loan({
    required this.id,
    required this.copyId,
    required this.borrower,
    required this.loanedAt,
    this.returnedAt,
    required this.updatedAt,
    required this.needsPush,
    this.dueAt,
    this.borrowerContact,
    this.notes,
    this.reminderSentAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['copy_id'] = Variable<String>(copyId);
    map['borrower'] = Variable<String>(borrower);
    map['loaned_at'] = Variable<DateTime>(loanedAt);
    if (!nullToAbsent || returnedAt != null) {
      map['returned_at'] = Variable<DateTime>(returnedAt);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['needs_push'] = Variable<bool>(needsPush);
    if (!nullToAbsent || dueAt != null) {
      map['due_at'] = Variable<DateTime>(dueAt);
    }
    if (!nullToAbsent || borrowerContact != null) {
      map['borrower_contact'] = Variable<String>(borrowerContact);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    if (!nullToAbsent || reminderSentAt != null) {
      map['reminder_sent_at'] = Variable<DateTime>(reminderSentAt);
    }
    return map;
  }

  LoansCompanion toCompanion(bool nullToAbsent) {
    return LoansCompanion(
      id: Value(id),
      copyId: Value(copyId),
      borrower: Value(borrower),
      loanedAt: Value(loanedAt),
      returnedAt: returnedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(returnedAt),
      updatedAt: Value(updatedAt),
      needsPush: Value(needsPush),
      dueAt: dueAt == null && nullToAbsent
          ? const Value.absent()
          : Value(dueAt),
      borrowerContact: borrowerContact == null && nullToAbsent
          ? const Value.absent()
          : Value(borrowerContact),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
      reminderSentAt: reminderSentAt == null && nullToAbsent
          ? const Value.absent()
          : Value(reminderSentAt),
    );
  }

  factory Loan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Loan(
      id: serializer.fromJson<String>(json['id']),
      copyId: serializer.fromJson<String>(json['copyId']),
      borrower: serializer.fromJson<String>(json['borrower']),
      loanedAt: serializer.fromJson<DateTime>(json['loanedAt']),
      returnedAt: serializer.fromJson<DateTime?>(json['returnedAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      needsPush: serializer.fromJson<bool>(json['needsPush']),
      dueAt: serializer.fromJson<DateTime?>(json['dueAt']),
      borrowerContact: serializer.fromJson<String?>(json['borrowerContact']),
      notes: serializer.fromJson<String?>(json['notes']),
      reminderSentAt: serializer.fromJson<DateTime?>(json['reminderSentAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'copyId': serializer.toJson<String>(copyId),
      'borrower': serializer.toJson<String>(borrower),
      'loanedAt': serializer.toJson<DateTime>(loanedAt),
      'returnedAt': serializer.toJson<DateTime?>(returnedAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'needsPush': serializer.toJson<bool>(needsPush),
      'dueAt': serializer.toJson<DateTime?>(dueAt),
      'borrowerContact': serializer.toJson<String?>(borrowerContact),
      'notes': serializer.toJson<String?>(notes),
      'reminderSentAt': serializer.toJson<DateTime?>(reminderSentAt),
    };
  }

  Loan copyWith({
    String? id,
    String? copyId,
    String? borrower,
    DateTime? loanedAt,
    Value<DateTime?> returnedAt = const Value.absent(),
    DateTime? updatedAt,
    bool? needsPush,
    Value<DateTime?> dueAt = const Value.absent(),
    Value<String?> borrowerContact = const Value.absent(),
    Value<String?> notes = const Value.absent(),
    Value<DateTime?> reminderSentAt = const Value.absent(),
  }) => Loan(
    id: id ?? this.id,
    copyId: copyId ?? this.copyId,
    borrower: borrower ?? this.borrower,
    loanedAt: loanedAt ?? this.loanedAt,
    returnedAt: returnedAt.present ? returnedAt.value : this.returnedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    needsPush: needsPush ?? this.needsPush,
    dueAt: dueAt.present ? dueAt.value : this.dueAt,
    borrowerContact: borrowerContact.present
        ? borrowerContact.value
        : this.borrowerContact,
    notes: notes.present ? notes.value : this.notes,
    reminderSentAt: reminderSentAt.present
        ? reminderSentAt.value
        : this.reminderSentAt,
  );
  Loan copyWithCompanion(LoansCompanion data) {
    return Loan(
      id: data.id.present ? data.id.value : this.id,
      copyId: data.copyId.present ? data.copyId.value : this.copyId,
      borrower: data.borrower.present ? data.borrower.value : this.borrower,
      loanedAt: data.loanedAt.present ? data.loanedAt.value : this.loanedAt,
      returnedAt: data.returnedAt.present
          ? data.returnedAt.value
          : this.returnedAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      needsPush: data.needsPush.present ? data.needsPush.value : this.needsPush,
      dueAt: data.dueAt.present ? data.dueAt.value : this.dueAt,
      borrowerContact: data.borrowerContact.present
          ? data.borrowerContact.value
          : this.borrowerContact,
      notes: data.notes.present ? data.notes.value : this.notes,
      reminderSentAt: data.reminderSentAt.present
          ? data.reminderSentAt.value
          : this.reminderSentAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Loan(')
          ..write('id: $id, ')
          ..write('copyId: $copyId, ')
          ..write('borrower: $borrower, ')
          ..write('loanedAt: $loanedAt, ')
          ..write('returnedAt: $returnedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('needsPush: $needsPush, ')
          ..write('dueAt: $dueAt, ')
          ..write('borrowerContact: $borrowerContact, ')
          ..write('notes: $notes, ')
          ..write('reminderSentAt: $reminderSentAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    copyId,
    borrower,
    loanedAt,
    returnedAt,
    updatedAt,
    needsPush,
    dueAt,
    borrowerContact,
    notes,
    reminderSentAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Loan &&
          other.id == this.id &&
          other.copyId == this.copyId &&
          other.borrower == this.borrower &&
          other.loanedAt == this.loanedAt &&
          other.returnedAt == this.returnedAt &&
          other.updatedAt == this.updatedAt &&
          other.needsPush == this.needsPush &&
          other.dueAt == this.dueAt &&
          other.borrowerContact == this.borrowerContact &&
          other.notes == this.notes &&
          other.reminderSentAt == this.reminderSentAt);
}

class LoansCompanion extends UpdateCompanion<Loan> {
  final Value<String> id;
  final Value<String> copyId;
  final Value<String> borrower;
  final Value<DateTime> loanedAt;
  final Value<DateTime?> returnedAt;
  final Value<DateTime> updatedAt;
  final Value<bool> needsPush;
  final Value<DateTime?> dueAt;
  final Value<String?> borrowerContact;
  final Value<String?> notes;
  final Value<DateTime?> reminderSentAt;
  final Value<int> rowid;
  const LoansCompanion({
    this.id = const Value.absent(),
    this.copyId = const Value.absent(),
    this.borrower = const Value.absent(),
    this.loanedAt = const Value.absent(),
    this.returnedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.borrowerContact = const Value.absent(),
    this.notes = const Value.absent(),
    this.reminderSentAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LoansCompanion.insert({
    required String id,
    required String copyId,
    required String borrower,
    this.loanedAt = const Value.absent(),
    this.returnedAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.dueAt = const Value.absent(),
    this.borrowerContact = const Value.absent(),
    this.notes = const Value.absent(),
    this.reminderSentAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       copyId = Value(copyId),
       borrower = Value(borrower);
  static Insertable<Loan> custom({
    Expression<String>? id,
    Expression<String>? copyId,
    Expression<String>? borrower,
    Expression<DateTime>? loanedAt,
    Expression<DateTime>? returnedAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? needsPush,
    Expression<DateTime>? dueAt,
    Expression<String>? borrowerContact,
    Expression<String>? notes,
    Expression<DateTime>? reminderSentAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (copyId != null) 'copy_id': copyId,
      if (borrower != null) 'borrower': borrower,
      if (loanedAt != null) 'loaned_at': loanedAt,
      if (returnedAt != null) 'returned_at': returnedAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (needsPush != null) 'needs_push': needsPush,
      if (dueAt != null) 'due_at': dueAt,
      if (borrowerContact != null) 'borrower_contact': borrowerContact,
      if (notes != null) 'notes': notes,
      if (reminderSentAt != null) 'reminder_sent_at': reminderSentAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LoansCompanion copyWith({
    Value<String>? id,
    Value<String>? copyId,
    Value<String>? borrower,
    Value<DateTime>? loanedAt,
    Value<DateTime?>? returnedAt,
    Value<DateTime>? updatedAt,
    Value<bool>? needsPush,
    Value<DateTime?>? dueAt,
    Value<String?>? borrowerContact,
    Value<String?>? notes,
    Value<DateTime?>? reminderSentAt,
    Value<int>? rowid,
  }) {
    return LoansCompanion(
      id: id ?? this.id,
      copyId: copyId ?? this.copyId,
      borrower: borrower ?? this.borrower,
      loanedAt: loanedAt ?? this.loanedAt,
      returnedAt: returnedAt ?? this.returnedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      needsPush: needsPush ?? this.needsPush,
      dueAt: dueAt ?? this.dueAt,
      borrowerContact: borrowerContact ?? this.borrowerContact,
      notes: notes ?? this.notes,
      reminderSentAt: reminderSentAt ?? this.reminderSentAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (copyId.present) {
      map['copy_id'] = Variable<String>(copyId.value);
    }
    if (borrower.present) {
      map['borrower'] = Variable<String>(borrower.value);
    }
    if (loanedAt.present) {
      map['loaned_at'] = Variable<DateTime>(loanedAt.value);
    }
    if (returnedAt.present) {
      map['returned_at'] = Variable<DateTime>(returnedAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (needsPush.present) {
      map['needs_push'] = Variable<bool>(needsPush.value);
    }
    if (dueAt.present) {
      map['due_at'] = Variable<DateTime>(dueAt.value);
    }
    if (borrowerContact.present) {
      map['borrower_contact'] = Variable<String>(borrowerContact.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (reminderSentAt.present) {
      map['reminder_sent_at'] = Variable<DateTime>(reminderSentAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LoansCompanion(')
          ..write('id: $id, ')
          ..write('copyId: $copyId, ')
          ..write('borrower: $borrower, ')
          ..write('loanedAt: $loanedAt, ')
          ..write('returnedAt: $returnedAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('needsPush: $needsPush, ')
          ..write('dueAt: $dueAt, ')
          ..write('borrowerContact: $borrowerContact, ')
          ..write('notes: $notes, ')
          ..write('reminderSentAt: $reminderSentAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CopyPhotosTable extends CopyPhotos
    with TableInfo<$CopyPhotosTable, CopyPhoto> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CopyPhotosTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _copyIdMeta = const VerificationMeta('copyId');
  @override
  late final GeneratedColumn<String> copyId = GeneratedColumn<String>(
    'copy_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES physical_copies (id)',
    ),
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _takenAtMeta = const VerificationMeta(
    'takenAt',
  );
  @override
  late final GeneratedColumn<DateTime> takenAt = GeneratedColumn<DateTime>(
    'taken_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _captionMeta = const VerificationMeta(
    'caption',
  );
  @override
  late final GeneratedColumn<String> caption = GeneratedColumn<String>(
    'caption',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _needsPushMeta = const VerificationMeta(
    'needsPush',
  );
  @override
  late final GeneratedColumn<bool> needsPush = GeneratedColumn<bool>(
    'needs_push',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_push" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    copyId,
    path,
    takenAt,
    caption,
    updatedAt,
    needsPush,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'copy_photos';
  @override
  VerificationContext validateIntegrity(
    Insertable<CopyPhoto> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('copy_id')) {
      context.handle(
        _copyIdMeta,
        copyId.isAcceptableOrUnknown(data['copy_id']!, _copyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_copyIdMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('taken_at')) {
      context.handle(
        _takenAtMeta,
        takenAt.isAcceptableOrUnknown(data['taken_at']!, _takenAtMeta),
      );
    }
    if (data.containsKey('caption')) {
      context.handle(
        _captionMeta,
        caption.isAcceptableOrUnknown(data['caption']!, _captionMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('needs_push')) {
      context.handle(
        _needsPushMeta,
        needsPush.isAcceptableOrUnknown(data['needs_push']!, _needsPushMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CopyPhoto map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CopyPhoto(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      copyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}copy_id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      takenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}taken_at'],
      )!,
      caption: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}caption'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      needsPush: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_push'],
      )!,
    );
  }

  @override
  $CopyPhotosTable createAlias(String alias) {
    return $CopyPhotosTable(attachedDatabase, alias);
  }
}

class CopyPhoto extends DataClass implements Insertable<CopyPhoto> {
  final String id;
  final String copyId;

  /// Relative to the data dir, like `BookFiles.path` — `photos/<id>.jpg`.
  final String path;
  final DateTime takenAt;
  final String? caption;
  final DateTime updatedAt;
  final bool needsPush;
  const CopyPhoto({
    required this.id,
    required this.copyId,
    required this.path,
    required this.takenAt,
    this.caption,
    required this.updatedAt,
    required this.needsPush,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['copy_id'] = Variable<String>(copyId);
    map['path'] = Variable<String>(path);
    map['taken_at'] = Variable<DateTime>(takenAt);
    if (!nullToAbsent || caption != null) {
      map['caption'] = Variable<String>(caption);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['needs_push'] = Variable<bool>(needsPush);
    return map;
  }

  CopyPhotosCompanion toCompanion(bool nullToAbsent) {
    return CopyPhotosCompanion(
      id: Value(id),
      copyId: Value(copyId),
      path: Value(path),
      takenAt: Value(takenAt),
      caption: caption == null && nullToAbsent
          ? const Value.absent()
          : Value(caption),
      updatedAt: Value(updatedAt),
      needsPush: Value(needsPush),
    );
  }

  factory CopyPhoto.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CopyPhoto(
      id: serializer.fromJson<String>(json['id']),
      copyId: serializer.fromJson<String>(json['copyId']),
      path: serializer.fromJson<String>(json['path']),
      takenAt: serializer.fromJson<DateTime>(json['takenAt']),
      caption: serializer.fromJson<String?>(json['caption']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      needsPush: serializer.fromJson<bool>(json['needsPush']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'copyId': serializer.toJson<String>(copyId),
      'path': serializer.toJson<String>(path),
      'takenAt': serializer.toJson<DateTime>(takenAt),
      'caption': serializer.toJson<String?>(caption),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'needsPush': serializer.toJson<bool>(needsPush),
    };
  }

  CopyPhoto copyWith({
    String? id,
    String? copyId,
    String? path,
    DateTime? takenAt,
    Value<String?> caption = const Value.absent(),
    DateTime? updatedAt,
    bool? needsPush,
  }) => CopyPhoto(
    id: id ?? this.id,
    copyId: copyId ?? this.copyId,
    path: path ?? this.path,
    takenAt: takenAt ?? this.takenAt,
    caption: caption.present ? caption.value : this.caption,
    updatedAt: updatedAt ?? this.updatedAt,
    needsPush: needsPush ?? this.needsPush,
  );
  CopyPhoto copyWithCompanion(CopyPhotosCompanion data) {
    return CopyPhoto(
      id: data.id.present ? data.id.value : this.id,
      copyId: data.copyId.present ? data.copyId.value : this.copyId,
      path: data.path.present ? data.path.value : this.path,
      takenAt: data.takenAt.present ? data.takenAt.value : this.takenAt,
      caption: data.caption.present ? data.caption.value : this.caption,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      needsPush: data.needsPush.present ? data.needsPush.value : this.needsPush,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CopyPhoto(')
          ..write('id: $id, ')
          ..write('copyId: $copyId, ')
          ..write('path: $path, ')
          ..write('takenAt: $takenAt, ')
          ..write('caption: $caption, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('needsPush: $needsPush')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, copyId, path, takenAt, caption, updatedAt, needsPush);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CopyPhoto &&
          other.id == this.id &&
          other.copyId == this.copyId &&
          other.path == this.path &&
          other.takenAt == this.takenAt &&
          other.caption == this.caption &&
          other.updatedAt == this.updatedAt &&
          other.needsPush == this.needsPush);
}

class CopyPhotosCompanion extends UpdateCompanion<CopyPhoto> {
  final Value<String> id;
  final Value<String> copyId;
  final Value<String> path;
  final Value<DateTime> takenAt;
  final Value<String?> caption;
  final Value<DateTime> updatedAt;
  final Value<bool> needsPush;
  final Value<int> rowid;
  const CopyPhotosCompanion({
    this.id = const Value.absent(),
    this.copyId = const Value.absent(),
    this.path = const Value.absent(),
    this.takenAt = const Value.absent(),
    this.caption = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CopyPhotosCompanion.insert({
    required String id,
    required String copyId,
    required String path,
    this.takenAt = const Value.absent(),
    this.caption = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       copyId = Value(copyId),
       path = Value(path);
  static Insertable<CopyPhoto> custom({
    Expression<String>? id,
    Expression<String>? copyId,
    Expression<String>? path,
    Expression<DateTime>? takenAt,
    Expression<String>? caption,
    Expression<DateTime>? updatedAt,
    Expression<bool>? needsPush,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (copyId != null) 'copy_id': copyId,
      if (path != null) 'path': path,
      if (takenAt != null) 'taken_at': takenAt,
      if (caption != null) 'caption': caption,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (needsPush != null) 'needs_push': needsPush,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CopyPhotosCompanion copyWith({
    Value<String>? id,
    Value<String>? copyId,
    Value<String>? path,
    Value<DateTime>? takenAt,
    Value<String?>? caption,
    Value<DateTime>? updatedAt,
    Value<bool>? needsPush,
    Value<int>? rowid,
  }) {
    return CopyPhotosCompanion(
      id: id ?? this.id,
      copyId: copyId ?? this.copyId,
      path: path ?? this.path,
      takenAt: takenAt ?? this.takenAt,
      caption: caption ?? this.caption,
      updatedAt: updatedAt ?? this.updatedAt,
      needsPush: needsPush ?? this.needsPush,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (copyId.present) {
      map['copy_id'] = Variable<String>(copyId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (takenAt.present) {
      map['taken_at'] = Variable<DateTime>(takenAt.value);
    }
    if (caption.present) {
      map['caption'] = Variable<String>(caption.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (needsPush.present) {
      map['needs_push'] = Variable<bool>(needsPush.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CopyPhotosCompanion(')
          ..write('id: $id, ')
          ..write('copyId: $copyId, ')
          ..write('path: $path, ')
          ..write('takenAt: $takenAt, ')
          ..write('caption: $caption, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('needsPush: $needsPush, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShelvesTable extends Shelves with TableInfo<$ShelvesTable, Shelf> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShelvesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _isPersonalMeta = const VerificationMeta(
    'isPersonal',
  );
  @override
  late final GeneratedColumn<bool> isPersonal = GeneratedColumn<bool>(
    'is_personal',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_personal" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _ownerIdMeta = const VerificationMeta(
    'ownerId',
  );
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
    'owner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acceptedMeta = const VerificationMeta(
    'accepted',
  );
  @override
  late final GeneratedColumn<bool> accepted = GeneratedColumn<bool>(
    'accepted',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("accepted" IN (0, 1))',
    ),
  );
  static const VerificationMeta _needsPushMeta = const VerificationMeta(
    'needsPush',
  );
  @override
  late final GeneratedColumn<bool> needsPush = GeneratedColumn<bool>(
    'needs_push',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_push" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    sortOrder,
    updatedAt,
    isPersonal,
    ownerId,
    accepted,
    needsPush,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shelves';
  @override
  VerificationContext validateIntegrity(
    Insertable<Shelf> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('is_personal')) {
      context.handle(
        _isPersonalMeta,
        isPersonal.isAcceptableOrUnknown(data['is_personal']!, _isPersonalMeta),
      );
    }
    if (data.containsKey('owner_id')) {
      context.handle(
        _ownerIdMeta,
        ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta),
      );
    }
    if (data.containsKey('accepted')) {
      context.handle(
        _acceptedMeta,
        accepted.isAcceptableOrUnknown(data['accepted']!, _acceptedMeta),
      );
    }
    if (data.containsKey('needs_push')) {
      context.handle(
        _needsPushMeta,
        needsPush.isAcceptableOrUnknown(data['needs_push']!, _needsPushMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Shelf map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Shelf(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      isPersonal: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_personal'],
      )!,
      ownerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}owner_id'],
      ),
      accepted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}accepted'],
      ),
      needsPush: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_push'],
      )!,
    );
  }

  @override
  $ShelvesTable createAlias(String alias) {
    return $ShelvesTable(attachedDatabase, alias);
  }
}

class Shelf extends DataClass implements Insertable<Shelf> {
  final String id;
  final String name;
  final int sortOrder;
  final DateTime updatedAt;

  /// A shelf its owner keeps to themselves. Synced — it is theirs on every
  /// device they use — but the server withholds it from shares (migration
  /// 0029), so it never appears in anyone else's chip row.
  final bool isPersonal;

  /// Who made it, as the server knows them. Null for a shelf made on this
  /// device, or on a library with no server: "mine" is the useful reading of
  /// null, and it is what the shelf was before any of this existed.
  final String? ownerId;

  /// Whether this device shows a shelf somebody else made. **App-local only**,
  /// and deliberately: it says what this reader wants to see, not anything
  /// about the shelf, so pushing it would let one person's "no thanks" hide a
  /// shelf for everyone.
  ///
  /// Null means undecided, which is not the same as yes: an undecided shelf
  /// follows the `acceptSharedShelves` preference, and a decided one keeps the
  /// answer you gave it even if you later flip that preference. Without the
  /// third state, "accept new shelves by default: off" and "I declined this
  /// one" would be the same value, and turning the default back on would undo
  /// every individual no.
  final bool? accepted;
  final bool needsPush;
  const Shelf({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.updatedAt,
    required this.isPersonal,
    this.ownerId,
    this.accepted,
    required this.needsPush,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['is_personal'] = Variable<bool>(isPersonal);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    if (!nullToAbsent || accepted != null) {
      map['accepted'] = Variable<bool>(accepted);
    }
    map['needs_push'] = Variable<bool>(needsPush);
    return map;
  }

  ShelvesCompanion toCompanion(bool nullToAbsent) {
    return ShelvesCompanion(
      id: Value(id),
      name: Value(name),
      sortOrder: Value(sortOrder),
      updatedAt: Value(updatedAt),
      isPersonal: Value(isPersonal),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
      accepted: accepted == null && nullToAbsent
          ? const Value.absent()
          : Value(accepted),
      needsPush: Value(needsPush),
    );
  }

  factory Shelf.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Shelf(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      isPersonal: serializer.fromJson<bool>(json['isPersonal']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
      accepted: serializer.fromJson<bool?>(json['accepted']),
      needsPush: serializer.fromJson<bool>(json['needsPush']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'isPersonal': serializer.toJson<bool>(isPersonal),
      'ownerId': serializer.toJson<String?>(ownerId),
      'accepted': serializer.toJson<bool?>(accepted),
      'needsPush': serializer.toJson<bool>(needsPush),
    };
  }

  Shelf copyWith({
    String? id,
    String? name,
    int? sortOrder,
    DateTime? updatedAt,
    bool? isPersonal,
    Value<String?> ownerId = const Value.absent(),
    Value<bool?> accepted = const Value.absent(),
    bool? needsPush,
  }) => Shelf(
    id: id ?? this.id,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    updatedAt: updatedAt ?? this.updatedAt,
    isPersonal: isPersonal ?? this.isPersonal,
    ownerId: ownerId.present ? ownerId.value : this.ownerId,
    accepted: accepted.present ? accepted.value : this.accepted,
    needsPush: needsPush ?? this.needsPush,
  );
  Shelf copyWithCompanion(ShelvesCompanion data) {
    return Shelf(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      isPersonal: data.isPersonal.present
          ? data.isPersonal.value
          : this.isPersonal,
      ownerId: data.ownerId.present ? data.ownerId.value : this.ownerId,
      accepted: data.accepted.present ? data.accepted.value : this.accepted,
      needsPush: data.needsPush.present ? data.needsPush.value : this.needsPush,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Shelf(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isPersonal: $isPersonal, ')
          ..write('ownerId: $ownerId, ')
          ..write('accepted: $accepted, ')
          ..write('needsPush: $needsPush')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    sortOrder,
    updatedAt,
    isPersonal,
    ownerId,
    accepted,
    needsPush,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Shelf &&
          other.id == this.id &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.updatedAt == this.updatedAt &&
          other.isPersonal == this.isPersonal &&
          other.ownerId == this.ownerId &&
          other.accepted == this.accepted &&
          other.needsPush == this.needsPush);
}

class ShelvesCompanion extends UpdateCompanion<Shelf> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime> updatedAt;
  final Value<bool> isPersonal;
  final Value<String?> ownerId;
  final Value<bool?> accepted;
  final Value<bool> needsPush;
  final Value<int> rowid;
  const ShelvesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isPersonal = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.accepted = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShelvesCompanion.insert({
    required String id,
    required String name,
    this.sortOrder = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.isPersonal = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.accepted = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Shelf> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? updatedAt,
    Expression<bool>? isPersonal,
    Expression<String>? ownerId,
    Expression<bool>? accepted,
    Expression<bool>? needsPush,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (isPersonal != null) 'is_personal': isPersonal,
      if (ownerId != null) 'owner_id': ownerId,
      if (accepted != null) 'accepted': accepted,
      if (needsPush != null) 'needs_push': needsPush,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShelvesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<DateTime>? updatedAt,
    Value<bool>? isPersonal,
    Value<String?>? ownerId,
    Value<bool?>? accepted,
    Value<bool>? needsPush,
    Value<int>? rowid,
  }) {
    return ShelvesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt ?? this.updatedAt,
      isPersonal: isPersonal ?? this.isPersonal,
      ownerId: ownerId ?? this.ownerId,
      accepted: accepted ?? this.accepted,
      needsPush: needsPush ?? this.needsPush,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (isPersonal.present) {
      map['is_personal'] = Variable<bool>(isPersonal.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (accepted.present) {
      map['accepted'] = Variable<bool>(accepted.value);
    }
    if (needsPush.present) {
      map['needs_push'] = Variable<bool>(needsPush.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShelvesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('isPersonal: $isPersonal, ')
          ..write('ownerId: $ownerId, ')
          ..write('accepted: $accepted, ')
          ..write('needsPush: $needsPush, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ShelfBooksTable extends ShelfBooks
    with TableInfo<$ShelfBooksTable, ShelfBook> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ShelfBooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _shelfIdMeta = const VerificationMeta(
    'shelfId',
  );
  @override
  late final GeneratedColumn<String> shelfId = GeneratedColumn<String>(
    'shelf_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES shelves (id)',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id)',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [shelfId, bookId, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shelf_books';
  @override
  VerificationContext validateIntegrity(
    Insertable<ShelfBook> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('shelf_id')) {
      context.handle(
        _shelfIdMeta,
        shelfId.isAcceptableOrUnknown(data['shelf_id']!, _shelfIdMeta),
      );
    } else if (isInserting) {
      context.missing(_shelfIdMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {shelfId, bookId};
  @override
  ShelfBook map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ShelfBook(
      shelfId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}shelf_id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $ShelfBooksTable createAlias(String alias) {
    return $ShelfBooksTable(attachedDatabase, alias);
  }
}

class ShelfBook extends DataClass implements Insertable<ShelfBook> {
  final String shelfId;
  final String bookId;
  final int position;
  const ShelfBook({
    required this.shelfId,
    required this.bookId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['shelf_id'] = Variable<String>(shelfId);
    map['book_id'] = Variable<String>(bookId);
    map['position'] = Variable<int>(position);
    return map;
  }

  ShelfBooksCompanion toCompanion(bool nullToAbsent) {
    return ShelfBooksCompanion(
      shelfId: Value(shelfId),
      bookId: Value(bookId),
      position: Value(position),
    );
  }

  factory ShelfBook.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ShelfBook(
      shelfId: serializer.fromJson<String>(json['shelfId']),
      bookId: serializer.fromJson<String>(json['bookId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'shelfId': serializer.toJson<String>(shelfId),
      'bookId': serializer.toJson<String>(bookId),
      'position': serializer.toJson<int>(position),
    };
  }

  ShelfBook copyWith({String? shelfId, String? bookId, int? position}) =>
      ShelfBook(
        shelfId: shelfId ?? this.shelfId,
        bookId: bookId ?? this.bookId,
        position: position ?? this.position,
      );
  ShelfBook copyWithCompanion(ShelfBooksCompanion data) {
    return ShelfBook(
      shelfId: data.shelfId.present ? data.shelfId.value : this.shelfId,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ShelfBook(')
          ..write('shelfId: $shelfId, ')
          ..write('bookId: $bookId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(shelfId, bookId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ShelfBook &&
          other.shelfId == this.shelfId &&
          other.bookId == this.bookId &&
          other.position == this.position);
}

class ShelfBooksCompanion extends UpdateCompanion<ShelfBook> {
  final Value<String> shelfId;
  final Value<String> bookId;
  final Value<int> position;
  final Value<int> rowid;
  const ShelfBooksCompanion({
    this.shelfId = const Value.absent(),
    this.bookId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShelfBooksCompanion.insert({
    required String shelfId,
    required String bookId,
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : shelfId = Value(shelfId),
       bookId = Value(bookId);
  static Insertable<ShelfBook> custom({
    Expression<String>? shelfId,
    Expression<String>? bookId,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (shelfId != null) 'shelf_id': shelfId,
      if (bookId != null) 'book_id': bookId,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShelfBooksCompanion copyWith({
    Value<String>? shelfId,
    Value<String>? bookId,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return ShelfBooksCompanion(
      shelfId: shelfId ?? this.shelfId,
      bookId: bookId ?? this.bookId,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (shelfId.present) {
      map['shelf_id'] = Variable<String>(shelfId.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ShelfBooksCompanion(')
          ..write('shelfId: $shelfId, ')
          ..write('bookId: $bookId, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PhysicalEnvironmentsTable extends PhysicalEnvironments
    with TableInfo<$PhysicalEnvironmentsTable, PhysicalEnvironment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PhysicalEnvironmentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _serverRevisionMeta = const VerificationMeta(
    'serverRevision',
  );
  @override
  late final GeneratedColumn<int> serverRevision = GeneratedColumn<int>(
    'server_revision',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _needsPublishMeta = const VerificationMeta(
    'needsPublish',
  );
  @override
  late final GeneratedColumn<bool> needsPublish = GeneratedColumn<bool>(
    'needs_publish',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_publish" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _wallColorMeta = const VerificationMeta(
    'wallColor',
  );
  @override
  late final GeneratedColumn<int> wallColor = GeneratedColumn<int>(
    'wall_color',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _floorColorMeta = const VerificationMeta(
    'floorColor',
  );
  @override
  late final GeneratedColumn<int> floorColor = GeneratedColumn<int>(
    'floor_color',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roomSurfacesMeta = const VerificationMeta(
    'roomSurfaces',
  );
  @override
  late final GeneratedColumn<bool> roomSurfaces = GeneratedColumn<bool>(
    'room_surfaces',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("room_surfaces" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _backdropPathMeta = const VerificationMeta(
    'backdropPath',
  );
  @override
  late final GeneratedColumn<String> backdropPath = GeneratedColumn<String>(
    'backdrop_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backdropOpacityMeta = const VerificationMeta(
    'backdropOpacity',
  );
  @override
  late final GeneratedColumn<double> backdropOpacity = GeneratedColumn<double>(
    'backdrop_opacity',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.5),
  );
  static const VerificationMeta _backdropScaleMeta = const VerificationMeta(
    'backdropScale',
  );
  @override
  late final GeneratedColumn<double> backdropScale = GeneratedColumn<double>(
    'backdrop_scale',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _backdropOffsetXMeta = const VerificationMeta(
    'backdropOffsetX',
  );
  @override
  late final GeneratedColumn<double> backdropOffsetX = GeneratedColumn<double>(
    'backdrop_offset_x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _backdropOffsetYMeta = const VerificationMeta(
    'backdropOffsetY',
  );
  @override
  late final GeneratedColumn<double> backdropOffsetY = GeneratedColumn<double>(
    'backdrop_offset_y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    sortOrder,
    createdAt,
    serverRevision,
    needsPublish,
    wallColor,
    floorColor,
    roomSurfaces,
    backdropPath,
    backdropOpacity,
    backdropScale,
    backdropOffsetX,
    backdropOffsetY,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'physical_environments';
  @override
  VerificationContext validateIntegrity(
    Insertable<PhysicalEnvironment> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('server_revision')) {
      context.handle(
        _serverRevisionMeta,
        serverRevision.isAcceptableOrUnknown(
          data['server_revision']!,
          _serverRevisionMeta,
        ),
      );
    }
    if (data.containsKey('needs_publish')) {
      context.handle(
        _needsPublishMeta,
        needsPublish.isAcceptableOrUnknown(
          data['needs_publish']!,
          _needsPublishMeta,
        ),
      );
    }
    if (data.containsKey('wall_color')) {
      context.handle(
        _wallColorMeta,
        wallColor.isAcceptableOrUnknown(data['wall_color']!, _wallColorMeta),
      );
    }
    if (data.containsKey('floor_color')) {
      context.handle(
        _floorColorMeta,
        floorColor.isAcceptableOrUnknown(data['floor_color']!, _floorColorMeta),
      );
    }
    if (data.containsKey('room_surfaces')) {
      context.handle(
        _roomSurfacesMeta,
        roomSurfaces.isAcceptableOrUnknown(
          data['room_surfaces']!,
          _roomSurfacesMeta,
        ),
      );
    }
    if (data.containsKey('backdrop_path')) {
      context.handle(
        _backdropPathMeta,
        backdropPath.isAcceptableOrUnknown(
          data['backdrop_path']!,
          _backdropPathMeta,
        ),
      );
    }
    if (data.containsKey('backdrop_opacity')) {
      context.handle(
        _backdropOpacityMeta,
        backdropOpacity.isAcceptableOrUnknown(
          data['backdrop_opacity']!,
          _backdropOpacityMeta,
        ),
      );
    }
    if (data.containsKey('backdrop_scale')) {
      context.handle(
        _backdropScaleMeta,
        backdropScale.isAcceptableOrUnknown(
          data['backdrop_scale']!,
          _backdropScaleMeta,
        ),
      );
    }
    if (data.containsKey('backdrop_offset_x')) {
      context.handle(
        _backdropOffsetXMeta,
        backdropOffsetX.isAcceptableOrUnknown(
          data['backdrop_offset_x']!,
          _backdropOffsetXMeta,
        ),
      );
    }
    if (data.containsKey('backdrop_offset_y')) {
      context.handle(
        _backdropOffsetYMeta,
        backdropOffsetY.isAcceptableOrUnknown(
          data['backdrop_offset_y']!,
          _backdropOffsetYMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PhysicalEnvironment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PhysicalEnvironment(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      serverRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_revision'],
      ),
      needsPublish: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_publish'],
      )!,
      wallColor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}wall_color'],
      ),
      floorColor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}floor_color'],
      ),
      roomSurfaces: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}room_surfaces'],
      )!,
      backdropPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}backdrop_path'],
      ),
      backdropOpacity: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}backdrop_opacity'],
      )!,
      backdropScale: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}backdrop_scale'],
      ),
      backdropOffsetX: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}backdrop_offset_x'],
      )!,
      backdropOffsetY: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}backdrop_offset_y'],
      )!,
    );
  }

  @override
  $PhysicalEnvironmentsTable createAlias(String alias) {
    return $PhysicalEnvironmentsTable(attachedDatabase, alias);
  }
}

class PhysicalEnvironment extends DataClass
    implements Insertable<PhysicalEnvironment> {
  final String id;
  final String name;
  final int sortOrder;
  final DateTime createdAt;
  final int? serverRevision;
  final bool needsPublish;
  final int? wallColor;
  final int? floorColor;

  /// Whether to draw the floor line, its skirting board, and a soft shadow
  /// under each shelf. On by default — an empty room drawn without them looks
  /// like graph paper.
  final bool roomSurfaces;
  final String? backdropPath;
  final double backdropOpacity;

  /// Metres per backdrop pixel, from the two-point calibration. Null means the
  /// photo has never been calibrated, so it is drawn but not trusted for scale.
  final double? backdropScale;

  /// Where the photo's top-left sits in world metres.
  final double backdropOffsetX;
  final double backdropOffsetY;
  const PhysicalEnvironment({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
    this.serverRevision,
    required this.needsPublish,
    this.wallColor,
    this.floorColor,
    required this.roomSurfaces,
    this.backdropPath,
    required this.backdropOpacity,
    this.backdropScale,
    required this.backdropOffsetX,
    required this.backdropOffsetY,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || serverRevision != null) {
      map['server_revision'] = Variable<int>(serverRevision);
    }
    map['needs_publish'] = Variable<bool>(needsPublish);
    if (!nullToAbsent || wallColor != null) {
      map['wall_color'] = Variable<int>(wallColor);
    }
    if (!nullToAbsent || floorColor != null) {
      map['floor_color'] = Variable<int>(floorColor);
    }
    map['room_surfaces'] = Variable<bool>(roomSurfaces);
    if (!nullToAbsent || backdropPath != null) {
      map['backdrop_path'] = Variable<String>(backdropPath);
    }
    map['backdrop_opacity'] = Variable<double>(backdropOpacity);
    if (!nullToAbsent || backdropScale != null) {
      map['backdrop_scale'] = Variable<double>(backdropScale);
    }
    map['backdrop_offset_x'] = Variable<double>(backdropOffsetX);
    map['backdrop_offset_y'] = Variable<double>(backdropOffsetY);
    return map;
  }

  PhysicalEnvironmentsCompanion toCompanion(bool nullToAbsent) {
    return PhysicalEnvironmentsCompanion(
      id: Value(id),
      name: Value(name),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      serverRevision: serverRevision == null && nullToAbsent
          ? const Value.absent()
          : Value(serverRevision),
      needsPublish: Value(needsPublish),
      wallColor: wallColor == null && nullToAbsent
          ? const Value.absent()
          : Value(wallColor),
      floorColor: floorColor == null && nullToAbsent
          ? const Value.absent()
          : Value(floorColor),
      roomSurfaces: Value(roomSurfaces),
      backdropPath: backdropPath == null && nullToAbsent
          ? const Value.absent()
          : Value(backdropPath),
      backdropOpacity: Value(backdropOpacity),
      backdropScale: backdropScale == null && nullToAbsent
          ? const Value.absent()
          : Value(backdropScale),
      backdropOffsetX: Value(backdropOffsetX),
      backdropOffsetY: Value(backdropOffsetY),
    );
  }

  factory PhysicalEnvironment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PhysicalEnvironment(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      serverRevision: serializer.fromJson<int?>(json['serverRevision']),
      needsPublish: serializer.fromJson<bool>(json['needsPublish']),
      wallColor: serializer.fromJson<int?>(json['wallColor']),
      floorColor: serializer.fromJson<int?>(json['floorColor']),
      roomSurfaces: serializer.fromJson<bool>(json['roomSurfaces']),
      backdropPath: serializer.fromJson<String?>(json['backdropPath']),
      backdropOpacity: serializer.fromJson<double>(json['backdropOpacity']),
      backdropScale: serializer.fromJson<double?>(json['backdropScale']),
      backdropOffsetX: serializer.fromJson<double>(json['backdropOffsetX']),
      backdropOffsetY: serializer.fromJson<double>(json['backdropOffsetY']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'serverRevision': serializer.toJson<int?>(serverRevision),
      'needsPublish': serializer.toJson<bool>(needsPublish),
      'wallColor': serializer.toJson<int?>(wallColor),
      'floorColor': serializer.toJson<int?>(floorColor),
      'roomSurfaces': serializer.toJson<bool>(roomSurfaces),
      'backdropPath': serializer.toJson<String?>(backdropPath),
      'backdropOpacity': serializer.toJson<double>(backdropOpacity),
      'backdropScale': serializer.toJson<double?>(backdropScale),
      'backdropOffsetX': serializer.toJson<double>(backdropOffsetX),
      'backdropOffsetY': serializer.toJson<double>(backdropOffsetY),
    };
  }

  PhysicalEnvironment copyWith({
    String? id,
    String? name,
    int? sortOrder,
    DateTime? createdAt,
    Value<int?> serverRevision = const Value.absent(),
    bool? needsPublish,
    Value<int?> wallColor = const Value.absent(),
    Value<int?> floorColor = const Value.absent(),
    bool? roomSurfaces,
    Value<String?> backdropPath = const Value.absent(),
    double? backdropOpacity,
    Value<double?> backdropScale = const Value.absent(),
    double? backdropOffsetX,
    double? backdropOffsetY,
  }) => PhysicalEnvironment(
    id: id ?? this.id,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    serverRevision: serverRevision.present
        ? serverRevision.value
        : this.serverRevision,
    needsPublish: needsPublish ?? this.needsPublish,
    wallColor: wallColor.present ? wallColor.value : this.wallColor,
    floorColor: floorColor.present ? floorColor.value : this.floorColor,
    roomSurfaces: roomSurfaces ?? this.roomSurfaces,
    backdropPath: backdropPath.present ? backdropPath.value : this.backdropPath,
    backdropOpacity: backdropOpacity ?? this.backdropOpacity,
    backdropScale: backdropScale.present
        ? backdropScale.value
        : this.backdropScale,
    backdropOffsetX: backdropOffsetX ?? this.backdropOffsetX,
    backdropOffsetY: backdropOffsetY ?? this.backdropOffsetY,
  );
  PhysicalEnvironment copyWithCompanion(PhysicalEnvironmentsCompanion data) {
    return PhysicalEnvironment(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      serverRevision: data.serverRevision.present
          ? data.serverRevision.value
          : this.serverRevision,
      needsPublish: data.needsPublish.present
          ? data.needsPublish.value
          : this.needsPublish,
      wallColor: data.wallColor.present ? data.wallColor.value : this.wallColor,
      floorColor: data.floorColor.present
          ? data.floorColor.value
          : this.floorColor,
      roomSurfaces: data.roomSurfaces.present
          ? data.roomSurfaces.value
          : this.roomSurfaces,
      backdropPath: data.backdropPath.present
          ? data.backdropPath.value
          : this.backdropPath,
      backdropOpacity: data.backdropOpacity.present
          ? data.backdropOpacity.value
          : this.backdropOpacity,
      backdropScale: data.backdropScale.present
          ? data.backdropScale.value
          : this.backdropScale,
      backdropOffsetX: data.backdropOffsetX.present
          ? data.backdropOffsetX.value
          : this.backdropOffsetX,
      backdropOffsetY: data.backdropOffsetY.present
          ? data.backdropOffsetY.value
          : this.backdropOffsetY,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PhysicalEnvironment(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('serverRevision: $serverRevision, ')
          ..write('needsPublish: $needsPublish, ')
          ..write('wallColor: $wallColor, ')
          ..write('floorColor: $floorColor, ')
          ..write('roomSurfaces: $roomSurfaces, ')
          ..write('backdropPath: $backdropPath, ')
          ..write('backdropOpacity: $backdropOpacity, ')
          ..write('backdropScale: $backdropScale, ')
          ..write('backdropOffsetX: $backdropOffsetX, ')
          ..write('backdropOffsetY: $backdropOffsetY')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    sortOrder,
    createdAt,
    serverRevision,
    needsPublish,
    wallColor,
    floorColor,
    roomSurfaces,
    backdropPath,
    backdropOpacity,
    backdropScale,
    backdropOffsetX,
    backdropOffsetY,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PhysicalEnvironment &&
          other.id == this.id &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.serverRevision == this.serverRevision &&
          other.needsPublish == this.needsPublish &&
          other.wallColor == this.wallColor &&
          other.floorColor == this.floorColor &&
          other.roomSurfaces == this.roomSurfaces &&
          other.backdropPath == this.backdropPath &&
          other.backdropOpacity == this.backdropOpacity &&
          other.backdropScale == this.backdropScale &&
          other.backdropOffsetX == this.backdropOffsetX &&
          other.backdropOffsetY == this.backdropOffsetY);
}

class PhysicalEnvironmentsCompanion
    extends UpdateCompanion<PhysicalEnvironment> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<int?> serverRevision;
  final Value<bool> needsPublish;
  final Value<int?> wallColor;
  final Value<int?> floorColor;
  final Value<bool> roomSurfaces;
  final Value<String?> backdropPath;
  final Value<double> backdropOpacity;
  final Value<double?> backdropScale;
  final Value<double> backdropOffsetX;
  final Value<double> backdropOffsetY;
  final Value<int> rowid;
  const PhysicalEnvironmentsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.serverRevision = const Value.absent(),
    this.needsPublish = const Value.absent(),
    this.wallColor = const Value.absent(),
    this.floorColor = const Value.absent(),
    this.roomSurfaces = const Value.absent(),
    this.backdropPath = const Value.absent(),
    this.backdropOpacity = const Value.absent(),
    this.backdropScale = const Value.absent(),
    this.backdropOffsetX = const Value.absent(),
    this.backdropOffsetY = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PhysicalEnvironmentsCompanion.insert({
    required String id,
    required String name,
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.serverRevision = const Value.absent(),
    this.needsPublish = const Value.absent(),
    this.wallColor = const Value.absent(),
    this.floorColor = const Value.absent(),
    this.roomSurfaces = const Value.absent(),
    this.backdropPath = const Value.absent(),
    this.backdropOpacity = const Value.absent(),
    this.backdropScale = const Value.absent(),
    this.backdropOffsetX = const Value.absent(),
    this.backdropOffsetY = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<PhysicalEnvironment> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<int>? serverRevision,
    Expression<bool>? needsPublish,
    Expression<int>? wallColor,
    Expression<int>? floorColor,
    Expression<bool>? roomSurfaces,
    Expression<String>? backdropPath,
    Expression<double>? backdropOpacity,
    Expression<double>? backdropScale,
    Expression<double>? backdropOffsetX,
    Expression<double>? backdropOffsetY,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (serverRevision != null) 'server_revision': serverRevision,
      if (needsPublish != null) 'needs_publish': needsPublish,
      if (wallColor != null) 'wall_color': wallColor,
      if (floorColor != null) 'floor_color': floorColor,
      if (roomSurfaces != null) 'room_surfaces': roomSurfaces,
      if (backdropPath != null) 'backdrop_path': backdropPath,
      if (backdropOpacity != null) 'backdrop_opacity': backdropOpacity,
      if (backdropScale != null) 'backdrop_scale': backdropScale,
      if (backdropOffsetX != null) 'backdrop_offset_x': backdropOffsetX,
      if (backdropOffsetY != null) 'backdrop_offset_y': backdropOffsetY,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PhysicalEnvironmentsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<DateTime>? createdAt,
    Value<int?>? serverRevision,
    Value<bool>? needsPublish,
    Value<int?>? wallColor,
    Value<int?>? floorColor,
    Value<bool>? roomSurfaces,
    Value<String?>? backdropPath,
    Value<double>? backdropOpacity,
    Value<double?>? backdropScale,
    Value<double>? backdropOffsetX,
    Value<double>? backdropOffsetY,
    Value<int>? rowid,
  }) {
    return PhysicalEnvironmentsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      serverRevision: serverRevision ?? this.serverRevision,
      needsPublish: needsPublish ?? this.needsPublish,
      wallColor: wallColor ?? this.wallColor,
      floorColor: floorColor ?? this.floorColor,
      roomSurfaces: roomSurfaces ?? this.roomSurfaces,
      backdropPath: backdropPath ?? this.backdropPath,
      backdropOpacity: backdropOpacity ?? this.backdropOpacity,
      backdropScale: backdropScale ?? this.backdropScale,
      backdropOffsetX: backdropOffsetX ?? this.backdropOffsetX,
      backdropOffsetY: backdropOffsetY ?? this.backdropOffsetY,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (serverRevision.present) {
      map['server_revision'] = Variable<int>(serverRevision.value);
    }
    if (needsPublish.present) {
      map['needs_publish'] = Variable<bool>(needsPublish.value);
    }
    if (wallColor.present) {
      map['wall_color'] = Variable<int>(wallColor.value);
    }
    if (floorColor.present) {
      map['floor_color'] = Variable<int>(floorColor.value);
    }
    if (roomSurfaces.present) {
      map['room_surfaces'] = Variable<bool>(roomSurfaces.value);
    }
    if (backdropPath.present) {
      map['backdrop_path'] = Variable<String>(backdropPath.value);
    }
    if (backdropOpacity.present) {
      map['backdrop_opacity'] = Variable<double>(backdropOpacity.value);
    }
    if (backdropScale.present) {
      map['backdrop_scale'] = Variable<double>(backdropScale.value);
    }
    if (backdropOffsetX.present) {
      map['backdrop_offset_x'] = Variable<double>(backdropOffsetX.value);
    }
    if (backdropOffsetY.present) {
      map['backdrop_offset_y'] = Variable<double>(backdropOffsetY.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PhysicalEnvironmentsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('serverRevision: $serverRevision, ')
          ..write('needsPublish: $needsPublish, ')
          ..write('wallColor: $wallColor, ')
          ..write('floorColor: $floorColor, ')
          ..write('roomSurfaces: $roomSurfaces, ')
          ..write('backdropPath: $backdropPath, ')
          ..write('backdropOpacity: $backdropOpacity, ')
          ..write('backdropScale: $backdropScale, ')
          ..write('backdropOffsetX: $backdropOffsetX, ')
          ..write('backdropOffsetY: $backdropOffsetY, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PhysicalShelvesTable extends PhysicalShelves
    with TableInfo<$PhysicalShelvesTable, PhysicalShelf> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PhysicalShelvesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _environmentIdMeta = const VerificationMeta(
    'environmentId',
  );
  @override
  late final GeneratedColumn<String> environmentId = GeneratedColumn<String>(
    'environment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES physical_environments (id)',
    ),
  );
  static const VerificationMeta _x1Meta = const VerificationMeta('x1');
  @override
  late final GeneratedColumn<double> x1 = GeneratedColumn<double>(
    'x1',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _y1Meta = const VerificationMeta('y1');
  @override
  late final GeneratedColumn<double> y1 = GeneratedColumn<double>(
    'y1',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _x2Meta = const VerificationMeta('x2');
  @override
  late final GeneratedColumn<double> x2 = GeneratedColumn<double>(
    'x2',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _y2Meta = const VerificationMeta('y2');
  @override
  late final GeneratedColumn<double> y2 = GeneratedColumn<double>(
    'y2',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('shelf'),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _anchoredMeta = const VerificationMeta(
    'anchored',
  );
  @override
  late final GeneratedColumn<bool> anchored = GeneratedColumn<bool>(
    'anchored',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("anchored" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    environmentId,
    x1,
    y1,
    x2,
    y2,
    label,
    kind,
    groupId,
    anchored,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'physical_shelves';
  @override
  VerificationContext validateIntegrity(
    Insertable<PhysicalShelf> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('environment_id')) {
      context.handle(
        _environmentIdMeta,
        environmentId.isAcceptableOrUnknown(
          data['environment_id']!,
          _environmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_environmentIdMeta);
    }
    if (data.containsKey('x1')) {
      context.handle(_x1Meta, x1.isAcceptableOrUnknown(data['x1']!, _x1Meta));
    } else if (isInserting) {
      context.missing(_x1Meta);
    }
    if (data.containsKey('y1')) {
      context.handle(_y1Meta, y1.isAcceptableOrUnknown(data['y1']!, _y1Meta));
    } else if (isInserting) {
      context.missing(_y1Meta);
    }
    if (data.containsKey('x2')) {
      context.handle(_x2Meta, x2.isAcceptableOrUnknown(data['x2']!, _x2Meta));
    } else if (isInserting) {
      context.missing(_x2Meta);
    }
    if (data.containsKey('y2')) {
      context.handle(_y2Meta, y2.isAcceptableOrUnknown(data['y2']!, _y2Meta));
    } else if (isInserting) {
      context.missing(_y2Meta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('anchored')) {
      context.handle(
        _anchoredMeta,
        anchored.isAcceptableOrUnknown(data['anchored']!, _anchoredMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PhysicalShelf map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PhysicalShelf(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      environmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}environment_id'],
      )!,
      x1: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}x1'],
      )!,
      y1: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}y1'],
      )!,
      x2: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}x2'],
      )!,
      y2: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}y2'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      ),
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
      anchored: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}anchored'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PhysicalShelvesTable createAlias(String alias) {
    return $PhysicalShelvesTable(attachedDatabase, alias);
  }
}

class PhysicalShelf extends DataClass implements Insertable<PhysicalShelf> {
  final String id;
  final String environmentId;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final String? label;

  /// What this segment *is* (plan 5 #29): 'shelf' (books rest on it),
  /// 'panel' (a bookcase side — structure, nothing rests on it), 'divider'
  /// (a vertical separator), or 'label' (a text marker).
  ///
  /// A `kind` column rather than a second table, because a side panel is
  /// geometrically a shelf that books don't sit on — the only difference is
  /// whether `settle` may land something on it, which is one predicate.
  final String kind;

  /// Which bookcase this segment belongs to, or null when it stands alone.
  ///
  /// **A tag, not a hierarchy.** A bookcase is still just its segments — this
  /// only says which ones move, resize and delete together. Making bookcases a
  /// parent table would have broken every query that reasons about a flat list
  /// of segments (fill, tidy, stocktake, labels, the published document), and
  /// would have had to answer "what happens when I drag one shelf out of a
  /// bookcase". With a tag the answer is easy: it keeps the tag until you
  /// ungroup, and ungrouping is one UPDATE.
  final String? groupId;

  /// Whether this segment refuses to be dragged.
  ///
  /// **Anchored by default, deliberately.** A room is arranged once and then
  /// looked at hundreds of times, so the common gesture on a shelf is not
  /// "move it" — and a left-click that shifts a bookcase you were only trying
  /// to look at is a mistake you have to notice before you can undo it.
  /// Unanchoring is a right-click (or long-press) away, and is remembered, so
  /// rearranging stays a two-step act you opted into.
  final bool anchored;
  final DateTime createdAt;
  const PhysicalShelf({
    required this.id,
    required this.environmentId,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.label,
    required this.kind,
    this.groupId,
    required this.anchored,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['environment_id'] = Variable<String>(environmentId);
    map['x1'] = Variable<double>(x1);
    map['y1'] = Variable<double>(y1);
    map['x2'] = Variable<double>(x2);
    map['y2'] = Variable<double>(y2);
    if (!nullToAbsent || label != null) {
      map['label'] = Variable<String>(label);
    }
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    map['anchored'] = Variable<bool>(anchored);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PhysicalShelvesCompanion toCompanion(bool nullToAbsent) {
    return PhysicalShelvesCompanion(
      id: Value(id),
      environmentId: Value(environmentId),
      x1: Value(x1),
      y1: Value(y1),
      x2: Value(x2),
      y2: Value(y2),
      label: label == null && nullToAbsent
          ? const Value.absent()
          : Value(label),
      kind: Value(kind),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      anchored: Value(anchored),
      createdAt: Value(createdAt),
    );
  }

  factory PhysicalShelf.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PhysicalShelf(
      id: serializer.fromJson<String>(json['id']),
      environmentId: serializer.fromJson<String>(json['environmentId']),
      x1: serializer.fromJson<double>(json['x1']),
      y1: serializer.fromJson<double>(json['y1']),
      x2: serializer.fromJson<double>(json['x2']),
      y2: serializer.fromJson<double>(json['y2']),
      label: serializer.fromJson<String?>(json['label']),
      kind: serializer.fromJson<String>(json['kind']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      anchored: serializer.fromJson<bool>(json['anchored']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'environmentId': serializer.toJson<String>(environmentId),
      'x1': serializer.toJson<double>(x1),
      'y1': serializer.toJson<double>(y1),
      'x2': serializer.toJson<double>(x2),
      'y2': serializer.toJson<double>(y2),
      'label': serializer.toJson<String?>(label),
      'kind': serializer.toJson<String>(kind),
      'groupId': serializer.toJson<String?>(groupId),
      'anchored': serializer.toJson<bool>(anchored),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  PhysicalShelf copyWith({
    String? id,
    String? environmentId,
    double? x1,
    double? y1,
    double? x2,
    double? y2,
    Value<String?> label = const Value.absent(),
    String? kind,
    Value<String?> groupId = const Value.absent(),
    bool? anchored,
    DateTime? createdAt,
  }) => PhysicalShelf(
    id: id ?? this.id,
    environmentId: environmentId ?? this.environmentId,
    x1: x1 ?? this.x1,
    y1: y1 ?? this.y1,
    x2: x2 ?? this.x2,
    y2: y2 ?? this.y2,
    label: label.present ? label.value : this.label,
    kind: kind ?? this.kind,
    groupId: groupId.present ? groupId.value : this.groupId,
    anchored: anchored ?? this.anchored,
    createdAt: createdAt ?? this.createdAt,
  );
  PhysicalShelf copyWithCompanion(PhysicalShelvesCompanion data) {
    return PhysicalShelf(
      id: data.id.present ? data.id.value : this.id,
      environmentId: data.environmentId.present
          ? data.environmentId.value
          : this.environmentId,
      x1: data.x1.present ? data.x1.value : this.x1,
      y1: data.y1.present ? data.y1.value : this.y1,
      x2: data.x2.present ? data.x2.value : this.x2,
      y2: data.y2.present ? data.y2.value : this.y2,
      label: data.label.present ? data.label.value : this.label,
      kind: data.kind.present ? data.kind.value : this.kind,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      anchored: data.anchored.present ? data.anchored.value : this.anchored,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PhysicalShelf(')
          ..write('id: $id, ')
          ..write('environmentId: $environmentId, ')
          ..write('x1: $x1, ')
          ..write('y1: $y1, ')
          ..write('x2: $x2, ')
          ..write('y2: $y2, ')
          ..write('label: $label, ')
          ..write('kind: $kind, ')
          ..write('groupId: $groupId, ')
          ..write('anchored: $anchored, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    environmentId,
    x1,
    y1,
    x2,
    y2,
    label,
    kind,
    groupId,
    anchored,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PhysicalShelf &&
          other.id == this.id &&
          other.environmentId == this.environmentId &&
          other.x1 == this.x1 &&
          other.y1 == this.y1 &&
          other.x2 == this.x2 &&
          other.y2 == this.y2 &&
          other.label == this.label &&
          other.kind == this.kind &&
          other.groupId == this.groupId &&
          other.anchored == this.anchored &&
          other.createdAt == this.createdAt);
}

class PhysicalShelvesCompanion extends UpdateCompanion<PhysicalShelf> {
  final Value<String> id;
  final Value<String> environmentId;
  final Value<double> x1;
  final Value<double> y1;
  final Value<double> x2;
  final Value<double> y2;
  final Value<String?> label;
  final Value<String> kind;
  final Value<String?> groupId;
  final Value<bool> anchored;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PhysicalShelvesCompanion({
    this.id = const Value.absent(),
    this.environmentId = const Value.absent(),
    this.x1 = const Value.absent(),
    this.y1 = const Value.absent(),
    this.x2 = const Value.absent(),
    this.y2 = const Value.absent(),
    this.label = const Value.absent(),
    this.kind = const Value.absent(),
    this.groupId = const Value.absent(),
    this.anchored = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PhysicalShelvesCompanion.insert({
    required String id,
    required String environmentId,
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    this.label = const Value.absent(),
    this.kind = const Value.absent(),
    this.groupId = const Value.absent(),
    this.anchored = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       environmentId = Value(environmentId),
       x1 = Value(x1),
       y1 = Value(y1),
       x2 = Value(x2),
       y2 = Value(y2);
  static Insertable<PhysicalShelf> custom({
    Expression<String>? id,
    Expression<String>? environmentId,
    Expression<double>? x1,
    Expression<double>? y1,
    Expression<double>? x2,
    Expression<double>? y2,
    Expression<String>? label,
    Expression<String>? kind,
    Expression<String>? groupId,
    Expression<bool>? anchored,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (environmentId != null) 'environment_id': environmentId,
      if (x1 != null) 'x1': x1,
      if (y1 != null) 'y1': y1,
      if (x2 != null) 'x2': x2,
      if (y2 != null) 'y2': y2,
      if (label != null) 'label': label,
      if (kind != null) 'kind': kind,
      if (groupId != null) 'group_id': groupId,
      if (anchored != null) 'anchored': anchored,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PhysicalShelvesCompanion copyWith({
    Value<String>? id,
    Value<String>? environmentId,
    Value<double>? x1,
    Value<double>? y1,
    Value<double>? x2,
    Value<double>? y2,
    Value<String?>? label,
    Value<String>? kind,
    Value<String?>? groupId,
    Value<bool>? anchored,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return PhysicalShelvesCompanion(
      id: id ?? this.id,
      environmentId: environmentId ?? this.environmentId,
      x1: x1 ?? this.x1,
      y1: y1 ?? this.y1,
      x2: x2 ?? this.x2,
      y2: y2 ?? this.y2,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      groupId: groupId ?? this.groupId,
      anchored: anchored ?? this.anchored,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (environmentId.present) {
      map['environment_id'] = Variable<String>(environmentId.value);
    }
    if (x1.present) {
      map['x1'] = Variable<double>(x1.value);
    }
    if (y1.present) {
      map['y1'] = Variable<double>(y1.value);
    }
    if (x2.present) {
      map['x2'] = Variable<double>(x2.value);
    }
    if (y2.present) {
      map['y2'] = Variable<double>(y2.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (anchored.present) {
      map['anchored'] = Variable<bool>(anchored.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PhysicalShelvesCompanion(')
          ..write('id: $id, ')
          ..write('environmentId: $environmentId, ')
          ..write('x1: $x1, ')
          ..write('y1: $y1, ')
          ..write('x2: $x2, ')
          ..write('y2: $y2, ')
          ..write('label: $label, ')
          ..write('kind: $kind, ')
          ..write('groupId: $groupId, ')
          ..write('anchored: $anchored, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookPlacementsTable extends BookPlacements
    with TableInfo<$BookPlacementsTable, BookPlacement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookPlacementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _environmentIdMeta = const VerificationMeta(
    'environmentId',
  );
  @override
  late final GeneratedColumn<String> environmentId = GeneratedColumn<String>(
    'environment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES physical_environments (id)',
    ),
  );
  static const VerificationMeta _copyIdMeta = const VerificationMeta('copyId');
  @override
  late final GeneratedColumn<String> copyId = GeneratedColumn<String>(
    'copy_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES physical_copies (id)',
    ),
  );
  static const VerificationMeta _xMeta = const VerificationMeta('x');
  @override
  late final GeneratedColumn<double> x = GeneratedColumn<double>(
    'x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yMeta = const VerificationMeta('y');
  @override
  late final GeneratedColumn<double> y = GeneratedColumn<double>(
    'y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rotationMeta = const VerificationMeta(
    'rotation',
  );
  @override
  late final GeneratedColumn<int> rotation = GeneratedColumn<int>(
    'rotation',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _widthOverrideMeta = const VerificationMeta(
    'widthOverride',
  );
  @override
  late final GeneratedColumn<double> widthOverride = GeneratedColumn<double>(
    'width_override',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightOverrideMeta = const VerificationMeta(
    'heightOverride',
  );
  @override
  late final GeneratedColumn<double> heightOverride = GeneratedColumn<double>(
    'height_override',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _formatMeta = const VerificationMeta('format');
  @override
  late final GeneratedColumn<String> format = GeneratedColumn<String>(
    'format',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    environmentId,
    copyId,
    x,
    y,
    rotation,
    widthOverride,
    heightOverride,
    format,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_placements';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookPlacement> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('environment_id')) {
      context.handle(
        _environmentIdMeta,
        environmentId.isAcceptableOrUnknown(
          data['environment_id']!,
          _environmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_environmentIdMeta);
    }
    if (data.containsKey('copy_id')) {
      context.handle(
        _copyIdMeta,
        copyId.isAcceptableOrUnknown(data['copy_id']!, _copyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_copyIdMeta);
    }
    if (data.containsKey('x')) {
      context.handle(_xMeta, x.isAcceptableOrUnknown(data['x']!, _xMeta));
    } else if (isInserting) {
      context.missing(_xMeta);
    }
    if (data.containsKey('y')) {
      context.handle(_yMeta, y.isAcceptableOrUnknown(data['y']!, _yMeta));
    } else if (isInserting) {
      context.missing(_yMeta);
    }
    if (data.containsKey('rotation')) {
      context.handle(
        _rotationMeta,
        rotation.isAcceptableOrUnknown(data['rotation']!, _rotationMeta),
      );
    }
    if (data.containsKey('width_override')) {
      context.handle(
        _widthOverrideMeta,
        widthOverride.isAcceptableOrUnknown(
          data['width_override']!,
          _widthOverrideMeta,
        ),
      );
    }
    if (data.containsKey('height_override')) {
      context.handle(
        _heightOverrideMeta,
        heightOverride.isAcceptableOrUnknown(
          data['height_override']!,
          _heightOverrideMeta,
        ),
      );
    }
    if (data.containsKey('format')) {
      context.handle(
        _formatMeta,
        format.isAcceptableOrUnknown(data['format']!, _formatMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookPlacement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookPlacement(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      environmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}environment_id'],
      )!,
      copyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}copy_id'],
      )!,
      x: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}x'],
      )!,
      y: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}y'],
      )!,
      rotation: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rotation'],
      )!,
      widthOverride: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}width_override'],
      ),
      heightOverride: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}height_override'],
      ),
      format: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}format'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $BookPlacementsTable createAlias(String alias) {
    return $BookPlacementsTable(attachedDatabase, alias);
  }
}

class BookPlacement extends DataClass implements Insertable<BookPlacement> {
  final String id;
  final String environmentId;
  final String copyId;
  final double x;
  final double y;
  final int rotation;
  final double? widthOverride;
  final double? heightOverride;
  final String? format;
  final DateTime createdAt;
  const BookPlacement({
    required this.id,
    required this.environmentId,
    required this.copyId,
    required this.x,
    required this.y,
    required this.rotation,
    this.widthOverride,
    this.heightOverride,
    this.format,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['environment_id'] = Variable<String>(environmentId);
    map['copy_id'] = Variable<String>(copyId);
    map['x'] = Variable<double>(x);
    map['y'] = Variable<double>(y);
    map['rotation'] = Variable<int>(rotation);
    if (!nullToAbsent || widthOverride != null) {
      map['width_override'] = Variable<double>(widthOverride);
    }
    if (!nullToAbsent || heightOverride != null) {
      map['height_override'] = Variable<double>(heightOverride);
    }
    if (!nullToAbsent || format != null) {
      map['format'] = Variable<String>(format);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  BookPlacementsCompanion toCompanion(bool nullToAbsent) {
    return BookPlacementsCompanion(
      id: Value(id),
      environmentId: Value(environmentId),
      copyId: Value(copyId),
      x: Value(x),
      y: Value(y),
      rotation: Value(rotation),
      widthOverride: widthOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(widthOverride),
      heightOverride: heightOverride == null && nullToAbsent
          ? const Value.absent()
          : Value(heightOverride),
      format: format == null && nullToAbsent
          ? const Value.absent()
          : Value(format),
      createdAt: Value(createdAt),
    );
  }

  factory BookPlacement.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookPlacement(
      id: serializer.fromJson<String>(json['id']),
      environmentId: serializer.fromJson<String>(json['environmentId']),
      copyId: serializer.fromJson<String>(json['copyId']),
      x: serializer.fromJson<double>(json['x']),
      y: serializer.fromJson<double>(json['y']),
      rotation: serializer.fromJson<int>(json['rotation']),
      widthOverride: serializer.fromJson<double?>(json['widthOverride']),
      heightOverride: serializer.fromJson<double?>(json['heightOverride']),
      format: serializer.fromJson<String?>(json['format']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'environmentId': serializer.toJson<String>(environmentId),
      'copyId': serializer.toJson<String>(copyId),
      'x': serializer.toJson<double>(x),
      'y': serializer.toJson<double>(y),
      'rotation': serializer.toJson<int>(rotation),
      'widthOverride': serializer.toJson<double?>(widthOverride),
      'heightOverride': serializer.toJson<double?>(heightOverride),
      'format': serializer.toJson<String?>(format),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  BookPlacement copyWith({
    String? id,
    String? environmentId,
    String? copyId,
    double? x,
    double? y,
    int? rotation,
    Value<double?> widthOverride = const Value.absent(),
    Value<double?> heightOverride = const Value.absent(),
    Value<String?> format = const Value.absent(),
    DateTime? createdAt,
  }) => BookPlacement(
    id: id ?? this.id,
    environmentId: environmentId ?? this.environmentId,
    copyId: copyId ?? this.copyId,
    x: x ?? this.x,
    y: y ?? this.y,
    rotation: rotation ?? this.rotation,
    widthOverride: widthOverride.present
        ? widthOverride.value
        : this.widthOverride,
    heightOverride: heightOverride.present
        ? heightOverride.value
        : this.heightOverride,
    format: format.present ? format.value : this.format,
    createdAt: createdAt ?? this.createdAt,
  );
  BookPlacement copyWithCompanion(BookPlacementsCompanion data) {
    return BookPlacement(
      id: data.id.present ? data.id.value : this.id,
      environmentId: data.environmentId.present
          ? data.environmentId.value
          : this.environmentId,
      copyId: data.copyId.present ? data.copyId.value : this.copyId,
      x: data.x.present ? data.x.value : this.x,
      y: data.y.present ? data.y.value : this.y,
      rotation: data.rotation.present ? data.rotation.value : this.rotation,
      widthOverride: data.widthOverride.present
          ? data.widthOverride.value
          : this.widthOverride,
      heightOverride: data.heightOverride.present
          ? data.heightOverride.value
          : this.heightOverride,
      format: data.format.present ? data.format.value : this.format,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookPlacement(')
          ..write('id: $id, ')
          ..write('environmentId: $environmentId, ')
          ..write('copyId: $copyId, ')
          ..write('x: $x, ')
          ..write('y: $y, ')
          ..write('rotation: $rotation, ')
          ..write('widthOverride: $widthOverride, ')
          ..write('heightOverride: $heightOverride, ')
          ..write('format: $format, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    environmentId,
    copyId,
    x,
    y,
    rotation,
    widthOverride,
    heightOverride,
    format,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookPlacement &&
          other.id == this.id &&
          other.environmentId == this.environmentId &&
          other.copyId == this.copyId &&
          other.x == this.x &&
          other.y == this.y &&
          other.rotation == this.rotation &&
          other.widthOverride == this.widthOverride &&
          other.heightOverride == this.heightOverride &&
          other.format == this.format &&
          other.createdAt == this.createdAt);
}

class BookPlacementsCompanion extends UpdateCompanion<BookPlacement> {
  final Value<String> id;
  final Value<String> environmentId;
  final Value<String> copyId;
  final Value<double> x;
  final Value<double> y;
  final Value<int> rotation;
  final Value<double?> widthOverride;
  final Value<double?> heightOverride;
  final Value<String?> format;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const BookPlacementsCompanion({
    this.id = const Value.absent(),
    this.environmentId = const Value.absent(),
    this.copyId = const Value.absent(),
    this.x = const Value.absent(),
    this.y = const Value.absent(),
    this.rotation = const Value.absent(),
    this.widthOverride = const Value.absent(),
    this.heightOverride = const Value.absent(),
    this.format = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookPlacementsCompanion.insert({
    required String id,
    required String environmentId,
    required String copyId,
    required double x,
    required double y,
    this.rotation = const Value.absent(),
    this.widthOverride = const Value.absent(),
    this.heightOverride = const Value.absent(),
    this.format = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       environmentId = Value(environmentId),
       copyId = Value(copyId),
       x = Value(x),
       y = Value(y);
  static Insertable<BookPlacement> custom({
    Expression<String>? id,
    Expression<String>? environmentId,
    Expression<String>? copyId,
    Expression<double>? x,
    Expression<double>? y,
    Expression<int>? rotation,
    Expression<double>? widthOverride,
    Expression<double>? heightOverride,
    Expression<String>? format,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (environmentId != null) 'environment_id': environmentId,
      if (copyId != null) 'copy_id': copyId,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (rotation != null) 'rotation': rotation,
      if (widthOverride != null) 'width_override': widthOverride,
      if (heightOverride != null) 'height_override': heightOverride,
      if (format != null) 'format': format,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookPlacementsCompanion copyWith({
    Value<String>? id,
    Value<String>? environmentId,
    Value<String>? copyId,
    Value<double>? x,
    Value<double>? y,
    Value<int>? rotation,
    Value<double?>? widthOverride,
    Value<double?>? heightOverride,
    Value<String?>? format,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return BookPlacementsCompanion(
      id: id ?? this.id,
      environmentId: environmentId ?? this.environmentId,
      copyId: copyId ?? this.copyId,
      x: x ?? this.x,
      y: y ?? this.y,
      rotation: rotation ?? this.rotation,
      widthOverride: widthOverride ?? this.widthOverride,
      heightOverride: heightOverride ?? this.heightOverride,
      format: format ?? this.format,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (environmentId.present) {
      map['environment_id'] = Variable<String>(environmentId.value);
    }
    if (copyId.present) {
      map['copy_id'] = Variable<String>(copyId.value);
    }
    if (x.present) {
      map['x'] = Variable<double>(x.value);
    }
    if (y.present) {
      map['y'] = Variable<double>(y.value);
    }
    if (rotation.present) {
      map['rotation'] = Variable<int>(rotation.value);
    }
    if (widthOverride.present) {
      map['width_override'] = Variable<double>(widthOverride.value);
    }
    if (heightOverride.present) {
      map['height_override'] = Variable<double>(heightOverride.value);
    }
    if (format.present) {
      map['format'] = Variable<String>(format.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookPlacementsCompanion(')
          ..write('id: $id, ')
          ..write('environmentId: $environmentId, ')
          ..write('copyId: $copyId, ')
          ..write('x: $x, ')
          ..write('y: $y, ')
          ..write('rotation: $rotation, ')
          ..write('widthOverride: $widthOverride, ')
          ..write('heightOverride: $heightOverride, ')
          ..write('format: $format, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RoomPropsTable extends RoomProps
    with TableInfo<$RoomPropsTable, RoomProp> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoomPropsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _environmentIdMeta = const VerificationMeta(
    'environmentId',
  );
  @override
  late final GeneratedColumn<String> environmentId = GeneratedColumn<String>(
    'environment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES physical_environments (id)',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _xMeta = const VerificationMeta('x');
  @override
  late final GeneratedColumn<double> x = GeneratedColumn<double>(
    'x',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _yMeta = const VerificationMeta('y');
  @override
  late final GeneratedColumn<double> y = GeneratedColumn<double>(
    'y',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _widthMMeta = const VerificationMeta('widthM');
  @override
  late final GeneratedColumn<double> widthM = GeneratedColumn<double>(
    'width_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _heightMMeta = const VerificationMeta(
    'heightM',
  );
  @override
  late final GeneratedColumn<double> heightM = GeneratedColumn<double>(
    'height_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inFrontMeta = const VerificationMeta(
    'inFront',
  );
  @override
  late final GeneratedColumn<bool> inFront = GeneratedColumn<bool>(
    'in_front',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("in_front" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    environmentId,
    kind,
    x,
    y,
    widthM,
    heightM,
    inFront,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'room_props';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoomProp> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('environment_id')) {
      context.handle(
        _environmentIdMeta,
        environmentId.isAcceptableOrUnknown(
          data['environment_id']!,
          _environmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_environmentIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('x')) {
      context.handle(_xMeta, x.isAcceptableOrUnknown(data['x']!, _xMeta));
    } else if (isInserting) {
      context.missing(_xMeta);
    }
    if (data.containsKey('y')) {
      context.handle(_yMeta, y.isAcceptableOrUnknown(data['y']!, _yMeta));
    } else if (isInserting) {
      context.missing(_yMeta);
    }
    if (data.containsKey('width_m')) {
      context.handle(
        _widthMMeta,
        widthM.isAcceptableOrUnknown(data['width_m']!, _widthMMeta),
      );
    } else if (isInserting) {
      context.missing(_widthMMeta);
    }
    if (data.containsKey('height_m')) {
      context.handle(
        _heightMMeta,
        heightM.isAcceptableOrUnknown(data['height_m']!, _heightMMeta),
      );
    } else if (isInserting) {
      context.missing(_heightMMeta);
    }
    if (data.containsKey('in_front')) {
      context.handle(
        _inFrontMeta,
        inFront.isAcceptableOrUnknown(data['in_front']!, _inFrontMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RoomProp map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoomProp(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      environmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}environment_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      x: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}x'],
      )!,
      y: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}y'],
      )!,
      widthM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}width_m'],
      )!,
      heightM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}height_m'],
      )!,
      inFront: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}in_front'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $RoomPropsTable createAlias(String alias) {
    return $RoomPropsTable(attachedDatabase, alias);
  }
}

class RoomProp extends DataClass implements Insertable<RoomProp> {
  final String id;
  final String environmentId;

  /// A [PropKind] name. Text rather than an int so a database read by an older
  /// build shows an unknown prop rather than the wrong one.
  final String kind;
  final double x;
  final double y;

  /// Its footprint in metres. Stored per prop rather than taken from the kind,
  /// so one can be made bigger or smaller without every other one changing.
  final double widthM;
  final double heightM;

  /// Whether this prop is drawn in front of the books rather than behind them.
  ///
  /// Behind is the default and the ordinary case — an ornament pushed to the
  /// back of a shelf, with the spines readable in front of it. In front is for
  /// the things that really do stand at the edge: a photo frame, a plant whose
  /// leaves fall across the books. Per prop, because a room usually wants both.
  final bool inFront;
  final DateTime createdAt;
  const RoomProp({
    required this.id,
    required this.environmentId,
    required this.kind,
    required this.x,
    required this.y,
    required this.widthM,
    required this.heightM,
    required this.inFront,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['environment_id'] = Variable<String>(environmentId);
    map['kind'] = Variable<String>(kind);
    map['x'] = Variable<double>(x);
    map['y'] = Variable<double>(y);
    map['width_m'] = Variable<double>(widthM);
    map['height_m'] = Variable<double>(heightM);
    map['in_front'] = Variable<bool>(inFront);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  RoomPropsCompanion toCompanion(bool nullToAbsent) {
    return RoomPropsCompanion(
      id: Value(id),
      environmentId: Value(environmentId),
      kind: Value(kind),
      x: Value(x),
      y: Value(y),
      widthM: Value(widthM),
      heightM: Value(heightM),
      inFront: Value(inFront),
      createdAt: Value(createdAt),
    );
  }

  factory RoomProp.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoomProp(
      id: serializer.fromJson<String>(json['id']),
      environmentId: serializer.fromJson<String>(json['environmentId']),
      kind: serializer.fromJson<String>(json['kind']),
      x: serializer.fromJson<double>(json['x']),
      y: serializer.fromJson<double>(json['y']),
      widthM: serializer.fromJson<double>(json['widthM']),
      heightM: serializer.fromJson<double>(json['heightM']),
      inFront: serializer.fromJson<bool>(json['inFront']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'environmentId': serializer.toJson<String>(environmentId),
      'kind': serializer.toJson<String>(kind),
      'x': serializer.toJson<double>(x),
      'y': serializer.toJson<double>(y),
      'widthM': serializer.toJson<double>(widthM),
      'heightM': serializer.toJson<double>(heightM),
      'inFront': serializer.toJson<bool>(inFront),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  RoomProp copyWith({
    String? id,
    String? environmentId,
    String? kind,
    double? x,
    double? y,
    double? widthM,
    double? heightM,
    bool? inFront,
    DateTime? createdAt,
  }) => RoomProp(
    id: id ?? this.id,
    environmentId: environmentId ?? this.environmentId,
    kind: kind ?? this.kind,
    x: x ?? this.x,
    y: y ?? this.y,
    widthM: widthM ?? this.widthM,
    heightM: heightM ?? this.heightM,
    inFront: inFront ?? this.inFront,
    createdAt: createdAt ?? this.createdAt,
  );
  RoomProp copyWithCompanion(RoomPropsCompanion data) {
    return RoomProp(
      id: data.id.present ? data.id.value : this.id,
      environmentId: data.environmentId.present
          ? data.environmentId.value
          : this.environmentId,
      kind: data.kind.present ? data.kind.value : this.kind,
      x: data.x.present ? data.x.value : this.x,
      y: data.y.present ? data.y.value : this.y,
      widthM: data.widthM.present ? data.widthM.value : this.widthM,
      heightM: data.heightM.present ? data.heightM.value : this.heightM,
      inFront: data.inFront.present ? data.inFront.value : this.inFront,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoomProp(')
          ..write('id: $id, ')
          ..write('environmentId: $environmentId, ')
          ..write('kind: $kind, ')
          ..write('x: $x, ')
          ..write('y: $y, ')
          ..write('widthM: $widthM, ')
          ..write('heightM: $heightM, ')
          ..write('inFront: $inFront, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    environmentId,
    kind,
    x,
    y,
    widthM,
    heightM,
    inFront,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoomProp &&
          other.id == this.id &&
          other.environmentId == this.environmentId &&
          other.kind == this.kind &&
          other.x == this.x &&
          other.y == this.y &&
          other.widthM == this.widthM &&
          other.heightM == this.heightM &&
          other.inFront == this.inFront &&
          other.createdAt == this.createdAt);
}

class RoomPropsCompanion extends UpdateCompanion<RoomProp> {
  final Value<String> id;
  final Value<String> environmentId;
  final Value<String> kind;
  final Value<double> x;
  final Value<double> y;
  final Value<double> widthM;
  final Value<double> heightM;
  final Value<bool> inFront;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const RoomPropsCompanion({
    this.id = const Value.absent(),
    this.environmentId = const Value.absent(),
    this.kind = const Value.absent(),
    this.x = const Value.absent(),
    this.y = const Value.absent(),
    this.widthM = const Value.absent(),
    this.heightM = const Value.absent(),
    this.inFront = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoomPropsCompanion.insert({
    required String id,
    required String environmentId,
    required String kind,
    required double x,
    required double y,
    required double widthM,
    required double heightM,
    this.inFront = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       environmentId = Value(environmentId),
       kind = Value(kind),
       x = Value(x),
       y = Value(y),
       widthM = Value(widthM),
       heightM = Value(heightM);
  static Insertable<RoomProp> custom({
    Expression<String>? id,
    Expression<String>? environmentId,
    Expression<String>? kind,
    Expression<double>? x,
    Expression<double>? y,
    Expression<double>? widthM,
    Expression<double>? heightM,
    Expression<bool>? inFront,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (environmentId != null) 'environment_id': environmentId,
      if (kind != null) 'kind': kind,
      if (x != null) 'x': x,
      if (y != null) 'y': y,
      if (widthM != null) 'width_m': widthM,
      if (heightM != null) 'height_m': heightM,
      if (inFront != null) 'in_front': inFront,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoomPropsCompanion copyWith({
    Value<String>? id,
    Value<String>? environmentId,
    Value<String>? kind,
    Value<double>? x,
    Value<double>? y,
    Value<double>? widthM,
    Value<double>? heightM,
    Value<bool>? inFront,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return RoomPropsCompanion(
      id: id ?? this.id,
      environmentId: environmentId ?? this.environmentId,
      kind: kind ?? this.kind,
      x: x ?? this.x,
      y: y ?? this.y,
      widthM: widthM ?? this.widthM,
      heightM: heightM ?? this.heightM,
      inFront: inFront ?? this.inFront,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (environmentId.present) {
      map['environment_id'] = Variable<String>(environmentId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (x.present) {
      map['x'] = Variable<double>(x.value);
    }
    if (y.present) {
      map['y'] = Variable<double>(y.value);
    }
    if (widthM.present) {
      map['width_m'] = Variable<double>(widthM.value);
    }
    if (heightM.present) {
      map['height_m'] = Variable<double>(heightM.value);
    }
    if (inFront.present) {
      map['in_front'] = Variable<bool>(inFront.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoomPropsCompanion(')
          ..write('id: $id, ')
          ..write('environmentId: $environmentId, ')
          ..write('kind: $kind, ')
          ..write('x: $x, ')
          ..write('y: $y, ')
          ..write('widthM: $widthM, ')
          ..write('heightM: $heightM, ')
          ..write('inFront: $inFront, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LocalDeletionsTable extends LocalDeletions
    with TableInfo<$LocalDeletionsTable, LocalDeletion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalDeletionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('book'),
  );
  @override
  List<GeneratedColumn> get $columns => [bookId, deletedAt, kind];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_deletions';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalDeletion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId};
  @override
  LocalDeletion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalDeletion(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
    );
  }

  @override
  $LocalDeletionsTable createAlias(String alias) {
    return $LocalDeletionsTable(attachedDatabase, alias);
  }
}

class LocalDeletion extends DataClass implements Insertable<LocalDeletion> {
  final String bookId;
  final DateTime deletedAt;
  final String kind;
  const LocalDeletion({
    required this.bookId,
    required this.deletedAt,
    required this.kind,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['deleted_at'] = Variable<DateTime>(deletedAt);
    map['kind'] = Variable<String>(kind);
    return map;
  }

  LocalDeletionsCompanion toCompanion(bool nullToAbsent) {
    return LocalDeletionsCompanion(
      bookId: Value(bookId),
      deletedAt: Value(deletedAt),
      kind: Value(kind),
    );
  }

  factory LocalDeletion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalDeletion(
      bookId: serializer.fromJson<String>(json['bookId']),
      deletedAt: serializer.fromJson<DateTime>(json['deletedAt']),
      kind: serializer.fromJson<String>(json['kind']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'deletedAt': serializer.toJson<DateTime>(deletedAt),
      'kind': serializer.toJson<String>(kind),
    };
  }

  LocalDeletion copyWith({String? bookId, DateTime? deletedAt, String? kind}) =>
      LocalDeletion(
        bookId: bookId ?? this.bookId,
        deletedAt: deletedAt ?? this.deletedAt,
        kind: kind ?? this.kind,
      );
  LocalDeletion copyWithCompanion(LocalDeletionsCompanion data) {
    return LocalDeletion(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      kind: data.kind.present ? data.kind.value : this.kind,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalDeletion(')
          ..write('bookId: $bookId, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('kind: $kind')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookId, deletedAt, kind);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalDeletion &&
          other.bookId == this.bookId &&
          other.deletedAt == this.deletedAt &&
          other.kind == this.kind);
}

class LocalDeletionsCompanion extends UpdateCompanion<LocalDeletion> {
  final Value<String> bookId;
  final Value<DateTime> deletedAt;
  final Value<String> kind;
  final Value<int> rowid;
  const LocalDeletionsCompanion({
    this.bookId = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.kind = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LocalDeletionsCompanion.insert({
    required String bookId,
    this.deletedAt = const Value.absent(),
    this.kind = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId);
  static Insertable<LocalDeletion> custom({
    Expression<String>? bookId,
    Expression<DateTime>? deletedAt,
    Expression<String>? kind,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (kind != null) 'kind': kind,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LocalDeletionsCompanion copyWith({
    Value<String>? bookId,
    Value<DateTime>? deletedAt,
    Value<String>? kind,
    Value<int>? rowid,
  }) {
    return LocalDeletionsCompanion(
      bookId: bookId ?? this.bookId,
      deletedAt: deletedAt ?? this.deletedAt,
      kind: kind ?? this.kind,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalDeletionsCompanion(')
          ..write('bookId: $bookId, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('kind: $kind, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RemoteReadingPositionsTable extends RemoteReadingPositions
    with TableInfo<$RemoteReadingPositionsTable, RemoteReadingPosition> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RemoteReadingPositionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceLabelMeta = const VerificationMeta(
    'deviceLabel',
  );
  @override
  late final GeneratedColumn<String> deviceLabel = GeneratedColumn<String>(
    'device_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pageMeta = const VerificationMeta('page');
  @override
  late final GeneratedColumn<int> page = GeneratedColumn<int>(
    'page',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scrollMeta = const VerificationMeta('scroll');
  @override
  late final GeneratedColumn<double> scroll = GeneratedColumn<double>(
    'scroll',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
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
    bookId,
    deviceId,
    deviceLabel,
    progress,
    page,
    unit,
    scroll,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'remote_reading_positions';
  @override
  VerificationContext validateIntegrity(
    Insertable<RemoteReadingPosition> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('device_label')) {
      context.handle(
        _deviceLabelMeta,
        deviceLabel.isAcceptableOrUnknown(
          data['device_label']!,
          _deviceLabelMeta,
        ),
      );
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    }
    if (data.containsKey('page')) {
      context.handle(
        _pageMeta,
        page.isAcceptableOrUnknown(data['page']!, _pageMeta),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('scroll')) {
      context.handle(
        _scrollMeta,
        scroll.isAcceptableOrUnknown(data['scroll']!, _scrollMeta),
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
  Set<GeneratedColumn> get $primaryKey => {bookId, deviceId};
  @override
  RemoteReadingPosition map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RemoteReadingPosition(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      deviceLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_label'],
      ),
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      ),
      page: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page'],
      ),
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      ),
      scroll: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}scroll'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $RemoteReadingPositionsTable createAlias(String alias) {
    return $RemoteReadingPositionsTable(attachedDatabase, alias);
  }
}

class RemoteReadingPosition extends DataClass
    implements Insertable<RemoteReadingPosition> {
  final String bookId;
  final String deviceId;

  /// Human label for the prompt ("desktop", "Pixel 8"); may be absent if the
  /// writing device didn't send one.
  final String? deviceLabel;
  final double? progress;
  final int? page;

  /// What [page] counts: 'page' (PDF) or 'chapter' (EPUB). A remote device may
  /// have read a different format of the same book, so the unit travels with
  /// the row instead of being inferred locally.
  final String? unit;
  final double? scroll;
  final DateTime updatedAt;
  const RemoteReadingPosition({
    required this.bookId,
    required this.deviceId,
    this.deviceLabel,
    this.progress,
    this.page,
    this.unit,
    this.scroll,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || deviceLabel != null) {
      map['device_label'] = Variable<String>(deviceLabel);
    }
    if (!nullToAbsent || progress != null) {
      map['progress'] = Variable<double>(progress);
    }
    if (!nullToAbsent || page != null) {
      map['page'] = Variable<int>(page);
    }
    if (!nullToAbsent || unit != null) {
      map['unit'] = Variable<String>(unit);
    }
    if (!nullToAbsent || scroll != null) {
      map['scroll'] = Variable<double>(scroll);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  RemoteReadingPositionsCompanion toCompanion(bool nullToAbsent) {
    return RemoteReadingPositionsCompanion(
      bookId: Value(bookId),
      deviceId: Value(deviceId),
      deviceLabel: deviceLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceLabel),
      progress: progress == null && nullToAbsent
          ? const Value.absent()
          : Value(progress),
      page: page == null && nullToAbsent ? const Value.absent() : Value(page),
      unit: unit == null && nullToAbsent ? const Value.absent() : Value(unit),
      scroll: scroll == null && nullToAbsent
          ? const Value.absent()
          : Value(scroll),
      updatedAt: Value(updatedAt),
    );
  }

  factory RemoteReadingPosition.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RemoteReadingPosition(
      bookId: serializer.fromJson<String>(json['bookId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      deviceLabel: serializer.fromJson<String?>(json['deviceLabel']),
      progress: serializer.fromJson<double?>(json['progress']),
      page: serializer.fromJson<int?>(json['page']),
      unit: serializer.fromJson<String?>(json['unit']),
      scroll: serializer.fromJson<double?>(json['scroll']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'deviceId': serializer.toJson<String>(deviceId),
      'deviceLabel': serializer.toJson<String?>(deviceLabel),
      'progress': serializer.toJson<double?>(progress),
      'page': serializer.toJson<int?>(page),
      'unit': serializer.toJson<String?>(unit),
      'scroll': serializer.toJson<double?>(scroll),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  RemoteReadingPosition copyWith({
    String? bookId,
    String? deviceId,
    Value<String?> deviceLabel = const Value.absent(),
    Value<double?> progress = const Value.absent(),
    Value<int?> page = const Value.absent(),
    Value<String?> unit = const Value.absent(),
    Value<double?> scroll = const Value.absent(),
    DateTime? updatedAt,
  }) => RemoteReadingPosition(
    bookId: bookId ?? this.bookId,
    deviceId: deviceId ?? this.deviceId,
    deviceLabel: deviceLabel.present ? deviceLabel.value : this.deviceLabel,
    progress: progress.present ? progress.value : this.progress,
    page: page.present ? page.value : this.page,
    unit: unit.present ? unit.value : this.unit,
    scroll: scroll.present ? scroll.value : this.scroll,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  RemoteReadingPosition copyWithCompanion(
    RemoteReadingPositionsCompanion data,
  ) {
    return RemoteReadingPosition(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      deviceLabel: data.deviceLabel.present
          ? data.deviceLabel.value
          : this.deviceLabel,
      progress: data.progress.present ? data.progress.value : this.progress,
      page: data.page.present ? data.page.value : this.page,
      unit: data.unit.present ? data.unit.value : this.unit,
      scroll: data.scroll.present ? data.scroll.value : this.scroll,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RemoteReadingPosition(')
          ..write('bookId: $bookId, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceLabel: $deviceLabel, ')
          ..write('progress: $progress, ')
          ..write('page: $page, ')
          ..write('unit: $unit, ')
          ..write('scroll: $scroll, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bookId,
    deviceId,
    deviceLabel,
    progress,
    page,
    unit,
    scroll,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteReadingPosition &&
          other.bookId == this.bookId &&
          other.deviceId == this.deviceId &&
          other.deviceLabel == this.deviceLabel &&
          other.progress == this.progress &&
          other.page == this.page &&
          other.unit == this.unit &&
          other.scroll == this.scroll &&
          other.updatedAt == this.updatedAt);
}

class RemoteReadingPositionsCompanion
    extends UpdateCompanion<RemoteReadingPosition> {
  final Value<String> bookId;
  final Value<String> deviceId;
  final Value<String?> deviceLabel;
  final Value<double?> progress;
  final Value<int?> page;
  final Value<String?> unit;
  final Value<double?> scroll;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const RemoteReadingPositionsCompanion({
    this.bookId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.deviceLabel = const Value.absent(),
    this.progress = const Value.absent(),
    this.page = const Value.absent(),
    this.unit = const Value.absent(),
    this.scroll = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RemoteReadingPositionsCompanion.insert({
    required String bookId,
    required String deviceId,
    this.deviceLabel = const Value.absent(),
    this.progress = const Value.absent(),
    this.page = const Value.absent(),
    this.unit = const Value.absent(),
    this.scroll = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       deviceId = Value(deviceId),
       updatedAt = Value(updatedAt);
  static Insertable<RemoteReadingPosition> custom({
    Expression<String>? bookId,
    Expression<String>? deviceId,
    Expression<String>? deviceLabel,
    Expression<double>? progress,
    Expression<int>? page,
    Expression<String>? unit,
    Expression<double>? scroll,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (deviceId != null) 'device_id': deviceId,
      if (deviceLabel != null) 'device_label': deviceLabel,
      if (progress != null) 'progress': progress,
      if (page != null) 'page': page,
      if (unit != null) 'unit': unit,
      if (scroll != null) 'scroll': scroll,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RemoteReadingPositionsCompanion copyWith({
    Value<String>? bookId,
    Value<String>? deviceId,
    Value<String?>? deviceLabel,
    Value<double?>? progress,
    Value<int?>? page,
    Value<String?>? unit,
    Value<double?>? scroll,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return RemoteReadingPositionsCompanion(
      bookId: bookId ?? this.bookId,
      deviceId: deviceId ?? this.deviceId,
      deviceLabel: deviceLabel ?? this.deviceLabel,
      progress: progress ?? this.progress,
      page: page ?? this.page,
      unit: unit ?? this.unit,
      scroll: scroll ?? this.scroll,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (deviceLabel.present) {
      map['device_label'] = Variable<String>(deviceLabel.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (page.present) {
      map['page'] = Variable<int>(page.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (scroll.present) {
      map['scroll'] = Variable<double>(scroll.value);
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
    return (StringBuffer('RemoteReadingPositionsCompanion(')
          ..write('bookId: $bookId, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceLabel: $deviceLabel, ')
          ..write('progress: $progress, ')
          ..write('page: $page, ')
          ..write('unit: $unit, ')
          ..write('scroll: $scroll, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AnnotationsTable extends Annotations
    with TableInfo<$AnnotationsTable, Annotation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnnotationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id)',
    ),
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageMeta = const VerificationMeta('page');
  @override
  late final GeneratedColumn<int> page = GeneratedColumn<int>(
    'page',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chapterMeta = const VerificationMeta(
    'chapter',
  );
  @override
  late final GeneratedColumn<int> chapter = GeneratedColumn<int>(
    'chapter',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locatorMeta = const VerificationMeta(
    'locator',
  );
  @override
  late final GeneratedColumn<String> locator = GeneratedColumn<String>(
    'locator',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _quotedTextMeta = const VerificationMeta(
    'quotedText',
  );
  @override
  late final GeneratedColumn<String> quotedText = GeneratedColumn<String>(
    'quoted_text',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
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
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _needsPushMeta = const VerificationMeta(
    'needsPush',
  );
  @override
  late final GeneratedColumn<bool> needsPush = GeneratedColumn<bool>(
    'needs_push',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_push" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    kind,
    page,
    chapter,
    locator,
    quotedText,
    note,
    color,
    createdAt,
    updatedAt,
    needsPush,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'annotations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Annotation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('page')) {
      context.handle(
        _pageMeta,
        page.isAcceptableOrUnknown(data['page']!, _pageMeta),
      );
    }
    if (data.containsKey('chapter')) {
      context.handle(
        _chapterMeta,
        chapter.isAcceptableOrUnknown(data['chapter']!, _chapterMeta),
      );
    }
    if (data.containsKey('locator')) {
      context.handle(
        _locatorMeta,
        locator.isAcceptableOrUnknown(data['locator']!, _locatorMeta),
      );
    }
    if (data.containsKey('quoted_text')) {
      context.handle(
        _quotedTextMeta,
        quotedText.isAcceptableOrUnknown(data['quoted_text']!, _quotedTextMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('needs_push')) {
      context.handle(
        _needsPushMeta,
        needsPush.isAcceptableOrUnknown(data['needs_push']!, _needsPushMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Annotation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Annotation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      page: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}page'],
      ),
      chapter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chapter'],
      ),
      locator: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}locator'],
      ),
      quotedText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quoted_text'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      needsPush: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_push'],
      )!,
    );
  }

  @override
  $AnnotationsTable createAlias(String alias) {
    return $AnnotationsTable(attachedDatabase, alias);
  }
}

class Annotation extends DataClass implements Insertable<Annotation> {
  final String id;
  final String bookId;

  /// 'bookmark' | 'highlight' | 'note'.
  final String kind;

  /// Coarse location, kept as columns (not only inside [locator]) so the panel
  /// can order and group without parsing JSON: the PDF page or the EPUB chapter.
  final int? page;
  final int? chapter;

  /// Fine location as versioned JSON — see `annotation_locator.dart`. Versioned
  /// because the EPUB offsets depend on this app's own text extraction, so a
  /// parser change must be able to migrate them rather than orphan them.
  final String? locator;
  final String? quotedText;
  final String? note;

  /// Highlight colour as an ARGB int, or null for the default.
  final int? color;
  final DateTime createdAt;

  /// Last-write-wins key, and what a delta pull compares against. Bumped on
  /// every edit — recolouring a highlight or rewriting a note both count.
  final DateTime updatedAt;

  /// Waiting to be pushed. Same convention as every other synced table: set on
  /// local write, cleared once the server has it.
  final bool needsPush;
  const Annotation({
    required this.id,
    required this.bookId,
    required this.kind,
    this.page,
    this.chapter,
    this.locator,
    this.quotedText,
    this.note,
    this.color,
    required this.createdAt,
    required this.updatedAt,
    required this.needsPush,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['kind'] = Variable<String>(kind);
    if (!nullToAbsent || page != null) {
      map['page'] = Variable<int>(page);
    }
    if (!nullToAbsent || chapter != null) {
      map['chapter'] = Variable<int>(chapter);
    }
    if (!nullToAbsent || locator != null) {
      map['locator'] = Variable<String>(locator);
    }
    if (!nullToAbsent || quotedText != null) {
      map['quoted_text'] = Variable<String>(quotedText);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || color != null) {
      map['color'] = Variable<int>(color);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['needs_push'] = Variable<bool>(needsPush);
    return map;
  }

  AnnotationsCompanion toCompanion(bool nullToAbsent) {
    return AnnotationsCompanion(
      id: Value(id),
      bookId: Value(bookId),
      kind: Value(kind),
      page: page == null && nullToAbsent ? const Value.absent() : Value(page),
      chapter: chapter == null && nullToAbsent
          ? const Value.absent()
          : Value(chapter),
      locator: locator == null && nullToAbsent
          ? const Value.absent()
          : Value(locator),
      quotedText: quotedText == null && nullToAbsent
          ? const Value.absent()
          : Value(quotedText),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      color: color == null && nullToAbsent
          ? const Value.absent()
          : Value(color),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      needsPush: Value(needsPush),
    );
  }

  factory Annotation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Annotation(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      kind: serializer.fromJson<String>(json['kind']),
      page: serializer.fromJson<int?>(json['page']),
      chapter: serializer.fromJson<int?>(json['chapter']),
      locator: serializer.fromJson<String?>(json['locator']),
      quotedText: serializer.fromJson<String?>(json['quotedText']),
      note: serializer.fromJson<String?>(json['note']),
      color: serializer.fromJson<int?>(json['color']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      needsPush: serializer.fromJson<bool>(json['needsPush']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'kind': serializer.toJson<String>(kind),
      'page': serializer.toJson<int?>(page),
      'chapter': serializer.toJson<int?>(chapter),
      'locator': serializer.toJson<String?>(locator),
      'quotedText': serializer.toJson<String?>(quotedText),
      'note': serializer.toJson<String?>(note),
      'color': serializer.toJson<int?>(color),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'needsPush': serializer.toJson<bool>(needsPush),
    };
  }

  Annotation copyWith({
    String? id,
    String? bookId,
    String? kind,
    Value<int?> page = const Value.absent(),
    Value<int?> chapter = const Value.absent(),
    Value<String?> locator = const Value.absent(),
    Value<String?> quotedText = const Value.absent(),
    Value<String?> note = const Value.absent(),
    Value<int?> color = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? needsPush,
  }) => Annotation(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    kind: kind ?? this.kind,
    page: page.present ? page.value : this.page,
    chapter: chapter.present ? chapter.value : this.chapter,
    locator: locator.present ? locator.value : this.locator,
    quotedText: quotedText.present ? quotedText.value : this.quotedText,
    note: note.present ? note.value : this.note,
    color: color.present ? color.value : this.color,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    needsPush: needsPush ?? this.needsPush,
  );
  Annotation copyWithCompanion(AnnotationsCompanion data) {
    return Annotation(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      kind: data.kind.present ? data.kind.value : this.kind,
      page: data.page.present ? data.page.value : this.page,
      chapter: data.chapter.present ? data.chapter.value : this.chapter,
      locator: data.locator.present ? data.locator.value : this.locator,
      quotedText: data.quotedText.present
          ? data.quotedText.value
          : this.quotedText,
      note: data.note.present ? data.note.value : this.note,
      color: data.color.present ? data.color.value : this.color,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      needsPush: data.needsPush.present ? data.needsPush.value : this.needsPush,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Annotation(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('kind: $kind, ')
          ..write('page: $page, ')
          ..write('chapter: $chapter, ')
          ..write('locator: $locator, ')
          ..write('quotedText: $quotedText, ')
          ..write('note: $note, ')
          ..write('color: $color, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('needsPush: $needsPush')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    kind,
    page,
    chapter,
    locator,
    quotedText,
    note,
    color,
    createdAt,
    updatedAt,
    needsPush,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Annotation &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.kind == this.kind &&
          other.page == this.page &&
          other.chapter == this.chapter &&
          other.locator == this.locator &&
          other.quotedText == this.quotedText &&
          other.note == this.note &&
          other.color == this.color &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.needsPush == this.needsPush);
}

class AnnotationsCompanion extends UpdateCompanion<Annotation> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<String> kind;
  final Value<int?> page;
  final Value<int?> chapter;
  final Value<String?> locator;
  final Value<String?> quotedText;
  final Value<String?> note;
  final Value<int?> color;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> needsPush;
  final Value<int> rowid;
  const AnnotationsCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.kind = const Value.absent(),
    this.page = const Value.absent(),
    this.chapter = const Value.absent(),
    this.locator = const Value.absent(),
    this.quotedText = const Value.absent(),
    this.note = const Value.absent(),
    this.color = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnnotationsCompanion.insert({
    required String id,
    required String bookId,
    required String kind,
    this.page = const Value.absent(),
    this.chapter = const Value.absent(),
    this.locator = const Value.absent(),
    this.quotedText = const Value.absent(),
    this.note = const Value.absent(),
    this.color = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId),
       kind = Value(kind);
  static Insertable<Annotation> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<String>? kind,
    Expression<int>? page,
    Expression<int>? chapter,
    Expression<String>? locator,
    Expression<String>? quotedText,
    Expression<String>? note,
    Expression<int>? color,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? needsPush,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (kind != null) 'kind': kind,
      if (page != null) 'page': page,
      if (chapter != null) 'chapter': chapter,
      if (locator != null) 'locator': locator,
      if (quotedText != null) 'quoted_text': quotedText,
      if (note != null) 'note': note,
      if (color != null) 'color': color,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (needsPush != null) 'needs_push': needsPush,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AnnotationsCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<String>? kind,
    Value<int?>? page,
    Value<int?>? chapter,
    Value<String?>? locator,
    Value<String?>? quotedText,
    Value<String?>? note,
    Value<int?>? color,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? needsPush,
    Value<int>? rowid,
  }) {
    return AnnotationsCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      kind: kind ?? this.kind,
      page: page ?? this.page,
      chapter: chapter ?? this.chapter,
      locator: locator ?? this.locator,
      quotedText: quotedText ?? this.quotedText,
      note: note ?? this.note,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      needsPush: needsPush ?? this.needsPush,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (page.present) {
      map['page'] = Variable<int>(page.value);
    }
    if (chapter.present) {
      map['chapter'] = Variable<int>(chapter.value);
    }
    if (locator.present) {
      map['locator'] = Variable<String>(locator.value);
    }
    if (quotedText.present) {
      map['quoted_text'] = Variable<String>(quotedText.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (needsPush.present) {
      map['needs_push'] = Variable<bool>(needsPush.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnnotationsCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('kind: $kind, ')
          ..write('page: $page, ')
          ..write('chapter: $chapter, ')
          ..write('locator: $locator, ')
          ..write('quotedText: $quotedText, ')
          ..write('note: $note, ')
          ..write('color: $color, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('needsPush: $needsPush, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReadingSessionsTable extends ReadingSessions
    with TableInfo<$ReadingSessionsTable, ReadingSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReadingSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id)',
    ),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startPageMeta = const VerificationMeta(
    'startPage',
  );
  @override
  late final GeneratedColumn<int> startPage = GeneratedColumn<int>(
    'start_page',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _endPageMeta = const VerificationMeta(
    'endPage',
  );
  @override
  late final GeneratedColumn<int> endPage = GeneratedColumn<int>(
    'end_page',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _deviceLabelMeta = const VerificationMeta(
    'deviceLabel',
  );
  @override
  late final GeneratedColumn<String> deviceLabel = GeneratedColumn<String>(
    'device_label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _needsPushMeta = const VerificationMeta(
    'needsPush',
  );
  @override
  late final GeneratedColumn<bool> needsPush = GeneratedColumn<bool>(
    'needs_push',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_push" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    bookId,
    startedAt,
    endedAt,
    startPage,
    endPage,
    deviceId,
    deviceLabel,
    needsPush,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'reading_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReadingSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_endedAtMeta);
    }
    if (data.containsKey('start_page')) {
      context.handle(
        _startPageMeta,
        startPage.isAcceptableOrUnknown(data['start_page']!, _startPageMeta),
      );
    }
    if (data.containsKey('end_page')) {
      context.handle(
        _endPageMeta,
        endPage.isAcceptableOrUnknown(data['end_page']!, _endPageMeta),
      );
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('device_label')) {
      context.handle(
        _deviceLabelMeta,
        deviceLabel.isAcceptableOrUnknown(
          data['device_label']!,
          _deviceLabelMeta,
        ),
      );
    }
    if (data.containsKey('needs_push')) {
      context.handle(
        _needsPushMeta,
        needsPush.isAcceptableOrUnknown(data['needs_push']!, _needsPushMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReadingSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReadingSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      )!,
      startPage: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}start_page'],
      ),
      endPage: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}end_page'],
      ),
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      ),
      deviceLabel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_label'],
      ),
      needsPush: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_push'],
      )!,
    );
  }

  @override
  $ReadingSessionsTable createAlias(String alias) {
    return $ReadingSessionsTable(attachedDatabase, alias);
  }
}

class ReadingSession extends DataClass implements Insertable<ReadingSession> {
  final String id;
  final String bookId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int? startPage;
  final int? endPage;

  /// Which device this sitting happened on, so statistics can still answer
  /// "where do I actually read" once they span three of them.
  final String? deviceId;
  final String? deviceLabel;

  /// Waiting to be pushed. A session is an immutable fact, so this is only ever
  /// set once — there is no edit to re-push and no conflict to resolve.
  final bool needsPush;
  const ReadingSession({
    required this.id,
    required this.bookId,
    required this.startedAt,
    required this.endedAt,
    this.startPage,
    this.endPage,
    this.deviceId,
    this.deviceLabel,
    required this.needsPush,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['book_id'] = Variable<String>(bookId);
    map['started_at'] = Variable<DateTime>(startedAt);
    map['ended_at'] = Variable<DateTime>(endedAt);
    if (!nullToAbsent || startPage != null) {
      map['start_page'] = Variable<int>(startPage);
    }
    if (!nullToAbsent || endPage != null) {
      map['end_page'] = Variable<int>(endPage);
    }
    if (!nullToAbsent || deviceId != null) {
      map['device_id'] = Variable<String>(deviceId);
    }
    if (!nullToAbsent || deviceLabel != null) {
      map['device_label'] = Variable<String>(deviceLabel);
    }
    map['needs_push'] = Variable<bool>(needsPush);
    return map;
  }

  ReadingSessionsCompanion toCompanion(bool nullToAbsent) {
    return ReadingSessionsCompanion(
      id: Value(id),
      bookId: Value(bookId),
      startedAt: Value(startedAt),
      endedAt: Value(endedAt),
      startPage: startPage == null && nullToAbsent
          ? const Value.absent()
          : Value(startPage),
      endPage: endPage == null && nullToAbsent
          ? const Value.absent()
          : Value(endPage),
      deviceId: deviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceId),
      deviceLabel: deviceLabel == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceLabel),
      needsPush: Value(needsPush),
    );
  }

  factory ReadingSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReadingSession(
      id: serializer.fromJson<String>(json['id']),
      bookId: serializer.fromJson<String>(json['bookId']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime>(json['endedAt']),
      startPage: serializer.fromJson<int?>(json['startPage']),
      endPage: serializer.fromJson<int?>(json['endPage']),
      deviceId: serializer.fromJson<String?>(json['deviceId']),
      deviceLabel: serializer.fromJson<String?>(json['deviceLabel']),
      needsPush: serializer.fromJson<bool>(json['needsPush']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'bookId': serializer.toJson<String>(bookId),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime>(endedAt),
      'startPage': serializer.toJson<int?>(startPage),
      'endPage': serializer.toJson<int?>(endPage),
      'deviceId': serializer.toJson<String?>(deviceId),
      'deviceLabel': serializer.toJson<String?>(deviceLabel),
      'needsPush': serializer.toJson<bool>(needsPush),
    };
  }

  ReadingSession copyWith({
    String? id,
    String? bookId,
    DateTime? startedAt,
    DateTime? endedAt,
    Value<int?> startPage = const Value.absent(),
    Value<int?> endPage = const Value.absent(),
    Value<String?> deviceId = const Value.absent(),
    Value<String?> deviceLabel = const Value.absent(),
    bool? needsPush,
  }) => ReadingSession(
    id: id ?? this.id,
    bookId: bookId ?? this.bookId,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    startPage: startPage.present ? startPage.value : this.startPage,
    endPage: endPage.present ? endPage.value : this.endPage,
    deviceId: deviceId.present ? deviceId.value : this.deviceId,
    deviceLabel: deviceLabel.present ? deviceLabel.value : this.deviceLabel,
    needsPush: needsPush ?? this.needsPush,
  );
  ReadingSession copyWithCompanion(ReadingSessionsCompanion data) {
    return ReadingSession(
      id: data.id.present ? data.id.value : this.id,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      startPage: data.startPage.present ? data.startPage.value : this.startPage,
      endPage: data.endPage.present ? data.endPage.value : this.endPage,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      deviceLabel: data.deviceLabel.present
          ? data.deviceLabel.value
          : this.deviceLabel,
      needsPush: data.needsPush.present ? data.needsPush.value : this.needsPush,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReadingSession(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('startPage: $startPage, ')
          ..write('endPage: $endPage, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceLabel: $deviceLabel, ')
          ..write('needsPush: $needsPush')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    bookId,
    startedAt,
    endedAt,
    startPage,
    endPage,
    deviceId,
    deviceLabel,
    needsPush,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReadingSession &&
          other.id == this.id &&
          other.bookId == this.bookId &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.startPage == this.startPage &&
          other.endPage == this.endPage &&
          other.deviceId == this.deviceId &&
          other.deviceLabel == this.deviceLabel &&
          other.needsPush == this.needsPush);
}

class ReadingSessionsCompanion extends UpdateCompanion<ReadingSession> {
  final Value<String> id;
  final Value<String> bookId;
  final Value<DateTime> startedAt;
  final Value<DateTime> endedAt;
  final Value<int?> startPage;
  final Value<int?> endPage;
  final Value<String?> deviceId;
  final Value<String?> deviceLabel;
  final Value<bool> needsPush;
  final Value<int> rowid;
  const ReadingSessionsCompanion({
    this.id = const Value.absent(),
    this.bookId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.startPage = const Value.absent(),
    this.endPage = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.deviceLabel = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReadingSessionsCompanion.insert({
    required String id,
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
    this.startPage = const Value.absent(),
    this.endPage = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.deviceLabel = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       bookId = Value(bookId),
       startedAt = Value(startedAt),
       endedAt = Value(endedAt);
  static Insertable<ReadingSession> custom({
    Expression<String>? id,
    Expression<String>? bookId,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<int>? startPage,
    Expression<int>? endPage,
    Expression<String>? deviceId,
    Expression<String>? deviceLabel,
    Expression<bool>? needsPush,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (bookId != null) 'book_id': bookId,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (startPage != null) 'start_page': startPage,
      if (endPage != null) 'end_page': endPage,
      if (deviceId != null) 'device_id': deviceId,
      if (deviceLabel != null) 'device_label': deviceLabel,
      if (needsPush != null) 'needs_push': needsPush,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReadingSessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? bookId,
    Value<DateTime>? startedAt,
    Value<DateTime>? endedAt,
    Value<int?>? startPage,
    Value<int?>? endPage,
    Value<String?>? deviceId,
    Value<String?>? deviceLabel,
    Value<bool>? needsPush,
    Value<int>? rowid,
  }) {
    return ReadingSessionsCompanion(
      id: id ?? this.id,
      bookId: bookId ?? this.bookId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      startPage: startPage ?? this.startPage,
      endPage: endPage ?? this.endPage,
      deviceId: deviceId ?? this.deviceId,
      deviceLabel: deviceLabel ?? this.deviceLabel,
      needsPush: needsPush ?? this.needsPush,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (startPage.present) {
      map['start_page'] = Variable<int>(startPage.value);
    }
    if (endPage.present) {
      map['end_page'] = Variable<int>(endPage.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (deviceLabel.present) {
      map['device_label'] = Variable<String>(deviceLabel.value);
    }
    if (needsPush.present) {
      map['needs_push'] = Variable<bool>(needsPush.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReadingSessionsCompanion(')
          ..write('id: $id, ')
          ..write('bookId: $bookId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('startPage: $startPage, ')
          ..write('endPage: $endPage, ')
          ..write('deviceId: $deviceId, ')
          ..write('deviceLabel: $deviceLabel, ')
          ..write('needsPush: $needsPush, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookTextsTable extends BookTexts
    with TableInfo<$BookTextsTable, BookText> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookTextsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fileIdMeta = const VerificationMeta('fileId');
  @override
  late final GeneratedColumn<String> fileId = GeneratedColumn<String>(
    'file_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES book_files (id)',
    ),
  );
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES books (id)',
    ),
  );
  static const VerificationMeta _pagesMeta = const VerificationMeta('pages');
  @override
  late final GeneratedColumn<int> pages = GeneratedColumn<int>(
    'pages',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extractedAtMeta = const VerificationMeta(
    'extractedAt',
  );
  @override
  late final GeneratedColumn<DateTime> extractedAt = GeneratedColumn<DateTime>(
    'extracted_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    fileId,
    bookId,
    pages,
    extractedAt,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'book_text';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookText> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('file_id')) {
      context.handle(
        _fileIdMeta,
        fileId.isAcceptableOrUnknown(data['file_id']!, _fileIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fileIdMeta);
    }
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('pages')) {
      context.handle(
        _pagesMeta,
        pages.isAcceptableOrUnknown(data['pages']!, _pagesMeta),
      );
    }
    if (data.containsKey('extracted_at')) {
      context.handle(
        _extractedAtMeta,
        extractedAt.isAcceptableOrUnknown(
          data['extracted_at']!,
          _extractedAtMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fileId};
  @override
  BookText map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookText(
      fileId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_id'],
      )!,
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      pages: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pages'],
      ),
      extractedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}extracted_at'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $BookTextsTable createAlias(String alias) {
    return $BookTextsTable(attachedDatabase, alias);
  }
}

class BookText extends DataClass implements Insertable<BookText> {
  final String fileId;
  final String bookId;

  /// How many page/section rows were indexed, or null until extraction runs.
  final int? pages;
  final DateTime extractedAt;

  /// 'pending' | 'ok' | 'no_text' | 'failed' | 'skipped'.
  ///
  /// `no_text` is a scanned PDF — a real outcome rather than a failure, and
  /// the same position the server takes: there is no OCR here either.
  final String status;
  const BookText({
    required this.fileId,
    required this.bookId,
    this.pages,
    required this.extractedAt,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['file_id'] = Variable<String>(fileId);
    map['book_id'] = Variable<String>(bookId);
    if (!nullToAbsent || pages != null) {
      map['pages'] = Variable<int>(pages);
    }
    map['extracted_at'] = Variable<DateTime>(extractedAt);
    map['status'] = Variable<String>(status);
    return map;
  }

  BookTextsCompanion toCompanion(bool nullToAbsent) {
    return BookTextsCompanion(
      fileId: Value(fileId),
      bookId: Value(bookId),
      pages: pages == null && nullToAbsent
          ? const Value.absent()
          : Value(pages),
      extractedAt: Value(extractedAt),
      status: Value(status),
    );
  }

  factory BookText.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookText(
      fileId: serializer.fromJson<String>(json['fileId']),
      bookId: serializer.fromJson<String>(json['bookId']),
      pages: serializer.fromJson<int?>(json['pages']),
      extractedAt: serializer.fromJson<DateTime>(json['extractedAt']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fileId': serializer.toJson<String>(fileId),
      'bookId': serializer.toJson<String>(bookId),
      'pages': serializer.toJson<int?>(pages),
      'extractedAt': serializer.toJson<DateTime>(extractedAt),
      'status': serializer.toJson<String>(status),
    };
  }

  BookText copyWith({
    String? fileId,
    String? bookId,
    Value<int?> pages = const Value.absent(),
    DateTime? extractedAt,
    String? status,
  }) => BookText(
    fileId: fileId ?? this.fileId,
    bookId: bookId ?? this.bookId,
    pages: pages.present ? pages.value : this.pages,
    extractedAt: extractedAt ?? this.extractedAt,
    status: status ?? this.status,
  );
  BookText copyWithCompanion(BookTextsCompanion data) {
    return BookText(
      fileId: data.fileId.present ? data.fileId.value : this.fileId,
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      pages: data.pages.present ? data.pages.value : this.pages,
      extractedAt: data.extractedAt.present
          ? data.extractedAt.value
          : this.extractedAt,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookText(')
          ..write('fileId: $fileId, ')
          ..write('bookId: $bookId, ')
          ..write('pages: $pages, ')
          ..write('extractedAt: $extractedAt, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(fileId, bookId, pages, extractedAt, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookText &&
          other.fileId == this.fileId &&
          other.bookId == this.bookId &&
          other.pages == this.pages &&
          other.extractedAt == this.extractedAt &&
          other.status == this.status);
}

class BookTextsCompanion extends UpdateCompanion<BookText> {
  final Value<String> fileId;
  final Value<String> bookId;
  final Value<int?> pages;
  final Value<DateTime> extractedAt;
  final Value<String> status;
  final Value<int> rowid;
  const BookTextsCompanion({
    this.fileId = const Value.absent(),
    this.bookId = const Value.absent(),
    this.pages = const Value.absent(),
    this.extractedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookTextsCompanion.insert({
    required String fileId,
    required String bookId,
    this.pages = const Value.absent(),
    this.extractedAt = const Value.absent(),
    required String status,
    this.rowid = const Value.absent(),
  }) : fileId = Value(fileId),
       bookId = Value(bookId),
       status = Value(status);
  static Insertable<BookText> custom({
    Expression<String>? fileId,
    Expression<String>? bookId,
    Expression<int>? pages,
    Expression<DateTime>? extractedAt,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (fileId != null) 'file_id': fileId,
      if (bookId != null) 'book_id': bookId,
      if (pages != null) 'pages': pages,
      if (extractedAt != null) 'extracted_at': extractedAt,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookTextsCompanion copyWith({
    Value<String>? fileId,
    Value<String>? bookId,
    Value<int?>? pages,
    Value<DateTime>? extractedAt,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return BookTextsCompanion(
      fileId: fileId ?? this.fileId,
      bookId: bookId ?? this.bookId,
      pages: pages ?? this.pages,
      extractedAt: extractedAt ?? this.extractedAt,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fileId.present) {
      map['file_id'] = Variable<String>(fileId.value);
    }
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (pages.present) {
      map['pages'] = Variable<int>(pages.value);
    }
    if (extractedAt.present) {
      map['extracted_at'] = Variable<DateTime>(extractedAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookTextsCompanion(')
          ..write('fileId: $fileId, ')
          ..write('bookId: $bookId, ')
          ..write('pages: $pages, ')
          ..write('extractedAt: $extractedAt, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$VellumDatabase extends GeneratedDatabase {
  _$VellumDatabase(QueryExecutor e) : super(e);
  $VellumDatabaseManager get managers => $VellumDatabaseManager(this);
  late final $SeriesTable series = $SeriesTable(this);
  late final $BooksTable books = $BooksTable(this);
  late final $AuthorsTable authors = $AuthorsTable(this);
  late final $BookAuthorsTable bookAuthors = $BookAuthorsTable(this);
  late final $GenresTable genres = $GenresTable(this);
  late final $BookGenresTable bookGenres = $BookGenresTable(this);
  late final $BookFilesTable bookFiles = $BookFilesTable(this);
  late final $PhysicalCopiesTable physicalCopies = $PhysicalCopiesTable(this);
  late final $LoansTable loans = $LoansTable(this);
  late final $CopyPhotosTable copyPhotos = $CopyPhotosTable(this);
  late final $ShelvesTable shelves = $ShelvesTable(this);
  late final $ShelfBooksTable shelfBooks = $ShelfBooksTable(this);
  late final $PhysicalEnvironmentsTable physicalEnvironments =
      $PhysicalEnvironmentsTable(this);
  late final $PhysicalShelvesTable physicalShelves = $PhysicalShelvesTable(
    this,
  );
  late final $BookPlacementsTable bookPlacements = $BookPlacementsTable(this);
  late final $RoomPropsTable roomProps = $RoomPropsTable(this);
  late final $LocalDeletionsTable localDeletions = $LocalDeletionsTable(this);
  late final $RemoteReadingPositionsTable remoteReadingPositions =
      $RemoteReadingPositionsTable(this);
  late final $AnnotationsTable annotations = $AnnotationsTable(this);
  late final $ReadingSessionsTable readingSessions = $ReadingSessionsTable(
    this,
  );
  late final $BookTextsTable bookTexts = $BookTextsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    series,
    books,
    authors,
    bookAuthors,
    genres,
    bookGenres,
    bookFiles,
    physicalCopies,
    loans,
    copyPhotos,
    shelves,
    shelfBooks,
    physicalEnvironments,
    physicalShelves,
    bookPlacements,
    roomProps,
    localDeletions,
    remoteReadingPositions,
    annotations,
    readingSessions,
    bookTexts,
  ];
}

typedef $$SeriesTableCreateCompanionBuilder =
    SeriesCompanion Function({
      required String id,
      required String name,
      Value<int> rowid,
    });
typedef $$SeriesTableUpdateCompanionBuilder =
    SeriesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> rowid,
    });

final class $$SeriesTableReferences
    extends BaseReferences<_$VellumDatabase, $SeriesTable, Sery> {
  $$SeriesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BooksTable, List<Book>> _booksRefsTable(
    _$VellumDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.books,
    aliasName: 'series__id__books__series_id',
  );

  $$BooksTableProcessedTableManager get booksRefs {
    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.seriesId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_booksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SeriesTableFilterComposer
    extends Composer<_$VellumDatabase, $SeriesTable> {
  $$SeriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> booksRefs(
    Expression<bool> Function($$BooksTableFilterComposer f) f,
  ) {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.seriesId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SeriesTableOrderingComposer
    extends Composer<_$VellumDatabase, $SeriesTable> {
  $$SeriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeriesTableAnnotationComposer
    extends Composer<_$VellumDatabase, $SeriesTable> {
  $$SeriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  Expression<T> booksRefs<T extends Object>(
    Expression<T> Function($$BooksTableAnnotationComposer a) f,
  ) {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.seriesId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SeriesTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $SeriesTable,
          Sery,
          $$SeriesTableFilterComposer,
          $$SeriesTableOrderingComposer,
          $$SeriesTableAnnotationComposer,
          $$SeriesTableCreateCompanionBuilder,
          $$SeriesTableUpdateCompanionBuilder,
          (Sery, $$SeriesTableReferences),
          Sery,
          PrefetchHooks Function({bool booksRefs})
        > {
  $$SeriesTableTableManager(_$VellumDatabase db, $SeriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SeriesCompanion(id: id, name: name, rowid: rowid),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> rowid = const Value.absent(),
              }) => SeriesCompanion.insert(id: id, name: name, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$SeriesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({booksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (booksRefs) db.books],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (booksRefs)
                    await $_getPrefetchedData<Sery, $SeriesTable, Book>(
                      currentTable: table,
                      referencedTable: $$SeriesTableReferences._booksRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$SeriesTableReferences(db, table, p0).booksRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.seriesId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SeriesTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $SeriesTable,
      Sery,
      $$SeriesTableFilterComposer,
      $$SeriesTableOrderingComposer,
      $$SeriesTableAnnotationComposer,
      $$SeriesTableCreateCompanionBuilder,
      $$SeriesTableUpdateCompanionBuilder,
      (Sery, $$SeriesTableReferences),
      Sery,
      PrefetchHooks Function({bool booksRefs})
    >;
typedef $$BooksTableCreateCompanionBuilder =
    BooksCompanion Function({
      required String id,
      required String title,
      Value<String?> subtitle,
      Value<String?> description,
      Value<String?> isbn,
      Value<String?> publisher,
      Value<int?> publishedYear,
      Value<int?> pageCount,
      Value<String?> coverPath,
      Value<String?> spineStyle,
      Value<String?> seriesId,
      Value<double?> seriesIndex,
      Value<double?> readingProgress,
      Value<int?> lastReadPage,
      Value<DateTime?> lastReadAt,
      Value<String?> readerNotes,
      Value<DateTime?> readerNotesUpdatedAt,
      Value<bool> readerNotesNeedsPush,
      Value<String?> sourceMetadata,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> needsPush,
      Value<String?> coverEtag,
      Value<bool> needsProgressPush,
      Value<String> status,
      Value<int?> rating,
      Value<DateTime?> startedAt,
      Value<DateTime?> finishedAt,
      Value<int> readCount,
      Value<DateTime?> deletedAt,
      Value<bool> syncExcluded,
      Value<String?> addedBy,
      Value<int> rowid,
    });
typedef $$BooksTableUpdateCompanionBuilder =
    BooksCompanion Function({
      Value<String> id,
      Value<String> title,
      Value<String?> subtitle,
      Value<String?> description,
      Value<String?> isbn,
      Value<String?> publisher,
      Value<int?> publishedYear,
      Value<int?> pageCount,
      Value<String?> coverPath,
      Value<String?> spineStyle,
      Value<String?> seriesId,
      Value<double?> seriesIndex,
      Value<double?> readingProgress,
      Value<int?> lastReadPage,
      Value<DateTime?> lastReadAt,
      Value<String?> readerNotes,
      Value<DateTime?> readerNotesUpdatedAt,
      Value<bool> readerNotesNeedsPush,
      Value<String?> sourceMetadata,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> needsPush,
      Value<String?> coverEtag,
      Value<bool> needsProgressPush,
      Value<String> status,
      Value<int?> rating,
      Value<DateTime?> startedAt,
      Value<DateTime?> finishedAt,
      Value<int> readCount,
      Value<DateTime?> deletedAt,
      Value<bool> syncExcluded,
      Value<String?> addedBy,
      Value<int> rowid,
    });

final class $$BooksTableReferences
    extends BaseReferences<_$VellumDatabase, $BooksTable, Book> {
  $$BooksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SeriesTable _seriesIdTable(_$VellumDatabase db) =>
      db.series.createAlias('books__series_id__series__id');

  $$SeriesTableProcessedTableManager? get seriesId {
    final $_column = $_itemColumn<String>('series_id');
    if ($_column == null) return null;
    final manager = $$SeriesTableTableManager(
      $_db,
      $_db.series,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_seriesIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$BookAuthorsTable, List<BookAuthor>>
  _bookAuthorsRefsTable(_$VellumDatabase db) => MultiTypedResultKey.fromTable(
    db.bookAuthors,
    aliasName: 'books__id__book_authors__book_id',
  );

  $$BookAuthorsTableProcessedTableManager get bookAuthorsRefs {
    final manager = $$BookAuthorsTableTableManager(
      $_db,
      $_db.bookAuthors,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookAuthorsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BookGenresTable, List<BookGenre>>
  _bookGenresRefsTable(_$VellumDatabase db) => MultiTypedResultKey.fromTable(
    db.bookGenres,
    aliasName: 'books__id__book_genres__book_id',
  );

  $$BookGenresTableProcessedTableManager get bookGenresRefs {
    final manager = $$BookGenresTableTableManager(
      $_db,
      $_db.bookGenres,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookGenresRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BookFilesTable, List<BookFile>>
  _bookFilesRefsTable(_$VellumDatabase db) => MultiTypedResultKey.fromTable(
    db.bookFiles,
    aliasName: 'books__id__book_files__book_id',
  );

  $$BookFilesTableProcessedTableManager get bookFilesRefs {
    final manager = $$BookFilesTableTableManager(
      $_db,
      $_db.bookFiles,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookFilesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PhysicalCopiesTable, List<PhysicalCopy>>
  _physicalCopiesRefsTable(_$VellumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.physicalCopies,
        aliasName: 'books__id__physical_copies__book_id',
      );

  $$PhysicalCopiesTableProcessedTableManager get physicalCopiesRefs {
    final manager = $$PhysicalCopiesTableTableManager(
      $_db,
      $_db.physicalCopies,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_physicalCopiesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ShelfBooksTable, List<ShelfBook>>
  _shelfBooksRefsTable(_$VellumDatabase db) => MultiTypedResultKey.fromTable(
    db.shelfBooks,
    aliasName: 'books__id__shelf_books__book_id',
  );

  $$ShelfBooksTableProcessedTableManager get shelfBooksRefs {
    final manager = $$ShelfBooksTableTableManager(
      $_db,
      $_db.shelfBooks,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_shelfBooksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$AnnotationsTable, List<Annotation>>
  _annotationsRefsTable(_$VellumDatabase db) => MultiTypedResultKey.fromTable(
    db.annotations,
    aliasName: 'books__id__annotations__book_id',
  );

  $$AnnotationsTableProcessedTableManager get annotationsRefs {
    final manager = $$AnnotationsTableTableManager(
      $_db,
      $_db.annotations,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_annotationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ReadingSessionsTable, List<ReadingSession>>
  _readingSessionsRefsTable(_$VellumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.readingSessions,
        aliasName: 'books__id__reading_sessions__book_id',
      );

  $$ReadingSessionsTableProcessedTableManager get readingSessionsRefs {
    final manager = $$ReadingSessionsTableTableManager(
      $_db,
      $_db.readingSessions,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _readingSessionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BookTextsTable, List<BookText>>
  _bookTextsRefsTable(_$VellumDatabase db) => MultiTypedResultKey.fromTable(
    db.bookTexts,
    aliasName: 'books__id__book_text__book_id',
  );

  $$BookTextsTableProcessedTableManager get bookTextsRefs {
    final manager = $$BookTextsTableTableManager(
      $_db,
      $_db.bookTexts,
    ).filter((f) => f.bookId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookTextsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BooksTableFilterComposer
    extends Composer<_$VellumDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get subtitle => $composableBuilder(
    column: $table.subtitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get isbn => $composableBuilder(
    column: $table.isbn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get publisher => $composableBuilder(
    column: $table.publisher,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get publishedYear => $composableBuilder(
    column: $table.publishedYear,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get spineStyle => $composableBuilder(
    column: $table.spineStyle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get seriesIndex => $composableBuilder(
    column: $table.seriesIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get readingProgress => $composableBuilder(
    column: $table.readingProgress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReadPage => $composableBuilder(
    column: $table.lastReadPage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get readerNotes => $composableBuilder(
    column: $table.readerNotes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get readerNotesUpdatedAt => $composableBuilder(
    column: $table.readerNotesUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get readerNotesNeedsPush => $composableBuilder(
    column: $table.readerNotesNeedsPush,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceMetadata => $composableBuilder(
    column: $table.sourceMetadata,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsPush => $composableBuilder(
    column: $table.needsPush,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coverEtag => $composableBuilder(
    column: $table.coverEtag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsProgressPush => $composableBuilder(
    column: $table.needsProgressPush,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get readCount => $composableBuilder(
    column: $table.readCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get syncExcluded => $composableBuilder(
    column: $table.syncExcluded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addedBy => $composableBuilder(
    column: $table.addedBy,
    builder: (column) => ColumnFilters(column),
  );

  $$SeriesTableFilterComposer get seriesId {
    final $$SeriesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.seriesId,
      referencedTable: $db.series,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SeriesTableFilterComposer(
            $db: $db,
            $table: $db.series,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> bookAuthorsRefs(
    Expression<bool> Function($$BookAuthorsTableFilterComposer f) f,
  ) {
    final $$BookAuthorsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookAuthors,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookAuthorsTableFilterComposer(
            $db: $db,
            $table: $db.bookAuthors,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> bookGenresRefs(
    Expression<bool> Function($$BookGenresTableFilterComposer f) f,
  ) {
    final $$BookGenresTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookGenres,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookGenresTableFilterComposer(
            $db: $db,
            $table: $db.bookGenres,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> bookFilesRefs(
    Expression<bool> Function($$BookFilesTableFilterComposer f) f,
  ) {
    final $$BookFilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookFiles,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookFilesTableFilterComposer(
            $db: $db,
            $table: $db.bookFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> physicalCopiesRefs(
    Expression<bool> Function($$PhysicalCopiesTableFilterComposer f) f,
  ) {
    final $$PhysicalCopiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.physicalCopies,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalCopiesTableFilterComposer(
            $db: $db,
            $table: $db.physicalCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> shelfBooksRefs(
    Expression<bool> Function($$ShelfBooksTableFilterComposer f) f,
  ) {
    final $$ShelfBooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shelfBooks,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShelfBooksTableFilterComposer(
            $db: $db,
            $table: $db.shelfBooks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> annotationsRefs(
    Expression<bool> Function($$AnnotationsTableFilterComposer f) f,
  ) {
    final $$AnnotationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.annotations,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AnnotationsTableFilterComposer(
            $db: $db,
            $table: $db.annotations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> readingSessionsRefs(
    Expression<bool> Function($$ReadingSessionsTableFilterComposer f) f,
  ) {
    final $$ReadingSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.readingSessions,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReadingSessionsTableFilterComposer(
            $db: $db,
            $table: $db.readingSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> bookTextsRefs(
    Expression<bool> Function($$BookTextsTableFilterComposer f) f,
  ) {
    final $$BookTextsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookTexts,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookTextsTableFilterComposer(
            $db: $db,
            $table: $db.bookTexts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BooksTableOrderingComposer
    extends Composer<_$VellumDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get subtitle => $composableBuilder(
    column: $table.subtitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get isbn => $composableBuilder(
    column: $table.isbn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get publisher => $composableBuilder(
    column: $table.publisher,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get publishedYear => $composableBuilder(
    column: $table.publishedYear,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pageCount => $composableBuilder(
    column: $table.pageCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverPath => $composableBuilder(
    column: $table.coverPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get spineStyle => $composableBuilder(
    column: $table.spineStyle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get seriesIndex => $composableBuilder(
    column: $table.seriesIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get readingProgress => $composableBuilder(
    column: $table.readingProgress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReadPage => $composableBuilder(
    column: $table.lastReadPage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get readerNotes => $composableBuilder(
    column: $table.readerNotes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get readerNotesUpdatedAt => $composableBuilder(
    column: $table.readerNotesUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get readerNotesNeedsPush => $composableBuilder(
    column: $table.readerNotesNeedsPush,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceMetadata => $composableBuilder(
    column: $table.sourceMetadata,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsPush => $composableBuilder(
    column: $table.needsPush,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coverEtag => $composableBuilder(
    column: $table.coverEtag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsProgressPush => $composableBuilder(
    column: $table.needsProgressPush,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get readCount => $composableBuilder(
    column: $table.readCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get syncExcluded => $composableBuilder(
    column: $table.syncExcluded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addedBy => $composableBuilder(
    column: $table.addedBy,
    builder: (column) => ColumnOrderings(column),
  );

  $$SeriesTableOrderingComposer get seriesId {
    final $$SeriesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.seriesId,
      referencedTable: $db.series,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SeriesTableOrderingComposer(
            $db: $db,
            $table: $db.series,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BooksTableAnnotationComposer
    extends Composer<_$VellumDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get subtitle =>
      $composableBuilder(column: $table.subtitle, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get isbn =>
      $composableBuilder(column: $table.isbn, builder: (column) => column);

  GeneratedColumn<String> get publisher =>
      $composableBuilder(column: $table.publisher, builder: (column) => column);

  GeneratedColumn<int> get publishedYear => $composableBuilder(
    column: $table.publishedYear,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pageCount =>
      $composableBuilder(column: $table.pageCount, builder: (column) => column);

  GeneratedColumn<String> get coverPath =>
      $composableBuilder(column: $table.coverPath, builder: (column) => column);

  GeneratedColumn<String> get spineStyle => $composableBuilder(
    column: $table.spineStyle,
    builder: (column) => column,
  );

  GeneratedColumn<double> get seriesIndex => $composableBuilder(
    column: $table.seriesIndex,
    builder: (column) => column,
  );

  GeneratedColumn<double> get readingProgress => $composableBuilder(
    column: $table.readingProgress,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastReadPage => $composableBuilder(
    column: $table.lastReadPage,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get readerNotes => $composableBuilder(
    column: $table.readerNotes,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get readerNotesUpdatedAt => $composableBuilder(
    column: $table.readerNotesUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get readerNotesNeedsPush => $composableBuilder(
    column: $table.readerNotesNeedsPush,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceMetadata => $composableBuilder(
    column: $table.sourceMetadata,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get needsPush =>
      $composableBuilder(column: $table.needsPush, builder: (column) => column);

  GeneratedColumn<String> get coverEtag =>
      $composableBuilder(column: $table.coverEtag, builder: (column) => column);

  GeneratedColumn<bool> get needsProgressPush => $composableBuilder(
    column: $table.needsProgressPush,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get readCount =>
      $composableBuilder(column: $table.readCount, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<bool> get syncExcluded => $composableBuilder(
    column: $table.syncExcluded,
    builder: (column) => column,
  );

  GeneratedColumn<String> get addedBy =>
      $composableBuilder(column: $table.addedBy, builder: (column) => column);

  $$SeriesTableAnnotationComposer get seriesId {
    final $$SeriesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.seriesId,
      referencedTable: $db.series,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SeriesTableAnnotationComposer(
            $db: $db,
            $table: $db.series,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> bookAuthorsRefs<T extends Object>(
    Expression<T> Function($$BookAuthorsTableAnnotationComposer a) f,
  ) {
    final $$BookAuthorsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookAuthors,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookAuthorsTableAnnotationComposer(
            $db: $db,
            $table: $db.bookAuthors,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> bookGenresRefs<T extends Object>(
    Expression<T> Function($$BookGenresTableAnnotationComposer a) f,
  ) {
    final $$BookGenresTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookGenres,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookGenresTableAnnotationComposer(
            $db: $db,
            $table: $db.bookGenres,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> bookFilesRefs<T extends Object>(
    Expression<T> Function($$BookFilesTableAnnotationComposer a) f,
  ) {
    final $$BookFilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookFiles,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookFilesTableAnnotationComposer(
            $db: $db,
            $table: $db.bookFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> physicalCopiesRefs<T extends Object>(
    Expression<T> Function($$PhysicalCopiesTableAnnotationComposer a) f,
  ) {
    final $$PhysicalCopiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.physicalCopies,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalCopiesTableAnnotationComposer(
            $db: $db,
            $table: $db.physicalCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> shelfBooksRefs<T extends Object>(
    Expression<T> Function($$ShelfBooksTableAnnotationComposer a) f,
  ) {
    final $$ShelfBooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shelfBooks,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShelfBooksTableAnnotationComposer(
            $db: $db,
            $table: $db.shelfBooks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> annotationsRefs<T extends Object>(
    Expression<T> Function($$AnnotationsTableAnnotationComposer a) f,
  ) {
    final $$AnnotationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.annotations,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AnnotationsTableAnnotationComposer(
            $db: $db,
            $table: $db.annotations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> readingSessionsRefs<T extends Object>(
    Expression<T> Function($$ReadingSessionsTableAnnotationComposer a) f,
  ) {
    final $$ReadingSessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.readingSessions,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ReadingSessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.readingSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> bookTextsRefs<T extends Object>(
    Expression<T> Function($$BookTextsTableAnnotationComposer a) f,
  ) {
    final $$BookTextsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookTexts,
      getReferencedColumn: (t) => t.bookId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookTextsTableAnnotationComposer(
            $db: $db,
            $table: $db.bookTexts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BooksTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $BooksTable,
          Book,
          $$BooksTableFilterComposer,
          $$BooksTableOrderingComposer,
          $$BooksTableAnnotationComposer,
          $$BooksTableCreateCompanionBuilder,
          $$BooksTableUpdateCompanionBuilder,
          (Book, $$BooksTableReferences),
          Book,
          PrefetchHooks Function({
            bool seriesId,
            bool bookAuthorsRefs,
            bool bookGenresRefs,
            bool bookFilesRefs,
            bool physicalCopiesRefs,
            bool shelfBooksRefs,
            bool annotationsRefs,
            bool readingSessionsRefs,
            bool bookTextsRefs,
          })
        > {
  $$BooksTableTableManager(_$VellumDatabase db, $BooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> subtitle = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> isbn = const Value.absent(),
                Value<String?> publisher = const Value.absent(),
                Value<int?> publishedYear = const Value.absent(),
                Value<int?> pageCount = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<String?> spineStyle = const Value.absent(),
                Value<String?> seriesId = const Value.absent(),
                Value<double?> seriesIndex = const Value.absent(),
                Value<double?> readingProgress = const Value.absent(),
                Value<int?> lastReadPage = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<String?> readerNotes = const Value.absent(),
                Value<DateTime?> readerNotesUpdatedAt = const Value.absent(),
                Value<bool> readerNotesNeedsPush = const Value.absent(),
                Value<String?> sourceMetadata = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<String?> coverEtag = const Value.absent(),
                Value<bool> needsProgressPush = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> rating = const Value.absent(),
                Value<DateTime?> startedAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<int> readCount = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> syncExcluded = const Value.absent(),
                Value<String?> addedBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion(
                id: id,
                title: title,
                subtitle: subtitle,
                description: description,
                isbn: isbn,
                publisher: publisher,
                publishedYear: publishedYear,
                pageCount: pageCount,
                coverPath: coverPath,
                spineStyle: spineStyle,
                seriesId: seriesId,
                seriesIndex: seriesIndex,
                readingProgress: readingProgress,
                lastReadPage: lastReadPage,
                lastReadAt: lastReadAt,
                readerNotes: readerNotes,
                readerNotesUpdatedAt: readerNotesUpdatedAt,
                readerNotesNeedsPush: readerNotesNeedsPush,
                sourceMetadata: sourceMetadata,
                createdAt: createdAt,
                updatedAt: updatedAt,
                needsPush: needsPush,
                coverEtag: coverEtag,
                needsProgressPush: needsProgressPush,
                status: status,
                rating: rating,
                startedAt: startedAt,
                finishedAt: finishedAt,
                readCount: readCount,
                deletedAt: deletedAt,
                syncExcluded: syncExcluded,
                addedBy: addedBy,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                Value<String?> subtitle = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> isbn = const Value.absent(),
                Value<String?> publisher = const Value.absent(),
                Value<int?> publishedYear = const Value.absent(),
                Value<int?> pageCount = const Value.absent(),
                Value<String?> coverPath = const Value.absent(),
                Value<String?> spineStyle = const Value.absent(),
                Value<String?> seriesId = const Value.absent(),
                Value<double?> seriesIndex = const Value.absent(),
                Value<double?> readingProgress = const Value.absent(),
                Value<int?> lastReadPage = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<String?> readerNotes = const Value.absent(),
                Value<DateTime?> readerNotesUpdatedAt = const Value.absent(),
                Value<bool> readerNotesNeedsPush = const Value.absent(),
                Value<String?> sourceMetadata = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<String?> coverEtag = const Value.absent(),
                Value<bool> needsProgressPush = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int?> rating = const Value.absent(),
                Value<DateTime?> startedAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<int> readCount = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<bool> syncExcluded = const Value.absent(),
                Value<String?> addedBy = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion.insert(
                id: id,
                title: title,
                subtitle: subtitle,
                description: description,
                isbn: isbn,
                publisher: publisher,
                publishedYear: publishedYear,
                pageCount: pageCount,
                coverPath: coverPath,
                spineStyle: spineStyle,
                seriesId: seriesId,
                seriesIndex: seriesIndex,
                readingProgress: readingProgress,
                lastReadPage: lastReadPage,
                lastReadAt: lastReadAt,
                readerNotes: readerNotes,
                readerNotesUpdatedAt: readerNotesUpdatedAt,
                readerNotesNeedsPush: readerNotesNeedsPush,
                sourceMetadata: sourceMetadata,
                createdAt: createdAt,
                updatedAt: updatedAt,
                needsPush: needsPush,
                coverEtag: coverEtag,
                needsProgressPush: needsProgressPush,
                status: status,
                rating: rating,
                startedAt: startedAt,
                finishedAt: finishedAt,
                readCount: readCount,
                deletedAt: deletedAt,
                syncExcluded: syncExcluded,
                addedBy: addedBy,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$BooksTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                seriesId = false,
                bookAuthorsRefs = false,
                bookGenresRefs = false,
                bookFilesRefs = false,
                physicalCopiesRefs = false,
                shelfBooksRefs = false,
                annotationsRefs = false,
                readingSessionsRefs = false,
                bookTextsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (bookAuthorsRefs) db.bookAuthors,
                    if (bookGenresRefs) db.bookGenres,
                    if (bookFilesRefs) db.bookFiles,
                    if (physicalCopiesRefs) db.physicalCopies,
                    if (shelfBooksRefs) db.shelfBooks,
                    if (annotationsRefs) db.annotations,
                    if (readingSessionsRefs) db.readingSessions,
                    if (bookTextsRefs) db.bookTexts,
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
                        if (seriesId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.seriesId,
                                    referencedTable: $$BooksTableReferences
                                        ._seriesIdTable(db),
                                    referencedColumn: $$BooksTableReferences
                                        ._seriesIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (bookAuthorsRefs)
                        await $_getPrefetchedData<
                          Book,
                          $BooksTable,
                          BookAuthor
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._bookAuthorsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).bookAuthorsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bookGenresRefs)
                        await $_getPrefetchedData<Book, $BooksTable, BookGenre>(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._bookGenresRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).bookGenresRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bookFilesRefs)
                        await $_getPrefetchedData<Book, $BooksTable, BookFile>(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._bookFilesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).bookFilesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (physicalCopiesRefs)
                        await $_getPrefetchedData<
                          Book,
                          $BooksTable,
                          PhysicalCopy
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._physicalCopiesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).physicalCopiesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (shelfBooksRefs)
                        await $_getPrefetchedData<Book, $BooksTable, ShelfBook>(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._shelfBooksRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).shelfBooksRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (annotationsRefs)
                        await $_getPrefetchedData<
                          Book,
                          $BooksTable,
                          Annotation
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._annotationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).annotationsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (readingSessionsRefs)
                        await $_getPrefetchedData<
                          Book,
                          $BooksTable,
                          ReadingSession
                        >(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._readingSessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).readingSessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bookTextsRefs)
                        await $_getPrefetchedData<Book, $BooksTable, BookText>(
                          currentTable: table,
                          referencedTable: $$BooksTableReferences
                              ._bookTextsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$BooksTableReferences(
                                db,
                                table,
                                p0,
                              ).bookTextsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.bookId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$BooksTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $BooksTable,
      Book,
      $$BooksTableFilterComposer,
      $$BooksTableOrderingComposer,
      $$BooksTableAnnotationComposer,
      $$BooksTableCreateCompanionBuilder,
      $$BooksTableUpdateCompanionBuilder,
      (Book, $$BooksTableReferences),
      Book,
      PrefetchHooks Function({
        bool seriesId,
        bool bookAuthorsRefs,
        bool bookGenresRefs,
        bool bookFilesRefs,
        bool physicalCopiesRefs,
        bool shelfBooksRefs,
        bool annotationsRefs,
        bool readingSessionsRefs,
        bool bookTextsRefs,
      })
    >;
typedef $$AuthorsTableCreateCompanionBuilder =
    AuthorsCompanion Function({
      required String id,
      required String name,
      Value<int> rowid,
    });
typedef $$AuthorsTableUpdateCompanionBuilder =
    AuthorsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> rowid,
    });

final class $$AuthorsTableReferences
    extends BaseReferences<_$VellumDatabase, $AuthorsTable, Author> {
  $$AuthorsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BookAuthorsTable, List<BookAuthor>>
  _bookAuthorsRefsTable(_$VellumDatabase db) => MultiTypedResultKey.fromTable(
    db.bookAuthors,
    aliasName: 'authors__id__book_authors__author_id',
  );

  $$BookAuthorsTableProcessedTableManager get bookAuthorsRefs {
    final manager = $$BookAuthorsTableTableManager(
      $_db,
      $_db.bookAuthors,
    ).filter((f) => f.authorId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookAuthorsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AuthorsTableFilterComposer
    extends Composer<_$VellumDatabase, $AuthorsTable> {
  $$AuthorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> bookAuthorsRefs(
    Expression<bool> Function($$BookAuthorsTableFilterComposer f) f,
  ) {
    final $$BookAuthorsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookAuthors,
      getReferencedColumn: (t) => t.authorId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookAuthorsTableFilterComposer(
            $db: $db,
            $table: $db.bookAuthors,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AuthorsTableOrderingComposer
    extends Composer<_$VellumDatabase, $AuthorsTable> {
  $$AuthorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AuthorsTableAnnotationComposer
    extends Composer<_$VellumDatabase, $AuthorsTable> {
  $$AuthorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  Expression<T> bookAuthorsRefs<T extends Object>(
    Expression<T> Function($$BookAuthorsTableAnnotationComposer a) f,
  ) {
    final $$BookAuthorsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookAuthors,
      getReferencedColumn: (t) => t.authorId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookAuthorsTableAnnotationComposer(
            $db: $db,
            $table: $db.bookAuthors,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AuthorsTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $AuthorsTable,
          Author,
          $$AuthorsTableFilterComposer,
          $$AuthorsTableOrderingComposer,
          $$AuthorsTableAnnotationComposer,
          $$AuthorsTableCreateCompanionBuilder,
          $$AuthorsTableUpdateCompanionBuilder,
          (Author, $$AuthorsTableReferences),
          Author,
          PrefetchHooks Function({bool bookAuthorsRefs})
        > {
  $$AuthorsTableTableManager(_$VellumDatabase db, $AuthorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AuthorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AuthorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AuthorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AuthorsCompanion(id: id, name: name, rowid: rowid),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> rowid = const Value.absent(),
              }) => AuthorsCompanion.insert(id: id, name: name, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AuthorsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookAuthorsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (bookAuthorsRefs) db.bookAuthors],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (bookAuthorsRefs)
                    await $_getPrefetchedData<
                      Author,
                      $AuthorsTable,
                      BookAuthor
                    >(
                      currentTable: table,
                      referencedTable: $$AuthorsTableReferences
                          ._bookAuthorsRefsTable(db),
                      managerFromTypedResult: (p0) => $$AuthorsTableReferences(
                        db,
                        table,
                        p0,
                      ).bookAuthorsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.authorId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$AuthorsTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $AuthorsTable,
      Author,
      $$AuthorsTableFilterComposer,
      $$AuthorsTableOrderingComposer,
      $$AuthorsTableAnnotationComposer,
      $$AuthorsTableCreateCompanionBuilder,
      $$AuthorsTableUpdateCompanionBuilder,
      (Author, $$AuthorsTableReferences),
      Author,
      PrefetchHooks Function({bool bookAuthorsRefs})
    >;
typedef $$BookAuthorsTableCreateCompanionBuilder =
    BookAuthorsCompanion Function({
      required String bookId,
      required String authorId,
      Value<int> position,
      Value<int> rowid,
    });
typedef $$BookAuthorsTableUpdateCompanionBuilder =
    BookAuthorsCompanion Function({
      Value<String> bookId,
      Value<String> authorId,
      Value<int> position,
      Value<int> rowid,
    });

final class $$BookAuthorsTableReferences
    extends BaseReferences<_$VellumDatabase, $BookAuthorsTable, BookAuthor> {
  $$BookAuthorsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$VellumDatabase db) =>
      db.books.createAlias('book_authors__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $AuthorsTable _authorIdTable(_$VellumDatabase db) =>
      db.authors.createAlias('book_authors__author_id__authors__id');

  $$AuthorsTableProcessedTableManager get authorId {
    final $_column = $_itemColumn<String>('author_id')!;

    final manager = $$AuthorsTableTableManager(
      $_db,
      $_db.authors,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_authorIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BookAuthorsTableFilterComposer
    extends Composer<_$VellumDatabase, $BookAuthorsTable> {
  $$BookAuthorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AuthorsTableFilterComposer get authorId {
    final $$AuthorsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.authorId,
      referencedTable: $db.authors,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AuthorsTableFilterComposer(
            $db: $db,
            $table: $db.authors,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookAuthorsTableOrderingComposer
    extends Composer<_$VellumDatabase, $BookAuthorsTable> {
  $$BookAuthorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AuthorsTableOrderingComposer get authorId {
    final $$AuthorsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.authorId,
      referencedTable: $db.authors,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AuthorsTableOrderingComposer(
            $db: $db,
            $table: $db.authors,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookAuthorsTableAnnotationComposer
    extends Composer<_$VellumDatabase, $BookAuthorsTable> {
  $$BookAuthorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$AuthorsTableAnnotationComposer get authorId {
    final $$AuthorsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.authorId,
      referencedTable: $db.authors,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AuthorsTableAnnotationComposer(
            $db: $db,
            $table: $db.authors,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookAuthorsTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $BookAuthorsTable,
          BookAuthor,
          $$BookAuthorsTableFilterComposer,
          $$BookAuthorsTableOrderingComposer,
          $$BookAuthorsTableAnnotationComposer,
          $$BookAuthorsTableCreateCompanionBuilder,
          $$BookAuthorsTableUpdateCompanionBuilder,
          (BookAuthor, $$BookAuthorsTableReferences),
          BookAuthor,
          PrefetchHooks Function({bool bookId, bool authorId})
        > {
  $$BookAuthorsTableTableManager(_$VellumDatabase db, $BookAuthorsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookAuthorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookAuthorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookAuthorsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String> authorId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookAuthorsCompanion(
                bookId: bookId,
                authorId: authorId,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required String authorId,
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookAuthorsCompanion.insert(
                bookId: bookId,
                authorId: authorId,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BookAuthorsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false, authorId = false}) {
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
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable: $$BookAuthorsTableReferences
                                    ._bookIdTable(db),
                                referencedColumn: $$BookAuthorsTableReferences
                                    ._bookIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (authorId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.authorId,
                                referencedTable: $$BookAuthorsTableReferences
                                    ._authorIdTable(db),
                                referencedColumn: $$BookAuthorsTableReferences
                                    ._authorIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$BookAuthorsTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $BookAuthorsTable,
      BookAuthor,
      $$BookAuthorsTableFilterComposer,
      $$BookAuthorsTableOrderingComposer,
      $$BookAuthorsTableAnnotationComposer,
      $$BookAuthorsTableCreateCompanionBuilder,
      $$BookAuthorsTableUpdateCompanionBuilder,
      (BookAuthor, $$BookAuthorsTableReferences),
      BookAuthor,
      PrefetchHooks Function({bool bookId, bool authorId})
    >;
typedef $$GenresTableCreateCompanionBuilder =
    GenresCompanion Function({
      required String id,
      required String name,
      Value<int> rowid,
    });
typedef $$GenresTableUpdateCompanionBuilder =
    GenresCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> rowid,
    });

final class $$GenresTableReferences
    extends BaseReferences<_$VellumDatabase, $GenresTable, Genre> {
  $$GenresTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BookGenresTable, List<BookGenre>>
  _bookGenresRefsTable(_$VellumDatabase db) => MultiTypedResultKey.fromTable(
    db.bookGenres,
    aliasName: 'genres__id__book_genres__genre_id',
  );

  $$BookGenresTableProcessedTableManager get bookGenresRefs {
    final manager = $$BookGenresTableTableManager(
      $_db,
      $_db.bookGenres,
    ).filter((f) => f.genreId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookGenresRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$GenresTableFilterComposer
    extends Composer<_$VellumDatabase, $GenresTable> {
  $$GenresTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> bookGenresRefs(
    Expression<bool> Function($$BookGenresTableFilterComposer f) f,
  ) {
    final $$BookGenresTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookGenres,
      getReferencedColumn: (t) => t.genreId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookGenresTableFilterComposer(
            $db: $db,
            $table: $db.bookGenres,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GenresTableOrderingComposer
    extends Composer<_$VellumDatabase, $GenresTable> {
  $$GenresTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GenresTableAnnotationComposer
    extends Composer<_$VellumDatabase, $GenresTable> {
  $$GenresTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  Expression<T> bookGenresRefs<T extends Object>(
    Expression<T> Function($$BookGenresTableAnnotationComposer a) f,
  ) {
    final $$BookGenresTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookGenres,
      getReferencedColumn: (t) => t.genreId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookGenresTableAnnotationComposer(
            $db: $db,
            $table: $db.bookGenres,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GenresTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $GenresTable,
          Genre,
          $$GenresTableFilterComposer,
          $$GenresTableOrderingComposer,
          $$GenresTableAnnotationComposer,
          $$GenresTableCreateCompanionBuilder,
          $$GenresTableUpdateCompanionBuilder,
          (Genre, $$GenresTableReferences),
          Genre,
          PrefetchHooks Function({bool bookGenresRefs})
        > {
  $$GenresTableTableManager(_$VellumDatabase db, $GenresTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GenresTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GenresTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GenresTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GenresCompanion(id: id, name: name, rowid: rowid),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> rowid = const Value.absent(),
              }) => GenresCompanion.insert(id: id, name: name, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$GenresTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({bookGenresRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (bookGenresRefs) db.bookGenres],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (bookGenresRefs)
                    await $_getPrefetchedData<Genre, $GenresTable, BookGenre>(
                      currentTable: table,
                      referencedTable: $$GenresTableReferences
                          ._bookGenresRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$GenresTableReferences(db, table, p0).bookGenresRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.genreId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$GenresTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $GenresTable,
      Genre,
      $$GenresTableFilterComposer,
      $$GenresTableOrderingComposer,
      $$GenresTableAnnotationComposer,
      $$GenresTableCreateCompanionBuilder,
      $$GenresTableUpdateCompanionBuilder,
      (Genre, $$GenresTableReferences),
      Genre,
      PrefetchHooks Function({bool bookGenresRefs})
    >;
typedef $$BookGenresTableCreateCompanionBuilder =
    BookGenresCompanion Function({
      required String bookId,
      required String genreId,
      Value<int> rowid,
    });
typedef $$BookGenresTableUpdateCompanionBuilder =
    BookGenresCompanion Function({
      Value<String> bookId,
      Value<String> genreId,
      Value<int> rowid,
    });

final class $$BookGenresTableReferences
    extends BaseReferences<_$VellumDatabase, $BookGenresTable, BookGenre> {
  $$BookGenresTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$VellumDatabase db) =>
      db.books.createAlias('book_genres__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $GenresTable _genreIdTable(_$VellumDatabase db) =>
      db.genres.createAlias('book_genres__genre_id__genres__id');

  $$GenresTableProcessedTableManager get genreId {
    final $_column = $_itemColumn<String>('genre_id')!;

    final manager = $$GenresTableTableManager(
      $_db,
      $_db.genres,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_genreIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BookGenresTableFilterComposer
    extends Composer<_$VellumDatabase, $BookGenresTable> {
  $$BookGenresTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GenresTableFilterComposer get genreId {
    final $$GenresTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.genreId,
      referencedTable: $db.genres,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GenresTableFilterComposer(
            $db: $db,
            $table: $db.genres,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookGenresTableOrderingComposer
    extends Composer<_$VellumDatabase, $BookGenresTable> {
  $$BookGenresTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GenresTableOrderingComposer get genreId {
    final $$GenresTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.genreId,
      referencedTable: $db.genres,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GenresTableOrderingComposer(
            $db: $db,
            $table: $db.genres,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookGenresTableAnnotationComposer
    extends Composer<_$VellumDatabase, $BookGenresTable> {
  $$BookGenresTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$GenresTableAnnotationComposer get genreId {
    final $$GenresTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.genreId,
      referencedTable: $db.genres,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GenresTableAnnotationComposer(
            $db: $db,
            $table: $db.genres,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookGenresTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $BookGenresTable,
          BookGenre,
          $$BookGenresTableFilterComposer,
          $$BookGenresTableOrderingComposer,
          $$BookGenresTableAnnotationComposer,
          $$BookGenresTableCreateCompanionBuilder,
          $$BookGenresTableUpdateCompanionBuilder,
          (BookGenre, $$BookGenresTableReferences),
          BookGenre,
          PrefetchHooks Function({bool bookId, bool genreId})
        > {
  $$BookGenresTableTableManager(_$VellumDatabase db, $BookGenresTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookGenresTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookGenresTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookGenresTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String> genreId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookGenresCompanion(
                bookId: bookId,
                genreId: genreId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required String genreId,
                Value<int> rowid = const Value.absent(),
              }) => BookGenresCompanion.insert(
                bookId: bookId,
                genreId: genreId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BookGenresTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false, genreId = false}) {
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
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable: $$BookGenresTableReferences
                                    ._bookIdTable(db),
                                referencedColumn: $$BookGenresTableReferences
                                    ._bookIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (genreId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.genreId,
                                referencedTable: $$BookGenresTableReferences
                                    ._genreIdTable(db),
                                referencedColumn: $$BookGenresTableReferences
                                    ._genreIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$BookGenresTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $BookGenresTable,
      BookGenre,
      $$BookGenresTableFilterComposer,
      $$BookGenresTableOrderingComposer,
      $$BookGenresTableAnnotationComposer,
      $$BookGenresTableCreateCompanionBuilder,
      $$BookGenresTableUpdateCompanionBuilder,
      (BookGenre, $$BookGenresTableReferences),
      BookGenre,
      PrefetchHooks Function({bool bookId, bool genreId})
    >;
typedef $$BookFilesTableCreateCompanionBuilder =
    BookFilesCompanion Function({
      required String id,
      required String bookId,
      required String format,
      required String path,
      required int sizeBytes,
      required String sha256,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });
typedef $$BookFilesTableUpdateCompanionBuilder =
    BookFilesCompanion Function({
      Value<String> id,
      Value<String> bookId,
      Value<String> format,
      Value<String> path,
      Value<int> sizeBytes,
      Value<String> sha256,
      Value<DateTime> addedAt,
      Value<int> rowid,
    });

final class $$BookFilesTableReferences
    extends BaseReferences<_$VellumDatabase, $BookFilesTable, BookFile> {
  $$BookFilesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$VellumDatabase db) =>
      db.books.createAlias('book_files__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$BookTextsTable, List<BookText>>
  _bookTextsRefsTable(_$VellumDatabase db) => MultiTypedResultKey.fromTable(
    db.bookTexts,
    aliasName: 'book_files__id__book_text__file_id',
  );

  $$BookTextsTableProcessedTableManager get bookTextsRefs {
    final manager = $$BookTextsTableTableManager(
      $_db,
      $_db.bookTexts,
    ).filter((f) => f.fileId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookTextsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BookFilesTableFilterComposer
    extends Composer<_$VellumDatabase, $BookFilesTable> {
  $$BookFilesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> bookTextsRefs(
    Expression<bool> Function($$BookTextsTableFilterComposer f) f,
  ) {
    final $$BookTextsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookTexts,
      getReferencedColumn: (t) => t.fileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookTextsTableFilterComposer(
            $db: $db,
            $table: $db.bookTexts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BookFilesTableOrderingComposer
    extends Composer<_$VellumDatabase, $BookFilesTable> {
  $$BookFilesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
    column: $table.sizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sha256 => $composableBuilder(
    column: $table.sha256,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookFilesTableAnnotationComposer
    extends Composer<_$VellumDatabase, $BookFilesTable> {
  $$BookFilesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get sha256 =>
      $composableBuilder(column: $table.sha256, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> bookTextsRefs<T extends Object>(
    Expression<T> Function($$BookTextsTableAnnotationComposer a) f,
  ) {
    final $$BookTextsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookTexts,
      getReferencedColumn: (t) => t.fileId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookTextsTableAnnotationComposer(
            $db: $db,
            $table: $db.bookTexts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BookFilesTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $BookFilesTable,
          BookFile,
          $$BookFilesTableFilterComposer,
          $$BookFilesTableOrderingComposer,
          $$BookFilesTableAnnotationComposer,
          $$BookFilesTableCreateCompanionBuilder,
          $$BookFilesTableUpdateCompanionBuilder,
          (BookFile, $$BookFilesTableReferences),
          BookFile,
          PrefetchHooks Function({bool bookId, bool bookTextsRefs})
        > {
  $$BookFilesTableTableManager(_$VellumDatabase db, $BookFilesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookFilesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookFilesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookFilesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> format = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<int> sizeBytes = const Value.absent(),
                Value<String> sha256 = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookFilesCompanion(
                id: id,
                bookId: bookId,
                format: format,
                path: path,
                sizeBytes: sizeBytes,
                sha256: sha256,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                required String format,
                required String path,
                required int sizeBytes,
                required String sha256,
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookFilesCompanion.insert(
                id: id,
                bookId: bookId,
                format: format,
                path: path,
                sizeBytes: sizeBytes,
                sha256: sha256,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BookFilesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false, bookTextsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (bookTextsRefs) db.bookTexts],
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
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable: $$BookFilesTableReferences
                                    ._bookIdTable(db),
                                referencedColumn: $$BookFilesTableReferences
                                    ._bookIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (bookTextsRefs)
                    await $_getPrefetchedData<
                      BookFile,
                      $BookFilesTable,
                      BookText
                    >(
                      currentTable: table,
                      referencedTable: $$BookFilesTableReferences
                          ._bookTextsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$BookFilesTableReferences(
                            db,
                            table,
                            p0,
                          ).bookTextsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.fileId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$BookFilesTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $BookFilesTable,
      BookFile,
      $$BookFilesTableFilterComposer,
      $$BookFilesTableOrderingComposer,
      $$BookFilesTableAnnotationComposer,
      $$BookFilesTableCreateCompanionBuilder,
      $$BookFilesTableUpdateCompanionBuilder,
      (BookFile, $$BookFilesTableReferences),
      BookFile,
      PrefetchHooks Function({bool bookId, bool bookTextsRefs})
    >;
typedef $$PhysicalCopiesTableCreateCompanionBuilder =
    PhysicalCopiesCompanion Function({
      required String id,
      required String bookId,
      Value<String?> location,
      Value<String?> condition,
      Value<String?> notes,
      Value<DateTime> updatedAt,
      Value<bool> needsPush,
      Value<int> rowid,
    });
typedef $$PhysicalCopiesTableUpdateCompanionBuilder =
    PhysicalCopiesCompanion Function({
      Value<String> id,
      Value<String> bookId,
      Value<String?> location,
      Value<String?> condition,
      Value<String?> notes,
      Value<DateTime> updatedAt,
      Value<bool> needsPush,
      Value<int> rowid,
    });

final class $$PhysicalCopiesTableReferences
    extends
        BaseReferences<_$VellumDatabase, $PhysicalCopiesTable, PhysicalCopy> {
  $$PhysicalCopiesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BooksTable _bookIdTable(_$VellumDatabase db) =>
      db.books.createAlias('physical_copies__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$LoansTable, List<Loan>> _loansRefsTable(
    _$VellumDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.loans,
    aliasName: 'physical_copies__id__loans__copy_id',
  );

  $$LoansTableProcessedTableManager get loansRefs {
    final manager = $$LoansTableTableManager(
      $_db,
      $_db.loans,
    ).filter((f) => f.copyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_loansRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$CopyPhotosTable, List<CopyPhoto>>
  _copyPhotosRefsTable(_$VellumDatabase db) => MultiTypedResultKey.fromTable(
    db.copyPhotos,
    aliasName: 'physical_copies__id__copy_photos__copy_id',
  );

  $$CopyPhotosTableProcessedTableManager get copyPhotosRefs {
    final manager = $$CopyPhotosTableTableManager(
      $_db,
      $_db.copyPhotos,
    ).filter((f) => f.copyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_copyPhotosRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BookPlacementsTable, List<BookPlacement>>
  _bookPlacementsRefsTable(_$VellumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.bookPlacements,
        aliasName: 'physical_copies__id__book_placements__copy_id',
      );

  $$BookPlacementsTableProcessedTableManager get bookPlacementsRefs {
    final manager = $$BookPlacementsTableTableManager(
      $_db,
      $_db.bookPlacements,
    ).filter((f) => f.copyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookPlacementsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PhysicalCopiesTableFilterComposer
    extends Composer<_$VellumDatabase, $PhysicalCopiesTable> {
  $$PhysicalCopiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get condition => $composableBuilder(
    column: $table.condition,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsPush => $composableBuilder(
    column: $table.needsPush,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> loansRefs(
    Expression<bool> Function($$LoansTableFilterComposer f) f,
  ) {
    final $$LoansTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.loans,
      getReferencedColumn: (t) => t.copyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LoansTableFilterComposer(
            $db: $db,
            $table: $db.loans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> copyPhotosRefs(
    Expression<bool> Function($$CopyPhotosTableFilterComposer f) f,
  ) {
    final $$CopyPhotosTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.copyPhotos,
      getReferencedColumn: (t) => t.copyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CopyPhotosTableFilterComposer(
            $db: $db,
            $table: $db.copyPhotos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> bookPlacementsRefs(
    Expression<bool> Function($$BookPlacementsTableFilterComposer f) f,
  ) {
    final $$BookPlacementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookPlacements,
      getReferencedColumn: (t) => t.copyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookPlacementsTableFilterComposer(
            $db: $db,
            $table: $db.bookPlacements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PhysicalCopiesTableOrderingComposer
    extends Composer<_$VellumDatabase, $PhysicalCopiesTable> {
  $$PhysicalCopiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get location => $composableBuilder(
    column: $table.location,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get condition => $composableBuilder(
    column: $table.condition,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsPush => $composableBuilder(
    column: $table.needsPush,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PhysicalCopiesTableAnnotationComposer
    extends Composer<_$VellumDatabase, $PhysicalCopiesTable> {
  $$PhysicalCopiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get location =>
      $composableBuilder(column: $table.location, builder: (column) => column);

  GeneratedColumn<String> get condition =>
      $composableBuilder(column: $table.condition, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get needsPush =>
      $composableBuilder(column: $table.needsPush, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> loansRefs<T extends Object>(
    Expression<T> Function($$LoansTableAnnotationComposer a) f,
  ) {
    final $$LoansTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.loans,
      getReferencedColumn: (t) => t.copyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$LoansTableAnnotationComposer(
            $db: $db,
            $table: $db.loans,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> copyPhotosRefs<T extends Object>(
    Expression<T> Function($$CopyPhotosTableAnnotationComposer a) f,
  ) {
    final $$CopyPhotosTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.copyPhotos,
      getReferencedColumn: (t) => t.copyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CopyPhotosTableAnnotationComposer(
            $db: $db,
            $table: $db.copyPhotos,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> bookPlacementsRefs<T extends Object>(
    Expression<T> Function($$BookPlacementsTableAnnotationComposer a) f,
  ) {
    final $$BookPlacementsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookPlacements,
      getReferencedColumn: (t) => t.copyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookPlacementsTableAnnotationComposer(
            $db: $db,
            $table: $db.bookPlacements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PhysicalCopiesTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $PhysicalCopiesTable,
          PhysicalCopy,
          $$PhysicalCopiesTableFilterComposer,
          $$PhysicalCopiesTableOrderingComposer,
          $$PhysicalCopiesTableAnnotationComposer,
          $$PhysicalCopiesTableCreateCompanionBuilder,
          $$PhysicalCopiesTableUpdateCompanionBuilder,
          (PhysicalCopy, $$PhysicalCopiesTableReferences),
          PhysicalCopy,
          PrefetchHooks Function({
            bool bookId,
            bool loansRefs,
            bool copyPhotosRefs,
            bool bookPlacementsRefs,
          })
        > {
  $$PhysicalCopiesTableTableManager(
    _$VellumDatabase db,
    $PhysicalCopiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PhysicalCopiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PhysicalCopiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PhysicalCopiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String?> location = const Value.absent(),
                Value<String?> condition = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhysicalCopiesCompanion(
                id: id,
                bookId: bookId,
                location: location,
                condition: condition,
                notes: notes,
                updatedAt: updatedAt,
                needsPush: needsPush,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                Value<String?> location = const Value.absent(),
                Value<String?> condition = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhysicalCopiesCompanion.insert(
                id: id,
                bookId: bookId,
                location: location,
                condition: condition,
                notes: notes,
                updatedAt: updatedAt,
                needsPush: needsPush,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PhysicalCopiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                bookId = false,
                loansRefs = false,
                copyPhotosRefs = false,
                bookPlacementsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (loansRefs) db.loans,
                    if (copyPhotosRefs) db.copyPhotos,
                    if (bookPlacementsRefs) db.bookPlacements,
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
                        if (bookId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.bookId,
                                    referencedTable:
                                        $$PhysicalCopiesTableReferences
                                            ._bookIdTable(db),
                                    referencedColumn:
                                        $$PhysicalCopiesTableReferences
                                            ._bookIdTable(db)
                                            .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (loansRefs)
                        await $_getPrefetchedData<
                          PhysicalCopy,
                          $PhysicalCopiesTable,
                          Loan
                        >(
                          currentTable: table,
                          referencedTable: $$PhysicalCopiesTableReferences
                              ._loansRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PhysicalCopiesTableReferences(
                                db,
                                table,
                                p0,
                              ).loansRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.copyId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (copyPhotosRefs)
                        await $_getPrefetchedData<
                          PhysicalCopy,
                          $PhysicalCopiesTable,
                          CopyPhoto
                        >(
                          currentTable: table,
                          referencedTable: $$PhysicalCopiesTableReferences
                              ._copyPhotosRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PhysicalCopiesTableReferences(
                                db,
                                table,
                                p0,
                              ).copyPhotosRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.copyId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bookPlacementsRefs)
                        await $_getPrefetchedData<
                          PhysicalCopy,
                          $PhysicalCopiesTable,
                          BookPlacement
                        >(
                          currentTable: table,
                          referencedTable: $$PhysicalCopiesTableReferences
                              ._bookPlacementsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PhysicalCopiesTableReferences(
                                db,
                                table,
                                p0,
                              ).bookPlacementsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.copyId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$PhysicalCopiesTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $PhysicalCopiesTable,
      PhysicalCopy,
      $$PhysicalCopiesTableFilterComposer,
      $$PhysicalCopiesTableOrderingComposer,
      $$PhysicalCopiesTableAnnotationComposer,
      $$PhysicalCopiesTableCreateCompanionBuilder,
      $$PhysicalCopiesTableUpdateCompanionBuilder,
      (PhysicalCopy, $$PhysicalCopiesTableReferences),
      PhysicalCopy,
      PrefetchHooks Function({
        bool bookId,
        bool loansRefs,
        bool copyPhotosRefs,
        bool bookPlacementsRefs,
      })
    >;
typedef $$LoansTableCreateCompanionBuilder =
    LoansCompanion Function({
      required String id,
      required String copyId,
      required String borrower,
      Value<DateTime> loanedAt,
      Value<DateTime?> returnedAt,
      Value<DateTime> updatedAt,
      Value<bool> needsPush,
      Value<DateTime?> dueAt,
      Value<String?> borrowerContact,
      Value<String?> notes,
      Value<DateTime?> reminderSentAt,
      Value<int> rowid,
    });
typedef $$LoansTableUpdateCompanionBuilder =
    LoansCompanion Function({
      Value<String> id,
      Value<String> copyId,
      Value<String> borrower,
      Value<DateTime> loanedAt,
      Value<DateTime?> returnedAt,
      Value<DateTime> updatedAt,
      Value<bool> needsPush,
      Value<DateTime?> dueAt,
      Value<String?> borrowerContact,
      Value<String?> notes,
      Value<DateTime?> reminderSentAt,
      Value<int> rowid,
    });

final class $$LoansTableReferences
    extends BaseReferences<_$VellumDatabase, $LoansTable, Loan> {
  $$LoansTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PhysicalCopiesTable _copyIdTable(_$VellumDatabase db) =>
      db.physicalCopies.createAlias('loans__copy_id__physical_copies__id');

  $$PhysicalCopiesTableProcessedTableManager get copyId {
    final $_column = $_itemColumn<String>('copy_id')!;

    final manager = $$PhysicalCopiesTableTableManager(
      $_db,
      $_db.physicalCopies,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_copyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$LoansTableFilterComposer
    extends Composer<_$VellumDatabase, $LoansTable> {
  $$LoansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get borrower => $composableBuilder(
    column: $table.borrower,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get loanedAt => $composableBuilder(
    column: $table.loanedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get returnedAt => $composableBuilder(
    column: $table.returnedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsPush => $composableBuilder(
    column: $table.needsPush,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get borrowerContact => $composableBuilder(
    column: $table.borrowerContact,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get reminderSentAt => $composableBuilder(
    column: $table.reminderSentAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PhysicalCopiesTableFilterComposer get copyId {
    final $$PhysicalCopiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.copyId,
      referencedTable: $db.physicalCopies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalCopiesTableFilterComposer(
            $db: $db,
            $table: $db.physicalCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LoansTableOrderingComposer
    extends Composer<_$VellumDatabase, $LoansTable> {
  $$LoansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get borrower => $composableBuilder(
    column: $table.borrower,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get loanedAt => $composableBuilder(
    column: $table.loanedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get returnedAt => $composableBuilder(
    column: $table.returnedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsPush => $composableBuilder(
    column: $table.needsPush,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueAt => $composableBuilder(
    column: $table.dueAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get borrowerContact => $composableBuilder(
    column: $table.borrowerContact,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get reminderSentAt => $composableBuilder(
    column: $table.reminderSentAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PhysicalCopiesTableOrderingComposer get copyId {
    final $$PhysicalCopiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.copyId,
      referencedTable: $db.physicalCopies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalCopiesTableOrderingComposer(
            $db: $db,
            $table: $db.physicalCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LoansTableAnnotationComposer
    extends Composer<_$VellumDatabase, $LoansTable> {
  $$LoansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get borrower =>
      $composableBuilder(column: $table.borrower, builder: (column) => column);

  GeneratedColumn<DateTime> get loanedAt =>
      $composableBuilder(column: $table.loanedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get returnedAt => $composableBuilder(
    column: $table.returnedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get needsPush =>
      $composableBuilder(column: $table.needsPush, builder: (column) => column);

  GeneratedColumn<DateTime> get dueAt =>
      $composableBuilder(column: $table.dueAt, builder: (column) => column);

  GeneratedColumn<String> get borrowerContact => $composableBuilder(
    column: $table.borrowerContact,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get reminderSentAt => $composableBuilder(
    column: $table.reminderSentAt,
    builder: (column) => column,
  );

  $$PhysicalCopiesTableAnnotationComposer get copyId {
    final $$PhysicalCopiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.copyId,
      referencedTable: $db.physicalCopies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalCopiesTableAnnotationComposer(
            $db: $db,
            $table: $db.physicalCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$LoansTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $LoansTable,
          Loan,
          $$LoansTableFilterComposer,
          $$LoansTableOrderingComposer,
          $$LoansTableAnnotationComposer,
          $$LoansTableCreateCompanionBuilder,
          $$LoansTableUpdateCompanionBuilder,
          (Loan, $$LoansTableReferences),
          Loan,
          PrefetchHooks Function({bool copyId})
        > {
  $$LoansTableTableManager(_$VellumDatabase db, $LoansTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LoansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LoansTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LoansTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> copyId = const Value.absent(),
                Value<String> borrower = const Value.absent(),
                Value<DateTime> loanedAt = const Value.absent(),
                Value<DateTime?> returnedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<DateTime?> dueAt = const Value.absent(),
                Value<String?> borrowerContact = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime?> reminderSentAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LoansCompanion(
                id: id,
                copyId: copyId,
                borrower: borrower,
                loanedAt: loanedAt,
                returnedAt: returnedAt,
                updatedAt: updatedAt,
                needsPush: needsPush,
                dueAt: dueAt,
                borrowerContact: borrowerContact,
                notes: notes,
                reminderSentAt: reminderSentAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String copyId,
                required String borrower,
                Value<DateTime> loanedAt = const Value.absent(),
                Value<DateTime?> returnedAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<DateTime?> dueAt = const Value.absent(),
                Value<String?> borrowerContact = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<DateTime?> reminderSentAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LoansCompanion.insert(
                id: id,
                copyId: copyId,
                borrower: borrower,
                loanedAt: loanedAt,
                returnedAt: returnedAt,
                updatedAt: updatedAt,
                needsPush: needsPush,
                dueAt: dueAt,
                borrowerContact: borrowerContact,
                notes: notes,
                reminderSentAt: reminderSentAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$LoansTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback: ({copyId = false}) {
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
                    if (copyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.copyId,
                                referencedTable: $$LoansTableReferences
                                    ._copyIdTable(db),
                                referencedColumn: $$LoansTableReferences
                                    ._copyIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$LoansTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $LoansTable,
      Loan,
      $$LoansTableFilterComposer,
      $$LoansTableOrderingComposer,
      $$LoansTableAnnotationComposer,
      $$LoansTableCreateCompanionBuilder,
      $$LoansTableUpdateCompanionBuilder,
      (Loan, $$LoansTableReferences),
      Loan,
      PrefetchHooks Function({bool copyId})
    >;
typedef $$CopyPhotosTableCreateCompanionBuilder =
    CopyPhotosCompanion Function({
      required String id,
      required String copyId,
      required String path,
      Value<DateTime> takenAt,
      Value<String?> caption,
      Value<DateTime> updatedAt,
      Value<bool> needsPush,
      Value<int> rowid,
    });
typedef $$CopyPhotosTableUpdateCompanionBuilder =
    CopyPhotosCompanion Function({
      Value<String> id,
      Value<String> copyId,
      Value<String> path,
      Value<DateTime> takenAt,
      Value<String?> caption,
      Value<DateTime> updatedAt,
      Value<bool> needsPush,
      Value<int> rowid,
    });

final class $$CopyPhotosTableReferences
    extends BaseReferences<_$VellumDatabase, $CopyPhotosTable, CopyPhoto> {
  $$CopyPhotosTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PhysicalCopiesTable _copyIdTable(_$VellumDatabase db) => db
      .physicalCopies
      .createAlias('copy_photos__copy_id__physical_copies__id');

  $$PhysicalCopiesTableProcessedTableManager get copyId {
    final $_column = $_itemColumn<String>('copy_id')!;

    final manager = $$PhysicalCopiesTableTableManager(
      $_db,
      $_db.physicalCopies,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_copyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CopyPhotosTableFilterComposer
    extends Composer<_$VellumDatabase, $CopyPhotosTable> {
  $$CopyPhotosTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get takenAt => $composableBuilder(
    column: $table.takenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get caption => $composableBuilder(
    column: $table.caption,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsPush => $composableBuilder(
    column: $table.needsPush,
    builder: (column) => ColumnFilters(column),
  );

  $$PhysicalCopiesTableFilterComposer get copyId {
    final $$PhysicalCopiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.copyId,
      referencedTable: $db.physicalCopies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalCopiesTableFilterComposer(
            $db: $db,
            $table: $db.physicalCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CopyPhotosTableOrderingComposer
    extends Composer<_$VellumDatabase, $CopyPhotosTable> {
  $$CopyPhotosTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get takenAt => $composableBuilder(
    column: $table.takenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get caption => $composableBuilder(
    column: $table.caption,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsPush => $composableBuilder(
    column: $table.needsPush,
    builder: (column) => ColumnOrderings(column),
  );

  $$PhysicalCopiesTableOrderingComposer get copyId {
    final $$PhysicalCopiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.copyId,
      referencedTable: $db.physicalCopies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalCopiesTableOrderingComposer(
            $db: $db,
            $table: $db.physicalCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CopyPhotosTableAnnotationComposer
    extends Composer<_$VellumDatabase, $CopyPhotosTable> {
  $$CopyPhotosTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<DateTime> get takenAt =>
      $composableBuilder(column: $table.takenAt, builder: (column) => column);

  GeneratedColumn<String> get caption =>
      $composableBuilder(column: $table.caption, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get needsPush =>
      $composableBuilder(column: $table.needsPush, builder: (column) => column);

  $$PhysicalCopiesTableAnnotationComposer get copyId {
    final $$PhysicalCopiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.copyId,
      referencedTable: $db.physicalCopies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalCopiesTableAnnotationComposer(
            $db: $db,
            $table: $db.physicalCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CopyPhotosTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $CopyPhotosTable,
          CopyPhoto,
          $$CopyPhotosTableFilterComposer,
          $$CopyPhotosTableOrderingComposer,
          $$CopyPhotosTableAnnotationComposer,
          $$CopyPhotosTableCreateCompanionBuilder,
          $$CopyPhotosTableUpdateCompanionBuilder,
          (CopyPhoto, $$CopyPhotosTableReferences),
          CopyPhoto,
          PrefetchHooks Function({bool copyId})
        > {
  $$CopyPhotosTableTableManager(_$VellumDatabase db, $CopyPhotosTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CopyPhotosTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CopyPhotosTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CopyPhotosTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> copyId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<DateTime> takenAt = const Value.absent(),
                Value<String?> caption = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CopyPhotosCompanion(
                id: id,
                copyId: copyId,
                path: path,
                takenAt: takenAt,
                caption: caption,
                updatedAt: updatedAt,
                needsPush: needsPush,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String copyId,
                required String path,
                Value<DateTime> takenAt = const Value.absent(),
                Value<String?> caption = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CopyPhotosCompanion.insert(
                id: id,
                copyId: copyId,
                path: path,
                takenAt: takenAt,
                caption: caption,
                updatedAt: updatedAt,
                needsPush: needsPush,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$CopyPhotosTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({copyId = false}) {
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
                    if (copyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.copyId,
                                referencedTable: $$CopyPhotosTableReferences
                                    ._copyIdTable(db),
                                referencedColumn: $$CopyPhotosTableReferences
                                    ._copyIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$CopyPhotosTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $CopyPhotosTable,
      CopyPhoto,
      $$CopyPhotosTableFilterComposer,
      $$CopyPhotosTableOrderingComposer,
      $$CopyPhotosTableAnnotationComposer,
      $$CopyPhotosTableCreateCompanionBuilder,
      $$CopyPhotosTableUpdateCompanionBuilder,
      (CopyPhoto, $$CopyPhotosTableReferences),
      CopyPhoto,
      PrefetchHooks Function({bool copyId})
    >;
typedef $$ShelvesTableCreateCompanionBuilder =
    ShelvesCompanion Function({
      required String id,
      required String name,
      Value<int> sortOrder,
      Value<DateTime> updatedAt,
      Value<bool> isPersonal,
      Value<String?> ownerId,
      Value<bool?> accepted,
      Value<bool> needsPush,
      Value<int> rowid,
    });
typedef $$ShelvesTableUpdateCompanionBuilder =
    ShelvesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> sortOrder,
      Value<DateTime> updatedAt,
      Value<bool> isPersonal,
      Value<String?> ownerId,
      Value<bool?> accepted,
      Value<bool> needsPush,
      Value<int> rowid,
    });

final class $$ShelvesTableReferences
    extends BaseReferences<_$VellumDatabase, $ShelvesTable, Shelf> {
  $$ShelvesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ShelfBooksTable, List<ShelfBook>>
  _shelfBooksRefsTable(_$VellumDatabase db) => MultiTypedResultKey.fromTable(
    db.shelfBooks,
    aliasName: 'shelves__id__shelf_books__shelf_id',
  );

  $$ShelfBooksTableProcessedTableManager get shelfBooksRefs {
    final manager = $$ShelfBooksTableTableManager(
      $_db,
      $_db.shelfBooks,
    ).filter((f) => f.shelfId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_shelfBooksRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ShelvesTableFilterComposer
    extends Composer<_$VellumDatabase, $ShelvesTable> {
  $$ShelvesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isPersonal => $composableBuilder(
    column: $table.isPersonal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get accepted => $composableBuilder(
    column: $table.accepted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsPush => $composableBuilder(
    column: $table.needsPush,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> shelfBooksRefs(
    Expression<bool> Function($$ShelfBooksTableFilterComposer f) f,
  ) {
    final $$ShelfBooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shelfBooks,
      getReferencedColumn: (t) => t.shelfId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShelfBooksTableFilterComposer(
            $db: $db,
            $table: $db.shelfBooks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ShelvesTableOrderingComposer
    extends Composer<_$VellumDatabase, $ShelvesTable> {
  $$ShelvesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isPersonal => $composableBuilder(
    column: $table.isPersonal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ownerId => $composableBuilder(
    column: $table.ownerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get accepted => $composableBuilder(
    column: $table.accepted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsPush => $composableBuilder(
    column: $table.needsPush,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ShelvesTableAnnotationComposer
    extends Composer<_$VellumDatabase, $ShelvesTable> {
  $$ShelvesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get isPersonal => $composableBuilder(
    column: $table.isPersonal,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ownerId =>
      $composableBuilder(column: $table.ownerId, builder: (column) => column);

  GeneratedColumn<bool> get accepted =>
      $composableBuilder(column: $table.accepted, builder: (column) => column);

  GeneratedColumn<bool> get needsPush =>
      $composableBuilder(column: $table.needsPush, builder: (column) => column);

  Expression<T> shelfBooksRefs<T extends Object>(
    Expression<T> Function($$ShelfBooksTableAnnotationComposer a) f,
  ) {
    final $$ShelfBooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.shelfBooks,
      getReferencedColumn: (t) => t.shelfId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShelfBooksTableAnnotationComposer(
            $db: $db,
            $table: $db.shelfBooks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ShelvesTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $ShelvesTable,
          Shelf,
          $$ShelvesTableFilterComposer,
          $$ShelvesTableOrderingComposer,
          $$ShelvesTableAnnotationComposer,
          $$ShelvesTableCreateCompanionBuilder,
          $$ShelvesTableUpdateCompanionBuilder,
          (Shelf, $$ShelvesTableReferences),
          Shelf,
          PrefetchHooks Function({bool shelfBooksRefs})
        > {
  $$ShelvesTableTableManager(_$VellumDatabase db, $ShelvesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShelvesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShelvesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShelvesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isPersonal = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<bool?> accepted = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShelvesCompanion(
                id: id,
                name: name,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
                isPersonal: isPersonal,
                ownerId: ownerId,
                accepted: accepted,
                needsPush: needsPush,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> isPersonal = const Value.absent(),
                Value<String?> ownerId = const Value.absent(),
                Value<bool?> accepted = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShelvesCompanion.insert(
                id: id,
                name: name,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
                isPersonal: isPersonal,
                ownerId: ownerId,
                accepted: accepted,
                needsPush: needsPush,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ShelvesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({shelfBooksRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (shelfBooksRefs) db.shelfBooks],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (shelfBooksRefs)
                    await $_getPrefetchedData<Shelf, $ShelvesTable, ShelfBook>(
                      currentTable: table,
                      referencedTable: $$ShelvesTableReferences
                          ._shelfBooksRefsTable(db),
                      managerFromTypedResult: (p0) => $$ShelvesTableReferences(
                        db,
                        table,
                        p0,
                      ).shelfBooksRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.shelfId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ShelvesTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $ShelvesTable,
      Shelf,
      $$ShelvesTableFilterComposer,
      $$ShelvesTableOrderingComposer,
      $$ShelvesTableAnnotationComposer,
      $$ShelvesTableCreateCompanionBuilder,
      $$ShelvesTableUpdateCompanionBuilder,
      (Shelf, $$ShelvesTableReferences),
      Shelf,
      PrefetchHooks Function({bool shelfBooksRefs})
    >;
typedef $$ShelfBooksTableCreateCompanionBuilder =
    ShelfBooksCompanion Function({
      required String shelfId,
      required String bookId,
      Value<int> position,
      Value<int> rowid,
    });
typedef $$ShelfBooksTableUpdateCompanionBuilder =
    ShelfBooksCompanion Function({
      Value<String> shelfId,
      Value<String> bookId,
      Value<int> position,
      Value<int> rowid,
    });

final class $$ShelfBooksTableReferences
    extends BaseReferences<_$VellumDatabase, $ShelfBooksTable, ShelfBook> {
  $$ShelfBooksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ShelvesTable _shelfIdTable(_$VellumDatabase db) =>
      db.shelves.createAlias('shelf_books__shelf_id__shelves__id');

  $$ShelvesTableProcessedTableManager get shelfId {
    final $_column = $_itemColumn<String>('shelf_id')!;

    final manager = $$ShelvesTableTableManager(
      $_db,
      $_db.shelves,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_shelfIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $BooksTable _bookIdTable(_$VellumDatabase db) =>
      db.books.createAlias('shelf_books__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ShelfBooksTableFilterComposer
    extends Composer<_$VellumDatabase, $ShelfBooksTable> {
  $$ShelfBooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  $$ShelvesTableFilterComposer get shelfId {
    final $$ShelvesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shelfId,
      referencedTable: $db.shelves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShelvesTableFilterComposer(
            $db: $db,
            $table: $db.shelves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShelfBooksTableOrderingComposer
    extends Composer<_$VellumDatabase, $ShelfBooksTable> {
  $$ShelfBooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  $$ShelvesTableOrderingComposer get shelfId {
    final $$ShelvesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shelfId,
      referencedTable: $db.shelves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShelvesTableOrderingComposer(
            $db: $db,
            $table: $db.shelves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShelfBooksTableAnnotationComposer
    extends Composer<_$VellumDatabase, $ShelfBooksTable> {
  $$ShelfBooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  $$ShelvesTableAnnotationComposer get shelfId {
    final $$ShelvesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.shelfId,
      referencedTable: $db.shelves,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ShelvesTableAnnotationComposer(
            $db: $db,
            $table: $db.shelves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ShelfBooksTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $ShelfBooksTable,
          ShelfBook,
          $$ShelfBooksTableFilterComposer,
          $$ShelfBooksTableOrderingComposer,
          $$ShelfBooksTableAnnotationComposer,
          $$ShelfBooksTableCreateCompanionBuilder,
          $$ShelfBooksTableUpdateCompanionBuilder,
          (ShelfBook, $$ShelfBooksTableReferences),
          ShelfBook,
          PrefetchHooks Function({bool shelfId, bool bookId})
        > {
  $$ShelfBooksTableTableManager(_$VellumDatabase db, $ShelfBooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ShelfBooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ShelfBooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ShelfBooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> shelfId = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShelfBooksCompanion(
                shelfId: shelfId,
                bookId: bookId,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String shelfId,
                required String bookId,
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShelfBooksCompanion.insert(
                shelfId: shelfId,
                bookId: bookId,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ShelfBooksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({shelfId = false, bookId = false}) {
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
                    if (shelfId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.shelfId,
                                referencedTable: $$ShelfBooksTableReferences
                                    ._shelfIdTable(db),
                                referencedColumn: $$ShelfBooksTableReferences
                                    ._shelfIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable: $$ShelfBooksTableReferences
                                    ._bookIdTable(db),
                                referencedColumn: $$ShelfBooksTableReferences
                                    ._bookIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$ShelfBooksTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $ShelfBooksTable,
      ShelfBook,
      $$ShelfBooksTableFilterComposer,
      $$ShelfBooksTableOrderingComposer,
      $$ShelfBooksTableAnnotationComposer,
      $$ShelfBooksTableCreateCompanionBuilder,
      $$ShelfBooksTableUpdateCompanionBuilder,
      (ShelfBook, $$ShelfBooksTableReferences),
      ShelfBook,
      PrefetchHooks Function({bool shelfId, bool bookId})
    >;
typedef $$PhysicalEnvironmentsTableCreateCompanionBuilder =
    PhysicalEnvironmentsCompanion Function({
      required String id,
      required String name,
      Value<int> sortOrder,
      Value<DateTime> createdAt,
      Value<int?> serverRevision,
      Value<bool> needsPublish,
      Value<int?> wallColor,
      Value<int?> floorColor,
      Value<bool> roomSurfaces,
      Value<String?> backdropPath,
      Value<double> backdropOpacity,
      Value<double?> backdropScale,
      Value<double> backdropOffsetX,
      Value<double> backdropOffsetY,
      Value<int> rowid,
    });
typedef $$PhysicalEnvironmentsTableUpdateCompanionBuilder =
    PhysicalEnvironmentsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> sortOrder,
      Value<DateTime> createdAt,
      Value<int?> serverRevision,
      Value<bool> needsPublish,
      Value<int?> wallColor,
      Value<int?> floorColor,
      Value<bool> roomSurfaces,
      Value<String?> backdropPath,
      Value<double> backdropOpacity,
      Value<double?> backdropScale,
      Value<double> backdropOffsetX,
      Value<double> backdropOffsetY,
      Value<int> rowid,
    });

final class $$PhysicalEnvironmentsTableReferences
    extends
        BaseReferences<
          _$VellumDatabase,
          $PhysicalEnvironmentsTable,
          PhysicalEnvironment
        > {
  $$PhysicalEnvironmentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$PhysicalShelvesTable, List<PhysicalShelf>>
  _physicalShelvesRefsTable(_$VellumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.physicalShelves,
        aliasName:
            'physical_environments__id__physical_shelves__environment_id',
      );

  $$PhysicalShelvesTableProcessedTableManager get physicalShelvesRefs {
    final manager = $$PhysicalShelvesTableTableManager(
      $_db,
      $_db.physicalShelves,
    ).filter((f) => f.environmentId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _physicalShelvesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$BookPlacementsTable, List<BookPlacement>>
  _bookPlacementsRefsTable(_$VellumDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.bookPlacements,
        aliasName: 'physical_environments__id__book_placements__environment_id',
      );

  $$BookPlacementsTableProcessedTableManager get bookPlacementsRefs {
    final manager = $$BookPlacementsTableTableManager(
      $_db,
      $_db.bookPlacements,
    ).filter((f) => f.environmentId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_bookPlacementsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RoomPropsTable, List<RoomProp>>
  _roomPropsRefsTable(_$VellumDatabase db) => MultiTypedResultKey.fromTable(
    db.roomProps,
    aliasName: 'physical_environments__id__room_props__environment_id',
  );

  $$RoomPropsTableProcessedTableManager get roomPropsRefs {
    final manager = $$RoomPropsTableTableManager(
      $_db,
      $_db.roomProps,
    ).filter((f) => f.environmentId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_roomPropsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PhysicalEnvironmentsTableFilterComposer
    extends Composer<_$VellumDatabase, $PhysicalEnvironmentsTable> {
  $$PhysicalEnvironmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverRevision => $composableBuilder(
    column: $table.serverRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsPublish => $composableBuilder(
    column: $table.needsPublish,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get wallColor => $composableBuilder(
    column: $table.wallColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get floorColor => $composableBuilder(
    column: $table.floorColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get roomSurfaces => $composableBuilder(
    column: $table.roomSurfaces,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get backdropOpacity => $composableBuilder(
    column: $table.backdropOpacity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get backdropScale => $composableBuilder(
    column: $table.backdropScale,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get backdropOffsetX => $composableBuilder(
    column: $table.backdropOffsetX,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get backdropOffsetY => $composableBuilder(
    column: $table.backdropOffsetY,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> physicalShelvesRefs(
    Expression<bool> Function($$PhysicalShelvesTableFilterComposer f) f,
  ) {
    final $$PhysicalShelvesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.physicalShelves,
      getReferencedColumn: (t) => t.environmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalShelvesTableFilterComposer(
            $db: $db,
            $table: $db.physicalShelves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> bookPlacementsRefs(
    Expression<bool> Function($$BookPlacementsTableFilterComposer f) f,
  ) {
    final $$BookPlacementsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookPlacements,
      getReferencedColumn: (t) => t.environmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookPlacementsTableFilterComposer(
            $db: $db,
            $table: $db.bookPlacements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> roomPropsRefs(
    Expression<bool> Function($$RoomPropsTableFilterComposer f) f,
  ) {
    final $$RoomPropsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.roomProps,
      getReferencedColumn: (t) => t.environmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoomPropsTableFilterComposer(
            $db: $db,
            $table: $db.roomProps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PhysicalEnvironmentsTableOrderingComposer
    extends Composer<_$VellumDatabase, $PhysicalEnvironmentsTable> {
  $$PhysicalEnvironmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverRevision => $composableBuilder(
    column: $table.serverRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsPublish => $composableBuilder(
    column: $table.needsPublish,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get wallColor => $composableBuilder(
    column: $table.wallColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get floorColor => $composableBuilder(
    column: $table.floorColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get roomSurfaces => $composableBuilder(
    column: $table.roomSurfaces,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get backdropOpacity => $composableBuilder(
    column: $table.backdropOpacity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get backdropScale => $composableBuilder(
    column: $table.backdropScale,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get backdropOffsetX => $composableBuilder(
    column: $table.backdropOffsetX,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get backdropOffsetY => $composableBuilder(
    column: $table.backdropOffsetY,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PhysicalEnvironmentsTableAnnotationComposer
    extends Composer<_$VellumDatabase, $PhysicalEnvironmentsTable> {
  $$PhysicalEnvironmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get serverRevision => $composableBuilder(
    column: $table.serverRevision,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get needsPublish => $composableBuilder(
    column: $table.needsPublish,
    builder: (column) => column,
  );

  GeneratedColumn<int> get wallColor =>
      $composableBuilder(column: $table.wallColor, builder: (column) => column);

  GeneratedColumn<int> get floorColor => $composableBuilder(
    column: $table.floorColor,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get roomSurfaces => $composableBuilder(
    column: $table.roomSurfaces,
    builder: (column) => column,
  );

  GeneratedColumn<String> get backdropPath => $composableBuilder(
    column: $table.backdropPath,
    builder: (column) => column,
  );

  GeneratedColumn<double> get backdropOpacity => $composableBuilder(
    column: $table.backdropOpacity,
    builder: (column) => column,
  );

  GeneratedColumn<double> get backdropScale => $composableBuilder(
    column: $table.backdropScale,
    builder: (column) => column,
  );

  GeneratedColumn<double> get backdropOffsetX => $composableBuilder(
    column: $table.backdropOffsetX,
    builder: (column) => column,
  );

  GeneratedColumn<double> get backdropOffsetY => $composableBuilder(
    column: $table.backdropOffsetY,
    builder: (column) => column,
  );

  Expression<T> physicalShelvesRefs<T extends Object>(
    Expression<T> Function($$PhysicalShelvesTableAnnotationComposer a) f,
  ) {
    final $$PhysicalShelvesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.physicalShelves,
      getReferencedColumn: (t) => t.environmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalShelvesTableAnnotationComposer(
            $db: $db,
            $table: $db.physicalShelves,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> bookPlacementsRefs<T extends Object>(
    Expression<T> Function($$BookPlacementsTableAnnotationComposer a) f,
  ) {
    final $$BookPlacementsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.bookPlacements,
      getReferencedColumn: (t) => t.environmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookPlacementsTableAnnotationComposer(
            $db: $db,
            $table: $db.bookPlacements,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> roomPropsRefs<T extends Object>(
    Expression<T> Function($$RoomPropsTableAnnotationComposer a) f,
  ) {
    final $$RoomPropsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.roomProps,
      getReferencedColumn: (t) => t.environmentId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoomPropsTableAnnotationComposer(
            $db: $db,
            $table: $db.roomProps,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PhysicalEnvironmentsTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $PhysicalEnvironmentsTable,
          PhysicalEnvironment,
          $$PhysicalEnvironmentsTableFilterComposer,
          $$PhysicalEnvironmentsTableOrderingComposer,
          $$PhysicalEnvironmentsTableAnnotationComposer,
          $$PhysicalEnvironmentsTableCreateCompanionBuilder,
          $$PhysicalEnvironmentsTableUpdateCompanionBuilder,
          (PhysicalEnvironment, $$PhysicalEnvironmentsTableReferences),
          PhysicalEnvironment,
          PrefetchHooks Function({
            bool physicalShelvesRefs,
            bool bookPlacementsRefs,
            bool roomPropsRefs,
          })
        > {
  $$PhysicalEnvironmentsTableTableManager(
    _$VellumDatabase db,
    $PhysicalEnvironmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PhysicalEnvironmentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PhysicalEnvironmentsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PhysicalEnvironmentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int?> serverRevision = const Value.absent(),
                Value<bool> needsPublish = const Value.absent(),
                Value<int?> wallColor = const Value.absent(),
                Value<int?> floorColor = const Value.absent(),
                Value<bool> roomSurfaces = const Value.absent(),
                Value<String?> backdropPath = const Value.absent(),
                Value<double> backdropOpacity = const Value.absent(),
                Value<double?> backdropScale = const Value.absent(),
                Value<double> backdropOffsetX = const Value.absent(),
                Value<double> backdropOffsetY = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhysicalEnvironmentsCompanion(
                id: id,
                name: name,
                sortOrder: sortOrder,
                createdAt: createdAt,
                serverRevision: serverRevision,
                needsPublish: needsPublish,
                wallColor: wallColor,
                floorColor: floorColor,
                roomSurfaces: roomSurfaces,
                backdropPath: backdropPath,
                backdropOpacity: backdropOpacity,
                backdropScale: backdropScale,
                backdropOffsetX: backdropOffsetX,
                backdropOffsetY: backdropOffsetY,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int?> serverRevision = const Value.absent(),
                Value<bool> needsPublish = const Value.absent(),
                Value<int?> wallColor = const Value.absent(),
                Value<int?> floorColor = const Value.absent(),
                Value<bool> roomSurfaces = const Value.absent(),
                Value<String?> backdropPath = const Value.absent(),
                Value<double> backdropOpacity = const Value.absent(),
                Value<double?> backdropScale = const Value.absent(),
                Value<double> backdropOffsetX = const Value.absent(),
                Value<double> backdropOffsetY = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhysicalEnvironmentsCompanion.insert(
                id: id,
                name: name,
                sortOrder: sortOrder,
                createdAt: createdAt,
                serverRevision: serverRevision,
                needsPublish: needsPublish,
                wallColor: wallColor,
                floorColor: floorColor,
                roomSurfaces: roomSurfaces,
                backdropPath: backdropPath,
                backdropOpacity: backdropOpacity,
                backdropScale: backdropScale,
                backdropOffsetX: backdropOffsetX,
                backdropOffsetY: backdropOffsetY,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PhysicalEnvironmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                physicalShelvesRefs = false,
                bookPlacementsRefs = false,
                roomPropsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (physicalShelvesRefs) db.physicalShelves,
                    if (bookPlacementsRefs) db.bookPlacements,
                    if (roomPropsRefs) db.roomProps,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (physicalShelvesRefs)
                        await $_getPrefetchedData<
                          PhysicalEnvironment,
                          $PhysicalEnvironmentsTable,
                          PhysicalShelf
                        >(
                          currentTable: table,
                          referencedTable: $$PhysicalEnvironmentsTableReferences
                              ._physicalShelvesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PhysicalEnvironmentsTableReferences(
                                db,
                                table,
                                p0,
                              ).physicalShelvesRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.environmentId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (bookPlacementsRefs)
                        await $_getPrefetchedData<
                          PhysicalEnvironment,
                          $PhysicalEnvironmentsTable,
                          BookPlacement
                        >(
                          currentTable: table,
                          referencedTable: $$PhysicalEnvironmentsTableReferences
                              ._bookPlacementsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PhysicalEnvironmentsTableReferences(
                                db,
                                table,
                                p0,
                              ).bookPlacementsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.environmentId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (roomPropsRefs)
                        await $_getPrefetchedData<
                          PhysicalEnvironment,
                          $PhysicalEnvironmentsTable,
                          RoomProp
                        >(
                          currentTable: table,
                          referencedTable: $$PhysicalEnvironmentsTableReferences
                              ._roomPropsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$PhysicalEnvironmentsTableReferences(
                                db,
                                table,
                                p0,
                              ).roomPropsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.environmentId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$PhysicalEnvironmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $PhysicalEnvironmentsTable,
      PhysicalEnvironment,
      $$PhysicalEnvironmentsTableFilterComposer,
      $$PhysicalEnvironmentsTableOrderingComposer,
      $$PhysicalEnvironmentsTableAnnotationComposer,
      $$PhysicalEnvironmentsTableCreateCompanionBuilder,
      $$PhysicalEnvironmentsTableUpdateCompanionBuilder,
      (PhysicalEnvironment, $$PhysicalEnvironmentsTableReferences),
      PhysicalEnvironment,
      PrefetchHooks Function({
        bool physicalShelvesRefs,
        bool bookPlacementsRefs,
        bool roomPropsRefs,
      })
    >;
typedef $$PhysicalShelvesTableCreateCompanionBuilder =
    PhysicalShelvesCompanion Function({
      required String id,
      required String environmentId,
      required double x1,
      required double y1,
      required double x2,
      required double y2,
      Value<String?> label,
      Value<String> kind,
      Value<String?> groupId,
      Value<bool> anchored,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$PhysicalShelvesTableUpdateCompanionBuilder =
    PhysicalShelvesCompanion Function({
      Value<String> id,
      Value<String> environmentId,
      Value<double> x1,
      Value<double> y1,
      Value<double> x2,
      Value<double> y2,
      Value<String?> label,
      Value<String> kind,
      Value<String?> groupId,
      Value<bool> anchored,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$PhysicalShelvesTableReferences
    extends
        BaseReferences<_$VellumDatabase, $PhysicalShelvesTable, PhysicalShelf> {
  $$PhysicalShelvesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PhysicalEnvironmentsTable _environmentIdTable(_$VellumDatabase db) =>
      db.physicalEnvironments.createAlias(
        'physical_shelves__environment_id__physical_environments__id',
      );

  $$PhysicalEnvironmentsTableProcessedTableManager get environmentId {
    final $_column = $_itemColumn<String>('environment_id')!;

    final manager = $$PhysicalEnvironmentsTableTableManager(
      $_db,
      $_db.physicalEnvironments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_environmentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PhysicalShelvesTableFilterComposer
    extends Composer<_$VellumDatabase, $PhysicalShelvesTable> {
  $$PhysicalShelvesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get x1 => $composableBuilder(
    column: $table.x1,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get y1 => $composableBuilder(
    column: $table.y1,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get x2 => $composableBuilder(
    column: $table.x2,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get y2 => $composableBuilder(
    column: $table.y2,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get anchored => $composableBuilder(
    column: $table.anchored,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PhysicalEnvironmentsTableFilterComposer get environmentId {
    final $$PhysicalEnvironmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.environmentId,
      referencedTable: $db.physicalEnvironments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalEnvironmentsTableFilterComposer(
            $db: $db,
            $table: $db.physicalEnvironments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PhysicalShelvesTableOrderingComposer
    extends Composer<_$VellumDatabase, $PhysicalShelvesTable> {
  $$PhysicalShelvesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get x1 => $composableBuilder(
    column: $table.x1,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get y1 => $composableBuilder(
    column: $table.y1,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get x2 => $composableBuilder(
    column: $table.x2,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get y2 => $composableBuilder(
    column: $table.y2,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get anchored => $composableBuilder(
    column: $table.anchored,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PhysicalEnvironmentsTableOrderingComposer get environmentId {
    final $$PhysicalEnvironmentsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.environmentId,
          referencedTable: $db.physicalEnvironments,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PhysicalEnvironmentsTableOrderingComposer(
                $db: $db,
                $table: $db.physicalEnvironments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$PhysicalShelvesTableAnnotationComposer
    extends Composer<_$VellumDatabase, $PhysicalShelvesTable> {
  $$PhysicalShelvesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get x1 =>
      $composableBuilder(column: $table.x1, builder: (column) => column);

  GeneratedColumn<double> get y1 =>
      $composableBuilder(column: $table.y1, builder: (column) => column);

  GeneratedColumn<double> get x2 =>
      $composableBuilder(column: $table.x2, builder: (column) => column);

  GeneratedColumn<double> get y2 =>
      $composableBuilder(column: $table.y2, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<bool> get anchored =>
      $composableBuilder(column: $table.anchored, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$PhysicalEnvironmentsTableAnnotationComposer get environmentId {
    final $$PhysicalEnvironmentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.environmentId,
          referencedTable: $db.physicalEnvironments,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PhysicalEnvironmentsTableAnnotationComposer(
                $db: $db,
                $table: $db.physicalEnvironments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$PhysicalShelvesTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $PhysicalShelvesTable,
          PhysicalShelf,
          $$PhysicalShelvesTableFilterComposer,
          $$PhysicalShelvesTableOrderingComposer,
          $$PhysicalShelvesTableAnnotationComposer,
          $$PhysicalShelvesTableCreateCompanionBuilder,
          $$PhysicalShelvesTableUpdateCompanionBuilder,
          (PhysicalShelf, $$PhysicalShelvesTableReferences),
          PhysicalShelf,
          PrefetchHooks Function({bool environmentId})
        > {
  $$PhysicalShelvesTableTableManager(
    _$VellumDatabase db,
    $PhysicalShelvesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PhysicalShelvesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PhysicalShelvesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PhysicalShelvesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> environmentId = const Value.absent(),
                Value<double> x1 = const Value.absent(),
                Value<double> y1 = const Value.absent(),
                Value<double> x2 = const Value.absent(),
                Value<double> y2 = const Value.absent(),
                Value<String?> label = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<bool> anchored = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhysicalShelvesCompanion(
                id: id,
                environmentId: environmentId,
                x1: x1,
                y1: y1,
                x2: x2,
                y2: y2,
                label: label,
                kind: kind,
                groupId: groupId,
                anchored: anchored,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String environmentId,
                required double x1,
                required double y1,
                required double x2,
                required double y2,
                Value<String?> label = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<bool> anchored = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhysicalShelvesCompanion.insert(
                id: id,
                environmentId: environmentId,
                x1: x1,
                y1: y1,
                x2: x2,
                y2: y2,
                label: label,
                kind: kind,
                groupId: groupId,
                anchored: anchored,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PhysicalShelvesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({environmentId = false}) {
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
                    if (environmentId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.environmentId,
                                referencedTable:
                                    $$PhysicalShelvesTableReferences
                                        ._environmentIdTable(db),
                                referencedColumn:
                                    $$PhysicalShelvesTableReferences
                                        ._environmentIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$PhysicalShelvesTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $PhysicalShelvesTable,
      PhysicalShelf,
      $$PhysicalShelvesTableFilterComposer,
      $$PhysicalShelvesTableOrderingComposer,
      $$PhysicalShelvesTableAnnotationComposer,
      $$PhysicalShelvesTableCreateCompanionBuilder,
      $$PhysicalShelvesTableUpdateCompanionBuilder,
      (PhysicalShelf, $$PhysicalShelvesTableReferences),
      PhysicalShelf,
      PrefetchHooks Function({bool environmentId})
    >;
typedef $$BookPlacementsTableCreateCompanionBuilder =
    BookPlacementsCompanion Function({
      required String id,
      required String environmentId,
      required String copyId,
      required double x,
      required double y,
      Value<int> rotation,
      Value<double?> widthOverride,
      Value<double?> heightOverride,
      Value<String?> format,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$BookPlacementsTableUpdateCompanionBuilder =
    BookPlacementsCompanion Function({
      Value<String> id,
      Value<String> environmentId,
      Value<String> copyId,
      Value<double> x,
      Value<double> y,
      Value<int> rotation,
      Value<double?> widthOverride,
      Value<double?> heightOverride,
      Value<String?> format,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$BookPlacementsTableReferences
    extends
        BaseReferences<_$VellumDatabase, $BookPlacementsTable, BookPlacement> {
  $$BookPlacementsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PhysicalEnvironmentsTable _environmentIdTable(_$VellumDatabase db) =>
      db.physicalEnvironments.createAlias(
        'book_placements__environment_id__physical_environments__id',
      );

  $$PhysicalEnvironmentsTableProcessedTableManager get environmentId {
    final $_column = $_itemColumn<String>('environment_id')!;

    final manager = $$PhysicalEnvironmentsTableTableManager(
      $_db,
      $_db.physicalEnvironments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_environmentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $PhysicalCopiesTable _copyIdTable(_$VellumDatabase db) => db
      .physicalCopies
      .createAlias('book_placements__copy_id__physical_copies__id');

  $$PhysicalCopiesTableProcessedTableManager get copyId {
    final $_column = $_itemColumn<String>('copy_id')!;

    final manager = $$PhysicalCopiesTableTableManager(
      $_db,
      $_db.physicalCopies,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_copyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BookPlacementsTableFilterComposer
    extends Composer<_$VellumDatabase, $BookPlacementsTable> {
  $$BookPlacementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get y => $composableBuilder(
    column: $table.y,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rotation => $composableBuilder(
    column: $table.rotation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get widthOverride => $composableBuilder(
    column: $table.widthOverride,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get heightOverride => $composableBuilder(
    column: $table.heightOverride,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PhysicalEnvironmentsTableFilterComposer get environmentId {
    final $$PhysicalEnvironmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.environmentId,
      referencedTable: $db.physicalEnvironments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalEnvironmentsTableFilterComposer(
            $db: $db,
            $table: $db.physicalEnvironments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$PhysicalCopiesTableFilterComposer get copyId {
    final $$PhysicalCopiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.copyId,
      referencedTable: $db.physicalCopies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalCopiesTableFilterComposer(
            $db: $db,
            $table: $db.physicalCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookPlacementsTableOrderingComposer
    extends Composer<_$VellumDatabase, $BookPlacementsTable> {
  $$BookPlacementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get y => $composableBuilder(
    column: $table.y,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rotation => $composableBuilder(
    column: $table.rotation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get widthOverride => $composableBuilder(
    column: $table.widthOverride,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get heightOverride => $composableBuilder(
    column: $table.heightOverride,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get format => $composableBuilder(
    column: $table.format,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PhysicalEnvironmentsTableOrderingComposer get environmentId {
    final $$PhysicalEnvironmentsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.environmentId,
          referencedTable: $db.physicalEnvironments,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PhysicalEnvironmentsTableOrderingComposer(
                $db: $db,
                $table: $db.physicalEnvironments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$PhysicalCopiesTableOrderingComposer get copyId {
    final $$PhysicalCopiesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.copyId,
      referencedTable: $db.physicalCopies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalCopiesTableOrderingComposer(
            $db: $db,
            $table: $db.physicalCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookPlacementsTableAnnotationComposer
    extends Composer<_$VellumDatabase, $BookPlacementsTable> {
  $$BookPlacementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get x =>
      $composableBuilder(column: $table.x, builder: (column) => column);

  GeneratedColumn<double> get y =>
      $composableBuilder(column: $table.y, builder: (column) => column);

  GeneratedColumn<int> get rotation =>
      $composableBuilder(column: $table.rotation, builder: (column) => column);

  GeneratedColumn<double> get widthOverride => $composableBuilder(
    column: $table.widthOverride,
    builder: (column) => column,
  );

  GeneratedColumn<double> get heightOverride => $composableBuilder(
    column: $table.heightOverride,
    builder: (column) => column,
  );

  GeneratedColumn<String> get format =>
      $composableBuilder(column: $table.format, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$PhysicalEnvironmentsTableAnnotationComposer get environmentId {
    final $$PhysicalEnvironmentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.environmentId,
          referencedTable: $db.physicalEnvironments,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PhysicalEnvironmentsTableAnnotationComposer(
                $db: $db,
                $table: $db.physicalEnvironments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  $$PhysicalCopiesTableAnnotationComposer get copyId {
    final $$PhysicalCopiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.copyId,
      referencedTable: $db.physicalCopies,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalCopiesTableAnnotationComposer(
            $db: $db,
            $table: $db.physicalCopies,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookPlacementsTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $BookPlacementsTable,
          BookPlacement,
          $$BookPlacementsTableFilterComposer,
          $$BookPlacementsTableOrderingComposer,
          $$BookPlacementsTableAnnotationComposer,
          $$BookPlacementsTableCreateCompanionBuilder,
          $$BookPlacementsTableUpdateCompanionBuilder,
          (BookPlacement, $$BookPlacementsTableReferences),
          BookPlacement,
          PrefetchHooks Function({bool environmentId, bool copyId})
        > {
  $$BookPlacementsTableTableManager(
    _$VellumDatabase db,
    $BookPlacementsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookPlacementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookPlacementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookPlacementsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> environmentId = const Value.absent(),
                Value<String> copyId = const Value.absent(),
                Value<double> x = const Value.absent(),
                Value<double> y = const Value.absent(),
                Value<int> rotation = const Value.absent(),
                Value<double?> widthOverride = const Value.absent(),
                Value<double?> heightOverride = const Value.absent(),
                Value<String?> format = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookPlacementsCompanion(
                id: id,
                environmentId: environmentId,
                copyId: copyId,
                x: x,
                y: y,
                rotation: rotation,
                widthOverride: widthOverride,
                heightOverride: heightOverride,
                format: format,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String environmentId,
                required String copyId,
                required double x,
                required double y,
                Value<int> rotation = const Value.absent(),
                Value<double?> widthOverride = const Value.absent(),
                Value<double?> heightOverride = const Value.absent(),
                Value<String?> format = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookPlacementsCompanion.insert(
                id: id,
                environmentId: environmentId,
                copyId: copyId,
                x: x,
                y: y,
                rotation: rotation,
                widthOverride: widthOverride,
                heightOverride: heightOverride,
                format: format,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BookPlacementsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({environmentId = false, copyId = false}) {
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
                    if (environmentId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.environmentId,
                                referencedTable: $$BookPlacementsTableReferences
                                    ._environmentIdTable(db),
                                referencedColumn:
                                    $$BookPlacementsTableReferences
                                        ._environmentIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (copyId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.copyId,
                                referencedTable: $$BookPlacementsTableReferences
                                    ._copyIdTable(db),
                                referencedColumn:
                                    $$BookPlacementsTableReferences
                                        ._copyIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$BookPlacementsTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $BookPlacementsTable,
      BookPlacement,
      $$BookPlacementsTableFilterComposer,
      $$BookPlacementsTableOrderingComposer,
      $$BookPlacementsTableAnnotationComposer,
      $$BookPlacementsTableCreateCompanionBuilder,
      $$BookPlacementsTableUpdateCompanionBuilder,
      (BookPlacement, $$BookPlacementsTableReferences),
      BookPlacement,
      PrefetchHooks Function({bool environmentId, bool copyId})
    >;
typedef $$RoomPropsTableCreateCompanionBuilder =
    RoomPropsCompanion Function({
      required String id,
      required String environmentId,
      required String kind,
      required double x,
      required double y,
      required double widthM,
      required double heightM,
      Value<bool> inFront,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$RoomPropsTableUpdateCompanionBuilder =
    RoomPropsCompanion Function({
      Value<String> id,
      Value<String> environmentId,
      Value<String> kind,
      Value<double> x,
      Value<double> y,
      Value<double> widthM,
      Value<double> heightM,
      Value<bool> inFront,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$RoomPropsTableReferences
    extends BaseReferences<_$VellumDatabase, $RoomPropsTable, RoomProp> {
  $$RoomPropsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $PhysicalEnvironmentsTable _environmentIdTable(_$VellumDatabase db) =>
      db.physicalEnvironments.createAlias(
        'room_props__environment_id__physical_environments__id',
      );

  $$PhysicalEnvironmentsTableProcessedTableManager get environmentId {
    final $_column = $_itemColumn<String>('environment_id')!;

    final manager = $$PhysicalEnvironmentsTableTableManager(
      $_db,
      $_db.physicalEnvironments,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_environmentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RoomPropsTableFilterComposer
    extends Composer<_$VellumDatabase, $RoomPropsTable> {
  $$RoomPropsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get y => $composableBuilder(
    column: $table.y,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get widthM => $composableBuilder(
    column: $table.widthM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get heightM => $composableBuilder(
    column: $table.heightM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get inFront => $composableBuilder(
    column: $table.inFront,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$PhysicalEnvironmentsTableFilterComposer get environmentId {
    final $$PhysicalEnvironmentsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.environmentId,
      referencedTable: $db.physicalEnvironments,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PhysicalEnvironmentsTableFilterComposer(
            $db: $db,
            $table: $db.physicalEnvironments,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RoomPropsTableOrderingComposer
    extends Composer<_$VellumDatabase, $RoomPropsTable> {
  $$RoomPropsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get x => $composableBuilder(
    column: $table.x,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get y => $composableBuilder(
    column: $table.y,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get widthM => $composableBuilder(
    column: $table.widthM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get heightM => $composableBuilder(
    column: $table.heightM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get inFront => $composableBuilder(
    column: $table.inFront,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$PhysicalEnvironmentsTableOrderingComposer get environmentId {
    final $$PhysicalEnvironmentsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.environmentId,
          referencedTable: $db.physicalEnvironments,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PhysicalEnvironmentsTableOrderingComposer(
                $db: $db,
                $table: $db.physicalEnvironments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$RoomPropsTableAnnotationComposer
    extends Composer<_$VellumDatabase, $RoomPropsTable> {
  $$RoomPropsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<double> get x =>
      $composableBuilder(column: $table.x, builder: (column) => column);

  GeneratedColumn<double> get y =>
      $composableBuilder(column: $table.y, builder: (column) => column);

  GeneratedColumn<double> get widthM =>
      $composableBuilder(column: $table.widthM, builder: (column) => column);

  GeneratedColumn<double> get heightM =>
      $composableBuilder(column: $table.heightM, builder: (column) => column);

  GeneratedColumn<bool> get inFront =>
      $composableBuilder(column: $table.inFront, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$PhysicalEnvironmentsTableAnnotationComposer get environmentId {
    final $$PhysicalEnvironmentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.environmentId,
          referencedTable: $db.physicalEnvironments,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$PhysicalEnvironmentsTableAnnotationComposer(
                $db: $db,
                $table: $db.physicalEnvironments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$RoomPropsTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $RoomPropsTable,
          RoomProp,
          $$RoomPropsTableFilterComposer,
          $$RoomPropsTableOrderingComposer,
          $$RoomPropsTableAnnotationComposer,
          $$RoomPropsTableCreateCompanionBuilder,
          $$RoomPropsTableUpdateCompanionBuilder,
          (RoomProp, $$RoomPropsTableReferences),
          RoomProp,
          PrefetchHooks Function({bool environmentId})
        > {
  $$RoomPropsTableTableManager(_$VellumDatabase db, $RoomPropsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoomPropsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoomPropsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoomPropsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> environmentId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<double> x = const Value.absent(),
                Value<double> y = const Value.absent(),
                Value<double> widthM = const Value.absent(),
                Value<double> heightM = const Value.absent(),
                Value<bool> inFront = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoomPropsCompanion(
                id: id,
                environmentId: environmentId,
                kind: kind,
                x: x,
                y: y,
                widthM: widthM,
                heightM: heightM,
                inFront: inFront,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String environmentId,
                required String kind,
                required double x,
                required double y,
                required double widthM,
                required double heightM,
                Value<bool> inFront = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoomPropsCompanion.insert(
                id: id,
                environmentId: environmentId,
                kind: kind,
                x: x,
                y: y,
                widthM: widthM,
                heightM: heightM,
                inFront: inFront,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$RoomPropsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({environmentId = false}) {
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
                    if (environmentId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.environmentId,
                                referencedTable: $$RoomPropsTableReferences
                                    ._environmentIdTable(db),
                                referencedColumn: $$RoomPropsTableReferences
                                    ._environmentIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$RoomPropsTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $RoomPropsTable,
      RoomProp,
      $$RoomPropsTableFilterComposer,
      $$RoomPropsTableOrderingComposer,
      $$RoomPropsTableAnnotationComposer,
      $$RoomPropsTableCreateCompanionBuilder,
      $$RoomPropsTableUpdateCompanionBuilder,
      (RoomProp, $$RoomPropsTableReferences),
      RoomProp,
      PrefetchHooks Function({bool environmentId})
    >;
typedef $$LocalDeletionsTableCreateCompanionBuilder =
    LocalDeletionsCompanion Function({
      required String bookId,
      Value<DateTime> deletedAt,
      Value<String> kind,
      Value<int> rowid,
    });
typedef $$LocalDeletionsTableUpdateCompanionBuilder =
    LocalDeletionsCompanion Function({
      Value<String> bookId,
      Value<DateTime> deletedAt,
      Value<String> kind,
      Value<int> rowid,
    });

class $$LocalDeletionsTableFilterComposer
    extends Composer<_$VellumDatabase, $LocalDeletionsTable> {
  $$LocalDeletionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalDeletionsTableOrderingComposer
    extends Composer<_$VellumDatabase, $LocalDeletionsTable> {
  $$LocalDeletionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalDeletionsTableAnnotationComposer
    extends Composer<_$VellumDatabase, $LocalDeletionsTable> {
  $$LocalDeletionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);
}

class $$LocalDeletionsTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $LocalDeletionsTable,
          LocalDeletion,
          $$LocalDeletionsTableFilterComposer,
          $$LocalDeletionsTableOrderingComposer,
          $$LocalDeletionsTableAnnotationComposer,
          $$LocalDeletionsTableCreateCompanionBuilder,
          $$LocalDeletionsTableUpdateCompanionBuilder,
          (
            LocalDeletion,
            BaseReferences<
              _$VellumDatabase,
              $LocalDeletionsTable,
              LocalDeletion
            >,
          ),
          LocalDeletion,
          PrefetchHooks Function()
        > {
  $$LocalDeletionsTableTableManager(
    _$VellumDatabase db,
    $LocalDeletionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalDeletionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalDeletionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalDeletionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<DateTime> deletedAt = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalDeletionsCompanion(
                bookId: bookId,
                deletedAt: deletedAt,
                kind: kind,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                Value<DateTime> deletedAt = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LocalDeletionsCompanion.insert(
                bookId: bookId,
                deletedAt: deletedAt,
                kind: kind,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalDeletionsTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $LocalDeletionsTable,
      LocalDeletion,
      $$LocalDeletionsTableFilterComposer,
      $$LocalDeletionsTableOrderingComposer,
      $$LocalDeletionsTableAnnotationComposer,
      $$LocalDeletionsTableCreateCompanionBuilder,
      $$LocalDeletionsTableUpdateCompanionBuilder,
      (
        LocalDeletion,
        BaseReferences<_$VellumDatabase, $LocalDeletionsTable, LocalDeletion>,
      ),
      LocalDeletion,
      PrefetchHooks Function()
    >;
typedef $$RemoteReadingPositionsTableCreateCompanionBuilder =
    RemoteReadingPositionsCompanion Function({
      required String bookId,
      required String deviceId,
      Value<String?> deviceLabel,
      Value<double?> progress,
      Value<int?> page,
      Value<String?> unit,
      Value<double?> scroll,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$RemoteReadingPositionsTableUpdateCompanionBuilder =
    RemoteReadingPositionsCompanion Function({
      Value<String> bookId,
      Value<String> deviceId,
      Value<String?> deviceLabel,
      Value<double?> progress,
      Value<int?> page,
      Value<String?> unit,
      Value<double?> scroll,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$RemoteReadingPositionsTableFilterComposer
    extends Composer<_$VellumDatabase, $RemoteReadingPositionsTable> {
  $$RemoteReadingPositionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceLabel => $composableBuilder(
    column: $table.deviceLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get scroll => $composableBuilder(
    column: $table.scroll,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RemoteReadingPositionsTableOrderingComposer
    extends Composer<_$VellumDatabase, $RemoteReadingPositionsTable> {
  $$RemoteReadingPositionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceLabel => $composableBuilder(
    column: $table.deviceLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get scroll => $composableBuilder(
    column: $table.scroll,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RemoteReadingPositionsTableAnnotationComposer
    extends Composer<_$VellumDatabase, $RemoteReadingPositionsTable> {
  $$RemoteReadingPositionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get deviceLabel => $composableBuilder(
    column: $table.deviceLabel,
    builder: (column) => column,
  );

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<int> get page =>
      $composableBuilder(column: $table.page, builder: (column) => column);

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<double> get scroll =>
      $composableBuilder(column: $table.scroll, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$RemoteReadingPositionsTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $RemoteReadingPositionsTable,
          RemoteReadingPosition,
          $$RemoteReadingPositionsTableFilterComposer,
          $$RemoteReadingPositionsTableOrderingComposer,
          $$RemoteReadingPositionsTableAnnotationComposer,
          $$RemoteReadingPositionsTableCreateCompanionBuilder,
          $$RemoteReadingPositionsTableUpdateCompanionBuilder,
          (
            RemoteReadingPosition,
            BaseReferences<
              _$VellumDatabase,
              $RemoteReadingPositionsTable,
              RemoteReadingPosition
            >,
          ),
          RemoteReadingPosition,
          PrefetchHooks Function()
        > {
  $$RemoteReadingPositionsTableTableManager(
    _$VellumDatabase db,
    $RemoteReadingPositionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RemoteReadingPositionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$RemoteReadingPositionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RemoteReadingPositionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String?> deviceLabel = const Value.absent(),
                Value<double?> progress = const Value.absent(),
                Value<int?> page = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<double?> scroll = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RemoteReadingPositionsCompanion(
                bookId: bookId,
                deviceId: deviceId,
                deviceLabel: deviceLabel,
                progress: progress,
                page: page,
                unit: unit,
                scroll: scroll,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required String deviceId,
                Value<String?> deviceLabel = const Value.absent(),
                Value<double?> progress = const Value.absent(),
                Value<int?> page = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<double?> scroll = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => RemoteReadingPositionsCompanion.insert(
                bookId: bookId,
                deviceId: deviceId,
                deviceLabel: deviceLabel,
                progress: progress,
                page: page,
                unit: unit,
                scroll: scroll,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RemoteReadingPositionsTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $RemoteReadingPositionsTable,
      RemoteReadingPosition,
      $$RemoteReadingPositionsTableFilterComposer,
      $$RemoteReadingPositionsTableOrderingComposer,
      $$RemoteReadingPositionsTableAnnotationComposer,
      $$RemoteReadingPositionsTableCreateCompanionBuilder,
      $$RemoteReadingPositionsTableUpdateCompanionBuilder,
      (
        RemoteReadingPosition,
        BaseReferences<
          _$VellumDatabase,
          $RemoteReadingPositionsTable,
          RemoteReadingPosition
        >,
      ),
      RemoteReadingPosition,
      PrefetchHooks Function()
    >;
typedef $$AnnotationsTableCreateCompanionBuilder =
    AnnotationsCompanion Function({
      required String id,
      required String bookId,
      required String kind,
      Value<int?> page,
      Value<int?> chapter,
      Value<String?> locator,
      Value<String?> quotedText,
      Value<String?> note,
      Value<int?> color,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> needsPush,
      Value<int> rowid,
    });
typedef $$AnnotationsTableUpdateCompanionBuilder =
    AnnotationsCompanion Function({
      Value<String> id,
      Value<String> bookId,
      Value<String> kind,
      Value<int?> page,
      Value<int?> chapter,
      Value<String?> locator,
      Value<String?> quotedText,
      Value<String?> note,
      Value<int?> color,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> needsPush,
      Value<int> rowid,
    });

final class $$AnnotationsTableReferences
    extends BaseReferences<_$VellumDatabase, $AnnotationsTable, Annotation> {
  $$AnnotationsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BooksTable _bookIdTable(_$VellumDatabase db) =>
      db.books.createAlias('annotations__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AnnotationsTableFilterComposer
    extends Composer<_$VellumDatabase, $AnnotationsTable> {
  $$AnnotationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chapter => $composableBuilder(
    column: $table.chapter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locator => $composableBuilder(
    column: $table.locator,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get quotedText => $composableBuilder(
    column: $table.quotedText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsPush => $composableBuilder(
    column: $table.needsPush,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnnotationsTableOrderingComposer
    extends Composer<_$VellumDatabase, $AnnotationsTable> {
  $$AnnotationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get page => $composableBuilder(
    column: $table.page,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chapter => $composableBuilder(
    column: $table.chapter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locator => $composableBuilder(
    column: $table.locator,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get quotedText => $composableBuilder(
    column: $table.quotedText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsPush => $composableBuilder(
    column: $table.needsPush,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnnotationsTableAnnotationComposer
    extends Composer<_$VellumDatabase, $AnnotationsTable> {
  $$AnnotationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get page =>
      $composableBuilder(column: $table.page, builder: (column) => column);

  GeneratedColumn<int> get chapter =>
      $composableBuilder(column: $table.chapter, builder: (column) => column);

  GeneratedColumn<String> get locator =>
      $composableBuilder(column: $table.locator, builder: (column) => column);

  GeneratedColumn<String> get quotedText => $composableBuilder(
    column: $table.quotedText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get needsPush =>
      $composableBuilder(column: $table.needsPush, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnnotationsTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $AnnotationsTable,
          Annotation,
          $$AnnotationsTableFilterComposer,
          $$AnnotationsTableOrderingComposer,
          $$AnnotationsTableAnnotationComposer,
          $$AnnotationsTableCreateCompanionBuilder,
          $$AnnotationsTableUpdateCompanionBuilder,
          (Annotation, $$AnnotationsTableReferences),
          Annotation,
          PrefetchHooks Function({bool bookId})
        > {
  $$AnnotationsTableTableManager(_$VellumDatabase db, $AnnotationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnnotationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnnotationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnnotationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int?> page = const Value.absent(),
                Value<int?> chapter = const Value.absent(),
                Value<String?> locator = const Value.absent(),
                Value<String?> quotedText = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int?> color = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AnnotationsCompanion(
                id: id,
                bookId: bookId,
                kind: kind,
                page: page,
                chapter: chapter,
                locator: locator,
                quotedText: quotedText,
                note: note,
                color: color,
                createdAt: createdAt,
                updatedAt: updatedAt,
                needsPush: needsPush,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                required String kind,
                Value<int?> page = const Value.absent(),
                Value<int?> chapter = const Value.absent(),
                Value<String?> locator = const Value.absent(),
                Value<String?> quotedText = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<int?> color = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AnnotationsCompanion.insert(
                id: id,
                bookId: bookId,
                kind: kind,
                page: page,
                chapter: chapter,
                locator: locator,
                quotedText: quotedText,
                note: note,
                color: color,
                createdAt: createdAt,
                updatedAt: updatedAt,
                needsPush: needsPush,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AnnotationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
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
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable: $$AnnotationsTableReferences
                                    ._bookIdTable(db),
                                referencedColumn: $$AnnotationsTableReferences
                                    ._bookIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$AnnotationsTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $AnnotationsTable,
      Annotation,
      $$AnnotationsTableFilterComposer,
      $$AnnotationsTableOrderingComposer,
      $$AnnotationsTableAnnotationComposer,
      $$AnnotationsTableCreateCompanionBuilder,
      $$AnnotationsTableUpdateCompanionBuilder,
      (Annotation, $$AnnotationsTableReferences),
      Annotation,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$ReadingSessionsTableCreateCompanionBuilder =
    ReadingSessionsCompanion Function({
      required String id,
      required String bookId,
      required DateTime startedAt,
      required DateTime endedAt,
      Value<int?> startPage,
      Value<int?> endPage,
      Value<String?> deviceId,
      Value<String?> deviceLabel,
      Value<bool> needsPush,
      Value<int> rowid,
    });
typedef $$ReadingSessionsTableUpdateCompanionBuilder =
    ReadingSessionsCompanion Function({
      Value<String> id,
      Value<String> bookId,
      Value<DateTime> startedAt,
      Value<DateTime> endedAt,
      Value<int?> startPage,
      Value<int?> endPage,
      Value<String?> deviceId,
      Value<String?> deviceLabel,
      Value<bool> needsPush,
      Value<int> rowid,
    });

final class $$ReadingSessionsTableReferences
    extends
        BaseReferences<
          _$VellumDatabase,
          $ReadingSessionsTable,
          ReadingSession
        > {
  $$ReadingSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BooksTable _bookIdTable(_$VellumDatabase db) =>
      db.books.createAlias('reading_sessions__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ReadingSessionsTableFilterComposer
    extends Composer<_$VellumDatabase, $ReadingSessionsTable> {
  $$ReadingSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startPage => $composableBuilder(
    column: $table.startPage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endPage => $composableBuilder(
    column: $table.endPage,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceLabel => $composableBuilder(
    column: $table.deviceLabel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsPush => $composableBuilder(
    column: $table.needsPush,
    builder: (column) => ColumnFilters(column),
  );

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingSessionsTableOrderingComposer
    extends Composer<_$VellumDatabase, $ReadingSessionsTable> {
  $$ReadingSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startPage => $composableBuilder(
    column: $table.startPage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endPage => $composableBuilder(
    column: $table.endPage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceLabel => $composableBuilder(
    column: $table.deviceLabel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsPush => $composableBuilder(
    column: $table.needsPush,
    builder: (column) => ColumnOrderings(column),
  );

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingSessionsTableAnnotationComposer
    extends Composer<_$VellumDatabase, $ReadingSessionsTable> {
  $$ReadingSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get startPage =>
      $composableBuilder(column: $table.startPage, builder: (column) => column);

  GeneratedColumn<int> get endPage =>
      $composableBuilder(column: $table.endPage, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get deviceLabel => $composableBuilder(
    column: $table.deviceLabel,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get needsPush =>
      $composableBuilder(column: $table.needsPush, builder: (column) => column);

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ReadingSessionsTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $ReadingSessionsTable,
          ReadingSession,
          $$ReadingSessionsTableFilterComposer,
          $$ReadingSessionsTableOrderingComposer,
          $$ReadingSessionsTableAnnotationComposer,
          $$ReadingSessionsTableCreateCompanionBuilder,
          $$ReadingSessionsTableUpdateCompanionBuilder,
          (ReadingSession, $$ReadingSessionsTableReferences),
          ReadingSession,
          PrefetchHooks Function({bool bookId})
        > {
  $$ReadingSessionsTableTableManager(
    _$VellumDatabase db,
    $ReadingSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReadingSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReadingSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReadingSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime> endedAt = const Value.absent(),
                Value<int?> startPage = const Value.absent(),
                Value<int?> endPage = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String?> deviceLabel = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingSessionsCompanion(
                id: id,
                bookId: bookId,
                startedAt: startedAt,
                endedAt: endedAt,
                startPage: startPage,
                endPage: endPage,
                deviceId: deviceId,
                deviceLabel: deviceLabel,
                needsPush: needsPush,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String bookId,
                required DateTime startedAt,
                required DateTime endedAt,
                Value<int?> startPage = const Value.absent(),
                Value<int?> endPage = const Value.absent(),
                Value<String?> deviceId = const Value.absent(),
                Value<String?> deviceLabel = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReadingSessionsCompanion.insert(
                id: id,
                bookId: bookId,
                startedAt: startedAt,
                endedAt: endedAt,
                startPage: startPage,
                endPage: endPage,
                deviceId: deviceId,
                deviceLabel: deviceLabel,
                needsPush: needsPush,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$ReadingSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({bookId = false}) {
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
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable:
                                    $$ReadingSessionsTableReferences
                                        ._bookIdTable(db),
                                referencedColumn:
                                    $$ReadingSessionsTableReferences
                                        ._bookIdTable(db)
                                        .id,
                              )
                              as T;
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

typedef $$ReadingSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $ReadingSessionsTable,
      ReadingSession,
      $$ReadingSessionsTableFilterComposer,
      $$ReadingSessionsTableOrderingComposer,
      $$ReadingSessionsTableAnnotationComposer,
      $$ReadingSessionsTableCreateCompanionBuilder,
      $$ReadingSessionsTableUpdateCompanionBuilder,
      (ReadingSession, $$ReadingSessionsTableReferences),
      ReadingSession,
      PrefetchHooks Function({bool bookId})
    >;
typedef $$BookTextsTableCreateCompanionBuilder =
    BookTextsCompanion Function({
      required String fileId,
      required String bookId,
      Value<int?> pages,
      Value<DateTime> extractedAt,
      required String status,
      Value<int> rowid,
    });
typedef $$BookTextsTableUpdateCompanionBuilder =
    BookTextsCompanion Function({
      Value<String> fileId,
      Value<String> bookId,
      Value<int?> pages,
      Value<DateTime> extractedAt,
      Value<String> status,
      Value<int> rowid,
    });

final class $$BookTextsTableReferences
    extends BaseReferences<_$VellumDatabase, $BookTextsTable, BookText> {
  $$BookTextsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BookFilesTable _fileIdTable(_$VellumDatabase db) =>
      db.bookFiles.createAlias('book_text__file_id__book_files__id');

  $$BookFilesTableProcessedTableManager get fileId {
    final $_column = $_itemColumn<String>('file_id')!;

    final manager = $$BookFilesTableTableManager(
      $_db,
      $_db.bookFiles,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fileIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $BooksTable _bookIdTable(_$VellumDatabase db) =>
      db.books.createAlias('book_text__book_id__books__id');

  $$BooksTableProcessedTableManager get bookId {
    final $_column = $_itemColumn<String>('book_id')!;

    final manager = $$BooksTableTableManager(
      $_db,
      $_db.books,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_bookIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BookTextsTableFilterComposer
    extends Composer<_$VellumDatabase, $BookTextsTable> {
  $$BookTextsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get pages => $composableBuilder(
    column: $table.pages,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get extractedAt => $composableBuilder(
    column: $table.extractedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  $$BookFilesTableFilterComposer get fileId {
    final $$BookFilesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fileId,
      referencedTable: $db.bookFiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookFilesTableFilterComposer(
            $db: $db,
            $table: $db.bookFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BooksTableFilterComposer get bookId {
    final $$BooksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableFilterComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookTextsTableOrderingComposer
    extends Composer<_$VellumDatabase, $BookTextsTable> {
  $$BookTextsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get pages => $composableBuilder(
    column: $table.pages,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get extractedAt => $composableBuilder(
    column: $table.extractedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  $$BookFilesTableOrderingComposer get fileId {
    final $$BookFilesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fileId,
      referencedTable: $db.bookFiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookFilesTableOrderingComposer(
            $db: $db,
            $table: $db.bookFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BooksTableOrderingComposer get bookId {
    final $$BooksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableOrderingComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookTextsTableAnnotationComposer
    extends Composer<_$VellumDatabase, $BookTextsTable> {
  $$BookTextsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get pages =>
      $composableBuilder(column: $table.pages, builder: (column) => column);

  GeneratedColumn<DateTime> get extractedAt => $composableBuilder(
    column: $table.extractedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  $$BookFilesTableAnnotationComposer get fileId {
    final $$BookFilesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fileId,
      referencedTable: $db.bookFiles,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BookFilesTableAnnotationComposer(
            $db: $db,
            $table: $db.bookFiles,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$BooksTableAnnotationComposer get bookId {
    final $$BooksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.bookId,
      referencedTable: $db.books,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BooksTableAnnotationComposer(
            $db: $db,
            $table: $db.books,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BookTextsTableTableManager
    extends
        RootTableManager<
          _$VellumDatabase,
          $BookTextsTable,
          BookText,
          $$BookTextsTableFilterComposer,
          $$BookTextsTableOrderingComposer,
          $$BookTextsTableAnnotationComposer,
          $$BookTextsTableCreateCompanionBuilder,
          $$BookTextsTableUpdateCompanionBuilder,
          (BookText, $$BookTextsTableReferences),
          BookText,
          PrefetchHooks Function({bool fileId, bool bookId})
        > {
  $$BookTextsTableTableManager(_$VellumDatabase db, $BookTextsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookTextsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookTextsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookTextsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> fileId = const Value.absent(),
                Value<String> bookId = const Value.absent(),
                Value<int?> pages = const Value.absent(),
                Value<DateTime> extractedAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookTextsCompanion(
                fileId: fileId,
                bookId: bookId,
                pages: pages,
                extractedAt: extractedAt,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String fileId,
                required String bookId,
                Value<int?> pages = const Value.absent(),
                Value<DateTime> extractedAt = const Value.absent(),
                required String status,
                Value<int> rowid = const Value.absent(),
              }) => BookTextsCompanion.insert(
                fileId: fileId,
                bookId: bookId,
                pages: pages,
                extractedAt: extractedAt,
                status: status,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BookTextsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({fileId = false, bookId = false}) {
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
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.fileId,
                                referencedTable: $$BookTextsTableReferences
                                    ._fileIdTable(db),
                                referencedColumn: $$BookTextsTableReferences
                                    ._fileIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (bookId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.bookId,
                                referencedTable: $$BookTextsTableReferences
                                    ._bookIdTable(db),
                                referencedColumn: $$BookTextsTableReferences
                                    ._bookIdTable(db)
                                    .id,
                              )
                              as T;
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

typedef $$BookTextsTableProcessedTableManager =
    ProcessedTableManager<
      _$VellumDatabase,
      $BookTextsTable,
      BookText,
      $$BookTextsTableFilterComposer,
      $$BookTextsTableOrderingComposer,
      $$BookTextsTableAnnotationComposer,
      $$BookTextsTableCreateCompanionBuilder,
      $$BookTextsTableUpdateCompanionBuilder,
      (BookText, $$BookTextsTableReferences),
      BookText,
      PrefetchHooks Function({bool fileId, bool bookId})
    >;

class $VellumDatabaseManager {
  final _$VellumDatabase _db;
  $VellumDatabaseManager(this._db);
  $$SeriesTableTableManager get series =>
      $$SeriesTableTableManager(_db, _db.series);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$AuthorsTableTableManager get authors =>
      $$AuthorsTableTableManager(_db, _db.authors);
  $$BookAuthorsTableTableManager get bookAuthors =>
      $$BookAuthorsTableTableManager(_db, _db.bookAuthors);
  $$GenresTableTableManager get genres =>
      $$GenresTableTableManager(_db, _db.genres);
  $$BookGenresTableTableManager get bookGenres =>
      $$BookGenresTableTableManager(_db, _db.bookGenres);
  $$BookFilesTableTableManager get bookFiles =>
      $$BookFilesTableTableManager(_db, _db.bookFiles);
  $$PhysicalCopiesTableTableManager get physicalCopies =>
      $$PhysicalCopiesTableTableManager(_db, _db.physicalCopies);
  $$LoansTableTableManager get loans =>
      $$LoansTableTableManager(_db, _db.loans);
  $$CopyPhotosTableTableManager get copyPhotos =>
      $$CopyPhotosTableTableManager(_db, _db.copyPhotos);
  $$ShelvesTableTableManager get shelves =>
      $$ShelvesTableTableManager(_db, _db.shelves);
  $$ShelfBooksTableTableManager get shelfBooks =>
      $$ShelfBooksTableTableManager(_db, _db.shelfBooks);
  $$PhysicalEnvironmentsTableTableManager get physicalEnvironments =>
      $$PhysicalEnvironmentsTableTableManager(_db, _db.physicalEnvironments);
  $$PhysicalShelvesTableTableManager get physicalShelves =>
      $$PhysicalShelvesTableTableManager(_db, _db.physicalShelves);
  $$BookPlacementsTableTableManager get bookPlacements =>
      $$BookPlacementsTableTableManager(_db, _db.bookPlacements);
  $$RoomPropsTableTableManager get roomProps =>
      $$RoomPropsTableTableManager(_db, _db.roomProps);
  $$LocalDeletionsTableTableManager get localDeletions =>
      $$LocalDeletionsTableTableManager(_db, _db.localDeletions);
  $$RemoteReadingPositionsTableTableManager get remoteReadingPositions =>
      $$RemoteReadingPositionsTableTableManager(
        _db,
        _db.remoteReadingPositions,
      );
  $$AnnotationsTableTableManager get annotations =>
      $$AnnotationsTableTableManager(_db, _db.annotations);
  $$ReadingSessionsTableTableManager get readingSessions =>
      $$ReadingSessionsTableTableManager(_db, _db.readingSessions);
  $$BookTextsTableTableManager get bookTexts =>
      $$BookTextsTableTableManager(_db, _db.bookTexts);
}
