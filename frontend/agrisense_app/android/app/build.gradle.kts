import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ---------------------------------------------------------------------------
// Release signing.
//
// To sign release builds with a real keystore, create `android/key.properties`
// (already gitignored — never commit it) with:
//
//   storePassword=********
//   keyPassword=********
//   keyAlias=upload
//   storeFile=C:/Users/<you>/<path>/upload-keystore.jks   <- forward slashes,
//                                                            even on Windows
//
// Full walkthrough: docs/RELEASE_SIGNING.md.
//
// If `android/key.properties` does not exist, release builds fall back to the
// DEBUG keystore so `flutter build apk --release` always works out of the box.
// A debug-signed APK is fine for testing/installing manually, but it cannot be
// uploaded to the Play Store, and it must be uninstalled before a properly
// signed APK can be installed (signatures differ).
// ---------------------------------------------------------------------------
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

fun keystoreProperty(name: String): String =
    keystoreProperties.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: error(
            "android/key.properties exists but is missing the \"$name\" entry. " +
                "See docs/RELEASE_SIGNING.md for the expected format."
        )

android {
    namespace = "com.example.agrisense_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.agrisense_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                val storeFileRaw = keystoreProperty("storeFile")
                // Resolve relative to the app module first, then to android/.
                // Absolute paths (with FORWARD slashes on Windows) work too.
                val storeFileRef =
                    listOf(file(storeFileRaw), rootProject.file(storeFileRaw))
                        .distinct()
                        .firstOrNull { it.isFile }
                        ?: error(
                            "Keystore not found at \"$storeFileRaw\" " +
                                "(looked relative to android/app and android/). " +
                                "Use forward slashes in key.properties, e.g. " +
                                "storeFile=C:/Users/<you>/upload-keystore.jks"
                        )

                keyAlias = keystoreProperty("keyAlias")
                keyPassword = keystoreProperty("keyPassword")
                storeFile = storeFileRef
                storePassword = keystoreProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
                logger.lifecycle(
                    "Release build will be signed with the keystore from android/key.properties"
                )
            } else {
                // No android/key.properties found — sign with the debug key so
                // `flutter build apk --release` works without extra setup.
                signingConfig = signingConfigs.getByName("debug")
                logger.lifecycle(
                    "No android/key.properties found — release build will be signed " +
                        "with the DEBUG key (fine for testing, not for the Play Store). " +
                        "See docs/RELEASE_SIGNING.md to set up release signing."
                )
            }
        }
    }

    androidResources {
        // Store the bundled SQLite knowledge base uncompressed inside the APK.
        //
        // A compressed asset must be fully inflated into RAM before it can be
        // read; an uncompressed, zipalign-ed one is page-aligned and can be
        // streamed straight out of the APK. SQLite files are already compact
        // after VACUUM, so the size cost is small and the first-launch copy in
        // OfflineDatabase gets measurably faster and cheaper in memory.
        noCompress += "db"
    }
}

flutter {
    source = "../.."
}
