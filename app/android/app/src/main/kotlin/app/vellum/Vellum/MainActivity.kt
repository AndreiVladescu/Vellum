package app.vellum.Vellum

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Uri
import android.provider.OpenableColumns
import android.view.KeyEvent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Receives books opened or shared from another app (plan 5 #20) and hands Dart
 * plain file paths.
 *
 * Written as a small MethodChannel rather than taking a share-intent
 * dependency: the whole job is "resolve a content URI to a real file", and doing
 * it here keeps the copy on the Android side, where the URI permission actually
 * lives.
 *
 * The copy is the point. A `content://` URI is only readable while the granting
 * intent is alive, so handing it to Dart to open later is a race the user
 * eventually loses. Everything is copied into `cacheDir/incoming` first, and
 * Dart imports from there.
 *
 * Extends audio_service's activity, not plain `FlutterActivity` (v1.5.1): the
 * player's media session lives in a service that must share this activity's
 * Flutter engine, and that class is what makes the two use the same one. It
 * still *is* a FlutterActivity, so the channels below are unchanged.
 */
class MainActivity : AudioServiceActivity() {
    private val channelName = "app.vellum.Vellum/incoming_share"
    private var channel: MethodChannel? = null

    /** Files from the intent that launched a cold start, awaiting Dart's first ask. */
    private var pending: List<String> = emptyList()

    /**
     * Which launcher shortcut opened us, if any (plan 5 #40).
     *
     * Carried on the same channel as the shared files rather than a second one:
     * both answer "what did the user tap to get here?", and one channel is one
     * lifecycle to reason about. Consumed once — a hot restart must not
     * re-trigger the shortcut.
     */
    private var pendingShortcut: String? = null

    /** Starts/stops [SyncForegroundService] around a manual sync. */
    private val syncServiceChannelName = "app.vellum.Vellum/sync_service"

    /**
     * Whether the active network is metered, for "Download audiobooks on
     * Wi-Fi only" (docs/AUDIOBOOKS.md §6). Metered rather than "is Wi-Fi":
     * a phone's hotspot is Wi-Fi and still someone's data plan, and Android
     * already knows which networks the user marked as metered.
     */
    private val networkChannelName = "app.vellum.Vellum/network"

    /**
     * The volume keys as page turns, for the readers' opt-in setting. Off by
     * default and only on while a reader that asked for it is open, so the keys
     * change the volume everywhere else. Dart enables and disables it; while it
     * is on, the key presses go to Dart and the system never sees them.
     */
    private val volumeKeysChannelName = "app.vellum.Vellum/volume_keys"
    private var volumeKeysChannel: MethodChannel? = null
    private var volumeKeysOn = false

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (volumeKeysOn &&
            (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            // One turn per press: holding the key repeats, which would race
            // through the chapter. Both halves of the press are swallowed so
            // the volume bar never appears.
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                volumeKeysChannel?.invokeMethod(
                    "key",
                    if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down",
                )
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // A new engine starts with the keys back to the system's.
        volumeKeysOn = false
        volumeKeysChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, volumeKeysChannelName).also {
                it.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "enable" -> {
                            volumeKeysOn = true
                            result.success(null)
                        }
                        "disable" -> {
                            volumeKeysOn = false
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }
        val messenger = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel = messenger
        messenger.setMethodCallHandler { call, result ->
            when (call.method) {
                // Cold start: Dart asks once after boot for whatever launched us.
                "takeInitialFiles" -> {
                    val files = pending
                    pending = emptyList()
                    result.success(files)
                }
                // The launcher shortcut that opened this run, or null.
                "takeShortcut" -> {
                    val shortcut = pendingShortcut
                    pendingShortcut = null
                    result.success(shortcut)
                }
                else -> result.notImplemented()
            }
        }
        pending = copyFrom(intent)
        pendingShortcut = intent?.getStringExtra("vellum_shortcut")

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, syncServiceChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        startForegroundService(Intent(this, SyncForegroundService::class.java))
                        result.success(null)
                    }
                    "stop" -> {
                        stopService(Intent(this, SyncForegroundService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, networkChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isMetered" -> {
                        val manager =
                            getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                        // No manager: say metered, so the app asks rather than
                        // spends someone's data.
                        result.success(manager?.isActiveNetworkMetered ?: true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Warm resume: the app is already running (launchMode is singleTop), so
        // Dart is listening and can be told directly.
        // A shortcut tapped while the app is already running.
        intent.getStringExtra("vellum_shortcut")?.let { shortcut ->
            val sink = channel
            if (sink == null) pendingShortcut = shortcut
            else sink.invokeMethod("onShortcut", shortcut)
        }

        val files = copyFrom(intent)
        if (files.isEmpty()) return
        val sink = channel
        if (sink == null) {
            pending = files
        } else {
            sink.invokeMethod("onFiles", files)
        }
    }

    /** Extracts every shared/opened URI from [intent] and copies each to cache. */
    private fun copyFrom(intent: Intent?): List<String> {
        if (intent == null) return emptyList()
        val uris: List<Uri> = when (intent.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND ->
                listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
            Intent.ACTION_SEND_MULTIPLE ->
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                    ?.filterNotNull() ?: emptyList()
            else -> emptyList()
        }
        return uris.mapNotNull(::copyToCache)
    }

    /**
     * Copies one URI into `cacheDir/incoming`, keeping its display name so the
     * import's file-name metadata parsing still has something to work with.
     * Returns null on any failure — one unreadable attachment must not stop the
     * others.
     */
    private fun copyToCache(uri: Uri): String? = try {
        val name = displayName(uri) ?: "shared-book"
        val dir = File(cacheDir, "incoming").apply { mkdirs() }
        // A unique subdirectory per file, so two shares of the same name can't
        // overwrite each other mid-import.
        val slot = File(dir, System.nanoTime().toString()).apply { mkdirs() }
        val target = File(slot, name)
        contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        } ?: return null
        target.absolutePath
    } catch (e: Exception) {
        null
    }

    private fun displayName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
            val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (column >= 0 && cursor.moveToFirst()) return cursor.getString(column)
        }
        return uri.lastPathSegment
    }
}
