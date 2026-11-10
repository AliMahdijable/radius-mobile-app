package com.mysvcs.rad_mysvcs

import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Extends FlutterFragmentActivity (not FlutterActivity) so the local_auth
// plugin can attach its BiometricPrompt fragment. Without this, the prompt
// throws/rejects on Android even when fingerprint/face is enrolled.
class MainActivity : FlutterFragmentActivity() {
    // «طابعة الوصولات» (٩ نوفمبر): بلوتوث SPP + طابعة الجهاز (SUNMI) — lib/services/receipt_printer/.
    private var receiptPrinter: ReceiptPrinterChannel? = null

    // «صفّارة وضع الفنّي» (شبكة الألياف، ١٠ نوفمبر): نغمةٌ بصوت الوسائط — «صوت اللمس» (SystemSound.click) مطفأٌ بأغلب الهواتف
    // فكانت الصفّارة بلا صوت. lib/services/tech_beep.dart.
    private var beepTone: ToneGenerator? = null

    private fun releaseBeep() {
        try {
            beepTone?.release()
        } catch (_: Exception) {
        }
        beepTone = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        receiptPrinter?.dispose()
        receiptPrinter = ReceiptPrinterChannel(this, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mysvcs.rad_mysvcs/beep"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "beep" -> {
                    val ms = (call.argument<Int>("ms") ?: 90).coerceIn(20, 500)
                    try {
                        // 2600 هرتز: واضحةٌ بسمّاعة الهاتف وخارج المبنى. المولّد يُنشأ مرّةً ويُعاد استعماله.
                        val tone = beepTone
                            ?: ToneGenerator(AudioManager.STREAM_MUSIC, ToneGenerator.MAX_VOLUME).also { beepTone = it }
                        tone.startTone(ToneGenerator.TONE_CDMA_MED_L, ms)
                        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        // false = صوت الوسائط صفر: تشتغل ولا تُسمع — التطبيق يقولها للفنّي
                        result.success(audio.getStreamVolume(AudioManager.STREAM_MUSIC) > 0)
                    } catch (_: Exception) {
                        // مسارات الصوت مستنفدة أو المولّد مات ⇒ يُعاد إنشاؤه في النغمة التالية
                        releaseBeep()
                        result.success(null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mysvcs.rad_mysvcs/app_info"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAppVersion" -> {
                    try {
                        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageInfo(
                                packageName,
                                PackageManager.PackageInfoFlags.of(0)
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo(packageName, 0)
                        }

                        val versionName = packageInfo.versionName.orEmpty()
                        val buildNumber = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                            packageInfo.longVersionCode.toString()
                        } else {
                            @Suppress("DEPRECATION")
                            packageInfo.versionCode.toString()
                        }

                        result.success(
                            mapOf(
                                "version" to versionName,
                                "buildNumber" to buildNumber,
                            )
                        )
                    } catch (error: Exception) {
                        result.error(
                            "APP_VERSION_ERROR",
                            error.message ?: "Unknown error",
                            null,
                        )
                    }
                }

                // نوع الجهاز لتشخيصٍ بلا هويّة (ClientDiag) — إلغاء Credential Manager الصامت بعد
                // اختيار حساب Google على أجهزةٍ بعينها (بلاغ ٢٠٢٦-١٠-١٦: تكنو/هونر…).
                "getDeviceInfo" -> {
                    val gms = try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            packageManager.getPackageInfo(
                                "com.google.android.gms",
                                PackageManager.PackageInfoFlags.of(0)
                            ).versionName
                        } else {
                            @Suppress("DEPRECATION")
                            packageManager.getPackageInfo("com.google.android.gms", 0).versionName
                        }
                    } catch (_: Exception) {
                        null
                    }
                    result.success(
                        mapOf(
                            "manufacturer" to Build.MANUFACTURER,
                            "brand" to Build.BRAND,
                            "model" to Build.MODEL,
                            "sdk" to Build.VERSION.SDK_INT.toString(),
                            "release" to Build.VERSION.RELEASE,
                            "gms" to gms,
                        )
                    )
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        receiptPrinter?.dispose()
        receiptPrinter = null
        releaseBeep()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
