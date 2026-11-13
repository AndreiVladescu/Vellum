// Localised words for enums whose English text lives on the enum itself.
//
// The enums (`ReadingStatus.label`, `ShelfSort.label`, ...) are plain Dart with
// no BuildContext, and are used by code that has none, so the lookup sits next
// to them here instead: the widget that shows the value asks
// `status.labelOf(L10n.of(context))`.
import '../data/reading_status.dart';
import '../data/backup_schedule.dart';
import '../data/backup_service.dart';
import '../data/library_doctor.dart';
import '../dedupe/duplicate_finder.dart' show DuplicateReason;
import '../import/free_catalogues.dart' show FreeCatalogue;
import '../physical/bookcase_template.dart' show BookcaseStyle;
import '../physical/locate.dart' show TidySort;
import '../physical/physical_metrics.dart' show BookFormat;
import '../physical/room_measure.dart' show ShelfKind;
import '../physical/room_prop.dart' show PropKind;
import '../dedupe/merge_service.dart' show MergeConflict;
import '../server/background_sync.dart';
import '../server/sync_scope.dart' show SyncScope;
import '../server/sync_service.dart' show SyncIssue, SyncNote, SyncPhase;
import '../settings/appearance.dart';
import '../settings/book_face.dart';
import '../settings/shelf_sort.dart';
import '../settings/spine_art.dart';
import '../reader/annotations/annotation_store.dart';
import '../reader/annotations/highlight_palette.dart';
import '../reader/dictionary/wordnet.dart';
import '../reader/ink_tools.dart';
import '../reader/page_metric.dart';
import '../reader/reader_settings.dart';
import '../reader/translate/translation_backend.dart';
import '../settings/wallpaper.dart';
import 'gen/app_localizations.dart';

extension ReadingStatusL10n on ReadingStatus {
  String labelOf(L10n l10n) => switch (this) {
    ReadingStatus.unread => l10n.statusUnread,
    ReadingStatus.reading => l10n.statusReading,
    ReadingStatus.finished => l10n.statusFinished,
    ReadingStatus.abandoned => l10n.statusAbandoned,
    ReadingStatus.reference => l10n.statusReference,
    ReadingStatus.wishlist => l10n.statusWishlist,
  };

  String descriptionOf(L10n l10n) => switch (this) {
    ReadingStatus.unread => l10n.statusUnreadDescription,
    ReadingStatus.reading => l10n.statusReadingDescription,
    ReadingStatus.finished => l10n.statusFinishedDescription,
    ReadingStatus.abandoned => l10n.statusAbandonedDescription,
    ReadingStatus.reference => l10n.statusReferenceDescription,
    ReadingStatus.wishlist => l10n.statusWishlistDescription,
  };
}

extension ShelfSortL10n on ShelfSort {
  String labelOf(L10n l10n) => switch (this) {
    ShelfSort.title => l10n.sortTitle,
    ShelfSort.author => l10n.sortAuthor,
    ShelfSort.year => l10n.sortYear,
    ShelfSort.series => l10n.sortSeries,
  };
}

extension BookFaceL10n on BookFace {
  String labelOf(L10n l10n) => switch (this) {
    BookFace.spine => l10n.prefsFaceSpine,
    BookFace.cover => l10n.prefsFaceCover,
    BookFace.list => l10n.prefsFaceList,
  };
}

extension SpineArtL10n on SpineArt {
  String labelOf(L10n l10n) => switch (this) {
    SpineArt.coverSlice => l10n.prefsSpineArtCoverSlice,
    SpineArt.dominantColor => l10n.prefsSpineArtDominantColour,
  };
}

extension WallpaperL10n on Wallpaper {
  String labelOf(L10n l10n) => switch (this) {
    Wallpaper.parchment => l10n.prefsWallpaperParchment,
    Wallpaper.fern => l10n.prefsWallpaperFern,
    Wallpaper.ocean => l10n.prefsWallpaperOcean,
  };
}

extension SeedPresetL10n on SeedPreset {
  String labelOf(L10n l10n) => switch (this) {
    SeedPreset.leather => l10n.prefsSeedLeather,
    SeedPreset.ink => l10n.prefsSeedInk,
    SeedPreset.forest => l10n.prefsSeedForest,
    SeedPreset.slate => l10n.prefsSeedSlate,
    SeedPreset.plum => l10n.prefsSeedPlum,
    SeedPreset.ember => l10n.prefsSeedEmber,
  };
}

extension ShelfMaterialL10n on ShelfMaterial {
  String labelOf(L10n l10n) => switch (this) {
    ShelfMaterial.oak => l10n.prefsMaterialOak,
    ShelfMaterial.walnut => l10n.prefsMaterialWalnut,
    ShelfMaterial.ebony => l10n.prefsMaterialEbony,
    ShelfMaterial.painted => l10n.prefsMaterialPainted,
    ShelfMaterial.metal => l10n.prefsMaterialMetal,
    ShelfMaterial.glass => l10n.prefsMaterialGlass,
  };
}

extension BackgroundSyncIntervalL10n on BackgroundSyncInterval {
  String labelOf(L10n l10n) => switch (this) {
    BackgroundSyncInterval.off => l10n.prefsOff,
    BackgroundSyncInterval.everySixHours => l10n.prefsEvery6Hours,
    BackgroundSyncInterval.daily => l10n.prefsDaily,
  };
}

extension BackupFrequencyL10n on BackupFrequency {
  String labelOf(L10n l10n) => switch (this) {
    BackupFrequency.off => l10n.prefsOff,
    BackupFrequency.daily => l10n.prefsDaily,
    BackupFrequency.weekly => l10n.prefsWeekly,
  };
}

extension DefectKindL10n on DefectKind {
  String labelOf(L10n l10n) => switch (this) {
    DefectKind.missingFile => l10n.defectMissingFile,
    DefectKind.missingCover => l10n.defectMissingCover,
    DefectKind.orphanBlob => l10n.defectOrphanBlob,
    DefectKind.danglingPlacement => l10n.defectDanglingPlacement,
    DefectKind.duplicateFileRow => l10n.defectDuplicateFileRow,
    DefectKind.staleTombstone => l10n.defectStaleTombstone,
    DefectKind.duplicateBook => l10n.defectDuplicateBook,
    DefectKind.noCover => l10n.defectNoCover,
    DefectKind.incompleteMetadata => l10n.defectIncompleteMetadata,
  };

  String repairLabelOf(L10n l10n) => switch (this) {
    DefectKind.missingFile => l10n.defectMissingFileRepair,
    DefectKind.missingCover => l10n.defectMissingCoverRepair,
    DefectKind.orphanBlob => l10n.defectOrphanBlobRepair,
    DefectKind.danglingPlacement => l10n.defectDanglingPlacementRepair,
    DefectKind.duplicateFileRow => l10n.defectDuplicateFileRowRepair,
    DefectKind.staleTombstone => l10n.defectStaleTombstoneRepair,
    DefectKind.duplicateBook => l10n.defectDuplicateBookRepair,
    DefectKind.noCover => l10n.defectNoCoverRepair,
    DefectKind.incompleteMetadata => l10n.defectIncompleteMetadataRepair,
  };
}

extension BackupCheckL10n on BackupCheck {
  /// [BackupCheck.describe] in the reader's language. [BackupCheck.problem]
  /// comes from the archive reader and is shown as written.
  String describeOf(L10n l10n) {
    if (!readable) {
      return localizedProblem?.call(l10n) ??
          problem ??
          l10n.prefsBackupNotABackup;
    }
    if (!hasDatabase) return l10n.prefsBackupNoDatabase;
    if (corrupt.isNotEmpty || missing.isNotEmpty) {
      final parts = [
        if (corrupt.isNotEmpty) l10n.prefsBackupDamagedCount(corrupt.length),
        if (missing.isNotEmpty) l10n.prefsBackupMissingCount(missing.length),
      ];
      return l10n.prefsBackupNotIntact(parts.join(', '));
    }
    if (!hashesRecorded) return l10n.prefsBackupNoChecksums;
    final books = counts['books'];
    return books == null
        ? l10n.prefsBackupIntact(checked)
        : l10n.prefsBackupIntactBooks(checked, books);
  }
}

extension SyncPhaseL10n on SyncPhase {
  String labelOf(L10n l10n) => switch (this) {
    SyncPhase.downloadingCovers => l10n.syncPhaseCovers,
    SyncPhase.downloadingFiles => l10n.syncPhaseFiles,
    SyncPhase.pushingBooks => l10n.syncPhasePushing,
  };
}

/// The sentence for a sync problem. The service records which problem it was
/// ([SyncIssue.note]) and the detail; this is where it becomes English (or,
/// later, another language).
extension SyncIssueL10n on SyncIssue {
  String messageOf(L10n l10n) => switch (note) {
    null => message,
    SyncNote.overwritten => l10n.syncNoteOverwritten(title),
    SyncNote.unsafeBookId => l10n.syncNoteUnsafeBookId,
    SyncNote.unsafeFileId => l10n.syncNoteUnsafeFileId,
    SyncNote.copyMissing => l10n.syncNoteCopyMissing(message),
    SyncNote.loanCopyMissing => l10n.syncNoteLoanCopyMissing(message),
    SyncNote.copyPhotoDownload => l10n.syncNoteCopyPhotoDownload(message),
    SyncNote.copyPhotosPull => l10n.syncNoteCopyPhotosPull(message),
    SyncNote.copyPhotoDelete => l10n.syncNoteCopyPhotoDelete(message),
    SyncNote.copyPhotoPush => l10n.syncNoteCopyPhotoPush(message),
    SyncNote.profilePush => l10n.syncNoteProfilePush(message),
    SyncNote.annotationsPull => l10n.syncNoteAnnotationsPull(message),
    SyncNote.readingSessionsPull => l10n.syncNoteReadingSessionsPull(message),
    SyncNote.readingStatusesPull => l10n.syncNoteReadingStatusesPull(message),
    SyncNote.readerNotesPull => l10n.syncNoteReaderNotesPull(message),
    SyncNote.annotationDelete => l10n.syncNoteAnnotationDelete(message),
    SyncNote.annotationPush => l10n.syncNoteAnnotationPush(message),
    SyncNote.readingSessionPush => l10n.syncNoteReadingSessionPush(message),
    SyncNote.readerNotePush => l10n.syncNoteReaderNotePush(message),
    SyncNote.readingStatusPush => l10n.syncNoteReadingStatusPush(message),
  };
}

extension DuplicateReasonL10n on DuplicateReason {
  String labelOf(L10n l10n) => switch (this) {
    DuplicateReason.sameFile => l10n.duplicatesReasonSameFile,
    DuplicateReason.sameIsbn => l10n.duplicatesReasonSameIsbn,
    DuplicateReason.similarTitle => l10n.duplicatesReasonSimilarTitle,
  };
}

extension MergeConflictL10n on MergeConflict {
  /// [label] in the reader's language, chosen by the column the conflict is
  /// about; an unknown column shows its English label.
  String labelOf(L10n l10n) => switch (field) {
    'title' => l10n.duplicatesFieldTitle,
    'subtitle' => l10n.duplicatesFieldSubtitle,
    'description' => l10n.duplicatesFieldDescription,
    'isbn' => l10n.duplicatesFieldIsbn,
    'publisher' => l10n.duplicatesFieldPublisher,
    'publishedYear' => l10n.duplicatesFieldYear,
    'pageCount' => l10n.duplicatesFieldPages,
    'coverPath' => l10n.duplicatesFieldCover,
    _ => label,
  };
}

extension FreeCatalogueL10n on FreeCatalogue {
  /// [description] in the reader's language; a catalogue added later without
  /// a translated blurb shows its English one.
  String descriptionOf(L10n l10n) => switch (name) {
    'Project Gutenberg' => l10n.opdsFreeGutenberg,
    'Wikisource' => l10n.opdsFreeWikisource,
    _ => description,
  };
}

extension BookcaseStyleL10n on BookcaseStyle {
  String labelOf(L10n l10n) => switch (this) {
    BookcaseStyle.billy => l10n.roomStyleBilly,
    BookcaseStyle.tall => l10n.roomStyleTall,
    BookcaseStyle.low => l10n.roomStyleLow,
    BookcaseStyle.cube => l10n.roomStyleCube,
    BookcaseStyle.floating => l10n.roomStyleFloating,
  };
}

extension PropKindL10n on PropKind {
  String labelOf(L10n l10n) => switch (this) {
    PropKind.statuette => l10n.roomPropStatuette,
    PropKind.plant => l10n.roomPropPlant,
    PropKind.vase => l10n.roomPropVase,
    PropKind.clock => l10n.roomPropClock,
    PropKind.boxes => l10n.roomPropBoxes,
    PropKind.bookend => l10n.roomPropBookend,
  };
}

extension ShelfKindL10n on ShelfKind {
  String labelOf(L10n l10n) => switch (this) {
    ShelfKind.shelf => l10n.roomKindShelf,
    ShelfKind.panel => l10n.roomKindPanel,
    ShelfKind.divider => l10n.roomKindDivider,
    ShelfKind.marker => l10n.roomKindMarker,
  };
}

extension TidySortL10n on TidySort {
  String labelOf(L10n l10n) => switch (this) {
    TidySort.author => l10n.roomTidyByAuthor,
    TidySort.title => l10n.roomTidyByTitle,
    TidySort.series => l10n.roomTidyBySeries,
  };
}

extension BookFormatL10n on BookFormat {
  /// The preset's name in the reader's language. Paper sizes (A5, A4) are
  /// identifiers and keep their own label.
  String labelOf(L10n l10n) => switch (key) {
    'mass' => l10n.roomFormatMass,
    'trade' => l10n.roomFormatTrade,
    'b5soft' => l10n.roomFormatB5,
    'hardcover' => l10n.roomFormatHardcover,
    _ => label,
  };
}

extension SyncScopeL10n on SyncScope {
  /// [SyncScope.excluded] in the reader's language.
  List<String> excludedOf(L10n l10n) => [
    if (!books) l10n.syncScopeLabelBooks,
    if (!copies) l10n.syncScopeLabelCopies,
    if (!loans) l10n.syncScopeLabelLoans,
    if (!annotations) l10n.syncScopeLabelAnnotations,
    if (!sessions) l10n.syncScopeLabelSessions,
    if (!copyPhotos) l10n.syncScopeLabelPhotos,
  ];
}

extension PageMetricL10n on PageMetric {
  String labelOf(L10n l10n) => switch (this) {
    PageMetric.pagesOf => l10n.readerMetricPagesOf,
    PageMetric.percent => l10n.readerMetricPercent,
    PageMetric.pagesRead => l10n.readerMetricPagesRead,
    PageMetric.pagesLeft => l10n.readerMetricPagesLeft,
    PageMetric.timeLeft => l10n.readerMetricTimeLeft,
  };
}

extension ReaderThemeL10n on ReaderTheme {
  String labelOf(L10n l10n) => switch (this) {
    ReaderTheme.light => l10n.readerThemeLight,
    ReaderTheme.sepia => l10n.readerThemeSepia,
    ReaderTheme.grey => l10n.readerThemeGrey,
    ReaderTheme.dark => l10n.readerThemeDark,
  };
}

extension ReaderFontL10n on ReaderFont {
  String labelOf(L10n l10n) => switch (this) {
    ReaderFont.serif => l10n.readerFontSerif,
    ReaderFont.sans => l10n.readerFontSans,
    ReaderFont.mono => l10n.readerFontMono,
  };
}

extension PdfFitL10n on PdfFit {
  String labelOf(L10n l10n) => switch (this) {
    PdfFit.width => l10n.readerFitWidth,
    PdfFit.page => l10n.readerFitPage,
  };
}

extension PdfPageModeL10n on PdfPageMode {
  String labelOf(L10n l10n) => switch (this) {
    PdfPageMode.paged => l10n.readerModePaged,
    PdfPageMode.scroll => l10n.readerModeScroll,
  };

  String descriptionOf(L10n l10n) => switch (this) {
    PdfPageMode.paged => l10n.readerModePagedDescription,
    PdfPageMode.scroll => l10n.readerModeScrollDescription,
  };
}

extension HighlightColorL10n on HighlightColor {
  String labelOf(L10n l10n) => switch (this) {
    HighlightColor.yellow => l10n.readerColourYellow,
    HighlightColor.green => l10n.readerColourGreen,
    HighlightColor.blue => l10n.readerColourBlue,
    HighlightColor.pink => l10n.readerColourPink,
  };
}

extension InkToolL10n on InkTool {
  String labelOf(L10n l10n) => switch (this) {
    InkTool.select => l10n.inkToolSelect,
    InkTool.pen => l10n.inkToolPen,
    InkTool.eraser => l10n.inkToolEraser,
    InkTool.text => l10n.inkToolText,
  };
}

extension AnnotationKindL10n on AnnotationKind {
  String labelOf(L10n l10n) => switch (this) {
    AnnotationKind.bookmark => l10n.annotationKindBookmark,
    AnnotationKind.highlight => l10n.annotationKindHighlight,
    AnnotationKind.note => l10n.annotationKindNote,
    AnnotationKind.ink => l10n.annotationKindInk,
  };
}

extension WordSenseL10n on WordSense {
  /// [partOfSpeech] in the reader's language. WordNet names them in English.
  String partOfSpeechOf(L10n l10n) => switch (partOfSpeech) {
    'noun' => l10n.dictionaryPosNoun,
    'verb' => l10n.dictionaryPosVerb,
    'adjective' => l10n.dictionaryPosAdjective,
    'adverb' => l10n.dictionaryPosAdverb,
    _ => partOfSpeech,
  };
}

extension TranslationLanguageL10n on TranslationLanguage {
  /// The language's name in the reader's language; [TranslationLanguage.name]
  /// stays English for the commands and logs that need a stable one.
  String nameOf(L10n l10n) => switch (code) {
    'auto' => l10n.translateLangAuto,
    'en' => l10n.translateLangEn,
    'ar' => l10n.translateLangAr,
    'zh' => l10n.translateLangZh,
    'cs' => l10n.translateLangCs,
    'nl' => l10n.translateLangNl,
    'fr' => l10n.translateLangFr,
    'de' => l10n.translateLangDe,
    'el' => l10n.translateLangEl,
    'he' => l10n.translateLangHe,
    'hi' => l10n.translateLangHi,
    'hu' => l10n.translateLangHu,
    'it' => l10n.translateLangIt,
    'ja' => l10n.translateLangJa,
    'ko' => l10n.translateLangKo,
    'fa' => l10n.translateLangFa,
    'pl' => l10n.translateLangPl,
    'pt' => l10n.translateLangPt,
    'ro' => l10n.translateLangRo,
    'ru' => l10n.translateLangRu,
    'es' => l10n.translateLangEs,
    'sv' => l10n.translateLangSv,
    'tr' => l10n.translateLangTr,
    'uk' => l10n.translateLangUk,
    _ => name,
  };
}

extension TranslationBackendL10n on TranslationBackend {
  /// [TranslationBackend.name] in the reader's language, for the backends that
  /// have a phrase rather than a brand name.
  String displayNameOf(L10n l10n) => this is LocalizedBackendName
      ? (this as LocalizedBackendName).displayName(l10n)
      : name;
}
