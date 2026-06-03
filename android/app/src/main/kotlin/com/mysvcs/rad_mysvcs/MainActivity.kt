package com.mysvcs.rad_mysvcs

import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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

                else -> result.notImplemented()
            }
        }
    }
}
