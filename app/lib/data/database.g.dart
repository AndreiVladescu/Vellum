// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
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
    readingProgress,
    lastReadPage,
    lastReadAt,
    readerNotes,
    sourceMetadata,
    createdAt,
    updatedAt,
    needsPush,
    coverEtag,
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
  final double? readingProgress;
  final int? lastReadPage;
  final DateTime? lastReadAt;
  final String? readerNotes;
  final String? sourceMetadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool needsPush;
  final String? coverEtag;
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
    this.readingProgress,
    this.lastReadPage,
    this.lastReadAt,
    this.readerNotes,
    this.sourceMetadata,
    required this.createdAt,
    required this.updatedAt,
    required this.needsPush,
    this.coverEtag,
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
    if (!nullToAbsent || sourceMetadata != null) {
      map['source_metadata'] = Variable<String>(sourceMetadata);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['needs_push'] = Variable<bool>(needsPush);
    if (!nullToAbsent || coverEtag != null) {
      map['cover_etag'] = Variable<String>(coverEtag);
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
      sourceMetadata: sourceMetadata == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceMetadata),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      needsPush: Value(needsPush),
      coverEtag: coverEtag == null && nullToAbsent
          ? const Value.absent()
          : Value(coverEtag),
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
      readingProgress: serializer.fromJson<double?>(json['readingProgress']),
      lastReadPage: serializer.fromJson<int?>(json['lastReadPage']),
      lastReadAt: serializer.fromJson<DateTime?>(json['lastReadAt']),
      readerNotes: serializer.fromJson<String?>(json['readerNotes']),
      sourceMetadata: serializer.fromJson<String?>(json['sourceMetadata']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      needsPush: serializer.fromJson<bool>(json['needsPush']),
      coverEtag: serializer.fromJson<String?>(json['coverEtag']),
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
      'readingProgress': serializer.toJson<double?>(readingProgress),
      'lastReadPage': serializer.toJson<int?>(lastReadPage),
      'lastReadAt': serializer.toJson<DateTime?>(lastReadAt),
      'readerNotes': serializer.toJson<String?>(readerNotes),
      'sourceMetadata': serializer.toJson<String?>(sourceMetadata),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'needsPush': serializer.toJson<bool>(needsPush),
      'coverEtag': serializer.toJson<String?>(coverEtag),
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
    Value<double?> readingProgress = const Value.absent(),
    Value<int?> lastReadPage = const Value.absent(),
    Value<DateTime?> lastReadAt = const Value.absent(),
    Value<String?> readerNotes = const Value.absent(),
    Value<String?> sourceMetadata = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? needsPush,
    Value<String?> coverEtag = const Value.absent(),
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
    readingProgress: readingProgress.present
        ? readingProgress.value
        : this.readingProgress,
    lastReadPage: lastReadPage.present ? lastReadPage.value : this.lastReadPage,
    lastReadAt: lastReadAt.present ? lastReadAt.value : this.lastReadAt,
    readerNotes: readerNotes.present ? readerNotes.value : this.readerNotes,
    sourceMetadata: sourceMetadata.present
        ? sourceMetadata.value
        : this.sourceMetadata,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    needsPush: needsPush ?? this.needsPush,
    coverEtag: coverEtag.present ? coverEtag.value : this.coverEtag,
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
      sourceMetadata: data.sourceMetadata.present
          ? data.sourceMetadata.value
          : this.sourceMetadata,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      needsPush: data.needsPush.present ? data.needsPush.value : this.needsPush,
      coverEtag: data.coverEtag.present ? data.coverEtag.value : this.coverEtag,
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
          ..write('readingProgress: $readingProgress, ')
          ..write('lastReadPage: $lastReadPage, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('readerNotes: $readerNotes, ')
          ..write('sourceMetadata: $sourceMetadata, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('needsPush: $needsPush, ')
          ..write('coverEtag: $coverEtag')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
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
    readingProgress,
    lastReadPage,
    lastReadAt,
    readerNotes,
    sourceMetadata,
    createdAt,
    updatedAt,
    needsPush,
    coverEtag,
  );
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
          other.readingProgress == this.readingProgress &&
          other.lastReadPage == this.lastReadPage &&
          other.lastReadAt == this.lastReadAt &&
          other.readerNotes == this.readerNotes &&
          other.sourceMetadata == this.sourceMetadata &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.needsPush == this.needsPush &&
          other.coverEtag == this.coverEtag);
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
  final Value<double?> readingProgress;
  final Value<int?> lastReadPage;
  final Value<DateTime?> lastReadAt;
  final Value<String?> readerNotes;
  final Value<String?> sourceMetadata;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<bool> needsPush;
  final Value<String?> coverEtag;
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
    this.readingProgress = const Value.absent(),
    this.lastReadPage = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.readerNotes = const Value.absent(),
    this.sourceMetadata = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.coverEtag = const Value.absent(),
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
    this.readingProgress = const Value.absent(),
    this.lastReadPage = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.readerNotes = const Value.absent(),
    this.sourceMetadata = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.coverEtag = const Value.absent(),
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
    Expression<double>? readingProgress,
    Expression<int>? lastReadPage,
    Expression<DateTime>? lastReadAt,
    Expression<String>? readerNotes,
    Expression<String>? sourceMetadata,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<bool>? needsPush,
    Expression<String>? coverEtag,
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
      if (readingProgress != null) 'reading_progress': readingProgress,
      if (lastReadPage != null) 'last_read_page': lastReadPage,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (readerNotes != null) 'reader_notes': readerNotes,
      if (sourceMetadata != null) 'source_metadata': sourceMetadata,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (needsPush != null) 'needs_push': needsPush,
      if (coverEtag != null) 'cover_etag': coverEtag,
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
    Value<double?>? readingProgress,
    Value<int?>? lastReadPage,
    Value<DateTime?>? lastReadAt,
    Value<String?>? readerNotes,
    Value<String?>? sourceMetadata,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<bool>? needsPush,
    Value<String?>? coverEtag,
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
      readingProgress: readingProgress ?? this.readingProgress,
      lastReadPage: lastReadPage ?? this.lastReadPage,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      readerNotes: readerNotes ?? this.readerNotes,
      sourceMetadata: sourceMetadata ?? this.sourceMetadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      needsPush: needsPush ?? this.needsPush,
      coverEtag: coverEtag ?? this.coverEtag,
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
          ..write('readingProgress: $readingProgress, ')
          ..write('lastReadPage: $lastReadPage, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('readerNotes: $readerNotes, ')
          ..write('sourceMetadata: $sourceMetadata, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('needsPush: $needsPush, ')
          ..write('coverEtag: $coverEtag, ')
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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    copyId,
    borrower,
    loanedAt,
    returnedAt,
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
  const Loan({
    required this.id,
    required this.copyId,
    required this.borrower,
    required this.loanedAt,
    this.returnedAt,
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
    };
  }

  Loan copyWith({
    String? id,
    String? copyId,
    String? borrower,
    DateTime? loanedAt,
    Value<DateTime?> returnedAt = const Value.absent(),
  }) => Loan(
    id: id ?? this.id,
    copyId: copyId ?? this.copyId,
    borrower: borrower ?? this.borrower,
    loanedAt: loanedAt ?? this.loanedAt,
    returnedAt: returnedAt.present ? returnedAt.value : this.returnedAt,
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
    );
  }

  @override
  String toString() {
    return (StringBuffer('Loan(')
          ..write('id: $id, ')
          ..write('copyId: $copyId, ')
          ..write('borrower: $borrower, ')
          ..write('loanedAt: $loanedAt, ')
          ..write('returnedAt: $returnedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, copyId, borrower, loanedAt, returnedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Loan &&
          other.id == this.id &&
          other.copyId == this.copyId &&
          other.borrower == this.borrower &&
          other.loanedAt == this.loanedAt &&
          other.returnedAt == this.returnedAt);
}

class LoansCompanion extends UpdateCompanion<Loan> {
  final Value<String> id;
  final Value<String> copyId;
  final Value<String> borrower;
  final Value<DateTime> loanedAt;
  final Value<DateTime?> returnedAt;
  final Value<int> rowid;
  const LoansCompanion({
    this.id = const Value.absent(),
    this.copyId = const Value.absent(),
    this.borrower = const Value.absent(),
    this.loanedAt = const Value.absent(),
    this.returnedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LoansCompanion.insert({
    required String id,
    required String copyId,
    required String borrower,
    this.loanedAt = const Value.absent(),
    this.returnedAt = const Value.absent(),
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
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (copyId != null) 'copy_id': copyId,
      if (borrower != null) 'borrower': borrower,
      if (loanedAt != null) 'loaned_at': loanedAt,
      if (returnedAt != null) 'returned_at': returnedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LoansCompanion copyWith({
    Value<String>? id,
    Value<String>? copyId,
    Value<String>? borrower,
    Value<DateTime>? loanedAt,
    Value<DateTime?>? returnedAt,
    Value<int>? rowid,
  }) {
    return LoansCompanion(
      id: id ?? this.id,
      copyId: copyId ?? this.copyId,
      borrower: borrower ?? this.borrower,
      loanedAt: loanedAt ?? this.loanedAt,
      returnedAt: returnedAt ?? this.returnedAt,
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
  final bool needsPush;
  const Shelf({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.updatedAt,
    required this.needsPush,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['needs_push'] = Variable<bool>(needsPush);
    return map;
  }

  ShelvesCompanion toCompanion(bool nullToAbsent) {
    return ShelvesCompanion(
      id: Value(id),
      name: Value(name),
      sortOrder: Value(sortOrder),
      updatedAt: Value(updatedAt),
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
      'needsPush': serializer.toJson<bool>(needsPush),
    };
  }

  Shelf copyWith({
    String? id,
    String? name,
    int? sortOrder,
    DateTime? updatedAt,
    bool? needsPush,
  }) => Shelf(
    id: id ?? this.id,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    updatedAt: updatedAt ?? this.updatedAt,
    needsPush: needsPush ?? this.needsPush,
  );
  Shelf copyWithCompanion(ShelvesCompanion data) {
    return Shelf(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
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
          ..write('needsPush: $needsPush')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, sortOrder, updatedAt, needsPush);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Shelf &&
          other.id == this.id &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.updatedAt == this.updatedAt &&
          other.needsPush == this.needsPush);
}

class ShelvesCompanion extends UpdateCompanion<Shelf> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime> updatedAt;
  final Value<bool> needsPush;
  final Value<int> rowid;
  const ShelvesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ShelvesCompanion.insert({
    required String id,
    required String name,
    this.sortOrder = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.needsPush = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<Shelf> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? updatedAt,
    Expression<bool>? needsPush,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (needsPush != null) 'needs_push': needsPush,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ShelvesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<DateTime>? updatedAt,
    Value<bool>? needsPush,
    Value<int>? rowid,
  }) {
    return ShelvesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
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
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
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
    return (StringBuffer('ShelvesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('updatedAt: $updatedAt, ')
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
  @override
  List<GeneratedColumn> get $columns => [id, name, sortOrder, createdAt];
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
  const PhysicalEnvironment({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PhysicalEnvironmentsCompanion toCompanion(bool nullToAbsent) {
    return PhysicalEnvironmentsCompanion(
      id: Value(id),
      name: Value(name),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
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
    };
  }

  PhysicalEnvironment copyWith({
    String? id,
    String? name,
    int? sortOrder,
    DateTime? createdAt,
  }) => PhysicalEnvironment(
    id: id ?? this.id,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
  );
  PhysicalEnvironment copyWithCompanion(PhysicalEnvironmentsCompanion data) {
    return PhysicalEnvironment(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PhysicalEnvironment(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, sortOrder, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PhysicalEnvironment &&
          other.id == this.id &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt);
}

class PhysicalEnvironmentsCompanion
    extends UpdateCompanion<PhysicalEnvironment> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const PhysicalEnvironmentsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PhysicalEnvironmentsCompanion.insert({
    required String id,
    required String name,
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name);
  static Insertable<PhysicalEnvironment> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PhysicalEnvironmentsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return PhysicalEnvironmentsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
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
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
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
    return (StringBuffer('PhysicalEnvironmentsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
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
  final DateTime createdAt;
  const PhysicalShelf({
    required this.id,
    required this.environmentId,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.label,
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
    DateTime? createdAt,
  }) => PhysicalShelf(
    id: id ?? this.id,
    environmentId: environmentId ?? this.environmentId,
    x1: x1 ?? this.x1,
    y1: y1 ?? this.y1,
    x2: x2 ?? this.x2,
    y2: y2 ?? this.y2,
    label: label.present ? label.value : this.label,
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
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, environmentId, x1, y1, x2, y2, label, createdAt);
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

abstract class _$VellumDatabase extends GeneratedDatabase {
  _$VellumDatabase(QueryExecutor e) : super(e);
  $VellumDatabaseManager get managers => $VellumDatabaseManager(this);
  late final $BooksTable books = $BooksTable(this);
  late final $AuthorsTable authors = $AuthorsTable(this);
  late final $BookAuthorsTable bookAuthors = $BookAuthorsTable(this);
  late final $GenresTable genres = $GenresTable(this);
  late final $BookGenresTable bookGenres = $BookGenresTable(this);
  late final $BookFilesTable bookFiles = $BookFilesTable(this);
  late final $PhysicalCopiesTable physicalCopies = $PhysicalCopiesTable(this);
  late final $LoansTable loans = $LoansTable(this);
  late final $ShelvesTable shelves = $ShelvesTable(this);
  late final $ShelfBooksTable shelfBooks = $ShelfBooksTable(this);
  late final $PhysicalEnvironmentsTable physicalEnvironments =
      $PhysicalEnvironmentsTable(this);
  late final $PhysicalShelvesTable physicalShelves = $PhysicalShelvesTable(
    this,
  );
  late final $BookPlacementsTable bookPlacements = $BookPlacementsTable(this);
  late final $LocalDeletionsTable localDeletions = $LocalDeletionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    books,
    authors,
    bookAuthors,
    genres,
    bookGenres,
    bookFiles,
    physicalCopies,
    loans,
    shelves,
    shelfBooks,
    physicalEnvironments,
    physicalShelves,
    bookPlacements,
    localDeletions,
  ];
}

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
      Value<double?> readingProgress,
      Value<int?> lastReadPage,
      Value<DateTime?> lastReadAt,
      Value<String?> readerNotes,
      Value<String?> sourceMetadata,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> needsPush,
      Value<String?> coverEtag,
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
      Value<double?> readingProgress,
      Value<int?> lastReadPage,
      Value<DateTime?> lastReadAt,
      Value<String?> readerNotes,
      Value<String?> sourceMetadata,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<bool> needsPush,
      Value<String?> coverEtag,
      Value<int> rowid,
    });

final class $$BooksTableReferences
    extends BaseReferences<_$VellumDatabase, $BooksTable, Book> {
  $$BooksTableReferences(super.$_db, super.$_table, super.$_typedResult);

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
            bool bookAuthorsRefs,
            bool bookGenresRefs,
            bool bookFilesRefs,
            bool physicalCopiesRefs,
            bool shelfBooksRefs,
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
                Value<double?> readingProgress = const Value.absent(),
                Value<int?> lastReadPage = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<String?> readerNotes = const Value.absent(),
                Value<String?> sourceMetadata = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<String?> coverEtag = const Value.absent(),
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
                readingProgress: readingProgress,
                lastReadPage: lastReadPage,
                lastReadAt: lastReadAt,
                readerNotes: readerNotes,
                sourceMetadata: sourceMetadata,
                createdAt: createdAt,
                updatedAt: updatedAt,
                needsPush: needsPush,
                coverEtag: coverEtag,
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
                Value<double?> readingProgress = const Value.absent(),
                Value<int?> lastReadPage = const Value.absent(),
                Value<DateTime?> lastReadAt = const Value.absent(),
                Value<String?> readerNotes = const Value.absent(),
                Value<String?> sourceMetadata = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<String?> coverEtag = const Value.absent(),
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
                readingProgress: readingProgress,
                lastReadPage: lastReadPage,
                lastReadAt: lastReadAt,
                readerNotes: readerNotes,
                sourceMetadata: sourceMetadata,
                createdAt: createdAt,
                updatedAt: updatedAt,
                needsPush: needsPush,
                coverEtag: coverEtag,
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
                bookAuthorsRefs = false,
                bookGenresRefs = false,
                bookFilesRefs = false,
                physicalCopiesRefs = false,
                shelfBooksRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (bookAuthorsRefs) db.bookAuthors,
                    if (bookGenresRefs) db.bookGenres,
                    if (bookFilesRefs) db.bookFiles,
                    if (physicalCopiesRefs) db.physicalCopies,
                    if (shelfBooksRefs) db.shelfBooks,
                  ],
                  addJoins: null,
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
        bool bookAuthorsRefs,
        bool bookGenresRefs,
        bool bookFilesRefs,
        bool physicalCopiesRefs,
        bool shelfBooksRefs,
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
          PrefetchHooks Function({bool bookId})
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
                return [];
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
      PrefetchHooks Function({bool bookId})
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
                bookPlacementsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (loansRefs) db.loans,
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
      Value<int> rowid,
    });
typedef $$LoansTableUpdateCompanionBuilder =
    LoansCompanion Function({
      Value<String> id,
      Value<String> copyId,
      Value<String> borrower,
      Value<DateTime> loanedAt,
      Value<DateTime?> returnedAt,
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
                Value<int> rowid = const Value.absent(),
              }) => LoansCompanion(
                id: id,
                copyId: copyId,
                borrower: borrower,
                loanedAt: loanedAt,
                returnedAt: returnedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String copyId,
                required String borrower,
                Value<DateTime> loanedAt = const Value.absent(),
                Value<DateTime?> returnedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LoansCompanion.insert(
                id: id,
                copyId: copyId,
                borrower: borrower,
                loanedAt: loanedAt,
                returnedAt: returnedAt,
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
typedef $$ShelvesTableCreateCompanionBuilder =
    ShelvesCompanion Function({
      required String id,
      required String name,
      Value<int> sortOrder,
      Value<DateTime> updatedAt,
      Value<bool> needsPush,
      Value<int> rowid,
    });
typedef $$ShelvesTableUpdateCompanionBuilder =
    ShelvesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> sortOrder,
      Value<DateTime> updatedAt,
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
                Value<bool> needsPush = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShelvesCompanion(
                id: id,
                name: name,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
                needsPush: needsPush,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<bool> needsPush = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ShelvesCompanion.insert(
                id: id,
                name: name,
                sortOrder: sortOrder,
                updatedAt: updatedAt,
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
      Value<int> rowid,
    });
typedef $$PhysicalEnvironmentsTableUpdateCompanionBuilder =
    PhysicalEnvironmentsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> sortOrder,
      Value<DateTime> createdAt,
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
                Value<int> rowid = const Value.absent(),
              }) => PhysicalEnvironmentsCompanion(
                id: id,
                name: name,
                sortOrder: sortOrder,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PhysicalEnvironmentsCompanion.insert(
                id: id,
                name: name,
                sortOrder: sortOrder,
                createdAt: createdAt,
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
              ({physicalShelvesRefs = false, bookPlacementsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (physicalShelvesRefs) db.physicalShelves,
                    if (bookPlacementsRefs) db.bookPlacements,
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

class $VellumDatabaseManager {
  final _$VellumDatabase _db;
  $VellumDatabaseManager(this._db);
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
  $$LocalDeletionsTableTableManager get localDeletions =>
      $$LocalDeletionsTableTableManager(_db, _db.localDeletions);
}
