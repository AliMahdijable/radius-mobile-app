import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// حارس كاش فحص الأجهزة.
///
/// الشكوى التي وُلد منها هذا الاختبار (2026-08-30): «النظام يفحص مرّتين
/// — مرّة بالواجهة ومرّة عند فتح كارت المشترك». السبب أنّ الكارت كان
/// يُطلق فحصاً كاملاً بلا سؤال الكاش، بينما شريحة القائمة تقرأه قراءةً
/// متزامنة. الفحص عمليّة شبكيّة على جهاز في شبكة العميل — تكراره ليس
/// بطئاً فحسب بل استهلاك موارد على جهاز لا نملكه.
///
/// `peek` هي البوّابة التي يعتمد عليها الكارت والموجة معاً، فكسرها
/// يُعيد الازدواج صامتاً: لا خطأ، لا اختبار ساقط، فقط فحص مضاعف.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('peek يقرأ ما استُعيد من القرص ويميّز المجهول', () async {
    final now = DateTime.now().toIso8601String();
    SharedPreferences.setMockInitialValues({
      'device_probe.cache.v1': jsonEncode({
        '10.0.0.5': {
          'at': now,
          'snap': {'k': 'ont', 'ip': '10.0.0.5'},
        },
        '10.0.0.6': {
          'at': now,
          'snap': {'k': 'ubiquiti', 'ip': '10.0.0.6'},
        },
      }),
    });

    await DeviceProbeApi.hydrateFromPrefs();

    // ① المفحوص يُعرف فوراً وبلا انتظار — هذا ما يمنع الدوّارة الثانية.
    final hit = DeviceProbeApi.peek(ip: '10.0.0.5');
    expect(hit, isNotNull, reason: 'نتيجة محفوظة لم تُقرأ — الكارت سيفحص ثانيةً');
    expect(hit!.snap, isNotNull);
    expect(hit.stale, isFalse, reason: 'مُخزَّنة الآن فلا يجوز عدّها قديمة');

    // ② والـIP الخام كذلك عبر الواجهة القديمة
    expect(DeviceProbeApi.cached('10.0.0.5'), isNotNull);
    expect(DeviceProbeApi.cached('10.0.0.6'), isNotNull);

    // ③ المجهول يبقى مجهولاً — وإلّا تخطّت الموجة أجهزة لم تُفحص قطّ
    expect(DeviceProbeApi.peek(ip: '10.0.0.99'), isNull);
    expect(DeviceProbeApi.peek(username: 'lam-yufhas'), isNull);
    expect(DeviceProbeApi.peek(), isNull);
    expect(DeviceProbeApi.peek(ip: '   '), isNull,
        reason: 'عنوان فارغ ليس مفتاحاً صالحاً');

    // ④ الترشيح الذي تعتمده الموجة: تُفحص الأجهزة المجهولة وحدها
    const targets = [
      (username: 'a', ip: '10.0.0.5'),
      (username: 'b', ip: '10.0.0.6'),
      (username: 'c', ip: '10.0.0.99'),
      (username: 'd', ip: ''),
    ];
    final toProbe = targets
        .where((t) => DeviceProbeApi.peek(username: t.username, ip: t.ip) == null)
        .toList();
    expect(toProbe.map((t) => t.username), ['c', 'd'],
        reason: 'الموجة تُعيد فحص أجهزة معروفة أصلاً');
  });

  test('البيانات التالفة تُمسح ولا تُسقط الإقلاع', () async {
    // نفس المسار الذي كان يفشل كلّ boot قبل أن يُلتقط الاستثناء.
    SharedPreferences.setMockInitialValues({
      'device_probe.cache.v1': 'ليست JSON',
    });
    await expectLater(DeviceProbeApi.hydrateFromPrefs(), completes);
  });
}
