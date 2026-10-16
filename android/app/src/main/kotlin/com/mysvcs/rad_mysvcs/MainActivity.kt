package com.mysvcs.rad_mysvcs

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Extends FlutterFragmentActivity (not FlutterActivity) so the local_auth
// plugin can attach its BiometricPrompt fragment. Without this, the prompt
// throws/rejects on Android even when fingerprint/face is enrolled.
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
}
