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
        // Phase 17.5 — patrol's androidx.test orchestrator + JUnit runner pull
        // in Java 8+ APIs that must be desugared for minSdk 26. Required by
        // patrol's native test setup; harmless for the app's own code.
        isCoreLibraryDesugaringEnabled = true
    }

    // AGP 8+ requires explicit opt-in to emit BuildConfig.java.
    // Required so MainActivity.kt can read BuildConfig.DEBUG to gate FLAG_SECURE
    // in debug builds while keeping screenshot protection in release/profile builds.
    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.beautica.beautica_mobile"
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Phase 17.5 — patrol native E2E test runner. PatrolJUnitRunner replaces
        // the default AndroidJUnitRunner so `patrol test` can discover and drive
        // the Dart patrolTest(...) cases through native instrumentation. This
        // affects ONLY the androidTest variant — the app's production/debug APK
        // and the headless `flutter test integration_test/` path are untouched.
        // clearPackageData wipes app data between native test cases for isolation.
        testInstrumentationRunner = "pl.leancode.patrol.PatrolJUnitRunner"
        testInstrumentationRunnerArguments["clearPackageData"] = "true"
    }

    // Phase 17.5 — run each patrol native test in an isolated process via the
    // AndroidX Test Orchestrator. Required by patrol for reliable native runs
    // (permission grants, app restarts) and pairs with clearPackageData above.
    testOptions {
        execution = "ANDROIDX_TEST_ORCHESTRATOR"
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
            // ProGuard rules in proguard-rules.pro protect the reflection-based
            // native plugins (flutter_secure_storage, screen_protector, etc.).
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

// Phase 17.5 — patrol native test dependencies.
//   * coreLibraryDesugaring backs `isCoreLibraryDesugaredEnabled = true` above
//     so the test orchestrator's Java 8+ APIs work on minSdk 26.
//   * androidTestUtil orchestrator powers ANDROIDX_TEST_ORCHESTRATOR execution.
// Both are androidTest-only — they add nothing to the shipped app APK.
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    androidTestUtil("androidx.test:orchestrator:1.5.1")
}
