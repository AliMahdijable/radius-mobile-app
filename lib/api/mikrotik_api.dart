import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../core/util/dev_log.dart';

import 'mikrotik_binary_api.dart';
import 'mikrotik_snmp.dart';
import 'routeros_channel.dart';

/// Mikrotik high-level API — يستعمل Binary API (port 8728 افتراضي).
/// يجلب system/resource + interfaces + ppp active بالتوازي.
class MikrotikApi {
  /// جلب صورة كاملة عن حالة الراوتر عبر Binary API.
  /// **يعمل مع RouterOS 6.43+** (login sentence بسيط).
  /// **Progressive fetch**:
  /// - `onPartialReady` (اختياري): يُستدعى بعد Tier 1 (system + interfaces
  ///   + health + ethernet monitor) — ~400-600ms. UI يعرض CPU/RAM/interfaces فوراً.
  /// - القيمة النهائيّة (returned Future): بعد Tier 2 (wireless + registration
  ///   + hostname enrichment) — ~1.5-3s حسب حجم الجدول.
  ///
  /// **الفائدة**: بدل انتظار كل شي ~3s ثمّ عرض دفعة واحدة، الآن:
  ///   t=0: skeleton
  ///   t=500ms: CPU/RAM/interfaces (partial)
  ///   t=2s: wireless + clients (complete)

  /// الاختبارات واللقطات: يُرجع إحصاءاتٍ جاهزة بدل جلسة RouterOS حقيقيّة (لا جهاز في بيئة الاختبار).
  @visibleForTesting
  static Future<MikrotikStats> Function()? debugFetch;

  static Future<MikrotikStats> fetchStats({
    required String ip,
    required int port, // 8728 (api) أو 8729 (api-ssl)
    required String user,
    required String pass,
    Duration timeout = const Duration(seconds: 6),
    void Function(MikrotikStats partial)? onPartialReady,

    /// يقف عند الطبقة الأولى: موارد النظام والصحّة والمنافذ.
    ///
    /// 🐛 بلاغ ٢٠٢٦-٠٩-٠٢: «جهاز واحد فقط ظهر معلومات، البقيّة تكتب
    /// يقيس». والسبب أنّ البطاقة المطويّة تحتاج **ثلاثة أرقام** (معالج
    /// · ذاكرة · حرارة) وتدفع ثمن الجلسة كاملةً: جدول اللاسلكيّ، ثمّ
    /// جدول التسجيل، ثمّ صيغةٌ ثانية، ثمّ جلسة SSH — نحو خمس عشرة
    /// ثانية لجهازٍ تُقرأ منه ثلاثة أرقام تصل في أقلّ من ثانيتين.
    ///
    /// وبستّ خانات فقط، كلّ جلسةٍ طويلة تحجب خمس بطاقات.
    ///
    /// ⚠️ ولا يُستعمل حيث تُعرض التفاصيل: اللوحة المفردة والبطاقة
    /// المفتوحة تحتاجان العملاء والمنافذ فعلاً.
    bool vitalsOnly = false,
  }) async {
    final fake = debugFetch;
    if (fake != null) {
      final s = await fake();
      onPartialReady?.call(s);
      return s;
    }
    final ch = BinaryRouterOsChannel(
        MikrotikBinaryClient(host: ip, port: port, user: user, pass: pass, timeout: timeout));
    try {
      await ch.open();
      return await _collect(ch, ip: ip, user: user, pass: pass, vitalsOnly: vitalsOnly, onPartialReady: onPartialReady);
    } on MikrotikBinaryException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ MikrotikApi: $e');
      throw MikrotikException(_translateSocketError(e));
    } finally {
      await ch.close();
    }
  }

  /// الطريق الذي نجح لكلّ جهاز (عنوان · بروتوكول · منفذ) — فلا يُدفع ثمن منفذٍ مقفول في كلّ نبضة. بعد ٢٠ دقيقة
  /// يعود الترتيب الأصليّ: قد يُفتح الـAPI لاحقاً وهو الأسرع.
  static final Map<String, ({String route, DateTime at})> _routeMemo = {};
  static const _routeTtl = Duration(minutes: 20);

  @visibleForTesting
  static void resetRoutesForTest() => _routeMemo.clear();

  /// فاتح القنوات وفاحص المنافذ — يُستبدلان في الاختبار.
  @visibleForTesting
  static RouterOsChannel Function(String route, String ip, int port, String user, String pass, Duration timeout)
      channelFactory = _defaultChannel;
  @visibleForTesting
  static Future<bool> Function(String ip, int port) portProbe = _probePort;

  static RouterOsChannel _defaultChannel(
          String route, String ip, int port, String user, String pass, Duration timeout) =>
      switch (route) {
        'rest-https' => RestRouterOsChannel(host: ip, port: port, https: true, user: user, pass: pass, timeout: timeout),
        'rest-http' => RestRouterOsChannel(host: ip, port: port, https: false, user: user, pass: pass, timeout: timeout),
        'ssh' => SshRouterOsChannel(host: ip, port: port, user: user, pass: pass, timeout: timeout),
        _ => BinaryRouterOsChannel(
            MikrotikBinaryClient(host: ip, port: port, user: user, pass: pass, timeout: timeout)),
      };

  static Future<bool> _probePort(String ip, int port) async {
    try {
      final s = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 2500));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ترتيب الطرق. منفذٌ 443/80 مسجَّلٌ للـAPI يعني الويب؛ وما سواه منفذ الـAPI الثنائيّ (جهازٌ نقل الـAPI إلى 8080).
  @visibleForTesting
  static List<({String route, int port})> routeOrder({String? protocol, int? apiPort}) {
    const restS = (route: 'rest-https', port: 443);
    const restP = (route: 'rest-http', port: 80);
    if (protocol == 'ssh') {
      return [(route: 'ssh', port: apiPort ?? 22), (route: 'api', port: 8728), restS, restP];
    }
    return switch (apiPort) {
      443 => [restS, (route: 'api', port: 8728), restP, (route: 'ssh', port: 22)],
      80 => [restP, (route: 'api', port: 8728), restS, (route: 'ssh', port: 22)],
      _ => [(route: 'api', port: apiPort ?? 8728), restS, restP, (route: 'ssh', port: 22)],
    };
  }

  /// قراءة جهازٍ بكلّ الطرق — ما تستعمله اللوحة والنظرة العامّة.
  ///
  /// - `snmp` ⇒ SNMP وحده بالـcommunity ([MikrotikSnmp]).
  /// - `ssh` ⇒ SSH (منفذه) ثمّ الـAPI ثمّ الويب.
  /// - `api`/فارغ ⇒ الـAPI ثمّ الويب (HTTPS ثمّ HTTP) ثمّ SSH.
  ///
  /// يُنتقل للتالي حين **لا يوصَل** للطريق (مرفوض · مهلة · لا REST في RouterOS 6) — لا حين تُرفض كلمة المرور. ومنافذ
  /// البدائل تُفحص معاً (٢٫٥ ث) فلا ينتظر جهازٌ مطفأ مهلةَ كلّ طريقٍ على حدة.
  static Future<MikrotikStats> fetchStatsFor({
    required String ip,
    String? protocol,
    int? apiPort,
    required Map<String, dynamic> creds,
    Duration timeout = const Duration(seconds: 6),
    void Function(MikrotikStats partial)? onPartialReady,
    bool vitalsOnly = false,
  }) async {
    final fake = debugFetch;
    if (fake != null) {
      final s = await fake();
      onPartialReady?.call(s);
      return s;
    }
    if (protocol == 'snmp') {
      final community = (creds['community'] ?? creds['pass'] ?? '').toString();
      if (community.isEmpty) throw MikrotikException('لم تُحفظ الـcommunity لهذا الجهاز');
      return MikrotikSnmp.fetch(
          host: ip, port: apiPort ?? 161, community: community, vitalsOnly: vitalsOnly, onPartialReady: onPartialReady);
    }
    final user = (creds['user'] ?? '').toString();
    final pass = (creds['pass'] ?? '').toString();
    if (user.isEmpty) throw MikrotikException('لم يتم إعداد بيانات الدخول للجهاز');

    return _routed(
      ip: ip,
      protocol: protocol,
      apiPort: apiPort,
      user: user,
      pass: pass,
      timeout: timeout,
      body: (ch) => _collect(ch, ip: ip, user: user, pass: pass, vitalsOnly: vitalsOnly, onPartialReady: onPartialReady),
    );
  }

  /// إعادة التشغيل بطريق القراءة نفسه (API · الويب · SSH). SNMP قراءةٌ فقط.
  ///
  /// الجهاز يقطع الاتّصال فور تنفيذ الأمر — انقطاعٌ أو مهلةٌ بعد الإرسال نجاحٌ (كما في [rebootDevice]).
  static Future<void> rebootFor({
    required String ip,
    String? protocol,
    int? apiPort,
    required Map<String, dynamic> creds,
  }) async {
    if (protocol == 'snmp') throw MikrotikException('إعادة التشغيل تحتاج API أو SSH — SNMP للقراءة فقط');
    final user = (creds['user'] ?? '').toString();
    final pass = (creds['pass'] ?? '').toString();
    if (user.isEmpty) throw MikrotikException('لم يتم إعداد بيانات الدخول للجهاز');
    await _routed<void>(
      ip: ip,
      protocol: protocol,
      apiPort: apiPort,
      user: user,
      pass: pass,
      timeout: const Duration(seconds: 6),
      body: (ch) async {
        try {
          await ch.query(['/system/reboot']);
        } catch (e) {
          final m = e.toString().toLowerCase();
          if (e is SocketException ||
              e is TimeoutException ||
              m.contains('closed') ||
              m.contains('timeout') ||
              m.contains('reset') ||
              m.contains('reboot')) {
            return;
          }
          rethrow;
        }
      },
    );
  }

  /// اسم اللوحة وحده (كشف الطراز) — بالطرق نفسها، وبعمودٍ واحد.
  static Future<String?> boardNameFor({
    required String ip,
    String? protocol,
    int? apiPort,
    required Map<String, dynamic> creds,
  }) async {
    if (protocol == 'snmp') {
      final community = (creds['community'] ?? creds['pass'] ?? '').toString();
      if (community.isEmpty) return null;
      final s = await MikrotikSnmp.fetch(host: ip, port: apiPort ?? 161, community: community, vitalsOnly: true);
      return s.boardName.isEmpty ? null : s.boardName;
    }
    final user = (creds['user'] ?? '').toString();
    final pass = (creds['pass'] ?? '').toString();
    if (user.isEmpty) return null;
    return _routed(
      ip: ip,
      protocol: protocol,
      apiPort: apiPort,
      user: user,
      pass: pass,
      timeout: const Duration(seconds: 5),
      body: (ch) async {
        // `.proplist` يقصر الحمولة على العمود المطلوب وحده.
        final rows = await ch.query(['/system/resource/print', '=.proplist=board-name']);
        final v = rows.isEmpty ? null : rows.first['board-name'];
        return (v == null || v.isEmpty) ? null : v;
      },
    );
  }

  static Future<T> _routed<T>({
    required String ip,
    String? protocol,
    int? apiPort,
    required String user,
    required String pass,
    required Duration timeout,
    required Future<T> Function(RouterOsChannel ch) body,
  }) async {
    final routes = routeOrder(protocol: protocol, apiPort: apiPort);
    final key = '$ip|${protocol ?? ''}|${apiPort ?? ''}';
    final memo = _routeMemo[key];
    if (memo != null && DateTime.now().difference(memo.at) < _routeTtl) {
      final i = routes.indexWhere((r) => r.route == memo.route);
      if (i > 0) routes.insert(0, routes.removeAt(i));
    }
    Future<T> via(({String route, int port}) r) async {
      final v = await _viaRoute(r, ip, user, pass, timeout, body);
      _routeMemo[key] = (route: r.route, at: DateTime.now());
      return v;
    }

    Object cause;
    try {
      return await via(routes.first);
    } on _RouteUnavailable catch (e) {
      cause = e.cause;
    }
    final rest = routes.skip(1).toList();
    final open = await Future.wait(rest.map((r) => portProbe(ip, r.port)));
    for (var j = 0; j < rest.length; j++) {
      if (!open[j]) continue;
      try {
        return await via(rest[j]);
      } on _RouteUnavailable {/* التالي */}
    }
    _routeMemo.remove(key);
    // المضيف حيٌّ ومنافذه مقفولة ⇒ قل أيّها يُفتح؛ لا ردّ إطلاقاً ⇒ رسالة الشبكة وحدها.
    final refused = cause.toString().contains('refused') || open.any((o) => o);
    throw MikrotikException(refused
        ? 'تعذّر الوصول عبر API والويب وSSH — فعّل إحداها على الجهاز (IP ← Services) أو اختر SNMP'
        : _translateSocketError(cause));
  }

  static Future<T> _viaRoute<T>(
    ({String route, int port}) r,
    String ip,
    String user,
    String pass,
    Duration timeout,
    Future<T> Function(RouterOsChannel ch) body,
  ) async {
    final ch = channelFactory(r.route, ip, r.port, user, pass, timeout);
    try {
      try {
        await ch.open();
      } on MikrotikBinaryException catch (e) {
        // كلمة مرورٍ خاطئة لا يُصلحها طريقٌ آخر بالحساب نفسه. أمّا «not enough permissions» فسياسة مجموعةٍ تمنع
        // هذا الطريق وحده (api مثلاً) وقد تسمح بغيره.
        if (e.code == 'auth' && !e.message.contains('permission')) rethrow;
        throw _RouteUnavailable(e);
      } catch (e) {
        throw _RouteUnavailable(e);
      }
      return await body(ch);
    } on _RouteUnavailable {
      rethrow;
    } on MikrotikBinaryException {
      rethrow;
    } catch (e) {
      throw MikrotikException(_translateSocketError(e));
    } finally {
      await ch.close();
    }
  }

  /// بقيّة الجلسة بعد الدخول — مشتركةٌ بين الـAPI والويب وSSH (كلّها تُرجع صفوف الـAPI نفسها، راجع
  /// [RouterOsChannel]). جلسة SSH الاحتياطيّة لجدول التسجيل للـAPI الثنائيّ وحده: علّتها فيه (6.49).
  static Future<MikrotikStats> _collect(
    RouterOsChannel ch, {
    required String ip,
    required String user,
    required String pass,
    required bool vitalsOnly,
    void Function(MikrotikStats partial)? onPartialReady,
  }) async {
    // ═══════ TIER 1 (fast — عرض جزئي) ═══════
    // system/resource + interface/print + health + ethernet/monitor
    // هذي الأساسيّات: CPU/RAM/uptime/temp + قائمة الـinterfaces
    final resourceRows = await ch.query(['/system/resource/print']);
    final interfaceRows = await ch.query(['/interface/print']);
    List<Map<String, String>> healthRows = const [];
    try {
      healthRows = await ch.query(['/system/health/print']);
      // Debug: طباعة كل صفوف health لنعرف بأي أسماء fields يستعمل الراوتر
      // (CCR2116 مثلاً قد يستعمل psu1-voltage/psu2-voltage بدل voltage)
      if (kDebugMode && healthRows.isNotEmpty) {
        DevLog.trace(
            () => '🔵 [mikrotik health] rows count=${healthRows.length}');
        for (final r in healthRows) {
          debugPrint('   $r');
        }
      }
    } catch (_) {}
    List<Map<String, String>> pppRows = const [];
    try {
      pppRows = await ch.query(['/ppp/active/print']);
    } catch (_) {}

    // اجلب سرعة الـport الفعليّة (Tier 1 — قبل الـpartial callback)
    final Map<String, Map<String, String>> ethMonitorByName = {};
    final etherNames = interfaceRows
        .where((r) {
          final t = r['type'] ?? '';
          final n = r['name'] ?? '';
          return n.isNotEmpty && (t == 'ether' || t == 'sfp');
        })
        .map((r) => r['name']!)
        .toList();
    if (etherNames.isNotEmpty) {
      try {
        // request واحد مع كل الـinterfaces — RouterOS يرجع !re per interface
        final monResult = await ch.query([
          '/interface/ethernet/monitor',
          '=numbers=${etherNames.join(",")}',
          '=once=',
        ]);
        // كل row يحمل اسم الـinterface؛ لو ما موجود نستعمل الترتيب.
        for (int i = 0; i < monResult.length; i++) {
          final r = monResult[i];
          final key =
              r['name'] ?? (i < etherNames.length ? etherNames[i] : '');
          if (key.isNotEmpty) ethMonitorByName[key] = r;
        }
      } catch (_) {
        // fallback: لو RouterOS الإصدار ما يقبل قائمة، رجعنا للـloop
        // (سابقاً كان كل جهاز على حدة، بطيء لكن يشتغل)
        for (final name in etherNames) {
          try {
            final r = await ch.query([
              '/interface/ethernet/monitor',
              '=numbers=$name',
              '=once=',
            ]);
            if (r.isNotEmpty) ethMonitorByName[name] = r.first;
          } catch (_) {}
        }
      }
    }

    // أعضاء البريدجات — للّوحة المفصّلة وحدها (قسم البريدجات): جدولٌ صغير بطلبٍ واحد،
    // ولا يُطلب إلّا إن وُجد بريدج، ولا في الوضع الخفيف (بطاقات القائمة لا تعرض الأعضاء).
    final bridgePorts = <String, List<String>>{};
    if (!vitalsOnly && interfaceRows.any((r) => r['type'] == 'bridge')) {
      try {
        final rows = await ch.query([
          '/interface/bridge/port/print',
          '=.proplist=interface,bridge,disabled',
        ]);
        bridgePorts.addAll(parseBridgePorts(rows));
      } catch (_) {
        // صلاحيّة ناقصة أو إصدارٌ قديم — يبقى القسم بلا أعضاء، والترافيك يُعرض كما هو.
      }
    }

    if (resourceRows.isEmpty) {
      throw MikrotikBinaryException(
          'لم يرجع الراوتر معلومات system/resource');
    }
    final resource = resourceRows.first;

    // Health parsing — RouterOS v7 يرجع list of {name, value, type}
    // مثال CCR2116:
    //   cpu-temperature: 38 C
    //   sfp-temperature: 27 C
    //   switch-temperature: 29 C
    //   board-temperature1: 29 C
    //   fan1-speed: 4185 RPM (× 4)
    //   psu1-state: ok / psu2-state: fail (dual PSU)
    // مثال CCR1009:
    //   voltage: 24V (single value، بلا فانات)
    int? healthTemp;
    double? healthVoltage;
    double? healthCurrent;
    double? healthWatts;
    final fans = <MikrotikHealthItem>[];
    final psus = <MikrotikHealthItem>[];
    final extraTemps = <MikrotikHealthItem>[];

    for (final h in healthRows) {
      final name = (h['name'] ?? '').toLowerCase();
      final valueStr = h['value'] ?? '';
      if (name.isEmpty) continue;

      if (name.contains('temp')) {
        // كل الحرارات → extraTemps، الأولى (أو cpu) → healthTemp
        final v =
            double.tryParse(valueStr.replaceAll(RegExp(r'[^\d.-]'), ''));
        if (v != null) {
          extraTemps.add(MikrotikHealthItem(
            name: name,
            valueStr: valueStr,
            intValue: v.round(),
          ));
          if (healthTemp == null || name.contains('cpu')) {
            healthTemp = v.round();
          }
        }
      } else if (name.contains('voltage') || name == 'v') {
        // ٢٧ أكتوبر (المالك: «فولتيه بهواي اجهزه مثل هذا مايكروتيك ميقراها»): netPower 16P يُرجع psu1-voltage 25.3
        // وpsu2-voltage 0 (مدخلٌ غير موصول) — وكان الأخير يغلب فتظهر «0.0 V غير طبيعيّة». الفولتيّة = المزوّد العامل
        // (الأعلى)، وصفرٌ وحده = لا قراءة.
        final v =
            double.tryParse(valueStr.replaceAll(RegExp(r'[^\d.-]'), ''));
        if (v != null && v > 0 && v > (healthVoltage ?? 0)) healthVoltage = v;
      } else if (name.contains('current')) {
        final a = double.tryParse(valueStr.replaceAll(RegExp(r'[^\d.-]'), ''));
        if (a != null && a > 0) healthCurrent = (healthCurrent ?? 0) + a;
      } else if (name.contains('consumption')) {
        // poe-out-consumption (W) — ما تسحبه أجهزة الـPoE من السويج.
        final w = double.tryParse(valueStr.replaceAll(RegExp(r'[^\d.-]'), ''));
        if (w != null && w >= 0) healthWatts = (healthWatts ?? 0) + w;
      } else if (name.startsWith('fan') && name.contains('speed')) {
        // fan1-speed, fan2-speed, ...
        final rpm = int.tryParse(valueStr.replaceAll(RegExp(r'[^\d]'), ''));
        if (rpm != null && rpm > 0) {
          fans.add(MikrotikHealthItem(
            name: name.replaceAll('-speed', ''),
            valueStr: '$rpm RPM',
            intValue: rpm,
          ));
        }
      } else if (name.startsWith('psu') && name.endsWith('-state')) {
        // psu1-state, psu2-state
        final v = valueStr.toLowerCase().trim();
        psus.add(MikrotikHealthItem(
          name: name.replaceAll('-state', ''),
          valueStr: valueStr,
          isOk: v == 'ok',
        ));
      }
    }
    // fallback: بعض الإصدارات ترجع flat في نفس row واحد بأسماء متعدّدة
    // (temperature, board-temperature, cpu-temperature، voltage,
    // input-voltage, board-voltage, psu-voltage، إلخ)
    if (healthRows.length == 1) {
      final r = healthRows.first;
      healthTemp ??= _asInt(
        (r['temperature'] ?? r['board-temperature'] ?? r['cpu-temperature'])
            ?.replaceAll(RegExp(r'[^\d-]'), ''),
      );
      for (final vKey in const [
        'voltage',
        'input-voltage',
        'board-voltage',
        'psu-voltage',
        'psu1-voltage',
        'power-supply-1-voltage',
      ]) {
        if (healthVoltage == null && r[vKey] != null) {
          final v = double.tryParse(r[vKey]!.replaceAll(RegExp(r'[^\d.-]'), ''));
          if (v != null && v > 0) {
            healthVoltage = v;
            break;
          }
        }
      }
    }
    // fallback نهائي: system/resource قد يحوي cpu-temperature
    healthTemp ??= _asInt(resource['cpu-temperature']);
    if (healthTemp == 0) healthTemp = null;

    // ═══ بناء Tier 1 partial (بدون wireless بعد) ═══
    final tier1 = MikrotikStats(
      cpuLoad: _asInt(resource['cpu-load']),
      memUsedPercent: _calcMemUsed(resource),
      memTotalBytes: _asInt(resource['total-memory']),
      memFreeBytes: _asInt(resource['free-memory']),
      uptime: resource['uptime'] ?? '',
      version: resource['version'] ?? '',
      boardName: resource['board-name'] ?? '',
      architectureName: resource['architecture-name'] ?? '',
      cpuCount: _asInt(resource['cpu-count']),
      cpuFrequencyMhz: _asInt(resource['cpu-frequency']),
      temperature: healthTemp,
      voltage: healthVoltage,
      currentAmps: healthCurrent,
      powerWatts: healthWatts,
      fans: fans,
      psus: psus,
      extraTemps: extraTemps,
      interfaces: interfaceRows.map((row) {
        final name = row['name'] ?? '';
        final monitor = ethMonitorByName[name];
        return MikrotikInterface.fromApiMap(row, monitor: monitor);
      }).toList(),
      pppActiveCount: pppRows.length,
      wirelessInterfaces: const [], // Tier 2 يملؤها
      wirelessClients: const [],
      bridgePorts: bridgePorts,
      via: ch.via,
    );

    // ⚡ يُطلق callback الآن — UI يعرض CPU/RAM/interfaces فوراً
    if (onPartialReady != null) {
      try {
        onPartialReady(tier1);
      } catch (_) {}
    }

    // في الوضع الخفيف نكتفي بالطبقة الأولى — راجع [vitalsOnly].
    if (vitalsOnly) return tier1;

    // ═══════ TIER 2 (تفاصيل — wireless + enrichment) ═══════
    // 2026-08-18: أجهزة Mikrotik تستعمل حزم wireless مختلفة حسب النوع:
    //   - `/interface/wireless/print` — airMax/802.11 القديم (RouterOS 6)
    //   - `/interface/w60g/print` — 60 GHz (LHG 60G, wAP 60G, cAP 60G)
    //   - `/interface/wifi/print` — RouterOS 7 wifi (WiFi 6 / AX)
    //   - `/interface/wifiwave2/print` — legacy wifiwave2 (7.1-7.6)
    // نجرّب الأربعة، ونجمع النتائج (LHG 60G مثلاً لا يستجيب للأوّل بل للثاني).
    final List<Map<String, String>> wirelessRows = [];
    final List<Map<String, String>> wirelessClients = [];
    final w60gLinks = <MikrotikW60gLink>[];
    try {
      final rows = await ch.query(['/interface/wireless/print']);
      wirelessRows.addAll(rows);
    } catch (_) {/* عادي على CCR + LHG 60G */}
    try {
      final rows = await ch.query(['/interface/w60g/print']);
      // sanitize: نطابق بنية wireless (ssid/mode/frequency)
      for (final w in rows) {
        wirelessRows.add({
          'name': w['name'] ?? '',
          'ssid': w['ssid'] ?? '',
          'mode': (w['mode'] ?? 'bridge').toString(),
          'band': '60ghz',
          'frequency': w['frequency'] ?? '',
          'channel-width':
              w['channel-width']?.replaceAll(RegExp(r'[^0-9]'), '') ?? '2160',
          'tx-power': w['tx-power'] ?? '',
          'disabled': w['disabled'] ?? 'false',
          'running': w['running'] ?? 'false',
        });
      }
    } catch (_) {/* عادي على الأجهزة الي لا تدعم 60GHz */}
    try {
      final rows = await ch.query(['/interface/wifi/print']);
      for (final w in rows) {
        wirelessRows.add({
          'name': w['name'] ?? '',
          'ssid': (w['configuration'] ?? w['ssid'] ?? '').toString(),
          'mode': (w['mode'] ?? 'ap').toString(),
          'band': (w['band'] ?? '').toString(),
          'frequency': w['frequency'] ?? '',
          'channel-width':
              w['channel-width']?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
          'tx-power': w['tx-power'] ?? '',
          'disabled': w['disabled'] ?? 'false',
          'running': w['running'] ?? 'false',
        });
      }
    } catch (_) {/* عادي على RouterOS 6 */}
    // 60 GHz — ٢٧ أكتوبر (المالك: «اصدارات اجهزه لنكات مال ٦ جي هم ماكو بالمايكروتيك»): إشارة الوصلة وسرعتها
    // ومسافتها في `/interface/w60g/monitor` وحده. جدول `/interface/w60g/station` واجهاتٌ بماك الطرف الآخر بلا
    // إشارةٍ ولا سرعة — كان يُعرض عملاءً بـ«0 dBm» — فصار عدّاً للمحطّات فقط، ولا يدخل جدول العملاء.
    final w60gRows = wirelessRows.where((w) => w['band'] == '60ghz').toList();
    if (w60gRows.isNotEmpty) {
      final stationsOf = <String, int>{};
      try {
        final st = await ch.query(['/interface/w60g/station/print']).timeout(const Duration(seconds: 6));
        for (final r in st) {
          if ((r['running'] ?? 'true').toLowerCase() != 'true') continue;
          final parent = r['parent'] ?? '';
          stationsOf[parent] = (stationsOf[parent] ?? 0) + 1;
        }
      } catch (_) {/* إصدارٌ بلا جدول محطّات — الوصلة من monitor تكفي */}
      for (final w in w60gRows) {
        final name = w['name'] ?? '';
        if (name.isEmpty || (w['disabled'] ?? '').toLowerCase() == 'true') continue;
        try {
          final r = await ch.query(['/interface/w60g/monitor', '=numbers=$name', '=once='])
              .timeout(const Duration(seconds: 6));
          if (r.isEmpty) continue;
          final link = MikrotikW60gLink.fromMonitor(name, r.first, stations: stationsOf[name] ?? 0);
          w60gLinks.add(link);
          // التردّد في الإعداد قد يكون «auto» — والفعليّ من monitor.
          if (link.frequency != null && _iOrZero(w['frequency']) == 0) w['frequency'] = '${link.frequency}';
        } catch (_) {/* monitor مرفوض لهذا المستخدم — تبقى الواجهة بلا وصلة لا بأرقامٍ مخترعة */}
      }
    }
    // Clients — جدول التسجيل لراديوات wireless/wifi وحدها (Cube 60Pro ac فيه راديو 5 GHz احتياطيّ بجانب الـ60).
    // كان وجود واجهة 60 GHz يُسقط جدول الـ5 GHz، وجهاز 60 GHz وحده يطلق جلسة SSH بلا طائل كلّ قراءة.
    final hasRadio = wirelessRows.any((w) => w['band'] != '60ghz');
    // legacy wireless first (RouterOS 6 + 7-with-wireless-package).
    // wifi7 يستعمل نفس ROS-7 mikrotik: reg-table تحته
    // `/interface/wifi/registration-table/print`.
    const pickedPath = '/interface/wireless/registration-table/print';
    String? failureMsg;
    // Debug logging مفعّل دائماً لـreg-table لأن هذي الاستعلامات
    // تفشل بصمت أحياناً على RouterOS 6.4x. Log يُطبع فقط في debug build.
    if (hasRadio) {
      try {
        final regs = await ch.query([pickedPath],
            debugLog: true).timeout(const Duration(seconds: 12));
        wirelessClients.addAll(regs);
        if (kDebugMode) {
          debugPrint('🟢 [mikrotik] $pickedPath → ${regs.length} clients');
        }
      } on TimeoutException {
        failureMsg = 'timeout';
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('no such command') || msg.contains('no such item')) {
          // Package غير مثبّت → جرّب wifi (RouterOS 7)
          try {
            final regs = await ch.query(
                ['/interface/wifi/registration-table/print'],
                debugLog: true).timeout(const Duration(seconds: 8));
            wirelessClients.addAll(regs);
            if (kDebugMode) {
              debugPrint(
                  '🟢 [mikrotik] wifi reg-table → ${regs.length} clients');
            }
          } catch (e2) {
            final m2 = e2.toString();
            if (!m2.contains('no such command') &&
                !m2.contains('no such item')) {
              failureMsg = m2.length > 80 ? m2.substring(0, 80) : m2;
            }
          }
        } else {
          failureMsg = msg.length > 80 ? msg.substring(0, 80) : msg;
        }
      }
    }
    // ⚠️ الصيغة متعدّدة الكلمات حُذفت ٢٠٢٦-٠٩-٠٢.
    //
    // قاعدة المستخدم: «خلّ ميكروتك ثابت API، والأولويّة له، وUBNT
    // SSH». وهذه المحاولة لم تنجح **مرّةً واحدة** في سجلٍّ كامل —
    // ترد `!trap` دائماً. فهي جولة شبكةٍ مهدورة قبل كلّ سقوطٍ إلى
    // SSH، ومسارٌ ثالث يُعقّد الشيفرة بلا مقابل.
    //
    // بقي مساران لا ثلاثة: الـAPI الثنائيّ، ثمّ SSH عند فشله.
    // 2026-08-20: RouterOS 6.49.x + Binary API bug — reg-table يرجع !done
    // بـ 0 rows حتى لو Winbox يعرض عملاء. مؤكّد على BaseBox 5 / 6.49.13
    // (user admin/full، الأمر ينجح بلا !trap لكن سطر واحد !done فقط).
    // الحلّ الوحيد المضمون: SSH fallback — نفس interface الي يستعمله Winbox
    // terminal، بلا الـAPI quirks.
    if (wirelessClients.isEmpty && failureMsg == null && hasRadio && ch.via == 'API') {
      if (kDebugMode) {
        debugPrint('🔁 [mikrotik] Binary API رجع 0 — جرّب SSH fallback');
      }
      try {
        final sshClients = await _fetchClientsViaSsh(ip, user, pass);
        if (sshClients.isNotEmpty) {
          wirelessClients.addAll(sshClients);
          if (kDebugMode) {
            debugPrint(
                '🟢 [mikrotik] SSH fallback → ${sshClients.length} clients');
          }
        } else {
          if (kDebugMode) {
            debugPrint(
                'ℹ️ [mikrotik] SSH fallback رجع 0 كذلك — الـAP فعلاً بلا عملاء');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          final es = e.toString();
          debugPrint(
              '⚠️ [mikrotik] SSH fallback فشل: ${es.length > 80 ? es.substring(0, 80) : es}');
        }
      }
    }
    // CAPsMAN: نضيفه فقط لو الجهاز يبدو manager (اسم "capsman" في
    // interfaces، أو مسار /caps-man موجود مع wireless section null).
    // بدون هذا: كل جهاز عادي يهدر 6s على /caps-man غير الموجود.
    final looksLikeCapsMan = interfaceRows
        .any((i) => (i['name'] ?? '').toLowerCase().contains('capsman'));
    if (looksLikeCapsMan) {
      try {
        final regs = await ch
            .query(['/caps-man/registration-table/print']).timeout(
                const Duration(seconds: 8));
        wirelessClients.addAll(regs);
        if (kDebugMode) {
          debugPrint(
              '🟢 [mikrotik] caps-man reg-table → ${regs.length} clients');
        }
      } catch (_) {}
    }
    if (wirelessClients.isEmpty && hasRadio && kDebugMode) {
      if (failureMsg == 'timeout') {
        debugPrint(
            '⚠️ [mikrotik] reg-table timeout — الجهاز بطيء أو overload. زد timeout عبر MikrotikApi.fetchStats(timeout: ...).');
      } else if (failureMsg != null) {
        debugPrint('⚠️ [mikrotik] reg-table فشل: $failureMsg');
      } else {
        debugPrint(
            'ℹ️ [mikrotik] reg-table رجع فارغ عبر $pickedPath — الـAP بلا عملاء متصلين حالياً.');
      }
    }

    // hostname enrichment: DHCP lease + access-list + ARP
    final Map<String, ({String? hostname, String? ip})> dhcpMap = {};
    try {
      final leases = await ch.query(['/ip/dhcp-server/lease/print']);
      for (final l in leases) {
        final mac = (l['mac-address'] ?? '').toUpperCase();
        if (mac.isEmpty) continue;
        dhcpMap[mac] = (
          hostname: _nonEmpty(l['host-name']) ?? _nonEmpty(l['comment']),
          ip: _nonEmpty(l['active-address']) ?? _nonEmpty(l['address']),
        );
      }
    } catch (_) {}
    try {
      final acl =
          await ch.query(['/interface/wireless/access-list/print']);
      for (final a in acl) {
        final mac = (a['mac-address'] ?? '').toUpperCase();
        final comment = _nonEmpty(a['comment']);
        if (mac.isEmpty || comment == null) continue;
        final existing = dhcpMap[mac];
        dhcpMap[mac] = (
          hostname: existing?.hostname ?? comment,
          ip: existing?.ip,
        );
      }
    } catch (_) {}
    try {
      final arp = await ch.query(['/ip/arp/print']);
      for (final a in arp) {
        final mac = (a['mac-address'] ?? '').toUpperCase();
        final ip = _nonEmpty(a['address']);
        final comment = _nonEmpty(a['comment']);
        if (mac.isEmpty) continue;
        final existing = dhcpMap[mac];
        if (existing == null) {
          dhcpMap[mac] = (hostname: comment, ip: ip);
        } else {
          dhcpMap[mac] = (
            hostname: existing.hostname ?? comment,
            ip: existing.ip ?? ip,
          );
        }
      }
    } catch (_) {}

    // ═══ Tier 2 كامل — يُرجع النسخة النهائيّة ═══
    return tier1.copyWith(
      wirelessInterfaces:
          wirelessRows.map(MikrotikWireless.fromApiMap).toList(),
      w60gLinks: w60gLinks,
      wirelessClients: wirelessClients.map((c) {
        final macUpper = (c['mac-address'] ?? '').toUpperCase();
        final dhcp = dhcpMap[macUpper];
        return MikrotikWirelessClient.fromApiMap(
          c,
          hostname: dhcp?.hostname,
          ip: dhcp?.ip,
        );
      }).toList(),
    );
  }

  /// إعادة تشغيل الراوتر عبر `/system/reboot` (Binary API).
  /// **مهم**: الراوتر يقطع الاتصال فوراً بعد استقبال الأمر — نتوقّع socket
  /// exception طبيعي (يعني الأمر وصل). نُطلق success في هذي الحالة.
  static Future<void> rebootDevice({
    required String ip,
    required int port,
    required String user,
    required String pass,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final client = MikrotikBinaryClient(
      host: ip,
      port: port,
      user: user,
      pass: pass,
      timeout: timeout,
    );
    try {
      await client.connect();
      await client.login();
      try {
        // نُرسل الأمر — RouterOS قد يقطع الاتصال قبل الرد
        await client.query(['/system/reboot']);
      } catch (e) {
        // Socket closure = الراوتر بدأ يُعيد التشغيل (متوقّع)
        final msg = e.toString();
        if (msg.contains('closed') ||
            msg.contains('timeout') ||
            msg.contains('reset') ||
            msg.contains('reboot')) {
          return; // ← نجاح: الأمر وصل والراوتر بدأ
        }
        rethrow; // خطأ حقيقي (auth، socket refuse)
      }
    } catch (e) {
      if (e is MikrotikException) rethrow;
      throw MikrotikException(_translateSocketError(e));
    } finally {
      try {
        await client.close();
      } catch (_) {}
    }
  }

  static String _translateSocketError(dynamic e) {
    final msg = e.toString();
    if (msg.contains('SocketException') && msg.contains('refused')) {
      return 'الراوتر رفض الاتصال — تأكّد /ip service enable api على المنفذ 8728';
    }
    if (msg.contains('timed out') || msg.contains('timeout')) {
      return 'انتهت مهلة الاتصال — تأكّد أنك على شبكة الراوتر';
    }
    if (msg.contains('Network is unreachable')) {
      return 'الشبكة غير قابلة للوصول — تحقّق من الاتصال';
    }
    return 'خطأ اتصال: $msg';
  }

  /// صفوف /interface/bridge/port ← اسم البريدج: منافذه (بلا المعطّلة)، بترتيبها في الراوتر.
  static Map<String, List<String>> parseBridgePorts(
      List<Map<String, String>> rows) {
    final out = <String, List<String>>{};
    for (final r in rows) {
      final br = (r['bridge'] ?? '').trim();
      final port = (r['interface'] ?? '').trim();
      if (br.isEmpty || port.isEmpty) continue;
      if ((r['disabled'] ?? '').toLowerCase() == 'true') continue;
      (out[br] ??= <String>[]).add(port);
    }
    return out;
  }

  static int _asInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  static int _calcMemUsed(Map<String, String> resource) {
    final total = _asInt(resource['total-memory']);
    final free = _asInt(resource['free-memory']);
    if (total == 0) return 0;
    return (((total - free) / total) * 100).round();
  }

  /// 2026-08-20: SSH fallback لـregistration-table.
  /// RouterOS 6.49.x + Binary API لديه bug: reg-table يرجع !done مع 0 rows
  /// حتى لو الجهاز فيه عملاء. SSH يستعمل نفس الـshell الي يستعمله Winbox
  /// terminal — يعطي مخرجات كاملة بلا API quirks.
  ///
  /// نستعمل MikroTik script يطبع كل الحقول المطلوبة بصيغة ثابتة معروفة
  /// (بدل الاعتماد على `terse` الذي على 6.49.x لا يُخرج signal/rate/ccq
  /// تلقائياً — فقط mac-address و interface).
  static Future<List<Map<String, String>>> _fetchClientsViaSsh(
    String ip,
    String user,
    String pass,
  ) async {
    SSHClient? client;
    SSHSocket? socket;
    try {
      socket =
          await SSHSocket.connect(ip, 22, timeout: const Duration(seconds: 6));
      client = SSHClient(
        socket,
        username: user,
        onPasswordRequest: () => pass,
        onUserInfoRequest: (req) async => req.prompts.map((_) => pass).toList(),
      );
      await client.authenticated.timeout(const Duration(seconds: 6));
      // 2026-08-20: MikroTik script يجمع كل الحقول من registration-table.
      // كل client يُطبع بسطر واحد بصيغة "key=value|key=value|..." — الـpipe
      // يفصل الحقول والـSTART يفصل السجلّات. تجنّبنا newline بين حقول (لأنّه
      // SSH terminal يضيف \r\n قد يخرّب parse). الحقول مضمونة exist عبر :toarray.
      const script = ':local out ""; '
          ':foreach id in=[/interface wireless registration-table find] do={ '
          ':local r [/interface wireless registration-table get \$id]; '
          ':set out (\$out . "START|mac=" . (\$r->"mac-address") . '
          '"|iface=" . (\$r->"interface") . '
          '"|name=" . (\$r->"radio-name") . '
          '"|sig=" . (\$r->"signal-strength") . '
          '"|txsig=" . (\$r->"tx-signal-strength") . '
          '"|snr=" . (\$r->"signal-to-noise") . '
          '"|txccq=" . (\$r->"tx-ccq") . '
          '"|rxccq=" . (\$r->"rx-ccq") . '
          '"|txr=" . (\$r->"tx-rate") . '
          '"|rxr=" . (\$r->"rx-rate") . '
          '"|up=" . (\$r->"uptime") . '
          '"|comment=" . (\$r->"comment") . "\\r\\n") '
          '}; :put \$out';
      final out = utf8.decode(
        await client.run(script).timeout(const Duration(seconds: 10)),
        allowMalformed: true,
      );
      if (kDebugMode) {
        final preview = out.length > 400 ? out.substring(0, 400) : out;
        DevLog.trace(() => '📥 [mikrotik SSH] raw:\n$preview');
      }
      return _parseSshScript(out);
    } finally {
      client?.close();
      try {
        socket?.close();
      } catch (_) {}
    }
  }

  /// Parse SSH script output — كل record يبدأ بـSTART| وينتهي بـ\r\n.
  /// نُحوّل المفاتيح المختصرة (mac, iface, sig...) لأسماء API القياسيّة
  /// (mac-address, interface, signal-strength...) لتوافق مع fromApiMap.
  static List<Map<String, String>> _parseSshScript(String text) {
    final results = <Map<String, String>>[];
    // كل record: "START|mac=xx|iface=xx|..."
    final records = text.split('START|').where((s) => s.trim().isNotEmpty);
    for (final rec in records) {
      // نقطع عند أوّل \r أو \n لأن record واحد سطر واحد
      final line = rec.split(RegExp(r'[\r\n]')).first;
      if (line.isEmpty) continue;
      final map = <String, String>{};
      for (final pair in line.split('|')) {
        final eq = pair.indexOf('=');
        if (eq < 1) continue;
        final key = pair.substring(0, eq).trim();
        final val = pair.substring(eq + 1).trim();
        if (val.isEmpty) continue;
        // Map قصر → API standard
        switch (key) {
          case 'mac':
            map['mac-address'] = val;
            break;
          case 'iface':
            map['interface'] = val;
            break;
          case 'name':
            map['radio-name'] = val;
            break;
          case 'sig':
            map['signal-strength'] = val;
            break;
          case 'txsig':
            map['tx-signal-strength'] = val;
            break;
          case 'snr':
            map['signal-to-noise'] = val;
            break;
          case 'txccq':
            map['tx-ccq'] = val;
            break;
          case 'rxccq':
            map['rx-ccq'] = val;
            break;
          case 'txr':
            map['tx-rate'] = val;
            break;
          case 'rxr':
            map['rx-rate'] = val;
            break;
          case 'up':
            map['uptime'] = val;
            break;
          case 'comment':
            map['comment'] = val;
            break;
        }
      }
      if (map.containsKey('mac-address')) {
        results.add(map);
      }
    }
    return results;
  }
}

/// alias حتى الـ UI يبقى نفسه
typedef MikrotikException = MikrotikBinaryException;

/// طريقٌ لا يوصَل إليه (منفذ مقفول · مهلة · لا REST) — يُجرَّب التالي. لا يخرج من `MikrotikApi`.
class _RouteUnavailable implements Exception {
  _RouteUnavailable(this.cause);
  final Object cause;
}

/// حالة مروحة أو PSU
class MikrotikHealthItem {
  final String name; // 'fan1', 'psu1', 'sfp'
  final String? valueStr; // '4185 RPM' أو 'ok' أو '38 C'
  final int? intValue; // RPM أو Temp (لو رقمي)
  final bool? isOk; // true=ok، false=fail (لـPSU state)
  const MikrotikHealthItem({
    required this.name,
    this.valueStr,
    this.intValue,
    this.isOk,
  });
}

class MikrotikStats {
  final int cpuLoad;
  final int memUsedPercent;
  final int memTotalBytes;
  final int memFreeBytes;
  final String uptime;
  final String version;
  final String boardName;
  final String architectureName;
  final int cpuCount;
  final int cpuFrequencyMhz;
  final int? temperature; // °C من /system/health (CPU-preferred)
  final double? voltage; // V (CCR1009 نعم، CCR2116 لا)

  /// تيّار المزوّدات (A) وما تسحبه أجهزة الـPoE (W) — من /system/health إن قرأها الطراز (netPower · CRS PoE).
  final double? currentAmps;
  final double? powerWatts;
  final List<MikrotikHealthItem> fans; // fan1-speed, fan2-speed, ...
  final List<MikrotikHealthItem> psus; // psu1-state, psu2-state
  final List<MikrotikHealthItem>
      extraTemps; // sfp-temperature، switch-temperature، board-temperature
  final List<MikrotikInterface> interfaces;
  final int pppActiveCount;
  final List<MikrotikWireless> wirelessInterfaces;
  final List<MikrotikWirelessClient> wirelessClients;

  /// وصلات 60 GHz من `/interface/w60g/monitor` — واحدةٌ لكلّ واجهة w60g ردّت.
  final List<MikrotikW60gLink> w60gLinks;

  /// الطريق الذي قُرئ منه: «API» · «الويب» · «SSH» · «SNMP» — يُعرض في رأس اللوحة حين لا يكون الـAPI.
  final String via;

  /// المعالج والذاكرة مقروءان فعلاً — SNMP على SwOS (CSS) لا يحملهما، فيُعرضان «—» لا «0٪» (٢٧ أكتوبر).
  final bool cpuKnown;
  final bool memKnown;

  /// أعضاء كلّ بريدج: اسم البريدج ← منافذه (من /interface/bridge/port). فارغٌ إن لا بريدج،
  /// أو في الوضع الخفيف (vitalsOnly) حيث لا تُعرض المنافذ.
  final Map<String, List<String>> bridgePorts;

  const MikrotikStats({
    required this.cpuLoad,
    required this.memUsedPercent,
    required this.memTotalBytes,
    required this.memFreeBytes,
    required this.uptime,
    required this.version,
    required this.boardName,
    required this.architectureName,
    required this.cpuCount,
    required this.cpuFrequencyMhz,
    this.temperature,
    this.voltage,
    this.currentAmps,
    this.powerWatts,
    this.fans = const [],
    this.psus = const [],
    this.extraTemps = const [],
    required this.interfaces,
    required this.pppActiveCount,
    this.wirelessInterfaces = const [],
    this.wirelessClients = const [],
    this.w60gLinks = const [],
    this.bridgePorts = const {},
    this.via = 'API',
    this.cpuKnown = true,
    this.memKnown = true,
  });

  bool get hasWireless => wirelessInterfaces.isNotEmpty;

  /// وصلة الـ60 GHz لواجهةٍ باسمها، أو null.
  MikrotikW60gLink? w60gLinkOf(String iface) {
    for (final l in w60gLinks) {
      if (l.iface == iface) return l;
    }
    return null;
  }

  /// البريدج الذي ينتمي له المنفذ (أو null).
  String? bridgeOf(String port) {
    for (final e in bridgePorts.entries) {
      if (e.value.contains(port)) return e.key;
    }
    return null;
  }

  /// 2026-08-20: هل هذا الجهاز AP (بمعنى يخدم عملاء)؟
  /// نستعمل هذا لعرض قسم "العملاء" حتى لو الحالة صفر (بدل ما نخفيه كلياً).
  ///
  /// ⚠️ لا تُحسب واجهات 60 GHz: عملاؤها ليسوا في جدول تسجيل، ووصلتها تُعرض في بطاقتها — وإلّا ظهر لكلّ LHG 60G قسم
  /// «العملاء المتّصلون (0)» بنصّ «registration-table فارغ» والوصلة تعمل.
  bool get isAccessPoint => wirelessInterfaces.any((w) => w.isAp && !w.is60g);

  int get upInterfacesCount =>
      interfaces.where((i) => i.running && !i.disabled).length;

  /// نسخة بحقول محدَّثة — يستعملها progressive rendering.
  /// Tier 1 يبني MikrotikStats مع system data فقط (interfaces=[]، wireless=[]).
  /// Tier 2 يستعمل هذي عشان يضيف wireless/registration بلا إعادة بناء كل شيء.
  MikrotikStats copyWith({
    List<MikrotikInterface>? interfaces,
    int? pppActiveCount,
    List<MikrotikWireless>? wirelessInterfaces,
    List<MikrotikWirelessClient>? wirelessClients,
    List<MikrotikW60gLink>? w60gLinks,
  }) =>
      MikrotikStats(
        cpuLoad: cpuLoad,
        memUsedPercent: memUsedPercent,
        memTotalBytes: memTotalBytes,
        memFreeBytes: memFreeBytes,
        uptime: uptime,
        version: version,
        boardName: boardName,
        architectureName: architectureName,
        cpuCount: cpuCount,
        cpuFrequencyMhz: cpuFrequencyMhz,
        temperature: temperature,
        voltage: voltage,
        currentAmps: currentAmps,
        powerWatts: powerWatts,
        fans: fans,
        psus: psus,
        extraTemps: extraTemps,
        interfaces: interfaces ?? this.interfaces,
        pppActiveCount: pppActiveCount ?? this.pppActiveCount,
        wirelessInterfaces: wirelessInterfaces ?? this.wirelessInterfaces,
        wirelessClients: wirelessClients ?? this.wirelessClients,
        w60gLinks: w60gLinks ?? this.w60gLinks,
        bridgePorts: bridgePorts,
        via: via,
        cpuKnown: cpuKnown,
        memKnown: memKnown,
      );
  int get downInterfacesCount =>
      interfaces.where((i) => !i.running && !i.disabled).length;
  int get memUsedBytes => memTotalBytes - memFreeBytes;
}

/// معلومات wireless interface (link / sector / AP)
class MikrotikWireless {
  final String name; // wlan1, wlan2, ...
  final String ssid;
  final String mode; // ap-bridge, station, station-bridge, wds-slave, ...
  final String band; // 5ghz-a, 5ghz-n, 2ghz-b/g/n, ...
  final int frequency; // MHz
  final int channelWidth; // MHz
  final int txPower; // dBm
  final bool disabled;
  final bool running;

  const MikrotikWireless({
    required this.name,
    required this.ssid,
    required this.mode,
    required this.band,
    required this.frequency,
    required this.channelWidth,
    required this.txPower,
    required this.disabled,
    required this.running,
  });

  bool get isAp => mode.startsWith('ap') || mode == 'bridge';
  bool get isStation => mode.startsWith('station');
  bool get is60g => band == '60ghz';

  factory MikrotikWireless.fromApiMap(Map<String, String> j) {
    bool asBool(String? v) => v?.toLowerCase() == 'true';
    return MikrotikWireless(
      name: j['name'] ?? '',
      ssid: j['ssid'] ?? '',
      mode: j['mode'] ?? '',
      band: j['band'] ?? '',
      frequency: _iOrZero(j['frequency']),
      channelWidth:
          _iOrZero(j['channel-width']?.replaceAll(RegExp(r'[^0-9]'), '')),
      txPower: _iOrZero(j['tx-power']),
      disabled: asBool(j['disabled']),
      running: asBool(j['running']),
    );
  }
}

/// وصلة 60 GHz كما يقرؤها `/interface/w60g/monitor =once=` (LHG 60G · wAP 60G · Cube 60G/60Pro · nRAY).
///
/// ⚠️ `signal` هنا **جودةٌ بالمئة (0–100) لا dBm** — والـdBm في `rssi`. وسرعة الربط نصٌّ بوحدته («2.3Gbps» ·
/// «1540.0Mbps»)، والمسافة «160.9m». الإصدارات تختلف في الاسم: `mcs`/`phy-rate` (7) و`tx-mcs`/`tx-phy-rate` (6).
/// ما لا يُرجعه الجهاز يبقى null فيُعرض «—» — لا صفر.
class MikrotikW60gLink {
  final String iface;
  final bool connected;

  /// MHz — الفعليّ؛ الإعداد قد يكون «auto».
  final int? frequency;
  final String? remoteMac;

  /// dBm.
  final int? rssi;

  /// جودة الإشارة ٪ (0–100).
  final int? signalPercent;
  final int? mcs;
  final int? phyRateMbps;
  final double? distanceMeters;
  final int? txSector;
  final String? txSectorInfo;

  /// نسبة أخطاء الإرسال ٪.
  final int? packetErrorRate;

  /// محطّاتٌ متّصلة بهذه الواجهة (وضع ap-bridge) من `/interface/w60g/station`.
  final int stations;

  const MikrotikW60gLink({
    required this.iface,
    required this.connected,
    this.frequency,
    this.remoteMac,
    this.rssi,
    this.signalPercent,
    this.mcs,
    this.phyRateMbps,
    this.distanceMeters,
    this.txSector,
    this.txSectorInfo,
    this.packetErrorRate,
    this.stations = 0,
  });

  factory MikrotikW60gLink.fromMonitor(String iface, Map<String, String> m, {int stations = 0}) {
    int? asInt(String? v) {
      if (v == null) return null;
      final x = RegExp(r'-?\d+').firstMatch(v)?.group(0);
      return x == null ? null : int.tryParse(x);
    }

    final connected = const {'true', 'yes'}.contains((m['connected'] ?? '').toLowerCase());
    final pct = asInt(m['signal']);
    final rssi = asInt(m['rssi']);
    final freq = asInt(m['frequency']);
    return MikrotikW60gLink(
      iface: iface,
      connected: connected,
      frequency: freq != null && freq > 0 ? freq : null,
      remoteMac: _nonEmpty(m['remote-address']),
      // غير المتّصل لا إشارة له — أيّ رقمٍ يُرجعه بقايا آخر اتّصال.
      rssi: connected && rssi != null && rssi < 0 ? rssi : null,
      signalPercent: connected && pct != null && pct >= 0 && pct <= 100 ? pct : null,
      mcs: connected ? asInt(m['mcs'] ?? m['tx-mcs']) : null,
      phyRateMbps: connected ? rateMbps(m['phy-rate'] ?? m['tx-phy-rate']) : null,
      distanceMeters: connected ? meters(m['distance']) : null,
      txSector: connected ? asInt(m['tx-sector']) : null,
      txSectorInfo: connected ? _nonEmpty(m['tx-sector-info']) : null,
      packetErrorRate: connected ? asInt(m['tx-packet-error-rate']) : null,
      stations: stations,
    );
  }

  /// «2.31 Gbps» من الألف فما فوق، وإلّا «1540 Mbps» — للّوحة والنظرة العامّة معاً.
  static String rateText(int mbps) => mbps >= 1000 ? '${(mbps / 1000).toStringAsFixed(2)} Gbps' : '$mbps Mbps';

  static String distanceText(double m) => m >= 1000 ? '${(m / 1000).toStringAsFixed(2)} km' : '${m.round()} m';

  /// «28 · center» — رقم القطاع ثمّ وصفه كما يكتبه الجهاز.
  String? get sectorText => txSector == null ? null : (txSectorInfo == null ? '$txSector' : '$txSector · $txSectorInfo');

  /// «2.3Gbps» ← 2300 · «1540.0Mbps» ← 1540 · «0bps»/فارغ ← null.
  static int? rateMbps(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'([\d.]+)\s*([kKmMgG]?)bps').firstMatch(raw);
    final v = m == null ? null : double.tryParse(m.group(1)!);
    if (v == null || v <= 0) return null;
    final mbps = switch (m!.group(2)!.toLowerCase()) {
      'g' => v * 1000,
      'm' => v,
      'k' => v / 1000,
      _ => v / 1000000,
    };
    return mbps < 1 ? null : mbps.round();
  }

  /// «160.9m» ← 160.9 · «1.2km» ← 1200.
  static double? meters(String? raw) {
    if (raw == null) return null;
    final m = RegExp(r'([\d.]+)\s*(km|m)\b').firstMatch(raw);
    final v = m == null ? null : double.tryParse(m.group(1)!);
    if (v == null || v <= 0) return null;
    return m!.group(2) == 'km' ? v * 1000 : v;
  }
}

/// عميل wireless متصل (من registration-table + DHCP lease enrichment)
class MikrotikWirelessClient {
  final String mac;
  final String iface; // wlan1, wlan2 — أي wireless انضمّ عليه
  final int signalStrength; // dBm — RX (كيف نستقبل من العميل)
  final int
      txSignalStrength; // dBm — TX (كيف العميل يستقبل منّا). 0 = غير متوفّر
  final int signalToNoise; // dB (SNR)
  final int txCcq; // Client Connection Quality % (0-100)
  final int rxCcq; // %
  final int txRate; // Mbps
  final int rxRate; // Mbps
  final int uptime; // seconds
  final String? comment; // من registration-table comment
  final String? hostname; // من DHCP host-name أو lease comment
  final String? ip; // من DHCP active-address

  const MikrotikWirelessClient({
    required this.mac,
    required this.iface,
    required this.signalStrength,
    this.txSignalStrength = 0,
    required this.signalToNoise,
    required this.txCcq,
    required this.rxCcq,
    required this.txRate,
    required this.rxRate,
    required this.uptime,
    this.comment,
    this.hostname,
    this.ip,
  });

  /// أفضل اسم لعرض العميل: hostname (DHCP) > comment (registration) > MAC
  String get displayName => hostname ?? comment ?? mac;

  /// عرض الإشارة كما WinBox: "TX/RX" مثل "-36/-51". لو txSignal غير متوفّر
  /// نعرض الـRX فقط.
  String get signalDisplay {
    if (txSignalStrength != 0) return '$txSignalStrength/$signalStrength';
    return '$signalStrength';
  }

  factory MikrotikWirelessClient.fromApiMap(
    Map<String, String> j, {
    String? hostname,
    String? ip,
  }) {
    // radio-name = اسم الجهاز البعيد (لو Mikrotik→Mikrotik) — يظهر في WinBox
    // كـidentity للـsector/client. أولويّة عالية للعرض.
    final radioName = _nonEmpty(j['radio-name']);
    return MikrotikWirelessClient(
      // RouterOS 7 wifi package أحياناً يستعمل `mac` بدل `mac-address`.
      mac: j['mac-address'] ?? j['mac'] ?? '',
      iface: j['interface'] ?? '',
      // RX signal — wireless: `signal-strength`، wifi7+: `signal`.
      signalStrength: _parseSignal(j['signal-strength'] ?? j['signal']),
      // TX signal — wireless: `tx-signal-strength`، wifi7+: `tx-signal`.
      txSignalStrength: _parseSignal(j['tx-signal-strength'] ?? j['tx-signal']),
      // SNR — wireless: `signal-to-noise`، wifi7+: `snr` أحياناً.
      signalToNoise: _iOrZero(j['signal-to-noise'] ?? j['snr']),
      txCcq: _iOrZero(j['tx-ccq']),
      rxCcq: _iOrZero(j['rx-ccq']),
      txRate: _parseRate(j['tx-rate']),
      rxRate: _parseRate(j['rx-rate']),
      uptime: _parseUptimeSeconds(j['uptime']),
      comment: _nonEmpty(j['comment']),
      // نُفضّل: DHCP hostname > radio-name (Mikrotik identity) > wireless comment > null
      hostname: hostname ?? radioName,
      ip: ip,
    );
  }

  /// "-58@1Mbps" أو "-58" → -58
  static int _parseSignal(String? raw) {
    if (raw == null) return 0;
    final m = RegExp(r'-?\d+').firstMatch(raw);
    return m == null ? 0 : (int.tryParse(m.group(0)!) ?? 0);
  }

  /// "270Mbps-40MHz/2S/SGI" → 270
  static int _parseRate(String? raw) {
    if (raw == null) return 0;
    final m = RegExp(r'(\d+)').firstMatch(raw);
    return m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0);
  }

  /// "3w2d15h4m5s" → seconds
  static int _parseUptimeSeconds(String? raw) {
    if (raw == null || raw.isEmpty) return 0;
    int total = 0;
    final w = RegExp(r'(\d+)w').firstMatch(raw)?.group(1);
    final d = RegExp(r'(\d+)d').firstMatch(raw)?.group(1);
    final h = RegExp(r'(\d+)h').firstMatch(raw)?.group(1);
    final m = RegExp(r'(\d+)m(?!s)').firstMatch(raw)?.group(1);
    final s = RegExp(r'(\d+)s').firstMatch(raw)?.group(1);
    if (w != null) total += int.parse(w) * 604800;
    if (d != null) total += int.parse(d) * 86400;
    if (h != null) total += int.parse(h) * 3600;
    if (m != null) total += int.parse(m) * 60;
    if (s != null) total += int.parse(s);
    return total;
  }
}

int _iOrZero(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  return int.tryParse(v.toString()) ?? 0;
}

String? _nonEmpty(String? s) =>
    (s == null || s.trim().isEmpty) ? null : s.trim();

class MikrotikInterface {
  final String name;
  final String type;
  final bool running;
  final bool disabled;
  final int? mtu;
  final int? rxBytes;
  final int? txBytes;

  /// سرعة الـport الفعليّة من ethernet/monitor (مثل "1Gbps", "100Mbps")
  final String? linkSpeed;

  /// full-duplex من ethernet/monitor
  final bool fullDuplex;

  const MikrotikInterface({
    required this.name,
    required this.type,
    required this.running,
    required this.disabled,
    this.mtu,
    this.rxBytes,
    this.txBytes,
    this.linkSpeed,
    this.fullDuplex = true,
  });

  /// Binary API يرجع كل القيم كـString — نحوّل نحن.
  /// monitor (اختياري) من /interface/ethernet/monitor يحوي rate + full-duplex
  factory MikrotikInterface.fromApiMap(
    Map<String, String> j, {
    Map<String, String>? monitor,
  }) {
    bool asBool(String? v) => v?.toLowerCase() == 'true';
    int? asInt(String? v) {
      if (v == null) return null;
      return int.tryParse(v);
    }

    return MikrotikInterface(
      name: j['name'] ?? '',
      type: j['type'] ?? '',
      running: asBool(j['running']),
      disabled: asBool(j['disabled']),
      mtu: asInt(j['actual-mtu'] ?? j['mtu']),
      rxBytes: asInt(j['rx-byte']),
      txBytes: asInt(j['tx-byte']),
      linkSpeed: monitor?['rate'],
      fullDuplex: monitor == null ? true : asBool(monitor['full-duplex']),
    );
  }
}
