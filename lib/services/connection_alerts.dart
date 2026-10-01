import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import 'auth_storage.dart';
import '../core/util/bidi.dart';
import '../models/device_health.dart';

/// «تنبيه المشترك» بمشكلة الاتصال — الحدود والكشف وتركيب الرسالة.
///
/// **يدويّةٌ وحدها**: المدير يضغط الزرّ ويرى المعاينة ثمّ يرسل. الوضع
/// المجدول أُلغي (قرار المستخدم ٢٠٢٦-١٠-٠١: «بس يدوي»).
///
/// ── أين يجري الكشف ولماذا ────────────────────────────────────────
/// على الهاتف وحده: هو من يصل أجهزة المشتركين (نانو / ONT) على شبكة
/// المزوّد، وكاش فحصها في `DeviceProbeApi` محلّيّ. الخادم يحفظ حدود
/// كلّ مدير فقط (`/api/v2/connection-alerts/settings`).
///
/// ── ما يُضبط وما لا يُضبط ─────────────────────────────────────────
/// الإشارة وCCQ والضوئي والحرارة يضبطها المدير ضمن حدودٍ دنيا وعليا.
/// أمّا الكيبل فثابت: «10 ميكا أو غير مربوط» عطلٌ فعليّ، وكلاهما يصل
/// المشترك **سبباً واحداً** لأنّ النتيجة واحدة — نتٌّ غير مستقرّ.
/// (قرار المستخدم ٢٠٢٦-١٠-٠١.)

/// المسموح لكلّ حدّ — مطابقٌ `CONNECTION_ALERT_LIMITS` في server.js.
///
/// ⚠️ الحدود حمايةٌ لا تجميل: حدٌّ متهوّر (إشارة -40) يجعل كلّ المشتركين
/// «مشكلة»، فيصير الشريط على كلّ كارت ويفقد معناه.
class ConnectionAlertLimits {
  ConnectionAlertLimits._();
  static const signalMin = -85, signalMax = -55;
  static const ccqMin = 20, ccqMax = 90;
  static const rxMin = -32.0, rxMax = -20.0;
  static const tempMin = 50, tempMax = 90;
}

class ConnectionAlertThresholds {
  const ConnectionAlertThresholds({
    this.enabled = false,
    this.signalDbm = -60,
    this.ccqPct = 50,
    this.fiberRxDbm = -27,
    this.fiberTempC = 70,
    this.isDefault = true,
  });

  /// الميزة **متوقّفة حتّى يفعّلها المدير** (قرار المستخدم ٢٠٢٦-١٠-٠١):
  /// بدونه لا شريط في القائمة ولا زرّ في الكارت.
  final bool enabled;

  /// أضعف من هذا = مشكلة (‎-65 أضعف من ‎-60).
  final int signalDbm;

  /// هذا أو أقلّ = مشكلة.
  final int ccqPct;

  /// أضعف من هذا = مشكلة.
  final double fiberRxDbm;

  /// أعلى من هذا = مشكلة.
  final int fiberTempC;

  /// لم يحفظ المدير حدوداً بعد — هذه الافتراضيّات.
  final bool isDefault;

  static const defaults = ConnectionAlertThresholds();

  factory ConnectionAlertThresholds.fromJson(Map<String, dynamic> j) {
    int i(String k, int fb) {
      final v = j[k];
      if (v is num) return v.round();
      return num.tryParse('$v')?.round() ?? fb;
    }

    double d(String k, double fb) {
      final v = j[k];
      if (v is num) return v.toDouble();
      return double.tryParse('$v') ?? fb;
    }

    final en = j['enabled'];
    return ConnectionAlertThresholds(
      enabled: en == true || en == 1 || en == '1',
      signalDbm: i('signal_dbm', defaults.signalDbm),
      ccqPct: i('ccq_pct', defaults.ccqPct),
      fiberRxDbm: d('fiber_rx_dbm', defaults.fiberRxDbm),
      fiberTempC: i('fiber_temp_c', defaults.fiberTempC),
      isDefault: j['is_default'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'signal_dbm': signalDbm,
        'ccq_pct': ccqPct,
        'fiber_rx_dbm': fiberRxDbm,
        'fiber_temp_c': fiberTempC,
      };

  ConnectionAlertThresholds copyWith({
    bool? enabled,
    int? signalDbm,
    int? ccqPct,
    double? fiberRxDbm,
    int? fiberTempC,
  }) =>
      ConnectionAlertThresholds(
        enabled: enabled ?? this.enabled,
        signalDbm: signalDbm ?? this.signalDbm,
        ccqPct: ccqPct ?? this.ccqPct,
        fiberRxDbm: fiberRxDbm ?? this.fiberRxDbm,
        fiberTempC: fiberTempC ?? this.fiberTempC,
        isDefault: false,
      );
}

/// حدود المدير الحاليّ — مخزَّنةٌ في الذاكرة ومربوطةٌ بصاحبها.
///
/// [current] يبدأ بالافتراضيّات كي يعمل شريط القائمة فوراً، ثمّ يُستبدل
/// حين تصل حدود المدير فتُعاد رسم البطاقات وحدها.
class ConnectionAlertSettings {
  ConnectionAlertSettings._();

  static final ValueNotifier<ConnectionAlertThresholds> current =
      ValueNotifier<ConnectionAlertThresholds>(
          ConnectionAlertThresholds.defaults);

  static const _ttl = Duration(minutes: 10);
  static DateTime? _loadedAt;

  /// ⚠️ الكاش مختومٌ بصاحبه: هاتفٌ واحد قد يدخله مديران، وحدود الأوّل
  /// لا يجوز أن تحكم مشتركي الثاني.
  static String? _loadedFor;
  static Future<ConnectionAlertThresholds>? _inFlight;

  static Future<ConnectionAlertThresholds> ensureLoaded({bool force = false}) {
    return _inFlight ??= _load(force).whenComplete(() => _inFlight = null);
  }

  static Future<ConnectionAlertThresholds> _load(bool force) async {
    final adminId = await AuthStorage.readAdminId();
    final fresh = !force &&
        _loadedAt != null &&
        _loadedFor == adminId &&
        DateTime.now().difference(_loadedAt!) < _ttl;
    if (fresh) return current.value;
    if (_loadedFor != adminId) {
      current.value = ConnectionAlertThresholds.defaults;
    }
    try {
      final r = await ApiClient.dio.get<Map<String, dynamic>>(
          '/api/v2/connection-alerts/settings');
      final data = r.data?['data'];
      if (r.data?['success'] == true && data is Map) {
        current.value =
            ConnectionAlertThresholds.fromJson(Map<String, dynamic>.from(data));
        _loadedAt = DateTime.now();
        _loadedFor = adminId;
      }
    } catch (e) {
      // فشل الجلب لا يُسقط الميزة: تبقى آخر حدودٍ معروفة أو الافتراضيّات.
      if (!kReleaseMode) debugPrint('🔴 connection-alerts/settings: $e');
    }
    return current.value;
  }

  static Future<({bool ok, String? message})> save(
      ConnectionAlertThresholds t) async {
    try {
      final r = await ApiClient.dio.put<Map<String, dynamic>>(
        '/api/v2/connection-alerts/settings',
        data: t.toJson(),
      );
      final body = r.data ?? const {};
      if (body['success'] == true && body['data'] is Map) {
        current.value = ConnectionAlertThresholds.fromJson(
            Map<String, dynamic>.from(body['data'] as Map));
        _loadedAt = DateTime.now();
        _loadedFor = await AuthStorage.readAdminId();
        return (ok: true, message: body['message']?.toString());
      }
      return (ok: false, message: body['message']?.toString());
    } on DioException catch (e) {
      final data = e.response?.data;
      final msg = data is Map ? data['message']?.toString() : null;
      return (ok: false, message: msg ?? 'تعذّر حفظ الحدود');
    } catch (_) {
      return (ok: false, message: 'تعذّر حفظ الحدود');
    }
  }
}

enum ConnectionProblemKind { cable, signal, ccq, fiberRx, fiberTemp }

/// مشكلةٌ مكتشفة في آخر فحص لجهاز المشترك.
class ConnectionProblem {
  const ConnectionProblem({
    required this.kind,
    required this.label,
    required this.vars,
  });

  final ConnectionProblemKind kind;

  /// ما يراه المدير: «LAN غير مربوط» · «إشارة -68 dBm». القيم معزولة
  /// الاتّجاه كي لا تنقلب ‎-68 إلى 68- داخل النصّ العربيّ.
  final String label;

  /// متغيّرات سطر هذه المشكلة في القالب ({signal} …).
  final Map<String, String> vars;

  String get templateType => ConnectionAlertTemplates.lineType(kind);
}

class ConnectionAlerts {
  ConnectionAlerts._();

  /// المشاكل في لقطةٍ واحدة بحسب حدود المدير. فارغة = لا مشكلة.
  ///
  /// ⚠️ «لم نقرأ» ليست «مشكلة»: قيمةٌ غائبة أو غير مفهومة تُتجاوز. فتنبيه
  /// مشتركٍ على قراءةٍ فاشلة يرسله إلى السطح والجهاز سليم.
  static List<ConnectionProblem> detect(
      DeviceHealthSnapshot snap, ConnectionAlertThresholds t) {
    final out = <ConnectionProblem>[];
    if (snap.kind == DeviceKind.ubiquiti && snap.ubnt != null) {
      final u = snap.ubnt!;
      final lan = lanState(u);
      if (lan != null) {
        out.add(ConnectionProblem(
          kind: ConnectionProblemKind.cable,
          label: 'LAN $lan',
          vars: {'{lan_state}': lan},
        ));
      }
      // صفرٌ ليس قراءة: جهازٌ نصله لا تكون إشارته 0 ولا جودة ربطه 0٪.
      final s = u.signalDbm;
      if (s != null && s < 0 && s < t.signalDbm) {
        final v = iso('$s dBm');
        out.add(ConnectionProblem(
          kind: ConnectionProblemKind.signal,
          label: 'إشارة $v',
          vars: {'{signal}': v},
        ));
      }
      final c = u.ccqPercent;
      if (c != null && c > 0 && c <= t.ccqPct) {
        final v = iso('$c%');
        out.add(ConnectionProblem(
          kind: ConnectionProblemKind.ccq,
          label: 'CCQ $v',
          vars: {'{ccq}': v},
        ));
      }
    } else if (snap.kind == DeviceKind.ont && snap.ont != null) {
      final o = snap.ont!;
      final rx = double.tryParse(o.rxPower.trim());
      if (rx != null && rx < 0 && rx < t.fiberRxDbm) {
        final v = iso('${_num(rx)} dBm');
        out.add(ConnectionProblem(
          kind: ConnectionProblemKind.fiberRx,
          label: 'ضوئي $v',
          vars: {'{rx_power}': v},
        ));
      }
      final temp = double.tryParse(o.temperature.trim());
      if (temp != null && temp > t.fiberTempC) {
        final v = iso('${_num(temp)}°C');
        out.add(ConnectionProblem(
          kind: ConnectionProblemKind.fiberTemp,
          label: 'حرارة $v',
          vars: {'{temperature}': v},
        ));
      }
    }
    return out;
  }

  /// حالة كيبل LAN إن كانت عطلاً: «غير مربوط» أو «يقرأ 10 ميكا».
  /// `null` = سليم أو مجهول.
  @visibleForTesting
  static String? lanState(UbiquitiStatus u) {
    // لا منافذ مقروءة = لم نعرف، لا «غير مربوط».
    if (u.lanPorts.isEmpty) return null;
    final p = u.primaryLan;
    if (p == null) return null;
    if (!p.plugged) return 'غير مربوط';
    // موصولٌ والسرعة مجهولة (airOS 5) ليس عطلاً.
    if (p.speedUnknown) return null;
    final m = RegExp(r'^(\d+)Mbps').firstMatch(p.speed ?? '');
    final mbps = m == null ? null : int.tryParse(m.group(1)!);
    // `0Mbps` يعرضه التطبيق «Unplugged» — والكارت والرسالة يتّفقان.
    if (mbps == 0) return 'غير مربوط';
    if (mbps == 10) return 'يقرأ 10 ميكا';
    return null;
  }

  /// يركّب الرسالة: سطرٌ لكلّ مشكلة داخل {problems} في الرسالة العامّة.
  /// متغيّرات المشترك ({subscriber_name} …) تُملأ بعدها في
  /// `WhatsAppApi.renderForSubscriber`.
  ///
  /// [lines] نصوص المدير لكلّ سطر؛ الناقص منها يأخذ الافتراضيّ.
  static String compose({
    required String envelope,
    required Map<String, String> lines,
    required List<ConnectionProblem> problems,
  }) {
    final rendered = problems
        .map((p) {
          final own = lines[p.templateType]?.trim() ?? '';
          var line = own.isNotEmpty
              ? own
              : ConnectionAlertTemplates.defaultFor(p.templateType);
          p.vars.forEach((k, v) => line = line.replaceAll(k, v));
          return line.trim();
        })
        .where((l) => l.isNotEmpty)
        .join('\n');
    // مديرٌ حذف {problems} من قالبه: لا تُبتلع المشاكل صامتةً.
    if (!envelope.contains('{problems}')) {
      return '${envelope.trimRight()}\n\n$rendered';
    }
    return envelope.replaceAll('{problems}', rendered);
  }

  static String _num(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

/// أنواع القوالب ونصوصها الافتراضيّة — **المصدر الوحيد** لها.
///
/// الخادم لا يحمل نسخةً: الرسالة تُركَّب على الهاتف دائماً، وكانت
/// نسخته للوضع المجدول الذي أُلغي.
class ConnectionAlertTemplates {
  ConnectionAlertTemplates._();

  static const envelopeType = 'connection_alert';

  static const lineTypes = <String>[
    'conn_alert_cable',
    'conn_alert_signal',
    'conn_alert_ccq',
    'conn_alert_fiber_rx',
    'conn_alert_fiber_temp',
  ];

  static const allTypes = <String>[envelopeType, ...lineTypes];

  static bool isConnectionType(String type) => allTypes.contains(type);

  static String lineType(ConnectionProblemKind k) => switch (k) {
        ConnectionProblemKind.cable => 'conn_alert_cable',
        ConnectionProblemKind.signal => 'conn_alert_signal',
        ConnectionProblemKind.ccq => 'conn_alert_ccq',
        ConnectionProblemKind.fiberRx => 'conn_alert_fiber_rx',
        ConnectionProblemKind.fiberTemp => 'conn_alert_fiber_temp',
      };

  static const labels = <String, String>{
    'connection_alert': 'تنبيه مشكلة الاتصال',
    'conn_alert_cable': 'سطر: خلل الكيبل',
    'conn_alert_signal': 'سطر: إشارة ضعيفة',
    'conn_alert_ccq': 'سطر: جودة ربط منخفضة',
    'conn_alert_fiber_rx': 'سطر: إشارة ضوئيّة ضعيفة',
    'conn_alert_fiber_temp': 'سطر: حرارة جهاز الفايبر',
  };

  /// المتغيّر الخاصّ بكلّ سطر — يُعرض للمدير تحت حقله.
  static const lineVariable = <String, String>{
    'conn_alert_cable': '{lan_state}',
    'conn_alert_signal': '{signal}',
    'conn_alert_ccq': '{ccq}',
    'conn_alert_fiber_rx': '{rx_power}',
    'conn_alert_fiber_temp': '{temperature}',
  };

  static String defaultFor(String type) => _defaults[type] ?? '';

  static const _defaults = <String, String>{
    'connection_alert': '''
مرحباً {subscriber_name} 👋

لاحظنا مشكلة في اتصال الإنترنت عندك:
{problems}

إذا احتجت مساعدة تواصل ويانا 🙏''',
    'conn_alert_cable':
        '• يوجد خلل بكيبل الإنترنت، يرجى التأكّد من ربط الكيبل وسلامته وأنّ الراوتر شغّال.',
    'conn_alert_signal': '• الإشارة ضعيفة ({signal})، يرجى إعادة توجيه الجهاز.',
    'conn_alert_ccq':
        '• جودة الربط منخفضة (CCQ {ccq})، يرجى إعادة توجيه الجهاز.',
    'conn_alert_fiber_rx':
        '• الإشارة الضوئيّة ضعيفة ({rx_power})، يرجى التأكّد من كيبل الفايبر وعدم ثنيه أو كسره.',
    'conn_alert_fiber_temp':
        '• حرارة جهاز الفايبر مرتفعة ({temperature})، يرجى وضعه بمكان مهوّى بعيداً عن الحرارة.',
  };
}
