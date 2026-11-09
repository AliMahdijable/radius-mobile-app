import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_check_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';

import 'visual_perm/visual_perm_harness.dart';

/// رادار صفحة المشتركين والصفحة تفحص (١٠ نوفمبر — المالك: «الافضل سوي»): كان مقفولاً طول موجة الصفحة (منذ ٢٩ آب)؛ الآن
/// يُفتح «الفحص العامّ» أثناءها والدوّارة أيقونته، ويعرض «يفحص… n من N» للموجة نفسها — فتحه لا يبدأ موجةً جديدة (كانت
/// تترك الجارية فيرجع العدّاد صفراً) ولا يسأل الأجهزة من جديد — ثمّ «انتهى الفحص» حين تنتهي.
void main() {
  setUpAll(visualSetUpAll);

  testWidgets('الرادار يُفتح والموجة جارية: «يفحص… n من N» للموجة نفسها ثمّ «انتهى الفحص»', (t) async {
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);

    // المتّصلون بعناوين (أسماءٌ تجريبيّة من الخادم الوهميّ): الأوّل يجيب فوراً «ما ردّ»، والباقون معلّقون حتى يُكملهم
    // الاختبار
    final savedIps = [for (final m in fixtureSubscribers) (has: m.containsKey('ip'), ip: m['ip'])];
    addTearDown(() {
      for (var i = 0; i < fixtureSubscribers.length; i++) {
        savedIps[i].has ? fixtureSubscribers[i]['ip'] = savedIps[i].ip : fixtureSubscribers[i].remove('ip');
      }
    });
    for (final m in fixtureSubscribers) {
      if (m['online_status'] == 1) m['ip'] = '10.9.9.${m['idx']}';
    }
    final hang = Completer<DeviceHealthSnapshot?>();
    var calls = 0;
    DeviceProbeApi.debugRunProbe = (ip) {
      calls++;
      return ip == '10.9.9.1' ? Future.value(null) : hang.future;
    };
    DeviceProbeApi.debugConnectTime = (_) async => null;
    DeviceProbeApi.debugCaps(probe: const Duration(minutes: 10), zteExtra: Duration.zero);
    addTearDown(() {
      if (!hang.isCompleted) hang.complete(null);
      DeviceProbeApi.debugRunProbe = null;
      DeviceProbeApi.debugConnectTime = null;
      DeviceProbeApi.debugCaps(probe: const Duration(seconds: 15), zteExtra: const Duration(seconds: 15));
    });
    // الإعداد أوّلاً: ذاكرة التفضيلات الوهميّة قبل مسح كاش الفحص (يكتب إليها)
    await visualSetUp(s1bSasOwner);
    await DeviceProbeApi.clearAllCaches();
    DeviceConfigApi.clearAllCaches();
    await pumpVisual(t, phone, home: (_) => const SubscribersScreen());
    await settle(t, seconds: 2);

    final radar = find.byKey(const ValueKey('subs-general-check'));
    expect(find.descendant(of: radar, matching: find.byType(CircularProgressIndicator)), findsOneWidget,
        reason: 'الموجة جارية — الدوّارة أيقونته');
    expect(calls, 4, reason: 'أجهزة المتّصلين الأربعة سُئلت');

    final tappedAt = DateTime.now();
    await t.tap(radar);
    await settle(t, seconds: 2);
    expect(find.byType(SubscribersCheckScreen), findsOneWidget, reason: 'كان الرادار مقفولاً طول الموجة');
    String bar() => t.widget<Text>(find.byKey(const ValueKey('subs-check-progress-text'))).data!;
    final total = fixtureSubscribers.length;
    expect(bar(), matches(RegExp('^يفحص… \\d+ من $total\$')), reason: 'عدّاد الموجة الجارية لا موجةٍ جديدة');
    final wave = t.widget<SubscribersCheckScreen>(find.byType(SubscribersCheckScreen)).wave!.value;
    expect(wave.running, isTrue);
    expect(wave.startedAt!.isBefore(tappedAt), isTrue, reason: 'الفتح لا يبدأ موجةً تترك الجارية');
    expect(calls, 4, reason: 'الفتح لا يسأل الأجهزة من جديد');

    hang.complete(null);
    await settle(t, seconds: 2);
    expect(bar(), 'انتهى الفحص — $total مشترك');
    expect(calls, 4);

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 6));
    await visualTearDown();
  });
}
