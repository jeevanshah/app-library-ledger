# ML Kit text recognition ships optional per-script recognizer classes
# (Chinese/Japanese/Korean/Devanagari) that this app doesn't depend on —
# only the default Latin-script recognizer is used for the OCR scan flow.
# R8 warns about these missing classes during minification; suppress rather
# than pulling in unused language packs.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions

# flutter_local_notifications uses Gson to (de)serialize scheduled
# notifications, which needs generic type info (Signature attributes)
# that R8 strips by default. Without these keep rules,
# ScheduledNotificationBootReceiver crashes the whole process with
# "Missing type parameter" the moment BOOT_COMPLETED fires — i.e. on
# every real user's next phone reboot.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.google.gson.reflect.TypeToken { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
