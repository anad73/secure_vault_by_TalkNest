# Flutter's own rules are added by the Flutter Gradle plugin.

# flutter_secure_storage -> Tink references annotation-only classes.
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn com.google.crypto.tink.**
-keep class com.google.crypto.tink.** { *; }

# Flutter deferred-components references (unused here).
-dontwarn com.google.android.play.core.**

# MethodChannel handler in MainActivity.
-keep class com.safevault.app.MainActivity { *; }
