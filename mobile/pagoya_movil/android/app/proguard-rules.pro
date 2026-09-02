# PagoYa Móvil — reglas de R8/ProGuard para el build de release.
#
# Sin estas reglas la app funciona en debug y falla en release, que es la peor
# forma posible de descubrir un problema: ya está el APK subido a Play.

# ------------------------------------------------------------------
# Flutter
# ------------------------------------------------------------------
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# ------------------------------------------------------------------
# ML Kit — escáner de códigos de barras (mobile_scanner).
# R8 elimina los detectores porque solo se referencian por reflexión.
# Síntoma si falta: la cámara abre pero no lee NINGÚN código, sin error.
# ------------------------------------------------------------------
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-dontwarn com.google.mlkit.**

# Solo se declara el modelo de códigos de barras (ver el meta-data
# com.google.mlkit.vision.DEPENDENCIES del manifiesto). Se silencian los
# módulos de ML Kit que no usamos para que R8 no avise de clases ausentes.
-dontwarn com.google.mlkit.vision.text.**
-dontwarn com.google.mlkit.vision.face.**
-dontwarn com.google.mlkit.vision.label.**

# ------------------------------------------------------------------
# CameraX — lo usa mobile_scanner por debajo.
# ------------------------------------------------------------------
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# ------------------------------------------------------------------
# Seguridad / Keystore — flutter_secure_storage.
# Si R8 se lleva Tink, se pierde el UUID del dispositivo al actualizar la app
# y el cliente queda DESACTIVADO. Es el bug más caro posible aquí.
# ------------------------------------------------------------------
-keep class androidx.security.crypto.** { *; }
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# ------------------------------------------------------------------
# Bluetooth — print_bluetooth_thermal y flutter_blue_plus.
# ------------------------------------------------------------------
-keep class com.boskokg.flutter_blue_plus.** { *; }
-keep class groons.web.flutter.print_bluetooth_thermal.** { *; }
-dontwarn android.bluetooth.**

# ------------------------------------------------------------------
# SQLite nativo — sqlite3_flutter_libs (dueño: flutter-datos).
# ------------------------------------------------------------------
-keep class com.tekartik.sqflite.** { *; }
-dontwarn org.sqlite.**

# ------------------------------------------------------------------
# Play Core — Flutter lo referencia para deferred components aunque no los
# usemos. Sin esto, el build de release falla con "missing class".
# ------------------------------------------------------------------
-dontwarn com.google.android.play.core.**

# ------------------------------------------------------------------
# Kotlin
# ------------------------------------------------------------------
-keepclassmembers class ** {
    @kotlin.Metadata *;
}
-dontwarn kotlin.**

# ------------------------------------------------------------------
# Deja los nombres de método en los stack traces de release. Cuando un cliente
# reporta un cierre inesperado por WhatsApp, es la diferencia entre arreglarlo
# y adivinar.
# ------------------------------------------------------------------
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,Exceptions
-renamesourcefileattribute SourceFile