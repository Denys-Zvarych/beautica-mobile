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
        //
        // The AndroidX Test Orchestrator (testOptions below) is REQUIRED here:
        // patrol's PatrolAppService is single-test-per-process, and the
        // orchestrator is what runs each patrol test in a FRESH process. Without
        // it only the first patrol test passes; the second fails with HTTP 500
        // (`_testExecutionCompleted.isCompleted == false`). NOTE: the orchestrator
        // names a per-test output file after the test description, so patrol test
        // descriptions must NOT contain '/' — a path separator there crashes the
        // orchestrator (`File ...txt contains a path separator`). De-slash any
        // route names in the test NAME (assertions on real routes are fine).
        testInstrumentationRunner = "pl.leancode.patrol.PatrolJUnitRunner"
        testInstrumentationRunnerArguments["clearPackageData"] = "true"
    }

    // Phase 17.5 — run each patrol native test in an isolated process via the
    // AndroidX Test Orchestrator. REQUIRED by patrol: PatrolAppService is
    // single-test-per-process, so the orchestrator's fresh process per test is
    // what lets MORE THAN ONE patrol test run. Pairs with clearPackageData above.
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
            if (releaseConfig != null) {
                signingConfig = releaseConfig
            } else {
                // No BEAUTICA_* signing env vars → no real release keystore.
                // Assign the debug-key fallback at CONFIGURATION time (harmless:
                // it only affects the artifact IF a release is actually built).
                // The distribution guard itself is deferred to the EXECUTION phase
                // (taskGraph.whenReady below) so it fires ONLY when a release
                // artifact is genuinely being assembled — never for debug builds,
                // unit tests, or `:app:help`, all of which still evaluate this
                // release buildType block at config time (and would otherwise throw
                // under CI=true, breaking non-release CI work).
                signingConfig = signingConfigs.getByName("debug")
            }
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

// Distribution guard (mobile-security backlog, build.gradle.kts:74) — EXECUTION phase.
//
// A "release" APK/AAB signed with the debug key must NEVER reach a store /
// distribution. The check below runs in the EXECUTION phase via
// taskGraph.whenReady so it ONLY triggers when the concrete task graph actually
// includes a release-artifact task (assemble/bundle/package*Release). Debug
// builds, unit tests, and `:app:help` configure cleanly even under CI=true,
// because they never put a release-assembling task in the graph.
//
// We HARD-FAIL when ALL of these hold:
//   1. A release artifact is being assembled (task-graph predicate below), AND
//   2. The release signingConfig is ABSENT (debug-key fallback is in effect), AND
//   3. A distribution signal is present:
//        * CI env var set (`System.getenv("CI")`) — GitHub Actions and most CI
//          providers export CI=true automatically.
//        * BEAUTICA_REQUIRE_RELEASE_SIGNING=1 env var — explicit opt-in for
//          store-bound builds outside CI.
//        * -Prelease.signing.required Gradle property — explicit opt-in on the
//          command line (`./gradlew assembleRelease -Prelease.signing.required`).
// When (1) and (2) hold but NO distribution signal is present, we KEEP the
// debug-key fallback so local `scripts/deploy_apk.sh release` smoke builds still
// work — but emit a LOUD warning so a debug-signed "release" can never go
// unnoticed.
project.gradle.taskGraph.whenReady {
    val assemblesRelease = allTasks.any { task ->
        task.name.contains("Release") &&
            (task.name.startsWith("assemble") ||
                task.name.startsWith("bundle") ||
                task.name.startsWith("package"))
    }
    val releaseSigningAbsent =
        android.signingConfigs.findByName("release") == null
    if (assemblesRelease && releaseSigningAbsent) {
        val ciSignal = !System.getenv("CI").isNullOrBlank()
        val envRequiresSigning =
            System.getenv("BEAUTICA_REQUIRE_RELEASE_SIGNING") == "1"
        val propRequiresSigning = project.hasProperty("release.signing.required")
        if (ciSignal || envRequiresSigning || propRequiresSigning) {
            throw GradleException(
                "Release signing is REQUIRED for this build but the BEAUTICA_* " +
                    "signing env vars are absent (BEAUTICA_KEYSTORE_PATH, " +
                    "BEAUTICA_KEYSTORE_PASSWORD, BEAUTICA_KEY_ALIAS, " +
                    "BEAUTICA_KEY_PASSWORD). Refusing to produce a debug-signed " +
                    "release artifact for distribution. Set the signing env vars, " +
                    "or drop the distribution signal (unset CI / " +
                    "BEAUTICA_REQUIRE_RELEASE_SIGNING / -Prelease.signing.required) " +
                    "for a local-only smoke build."
            )
        }
        logger.warn(
            "⚠️  RELEASE build is using the DEBUG signing key — NOT for " +
                "distribution. Set BEAUTICA_* signing env vars for a real release."
        )
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
//   * coreLibraryDesugaring backs `isCoreLibraryDesugaringEnabled = true` above
//     so the test orchestrator's Java 8+ APIs work on minSdk 26.
//   * androidTestUtil orchestrator powers ANDROIDX_TEST_ORCHESTRATOR execution,
//     which is REQUIRED because patrol's PatrolAppService is one-test-per-process
//     — the orchestrator runs each patrol test in a fresh process so more than
//     one patrol test can run. (Reminder: keep '/' out of patrol test
//     descriptions; the orchestrator names a per-test output file after the
//     description and a path separator there crashes it.)
// Both are androidTest-only — they add nothing to the shipped app APK.
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    androidTestUtil("androidx.test:orchestrator:1.5.1")
}
