import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/self_deposit_api.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/screens/assistant/assistant_sheet.dart';
import 'package:rad_mysvcs/screens/more_modules_screen.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/ai_consent.dart';
import 'package:rad_mysvcs/services/app_resumed_signal.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «كيف أسوّي؟» في «قوائم أخرى» — المساعد الذكيّ مطفأٌ افتراضيّاً على
/// الخادم (`pro_settings.ai_assistant`)، فنسخة 3.0.4 تنزل للمتجرين قبل أن
/// يُفتح لأحد: ما دام مطفأً لا يظهر **شيء** — لا بطاقة ولا قفل — ولا نداء
/// سوى سؤال الحالة. ومفتوحاً: البطاقة أوّلاً، ولموظّفٍ بلا الصلاحيّة مقفلةٌ
/// بمكانها (لا مخفيّة) والنقر لا يطلب شيئاً.
void main() {
  const v = SimVariant(390, dark: false);
  const statusPath = '/api/v2/ai/status';
  late SimServer server;

  setUpAll(simSetUpAll);

  tearDown(() {
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
    SelfDepositState.reset();
    AiAssistantState.reset();
    AiAssistantState.now = DateTime.now;
    AiConsent.debugReset();
  });

  Future<void> setUpActor(
      {String adminId = '2251',
      String? provider,
      bool employee = false}) async {
    server = await simSetUp(secure: {'auth.admin_id': adminId});
    ProviderService.debugSet(provider);
    PermissionsService.debugSet(isEmployee: employee);
    SelfDepositState.reset();
    AiAssistantState.reset();
    AiConsent.debugAccepted = true; // الموافقة في assistant_sheet_test
  }

  Future<void> pumpMore(WidgetTester t) async {
    await pumpSim(t, v, home: (_) => const MoreModulesScreen());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  /// إعادة البناء ثمّ سلسلة السؤال (التخزين الآمن ← Dio ← الخادم الوهميّ).
  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
  }

  List<String> aiPosts() => [
        for (final r in server.requests)
          if (r.path.startsWith('/api/v2/ai/') && r.path != statusPath)
            '${r.method} ${r.path}',
      ];

  Future<void> expectNothing(WidgetTester t) async {
    await pumpMore(t);
    expect(find.text('كيف أسوّي؟', skipOffstage: false), findsNothing);
    expect(
        find.byIcon(LucideIcons.sparkles, skipOffstage: false), findsNothing);
    expect(AiAssistantState.visible, isFalse);
    expect(server.calls('GET', statusPath).length, lessThanOrEqualTo(1));
    expect(aiPosts(), isEmpty);
  }

  const on = {
    'success': true,
    'enabled': true,
    'can_use': true,
    'explain': true,
    'ask': true,
    'quota': {'left': 7, 'limit': 10},
    'suggestions': ['شلون أفعّل مشترك بالكارت؟'],
  };

  group('مطفأ أو غير معروف: لا شيء جديد', () {
    testWidgets('enabled:false (الافتراضيّ في الإنتاج)', (t) async {
      await setUpActor();
      server.reply('GET', statusPath, 200, {'success': true, 'enabled': false});
      await expectNothing(t);
      expect(server.calls('GET', statusPath), hasLength(1),
          reason: 'الاستماع يسأل مرّة');
    });

    testWidgets('خادمٌ أقدم بلا المسار (٤٠٤)', (t) async {
      await setUpActor();
      await expectNothing(t);
    });

    testWidgets('انقطاع', (t) async {
      await setUpActor();
      server.on('GET', statusPath, simTimeout);
      await expectNothing(t);
    });

    testWidgets('مفتوحٌ لـ«اشرحلي» وحده (ask:false) ⇒ لا بطاقة', (t) async {
      await setUpActor();
      server.reply('GET', statusPath, 200,
          Map<String, dynamic>.from(on)..['ask'] = false);
      await expectNothing(t);
    });
  });

  testWidgets(
      'مفتوح ⇒ «كيف أسوّي؟» أوّل البطاقات، والنقر يفتح المحادثة بلا سؤال',
      (t) async {
    await setUpActor();
    server.reply('GET', statusPath, 200, on);
    await pumpMore(t);
    final ai = find.text('كيف أسوّي؟');
    expect(ai, findsOneWidget);
    final reports = find.text('التقارير');
    if (reports.evaluate().isNotEmpty) {
      expect(t.getTopLeft(ai).dy, lessThan(t.getTopLeft(reports).dy),
          reason: 'الأولى');
    }
    await t.tap(ai);
    await t.pumpAndSettle();
    expect(find.byType(AssistantSheet), findsOneWidget);
    expect(find.text('شلون أفعّل مشترك بالكارت؟'), findsOneWidget);
    expect(aiPosts(), isEmpty, reason: 'لا سؤال قبل أن يكتب المدير');
  });

  testWidgets(
      'شُغّل من الخادم بعد فتح الشاشة ⇒ يظهر بالعودة للتطبيق (بعد المهلة)',
      (t) async {
    await setUpActor();
    var at = DateTime(2026, 10, 19, 10);
    AiAssistantState.now = () => at;
    server.reply('GET', statusPath, 200, {'success': true, 'enabled': false});
    await pumpMore(t);
    expect(find.text('كيف أسوّي؟'), findsNothing);
    expect(server.calls('GET', statusPath), hasLength(1));
    // المالك شغّله الآن؛ والعودة قبل المهلة لا تسأل.
    server.reply('GET', statusPath, 200, on);
    AppResumedSignal.bump();
    await settle(t);
    expect(server.calls('GET', statusPath), hasLength(1), reason: 'المهلة');
    at = at.add(const Duration(minutes: 6));
    AppResumedSignal.bump();
    await settle(t);
    expect(server.calls('GET', statusPath), hasLength(2));
    expect(find.text('كيف أسوّي؟'), findsOneWidget);
  });

  testWidgets('أوّل سؤالٍ فشل ⇒ يُعاد بعد التبريد عند أوّل إعادة بناء',
      (t) async {
    await setUpActor();
    var at = DateTime(2026, 10, 19, 10);
    AiAssistantState.now = () => at;
    server.on('GET', statusPath, simTimeout);
    await pumpMore(t);
    expect(find.text('كيف أسوّي؟'), findsNothing);
    server.reply('GET', statusPath, 200, on);
    at = at.add(const Duration(seconds: 31));
    AppResumedSignal.bump();
    await settle(t);
    expect(server.calls('GET', statusPath), hasLength(2));
    expect(find.text('كيف أسوّي؟'), findsOneWidget);
  });

  testWidgets('مالك ايرث لنك ⇒ البطاقة نفسها (لكلّ المزوّدين)', (t) async {
    await setUpActor(adminId: 'earthlink:5', provider: 'earthlink');
    server.reply('GET', statusPath, 200, on);
    await pumpMore(t);
    expect(find.text('كيف أسوّي؟'), findsOneWidget);
  });

  testWidgets('🚨 موظّفٌ بلا الصلاحيّة ⇒ مقفلةٌ بمكانها، والنقر رسالةٌ بلا طلب',
      (t) async {
    await setUpActor(employee: true);
    server.reply('GET', statusPath, 200, {
      'success': true,
      'enabled': true,
      'can_use': false,
      'reason': 'no_permission',
      'locked_text': 'ما عندك صلاحيّة المساعد — اطلبها من مديرك',
    });
    await pumpMore(t);
    final ai = find.text('كيف أسوّي؟');
    expect(ai, findsOneWidget);
    expect(find.byType(PermLockIcon), findsWidgets);
    final before = server.requests.length;
    await t.tap(ai);
    await t.pump();
    expect(find.byType(AssistantSheet), findsNothing);
    expect(find.textContaining('اطلبها من مديرك'), findsOneWidget);
    expect(server.requests.length, before, reason: 'المقفل لا يجلب');
    await t.pump(const Duration(seconds: 3));
  });
}
