import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/core/platform/store_policy.dart';
import 'package:rad_mysvcs/screens/account/account_dates.dart';
import 'package:rad_mysvcs/screens/account/account_settings_card.dart';
import 'package:rad_mysvcs/screens/account/companies_screen.dart';
import 'package:rad_mysvcs/screens/account/subscription_banner.dart';
import 'package:rad_mysvcs/screens/account/subscription_screen.dart';
import 'package:rad_mysvcs/screens/settings_screen.dart';
import 'package:rad_mysvcs/services/account_service.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «التواريخ أرقام» — المالك ١٤ نوفمبر (بلقطة كرت «الحساب والاشتراك»): «التواريخ حولها ارقام وليس اسماء يعني ينتهي
/// في فلان مدة ولديك كذا ايام». كان «مشترك · باقي 31 يوم · صالح حتى 14 ديسمبر 2026» (اسم شهر، والرقم من تقريب
/// ساعات الخادم للأعلى فلا يطابق التاريخ)؛ صار «مشترك · ينتهي في 2026/12/14 · باقي 30 يوم» في الكرت والشاشة
/// و«شركاتي» والحبّة — رقمٌ واحد بالتقويم.

const _monthNames = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر', //
  'كانون', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'أيلول', 'تشرين',
];

String _ymd(DateTime d) =>
    '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

/// يومٌ بعد [plus] من اليوم بساعةٍ معيّنة (التوقيت المحلّيّ كما يحوّله النموذج).
DateTime _dayAt(int plus, {int h = 23, int m = 50}) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day + plus, h, m);
}

AccountSubscription _sub(String status, int plus, {int? serverDays}) => AccountSubscription(
      status: status,
      active: true,
      // الخادم يقرّب الساعات للأعلى: ساعة الانتهاء بعد ساعة الآن ⇒ يومٌ زائد — العرض لا يعتمده.
      daysLeft: serverDays ?? plus + 1,
      endsAt: _dayAt(plus),
      validUntil: status == 'active' ? _dayAt(plus) : null,
      trialEndsAt: status == 'trial' ? _dayAt(plus) : null,
    );

const _free = AccountSubscription(status: 'active', active: true, daysLeft: 36500);

AccountMe _me(AccountSubscription s) => AccountMe(
      registered: true,
      email: 'agent@example.com',
      accountStatus: 'active',
      subscription: s,
      support: const SupportInfo(whatsapp: '9647700000000'),
    );

/// كلّ نصوص الشاشة الظاهرة.
List<String> _texts(WidgetTester t) => [
      for (final w in t.widgetList<Text>(find.byType(Text)))
        if (w.data != null) w.data! else if (w.textSpan != null) w.textSpan!.toPlainText(),
    ];

void _expectNoMonthNames(WidgetTester t) {
  for (final s in _texts(t)) {
    for (final m in _monthNames) {
      expect(s.contains(m), isFalse, reason: 'اسم شهر «$m» في «$s»');
    }
  }
}

class _Companies implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    final body = o.path == '/api/account/companies'
        ? {
            'success': true,
            'companies': [
              {'sasCode': 'supernet', 'sasUrl': 'https://home.example', 'username': 'agent', 'label': 'SuperNet', 'role': 'admin', 'locked': false},
            ],
          }
        : {'ok': false};
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

const _w480 = VisualDevice('_480', Size(480, 1040), 3);
const _w480Dark = VisualDevice('_480_dark', Size(480, 1040), 3, dark: true);
const _w360 = VisualDevice('_360', Size(360, 780), 3);
const _w320 = VisualDevice('_320', Size(320, 700), 3);

void main() {
  group('الدوالّ', () {
    test('accountDate: «2026/12/14» سنة/شهر/يوم بأرقام', () {
      expect(accountDate(DateTime(2026, 12, 14, 15, 52)), '2026/12/14');
      expect(accountDate(DateTime(2027, 3, 5)), '2027/03/05');
      expect(accountDate(null), '—');
    });

    test('calendarDaysUntil: بالتاريخ لا بالساعات', () {
      // الخادم: ceil((14/12 15:52 − 20/11 10:00) / يوم) = 25 — والتاريخ المكتوب بعد 24 يوماً.
      expect(calendarDaysUntil(DateTime(2026, 12, 14, 15, 52), DateTime(2026, 11, 20, 10)), 24);
      expect(calendarDaysUntil(DateTime(2026, 11, 15, 0, 30), DateTime(2026, 11, 14, 23, 30)), 1);
      expect(calendarDaysUntil(DateTime(2026, 11, 14, 23, 50), DateTime(2026, 11, 14, 0, 10)), 0);
      expect(calendarDaysUntil(DateTime(2026, 11, 11), DateTime(2026, 11, 14, 9)), -3);
      expect(calendarDaysUntil(DateTime(2027, 1, 1), DateTime(2026, 12, 31, 23, 59)), 1);
      expect(calendarDaysUntil(DateTime(2028, 3, 1), DateTime(2028, 2, 28)), 2); // كبيسة
    });

    test('daysLeftOn: لا يقلّ عن 0، وبلا تاريخٍ رقم الخادم كما هو', () {
      final now = DateTime(2026, 11, 20, 10);
      AccountSubscription s(int server, DateTime? end, {bool active = true}) =>
          AccountSubscription(status: active ? 'active' : 'expired', active: active, daysLeft: server, endsAt: end);
      expect(s(25, DateTime(2026, 12, 14, 15, 52)).daysLeftOn(now), 24);
      expect(s(1, DateTime(2026, 11, 20, 23)).daysLeftOn(now), 0);
      expect(s(0, DateTime(2026, 11, 1), active: false).daysLeftOn(now), 0);
      expect(_free.daysLeftOn(now), 36500);
    });
  });

  group('الشاشات', () {
    setUpAll(visualSetUpAll);
    tearDown(() {
      AccountStatusCache.debugOverride = null;
      StorePolicy.debugHidePurchaseFlows = null;
    });

    Future<void> pumpCard(WidgetTester t, AccountSubscription s, {VisualDevice d = _w480}) async {
      AccountStatusCache.debugOverride = _me(s);
      await pumpVisual(t, d,
          home: (_) => Scaffold(
                backgroundColor: AppColors.bg,
                body: ListView(padding: const EdgeInsets.all(16), children: const [AccountSettingsCard()]),
              ));
      await settle(t, seconds: 1);
    }

    Future<void> expand(WidgetTester t, {bool neutral = false}) async {
      await t.tap(find.text(neutral ? 'الحساب' : 'الحساب والاشتراك'));
      await settle(t, seconds: 1);
    }

    testWidgets('الكرت: «مشترك · ينتهي في 2026/12/14 · باقي 30 يوم» — رقم التقويم لا تقريب الخادم (31)', (t) async {
      final s = _sub('active', 30, serverDays: 31);
      await pumpCard(t, s);
      expect(find.text('مشترك · باقي 30 يوم'), findsOneWidget); // الرأس مطويّاً
      await expand(t);
      expect(find.text('مشترك · ينتهي في ${_ymd(s.endsAt!)} · باقي 30 يوم'), findsOneWidget);
      expect(find.textContaining('31'), findsNothing);
      _expectNoMonthNames(t);
      expect(t.takeException(), isNull);
    });

    testWidgets('الكرت: تجربة 9 أيّام', (t) async {
      final s = _sub('trial', 9);
      await pumpCard(t, s);
      await expand(t);
      expect(find.text('تجربة · باقي 9 يوم'), findsOneWidget);
      expect(find.text('تجربة · ينتهي في ${_ymd(s.endsAt!)} · باقي 9 يوم'), findsOneWidget);
      _expectNoMonthNames(t);
    });

    testWidgets('الكرت: يومه الأخير «ينتهي اليوم» لا «باقي 0 يوم»', (t) async {
      await pumpCard(t, _sub('active', 0, serverDays: 1));
      await expand(t);
      expect(find.text('ينتهي اليوم'), findsOneWidget); // الرأس
      expect(find.text('مشترك · ينتهي اليوم'), findsOneWidget);
      expect(find.textContaining('باقي 0'), findsNothing);
    });

    testWidgets('الكرت: «مجّاني دائم» كما هو', (t) async {
      await pumpCard(t, _free);
      await expand(t);
      expect(find.text('مجّاني دائم'), findsNWidgets(2));
      expect(find.textContaining('ينتهي'), findsNothing);
    });

    testWidgets('الكرت بالآيفون: «ينتهي في 2026/12/14 · باقي 30 يوم» بلا «مشترك»', (t) async {
      StorePolicy.debugHidePurchaseFlows = true;
      final s = _sub('active', 30);
      await pumpCard(t, s);
      await expand(t, neutral: true);
      expect(find.text('ينتهي في ${_ymd(s.endsAt!)} · باقي 30 يوم'), findsOneWidget);
      expect(find.textContaining('مشترك'), findsNothing);
      _expectNoMonthNames(t);
    });

    testWidgets('شاشة الاشتراك: فعّال ⇒ «ينتهي في … · باقي 30 يوم»؛ تجربة ⇒ الأيّام بالعنوان والتاريخ تحته', (t) async {
      final a = _sub('active', 30, serverDays: 31);
      await pumpVisual(t, _w480, home: (_) => SubscriptionScreen(me: _me(a), fromCompanies: true));
      await settle(t, seconds: 1);
      expect(find.text('الاشتراك فعّال'), findsOneWidget);
      expect(find.text('ينتهي في ${_ymd(a.endsAt!)} · باقي 30 يوم'), findsOneWidget);
      _expectNoMonthNames(t);

      final tr = _sub('trial', 9);
      await t.pumpWidget(const SizedBox()); // حالة الشاشة تُبنى من جديد (لا تُورث الاشتراك السابق)
      await pumpVisual(t, _w480, home: (_) => SubscriptionScreen(me: _me(tr), fromCompanies: true));
      await settle(t, seconds: 1);
      expect(find.text('تجربة مجانيّة — باقي 9 يوم'), findsOneWidget);
      expect(find.text('ينتهي في ${_ymd(tr.endsAt!)}'), findsOneWidget);
      _expectNoMonthNames(t);
    });

    testWidgets('شاشة الاشتراك: منتهٍ ⇒ «انتهى في 2026/11/11 — …» بالأرقام', (t) async {
      final end = _dayAt(-3, h: 10);
      final s = AccountSubscription(status: 'expired', active: false, daysLeft: 0, endsAt: end, validUntil: end);
      await pumpVisual(t, _w480, home: (_) => SubscriptionScreen(me: _me(s), fromCompanies: true));
      await settle(t, seconds: 1);
      expect(find.textContaining('انتهى في ${_ymd(end)}'), findsOneWidget);
      _expectNoMonthNames(t);
    });

    group('«شركاتي»', () {
      setUp(() {
        FlutterSecureStorage.setMockInitialValues({});
        AccountApi.dio.httpClientAdapter = _Companies();
        AccountApi.tokenSource = ({bool force = false}) async => 'account-test';
      });
      tearDown(() => AccountApi.tokenSource = AccountService.idToken);

      Future<void> pumpCompanies(WidgetTester t, AccountSubscription s) async {
        await pumpVisual(t, _w480, home: (_) => CompaniesScreen(me: _me(s)));
        for (var i = 0; i < 6; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await t.pump(const Duration(milliseconds: 50));
        }
      }

      testWidgets('أندرويد: «مشترك · باقي 30 يوم» (التقويم، لا 31)', (t) async {
        await pumpCompanies(t, _sub('active', 30, serverDays: 31));
        expect(find.text('مشترك · باقي 30 يوم'), findsOneWidget);
      });

      testWidgets('آيفون: «فعّال حتى 2026/12/14»', (t) async {
        StorePolicy.debugHidePurchaseFlows = true;
        final s = _sub('active', 30);
        await pumpCompanies(t, s);
        expect(find.text('فعّال حتى ${_ymd(s.endsAt!)}'), findsOneWidget);
        _expectNoMonthNames(t);
      });
    });

    testWidgets('حبّة الرئيسيّة: نفس رقم الكرت، و«ينتهي اليوم» في يومه الأخير', (t) async {
      AccountStatusCache.debugOverride = _me(_sub('active', 5, serverDays: 6));
      await pumpVisual(t, _w480, home: (_) => const Scaffold(body: Center(child: SubscriptionChip())));
      await settle(t, seconds: 1);
      expect(find.text('باقي 5 يوم'), findsOneWidget);

      AccountStatusCache.debugOverride = _me(_sub('active', 0, serverDays: 1));
      await t.pumpWidget(const SizedBox());
      await pumpVisual(t, _w480, home: (_) => const Scaffold(body: Center(child: SubscriptionChip())));
      await settle(t, seconds: 1);
      expect(find.text('ينتهي اليوم'), findsOneWidget);

      // آيفون: نافذتها «ينتهي تفعيل الحساب في 2026/…» بالأرقام.
      StorePolicy.debugHidePurchaseFlows = true;
      final s = _sub('active', 5);
      AccountStatusCache.debugOverride = _me(s);
      await t.pumpWidget(const SizedBox());
      await pumpVisual(t, _w480, home: (_) => const Scaffold(body: Center(child: SubscriptionChip())));
      await settle(t, seconds: 1);
      await t.tap(find.text('باقي 5 يوم'));
      await settle(t, seconds: 1);
      expect(find.text('ينتهي تفعيل الحساب في ${_ymd(s.endsAt!)}'), findsOneWidget);
      _expectNoMonthNames(t);
    });

    testWidgets('لا يفيض: الكرت مفتوحاً على 320 و360 بخطّ 1.2', (t) async {
      for (final d in [_w320, _w360]) {
        t.platformDispatcher.textScaleFactorTestValue = 1.2;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.pumpWidget(const SizedBox());
        await pumpCard(t, _sub('trial', 13), d: d);
        await expand(t);
        expect(t.takeException(), isNull, reason: 'فيضٌ على ${d.size.width}');
      }
    });
  });

  // ─── لقطات الشاشة الحقيقيّة (الإعدادات ⇒ «الحساب والاشتراك» مفتوحاً) — عند طلبها وحده:
  // flutter test test/account_dates_test.dart --dart-define=VISUAL_OUT=<مجلّد> --plain-name "لقطات"
  const out = String.fromEnvironment('VISUAL_OUT');
  group('لقطات', () {
    setUpAll(visualSetUpAll);
    tearDown(() {
      AccountStatusCache.debugOverride = null;
      StorePolicy.debugHidePurchaseFlows = null;
    });
    for (final c in [
      ('paid30', _sub('active', 30, serverDays: 31)),
      ('trial9', _sub('trial', 9)),
      ('today', _sub('active', 0, serverDays: 1)),
      ('free', _free),
    ]) {
      for (final d in [_w480, _w480Dark, _w360]) {
        testWidgets('${c.$1}${d.tag}', (t) async {
          debugDisableShadows = false;
          final server = await visualSetUp(s1bSasOwner);
          AccountStatusCache.debugOverride = _me(c.$2);
          final nav = GlobalKey<NavigatorState>();
          await pumpVisual(t, d, navigatorKey: nav, home: (_) => Scaffold(backgroundColor: AppColors.bg));
          await settle(t, seconds: 1);
          nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
          await settle(t, seconds: 2);
          await t.tap(find.text('الحساب والاشتراك'));
          await settle(t, seconds: 1);
          final boundary = t.renderObject<RenderRepaintBoundary>(find.byKey(visualRootKey));
          final png = await t.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: d.dpr);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            return data!.buffer.asUint8List();
          });
          final f = File('$out/settings_account_${c.$1}${d.tag}.png');
          f.parent.createSync(recursive: true);
          f.writeAsBytesSync(png!, flush: true);
          server.writeLog('settings_account_${c.$1}${d.tag}.requests.txt');
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(seconds: 6));
          await visualTearDown();
          debugDisableShadows = true; // يُعاد قبل فحص ثوابت الإطار
        });
      }
    }
  }, skip: out.isEmpty ? 'لقطاتٌ عند الطلب (VISUAL_OUT)' : null);
}
