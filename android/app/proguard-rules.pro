# flutter_local_notifications (usa Gson para guardar las notificaciones programadas)
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class * extends com.google.gson.TypeAdapter
-keep class * extends com.google.gson.reflect.TypeToken
# Health Connect
-keep class androidx.health.** { *; }
-dontwarn com.google.android.play.core.**
# ML Kit: solo usamos el reconocedor latino; los demás idiomas no se incluyen
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
