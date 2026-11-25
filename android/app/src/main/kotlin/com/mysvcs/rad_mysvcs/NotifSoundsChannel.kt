package com.mysvcs.rad_mysvcs

import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * «أصوات الإشعارات» (٢٥ نوفمبر — lib/services/notif_sound_engine.dart): معاينة النغمة (res/raw أو نغمة الجهاز أو صوت الهاتف)،
 * منتقي نغمات الهاتف، حالة الإذن والقناة و«عدم الإزعاج»، وفتح إعدادات القناة. القنوات نفسها ينشئها flutter_local_notifications.
 * النغمات تُطلب بأسمائها (getIdentifier) ⇒ res/raw/keep.xml يحفظها من المقلِّص (R8، AGP 9).
 */
class NotifSoundsChannel(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL = "com.mysvcs.rad_mysvcs/notif_sounds"
        const val REQ_PICK = 7311
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private var player: MediaPlayer? = null
    private var pendingPick: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    private fun stopPlayer() {
        try {
            player?.stop()
        } catch (_: Exception) {
        }
        try {
            player?.release()
        } catch (_: Exception) {
        }
        player = null
    }

    private fun play(raw: String?, uri: String?): Boolean {
        stopPlayer()
        val target: Uri = when {
            !raw.isNullOrEmpty() -> {
                val id = activity.resources.getIdentifier(raw, "raw", activity.packageName)
                if (id == 0) return false
                Uri.parse("android.resource://${activity.packageName}/$id")
            }
            !uri.isNullOrEmpty() -> Uri.parse(uri)
            else -> RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION) ?: return false
        }
        return try {
            val mp = MediaPlayer()
            mp.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            mp.setDataSource(activity, target)
            mp.setOnCompletionListener {
                try {
                    it.release()
                } catch (_: Exception) {
                }
                if (player === it) player = null
            }
            mp.prepare()
            mp.start()
            player = mp
            true
        } catch (_: Exception) {
            stopPlayer()
            false
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "play" -> result.success(play(call.argument<String>("raw"), call.argument<String>("uri")))

            "stop" -> {
                stopPlayer()
                result.success(null)
            }

            "pickRingtone" -> {
                if (pendingPick != null) {
                    result.success(null)
                    return
                }
                val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                    putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_NOTIFICATION)
                    putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                    putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, false)
                    putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, call.argument<String>("title") ?: "")
                    call.argument<String>("current")?.let { putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, Uri.parse(it)) }
                }
                pendingPick = result
                try {
                    activity.startActivityForResult(intent, REQ_PICK)
                } catch (_: Exception) {
                    pendingPick = null
                    result.success(null)
                }
            }

            "status" -> {
                val enabled = NotificationManagerCompat.from(activity).areNotificationsEnabled()
                val chans = HashMap<String, Any>()
                var dnd = false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val nm = activity.getSystemService(NotificationManager::class.java)
                    if (nm != null) {
                        for (id in call.argument<List<String>>("channels") ?: emptyList()) {
                            val ch = nm.getNotificationChannel(id) ?: continue
                            chans[id] = mapOf(
                                "importance" to ch.importance,
                                "sound" to (ch.sound != null),
                                "bypassDnd" to ch.canBypassDnd()
                            )
                        }
                        dnd = nm.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL &&
                            nm.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_UNKNOWN
                    }
                }
                result.success(mapOf("enabled" to enabled, "channels" to chans, "dnd" to dnd))
            }

            "openSettings" -> {
                val pkg = activity.packageName
                val ch = call.argument<String>("channel")
                val intent = when {
                    !ch.isNullOrEmpty() && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                        Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                            .putExtra(Settings.EXTRA_CHANNEL_ID, ch)
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                    else -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$pkg"))
                }
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                try {
                    activity.startActivity(intent)
                    result.success(true)
                } catch (_: Exception) {
                    result.success(false)
                }
            }

            else -> result.notImplemented()
        }
    }

    /** نتيجة منتقي النغمات — من MainActivity.onActivityResult. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK) return false
        val r = pendingPick ?: return true
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            r.success(null)
            return true
        }
        val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        }
        if (uri == null) {
            r.success(null)
            return true
        }
        val title = try {
            RingtoneManager.getRingtone(activity, uri)?.getTitle(activity) ?: ""
        } catch (_: Exception) {
            ""
        }
        r.success(mapOf("uri" to uri.toString(), "title" to title))
        return true
    }

    fun dispose() {
        stopPlayer()
        pendingPick?.success(null)
        pendingPick = null
        channel.setMethodCallHandler(null)
    }
}
