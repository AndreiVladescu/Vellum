# R8/ProGuard keep rules for the release (minified) build.
#
# Flutter ships engine keep rules automatically; this file only covers this
# app's plugins and the classes R8 can't see are reachable (JNI / reflection).

# Flutter's deferred-components code references Play Core split-install classes
# that we don't bundle — silence the warnings instead of pulling the library in.
-dontwarn com.google.android.play.core.**
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }

# pdfrx / pdfium_android — the PDF renderer loads native code and is called
# across the JNI boundary; keep it and don't warn on its optional deps.
-keep class io.github.espresso3389.** { *; }
-dontwarn io.github.espresso3389.**

# flutter_secure_storage uses AndroidX Security (EncryptedSharedPreferences),
# which pulls Tink; Tink references optional providers via reflection.
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# sqlite3 native bindings used by drift.
-keep class org.sqlite.** { *; }
-dontwarn org.sqlite.**
