package app.vellum.Vellum

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Bundle
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * The continue-reading and continue-listening home-screen widget (plan 5 #40).
 *
 * Reads what Dart wrote through `home_widget` and draws it — cover, title,
 * progress. **It never touches the database.** A widget process that opened the
 * app's SQLite file would be a second writer to a store the app assumes it owns
 * alone, and the failure mode (a locked or half-written database) would be much
 * worse than a stale widget.
 *
 * Everything it shows is therefore a snapshot the app pushed the last time it
 * knew something changed. Stale is the intended failure: a widget showing
 * yesterday's book is a widget, not a bug.
 *
 * Two layouts, chosen by the size the launcher gives this instance: tall enough
 * (about 4x2) and with both a book being read and one being listened to, two
 * rows; otherwise one row with whichever came last. The snapshot carries all
 * three so a resize needs nothing from the app.
 */
class ContinueReadingWidget : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { draw(context, appWidgetManager, it, widgetData) }
    }

    /** Resizing needs a different layout, not new data. */
    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        draw(context, appWidgetManager, appWidgetId, HomeWidgetPlugin.getData(context))
    }

    private fun draw(
        context: Context,
        appWidgetManager: AppWidgetManager,
        widgetId: Int,
        data: SharedPreferences,
    ) {
        val read = Row.of(data, "read")?.takeIf { it.book.isNotEmpty() }
        val listen = Row.of(data, "listen")?.takeIf { it.book.isNotEmpty() }
        val options = appWidgetManager.getAppWidgetOptions(widgetId)
        val minHeightDp = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        // A 4x1 is at most about 110dp tall in portrait; a 4x2 starts above it.
        val tall = minHeightDp >= TALL_DP || minHeightDp == 0
        val views = if (tall && read != null && listen != null) {
            twoRows(context, read, listen)
        } else {
            oneRow(context, data)
        }
        appWidgetManager.updateAppWidget(widgetId, views)
    }

    private fun twoRows(context: Context, read: Row, listen: Row): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.continue_reading_widget_two)
        views.setTextViewText(R.id.widget_read_title, read.title)
        views.setTextViewText(
            R.id.widget_read_subtitle,
            context.getString(R.string.widget_row_format, context.getString(R.string.widget_label_reading), read.subtitle),
        )
        views.setTextViewText(R.id.widget_listen_title, listen.title)
        views.setTextViewText(
            R.id.widget_listen_subtitle,
            context.getString(R.string.widget_row_format, context.getString(R.string.widget_label_listening), listen.subtitle),
        )
        setCover(context, views, R.id.widget_read_cover, read.cover)
        setCover(context, views, R.id.widget_listen_cover, listen.cover)
        // Each row opens its own destination: the book, or the player.
        views.setOnClickPendingIntent(R.id.widget_row_read, open(context, 1, "read:" + read.book))
        views.setOnClickPendingIntent(R.id.widget_row_listen, open(context, 2, "listen:" + listen.book))
        return views
    }

    private fun oneRow(context: Context, data: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.continue_reading_widget)
        // The most recent of the two, as the app decided.
        val row = Row.of(data, "continue")
        if (row == null) {
            // Empty state rather than a blank rectangle: a widget with
            // nothing in it looks broken, and "nothing to continue" is
            // a real answer.
            views.setTextViewText(R.id.widget_title, context.getString(R.string.widget_empty_title))
            views.setTextViewText(R.id.widget_subtitle, context.getString(R.string.widget_empty_subtitle))
            views.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
            views.setOnClickPendingIntent(R.id.widget_root, open(context, 0, "continue"))
            return views
        }
        views.setTextViewText(R.id.widget_title, row.title)
        views.setTextViewText(R.id.widget_subtitle, row.subtitle)
        setCover(context, views, R.id.widget_cover, row.cover)
        val listening = data.getString("continue_kind", null) == "listen"
        val target = when {
            row.book.isEmpty() -> "continue"
            listening -> "listen:" + row.book
            else -> "read:" + row.book
        }
        views.setOnClickPendingIntent(R.id.widget_root, open(context, 0, target))
        return views
    }

    private class Row(val title: String, val subtitle: String, val cover: String?, val book: String) {
        companion object {
            fun of(data: SharedPreferences, prefix: String): Row? {
                val title = data.getString("${prefix}_title", null)
                // No book id: a snapshot from before the rows existed, which
                // still draws, and opens the app on "continue".
                val book = data.getString("${prefix}_book", null) ?: ""
                if (title.isNullOrEmpty()) return null
                return Row(
                    title,
                    data.getString("${prefix}_subtitle", null) ?: "",
                    data.getString("${prefix}_cover", null),
                    book,
                )
            }
        }
    }

    /**
     * Decoded defensively and downsampled: the cover may have been deleted
     * between the app writing this and the launcher drawing it, and two
     * full-size bitmaps can push a RemoteViews over the binder's limit.
     */
    private fun setCover(context: Context, views: RemoteViews, id: Int, path: String?) {
        val bitmap = path?.let { runCatching { decode(it) }.getOrNull() }
        if (bitmap != null) {
            views.setImageViewBitmap(id, bitmap)
        } else {
            views.setImageViewResource(id, R.mipmap.ic_launcher)
        }
    }

    private fun decode(path: String): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(path, bounds)
        var sample = 1
        while (bounds.outHeight / (sample * 2) >= MAX_COVER_PX) sample *= 2
        return BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
    }

    /**
     * Opens the app on [shortcut] — what MainActivity reads (cold:
     * takeShortcut, warm: onNewIntent). `continue` is the launcher shortcut's
     * path; `read:<id>` and `listen:<id>` name the book. HomeWidgetLaunchIntent
     * only sets a vellum:// data URI, which nothing reads, so a tap would just
     * open the shelf. Distinct request codes keep the intents apart.
     */
    private fun open(context: Context, code: Int, shortcut: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .putExtra("vellum_shortcut", shortcut)
            .setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context,
            code,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private companion object {
        const val TALL_DP = 110
        const val MAX_COVER_PX = 400
    }
}
