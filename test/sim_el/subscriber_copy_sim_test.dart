import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_harness.dart';

/// محاكاة «نسخ معلومات كارت المشترك» — زرّ النسخ في الرأس، والوميض
/// والإشعار بعد الضغط المطوّل، وأطول رسائل النسخ الكلّيّ، وصفّه في شيت
/// «المزيد». لكلّ مزوّد، بالعروض الثلاثة والوضعين. اللقطات في
/// `shots/subscriber_copy/`.
const _screen = 'subscriber_copy';

/// متّصلٌ بأرقام جلسة وعنوانٍ مثبَّت — وبلا عنوان جلسة: كارت الجهاز يفحص
/// عنوان الجلسة وحده بالشبكة الحقيقيّة، والمحاكاة لا تلمس الشبكة.
Subscriber _sub({required bool el}) => Subscriber.fromJson({
      'idx': el ? 'earthlink:41' : '7',
      'username': el ? 'ahmed41' : 'unc.thaaer@popq',
      'firstname': 'علي',
      'lastname': 'حسن الموسوي',
      'phone': '9647701234567',
      'profile_name': '10M-Unlimited-30D',
      'profile_id': 7,
      'expiration': '2026-12-20 14:30:00',
      'online_status': 1,
      'enabled': 1,
      'notes': '-135000',
      if (!el) 'parent_username': 'najaf650',
      'package_price': 35000,
      'static_ip': '192.168.100.254',
      'session_time': 970000,
      'download': 5261334938,
      'upload': 1288490188,
    });

void main() {
  late SimServer server;
  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp();
    SubscribersApi.clearAllCaches();
    DeviceConfigApi.clearAllCaches();
    await DeviceProbeApi.clearAllCaches();
    PermissionsService.debugSet(isEmployee: false);
    for (final idx in ['7', 'earthlink:41']) {
      server.reply('GET', '/api/v2/subscribers/$idx/password', 200, {
        'success': true,
        'data': {'password': 'pa55word'},
      });
    }
  });

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  void clipboard(WidgetTester t) {
    t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }

  Future<void> open(WidgetTester t, SimVariant v, {required bool el}) async {
    ProviderService.debugSet(el ? 'earthlink' : null);
    clipboard(t);
    await pumpSim(t, v,
        home: (_) => SubscriberDetailScreen(sub: _sub(el: el)), settle: false);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
  }

  Future<void> done(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await simDrain(t);
  }

  for (final el in [false, true]) {
    final p = el ? 'el' : 'sas';

    simCase(_screen, '${p}_header', (t, v) async {
      await open(t, v, el: el);
      expect(find.byTooltip('copy.all'.tr()), findsOneWidget);
      await simCheck(t, v, _screen, '${p}_header');
      await done(t);
    });

    // الوميض والإشعار معاً: لقطةٌ في منتصف الوميض (٤٥٠ مث).
    simCase(_screen, '${p}_long_press', (t, v) async {
      await open(t, v, el: el);
      await t.longPress(find.text(el ? 'ahmed41' : 'unc.thaaer@popq'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 120));
      expect(find.text('تمّ نسخ اسم المستخدم'), findsOneWidget);
      await simCheck(t, v, _screen, '${p}_long_press');
      await done(t);
    });

    // أطول رسالةٍ للنسخ الكلّيّ (كلمة السرّ مخفيّة) — تلتفّ ولا تُقصّ.
    simCase(_screen, '${p}_copy_all', (t, v) async {
      await open(t, v, el: el);
      await t.tap(find.byTooltip('copy.all'.tr()));
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('copy.all_done_password_hidden'.tr()), findsOneWidget);
      await simCheck(t, v, _screen, '${p}_copy_all');
      await done(t);
    });

    simCase(_screen, '${p}_more_sheet', (t, v) async {
      await open(t, v, el: el);
      await t.tap(find.text('subscribers.more_actions'.tr()));
      await t.pumpAndSettle();
      final row = find.descendant(
          of: find.byType(BottomSheet), matching: find.text('copy.all'.tr()));
      await t.ensureVisible(row);
      await t.pumpAndSettle();
      expect(row, findsOneWidget);
      await simCheck(t, v, _screen, '${p}_more_sheet');
      await done(t);
    });
  }
}
