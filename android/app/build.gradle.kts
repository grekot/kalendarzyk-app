import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Wczytaj key.properties (lokalnie) lub środowisko (CI: GitHub Actions).
val keystoreProperties = Properties()
val keystoreFile = rootProject.file("key.properties")
if (keystoreFile.exists()) {
    keystoreProperties.load(FileInputStream(keystoreFile))
}

// Helper: bierze property z key.properties albo z env (CI).
fun keystoreProp(key: String, env: String): String? =
    keystoreProperties.getProperty(key) ?: System.getenv(env)

android {
    namespace = "pl.grkotarba.kalendazyk"
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
        applicationId = "pl.grkotarba.kalendazyk"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val storePath = keystoreProp("storeFile", "RELEASE_KEYSTORE_PATH")
            if (storePath != null) {
                storeFile = file(storePath)
                storePassword = keystoreProp("storePassword", "RELEASE_KEYSTORE_PASSWORD")
                keyAlias = keystoreProp("keyAlias", "RELEASE_KEY_ALIAS")
                keyPassword = keystoreProp("keyPassword", "RELEASE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Jeśli release keystore jest skonfigurowany (lokalnie key.properties
            // lub w CI env vars) — używamy go. W innym przypadku fallback do debug
            // keystore (działa do `flutter run --release` na laptopie deweloperskim
            // bez setupu).
            val releaseStorePath = keystoreProp("storeFile", "RELEASE_KEYSTORE_PATH")
            signingConfig = if (releaseStorePath != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
