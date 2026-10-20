import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/models/app_notification.dart';
import 'package:rad_mysvcs/screens/assistant/assistant_consent_sheet.dart';
import 'package:rad_mysvcs/screens/assistant/assistant_sheet.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:rad_mysvcs/screens/notifications/inbox_screen.dart';
import 'package:rad_mysvcs/screens/settings_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/top_actions.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/ai_consent.dart';
import 'package:rad_mysvcs/services/alerts_service.dart';
import 'package:rad_mysvcs/services/app_resumed_signal.dart';
import 'package:rad_mysvcs/services/inbox_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sim_el/sim_harness.dart';
import 'support/ai_status_overlay.dart';
import 'visual_perm/visual_perm_harness.dart';

/// شاشة الأجهزة تطلب صلاحيّة الإشعارات المحلّيّة عند فتحها — لا منصّة في
/// الاختبار، فالمنفّذ الوهميّ يردّ «لا شيء» بدل `LateInitializationError`.
class _NoLocalNotifications extends FlutterLocalNotificationsPlatform {}

/// أزرار الأعلى (٢٠ أكتوبر، طلب المالك): **المساعد الذكيّ · الإشعارات ·
/// الإعدادات** بمكانها نفسه في رأس كلّ تبويب، والمساعد جنب الجرس.
///
/// المساعد يتبع حال الخادم كبطاقة «كيف أسوّي؟» حرفيّاً: مطفأٌ ⇒ لا زرّ؛
/// موظّفٌ بلا الصلاحيّة ⇒ مقفلٌ بمكانه والنقر رسالةٌ بلا طلب؛ وإلّا يفتح الورقة
/// نفسها والموافقة أوّلاً. الخادم وهميّ (لا شبكة ولا نموذج).
void main() {
  setUpAll(() async {
    await simSetUpAll();
    FlutterLocalNotificationsPlatform.instance = _NoLocalNotifications();
  });

  late AiStatusOverlay server;

  /// موظّف ساس بلا «المساعد الذكي» — يعرض المشتركين والتقارير.
  const sasEmployee = Scenario(
    id: 'T_sas_emp',
    title: 'موظّف ساس — بلا المساعد',
    actor: Actor.elEmployee,
    provider: null,
    keys: {
      'subscribers.view': true,
      'reports.financial': true,
      'reports.daily_activations': true,
    },
  );

  final assistant = find.byKey(const ValueKey('top-actions-assistant'));
  final bell = find.byKey(const ValueKey('top-actions-notifications'));
  final gear = find.byKey(const ValueKey('top-actions-settings'));

  Future<void> setUpActor(Scenario s, Map<String, dynamic>? ai) async {
    final inner = await visualSetUp(s);
    server = AiStatusOverlay(inner, status: ai);
    ApiClient.dio.httpClientAdapter = server;
    AiAssistantState.reset();
    AiAssistantState.now = DateTime.now;
    AiConsent.debugReset();
    AlertsService.reset();
  }

  /// يُفكّك الشجرة ويُفرغ المؤقّتات (رسالة القفل، استطلاع المشتركين، فحص
  /// الأجهزة، تبريد الرئيسيّة) ثمّ يُعيد الحال العامّة.
  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 25));
    await visualTearDown();
    AiAssistantState.reset();
    AiConsent.debugReset();
    AlertsService.reset();
    // ⚠️ خارج الوقت الوهميّ: صندوق الإشعارات يسأل المنصّة عن مجلّده، وطلب
    // المنصّة لا يُجاب داخل `testWidgets` فيعلق الاختبار.
    if (InboxService.all.isNotEmpty) await t.runAsync(InboxService.clear);
  }

  /// سلسلة سؤال الحال (الخزنة ← Dio ← الخادم الوهميّ) ثمّ إعادة البناء.
  Future<void> settleFetch(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
  }

  /// رأس تبويبٍ وحده (العنوان + أزرار الأعلى) بعرض [width].
  Future<void> pumpHeader(WidgetTester t, {double width = 390}) async {
    await pumpSim(
      t,
      SimVariant(width, dark: false),
      settle: false,
      home: (_) => const Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: TabHeader(title: 'المشتركون'),
          ),
        ),
      ),
    );
    await settleFetch(t);
    expect(t.takeException(), isNull);
  }

  group('المساعد يتبع حال الخادم كبطاقة «كيف أسوّي؟»', () {
    testWidgets('مطفأ ⇒ لا زرّ للمساعد، والجرس والترس بمكانيهما', (t) async {
      await setUpActor(s1bSasOwner, aiStatusOff);
      await pumpHeader(t);
      expect(assistant, findsNothing);
      expect(find.byIcon(LucideIcons.sparkles), findsNothing);
      expect(bell, findsOneWidget);
      expect(gear, findsOneWidget);
      expect(server.statusCalls, 1, reason: 'الاستماع يسأل مرّة');
      expect(server.aiCalls, isEmpty);
      await finish(t);
    });

    testWidgets('خادمٌ أقدم بلا المسار (٤٠٤) ⇒ لا زرّ كذلك', (t) async {
      await setUpActor(s1bSasOwner, null);
      await pumpHeader(t);
      expect(assistant, findsNothing);
      expect(bell, findsOneWidget);
      expect(gear, findsOneWidget);
      await finish(t);
    });

    testWidgets('مفتوح ⇒ المساعد جنب الجرس (يمينه بالعربيّة) والترس بالزاوية',
        (t) async {
      await setUpActor(s1bSasOwner, aiStatusOn);
      await pumpHeader(t);
      expect(assistant, findsOneWidget);
      expect(
          find.descendant(
              of: assistant, matching: find.byIcon(LucideIcons.sparkles)),
          findsOneWidget);
      expect(find.byType(PermLockIcon), findsNothing, reason: 'لا قفل للمالك');
      // من اليمين: المساعد ← الجرس ← الترس، متجاورةً بفراغٍ واحد.
      final a = t.getRect(assistant);
      final b = t.getRect(bell);
      final g = t.getRect(gear);
      expect(a.left, greaterThan(b.right));
      expect(b.left, greaterThan(g.right));
      expect(a.left - b.right, moreOrLessEquals(b.left - g.right));
      // الترس في الزاوية: على حشوة الرأس من الحافّة اليسرى.
      expect(g.left, moreOrLessEquals(16));
      expect(a.top, g.top);
      expect(b.top, g.top);
      await finish(t);
    });

    testWidgets('🚨 موظّفٌ بلا الصلاحيّة ⇒ بمكانه مقفلاً، والنقر رسالةٌ بلا طلب',
        (t) async {
      await setUpActor(sasEmployee, aiStatusLocked);
      await pumpHeader(t);
      expect(assistant, findsOneWidget, reason: 'مقفلٌ لا مخفيّ');
      expect(find.descendant(of: assistant, matching: find.byType(PermLockIcon)),
          findsOneWidget);
      final before = server.requests.length;
      await t.tap(find.byIcon(LucideIcons.sparkles));
      await t.pump();
      expect(find.byType(AssistantConsentSheet), findsNothing);
      expect(find.byType(AssistantSheet), findsNothing);
      expect(find.textContaining('اطلبها من مديرك'), findsOneWidget);
      expect(server.requests.length, before, reason: 'المقفل لا يجلب');
      await t.pump(const Duration(seconds: 3)); // مؤقّت رسالة القفل
      await finish(t);
    });

    testWidgets('شُغّل من الخادم بعد الفتح ⇒ يظهر بالعودة للتطبيق (بعد المهلة)',
        (t) async {
      await setUpActor(s1bSasOwner, aiStatusOff);
      var at = DateTime(2026, 10, 20, 10);
      AiAssistantState.now = () => at;
      await pumpHeader(t);
      expect(assistant, findsNothing);
      expect(server.statusCalls, 1);
      // المالك شغّله الآن؛ والعودة قبل المهلة لا تسأل.
      server.status = aiStatusOn;
      AppResumedSignal.bump();
      await settleFetch(t);
      expect(server.statusCalls, 1, reason: 'المهلة');
      expect(assistant, findsNothing);
      at = at.add(const Duration(minutes: 6));
      AppResumedSignal.bump();
      await settleFetch(t);
      expect(server.statusCalls, 2);
      expect(assistant, findsOneWidget);
      await finish(t);
    });
  });

  group('النقر يفتح ورقة «كيف أسوّي؟» نفسها — والموافقة أوّلاً', () {
    testWidgets('بلا موافقةٍ سابقة ⇒ الموافقة ثمّ المحادثة، بلا سؤالٍ مرسَل',
        (t) async {
      await setUpActor(s1bSasOwner, aiStatusOn);
      SharedPreferences.setMockInitialValues({});
      await pumpHeader(t);
      await t.tap(find.byIcon(LucideIcons.sparkles));
      await t.pumpAndSettle();
      expect(find.byType(AssistantConsentSheet), findsOneWidget);
      expect(find.byType(AssistantSheet), findsNothing);
      await t.tap(find.text('موافق، كمّل'));
      await t.pumpAndSettle();
      expect(find.byType(AssistantSheet), findsOneWidget);
      expect(find.text('شلون أفعّل مشترك بالكارت؟'), findsOneWidget);
      expect(server.aiCalls, isEmpty, reason: 'لا سؤال قبل أن يكتب المدير');
      await finish(t);
    });

    testWidgets('«مو هسه» ⇒ لا ورقة ولا طلب', (t) async {
      await setUpActor(s1bSasOwner, aiStatusOn);
      SharedPreferences.setMockInitialValues({});
      await pumpHeader(t);
      await t.tap(find.byIcon(LucideIcons.sparkles));
      await t.pumpAndSettle();
      await t.tap(find.text('مو هسه'));
      await t.pumpAndSettle();
      expect(find.byType(AssistantSheet), findsNothing);
      expect(server.aiCalls, isEmpty);
      await finish(t);
    });

    testWidgets('موافقٌ من قبل ⇒ المحادثة مباشرةً', (t) async {
      await setUpActor(s1bSasOwner, aiStatusOn);
      AiConsent.debugAccepted = true;
      await pumpHeader(t);
      await t.tap(find.byIcon(LucideIcons.sparkles));
      await t.pumpAndSettle();
      expect(find.byType(AssistantConsentSheet), findsNothing);
      expect(find.byType(AssistantSheet), findsOneWidget);
      expect(server.aiCalls, isEmpty);
      await finish(t);
    });
  });

  group('الجرس والترس كما كانا في الرئيسيّة', () {
    testWidgets('الشارة = غير المقروء + المشتركون في خطر، والنقر يفتح الإشعارات',
        (t) async {
      await setUpActor(s1bSasOwner, aiStatusOff);
      await pumpHeader(t);
      AlertsService.count.value = 2;
      await t.runAsync(() => InboxService.add(AppNotification(
            id: 'n1',
            kind: NotificationKind.other,
            title: 'إشعار',
            body: 'نصّ',
            receivedAt: DateTime(2026, 10, 20, 9),
          )));
      await t.pump();
      expect(find.descendant(of: bell, matching: find.text('3')),
          findsOneWidget);
      await t.tap(bell);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(InboxScreen), findsOneWidget);
      await finish(t);
    });

    testWidgets('بلا شيءٍ جديد ⇒ لا شارة', (t) async {
      await setUpActor(s1bSasOwner, aiStatusOff);
      await pumpHeader(t);
      expect(find.descendant(of: bell, matching: find.byType(Text)),
          findsNothing);
      await finish(t);
    });

    testWidgets('الترس يفتح الإعدادات', (t) async {
      await setUpActor(s1bSasOwner, aiStatusOff);
      await pumpHeader(t);
      await t.tap(gear);
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.byType(SettingsScreen), findsOneWidget);
      await finish(t);
    });

    testWidgets('شاشةٌ ضيّقة (٣٢٠) ⇒ المربّعات ٣٨ والفراغ ٦، وإلّا ٤٢ و٨',
        (t) async {
      await setUpActor(s1bSasOwner, aiStatusOn);
      await pumpHeader(t, width: 320);
      expect(t.getSize(gear), const Size(38, 38));
      expect(t.getRect(bell).left - t.getRect(gear).right, moreOrLessEquals(6));
      await finish(t);

      await setUpActor(s1bSasOwner, aiStatusOn);
      await pumpHeader(t, width: 390);
      expect(t.getSize(gear), const Size(42, 42));
      expect(t.getRect(bell).left - t.getRect(gear).right, moreOrLessEquals(8));
      await finish(t);
    });
  });

  testWidgets('المشتركون أثناء أوّل تحميل: العنوان والأزرار فوق الدوّارة',
      (t) async {
    await setUpActor(s1bSasOwner, aiStatusOn);
    final list = Completer<void>();
    server.holds['GET /api/v2/subscribers'] = list;
    await pumpSim(t, const SimVariant(390, dark: false),
        settle: false,
        home: (_) => SubscribersScreen(isActive: ValueNotifier<bool>(true)));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('المشتركون'), findsOneWidget);
    expect(assistant, findsOneWidget);
    expect(bell, findsOneWidget);
    final loading = [t.getRect(assistant), t.getRect(bell), t.getRect(gear)];
    list.complete();
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull);
    expect(find.byType(TopActions), findsOneWidget);
    expect([t.getRect(assistant), t.getRect(bell), t.getRect(gear)], loading,
        reason: 'الموضع نفسه قبل وصول القائمة وبعده');
    await finish(t);
  });

  group('التبويبات الأربعة: الأزرار نفسها بالموضع نفسه', () {
    Future<void> settleShell(WidgetTester t, {int seconds = 3}) async {
      for (var i = 0; i < seconds * 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> openTab(WidgetTester t, String navKey) async {
      await t.tap(find.text(navKey.tr()).last);
      await settleShell(t);
    }

    /// موضع الأزرار الثلاثة في التبويب المعروض.
    Future<List<Rect>> rects(WidgetTester t) async {
      expect(find.byType(TopActions), findsOneWidget,
          reason: 'شريطٌ واحد في التبويب المعروض');
      return [t.getRect(assistant), t.getRect(bell), t.getRect(gear)];
    }

    testWidgets('المالك: الرئيسيّة والمشتركون والأجهزة و«قوائم أخرى»',
        (t) async {
      await setUpActor(s1bSasOwner, aiStatusOn);
      await pumpSim(t, const SimVariant(390, dark: false),
          settle: false, home: (_) => const MainShell());
      await settleShell(t);
      expect(t.takeException(), isNull);
      final home = await rects(t);
      // «الصفحات» في الرئيسيّة وحدها، يمين المساعد.
      expect(find.byIcon(Icons.swap_horiz_rounded), findsOneWidget);
      expect(t.getRect(find.byIcon(Icons.swap_horiz_rounded)).left,
          greaterThan(home[0].right));

      for (final tab in ['nav.subscribers', 'nav.devices', 'nav.more']) {
        await openTab(t, tab);
        expect(t.takeException(), isNull, reason: tab);
        expect(await rects(t), home, reason: '$tab: الموضع نفسه حرفيّاً');
        expect(find.byIcon(Icons.swap_horiz_rounded), findsNothing,
            reason: '«الصفحات» للرئيسيّة وحدها');
      }
      // «قوائم أخرى»: البطاقة باقية مع الزرّ.
      expect(find.text('كيف أسوّي؟'), findsOneWidget);
      // أربعة تبويبات لا تعني أربعة طلبات (مهلة الحال ٥ دقائق).
      expect(server.statusCalls, 1);
      expect(server.aiCalls, isEmpty);
      await finish(t);
    });

    testWidgets('موظّفٌ بلا مفاتيح: التبويبان المقفلان يحملان الأزرار بمكانها',
        (t) async {
      await setUpActor(s3ElEmpNone, aiStatusLocked);
      await pumpSim(t, const SimVariant(390, dark: false),
          settle: false, home: (_) => const MainShell());
      await settleShell(t);
      final home = await rects(t);
      for (final tab in ['nav.subscribers', 'nav.devices', 'nav.more']) {
        await openTab(t, tab);
        expect(t.takeException(), isNull, reason: tab);
        expect(await rects(t), home, reason: tab);
        expect(
            find.descendant(
                of: assistant, matching: find.byType(PermLockIcon)),
            findsOneWidget,
            reason: '$tab: المساعد مقفلٌ بمكانه');
      }
      await finish(t);
    });
  });
}
