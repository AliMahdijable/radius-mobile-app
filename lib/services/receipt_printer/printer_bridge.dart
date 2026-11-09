import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// خطأٌ من الطبقة الأصليّة برمزٍ ثابت:
/// `unsupported` · `off` · `permission` · `not_found` · `connect_failed` · `timeout` · `no_write` · `io` · `busy`.
class PrinterFailure implements Exception {
  const PrinterFailure(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => 'PrinterFailure($code${message == null ? '' : ': $message'})';
}

/// حال بلوتوث الهاتف.
@immutable
class BtState {
  const BtState({required this.supported, required this.enabled, this.authorized = true});

  final bool supported;
  final bool enabled;

  /// الآيفون: هل سُمح للتطبيق بالبلوتوث (أندرويد: [BtPermissionGate]).
  final bool authorized;
}

/// طابعةٌ (أو جهازٌ) يراه الهاتف — المقترن بأندرويد، أو ما وُجد بالبحث على الآيفون.
@immutable
class BtDevice {
  const BtDevice({required this.id, required this.name, this.printer = false, this.leOnly = false, this.rssi});

  final String id;
  final String name;

  /// صنفه عند البلوتوث «طابعة/تصوير» — يُقدَّم في القائمة.
  final bool printer;

  /// أندرويد: جهاز BLE فقط — لا يُطبع عليه بالبلوتوث المعتاد.
  final bool leOnly;

  /// الآيفون: قوّة الإشارة (الأقرب أعلى).
  final int? rssi;

  static BtDevice fromMap(Map<Object?, Object?> m) => BtDevice(
        id: '${m['id'] ?? ''}',
        name: '${m['name'] ?? ''}'.trim(),
        printer: m['printer'] == true,
        leOnly: m['le'] == true,
        rssi: m['rssi'] is int ? m['rssi'] as int : null,
      );
}

/// طابعة الجهاز المدمجة كما وجدتها الطبقة الأصليّة.
@immutable
class BuiltinInfo {
  const BuiltinInfo({required this.available, this.vendor = '', this.status = 0, this.paperMm = 0, this.model = ''});

  final bool available;

  /// الشركة (`sunmi`) — كلّ شركةٍ بمكتبتها الرسميّة (MainActivity ← ReceiptPrinterChannel).
  final String vendor;

  /// رمز حالتها كما تعطيه مكتبتها (SUNMI: ١ جاهزة · ٢ تتهيّأ · ٣ عطل اتّصال · ٤ نفد الورق · ٥ ساخنة · ٦ الغطاء
  /// مفتوح · ٧ عطل القاطع · ٨ القاطع عاد · ٩ لا علامة سوداء · ٥٠٥ لا طابعة · ٥٠٧ فشل تحديثها).
  final int status;

  /// عرض ورقها إن عرفته (٥٨ / ٨٠)، وإلّا ٠.
  final int paperMm;
  final String model;

  /// لا خدمة طابعةٍ مدمجة في الجهاز أصلاً (هاتفٌ عاديّ): الطبقة الأصليّة لم تجد شركةً بمكتبتها ([vendor] فارغ). غير
  /// «موجودةٌ ولم تُربط بعد» (الشركة معروفة) — تلك قد تجهز بعد لحظات.
  bool get absent => !available && vendor.isEmpty;

  static BuiltinInfo fromMap(Map<Object?, Object?> m) => BuiltinInfo(
        available: m['available'] == true,
        vendor: '${m['vendor'] ?? ''}',
        status: m['status'] is int ? m['status'] as int : 0,
        paperMm: m['paper'] is int ? m['paper'] as int : 0,
        model: '${m['model'] ?? ''}'.trim(),
      );
}

/// ما ردّت به طابعة الجهاز على الوصل.
@immutable
class BuiltinAck {
  const BuiltinAck({required this.transaction, required this.done, this.code = -1, this.message = ''});

  /// طُبع بوضع «المعاملة» (تؤكّد الطابعة نتيجته) — وإلّا أُرسل فقط.
  final bool transaction;

  /// ردّت الطابعة قبل المهلة.
  final bool done;

  /// ٠ = طُبع.
  final int code;
  final String message;

  static BuiltinAck fromMap(Map<Object?, Object?> m) => BuiltinAck(
        transaction: m['transaction'] == true,
        done: m['done'] == true,
        code: m['code'] is int ? m['code'] as int : -1,
        message: '${m['message'] ?? ''}',
      );
}

/// ما يطلبه التطبيق من الهاتف للطباعة — يُستبدل في الاختبارات.
abstract class PrinterBridge {
  Future<BtState> btState();

  /// أندرويد: الأجهزة المقترنة بالهاتف (الطابعة تُقرن من إعدادات البلوتوث).
  Future<List<BtDevice>> btPaired();

  /// الآيفون: بحثٌ عن طابعات BLE القريبة.
  Future<List<BtDevice>> btScan(Duration timeout);

  Future<void> btConnect(String id, Duration timeout);
  Future<void> btWrite(Uint8List data);

  /// ما وصل من الطابعة (ردود أسئلة الحالة) — فارغٌ إن لم يصل شيءٌ خلال [timeout].
  Future<Uint8List> btRead(Duration timeout, {int max = 64});
  Future<void> btClose();

  /// إعدادات البلوتوث في الهاتف (الآيفون: إعدادات التطبيق).
  Future<void> btSettings();

  Future<BuiltinInfo> builtinInfo();
  Future<BuiltinAck> builtinPrint(List<Uint8List> chunks, Duration timeout);
}

/// القناة إلى الطبقة الأصليّة: أندرويد `ReceiptPrinterChannel.kt` (SPP + SUNMI)، الآيفون `ReceiptPrinterBle.swift`
/// (BLE). كلّ اتّصالٍ وكتابةٍ هناك خارج خيط الواجهة.
class MethodChannelPrinterBridge implements PrinterBridge {
  const MethodChannelPrinterBridge();

  static const _ch = MethodChannel('com.mysvcs.rad_mysvcs/receipt_printer');

  Future<T?> _call<T>(String method, [Map<String, Object?>? args, Duration? timeout]) async {
    try {
      final f = _ch.invokeMethod<T>(method, args);
      return timeout == null ? await f : await f.timeout(timeout);
    } on PlatformException catch (e) {
      throw PrinterFailure(e.code, e.message);
    } on MissingPluginException {
      throw const PrinterFailure('unsupported');
    } on TimeoutException {
      throw const PrinterFailure('timeout');
    }
  }

  @override
  Future<BtState> btState() async {
    final m = await _call<Map<Object?, Object?>>('btState', null, const Duration(seconds: 40)) ?? const {};
    return BtState(
      supported: m['supported'] == true,
      enabled: m['enabled'] == true,
      authorized: m['authorized'] != false,
    );
  }

  @override
  Future<List<BtDevice>> btPaired() async {
    final list = await _call<List<Object?>>('btPaired', null, const Duration(seconds: 15)) ?? const [];
    return [for (final e in list) if (e is Map) BtDevice.fromMap(e)];
  }

  @override
  Future<List<BtDevice>> btScan(Duration timeout) async {
    final list = await _call<List<Object?>>(
            'btScan', {'timeoutMs': timeout.inMilliseconds}, timeout + const Duration(seconds: 10)) ??
        const [];
    return [for (final e in list) if (e is Map) BtDevice.fromMap(e)];
  }

  @override
  Future<void> btConnect(String id, Duration timeout) =>
      _call<bool>('btConnect', {'id': id, 'timeoutMs': timeout.inMilliseconds}, timeout + const Duration(seconds: 5));

  @override
  Future<void> btWrite(Uint8List data) => _call<bool>('btWrite', {'data': data}, const Duration(seconds: 45));

  @override
  Future<Uint8List> btRead(Duration timeout, {int max = 64}) async =>
      await _call<Uint8List>(
          'btRead', {'timeoutMs': timeout.inMilliseconds, 'max': max}, timeout + const Duration(seconds: 5)) ??
      Uint8List(0);

  @override
  Future<void> btClose() => _call<bool>('btClose', null, const Duration(seconds: 10));

  @override
  Future<void> btSettings() => _call<bool>('btSettings');

  @override
  Future<BuiltinInfo> builtinInfo() async {
    final m = await _call<Map<Object?, Object?>>('builtinInfo', null, const Duration(seconds: 10)) ?? const {};
    return BuiltinInfo.fromMap(m);
  }

  @override
  Future<BuiltinAck> builtinPrint(List<Uint8List> chunks, Duration timeout) async {
    final m = await _call<Map<Object?, Object?>>(
            'builtinPrint', {'chunks': chunks, 'timeoutMs': timeout.inMilliseconds}, timeout + const Duration(seconds: 10)) ??
        const {};
    return BuiltinAck.fromMap(m);
  }
}

enum BtPermit { granted, denied, blocked }

/// إذن «الأجهزة المجاورة» (أندرويد ١٢+) يُطلب **لحظة الحاجة** (اختيار البلوتوث أو الطباعة) لا عند الإقلاع.
/// الآيفون يسأل بنفسه حين يبدأ التطبيق باستعمال البلوتوث، وحاله في [BtState.authorized].
abstract class BtPermissionGate {
  Future<BtPermit> ensure();
  Future<bool> openSettings();
}

class PlatformBtPermission implements BtPermissionGate {
  const PlatformBtPermission();

  @override
  Future<BtPermit> ensure() async {
    if (kIsWeb || !Platform.isAndroid) return BtPermit.granted;
    try {
      // أندرويد ١١ وأقدم: الإذن يُمنح بالتثبيت — المكتبة تعيده «مسموحاً».
      if (await Permission.bluetoothConnect.isGranted) return BtPermit.granted;
      final s = await Permission.bluetoothConnect.request();
      if (s.isGranted) return BtPermit.granted;
      if (s.isPermanentlyDenied || s.isRestricted) return BtPermit.blocked;
      return BtPermit.denied;
    } catch (_) {
      // الطبقة الأصليّة تفحص الإذن أيضاً وتقول «permission» إن غاب فعلاً.
      return BtPermit.granted;
    }
  }

  @override
  Future<bool> openSettings() => openAppSettings();
}
