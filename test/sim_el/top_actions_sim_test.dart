import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/models/app_notification.dart';
import 'package:rad_mysvcs/screens/main_shell.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/ai_consent.dart';
import 'package:rad_mysvcs/services/alerts_service.dart';
import 'package:rad_mysvcs/services/device_alerts_service.dart';
import 'package:rad_mysvcs/services/inbox_service.dart';

import '../support/ai_status_overlay.dart';
import '../visual_perm/visual_perm_harness.dart'
    show Actor, Scenario, fixtureSubscribers, s1bSasOwner, visualSetUp,
        visualTearDown;
import 'sim_harness.dart';

/// شاشة الأجهزة تطلب صلاحيّة الإشعارات المحلّيّة عند فتحها — لا منصّة هنا.
class _NoLocalNotifications extends FlutterLocalNotificationsPlatform {}

/// أزرار الأعلى (٢٠ أكتوبر، طلب المالك) — التبويبات الأربعة كما يراها المدير:
/// المساعد الذكيّ جنب الجرس، والجرس والترس بمكانهما نفسه في الرئيسيّة
/// والمشتركين والأجهزة و«قوائم أخرى». بالعروض ٣٢٠ و٣٦٠ و٣٩٠ و٤١٤ وبالوضعين،
/// أمام خادمٍ وهميّ (خادم لقطات الصلاحيّات + حال المساعد). ٣٦٠ أوّل عرضٍ بالمقاس
/// الكامل (٤٢)، و٤١٤ أعرض هاتف.
///
/// اللقطات في `shots/top_actions/`. التحيّة في الرئيسيّة («صباح الخير»…) تتبع
/// ساعة التشغيل، وتواريخ قائمة المشتركين تتبع اليوم — والباقي ثابت: شارة الجرس
/// من ثلاثة إشعاراتٍ غير مقروءة (لا مشترك ينتهي خلال يوم في البيانات).
const _screen = 'top_actions';

const _variants = <SimVariant>[
  SimVariant(320, dark: false),
  SimVariant(320, dark: true),
  SimVariant(360, dark: false),
  SimVariant(360, dark: true),
  SimVariant(390, dark: false),
  SimVariant(390, dark: true),
  SimVariant(414, dark: false),
  SimVariant(414, dark: true),
];

void _case(
    String state, Future<void> Function(WidgetTester t, SimVariant v) body) {
  for (final v in _variants) {
    testWidgets('$_screen/$state @${v.tag}', (t) async {
      debugDisableShadows = false;
      try {
        await body(t, v);
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}

/// موظّف ساس بلا «المساعد الذكي» — يعرض المشتركين والتقارير والواتساب.
const _sasEmployee = Scenario(
  id: 'T_sas_emp',
  title: 'موظّف ساس — بلا المساعد',
  actor: Actor.elEmployee,
  provider: null,
  keys: {
    'subscribers.view': true,
    'reports.financial': true,
    'reports.daily_activations': true,
    'whatsapp.connect': true,
  },
);

/// بيانات اللقطات بلا مشتركٍ ينتهي اليوم أو غداً — فعدّاد «في خطر» صفرٌ في أيّ
/// ساعة، وشارة الجرس من الإشعارات وحدها.
final _stableSubs = [
  for (final r in fixtureSubscribers)
    if (r['remaining_days'] != 0 && r['remaining_days'] != 1) r,
];

void main() {
  setUpAll(() async {
    await simSetUpAll();
    FlutterLocalNotificationsPlatform.instance = _NoLocalNotifications();
  });

  /// خطواتٌ محدودة لا `pumpAndSettle`: في التبويبات دوّاراتٌ وشمعاتٌ تتكرّر.
  Future<void> settle(WidgetTester t, {int seconds = 3}) async {
    for (var i = 0; i < seconds * 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// الغلاف كاملاً على [tab] (مفتاح تسمية الشريط السفليّ، أو الرئيسيّة).
  Future<void> open(
    WidgetTester t,
    SimVariant v, {
    Scenario actor = s1bSasOwner,
    Map<String, dynamic>? ai = aiStatusOn,
    String? tab,
  }) async {
    final inner = await visualSetUp(actor);
    ApiClient.dio.httpClientAdapter = AiStatusOverlay(inner,
        status: ai,
        routes: {
          'GET /api/v2/subscribers': {'success': true, 'data': _stableSubs},
        });
    AiAssistantState.reset();
    AiConsent.debugReset();
    AlertsService.reset();
    DeviceAlertsService.instance.unreadCount.value = 2;
    // ⚠️ خارج الوقت الوهميّ: صندوق الإشعارات يسأل المنصّة عن مجلّده.
    await t.runAsync(() async {
      for (var i = 1; i <= 3; i++) {
        await InboxService.add(AppNotification(
          id: 'sim-$i',
          kind: NotificationKind.other,
          title: 'إشعار $i',
          body: 'نصّ',
          receivedAt: DateTime(2026, 10, 20, 9, i),
        ));
      }
    });
    await pumpSim(t, v, settle: false, home: (_) => const MainShell());
    await settle(t);
    if (tab != null) {
      await t.tap(find.text(tab.tr()).last);
      await settle(t);
    }
  }

  Future<void> finish(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 25));
    await visualTearDown();
    AiAssistantState.reset();
    AiConsent.debugReset();
    AlertsService.reset();
    DeviceAlertsService.instance.unreadCount.value = 0;
    await t.runAsync(InboxService.clear);
  }

  _case('home', (t, v) async {
    await open(t, v);
    await simCheck(t, v, _screen, 'home');
    await finish(t);
  });

  _case('subscribers', (t, v) async {
    await open(t, v, tab: 'nav.subscribers');
    await simCheck(t, v, _screen, 'subscribers');
    await finish(t);
  });

  _case('devices', (t, v) async {
    await open(t, v, tab: 'nav.devices');
    await simCheck(t, v, _screen, 'devices');
    await finish(t);
  });

  _case('more', (t, v) async {
    await open(t, v, tab: 'nav.more');
    await simCheck(t, v, _screen, 'more');
    await finish(t);
  });

  // موظّفٌ بلا الصلاحيّة: المساعد بمكانه مقفلاً (لا مخفيّ)، ولا «الصفحات».
  _case('home_employee_locked', (t, v) async {
    await open(t, v, actor: _sasEmployee, ai: aiStatusLocked);
    await simCheck(t, v, _screen, 'home_employee_locked');
    await finish(t);
  });

  // مطفأٌ لهذا الحساب: الجرس والترس (و«الصفحات») كما كانت قبل الميزة.
  _case('home_ai_off', (t, v) async {
    await open(t, v, ai: aiStatusOff);
    await simCheck(t, v, _screen, 'home_ai_off');
    await finish(t);
  });
}
