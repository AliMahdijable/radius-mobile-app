import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mikrotik_binary_api.dart';

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
  static Future<MikrotikStats> fetchStats({
    required String ip,
    required int port,          // 8728 (api) أو 8729 (api-ssl)
    required String user,
    required String pass,
    Duration timeout = const Duration(seconds: 6),
    void Function(MikrotikStats partial)? onPartialReady,
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

      // ═══════ TIER 1 (fast — عرض جزئي) ═══════
      // system/resource + interface/print + health + ethernet/monitor
      // هذي الأساسيّات: CPU/RAM/uptime/temp + قائمة الـinterfaces
      final resourceRows = await client.query(['/system/resource/print']);
      final interfaceRows = await client.query(['/interface/print']);
      List<Map<String, String>> healthRows = const [];
      try {
        healthRows = await client.query(['/system/health/print']);
        // Debug: طباعة كل صفوف health لنعرف بأي أسماء fields يستعمل الراوتر
        // (CCR2116 مثلاً قد يستعمل psu1-voltage/psu2-voltage بدل voltage)
        if (kDebugMode && healthRows.isNotEmpty) {
          debugPrint('🔵 [mikrotik health] rows count=${healthRows.length}');
          for (final r in healthRows) {
            debugPrint('   $r');
          }
        }
      } catch (_) {}
      List<Map<String, String>> pppRows = const [];
      try {
        pppRows = await client.query(['/ppp/active/print']);
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
          final monResult = await client.query([
            '/interface/ethernet/monitor',
            '=numbers=${etherNames.join(",")}',
            '=once=',
          ]);
          // كل row يحمل اسم الـinterface؛ لو ما موجود نستعمل الترتيب.
          for (int i = 0; i < monResult.length; i++) {
            final r = monResult[i];
            final key = r['name'] ?? (i < etherNames.length ? etherNames[i] : '');
            if (key.isNotEmpty) ethMonitorByName[key] = r;
          }
        } catch (_) {
          // fallback: لو RouterOS الإصدار ما يقبل قائمة، رجعنا للـloop
          // (سابقاً كان كل جهاز على حدة، بطيء لكن يشتغل)
          for (final name in etherNames) {
            try {
              final r = await client.query([
                '/interface/ethernet/monitor',
                '=numbers=$name',
                '=once=',
              ]);
              if (r.isNotEmpty) ethMonitorByName[name] = r.first;
            } catch (_) {}
          }
        }
      }

      if (resourceRows.isEmpty) {
        throw MikrotikBinaryException('لم يرجع الراوتر معلومات system/resource');
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
      final fans = <MikrotikHealthItem>[];
      final psus = <MikrotikHealthItem>[];
      final extraTemps = <MikrotikHealthItem>[];

      for (final h in healthRows) {
        final name = (h['name'] ?? '').toLowerCase();
        final valueStr = h['value'] ?? '';
        if (name.isEmpty) continue;

        if (name.contains('temp')) {
          // كل الحرارات → extraTemps، الأولى (أو cpu) → healthTemp
          final v = double.tryParse(valueStr.replaceAll(RegExp(r'[^\d.-]'), ''));
          if (v != null) {
            extraTemps.add(MikrotikHealthItem(
              name: name, valueStr: valueStr, intValue: v.round(),
            ));
            if (healthTemp == null || name.contains('cpu')) {
              healthTemp = v.round();
            }
          }
        } else if (name.contains('voltage') || name == 'v') {
          final v = double.tryParse(valueStr.replaceAll(RegExp(r'[^\d.-]'), ''));
          if (v != null) healthVoltage = v;
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
          'voltage', 'input-voltage', 'board-voltage',
          'psu-voltage', 'psu1-voltage', 'power-supply-1-voltage',
        ]) {
          if (healthVoltage == null && r[vKey] != null) {
            healthVoltage = double.tryParse(
                r[vKey]!.replaceAll(RegExp(r'[^\d.-]'), ''));
            if (healthVoltage != null) break;
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
        fans: fans,
        psus: psus,
        extraTemps: extraTemps,
        interfaces: interfaceRows.map((row) {
          final name = row['name'] ?? '';
          final monitor = ethMonitorByName[name];
          return MikrotikInterface.fromApiMap(row, monitor: monitor);
        }).toList(),
        pppActiveCount: pppRows.length,
        wirelessInterfaces: const [],   // Tier 2 يملؤها
        wirelessClients: const [],
      );

      // ⚡ يُطلق callback الآن — UI يعرض CPU/RAM/interfaces فوراً
      if (onPartialReady != null) {
        try { onPartialReady(tier1); } catch (_) {}
      }

      // ═══════ TIER 2 (تفاصيل — wireless + enrichment) ═══════
      // 2026-08-18: أجهزة Mikrotik تستعمل حزم wireless مختلفة حسب النوع:
      //   - `/interface/wireless/print` — airMax/802.11 القديم (RouterOS 6)
      //   - `/interface/w60g/print` — 60 GHz (LHG 60G, wAP 60G, cAP 60G)
      //   - `/interface/wifi/print` — RouterOS 7 wifi (WiFi 6 / AX)
      //   - `/interface/wifiwave2/print` — legacy wifiwave2 (7.1-7.6)
      // نجرّب الأربعة، ونجمع النتائج (LHG 60G مثلاً لا يستجيب للأوّل بل للثاني).
      List<Map<String, String>> wirelessRows = [];
      List<Map<String, String>> wirelessClients = [];
      try {
        final rows = await client.query(['/interface/wireless/print']);
        wirelessRows.addAll(rows);
      } catch (_) { /* عادي على CCR + LHG 60G */ }
      try {
        final rows = await client.query(['/interface/w60g/print']);
        // sanitize: نطابق بنية wireless (ssid/mode/frequency)
        for (final w in rows) {
          wirelessRows.add({
            'name': w['name'] ?? '',
            'ssid': w['ssid'] ?? '',
            'mode': (w['mode'] ?? 'bridge').toString(),
            'band': '60ghz',
            'frequency': w['frequency'] ?? '',
            'channel-width': w['channel-width']?.replaceAll(RegExp(r'[^0-9]'), '') ?? '2160',
            'tx-power': w['tx-power'] ?? '',
            'disabled': w['disabled'] ?? 'false',
            'running': w['running'] ?? 'false',
          });
        }
      } catch (_) { /* عادي على الأجهزة الي لا تدعم 60GHz */ }
      try {
        final rows = await client.query(['/interface/wifi/print']);
        for (final w in rows) {
          wirelessRows.add({
            'name': w['name'] ?? '',
            'ssid': (w['configuration'] ?? w['ssid'] ?? '').toString(),
            'mode': (w['mode'] ?? 'ap').toString(),
            'band': (w['band'] ?? '').toString(),
            'frequency': w['frequency'] ?? '',
            'channel-width': w['channel-width']?.replaceAll(RegExp(r'[^0-9]'), '') ?? '',
            'tx-power': w['tx-power'] ?? '',
            'disabled': w['disabled'] ?? 'false',
            'running': w['running'] ?? 'false',
          });
        }
      } catch (_) { /* عادي على RouterOS 6 */ }
      // Clients — نختار المسار الصحيح بناءً على نوع الـwireless interfaces
      // المكتشفة أعلاه، بدل تجربة الـ6 مسارات متسلسلة (كانت تسبّب global
      // timeout: 6s × 5 مسارات فاشلة = 30s → الـfetch الخارجي يفشل → لا
      // عملاء إطلاقاً حتى للأجهزة السليمة).
      //
      // الاستنتاج من `wirelessRows` (band field):
      //   band='60ghz' → w60g/station
      //   band=''      + جاء من /interface/wireless/print → wireless legacy
      //   band=<other> + جاء من /interface/wifi/print → wifi (RouterOS 7)
      // إن لم نستطع الاستنتاج، نجرّب `/interface/wireless/registration-table
      // /print` (الأشيع لـRouterOS 6) ثمّ نتوقّف إن رجع empty.
      String pickedPath;
      if (wirelessRows.any((w) => (w['band'] ?? '') == '60ghz')) {
        pickedPath = '/interface/w60g/station/print';
      } else {
        // legacy wireless first (RouterOS 6 + 7-with-wireless-package).
        // wifi7 يستعمل نفس ROS-7 mikrotik: reg-table تحته
        // `/interface/wifi/registration-table/print`.
        pickedPath = '/interface/wireless/registration-table/print';
      }
      String? failureMsg;
      try {
        final regs = await client.query([pickedPath])
            .timeout(const Duration(seconds: 12));
        wirelessClients.addAll(regs);
        if (kDebugMode) debugPrint('🟢 [mikrotik] $pickedPath → ${regs.length} clients');
      } on TimeoutException {
        failureMsg = 'timeout';
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('no such command') || msg.contains('no such item')) {
          // Package غير مثبّت → جرّب wifi (RouterOS 7)
          try {
            final regs = await client.query(['/interface/wifi/registration-table/print'])
                .timeout(const Duration(seconds: 8));
            wirelessClients.addAll(regs);
            if (kDebugMode) debugPrint('🟢 [mikrotik] wifi reg-table → ${regs.length} clients');
          } catch (e2) {
            final m2 = e2.toString();
            if (!m2.contains('no such command') && !m2.contains('no such item')) {
              failureMsg = m2.length > 80 ? m2.substring(0, 80) : m2;
            }
          }
        } else {
          failureMsg = msg.length > 80 ? msg.substring(0, 80) : msg;
        }
      }
      // CAPsMAN: نضيفه فقط لو الجهاز يبدو manager (اسم "capsman" في
      // interfaces، أو مسار /caps-man موجود مع wireless section null).
      // بدون هذا: كل جهاز عادي يهدر 6s على /caps-man غير الموجود.
      final looksLikeCapsMan = interfaceRows.any((i) =>
        (i['name'] ?? '').toLowerCase().contains('capsman'));
      if (looksLikeCapsMan) {
        try {
          final regs = await client.query(['/caps-man/registration-table/print'])
              .timeout(const Duration(seconds: 8));
          wirelessClients.addAll(regs);
          if (kDebugMode) debugPrint('🟢 [mikrotik] caps-man reg-table → ${regs.length} clients');
        } catch (_) {}
      }
      if (wirelessClients.isEmpty && wirelessRows.isNotEmpty && kDebugMode) {
        if (failureMsg == 'timeout') {
          debugPrint('⚠️ [mikrotik] reg-table timeout — الجهاز بطيء أو overload. زد timeout عبر MikrotikApi.fetchStats(timeout: ...).');
        } else if (failureMsg != null) {
          debugPrint('⚠️ [mikrotik] reg-table فشل: $failureMsg');
        } else {
          debugPrint('ℹ️ [mikrotik] reg-table رجع فارغ عبر $pickedPath — الـAP بلا عملاء متصلين حالياً.');
        }
      }

      // hostname enrichment: DHCP lease + access-list + ARP
      final Map<String, ({String? hostname, String? ip})> dhcpMap = {};
      try {
        final leases = await client.query(['/ip/dhcp-server/lease/print']);
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
        final acl = await client.query(['/interface/wireless/access-list/print']);
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
        final arp = await client.query(['/ip/arp/print']);
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
        wirelessInterfaces: wirelessRows.map(MikrotikWireless.fromApiMap).toList(),
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
    } on MikrotikBinaryException {
      rethrow;
    } catch (e) {
      if (kDebugMode) debugPrint('❌ MikrotikApi: $e');
      throw MikrotikException(_translateSocketError(e));
    } finally {
      await client.close();
    }
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
        if (msg.contains('closed') || msg.contains('timeout') ||
            msg.contains('reset') || msg.contains('reboot')) {
          return;  // ← نجاح: الأمر وصل والراوتر بدأ
        }
        rethrow;  // خطأ حقيقي (auth، socket refuse)
      }
    } catch (e) {
      if (e is MikrotikException) rethrow;
      throw MikrotikException(_translateSocketError(e));
    } finally {
      try { await client.close(); } catch (_) {}
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
}

/// alias حتى الـ UI يبقى نفسه
typedef MikrotikException = MikrotikBinaryException;

/// حالة مروحة أو PSU
class MikrotikHealthItem {
  final String name;      // 'fan1', 'psu1', 'sfp'
  final String? valueStr; // '4185 RPM' أو 'ok' أو '38 C'
  final int? intValue;    // RPM أو Temp (لو رقمي)
  final bool? isOk;       // true=ok، false=fail (لـPSU state)
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
  final int? temperature;         // °C من /system/health (CPU-preferred)
  final double? voltage;          // V (CCR1009 نعم، CCR2116 لا)
  final List<MikrotikHealthItem> fans;        // fan1-speed, fan2-speed, ...
  final List<MikrotikHealthItem> psus;        // psu1-state, psu2-state
  final List<MikrotikHealthItem> extraTemps;  // sfp-temperature، switch-temperature، board-temperature
  final List<MikrotikInterface> interfaces;
  final int pppActiveCount;
  final List<MikrotikWireless> wirelessInterfaces;
  final List<MikrotikWirelessClient> wirelessClients;

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
    this.fans = const [],
    this.psus = const [],
    this.extraTemps = const [],
    required this.interfaces,
    required this.pppActiveCount,
    this.wirelessInterfaces = const [],
    this.wirelessClients = const [],
  });

  bool get hasWireless => wirelessInterfaces.isNotEmpty;

  /// 2026-08-20: هل هذا الجهاز AP (بمعنى يخدم عملاء)؟
  /// نستعمل هذا لعرض قسم "العملاء" حتى لو الحالة صفر (بدل ما نخفيه كلياً).
  bool get isAccessPoint => wirelessInterfaces.any((w) => w.isAp);

  int get upInterfacesCount => interfaces.where((i) => i.running && !i.disabled).length;

  /// نسخة بحقول محدَّثة — يستعملها progressive rendering.
  /// Tier 1 يبني MikrotikStats مع system data فقط (interfaces=[]، wireless=[]).
  /// Tier 2 يستعمل هذي عشان يضيف wireless/registration بلا إعادة بناء كل شيء.
  MikrotikStats copyWith({
    List<MikrotikInterface>? interfaces,
    int? pppActiveCount,
    List<MikrotikWireless>? wirelessInterfaces,
    List<MikrotikWirelessClient>? wirelessClients,
  }) => MikrotikStats(
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
        fans: fans,
        psus: psus,
        extraTemps: extraTemps,
        interfaces: interfaces ?? this.interfaces,
        pppActiveCount: pppActiveCount ?? this.pppActiveCount,
        wirelessInterfaces: wirelessInterfaces ?? this.wirelessInterfaces,
        wirelessClients: wirelessClients ?? this.wirelessClients,
      );
  int get downInterfacesCount => interfaces.where((i) => !i.running && !i.disabled).length;
  int get memUsedBytes => memTotalBytes - memFreeBytes;
}

/// معلومات wireless interface (link / sector / AP)
class MikrotikWireless {
  final String name;              // wlan1, wlan2, ...
  final String ssid;
  final String mode;              // ap-bridge, station, station-bridge, wds-slave, ...
  final String band;              // 5ghz-a, 5ghz-n, 2ghz-b/g/n, ...
  final int frequency;            // MHz
  final int channelWidth;         // MHz
  final int txPower;              // dBm
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

  factory MikrotikWireless.fromApiMap(Map<String, String> j) {
    bool asBool(String? v) => v?.toLowerCase() == 'true';
    return MikrotikWireless(
      name: j['name'] ?? '',
      ssid: j['ssid'] ?? '',
      mode: j['mode'] ?? '',
      band: j['band'] ?? '',
      frequency: _iOrZero(j['frequency']),
      channelWidth: _iOrZero(j['channel-width']?.replaceAll(RegExp(r'[^0-9]'), '')),
      txPower: _iOrZero(j['tx-power']),
      disabled: asBool(j['disabled']),
      running: asBool(j['running']),
    );
  }
}

/// عميل wireless متصل (من registration-table + DHCP lease enrichment)
class MikrotikWirelessClient {
  final String mac;
  final String iface;             // wlan1, wlan2 — أي wireless انضمّ عليه
  final int signalStrength;       // dBm — RX (كيف نستقبل من العميل)
  final int txSignalStrength;     // dBm — TX (كيف العميل يستقبل منّا). 0 = غير متوفّر
  final int signalToNoise;        // dB (SNR)
  final int txCcq;                // Client Connection Quality % (0-100)
  final int rxCcq;                // %
  final int txRate;               // Mbps
  final int rxRate;               // Mbps
  final int uptime;               // seconds
  final String? comment;          // من registration-table comment
  final String? hostname;         // من DHCP host-name أو lease comment
  final String? ip;                // من DHCP active-address

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

String? _nonEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

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
