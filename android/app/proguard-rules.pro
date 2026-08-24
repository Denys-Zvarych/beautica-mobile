# flutter_secure_storage — uses reflection to access Keystore
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keepclassmembers class com.it_nomads.fluttersecurestorage.** { *; }

# Kotlin metadata — keep generic signatures / annotations for the reflection-
# based native plugins above.
-keepattributes *Annotation*, Signature, Exception
-dontwarn kotlin.**

# flutter_native_splash — MethodChannel handler reached via Flutter native bridge (Phase 2.15)
-keep class net.jonhanson.flutter_native_splash.** { *; }
-keepclassmembers class net.jonhanson.flutter_native_splash.** { *; }

# screen_protector — MethodChannel handler for the app-switcher / data-leakage
# blur. It no longer serves FLAG_SECURE: screenshots and screen recording are
# ALLOWED by product decision 2026-08-20 (see the header comment in
# MainActivity.kt), and no Dart code calls preventScreenshotOn/Off any more.
# R8 must not strip the MethodChannel implementation or
# protectDataLeakageWithBlur/…Off become silent no-ops.
-keep class com.prongbang.screen_protector.** { *; }
-keepclassmembers class com.prongbang.screen_protector.** { *; }

# Dio — keep response type adapters
-keep class retrofit2.** { *; }
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn retrofit2.**
