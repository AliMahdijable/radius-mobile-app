import 'package:flutter/foundation.dart';

import '../../api/mikrotik_api.dart';
import '../../api/mimosa_api.dart';
import '../../api/network_devices_api.dart';
import '../../api/ubnt_api.dart';
import '../../models/network_device.dart';
import '../../theme/colors.dart';
import 'widgets/_grade.dart';

/// مقياس واحد في خانة من خانات البطاقة الثلاث.
@immutable
class Vital {
  const Vital({
    required this.label,
    required this.value,
    required this.tone,
    this.unit,
  });

  final String label;
  final String value;

  /// الوحدة منفصلة عن الرقم لتُرسَم بلون مميّز بجانبه — طلب المستخدم
  /// في رسوم الاستهلاك، ونفس المبدأ هنا.
  final String? unit;
  final AppTone tone;

  static const empty = Vital(label: '—', value: '—', tone: AppTone.neutral);
}

/// حالة مقاييس جهاز واحد.
@immutable
class VitalsState {
  const VitalsState({this.vitals, this.loading = false, this.error, this.at});

  final List<Vital>? vitals;
  final bool loading;
  final String? error;
  final DateTime? at;

  static const idle = VitalsState();

  bool get isFresh =>
      at != null && DateTime.now().difference(at!) < DeviceVitals.freshFor;
}

/// خريطة «العلامة ← ثلاثة مقاييس».
///
/// ── المشكلة ───────────────────────────────────────────────────────
/// العلامات لا تشترك في مقاييسها: UBNT يعطي إشارةً وحرارة، وميكروتك
/// يعطي ذاكرةً ومعالجاً، وميموزا يعطي قدرةً بصريّة ومعدّلاً. جدولٌ
/// موحّد مستحيل.
///
/// ── الحلّ ─────────────────────────────────────────────────────────
/// نُثبّت **المواضع** ونُغيّر **المعاني**: ثلاث خانات في كلّ بطاقة تحمل
/// أهمّ ثلاثة مقاييس لتلك العلامة. فتصطفّ البطاقات بصريّاً وإن اختلفت
/// التسميات، ويقرأ المدير عموداً واحداً بدل أن يُعيد ضبط عينه مع كلّ
/// بطاقة.
///
/// والألوان كلّها من [Grade] — السلّم الموحّد الذي وحّد ٢٤ دالّة تدريج
/// متفرّقة عبر اللوحات الخمس. لا سلّم سادس هنا.
class DeviceVitals {
  DeviceVitals._();

  /// كم تبقى القيمة صالحةً قبل إعادة الجلب.
  ///
  /// أطول من نبضة اللوحة المفردة (٨–١٥ث) عمداً: الجدار يعرض ستّ بطاقات
  /// لا واحدة، والتمرير ذهاباً وإياباً يُعيد بناءها. بلا نافذة صلاحيّة
  /// يصير كلّ تمرير موجة جلسات جديدة.
  static const freshFor = Duration(seconds: 20);

  /// هل تصلح هذه العلامة لجلسة عميقة أصلاً؟
  static bool supports(String brand) =>
      const {'mikrotik', 'ubnt', 'mimosa'}.contains(brand.toLowerCase());

  /// سبب امتناعنا عن الجلب — أو `null` إن كان الجهاز صالحاً.
  ///
  /// نمتنع صراحةً بدل أن نحاول ونفشل: كلّ محاولة فاشلة تحجز خانةً من
  /// ستّ وتنتظر مهلتها كاملةً.
  static String? skipReason(NetworkDevice d) {
    if (d.lastStatus == 'offline') return 'معطّل';
    if (!d.hasCredentials) return 'بلا بيانات دخول';
    if (!supports(d.brand)) return 'لا مقاييس لهذه العلامة';
    return null;
  }

  /// يفتح جلسةً ويُعيد ثلاثة مقاييس. يرمي عند الفشل.
  static Future<List<Vital>> fetch(NetworkDevice d) async {
    final creds = await NetworkDevicesApi.getCredentials(d.id);
    switch (d.brand.toLowerCase()) {
      case 'mikrotik':
        return _mikrotik(d, creds);
      case 'ubnt':
        return _ubnt(d, creds);
      case 'mimosa':
        return _mimosa(d, creds);
      default:
        throw StateError('علامة غير مدعومة: ${d.brand}');
    }
  }

  // ── ميكروتك: معالج · ذاكرة · حرارة ───────────────────────────────

  static Future<List<Vital>> _mikrotik(
      NetworkDevice d, Map<String, dynamic> creds) async {
    final user = (creds['user'] ?? '').toString();
    final pass = (creds['pass'] ?? '').toString();
    if (user.isEmpty || pass.isEmpty) throw StateError('بيانات دخول ناقصة');

    final s = await MikrotikApi.fetchStats(
      ip: d.ip,
      port: d.apiPort ?? 8728,
      user: user,
      pass: pass,
    );
    return [
      Vital(
        label: 'المعالج',
        value: '${s.cpuLoad}',
        unit: '%',
        tone: Grade.percentLowerBetter(s.cpuLoad),
      ),
      Vital(
        label: 'الذاكرة',
        value: '${s.memUsedPercent}',
        unit: '%',
        tone: Grade.percentLowerBetter(s.memUsedPercent),
      ),
      // الحرارة غير متوفّرة على كلّ الطُرُز (CCR2116 مثلاً بلا مجسّ).
      // نُظهر شرطةً لا صفراً — الصفر رقمٌ يكذب.
      s.temperature == null
          ? Vital.empty.copyLabel('الحرارة')
          : Vital(
              label: 'الحرارة',
              value: '${s.temperature}',
              unit: '°',
              tone: Grade.temperature(s.temperature),
            ),
    ];
  }

  // ── UBNT: الإشارة · المعالج · الحرارة ────────────────────────────

  static Future<List<Vital>> _ubnt(
      NetworkDevice d, Map<String, dynamic> creds) async {
    final user = (creds['user'] ?? '').toString();
    final pass = (creds['pass'] ?? '').toString();
    if (user.isEmpty || pass.isEmpty) throw StateError('بيانات دخول ناقصة');

    final s = await UbntApi.fetchStats(
      ip: d.ip,
      port: d.apiPort ?? 22,
      user: user,
      pass: pass,
    );
    final w = s.wireless;
    return [
      // نقطة الوصول لا إشارة لها (هي المصدر) — والصفر هنا يعني «غير
      // متوفّر» لا «إشارة صفر dBm»، وهي قيمة ممتازة لو صُدّقت.
      (w == null || w.signal == 0)
          ? Vital.empty.copyLabel('الإشارة')
          : Vital(
              label: 'الإشارة',
              value: '${w.signal}',
              unit: 'dBm',
              tone: Grade.signal(w.signal),
            ),
      Vital(
        label: 'المعالج',
        value: '${s.host.cpuload}',
        unit: '%',
        tone: Grade.percentLowerBetter(s.host.cpuload),
      ),
      s.host.temperature == 0
          ? Vital.empty.copyLabel('الحرارة')
          : Vital(
              label: 'الحرارة',
              value: '${s.host.temperature}',
              unit: '°',
              tone: Grade.temperature(s.host.temperature),
            ),
    ];
  }

  // ── ميموزا: قدرة الاستقبال · معدّل الاستقبال · الحرارة ───────────

  static Future<List<Vital>> _mimosa(
      NetworkDevice d, Map<String, dynamic> creds) async {
    final community =
        (creds['community'] ?? creds['user'] ?? 'public').toString();
    final s = await MimosaApi.fetchStats(
      host: d.ip,
      port: d.apiPort ?? 161,
      community: community,
    );
    return [
      s.totalRxPowerDbm == null
          ? Vital.empty.copyLabel('الاستقبال')
          : Vital(
              label: 'الاستقبال',
              value: s.totalRxPowerDbm!.toStringAsFixed(0),
              unit: 'dBm',
              tone: Grade.rxPower(s.totalRxPowerDbm),
            ),
      s.phyRxRateMbps == null
          ? Vital.empty.copyLabel('معدّل RX')
          : Vital(
              label: 'معدّل RX',
              value: '${s.phyRxRateMbps}',
              unit: 'M',
              tone: Grade.speedMbps(s.phyRxRateMbps),
            ),
      s.temperatureC == null
          ? Vital.empty.copyLabel('الحرارة')
          : Vital(
              label: 'الحرارة',
              value: s.temperatureC!.toStringAsFixed(0),
              unit: '°',
              tone: Grade.temperature(s.temperatureC),
            ),
    ];
  }
}

extension on Vital {
  Vital copyLabel(String l) => Vital(label: l, value: value, tone: tone);
}

/// مخزن المقاييس — مُنبّه لكلّ جهاز على حدة.
///
/// ⚠️ مُنبّهٌ لكلّ بطاقة، لا `setState` على الشاشة كلّها: الجدار قد يحمل
/// ثمانين بطاقة، وإعادة بنائها جميعاً كلّما وصلت قيمةُ واحدةٍ تُسقط
/// إطارات التمرير — وهو ما يُفترض بهذه الميزة أن تتجنّبه أصلاً.
class VitalsStore {
  final Map<int, ValueNotifier<VitalsState>> _byId = {};

  ValueNotifier<VitalsState> of(int deviceId) =>
      _byId.putIfAbsent(deviceId, () => ValueNotifier(VitalsState.idle));

  void set(int deviceId, VitalsState s) => of(deviceId).value = s;

  void dispose() {
    for (final n in _byId.values) {
      n.dispose();
    }
    _byId.clear();
  }
}
