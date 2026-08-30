import 'dart:async';

import '../../api/mikrotik_binary_api.dart';
import '../../api/network_devices_api.dart';
import '../../api/ubnt_api.dart';
import '../../api/snmp_client.dart';
import '../../models/network_device.dart';
import 'detected_model.dart';

/// كشف طُرُز الأجهزة دفعةً واحدة.
///
/// ⚠️ **أخفّ نداء ممكن لكلّ علامة، لا لقطة كاملة**:
/// · Mikrotik: اتّصال + دخول + استعلام واحد `/system/resource/print`
///   ثمّ إغلاق فوريّ. `fetchStats` تُنفّذ 8-15 استعلاماً بينما الطراز
///   في أوّلها.
/// · UBNT: مصافحة SSH + `cat /etc/board.info` وحده. المهيمن على الزمن
///   المصافحة (0.8-3 ثوانٍ) لا الأمر (~50ms)، فتنفيذ أمر واحد بدل
///   عشرة يوفّر أغلب ما يمكن توفيره.
/// · SNMP (Mimosa · Ruijie): حزمة UDP واحدة لـsysDescr، بلا جلسة ولا
///   مصادقة — أرخص مسار في المشروع كلّه.
///
/// ⚠️ **لا يُربط بمؤقّت دوريّ إطلاقاً**. مؤقّت الشاشة كلّ 20 ثانية
/// يفتح TCP ويغلقه — بريء. ربط الكشف به يحوّله إلى جلسة مصادَقة لكلّ
/// جهاز كلّ 20 ثانية، وهو التصميم الوحيد الذي يضغط الأجهزة فعلاً.
/// يُشغَّل بطلب المستخدم، مرّةً.
class ModelDetector {
  ModelDetector._();

  /// سقوف التزامن بحسب كلفة العلامة على الجهاز.
  static const _capSsh = 2; // مصافحة SSH تستهلك معالج airOS الضعيف
  static const _capApi = 4;
  static const _capSnmp = 8; // حزمة UDP — بلا كلفة تُذكر

  /// يمرّ على الأجهزة المؤهَّلة ويحفظ ما يُبلّغ به كلّ جهاز.
  ///
  /// يُرجع الأجهزة المُحدَّثة. `onProgress` يُستدعى بعد كلّ جهاز.
  static Future<List<NetworkDevice>> run(
    List<NetworkDevice> devices, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCanceled,
  }) async {
    // مؤهَّل = يحتاج كشفاً + متّصل + له اعتماديّات (عدا SNMP) + علامة
    // مدعومة. الجهاز المفصول يُهدر مهلةً كاملة بلا فائدة.
    final targets = devices.where((d) {
      if (!DetectedModel.needsDetection(d)) return false;
      if (d.lastStatus != 'online') return false;
      return const ['mikrotik', 'ubnt', 'mimosa', 'roji', 'ruijie']
          .contains(d.brand.toLowerCase());
    }).toList();

    if (targets.isEmpty) {
      onProgress?.call(0, 0);
      return const [];
    }

    final updated = <NetworkDevice>[];
    var done = 0;
    final total = targets.length;

    Future<void> one(NetworkDevice d) async {
      if (isCanceled?.call() ?? false) return;
      try {
        final reported = await _detect(d);
        if (reported != null) {
          final u = await DetectedModel.save(d, reported);
          if (u != null) updated.add(u);
        }
      } catch (_) {
        // جهاز واحد يفشل لا يُسقط المرور.
      } finally {
        done++;
        onProgress?.call(done, total);
      }
    }

    // نُجمّع حسب العلامة فسقف كلٍّ مستقلّ — بطء UBNT لا يُعطّل SNMP.
    final byCap = <int, List<NetworkDevice>>{};
    for (final d in targets) {
      final b = d.brand.toLowerCase();
      final cap = b == 'ubnt' ? _capSsh : (b == 'mikrotik' ? _capApi : _capSnmp);
      byCap.putIfAbsent(cap, () => []).add(d);
    }
    await Future.wait(byCap.entries.map((e) async {
      for (var i = 0; i < e.value.length; i += e.key) {
        if (isCanceled?.call() ?? false) return;
        await Future.wait(e.value.skip(i).take(e.key).map(one));
      }
    }));
    return updated;
  }

  static Future<String?> _detect(NetworkDevice d) async {
    switch (d.brand.toLowerCase()) {
      case 'mikrotik':
        return _mikrotik(d);
      case 'ubnt':
        return _ubnt(d);
      default:
        return _snmp(d);
    }
  }

  static Future<String?> _mikrotik(NetworkDevice d) async {
    if (!d.hasCredentials) return null;
    final c = await NetworkDevicesApi.getCredentials(d.id);
    final user = (c['user'] ?? '').toString();
    final pass = (c['pass'] ?? '').toString();
    if (user.isEmpty) return null;
    final client = MikrotikBinaryClient(
      host: d.ip,
      port: d.apiPort ?? 8728,
      user: user,
      pass: pass,
      timeout: const Duration(seconds: 5),
    );
    try {
      await client.connect();
      await client.login();
      // `.proplist` يقصر الحمولة على العمود المطلوب وحده.
      final rows =
          await client.query(['/system/resource/print', '=.proplist=board-name']);
      if (rows.isEmpty) return null;
      final v = rows.first['board-name'];
      return (v == null || v.isEmpty) ? null : v;
    } finally {
      client.close();
    }
  }

  static Future<String?> _ubnt(NetworkDevice d) async {
    if (!d.hasCredentials) return null;
    final c = await NetworkDevicesApi.getCredentials(d.id);
    final user = (c['user'] ?? '').toString();
    final pass = (c['pass'] ?? '').toString();
    if (user.isEmpty) return null;
    final sess = await UbntTrafficSession.open(
      ip: d.ip,
      port: d.apiPort ?? 22,
      user: user,
      pass: pass,
      timeout: const Duration(seconds: 8),
    );
    if (sess == null) return null;
    try {
      return await sess.readBoardName();
    } finally {
      sess.close();
    }
  }

  static Future<String?> _snmp(NetworkDevice d) async {
    final snmp = SnmpV2c(
      host: d.ip,
      community: 'public',
      timeout: const Duration(seconds: 4),
    );
    try {
      final r = await snmp.get(['1.3.6.1.2.1.1.1.0']);
      final descr = r.isEmpty ? null : r.first.asString;
      return _modelFromSysDescr(descr);
    } catch (_) {
      return null;
    }
  }

  /// يستخرج طرازاً معقولاً من `sysDescr` الحرّ.
  ///
  /// ⚠️ الحقل نصّ تسويقي لا معرّف: «Mimosa B5c ...» أو «Ruijie ...».
  /// نأخذ أوّل كلمة تحوي رقماً وحرفاً معاً — وإن لم توجد نُعيد null
  /// بدل تخمين، فالطراز الخطأ يُظهر صورة خطأ.
  static String? _modelFromSysDescr(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    for (final w in s.split(RegExp(r'[\s,;()]+'))) {
      final t = w.trim();
      if (t.length < 2 || t.length > 24) continue;
      final hasDigit = RegExp(r'[0-9]').hasMatch(t);
      final hasAlpha = RegExp(r'[A-Za-z]').hasMatch(t);
      if (hasDigit && hasAlpha) return t;
    }
    return null;
  }
}
