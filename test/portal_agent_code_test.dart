import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/portal_settings_api.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/screens/portal_settings/portal_settings_screen.dart';
import 'package:rad_mysvcs/screens/portal_settings/widgets/agent_code_tab.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «رمز الوكيل» في «بوابة المشترك» — أمام خادمٍ وهميّ بعقد الخادم الحيّ
/// (fdcc2d7، `server.js` ~25546–25615 و`portalBroker.js`):
///
///   GET  /api/v2/portal/settings            → {success, enabled, agent_code}
///   PUT  /api/v2/portal/settings {enabled}  → {success, enabled} · ٤٠٣ PERMISSION_DENIED · ٥٠٣
///   POST /api/v2/portal/agent-code/rotate   → {success, agent_code} · ٤٠٣ OWNER_ONLY · ٥٠٣
///   GET  /api/v2/portal/logins?limit=N      → {success, data:[{at, username_lc, via, result…}]}
///
/// والسلوك المطلوب: الرمز ونسخه ومشاركته لكلّ فاعل، و«تغيير الرمز» لصاحب
/// الحساب وحده، والمفتاح والسجلّ بصلاحيّتيهما مقفلَين بمكانهما (لا يُطلبان).
const _settings = '/api/v2/portal/settings';
const _rotate = '/api/v2/portal/agent-code/rotate';
const _logins = '/api/v2/portal/logins';
const _branding = '/api/v2/admin/branding';
const _packages = '/api/v2/admin/portal-packages';

/// الردّ الآمن الفارغ الذي تأخذه جلسة ايرث لنك لمسارٍ لا يمرّره الخادم.
const _elSafeEmpty = {
  'success': true,
  'data': null,
  'items': <Object>[],
  'value': null,
  'total': 0,
};

const _v = SimVariant(360, dark: false);

void main() {
  late SimServer server;
  late List<String> clipboard;
  final originalShare = AgentCodeTab.shareText;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '2251'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
  });

  tearDown(() {
    AgentCodeTab.shareText = originalShare;
    PermissionsService.debugReset();
    ProviderService.debugSet(null);
  });

  /// الحافظة والاهتزاز — قناة المنصّة بلا محرّك في `flutter test`.
  void mockPlatform(WidgetTester t) {
    clipboard = <String>[];
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(() => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
  }

  void settings({bool enabled = true, Object? code = '402917'}) =>
      server.reply('GET', _settings, 200,
          {'success': true, 'enabled': enabled, 'agent_code': code});

  /// الشاشة كاملةً بطولٍ يبني كلّ عناصر التبويب الأوّل.
  Future<void> open(WidgetTester t) async {
    mockPlatform(t);
    await pumpSim(t, _v, home: (_) => const PortalSettingsScreen());
    t.view.physicalSize = const Size(400, 2000);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  final sheet = find.byType(BottomSheet);
  Finder inSheet(Finder f) => find.descendant(of: sheet, matching: f);

  /// الأرقام الستّة بترتيبها — كلّ خانةٍ نصٌّ مستقلّ.
  List<String> shownDigits(WidgetTester t) => [
        for (final e in find
            .descendant(
              of: find.byWidgetPredicate(
                  (w) => w.runtimeType.toString() == '_Digits'),
              matching: find.byType(Text),
            )
            .evaluate())
          (e.widget as Text).data ?? '',
      ];

  // ═════════════════════════ العقد ═════════════════════════

  group('العقد', () {
    test('رمز الوكيل: ستّة أرقامٍ بالضبط، والأصفار البادئة تبقى', () {
      expect(parseAgentCode('004211'), '004211');
      expect(parseAgentCode(' 123456 '), '123456');
      expect(parseAgentCode(123456), '123456');
      expect(parseAgentCode('12345'), isNull);
      expect(parseAgentCode('1234567'), isNull);
      expect(parseAgentCode('12a456'), isNull);
      expect(parseAgentCode(null), isNull);
    });

    test('الإعدادات: مفتوحةٌ افتراضاً، والرمز الخاطئ لا يُعرض', () {
      final a = PortalAccess.fromJson(const {'success': true});
      expect(a.enabled, isTrue);
      expect(a.agentCode, isNull);
      expect(
          PortalAccess.fromJson(const {'enabled': false, 'agent_code': '000777'})
              .agentCode,
          '000777');
      expect(PortalAccess.fromJson(const {'enabled': false}).enabled, isFalse);
      expect(PortalAccess.fromJson(const {'enabled': 0}).enabled, isFalse);
      expect(PortalAccess.fromJson(const {'enabled': 1}).enabled, isTrue);
      expect(PortalAccess.fromJson(const {'agent_code': 'abc'}).agentCode,
          isNull);
    });

    test('سجلّ الدخول: الطريقة والنتيجة والتوقيت', () {
      PortalLogin row(Map<String, dynamic> j) => PortalLogin.fromJson(j);
      expect(row({'via': 'pw'}).via, PortalLoginVia.password);
      expect(row({'via': 'sas'}).via, PortalLoginVia.password,
          reason: 'الدخول المباشر على الساس كلمة مرور أيضاً');
      expect(row({'via': 'qr'}).via, PortalLoginVia.qr);
      expect(row({'via': null}).via, PortalLoginVia.unknown);
      expect(row({'result': 'ok'}).result, PortalLoginResult.ok);
      expect(row({'result': 'bad_password'}).result,
          PortalLoginResult.badPassword);
      expect(row({'result': 'pw_unverifiable'}).result,
          PortalLoginResult.unverifiable);
      expect(row({'result': 'portal_disabled'}).result,
          PortalLoginResult.disabled);
      expect(row({'result': 'portal_unavailable'}).result,
          PortalLoginResult.unavailable);
      expect(row({'result': 'something_new'}).result, PortalLoginResult.other);
      // `at` من قاعدتنا موسومٌ بـZ — اللحظة نفسها بتوقيت الجهاز.
      final at = row({'at': '2026-10-18T07:12:44.000Z'}).at!;
      expect(at.isUtc, isFalse);
      expect(at.toUtc(), DateTime.utc(2026, 10, 18, 7, 12, 44));
      expect(row({'username_lc': '  ali@x '}).username, 'ali@x');
      expect(row({'username_lc': ''}).username, isNull);
    });

    test('🚨 نصّ المشاركة كما طُلب حرفيّاً + رابط Play + بديل آب ستور (نصّ الويب)',
        () {
      expect(
        agentCodeShareText('123456'),
        'حمّل تطبيق MyServices وادخل برمز الوكيل: 123456 واسم المستخدم '
        'وكلمة المرور\n\n'
        'أندرويد: https://play.google.com/store/apps/details?id=com.myservices.mysub\n'
        'آيفون: ابحث عن MyServices في App Store',
      );
      // لا رابط آب ستور بعد (2.0.7 بانتظار أبل) — فسطر الآيفون بديلٌ لا رابطٌ ميّت.
      expect(SubscriberApp.iosUrl, isNull);
      // ومتى عُرف رابطه يحلّ محلّ البديل.
      expect(
        agentCodeShareText('123456', iosUrl: 'https://apps.apple.com/app/x'),
        endsWith('\nآيفون: https://apps.apple.com/app/x'),
      );
      // ولا رابط معروفٌ إطلاقاً: البديلان معاً — كـagentShareText في الويب.
      expect(
        agentCodeShareText('123456', androidUrl: null, iosUrl: null),
        'حمّل تطبيق MyServices وادخل برمز الوكيل: 123456 واسم المستخدم '
        'وكلمة المرور\n\n'
        'أندرويد: ابحث عن MyServices في Google Play\n'
        'آيفون: ابحث عن MyServices في App Store',
      );
    });

    test('التوقيت: «منذ…» لليوم، وتاريخٌ قصير لما قبله', () {
      final now = DateTime(2026, 10, 18, 12, 0);
      expect(portalLoginWhen(now.subtract(const Duration(minutes: 5)), now: now),
          'منذ 5 دقيقة');
      expect(portalLoginWhen(now.subtract(const Duration(hours: 3)), now: now),
          'منذ 3 ساعة');
      expect(portalLoginWhen(DateTime(2026, 10, 16, 21, 5), now: now),
          '16/10 21:05');
      expect(portalLoginWhen(null, now: now), '');
    });
  });

  // ═════════════════════════ الواجهة البرمجيّة ═════════════════════════

  group('PortalSettingsApi', () {
    test('getAccess: الردّ ← الإعدادات، والإخفاق ← null', () async {
      settings(enabled: false, code: '010203');
      final a = await PortalSettingsApi.getAccess();
      expect(a!.enabled, isFalse);
      expect(a.agentCode, '010203');

      server.reply('GET', _settings, 401,
          {'success': false, 'message': 'التوثيق مطلوب'});
      expect(await PortalSettingsApi.getAccess(), isNull);
      server.on('GET', _settings, simTimeout);
      expect(await PortalSettingsApi.getAccess(), isNull);
    });

    test('setPortalEnabled: الجسم {enabled} · ٤٠٣ «لا صلاحيّة» · ٥٠٣', () async {
      server.reply('PUT', _settings, 200, {'success': true, 'enabled': false});
      final ok = await PortalSettingsApi.setPortalEnabled(false);
      expect(ok.ok, isTrue);
      expect(ok.enabled, isFalse);
      expect(server.bodies('PUT', _settings).single, {'enabled': false});

      server.reply('PUT', _settings, 403, {
        'success': false,
        'code': 'PERMISSION_DENIED',
        'message': 'لا تملك صلاحية: settings.edit',
      });
      final denied = await PortalSettingsApi.setPortalEnabled(true);
      expect(denied.ok, isFalse);
      expect(denied.denied, isTrue);
      expect(denied.message, isNull, reason: 'لا مفتاح صلاحيّةٍ خامّ للمدير');

      server.reply('PUT', _settings, 503,
          {'success': false, 'message': 'إعدادات البوّابة غير متاحة بعد'});
      final down = await PortalSettingsApi.setPortalEnabled(true);
      expect(down.ok, isFalse);
      expect(down.denied, isFalse);
    });

    test('rotateAgentCode: الجديد · OWNER_ONLY برسالته · رمزٌ معطوب', () async {
      server.reply('POST', _rotate, 200, {'success': true, 'agent_code': '654321'});
      expect((await PortalSettingsApi.rotateAgentCode()).code, '654321');

      server.reply('POST', _rotate, 403, {
        'success': false,
        'code': 'OWNER_ONLY',
        'message': 'هذه العمليّة لصاحب الحساب فقط',
      });
      final emp = await PortalSettingsApi.rotateAgentCode();
      expect(emp.code, isNull);
      expect(emp.ownerOnly, isTrue);
      expect(emp.message, 'هذه العمليّة لصاحب الحساب فقط');

      server.reply('POST', _rotate, 200, {'success': true, 'agent_code': 'x'});
      expect((await PortalSettingsApi.rotateAgentCode()).code, isNull);
      server.on('POST', _rotate, simTimeout);
      final down = await PortalSettingsApi.rotateAgentCode();
      expect(down.code, isNull);
      expect(down.message, isNull);
    });

    test('getLogins: ?limit= · الصفوف · ٤٠٣', () async {
      server.reply('GET', _logins, 200, {
        'success': true,
        'data': [
          {'at': '2026-10-18T07:00:00.000Z', 'username_lc': 'a@b', 'via': 'qr', 'result': 'ok'},
        ],
      });
      final r = await PortalSettingsApi.getLogins(limit: 20);
      expect(r.rows, hasLength(1));
      expect(r.rows!.single.via, PortalLoginVia.qr);
      expect(server.calls('GET', _logins).single.queryParameters,
          {'limit': 20});

      server.reply('GET', _logins, 403,
          {'success': false, 'code': 'PERMISSION_DENIED'});
      final denied = await PortalSettingsApi.getLogins();
      expect(denied.rows, isNull);
      expect(denied.denied, isTrue);
    });

    test('🚨 fillAgentCode: اليدويّ لا يمرّ بالخادم — فيُملأ المتغيّر هنا',
        () async {
      // نصٌّ بلا المتغيّر: كما هو، بلا نداء.
      expect(await PortalSettingsApi.fillAgentCode('مرحباً'), 'مرحباً');
      expect(server.calls('GET', _settings), isEmpty);

      settings(code: '004211');
      expect(
        await PortalSettingsApi.fillAgentCode(
            'ادخل برمز الوكيل: {agent_code} — {agent_code}'),
        'ادخل برمز الوكيل: 004211 — 004211',
      );
      // حسابٌ بلا رمز (ردٌّ ناجح بـagent_code: null): يُفرَّغ المتغيّر كما يفرّغه
      // الخادم في التلقائيّ — لا «{agent_code}» حرفيّاً للمشترك من اليدويّ.
      settings(code: null);
      expect(await PortalSettingsApi.fillAgentCode('رمزك: {agent_code}.'),
          'رمزك: .');
      // رمزٌ تعذّر جلبه: يبقى المتغيّر (يُرى في المعاينة، والخادم يملؤه تلقائيّاً).
      server.on('GET', _settings, simTimeout);
      expect(await PortalSettingsApi.fillAgentCode('رمزك {agent_code}'),
          'رمزك {agent_code}');
    });

    test('🚨 الهويّة والباقات: ردّ ايرث لنك الآمن «غير متوفّر» لا نموذجٌ فارغ',
        () async {
      server.reply('GET', _branding, 200, _elSafeEmpty);
      server.reply('GET', _packages, 200, _elSafeEmpty);
      expect((await PortalSettingsApi.loadBranding()).state,
          PortalLoad.unsupported);
      expect((await PortalSettingsApi.loadPackages()).state,
          PortalLoad.unsupported);

      server.reply('GET', _branding, 200, {
        'success': true,
        'branding': {'display_name': 'شبكة النور'},
      });
      server.reply('GET', _packages, 200, {'success': true, 'packages': []});
      final b = await PortalSettingsApi.loadBranding();
      expect(b.state, PortalLoad.ok);
      expect(b.branding.displayName, 'شبكة النور');
      expect((await PortalSettingsApi.loadPackages()).state, PortalLoad.ok);

      // ⚠️ الإخفاق ليس «غير متوفّر» ولا نموذجاً فارغاً يمسح المحفوظ.
      server.reply('GET', _branding, 401,
          {'success': false, 'message': 'التوثيق مطلوب'});
      expect((await PortalSettingsApi.loadBranding()).state, PortalLoad.failed);
      server.on('GET', _packages, simTimeout);
      expect((await PortalSettingsApi.loadPackages()).state, PortalLoad.failed);
    });
  });

  // ═════════════════════════ المالك ═════════════════════════

  group('المالك', () {
    testWidgets('🚨 التبويب الأوّل: الأرقام الستّة + نسخ + مشاركة + تغيير',
        (t) async {
      settings();
      server.reply('GET', _logins, 200, {'success': true, 'data': []});
      await open(t);
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.text('رمز الوكيل'), findsWidgets);
      expect(shownDigits(t), ['4', '0', '2', '9', '1', '7']);
      expect(find.text('نسخ'), findsOneWidget);
      expect(find.text('مشاركة'), findsOneWidget);
      expect(find.text('تغيير الرمز'), findsOneWidget);
      expect(find.text('مفعّلة'), findsOneWidget);
      expect(find.text('تفعيل بوابة مشتركيّ'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      expect(find.text(kAgentCodeVariable), findsOneWidget);
      expect(find.text('ما دخل أيّ مشترك بعد'), findsOneWidget);
      // لا تبويبٌ آخر طُلب قبل أن يُفتح.
      expect(server.calls('GET', _branding), isEmpty);
    });

    testWidgets('نسخ: الرمز وحده في الحافظة + إشعار', (t) async {
      settings();
      await open(t);
      await t.tap(find.text('نسخ'));
      await t.pump();
      expect(clipboard, ['402917']);
      expect(find.text('تمّ نسخ رمز الوكيل'), findsOneWidget);
      await t.tap(find.text(kAgentCodeVariable));
      await t.pump();
      expect(clipboard.last, '{agent_code}');
      await simDrain(t);
    });

    testWidgets('🚨 مشاركة: النصّ الجاهز برمز الحساب', (t) async {
      settings();
      final shared = <String>[];
      AgentCodeTab.shareText = (text, origin) async => shared.add(text);
      await open(t);
      await t.tap(find.text('مشاركة'));
      await t.pump();
      expect(shared, [agentCodeShareText('402917')]);
      expect(shared.single, contains('ادخل برمز الوكيل: 402917'));
    });

    testWidgets('مشاركةٌ تعذّرت: رسالةٌ لا انهيار', (t) async {
      settings();
      AgentCodeTab.shareText = (text, origin) async => throw StateError('x');
      await open(t);
      await t.tap(find.text('مشاركة'));
      await t.pump();
      expect(find.text('تعذّرت المشاركة — انسخ الرمز وأرسله بنفسك'),
          findsOneWidget);
      await simDrain(t);
    });

    testWidgets('🚨 تغيير الرمز: تأكيدٌ «القديم يتوقّف فوراً» ثمّ الجديد',
        (t) async {
      settings();
      server.reply('POST', _rotate, 200, {'success': true, 'agent_code': '770015'});
      await open(t);
      await t.tap(find.text('تغيير الرمز'));
      await t.pumpAndSettle();
      expect(inSheet(find.text('تغيير رمز الوكيل؟')), findsOneWidget);
      expect(
          inSheet(find.textContaining('الرمز القديم سيتوقّف فوراً')),
          findsOneWidget);
      expect(server.calls('POST', _rotate), isEmpty, reason: 'لا شيء قبل التأكيد');

      await t.tap(inSheet(find.text('تغيير الرمز')));
      await t.pumpAndSettle();
      expect(server.calls('POST', _rotate), hasLength(1));
      expect(shownDigits(t), ['7', '7', '0', '0', '1', '5']);
      expect(find.text('تغيّر الرمز — أرسل الرمز الجديد لمشتركيك'),
          findsOneWidget);
      await simDrain(t);
    });

    testWidgets('إلغاء التغيير لا يمسّ الرمز', (t) async {
      settings();
      await open(t);
      await t.tap(find.text('تغيير الرمز'));
      await t.pumpAndSettle();
      await t.tap(inSheet(find.text('إلغاء')));
      await t.pumpAndSettle();
      expect(server.calls('POST', _rotate), isEmpty);
      expect(shownDigits(t), ['4', '0', '2', '9', '1', '7']);
    });

    testWidgets('رفض التغيير: الرمز القديم باقٍ ورسالة الخادم', (t) async {
      settings();
      server.reply('POST', _rotate, 400,
          {'success': false, 'message': 'رمز الوكيل غير متاح بعد — حاول لاحقاً'});
      await open(t);
      await t.tap(find.text('تغيير الرمز'));
      await t.pumpAndSettle();
      await t.tap(inSheet(find.text('تغيير الرمز')));
      await t.pumpAndSettle();
      expect(shownDigits(t), ['4', '0', '2', '9', '1', '7']);
      expect(find.text('رمز الوكيل غير متاح بعد — حاول لاحقاً'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('🚨 الإيقاف بتأكيد ← PUT {enabled:false} ← «موقوفة»، والتفعيل بلا سؤال',
        (t) async {
      settings();
      server.on('PUT', _settings, (req) => SimReply(200, {
            'success': true,
            'enabled': (req.data as Map)['enabled'],
          }));
      await open(t);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(inSheet(find.text('إيقاف بوابة مشتركيك؟')), findsOneWidget);
      expect(server.calls('PUT', _settings), isEmpty);
      await t.tap(inSheet(find.text('إيقاف البوابة')));
      await t.pumpAndSettle();
      expect(server.bodies('PUT', _settings).single, {'enabled': false});
      expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(find.text('موقوفة'), findsOneWidget);
      expect(find.text('البوابة موقوفة — مشتركوك ما يقدرون يدخلون'),
          findsOneWidget);

      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(sheet, findsNothing, reason: 'التفعيل لا يُسأل عنه');
      expect(server.bodies('PUT', _settings).last, {'enabled': true});
      expect(find.text('مفعّلة'), findsOneWidget);
      expect(find.text('البوابة موقوفة — مشتركوك ما يقدرون يدخلون'),
          findsNothing);
    });

    testWidgets('حفظٌ تعذّر: المفتاح يرجع كما كان + رسالة', (t) async {
      settings(enabled: false);
      server.reply('PUT', _settings, 503,
          {'success': false, 'message': 'غير متاحة بعد'});
      await open(t);
      expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(server.calls('PUT', _settings), hasLength(1));
      expect(t.widget<Switch>(find.byType(Switch)).value, isFalse,
          reason: 'لم يُحفظ — لا تفاؤلٌ باقٍ');
      expect(find.text('تعذّر الحفظ — حاول لاحقاً'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('لا رمز لحسابك: سطرٌ هادئ بلا نسخ ولا مشاركة', (t) async {
      settings(code: null);
      await open(t);
      expect(find.text('رمز الوكيل غير متاح لحسابك بعد'), findsOneWidget);
      expect(find.text('نسخ'), findsNothing);
      expect(find.text('مشاركة'), findsNothing);
      expect(find.text('تغيير الرمز'), findsNothing);
      expect(find.text(kAgentCodeVariable), findsNothing);
      // والمفتاح يبقى — البوّابة نفسها ما زالت تُفتح وتُغلق.
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('تعذّر التحميل ← «إعادة المحاولة» ← الرمز', (t) async {
      // مهلةٌ بلا ردّ (لا ٤٠١: ذاك يشعل تجديد الجلسة، وليس موضوع هذا الفحص).
      server.on('GET', _settings, simTimeout);
      await open(t);
      expect(find.text('تعذّر تحميل رمز الوكيل — تحقّق من الاتصال'),
          findsOneWidget);
      expect(find.byType(Switch), findsNothing, reason: 'لا حالة مجهولة');
      settings();
      await t.tap(find.text('إعادة المحاولة').first);
      await t.pumpAndSettle();
      expect(shownDigits(t), ['4', '0', '2', '9', '1', '7']);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('آخر دخول المشتركين: اليوزر والطريقة والنتيجة', (t) async {
      settings();
      final now = DateTime.now().toUtc();
      String ago(Duration d) => now.subtract(d).toIso8601String();
      server.reply('GET', _logins, 200, {
        'success': true,
        'data': [
          {'at': ago(const Duration(minutes: 5)), 'username_lc': 'ali.abbas@popq', 'via': 'qr', 'result': 'ok'},
          {'at': ago(const Duration(hours: 2)), 'username_lc': 'noor@popq', 'via': 'pw', 'result': 'bad_password'},
          {'at': ago(const Duration(hours: 3)), 'username_lc': 'sara', 'via': null, 'result': 'portal_disabled'},
        ],
      });
      await open(t);
      expect(simText('ali.abbas@popq'), findsOneWidget);
      expect(simText('QR · منذ 5 دقيقة'), findsOneWidget);
      expect(find.text('دخل'), findsOneWidget);
      expect(simText('noor@popq'), findsOneWidget);
      expect(simText('كلمة مرور · منذ 2 ساعة'), findsOneWidget);
      expect(find.text('كلمة مرور خاطئة'), findsOneWidget);
      expect(simText('منذ 3 ساعة'), findsOneWidget, reason: 'بلا طريقة');
      // «البوابة موقوفة» لا «موقوفة» وحدها بجانب يوزر المشترك — كي لا تُقرأ
      // «حساب المشترك موقوف» (كالويب).
      expect(find.text('البوابة موقوفة'), findsOneWidget);
      expect(server.calls('GET', _logins).single.queryParameters,
          {'limit': 20});
    });

    testWidgets('🚨 ايرث لنك: الهويّة والباقات «غير متوفّرة» لا نموذجٌ يفشل حفظه',
        (t) async {
      ProviderService.debugSet('earthlink');
      settings();
      server.reply('GET', _branding, 200, _elSafeEmpty);
      server.reply('GET', _packages, 200, _elSafeEmpty);
      await open(t);
      expect(shownDigits(t), hasLength(6), reason: 'الرمز لايرث لنك أيضاً');
      await t.tap(find.text('معلومات الشركة'));
      await t.pumpAndSettle();
      expect(find.text('تخصيص معلومات الشركة غير متوفّر لشركتك بعد'),
          findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      await t.tap(find.text('وصف الباقات'));
      await t.pumpAndSettle();
      expect(find.text('وصف الباقات غير متوفّر لشركتك بعد'), findsOneWidget);
    });

    testWidgets('🚨 الهويّة تعذّرت: لا نموذج فارغ يمسح المحفوظ — بل إعادة',
        (t) async {
      settings();
      server.on('GET', _branding, simTimeout);
      await open(t);
      await t.tap(find.text('معلومات الشركة'));
      await t.pumpAndSettle();
      expect(find.text('تعذّر التحميل — تحقّق من الاتصال وأعد المحاولة'),
          findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      server.reply('GET', _branding, 200, {
        'success': true,
        'branding': {'display_name': 'شبكة النور'},
      });
      await t.tap(find.text('إعادة المحاولة').last);
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsWidgets);
      expect(find.text('شبكة النور'), findsWidgets);
    });
  });

  // ═════════════════════════ الموظّف ═════════════════════════

  group('الموظّف', () {
    testWidgets(
        '🚨 موظّف ساس بلا صلاحيّات: الرمز ونسخه ومشاركته — لا تغيير، والباقي مقفل لا يُطلب',
        (t) async {
      PermissionsService.debugSet(isEmployee: true);
      settings();
      final shared = <String>[];
      AgentCodeTab.shareText = (text, origin) async => shared.add(text);
      await open(t);
      expect(shownDigits(t), ['4', '0', '2', '9', '1', '7']);
      expect(find.text('تغيير الرمز'), findsNothing, reason: 'لصاحب الحساب');
      await t.tap(find.text('نسخ'));
      await t.pump();
      expect(clipboard, ['402917']);
      await t.tap(find.text('مشاركة'));
      await t.pump();
      expect(shared, hasLength(1));
      // لا يحرّر القوالب ⇒ لا «تقدر تضيف رمزك…» (كالويب).
      expect(find.text(kAgentCodeVariable), findsNothing);

      // المفتاح بمكانه: الحالة + قفل، بلا مفتاحٍ يُبدَّل.
      expect(find.byType(Switch), findsNothing);
      expect(find.text('تفعيل بوابة مشتركيّ'), findsOneWidget);
      expect(find.text('مفعّلة'), findsWidgets);
      await t.tap(find.text('تفعيل بوابة مشتركيّ'));
      await t.pump();
      expect(find.text('ليس لديك صلاحيّة لهذا الإجراء — اطلبها من مديرك'),
          findsOneWidget);
      expect(server.calls('PUT', _settings), isEmpty);

      // السجلّ مقفلٌ بمكانه — ولا يُسأل الخادم عنه.
      expect(find.byType(LockedCard), findsOneWidget);
      expect(server.calls('GET', _logins), isEmpty);

      // وتبويبا التخصيص بمكانهما مقفلين — بلا نداء.
      expect(find.byType(TabBar), findsOneWidget);
      await t.tap(find.text('معلومات الشركة'));
      await t.pumpAndSettle();
      expect(find.byType(LockedNotice), findsOneWidget);
      expect(server.calls('GET', _branding), isEmpty);
      await simDrain(t);
    });

    testWidgets('موظّف ساس بـsettings.edit وsubscribers.view: المفتاح والسجلّ له',
        (t) async {
      PermissionsService.debugSet(isEmployee: true, permissions: const {
        'settings.edit': true,
        'subscribers.view': true,
      });
      settings();
      server.reply('GET', _logins, 200, {'success': true, 'data': []});
      await open(t);
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(LockedCard), findsNothing);
      expect(server.calls('GET', _logins), hasLength(1));
      expect(find.text('تغيير الرمز'), findsNothing,
          reason: 'التغيير لصاحب الحساب ولو بكلّ الصلاحيّات');
      expect(find.text(kAgentCodeVariable), findsNothing,
          reason: 'التلميح لمن يحرّر القوالب');
    });

    testWidgets('موظّف بإدارة القوالب: تلميح {agent_code} له', (t) async {
      PermissionsService.debugSet(
          isEmployee: true, permissions: const {'whatsapp.templates': true});
      settings();
      await open(t);
      expect(find.text(kAgentCodeVariable), findsOneWidget);
    });

    testWidgets(
        '🚨 صلاحيّة السجلّ سُحبت (٤٠٣): قفلٌ بمكانه لا «تعذّر التحميل»',
        (t) async {
      PermissionsService.debugSet(
          isEmployee: true, permissions: const {'subscribers.view': true});
      settings();
      server.reply('GET', _logins, 403, {
        'success': false,
        'code': 'PERMISSION_DENIED',
        'message': 'لا تملك صلاحية: subscribers.view',
      });
      await open(t);
      expect(find.byType(LockedCard), findsOneWidget);
      expect(find.text('تعذّر تحميل السجلّ'), findsNothing);
      expect(find.textContaining('subscribers.view'), findsNothing);
      expect(server.calls('GET', _logins), hasLength(1));
      // سحب التحديث لا يعيد السؤال عمّا رفضه الخادم.
      await t.runAsync(() =>
          t.widget<RefreshIndicator>(find.byType(RefreshIndicator).first)
              .onRefresh());
      await t.pumpAndSettle();
      expect(server.calls('GET', _settings).length, greaterThan(1),
          reason: 'السحب حدّث الرمز');
      expect(server.calls('GET', _logins), hasLength(1));
      expect(find.byType(LockedCard), findsOneWidget);
    });

    testWidgets(
        '🚨 موظّف ايرث لنك: تبويب الرمز وحده، وقفل المفتاح «لصاحب الحساب»',
        (t) async {
      ProviderService.debugSet('earthlink');
      PermissionsService.debugSet(
          isEmployee: true, permissions: const {'subscribers.view': true});
      settings();
      server.reply('GET', _logins, 200, {
        'success': true,
        'data': [
          {'at': DateTime.now().toUtc().toIso8601String(), 'username_lc': 'el.user', 'via': 'pw', 'result': 'ok'},
        ],
      });
      await open(t);
      // settings.edit لا يُمنح له ⇒ التخصيص مخفيّ، فلا شريط تبويبات.
      expect(find.byType(TabBar), findsNothing);
      expect(shownDigits(t), hasLength(6));
      expect(find.text('تغيير الرمز'), findsNothing);
      expect(simText('el.user'), findsOneWidget);
      expect(find.text(kAgentCodeVariable), findsNothing,
          reason: 'القوالب لا تُمنح لموظّف ايرث لنك');

      await t.tap(find.text('تفعيل بوابة مشتركيّ'));
      await t.pump();
      expect(find.text('تفعيل البوابة وإيقافها لصاحب الحساب'), findsOneWidget,
          reason: 'لا «اطلبها من مديرك» لما لا يملك مديره منحه');
      expect(find.text('ليس لديك صلاحيّة لهذا الإجراء — اطلبها من مديرك'),
          findsNothing);
      expect(server.calls('GET', _branding), isEmpty);
      await simDrain(t);
    });

    testWidgets('صلاحيّةٌ سُحبت (٤٠٣): المفتاح يرجع + «لا صلاحيّة»', (t) async {
      PermissionsService.debugSet(
          isEmployee: true, permissions: const {'settings.edit': true});
      settings();
      server.reply('PUT', _settings, 403, {
        'success': false,
        'code': 'PERMISSION_DENIED',
        'message': 'لا تملك صلاحية: settings.edit',
      });
      await open(t);
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      await t.tap(inSheet(find.text('إيقاف البوابة')));
      await t.pumpAndSettle();
      expect(t.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text('ليس لديك صلاحيّة لهذا الإجراء — اطلبها من مديرك'),
          findsOneWidget);
      expect(find.textContaining('settings.edit'), findsNothing);
      await simDrain(t);
    });
  });

  testWidgets('🔒 القفل يبقى بمقاس الصفّ ومكانه (الرسم)', (t) async {
    PermissionsService.debugSet(isEmployee: true);
    settings();
    await open(t);
    final lockIcons = find.descendant(
      of: find.ancestor(
          of: find.text('تفعيل بوابة مشتركيّ'), matching: find.byType(Row)),
      matching: find.byType(PermLockIcon),
    );
    expect(lockIcons, findsWidgets);
    expect(find.byIcon(LucideIcons.power), findsOneWidget);
  });
}
