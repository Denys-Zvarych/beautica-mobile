pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // Phase 066 — applied per-module only when android/app/google-services.json exists.
    id("com.google.gms.google-services") version "4.4.2" apply false
    // Phase 411 (R.4) D4 — R8 mapping upload + ProGuard UUID injection for Sentry.
    // Exact pin (6.23.x line per the phase doc).
    id("io.sentry.android.gradle") version "6.23.0" apply false
}

include(":app")
