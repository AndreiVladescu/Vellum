package app.vellum.Vellum

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * The continue-reading home-screen widget (plan 5 #40).
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
 */
class ContinueReadingWidget : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.continue_reading_widget).apply {
                val title = widgetData.getString("continue_title", null)
                val subtitle = widgetData.getString("continue_subtitle", null)
                val coverPath = widgetData.getString("continue_cover", null)

                if (title == null) {
                    // Empty state rather than a blank rectangle: a widget with
                    // nothing in it looks broken, and "nothing to continue" is
                    // a real answer.
                    setTextViewText(R.id.widget_title, context.getString(R.string.widget_empty_title))
                    setTextViewText(R.id.widget_subtitle, context.getString(R.string.widget_empty_subtitle))
                    setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
                } else {
                    setTextViewText(R.id.widget_title, title)
                    setTextViewText(R.id.widget_subtitle, subtitle ?: "")
                    // Decoded defensively: the cover may have been deleted
                    // between the app writing this and the launcher drawing it.
                    val bitmap = coverPath?.let {
                        runCatching { BitmapFactory.decodeFile(it) }.getOrNull()
                    }
                    if (bitmap != null) {
                        setImageViewBitmap(R.id.widget_cover, bitmap)
                    } else {
                        setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
                    }
                }

                // Tapping opens the app on the same "continue reading" path the
                // launcher shortcut uses — one destination, not two.
                // The extra is what MainActivity reads (cold: takeShortcut,
                // warm: onNewIntent). HomeWidgetLaunchIntent only sets a
                // vellum:// data URI, which nothing reads, so the tap just
                // opened the shelf.
                val open = android.content.Intent(context, MainActivity::class.java)
                    .putExtra("vellum_shortcut", "continue")
                    .setFlags(android.content.Intent.FLAG_ACTIVITY_SINGLE_TOP)
                setOnClickPendingIntent(
                    R.id.widget_root,
                    android.app.PendingIntent.getActivity(
                        context,
                        0,
                        open,
                        android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                            android.app.PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
            }
            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
