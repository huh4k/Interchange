# R8 strips Kotlin runtime classes that plugins (e.g. shared_preferences) reach
# reflectively, which crashes release builds at startup with NoSuchMethodError /
# ClassNotFoundException before the first frame.
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-dontwarn kotlin.**
