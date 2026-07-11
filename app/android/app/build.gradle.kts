plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.avladescu.vellum"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.avladescu.vellum"
        // Pinned rather than inherited for reproducibility. 24 is Flutter's
        // current floor and clears the plugin minimums (flutter_secure_storage's
        // EncryptedSharedPreferences needs 23, pdfrx needs 21).
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release`
            // works. Replace with a real keystore before distributing (see
            // key.properties in the Flutter docs).
            signingConfig = signingConfigs.getByName("debug")
            // Shrink + obfuscate with R8 and strip unused resources, so the
            // release build is smaller. proguard-rules.pro keeps what the
            // plugins need past the shrinker.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
