package com.mysvcs.rad_mysvcs

import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.WindowManager
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Extends FlutterFragmentActivity (not FlutterActivity) so the local_auth
// plugin can attach its BiometricPrompt fragment. Without this, the prompt
// throws/rejects on Android even when fingerprint/face is enrolled.
class MainActivity : FlutterFragmentActivity() {
    // ٢٥ نوفمبر (اقتراح Google Play «العرض حتى حافّة الشاشة قد لا يكون مفعّلاً لدى الجميع»): أندرويد 15+ يرسم التطبيق تحت شريطي
    // النظام أصلاً (targetSdk 36) — وهنا أندرويد 14 فأقدم مثله.
    // ⚠️ لا يُستدعى بأندرويد 15+: هناك يجعل شريط الأزرار الثلاثة شفّافاً تماماً فيسقط الظلّ خلفها (أزرارٌ لا تُرى — محاكي أندرويد
    // 17، تطبيق المشترك ٢٥ نوفمبر). وبالأقدم نعيد «التباين» كما كان، ولون الشريط يضعه main.dart/MaterialApp بعده كما كان.
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.VANILLA_ICE_CREAM) {
            val navContrast = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) window.isNavigationBarContrastEnforced else null
            val statusContrast = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) window.isStatusBarContrastEnforced else null
            WindowCompat.enableEdgeToEdge(window)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                navContrast?.let { window.isNavigationBarContrastEnforced = it }
                statusContrast?.let { window.isStatusBarContrastEnforced = it }
            }
        }
    }

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

    // «حفظ الصورة» (١٩ نوفمبر — رمز دخول المشترك؛ المالك: «نخلي إمكانية حفظ الكيو آر، مو بس مشاركة»): إلى صور الهاتف
    // (Pictures/MyServices) عبر MediaStore بلا أيّ إذن — أندرويد 10 فأحدث (الملفّ ملك التطبيق). الأقدم ⇒ "unsupported" والتطبيق
    // يفتح نافذة المشاركة (لا إذن تخزين: سياسة Play — انظر AndroidManifest). lib/services/image_saver.dart.
    private fun saveImageToPictures(bytes: ByteArray, name: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "unsupported"
        val resolver = applicationContext.contentResolver
        val values = ContentValues()
        values.put(MediaStore.Images.Media.DISPLAY_NAME, "$name.png")
        values.put(MediaStore.Images.Media.MIME_TYPE, "image/png")
        values.put(MediaStore.Images.Media.RELATIVE_PATH, Environment.DIRECTORY_PICTURES + "/MyServices")
        values.put(MediaStore.Images.Media.IS_PENDING, 1)
        var uri: Uri? = null
        try {
            uri = resolver.insert(MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values)
            val target = uri ?: return "failed"
            val out = resolver.openOutputStream(target) ?: throw java.io.IOException("no output stream")
            out.use { it.write(bytes) }
            val done = ContentValues()
            done.put(MediaStore.Images.Media.IS_PENDING, 0)
            resolver.update(target, done, null, null)
            return "saved"
        } catch (_: Exception) {
            // صفٌّ بدأ ولم يكتمل لا يبقى في المعرض
            try {
                uri?.let { resolver.delete(it, null, null) }
            } catch (_: Exception) {
            }
            return "failed"
        }
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

                // الصفّارة شغّالة ⇒ الشاشة لا تنطفئ (الفنّي لا يلمس الهاتف)؛ تُرفع بإطفائها أو الخروج من «وضع الفنّي»
                "keepAwake" -> {
                    try {
                        if (call.argument<Boolean>("on") == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                    } catch (_: Exception) {
                    }
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.mysvcs.rad_mysvcs/media"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImage" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val raw = call.argument<String>("name") ?: "image"
                    val name = raw.replace(Regex("[^A-Za-z0-9_-]"), "_").take(80).ifEmpty { "image" }
                    if (bytes == null || bytes.isEmpty()) {
                        result.success("failed")
                    } else {
                        result.success(saveImageToPictures(bytes, name))
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
