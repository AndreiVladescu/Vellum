package app.vellum.Vellum

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
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
 */
class MainActivity : FlutterActivity() {
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
