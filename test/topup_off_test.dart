import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/self_deposit_api.dart';
import 'package:rad_mysvcs/screens/more_modules_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/services/self_deposit_pending.dart';
import 'package:rad_mysvcs/services/self_deposit_sync.dart';

import 'sim_el/sim_harness.dart';

/// «شحن رصيد الصفحة» مطفأٌ على الخادم افتراضيّاً (`pro_settings.self_deposit`).
///
/// نسخة 3.0.3 تنزل للمتجرين قبل أن يُفتح المفتاح لأحد — فما دام مطفأً لا يظهر
/// منها **شيء**: لا بطاقة ولا قفل ولا «متوقّف مؤقّتاً»، لكلّ فاعلٍ (مالك،
/// موظّف) ولكلّ مزوّد (ساس، ايرث لنك، المشروع الوطنيّ)، وكذلك أمام خادمٍ أقدم
/// بلا المسار أو ردٍّ فارغ أو انقطاع. ولا نداء دفعٍ يخرج: سؤالٌ واحد «probe»
/// للبطاقة وحده، والتسليم الخلفيّ بلا قيودٍ معلّقة لا يطرق الخادم.
void main() {
  const v = SimVariant(390, dark: false);
  const optionsPath = '/api/v2/self-deposit/options';
  late SimServer server;

  setUpAll(simSetUpAll);

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
    SelfDepositState.reset();
    SelfDepositSync.debugReset();
  });

  Future<void> setUpActor({required String adminId, String? provider, bool employee = false}) async {
    server = await simSetUp(secure: {'auth.admin_id': adminId});
    ProviderService.debugSet(provider);
    PermissionsService.debugSet(isEmployee: employee);
    SelfDepositState.reset();
    SelfDepositSync.debugReset();
    // كما في main.dart: الاستماع للبطاقة يطلق التسليم الخلفيّ أيضاً.
    SelfDepositSync.install();
  }

  /// لا أثر للميزة في «قوائم أخرى»، ولا نداء لها سوى سؤال البطاقة.
  Future<void> expectNothing(WidgetTester t) async {
    await pumpSim(t, v, home: (_) => const MoreModulesScreen());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('شحن رصيد الصفحة', skipOffstage: false), findsNothing);
    expect(find.byIcon(LucideIcons.banknoteArrowUp, skipOffstage: false), findsNothing);
    expect(find.textContaining('زين كاش', skipOffstage: false), findsNothing);
    expect(find.textContaining('متوقّف مؤقّتاً', skipOffstage: false), findsNothing);
    expect(SelfDepositState.visible, isFalse);
    final probes = server.calls('GET', optionsPath);
    expect(probes.length, lessThanOrEqualTo(1));
    for (final p in probes) {
      expect(p.queryParameters['probe'], 1, reason: 'سؤال البطاقة بلا نداءٍ للساس');
    }
    final other = [
      for (final r in server.requests)
        if (r.path.startsWith('/api/v2/self-deposit') && r.path != optionsPath) '${r.method} ${r.path}',
    ];
    expect(other, isEmpty, reason: 'لا طلب دفعٍ ولا تسليم والمفتاح مطفأ');
    await t.pump(const Duration(seconds: 3));
  }

  const off = {'success': true, 'enabled': false};

  group('المفتاح مطفأ (الافتراضيّ في الإنتاج): لا شيء جديد', () {
    testWidgets('مالك ساس', (t) async {
      await setUpActor(adminId: '2251');
      server.reply('GET', optionsPath, 200, off);
      await expectNothing(t);
    });

    testWidgets('موظّف ساس', (t) async {
      await setUpActor(adminId: '2251', employee: true);
      server.reply('GET', optionsPath, 200, off);
      await expectNothing(t);
    });

    testWidgets('مالك ايرث لنك', (t) async {
      await setUpActor(adminId: 'earthlink:5', provider: 'earthlink');
      server.reply('GET', optionsPath, 200, off);
      await expectNothing(t);
    });

    testWidgets('موظّف ايرث لنك (٤٠٣ بلا كلام الميزة)', (t) async {
      await setUpActor(adminId: 'earthlink:5', provider: 'earthlink', employee: true);
      server.reply('GET', optionsPath, 403,
          {'success': false, 'code': 'OWNER_ONLY', 'message': 'هذه العمليّة لصاحب الحساب فقط'});
      await expectNothing(t);
    });

    testWidgets('المشروع الوطنيّ', (t) async {
      await setUpActor(adminId: 'ftth-iq:9', provider: 'ftth');
      server.reply('GET', optionsPath, 200, off);
      await expectNothing(t);
    });
  });

  group('خادمٌ لا يعرف الميزة: لا شيء', () {
    testWidgets('خادمٌ أقدم بلا المسار (٤٠٤)', (t) async {
      await setUpActor(adminId: '2251');
      await expectNothing(t);
    });

    testWidgets('ردٌّ فارغ بلا كلام الميزة (وسيط ايرث لنك)', (t) async {
      await setUpActor(adminId: 'earthlink:5', provider: 'earthlink');
      server.reply('GET', optionsPath, 200, {'success': true});
      await expectNothing(t);
    });

    testWidgets('انقطاع', (t) async {
      await setUpActor(adminId: '2251');
      server.on('GET', optionsPath, simTimeout);
      await expectNothing(t);
    });
  });

  Future<void> bootAndWait(WidgetTester t) async {
    SelfDepositSync.debugReset();
    SelfDepositSync.start();
    await t.pump(const Duration(seconds: 6));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 150));
    }
  }

  testWidgets('الإقلاع (SelfDepositSync.start) بلا قيودٍ معلّقة لا يطرق الخادم', (t) async {
    await setUpActor(adminId: '2251');
    await bootAndWait(t);
    expect(SelfDepositSync.lastReport, isNull);
    expect(server.requests, isEmpty);
  });

  // ضابطٌ للاختبار السابق: الإقلاع يجري فعلاً بعد ثوانٍ (فخلوّه من الطلبات
  // ليس لأنّه لم يجرِ) — ويسلّم الرجوع الملتقط مهما كان المفتاح.
  testWidgets('الإقلاع بقيدٍ ملتقط: يسلّمه بعد ثوانٍ بلا سؤال options', (t) async {
    await setUpActor(adminId: '2251');
    await SelfDepositPendingStore.put(SelfDepositPending(
      psid: 'p1',
      adminId: '2251',
      createdAt: DateTime.now(),
      amount: 25000,
      returnUrl: 'https://sas.x.iq/#/zaincash/process?token=p1.aaaa.bbbb',
    ));
    server.reply('POST', '/api/v2/self-deposit/complete', 200, {
      'success': true,
      'psid': 'p1',
      'status': 'success',
      'final': true,
      'received': true,
      'credited': 25000,
    });
    await bootAndWait(t);
    expect(server.calls('POST', '/api/v2/self-deposit/complete'), hasLength(1));
    expect(server.calls('GET', optionsPath), isEmpty);
    expect(await SelfDepositPendingStore.forAdmin('2251'), isEmpty);
  });

  testWidgets('جولة التسليم بلا قيودٍ معلّقة: لم تُجرَ، ولا طلب', (t) async {
    await setUpActor(adminId: '2251');
    final rep = await SelfDepositSync.run(force: true);
    expect(rep.ran, isFalse);
    expect(server.requests, isEmpty);
  });
}
