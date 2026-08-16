package app.vellum.Vellum

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * Anchors a manual sync to a real Android foreground service, so the process
 * keeps its network access if the app is backgrounded mid-sync.
 *
 * Backgrounding an app on Android suspends its network fairly promptly — a
 * sync in flight when that happens dies with a DNS lookup failure, since the
 * socket it was using is torn down. A foreground service is the OS's own
 * mechanism for "this process is doing something the user asked for and
 * cares about" and is exempt from that. This service does none of the sync
 * work itself; `SyncService` (Dart) still runs in the normal Flutter engine.
 * All this does is exist, with a visible notification, for exactly as long
 * as [MainActivity] tells it to — never longer.
 *
 * The notification it posts on start is a placeholder. [FlutterLocalNotificationsPlugin]
 * (Dart side, same channel and notification id — see `sync_tray.dart`) is
 * what the user actually sees updating with progress; posting to the same id
 * here first is only so `startForeground()` has something valid to show
 * before Dart's first progress update arrives, which Android requires
 * promptly after the service starts.
 */
class SyncForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "vellum.sync"
        const val NOTIFICATION_ID = 2
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        // Not sticky: this service exists only for a sync Dart is already
        // running. If the process is killed and restarted by the system,
        // there is no sync left to protect, so it must not come back on its
        // own.
        return START_NOT_STICKY
    }

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            // Idempotent — safe to call every time the service starts, and
            // means this doesn't depend on Dart having created the channel
            // first.
            manager?.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Syncing",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Progress while your library syncs with the server"
                },
            )
        }

        val openApp = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = openApp?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val builder = Notification.Builder(this).apply {
            setContentTitle("Vellum")
            setContentText("Syncing your library…")
            setSmallIcon(applicationInfo.icon)
            setOngoing(true)
            if (contentIntent != null) setContentIntent(contentIntent)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder.setChannelId(CHANNEL_ID)
        }
        return builder.build()
    }
}
