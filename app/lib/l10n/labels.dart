// Localised words for enums whose English text lives on the enum itself.
//
// The enums (`ReadingStatus.label`, `ShelfSort.label`, ...) are plain Dart with
// no BuildContext, and are used by code that has none, so the lookup sits next
// to them here instead: the widget that shows the value asks
// `status.labelOf(L10n.of(context))`. The enum's own English field stays for
// the screens not yet moved over.
import '../data/reading_status.dart';
import '../settings/shelf_sort.dart';
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
