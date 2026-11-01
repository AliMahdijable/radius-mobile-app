import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/device_reach.dart';
import '../../core/util/bidi.dart';
import '../../models/network_device.dart';
import '../../theme/colors.dart';

/// سطر الفحص بالكلام — عنوانٌ وتفصيلٌ ونغمة.
@immutable
class DeviceCheckNote {
  const DeviceCheckNote({required this.title, required this.detail, required this.tone, required this.icon});
  final String title;
  final String detail;
  final AppTone tone;
  final IconData icon;

  /// سطرٌ واحد: «العنوان — التفصيل».
  String get line => '$title — $detail';
}

/// ما يقوله «فحص الآن (ping)» للوكيل — مكانٌ واحد للصياغة (شاشة الجهاز، شيت الإضافة/التعديل، البطاقات الكبيرة، البرج).
///
/// المالك (١ نوفمبر): «اذا الجهاز حتى لو ما مضيوف صح المفروض تخلي زر فحص الجهاز بالبنك يرد ويظهر شعار الجهاز يرد بنك اتصال
/// ping تاكد من الاعدادات الجهاز». فالجهاز الذي يردّ على الشبكة وقراءته/خدمته لا تردّ **ليس مفصولاً** — إعداداته هي الخطأ.
class DeviceCheckText {
  DeviceCheckText._();

  /// ما يُراجَع في إعدادات الجهاز بحسب بروتوكوله.
  static String fields(NetworkDevice d) => switch (d.protocol) {
        'snmp' => 'الـcommunity والمنفذ',
        null => 'بروتوكول الإدارة والمنفذ',
        _ => 'اسم المستخدم وكلمة المرور والمنفذ',
      };

  /// «تأكّد من إعدادات الجهاز: اسم المستخدم وكلمة المرور والمنفذ».
  static String checkSettings(NetworkDevice d) => 'تأكّد من إعدادات الجهاز: ${fields(d)}';

  /// «الجهاز يردّ على الاتصال (ping)» — وحين ثبت الردّ بمنفذٍ لا بـping (iOS، أو جهازٌ يحجب ping) يُسمّى المنفذ.
  static String reachableTitle({ReachVia? via, int? port}) =>
      via == ReachVia.port && port != null ? 'الجهاز يردّ على الاتصال (المنفذ $port)' : 'الجهاز يردّ على الاتصال (ping)';

  /// سطر البطاقة الكبيرة والبرج: يردّ على الفحص وقراءته تفشل.
  static String settingsLine(NetworkDevice d) => '${reachableTitle()} — ${checkSettings(d)}';

  /// «لا يردّ على ping» — وحيث لم يُرسل ping أصلاً (iOS) «لا يردّ على الاتصال»: لا نقول ما لم نفعل.
  static String unreachableTitle({required bool icmpTried}) => icmpTried ? 'لا يردّ على ping' : 'لا يردّ على الاتصال';

  static const unreachableHint = 'تأكّد من العنوان والشبكة';

  /// خدمة الإدارة المسجّلة: «SNMP:444» · «API (HTTP):8729» · «منفذ الإدارة 80».
  static String service(NetworkDevice d) {
    final port = d.apiPort ?? d.port;
    return d.protocol != null ? iso('${NetworkDeviceLabels.protocolLabel(d.protocol!)}:$port') : 'منفذ الإدارة $port';
  }

  /// السطر تحت الفحص، أو `null` حين لا شيء يُقال (لم يُفحص بعد، أو يردّ وخدمته وقراءته سليمتان).
  /// [readError] آخر قراءةٍ حيّة فاشلة (اللوحة/البطاقة — `DeviceReadHealth`).
  static DeviceCheckNote? note(NetworkDevice d, DeviceCheck? c, {String? readError}) {
    if (c == null) return null;
    if (!c.reachable) {
      return DeviceCheckNote(
        title: unreachableTitle(icmpTried: c.icmpTried),
        detail: unreachableHint,
        tone: AppTone.danger,
        icon: LucideIcons.wifiOff,
      );
    }
    final svcDown = _serviceDown(d, c);
    if (!svcDown && readError == null) return null;
    return DeviceCheckNote(
      // ثبت الردّ بخدمته المسجّلة (منفذها يقبل والدخول يفشل) ⇒ المنفذ نفسه، فالخطأ في اسم المستخدم/كلمة المرور لا المنفذ.
      title: c.via == ReachVia.service
          ? (d.protocol == 'snmp' ? 'الجهاز يردّ على الاتصال (SNMP)' : reachableTitle(via: ReachVia.port, port: d.apiPort ?? d.port))
          : reachableTitle(via: c.via, port: c.port),
      detail: svcDown ? '${checkSettings(d)} — ${service(d)} لا يردّ' : checkSettings(d),
      tone: AppTone.warning,
      icon: LucideIcons.triangleAlert,
    );
  }

  /// خدمة إدارته المسجّلة لا تردّ — ولجهاز «ICMP فقط» (بلا بروتوكول) لا خدمة تُراجَع: منفذه الافتراضيّ (80) لم يختره أحد.
  static bool _serviceDown(NetworkDevice d, DeviceCheck c) => c.serviceOk == false && d.protocol != null;

  /// نتيجة فحص ما بعد الحفظ في سطرٍ واحد (إشعار الشيت).
  static String afterSave(NetworkDevice d, DeviceCheck c, {required bool created}) {
    final head = created ? 'تمّت إضافة الجهاز' : 'تمّ الحفظ';
    if (!c.reachable) return '$head — ${unreachableTitle(icmpTried: c.icmpTried)}: $unreachableHint';
    final ms = c.latencyMs == null ? '' : ' ${iso('${c.latencyMs} ms')}';
    if (_serviceDown(d, c)) {
      return '$head — ${reachableTitle(via: c.via, port: c.port)}$ms، لكن ${service(d)} لا يردّ: ${checkSettings(d)}';
    }
    return '$head — يردّ على الاتصال$ms';
  }
}
