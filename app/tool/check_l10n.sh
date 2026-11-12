#!/usr/bin/env bash
# Guards the localization retrofit (plan 5 #38).
#
# The retrofit is finished: every file under lib/ (apart from lib/l10n/) is in
# the list below, so a new hardcoded string anywhere in the app fails CI. The
# list mechanism stays so a new file can be added the moment it is created, and
# so a deliberate exception is one line (`// i18n-ignore`), not a script edit.
#
# The check is a grep, not a parser: it looks for a `Text('…')` (or a
# label/hint/tooltip taking a literal) whose content contains a letter. That
# misses clever cases and flags a few innocent ones — which is why the escape
# hatch is a trailing `// i18n-ignore` comment, and why the list is opt-in
# rather than the default.
set -euo pipefail
cd "$(dirname "$0")/.."

MIGRATED=(
  lib/main.dart
  lib/app_drawer.dart
  lib/app_version.dart
  lib/navigation_history.dart
  lib/shortcuts.dart
  lib/snack_bars.dart
  lib/account/account_page.dart
  lib/account/avatar_image.dart
  lib/account/profile_avatar.dart
  lib/account/user_profile.dart
  lib/add_book/add_book_page.dart
  lib/add_book/barcode_camera.dart
  lib/add_book/isbn.dart
  lib/add_book/scan_page.dart
  lib/book_detail/book_detail_page.dart
  lib/book_detail/copy_photos.dart
  lib/book_detail/cover_thumb.dart
  lib/book_detail/edit_book_sheet.dart
  lib/book_detail/formats_section.dart
  lib/book_detail/genres_section.dart
  lib/book_detail/lend_sheet.dart
  lib/book_detail/physical_copies_section.dart
  lib/book_detail/read_button.dart
  lib/book_detail/reader_notes_section.dart
  lib/book_detail/reading_stats_section.dart
  lib/book_detail/send_to_device_sheet.dart
  lib/data/background_work.dart
  lib/data/backup_crypto.dart
  lib/data/backup_schedule.dart
  lib/data/backup_service.dart
  lib/data/book_file_validation.dart
  lib/data/book_write_service.dart
  lib/data/catalogue_enrich.dart
  lib/data/copy_photo_service.dart
  lib/data/cover_service.dart
  lib/data/cover_thumbnails.dart
  lib/data/database.dart
  lib/data/database.g.dart
  lib/data/external_open.dart
  lib/data/file_hash.dart
  lib/data/file_service.dart
  lib/data/library_doctor.dart
  lib/data/library_queries.dart
  lib/data/library_repository.dart
  lib/data/local_text_index.dart
  lib/data/metadata.dart
  lib/data/pdf_cover.dart
  lib/data/physical_service.dart
  lib/data/reading_position_service.dart
  lib/data/reading_status.dart
  lib/data/search_index.dart
  lib/data/seed_library.dart
  lib/data/series_service.dart
  lib/data/shelf_service.dart
  lib/data/sync_clock.dart
  lib/data/trash_service.dart
  lib/data/wishlist_service.dart
  lib/dedupe/duplicate_finder.dart
  lib/dedupe/duplicates_page.dart
  lib/dedupe/merge_service.dart
  lib/diagnostics/diagnostics_collector.dart
  lib/diagnostics/diagnostics_report.dart
  lib/diagnostics/error_log.dart
  lib/import/calibre_import.dart
  lib/import/catalog_entry.dart
  lib/import/catalog_format_help.dart
  lib/import/csv_import.dart
  lib/import/filename_metadata.dart
  lib/import/folder_import_page.dart
  lib/import/folder_import_service.dart
  lib/import/free_catalogues.dart
  lib/import/import_plan.dart
  lib/import/incoming_share.dart
  lib/import/opds_browser_page.dart
  lib/import/opds_client.dart
  lib/loans/borrow_requests.dart
  lib/loans/due_dates.dart
  lib/loans/loans_page.dart
  lib/notifications/notifications_button.dart
  lib/notifications/notifications_page.dart
  lib/notifications/sync_tray.dart
  lib/notifications/tray.dart
  lib/onboarding/first_run_sheet.dart
  lib/onboarding/sample_library.dart
  lib/physical/book_picker.dart
  lib/physical/bookcase_template.dart
  lib/physical/bulk_place.dart
  lib/physical/environment_editor_page.dart
  lib/physical/find_copy.dart
  lib/physical/labels.dart
  lib/physical/layout_doc.dart
  lib/physical/layout_repository.dart
  lib/physical/locate.dart
  lib/physical/physical_libraries_page.dart
  lib/physical/physical_metrics.dart
  lib/physical/placement_toolbar.dart
  lib/physical/publish_room.dart
  lib/physical/room_backdrop.dart
  lib/physical/room_gestures.dart
  lib/physical/room_measure.dart
  lib/physical/room_painter.dart
  lib/physical/room_prop.dart
  lib/physical/room_semantics.dart
  lib/physical/settle.dart
  lib/physical/shared_room_page.dart
  lib/physical/shelf_dialogs.dart
  lib/physical/shelf_scan_page.dart
  lib/physical/shelf_snap.dart
  lib/physical/stocktake.dart
  lib/physical/stocktake_page.dart
  lib/reader/ai/ai_client.dart
  lib/reader/ai/ai_settings.dart
  lib/reader/ai/ai_setup_sheet.dart
  lib/reader/ai/ask_ai_sheet.dart
  lib/reader/annotations/annotation_locator.dart
  lib/reader/annotations/annotation_store.dart
  lib/reader/annotations/annotations_panel.dart
  lib/reader/annotations/epub_highlight_html.dart
  lib/reader/annotations/highlight_palette.dart
  lib/reader/annotations/ink_markup.dart
  lib/reader/annotations/ink_painter.dart
  lib/reader/annotations/markdown_export.dart
  lib/reader/annotations/pdf_highlight_painter.dart
  lib/reader/auto_scroll.dart
  lib/reader/auto_scroll_bar.dart
  lib/reader/chapter_markup.dart
  lib/reader/dictionary/dictionary_sheet.dart
  lib/reader/dictionary/dictionary_store.dart
  lib/reader/dictionary/dictionary_tile.dart
  lib/reader/dictionary/wordnet.dart
  lib/reader/edge_turn.dart
  lib/reader/epub_book.dart
  lib/reader/epub_reader_page.dart
  lib/reader/epub_search.dart
  lib/reader/ink_tools.dart
  lib/reader/night_mode.dart
  lib/reader/page_metric.dart
  lib/reader/pdf_paged_view.dart
  lib/reader/reader_actions.dart
  lib/reader/reader_gestures.dart
  lib/reader/reader_hotkeys.dart
  lib/reader/reader_page.dart
  lib/reader/reader_search_field.dart
  lib/reader/reader_settings.dart
  lib/reader/reader_settings_sheet.dart
  lib/reader/translate/local_engine_backend.dart
  lib/reader/translate/on_device.dart
  lib/reader/translate/on_device_stub.dart
  lib/reader/translate/proprietary/language_packs_sheet.dart
  lib/reader/translate/proprietary/on_device.dart
  lib/reader/translate/proprietary/on_device_backend.dart
  lib/reader/translate/translate_sheet.dart
  lib/reader/translate/translation_backend.dart
  lib/reader/translate/translator_setup_sheet.dart
  lib/server/auto_pusher.dart
  lib/server/background_sync.dart
  lib/server/cert_trust.dart
  lib/server/connection_store.dart
  lib/server/continue_widget.dart
  lib/server/live_sync.dart
  lib/server/server_client.dart
  lib/server/server_page.dart
  lib/server/sharing_page.dart
  lib/server/sync_foreground_service.dart
  lib/server/sync_scope.dart
  lib/server/sync_scope_page.dart
  lib/server/sync_service.dart
  lib/server/write_access_request.dart
  lib/settings/app_settings.dart
  lib/settings/appearance.dart
  lib/settings/book_face.dart
  lib/settings/preferences_page.dart
  lib/settings/shared_shelves_page.dart
  lib/settings/shelf_sort.dart
  lib/settings/spine_art.dart
  lib/settings/trash_page.dart
  lib/settings/wallpaper.dart
  lib/shelf/author_page.dart
  lib/shelf/book_list_view.dart
  lib/shelf/book_open_route.dart
  lib/shelf/command_palette.dart
  lib/shelf/content_search.dart
  lib/shelf/cover_color.dart
  lib/shelf/cover_image.dart
  lib/shelf/library_header.dart
  lib/shelf/new_shelf_dialog.dart
  lib/shelf/series_page.dart
  lib/shelf/shelf_filter.dart
  lib/shelf/shelf_target_sheet.dart
  lib/shelf/shelf_view.dart
  lib/shelf/spine_style.dart
  lib/stats/book_reading_stats.dart
  lib/stats/day_detail_sheet.dart
  lib/stats/duration_label.dart
  lib/stats/goals_dialog.dart
  lib/stats/heatmap_grid.dart
  lib/stats/insights_page.dart
  lib/stats/insights_range.dart
  lib/stats/month_review.dart
  lib/stats/month_review_page.dart
  lib/stats/reading_goals.dart
  lib/stats/session_recorder.dart
  lib/stats/stats_queries.dart
  lib/widgets/page_insets.dart
  lib/wishlist/wishlist_page.dart
)

fail=0
for file in "${MIGRATED[@]}"; do
  [ -f "$file" ] || { echo "check_l10n: $file is listed but missing"; fail=1; continue; }

  # A user-facing literal: Text('…'), or one of the common string parameters,
  # where the literal contains at least one letter (so ':' , '·' and '' pass).
  hits=$(grep -nE \
    "(Text\(|label: |labelText: |hintText: |tooltip: |title: |subtitle: )'[^']*[A-Za-z][^']*'" \
    "$file" | grep -v 'i18n-ignore' || true)

  # Hand-built plurals, anywhere in the file — not just on a `Text(` line.
  # This is the pattern plan 5 #38 exists to remove (`'$n issue${n == 1 ? '' :
  # 's'}'`), and it slipped through the check above because the literal sat on
  # its own continuation line rather than next to the `Text(`. A same-line grep
  # is a weak guard for a codebase that writes most user-facing copy across
  # several lines; this catches the specific shape that matters.
  # The shape, precisely: a ternary choosing between two *very short* quoted
  # strings — `? '' : 's'`. That is the suffix hack and essentially nothing
  # else, so it doesn't fire on `if (paths.length == 1)`, which is control flow.
  # `//` lines are skipped: the comments explaining this rule contain the very
  # pattern they warn about, and a guard that flags its own documentation is one
  # people switch off.
  plurals=$(grep -nE "\? *'[a-z]{0,2}' *: *'[a-z]{0,2}'" "$file" \
    | grep -vE "i18n-ignore|^[0-9]+: *(//|///|\*)" || true)
  if [ -n "$plurals" ]; then
    echo "check_l10n: hand-built plural in $file"
    echo "  Use an ICU plural in lib/l10n/app_en.arb — no other language"
    echo "  survives 'thing' + 's'."
    echo "$plurals" | sed 's/^/    /'
    fail=1
  fi

  if [ -n "$hits" ]; then
    echo "check_l10n: hardcoded user-facing strings in $file"
    echo "  Move them to lib/l10n/app_en.arb and use L10n.of(context)."
    echo "  If the string is genuinely not user-facing, append // i18n-ignore."
    echo "$hits" | sed 's/^/    /'
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  exit 1
fi
echo "check_l10n: ${#MIGRATED[@]} migrated file(s) clean"
