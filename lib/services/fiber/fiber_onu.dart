import 'package:flutter/foundation.dart';

import '../../api/vsol_olt_api.dart';
import '../../models/fiber_network.dart';
import 'fiber_band.dart';

/// لماذا سقط الجهاز — كما يقوله الأولت نفسه، وإلّا «غير معروف». لا تخمين: بلا سببٍ من الأولت لا يُقال «قطع ليف».
enum FiberDropReason {
  /// انطفاء كهرباء عند المشترك (Dying Gasp / power-off) — لا يحتاج فنّيّاً.
  power,

  /// فقدان الضوء (LOS / wire-down) — خللٌ بالليف أو الوصلة.
  fiber,

  /// سببٌ آخر يذكره الأولت (فصلٌ يدويّ، تحديث، تسجيلٌ مرفوض…).
  other,
  unknown,
}

String fiberReasonLabel(FiberDropReason r) => switch (r) {
      FiberDropReason.power => 'انطفاء كهرباء',
      FiberDropReason.fiber => 'فقدان ضوء',
      FiberDropReason.other => 'فصلٌ آخر',
      FiberDropReason.unknown => 'سببٌ غير معروف',
    };

/// اسم منفذ PON للعرض: «PON 3»، ومعه البطاقة حين لا تكون صفراً «PON 1/3».
String fiberPonDisplay(String pon) {
  final m = RegExp(r'^(?:[EG]PON)?(\d+)/(\d+)$', caseSensitive: false).firstMatch(pon);
  if (m == null) return pon;
  final slot = int.parse(m.group(1)!);
  final port = int.parse(m.group(2)!);
  return slot == 0 ? 'PON $port' : 'PON $slot/$port';
}

/// رقم الـONU للعرض: «ONU 3:2».
String fiberOnuDisplay(VsolOnu o) => o.slot == 0 ? 'ONU ${o.ponPort}:${o.onuId}' : 'ONU ${o.slot}/${o.ponPort}:${o.onuId}';

/// رقم الـONU من مفتاحها المحفوظ (`EPON0/3:2` ⇒ «ONU 3:2») — لجهازٍ لم يُقرأ الأولت بعد.
String fiberOnuKeyDisplay(String key) {
  final m = RegExp(r'^[EG]PON(\d+)/(\d+):(\d+)$', caseSensitive: false).firstMatch(key);
  if (m == null) return key;
  final slot = int.parse(m.group(1)!);
  return slot == 0 ? 'ONU ${m.group(2)}:${m.group(3)}' : 'ONU $slot/${m.group(2)}:${m.group(3)}';
}

/// منفذ PON لـONU: `EPON0/3` من `EPON0/3:2`.
String fiberPonOf(VsolOnu o) => '${o.technology.prefix}${o.slot}/${o.ponPort}';

/// قراءةٌ حيّة لـONU واحدة مع ما زاده قارئ الألياف: سبب السقوط ولحظته والمسافة.
@immutable
class FiberOnuLive {
  const FiberOnuLive({
    required this.onu,
    this.reason,
    this.changedAt,
    this.distanceM,
  });

  final VsolOnu onu;

  /// سبب آخر سقوط (للمفصول وحده) — من الأولت.
  final FiberDropReason? reason;

  /// لحظة آخر تغيّرٍ للحالة (سقوطٌ للمفصول وعودةٌ للمتّصل) بحساب `ifLastChange` من وقت تشغيل الأولت — بساعة الهاتف.
  final DateTime? changedAt;

  /// المسافة من الأولت بالمتر (حيث يعطيها الأولت بوحدةٍ ثابتة).
  final double? distanceM;

  String get key => onu.label;
  String get pon => fiberPonOf(onu);
  bool get online => onu.online;
  String? get ident => fiberIdent(onu.serial ?? onu.mac);
  String get display => fiberOnuDisplay(onu);

  /// قراءة الضوء ما دام الجهاز متّصلاً ومعقولة — وإلّا `null` (لا ضوء لمفصول، ولا رقم كاذب).
  double? get rx {
    if (!onu.online) return null;
    final v = onu.reading?.rxDbm;
    return FiberBands.plausible(v) ? v : null;
  }

  double? get tx => onu.online ? onu.reading?.txDbm : null;
  double? get tempC => onu.online ? onu.reading?.tempC : null;
  double? get voltV => onu.online ? onu.reading?.voltV : null;

  FiberOnuLive copyWith({
    VsolOnu? onu,
    FiberDropReason? reason,
    bool clearReason = false,
    DateTime? changedAt,
    double? distanceM,
  }) =>
      FiberOnuLive(
        onu: onu ?? this.onu,
        reason: clearReason ? null : (reason ?? this.reason),
        changedAt: changedAt ?? this.changedAt,
        distanceM: distanceM ?? this.distanceM,
      );
}
