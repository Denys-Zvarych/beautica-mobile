import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.beautica.beautica_mobile"
    // Phase 0 — locked SDK levels per ARCHITECTURE-mobile.md § 2.
    // compileSdk 36 is required by Flutter 3.41 toolchain; targetSdk 35
    // matches current Play Store policy; minSdk 26 covers ~96% of devices.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.beautica.beautica_mobile"
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // MEDIUM-1 (mobile-security 2026-05-24): production keystore sourced from
    // environment variables so credentials are never committed to VCS.
    // Required env vars (set in CI secrets and local ~/.gradle/gradle.properties):
    //   BEAUTICA_KEYSTORE_PATH       — absolute path to beautica-release.jks
    //   BEAUTICA_KEYSTORE_PASSWORD   — store password
    //   BEAUTICA_KEY_ALIAS           — key alias inside the keystore
    //   BEAUTICA_KEY_PASSWORD        — key password
    //
    // Fall-through: when the env vars are absent (local dev without keystore),
    // the signingConfig block is skipped and Android Gradle uses the default
    // debug keystore automatically — `flutter run --release` still works for
    // local smoke testing without credentials.
    val keystorePath = System.getenv("BEAUTICA_KEYSTORE_PATH")
    val keystorePassword = System.getenv("BEAUTICA_KEYSTORE_PASSWORD")
    // Use distinct names (storeKey*) to avoid shadowing the Kotlin DSL
    // properties `keyAlias` / `keyPassword` inside signingConfigs.create {}.
    val storeKeyAlias = System.getenv("BEAUTICA_KEY_ALIAS")
    val storeKeyPassword = System.getenv("BEAUTICA_KEY_PASSWORD")

    if (keystorePath != null && keystorePassword != null &&
        storeKeyAlias != null && storeKeyPassword != null) {
        signingConfigs {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = keystorePassword
                keyAlias = storeKeyAlias
                keyPassword = storeKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Use the env-var-driven release config when credentials are present;
            // fall back to debug signing for local development (MEDIUM-1 fix).
            val releaseConfig = signingConfigs.findByName("release")
            signingConfig = releaseConfig ?: signingConfigs.getByName("debug")
            // R8 shrinking and obfuscation enabled for release builds.
            // ProGuard rules in proguard-rules.pro protect flutter_secure_storage
            // and firebase_messaging reflection paths (Phase 2.1).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}
