import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/device_config_api.dart';
import 'package:rad_mysvcs/api/device_probe_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/device_health.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim_el/sim_harness.dart';

/// «نسخ كلّ المعلومات» ينسخ ما يرسمه كارت الجهاز **الآن** — لا ما في مخزن
/// الفحص.
///
/// 🐛 الكارت يُبقي آخر قراءةٍ ناجحة معروضةً إن فشل فحصٌ صامتٌ بعدها (التحديث
/// المُجبَر عند الفتح، ونبضة الإشارة كلّ عشر ثوانٍ، وسقف الخمس عشرة ثانية
/// على رابطٍ ضعيف)، بينما `DeviceProbeApi` يحفظ ذلك الفشل `null` — فكان
/// النسخ الكلّيّ يُسقط قراءات الجهاز وهي على الشاشة، وهو بالضبط جهازُ رابطٍ
/// ضعيف يُفحص لأنّه مشكوكٌ فيه.
///
/// ملفٌّ مستقلّ لأنّ استعادة المخزن من القرص (`hydrateFromPrefs`) تجري مرّةً
/// واحدة في العزلة.
const _ip = '10.100.11.254';

const _ont = DeviceHealthSnapshot(
  kind: DeviceKind.ont,
  ip: _ip,
  ont: OntOpticalInfo(
    txPower: '2.31',
    rxPower: '-21.55',
    voltage: '3300',
    temperature: '45',
    bias: '10',
    sendStatus: 'OK',
  ),
);

void main() {
  setUpAll(simSetUpAll);

  testWidgets('🚨 فحصٌ صامتٌ فشل: الكارت يُبقي القراءة، والنسخ يضمّها', (t) async {
    final server = await simSetUp();
    SubscribersApi.clearAllCaches();
    DeviceConfigApi.clearAllCaches();
    await DeviceProbeApi.clearAllCaches();
    PermissionsService.debugSet(isEmployee: false);
    addTearDown(PermissionsService.debugReset);
    server.reply('GET', '/api/subscribers/user7/device', 200, {
      'success': true,
      'device': {'notes': 'فوق السطح'},
    });

    // قراءةٌ ناجحة لجهاز الجلسة قبل دقيقة — كما تتركها موجة القائمة. والفحص
    // المُجبَر عند الفتح يفشل هنا حتماً: عميل HTTP في الاختبار يردّ 400.
    final at = DateTime.now().subtract(const Duration(minutes: 1));
    SharedPreferences.setMockInitialValues({
      'device_probe.cache.v1': jsonEncode({
        _ip: {'at': at.toIso8601String(), 'snap': _ont.toJson()},
      }),
    });
    await DeviceProbeApi.hydrateFromPrefs();
    expect(DeviceProbeApi.peek(ip: _ip)?.snap, isNotNull);

    final clips = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clips.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    final sub = Subscriber.fromJson({
      'idx': '7',
      'username': 'user7',
      'firstname': 'علي',
      'lastname': 'حسن',
      'profile_name': '10M-Unlimited',
      'expiration': '2026-12-20 14:30:00',
      'online_status': 1,
      'enabled': 1,
      'ip': _ip,
      'session_time': 3600,
      'download': 1048576,
      'upload': 1048576,
    });
    await pumpSim(t, const SimVariant(390, dark: false),
        home: (_) => SubscriberDetailScreen(sub: sub), settle: false);
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 500));
    }

    // الشرط الذي كان يُسقط القراءة: المخزن حفظ الفشل فوق القراءة الناجحة…
    for (final hit in [
      DeviceProbeApi.peek(username: 'user7'),
      DeviceProbeApi.peek(ip: _ip),
    ]) {
      expect(hit, isNotNull, reason: 'الفحص المُجبَر لم يُخزَّن بعد');
      expect(hit!.snap, isNull,
          reason: 'الفحص المُجبَر لم يفشل — الاختبار لا يفحص شيئاً');
    }
    // …والكارت ما زال يرسم القراءة الناجحة.
    expect(simText('Huawei ONT'), findsOneWidget);
    expect(simText('-21.55 dBm'), findsOneWidget);

    await t.tap(find.byTooltip('copy.all'.tr()));
    await t.pump();
    expect(clips, hasLength(1));
    final lines = clips.single.split('\n');
    String two(int n) => n.toString().padLeft(2, '0');
    expect(
      lines,
      containsAllInOrder([
        'نوع الجهاز: Huawei ONT',
        'RX Power: -21.55 dBm',
        'TX Power: 2.31 dBm',
        'الفولتية: 3300 mV',
        'الحرارة: 45 °C',
        'حالة الليف: OK',
        // وقت القراءة المعروضة نفسها، لا وقت الفحص الفاشل.
        'وقت قراءة الجهاز: ${at.year}/${two(at.month)}/${two(at.day)} '
            '${two(at.hour)}:${two(at.minute)}',
        'ملاحظة الجهاز: فوق السطح',
      ]),
    );

    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 4));
  });
}
