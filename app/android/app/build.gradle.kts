import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is read from a gitignored `android/key.properties` (see
// key.properties.example). When it's absent — a fresh checkout, or CI without
// the secret — we fall back to the debug key so `flutter run --release` still
// works; such a build just isn't distributable/updatable.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "app.vellum.Vellum"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications, which uses java.time to
        // schedule. minSdk is 24 and those APIs landed in 26, so without this
        // the build fails outright — see the dependency below, which supplies
        // the back-ported implementations.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "app.vellum.Vellum"
        // Pinned rather than inherited for reproducibility. 24 is Flutter's
        // current floor and clears the plugin minimums (flutter_secure_storage's
        // EncryptedSharedPreferences needs 23, pdfrx needs 21).
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Defined only when key.properties is present; otherwise the release
        // build falls back to the debug signing config below.
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // A real release keystore when key.properties exists, else the debug
            // key so `flutter run --release` still works on a fresh checkout (a
            // debug-signed build is not distributable — see key.properties.example).
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Shrink + obfuscate with R8 and strip unused resources, so the
            // release build is smaller. proguard-rules.pro keeps what the
            // plugins need past the shrinker.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Ship only a symbol table for the native libs (pdfium, sqlite3):
            // enough for Play's native crash symbolication, without the full
            // debug info that bloats the artifact.
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Pairs with `isCoreLibraryDesugaringEnabled` above.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
