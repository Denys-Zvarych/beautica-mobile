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
