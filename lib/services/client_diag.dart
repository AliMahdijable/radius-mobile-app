import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/api_client.dart';

/// تشخيصٌ بلا هويّة إلى الخادم (`POST /api/client-diag`) — لما لا يراه المستخدم ولا
/// يصل الخادم أصلاً.
///
/// 🐛 بلاغ ٢٠٢٦-١٠-١٦: «تكنو وهونر وبقيّة الهواتف: يطلع اختيار الحساب، تنقر عليه
/// يختفي وما يصير شي». Credential Manager يُرجع «إلغاء» بعد اختيار الحساب على أجهزةٍ
/// بعينها، فلا رسالة ولا نداء للخادم — والبصمة سليمة (١١ زبوناً دخلوا بـGoogle من
/// أندرويد المتجر). هنا يصلنا نوع الجهاز ونصّ الخطأ فيُعرف السبب بالدليل لا بالتخمين.
///
/// ما يُرسل: النوع/الرمز/نصّ الخطأ (≤٣٠٠ حرف) + الشركة/الطراز/أندرويد/خدمات Google/
/// نسخة التطبيق. لا بريد ولا معرّف (الخادم ينزع أيّ بريدٍ يتسرّب في النصّ). لا ينتظره
/// أحدٌ ولا يرمي أبداً.
class ClientDiag {
  ClientDiag._();

  static const _channel = MethodChannel('com.mysvcs.rad_mysvcs/app_info');
  static Map<String, Object?>? _device;

  static Future<Map<String, Object?>> _deviceInfo() async {
    final cached = _device;
    if (cached != null) return cached;
    final out = <String, Object?>{};
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final m = await _channel.invokeMapMethod<String, Object?>('getDeviceInfo');
        if (m != null) out.addAll(m);
      } else if (!kIsWeb && Platform.isIOS) {
        out['brand'] = 'apple';
        out['release'] = Platform.operatingSystemVersion;
      }
    } catch (_) {
      // قناةٌ غائبة (اختبار/منصّة أخرى) — يُرسل بلا نوع الجهاز.
    }
    try {
      final p = await PackageInfo.fromPlatform();
      out['app'] = '${p.version}+${p.buildNumber}';
    } catch (_) {}
    return _device = out;
  }

  /// يُرسَل بالخلفيّة — المستدعي لا ينتظر.
  static void report(String kind, {String? code, String? message}) {
    unawaited(_send(kind, code, message));
  }

  static Future<void> _send(String kind, String? code, String? message) async {
    try {
      final d = await _deviceInfo();
      final msg = message == null
          ? null
          : (message.length > 300 ? message.substring(0, 300) : message);
      await ApiClient.dio.post<void>(
        '/api/client-diag',
        data: {
          'kind': kind,
          if (code != null) 'code': code,
          if (msg != null) 'message': msg,
          for (final e in d.entries)
            if (e.value != null) e.key: e.value.toString(),
        },
        options: Options(
          sendTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('🟠 client-diag: $e');
    }
  }
}
