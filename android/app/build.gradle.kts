import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase: apply the Google Services plugin ONLY when
// google-services.json has been supplied by the developer at
// android/app/google-services.json. Without it, the app still builds
// and runs; Firebase auth reports "not configured" and the app skips
// auth gating. Do NOT commit a real google-services.json here without
// checking what it contains.
if (rootProject.file("app/google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localProperties.load(FileInputStream(localPropertiesFile))
}

android {
    namespace = "com.estudyantego.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.estudyantego.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Floor is 26 (Android 8.0), NOT the Flutter default 24:
        // the Health Connect client (Walking Goal fallback for
        // phones with no step-counter sensor) requires minSdk 26,
        // and the user approved the bump on Nov 5, 2026. Do not
        // lower it back to flutter.minSdkVersion without removing
        // the Health Connect dependency first — the build
        // hard-fails (manifest merger) if the floor is below 26.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Google Maps API key from local.properties (never committed).
        manifestPlaceholders["MAPS_API_KEY"] =
            localProperties.getProperty("MAPS_API_KEY", "")
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Pin the debug keystore to the persistent home-disk copy so the
        // APK signature (and its SHA-1 for Cloud Console restrictions)
        // survives VM replacements. The path comes from local.properties
        // (gitignored); when unset, the AGP default applies.
        getByName("debug") {
            val debugKeystore = localProperties.getProperty("debug.keystore")
            if (debugKeystore != null) {
                storeFile = file(debugKeystore)
                storePassword = "android"
                keyAlias = "androiddebugkey"
                keyPassword = "android"
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // Walking Goal Health Connect fallback (Nov 5, 2026): today's
    // steps from Health Connect on phones with no step-counter
    // sensor. connect-client 1.1.0 is the stable release and
    // requires minSdk 26 — that is why the app floor above is 26.
    // coroutines-android is added explicitly (not relied on as a
    // transitive dependency) because MainActivity calls the
    // client's suspend functions from a CoroutineScope.
    implementation("androidx.health.connect:connect-client:1.1.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
