# flutter_secure_storage — uses reflection to access Keystore
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keepclassmembers class com.it_nomads.fluttersecurestorage.** { *; }

# firebase_messaging — FCM listener and service classes
-keep class com.google.firebase.messaging.** { *; }
-keepclassmembers class com.google.firebase.messaging.** { *; }
-keep class io.flutter.plugins.firebase.messaging.** { *; }

# Kotlin metadata (required for kotlinx-coroutines used by firebase)
-keepattributes *Annotation*, Signature, Exception
-dontwarn kotlin.**

# json_serializable / freezed — preserve fromJson factory and toJson methods
# (Dart AOT strips unreferenced methods; these are called via dart:convert, not reflection)
-keepclassmembers class ** {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keepclassmembers class * {
    *** fromJson(com.google.gson.JsonElement);
    com.google.gson.JsonElement toJson();
}

# flutter_native_splash — MethodChannel handler reached via Flutter native bridge (Phase 2.15)
-keep class net.jonhanson.flutter_native_splash.** { *; }
-keepclassmembers class net.jonhanson.flutter_native_splash.** { *; }

# screen_protector — MethodChannel handler for FLAG_SECURE (MASVS-PLATFORM MS6)
# Protects auth screens from OS-level screenshot/recording. R8 must not strip
# the MethodChannel implementation or preventScreenshotOn/Off become silent no-ops.
-keep class io.etchells.screenprotector.** { *; }
-keepclassmembers class io.etchells.screenprotector.** { *; }

# Dio — keep response type adapters
-keep class retrofit2.** { *; }
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn retrofit2.**
