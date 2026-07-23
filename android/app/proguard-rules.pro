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

# screen_protector — MethodChannel handler for FLAG_SECURE (MASVS-PLATFORM MS6)
# Protects auth screens from OS-level screenshot/recording. R8 must not strip
# the MethodChannel implementation or preventScreenshotOn/Off become silent no-ops.
-keep class com.prongbang.screen_protector.** { *; }
-keepclassmembers class com.prongbang.screen_protector.** { *; }

# Dio — keep response type adapters
-keep class retrofit2.** { *; }
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn retrofit2.**
