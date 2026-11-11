# R8 rules for the release build (minify + shrink are on).
# See docs/release.md. If the CI release job reports missing classes, add the
# suggestions from build/app/outputs/mapping/release/missing_rules.txt here.

# MediaPipe Tasks Vision (flutter_mp_pose_landmarker) loads classes through JNI
# and reflection; stripping or renaming them breaks pose detection at runtime.
-keep class com.google.mediapipe.** { *; }
-keep interface com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# MediaPipe's generated protobuf messages are resolved reflectively.
-keep class com.google.protobuf.** { *; }
-dontwarn com.google.protobuf.**
-keep class * extends com.google.protobuf.GeneratedMessageLite { *; }

# Optional annotation/AutoValue classes referenced by MediaPipe but not shipped.
-dontwarn javax.annotation.**
-dontwarn com.google.auto.value.**
-dontwarn org.checkerframework.**
-dontwarn com.google.errorprone.annotations.**

# flutter_mp_pose_landmarker sends landmarks to Dart as Gson JSON built from
# Kotlin data classes (CameraManager.Landmark / WorldLandmark). Gson reads the
# field names reflectively: renaming x/y/z/visibility/presence breaks parsing
# in release builds only.
-keep class com.carecode.flutter_mp_pose_lm.** { *; }
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-dontwarn sun.misc.**

# Native methods keep their names for JNI lookup.
-keepclasseswithmembernames class * {
    native <methods>;
}

# Flutter's deferred components reference Play Core, which is not bundled.
-dontwarn com.google.android.play.core.**
