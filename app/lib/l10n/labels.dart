// Localised words for enums whose English text lives on the enum itself.
//
// The enums (`ReadingStatus.label`, `ShelfSort.label`, ...) are plain Dart with
// no BuildContext, and are used by code that has none, so the lookup sits next
// to them here instead: the widget that shows the value asks
// `status.labelOf(L10n.of(context))`. The enum's own English field stays for
// the screens not yet moved over.
import '../data/reading_status.dart';
import '../data/backup_schedule.dart';
import '../data/backup_service.dart';
import '../data/library_doctor.dart';
import '../server/background_sync.dart';
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
    if (!readable) return problem ?? l10n.prefsBackupNotABackup;
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
