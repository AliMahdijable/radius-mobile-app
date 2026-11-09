package com.mysvcs.rad_mysvcs

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import com.sunmi.peripheral.printer.InnerPrinterCallback
import com.sunmi.peripheral.printer.InnerPrinterException
import com.sunmi.peripheral.printer.InnerPrinterManager
import com.sunmi.peripheral.printer.InnerResultCallback
import com.sunmi.peripheral.printer.SunmiPrinterService
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * «طابعة الوصولات» (٩ نوفمبر): طابعات الكاشير الحراريّة عبر البلوتوث المعتاد (SPP) وطابعة الجهاز المدمجة (SUNMI).
 *
 * الطبقة رفيعة عمداً: تتّصل وتكتب وتقرأ وتُغلق — ومنطق الوصل كلّه (الصورة، أسئلة الحالة، منع التكرار، «غير مؤكَّد»)
 * في دارت (lib/services/receipt_printer/) حيث يُختبر. كلّ ما يلمس البلوتوث أو خدمة الطابعة على خيطٍ واحدٍ في
 * الخلفيّة — بالترتيب، ولا يتجمّد خيط الواجهة أبداً.
 *
 * لا بحث عن أجهزة: الطابعة تُقرن من إعدادات البلوتوث، فلا إذن بحثٍ ولا موقع. خدمة SUNMI لا تُربط إلّا حين تُطلب
 * (اختيار «طابعة الجهاز» أو الطباعة عليها) — لا شيء عند فتح التطبيق على أيّ هاتف.
 */
class ReceiptPrinterChannel(context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val app: Context = context.applicationContext
    private val channel = MethodChannel(messenger, CHANNEL)
    private val io: ExecutorService = Executors.newSingleThreadExecutor { r ->
        Thread(r, "receipt-printer").apply { isDaemon = true }
    }
    private val main = Handler(Looper.getMainLooper())

    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var input: InputStream? = null
    @Volatile private var output: OutputStream? = null

    /** كلّ شركةٍ بمكتبتها الرسميّة — تُضاف غيرها هنا (iMin، Telpo…) دون مساس البلوتوث ولا دارت. */
    private val builtins: List<BuiltinPrinter> = listOf(SunmiBuiltin(app))

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        closeSocket()
        try {
            io.execute { builtins.forEach { it.release() } }
        } catch (_: RejectedExecutionException) {
        }
        io.shutdown()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "btState" -> background(result) { btState() }
            "btPaired" -> background(result) { btPaired() }
            // أندرويد يطبع على المقترنة وحدها — البحث للآيفون (BLE).
            "btScan" -> result.success(emptyList<Any>())
            "btConnect" -> {
                val id = call.argument<String>("id") ?: ""
                val timeout = call.argument<Number>("timeoutMs")?.toLong() ?: 12000L
                background(result) { btConnect(id, timeout) }
            }
            "btWrite" -> {
                val data = call.argument<ByteArray>("data") ?: ByteArray(0)
                background(result) { btWrite(data) }
            }
            "btRead" -> {
                val timeout = call.argument<Number>("timeoutMs")?.toLong() ?: 500L
                val max = call.argument<Number>("max")?.toInt() ?: 64
                background(result) { btRead(timeout, max) }
            }
            // فوراً لا بالدور: الإغلاق يفكّ كتابةً عالقة على طابعةٍ اختفت.
            "btClose" -> {
                closeSocket()
                result.success(true)
            }
            "btSettings" -> {
                openBluetoothSettings()
                result.success(true)
            }
            "builtinInfo" -> background(result) { builtinInfo() }
            "builtinPrint" -> {
                val chunks = call.argument<List<ByteArray>>("chunks") ?: emptyList()
                val timeout = call.argument<Number>("timeoutMs")?.toLong() ?: 30000L
                background(result) { builtinPrint(chunks, timeout) }
            }
            else -> result.notImplemented()
        }
    }

    /** [block] على خيط الطابعة، والردّ على خيط الواجهة. */
    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        try {
            io.execute {
                try {
                    val value = block()
                    main.post { result.success(value) }
                } catch (e: PrinterException) {
                    main.post { result.error(e.code, e.message, null) }
                } catch (e: SecurityException) {
                    main.post { result.error("permission", e.message, null) }
                } catch (e: Exception) {
                    main.post { result.error("io", e.message ?: e.javaClass.simpleName, null) }
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error("io", "closed", null)
        }
    }

    // ─── البلوتوث (SPP) ─────────────────────────────

    private fun adapter(): BluetoothAdapter? =
        (app.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    /** أندرويد ١٢+: «الأجهزة المجاورة»؛ قبله إذن التثبيت يكفي. */
    private fun canConnect(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            app.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    private fun btState(): Map<String, Any> {
        val a = adapter()
        return mapOf(
            "supported" to (a != null),
            "enabled" to (a?.isEnabled == true),
            "authorized" to canConnect(),
        )
    }

    @SuppressLint("MissingPermission")
    private fun ready(): BluetoothAdapter {
        val a = adapter() ?: throw PrinterException("unsupported", "no bluetooth adapter")
        if (!canConnect()) throw PrinterException("permission", "BLUETOOTH_CONNECT not granted")
        if (!a.isEnabled) throw PrinterException("off", "bluetooth is off")
        return a
    }

    @SuppressLint("MissingPermission")
    private fun btPaired(): List<Map<String, Any>> {
        val a = ready()
        return a.bondedDevices.orEmpty().map { d ->
            val major = d.bluetoothClass?.majorDeviceClass
            mapOf(
                "id" to d.address,
                "name" to (d.name ?: ""),
                // صنف «تصوير/طابعة» — يُقدَّم في القائمة (كثيرٌ من الطابعات بلا صنفٍ فتبقى في القائمة كغيرها).
                "printer" to (major == BluetoothClass.Device.Major.IMAGING),
                "le" to (d.type == BluetoothDevice.DEVICE_TYPE_LE),
            )
        }
    }

    @SuppressLint("MissingPermission")
    private fun btConnect(id: String, timeoutMs: Long): Boolean {
        closeSocket()
        val a = ready()
        if (!BluetoothAdapter.checkBluetoothAddress(id)) throw PrinterException("not_found", "bad address")
        if (a.bondedDevices.orEmpty().none { it.address == id }) throw PrinterException("not_found", "not paired")
        val device = a.getRemoteDevice(id)
        // البحث الجاري يبطئ الاتصال — إيقافه يحتاج إذن البحث على أندرويد ١٢+ ولا نطلبه.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            try {
                a.cancelDiscovery()
            } catch (_: Exception) {
            }
        }
        val deadline = System.currentTimeMillis() + timeoutMs
        var last: Exception? = null
        // الآمن أوّلاً ثمّ غير الآمن: بعض الطابعات الرخيصة لا تقبل إلّا الثاني.
        for (secure in listOf(true, false)) {
            val remaining = deadline - System.currentTimeMillis()
            if (remaining < 1500) break
            val s = try {
                if (secure) device.createRfcommSocketToServiceRecord(SPP)
                else device.createInsecureRfcommSocketToServiceRecord(SPP)
            } catch (e: IOException) {
                last = e
                continue
            }
            val timedOut = AtomicBoolean(false)
            val watchdog = Runnable {
                timedOut.set(true)
                try {
                    s.close()
                } catch (_: IOException) {
                }
            }
            main.postDelayed(watchdog, remaining)
            try {
                s.connect()
                main.removeCallbacks(watchdog)
                socket = s
                input = s.inputStream
                output = s.outputStream
                return true
            } catch (e: IOException) {
                main.removeCallbacks(watchdog)
                try {
                    s.close()
                } catch (_: IOException) {
                }
                if (timedOut.get()) throw PrinterException("timeout", "connect timeout")
                last = e
            }
        }
        throw PrinterException("connect_failed", last?.message ?: "connect failed")
    }

    private fun btWrite(data: ByteArray): Boolean {
        val out = output ?: throw PrinterException("io", "not connected")
        var off = 0
        while (off < data.size) {
            val n = minOf(WRITE_CHUNK, data.size - off)
            out.write(data, off, n)
            out.flush()
            off += n
            if (off < data.size) Thread.sleep(WRITE_GAP_MS)
        }
        return true
    }

    /** ما وصل من الطابعة خلال [timeoutMs] (ردّ سؤال حالة: بايتٌ واحد عادةً) — فارغٌ إن لم يصل شيء. */
    private fun btRead(timeoutMs: Long, max: Int): ByteArray {
        val inp = input ?: throw PrinterException("io", "not connected")
        val deadline = System.currentTimeMillis() + timeoutMs
        val buf = ByteArrayOutputStream()
        while (System.currentTimeMillis() < deadline && buf.size() < max) {
            val n = inp.available()
            if (n <= 0) {
                Thread.sleep(20)
                continue
            }
            val chunk = ByteArray(minOf(n, max - buf.size()))
            val r = inp.read(chunk)
            if (r < 0) throw PrinterException("io", "closed")
            buf.write(chunk, 0, r)
            Thread.sleep(30)
            if (inp.available() == 0) break
        }
        return buf.toByteArray()
    }

    private fun closeSocket() {
        val s = socket
        socket = null
        input = null
        output = null
        try {
            s?.close()
        } catch (_: IOException) {
        }
    }

    private fun openBluetoothSettings() {
        try {
            app.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: Exception) {
        }
    }

    // ─── طابعة الجهاز المدمجة ─────────────────────────

    private fun builtinInfo(): Map<String, Any?> {
        for (b in builtins) if (b.present()) return b.info()
        return mapOf("available" to false, "vendor" to "")
    }

    private fun builtinPrint(chunks: List<ByteArray>, timeoutMs: Long): Map<String, Any?> {
        val b = builtins.firstOrNull { it.present() } ?: throw PrinterException("unsupported", "no built-in printer")
        return b.print(chunks, timeoutMs)
    }

    companion object {
        const val CHANNEL = "com.mysvcs.rad_mysvcs/receipt_printer"

        /** منفذ الطابعات التسلسليّ على البلوتوث (SPP). */
        private val SPP: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val WRITE_CHUNK = 512
        private const val WRITE_GAP_MS = 3L
    }
}

/** خطأٌ برمزٍ تفهمه دارت (printer_bridge.dart). */
class PrinterException(val code: String, message: String?) : Exception(message)

/** طابعة جهازٍ مدمجة — كلّ شركةٍ بمكتبتها الرسميّة. */
interface BuiltinPrinter {
    val vendor: String

    /** فحصٌ سريع بلا ربط (هل خدمة الشركة مثبّتة في الجهاز؟). */
    fun present(): Boolean
    fun info(): Map<String, Any?>
    fun print(chunks: List<ByteArray>, timeoutMs: Long): Map<String, Any?>
    fun release()
}

/**
 * SUNMI بمكتبتها الرسميّة com.sunmi:printerlibrary (خدمة woyou.aidlservice.jiuiv5 في كلّ أجهزتها بطابعة).
 * الوصل أوامر ESC/POS خامّاً (sendRAWData) بوضع «المعاملة»: الطابعة تقول في النهاية طُبع (٠) أم لا.
 */
class SunmiBuiltin(private val app: Context) : BuiltinPrinter {
    override val vendor = "sunmi"

    @Volatile private var service: SunmiPrinterService? = null
    private var connection: InnerPrinterCallback? = null

    override fun present(): Boolean = try {
        @Suppress("DEPRECATION")
        app.packageManager.getPackageInfo(SERVICE_PACKAGE, 0)
        true
    } catch (_: Exception) {
        false
    }

    private fun bind(timeoutMs: Long): SunmiPrinterService? {
        service?.let { return it }
        val latch = CountDownLatch(1)
        val cb = object : InnerPrinterCallback() {
            override fun onConnected(s: SunmiPrinterService) {
                service = s
                latch.countDown()
            }

            override fun onDisconnected() {
                service = null
            }
        }
        val bound = try {
            InnerPrinterManager.getInstance().bindService(app, cb)
        } catch (_: Exception) {
            false
        }
        if (!bound) return null
        connection = cb
        latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        return service
    }

    override fun info(): Map<String, Any?> {
        val s = bind(BIND_TIMEOUT_MS) ?: return mapOf("available" to false, "vendor" to vendor)
        val status = try {
            s.updatePrinterState()
        } catch (_: Exception) {
            0
        }
        val paper = try {
            when (s.printerPaper) {
                1 -> 58
                2 -> 80
                else -> 0
            }
        } catch (_: Exception) {
            0
        }
        val model = Build.MODEL.orEmpty().trim()
        val label = if (model.contains("sunmi", ignoreCase = true)) model else "SUNMI $model".trim()
        return mapOf(
            "available" to true,
            "vendor" to vendor,
            "status" to status,
            "paper" to paper,
            "model" to label,
        )
    }

    override fun print(chunks: List<ByteArray>, timeoutMs: Long): Map<String, Any?> {
        val s = bind(BIND_TIMEOUT_MS) ?: throw PrinterException("unsupported", "SUNMI printer service unavailable")
        val latch = CountDownLatch(1)
        var transaction = true
        var code = -1
        var message = ""
        val callback = object : InnerResultCallback() {
            override fun onRunResult(isSuccess: Boolean) {
                // بلا «معاملة»: نجاح الأمر الأخير = وصل الخدمةَ الوصلُ كلّه (لا تأكيد طباعة).
                if (!transaction) {
                    code = if (isSuccess) 0 else 1
                    latch.countDown()
                }
            }

            override fun onReturnString(result: String?) {}

            override fun onRaiseException(c: Int, m: String?) {
                code = c
                message = m ?: ""
                latch.countDown()
            }

            override fun onPrintResult(c: Int, m: String?) {
                code = c
                message = m ?: ""
                latch.countDown()
            }
        }
        try {
            s.enterPrinterBuffer(true)
        } catch (_: Exception) {
            transaction = false
        }
        var sent = 0
        try {
            for (c in chunks) {
                s.sendRAWData(c, null)
                sent++
            }
            if (transaction) {
                try {
                    s.exitPrinterBufferWithCallback(true, callback)
                } catch (_: InnerPrinterException) {
                    // SUNMI V1 أو خدمة طابعةٍ أقدم: المكتبة ترفض «إنهاء المعاملة بنتيجة» قبل أن يصل الخدمةَ شيء
                    // ("this model/version does not support this method!") — فلم يُطبع شيء بعد. يُطبع المخزَّن كما هو
                    // (exitPrinterBuffer(true) تعرفه تلك الخدمات) بلا تأكيد، ونهايته سطرٌ بنتيجة ⇒ «أُرسل» لا «عطل».
                    // فشل الإطباع نفسه ⇒ المعاملة لم تُطبع فتُلغى كما كانت (الـcatch أدناه)؛ وبعده لا إلغاء: قد خرج.
                    s.exitPrinterBuffer(true)
                    transaction = false
                    s.lineWrap(1, callback)
                }
            } else {
                s.lineWrap(1, callback)
            }
        } catch (e: Exception) {
            if (transaction) {
                // معاملةٌ لم تكتمل تُلغى — لم يُطبع منها شيء.
                try {
                    s.exitPrinterBuffer(false)
                } catch (_: Exception) {
                }
                throw PrinterException("connect_failed", e.message)
            }
            throw PrinterException(if (sent == 0) "connect_failed" else "io", e.message)
        }
        val done = latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        return mapOf("transaction" to transaction, "done" to done, "code" to code, "message" to message)
    }

    override fun release() {
        val cb = connection ?: return
        try {
            InnerPrinterManager.getInstance().unBindService(app, cb)
        } catch (_: Exception) {
        }
        connection = null
        service = null
    }

    companion object {
        const val SERVICE_PACKAGE = "woyou.aidlservice.jiuiv5"
        private const val BIND_TIMEOUT_MS = 4000L
    }
}
