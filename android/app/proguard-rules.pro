# ProGuard rules for release builds
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.idealstore.pos.** { *; }

# Play Core (for deferred components)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Bluetooth printer plugin (uses reflection)
-keep class com.anish.blur.** { *; }
-keep class flutter_bluetooth_printer.** { *; }
-dontwarn flutter_bluetooth_printer.**
