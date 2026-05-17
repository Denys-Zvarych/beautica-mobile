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

# Dio — keep response type adapters
-keep class retrofit2.** { *; }
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn retrofit2.**
