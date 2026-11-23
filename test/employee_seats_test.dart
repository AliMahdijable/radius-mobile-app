import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/auth_api.dart';
import 'package:rad_mysvcs/screens/account/companies_screen.dart';
import 'package:rad_mysvcs/screens/account/subscription_screen.dart';
import 'package:rad_mysvcs/services/account_service.dart';

import 'sim_el/sim_harness.dart';
import 'visual_perm/visual_perm_harness.dart';

/// «مقاعد الموظّفين» بتطبيق المدير (٢٣ نوفمبر — الخادم e7c6700، الموقع 190cba6):
///   • النموذج على شكل /account/me (subscription.maxEmployees وemployeeSeats) — أقرب انتهاءٍ بين الفعّالة غير الملغاة.
///   • التفعيل: كود المقاعد ناجحاً (seats/seatsUntil — لا يمسّ الاشتراك) ورفضه بصياغته (seats-unlimited · seats-inactive)،
///     ورمزٌ جديد برسالة الخادم العربيّة، والمعروف بصياغة التطبيق دائماً.
///   • شاشة الاشتراك: سطر «مقاعد موظّفين إضافيّة»، ونجاح كود المقاعد يبقى في الشاشة (لا «شركاتي»).
///   • الموظّف المحجوب بالمقاعد (402 employee-limit): رسالة الخادم كما هي، وبلاها «وصل حدّ الموظّفين» لا «اشتراكٌ منتهٍ».

/// خادم الحساب الوهميّ: ردّ التفعيل القادم، ويسجّل الأجسام.
class _AccountServer implements HttpClientAdapter {
  (int, Map<String, Object?>)? next;
  final bodies = <Object?>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    if (o.path == '/api/account/redeem-code' && o.method == 'POST') {
      bodies.add(o.data);
      final r = next ?? (400, <String, Object?>{'ok': false, 'error': 'not-found'});
      return ResponseBody.fromString(jsonEncode(r.$2), r.$1, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    }
    return ResponseBody.fromString(jsonEncode({'error': 'not-mocked'}), 404, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// اشتراكٌ فعّال بشكل getMe بالخادم — منتصف النهار UTC فلا يتبدّل اليوم بالمنطقة الزمنيّة.
Map<String, Object?> _subJson({int active = 2, bool withSeats = true}) => {
      'status': 'active',
      'active': true,
      'daysLeft': 40,
      'endsAt': '2027-01-01T12:00:00.000Z',
      'validUntil': '2027-01-01T12:00:00.000Z',
      'maxDevices': 3,
      'devicesUsed': 1,
      'maxEmployees': 5 + active,
      if (withSeats)
        'employeeSeats': {
          'active': active,
          'list': [
            {'id': 4, 'seats': 1, 'days': 90, 'code': 'S-2', 'startsAt': '2026-11-23T12:00:00.000Z', 'expiresAt': '2027-02-21T12:00:00.000Z', 'revokedAt': null, 'active': true},
            {'id': 3, 'seats': 1, 'days': 30, 'code': 'S-1', 'startsAt': '2026-11-14T12:00:00.000Z', 'expiresAt': '2026-12-14T12:00:00.000Z', 'revokedAt': null, 'active': true},
            // ملغاة (فعّالة بالتاريخ) ومنتهية — لا تدخلان أقرب انتهاء
            {'id': 2, 'seats': 2, 'days': 30, 'code': 'S-0', 'startsAt': '2026-11-10T12:00:00.000Z', 'expiresAt': '2026-12-01T12:00:00.000Z', 'revokedAt': '2026-11-12T12:00:00.000Z', 'active': true},
            {'id': 1, 'seats': 3, 'days': 30, 'code': 'S-x', 'startsAt': '2026-09-01T12:00:00.000Z', 'expiresAt': '2026-10-01T12:00:00.000Z', 'revokedAt': null, 'active': false},
          ],
        },
    };

void main() {
  group('النموذج والتفعيل', () {
    late _AccountServer server;
    setUp(() {
      server = _AccountServer();
      AccountApi.dio.httpClientAdapter = server;
      AccountApi.tokenSource = ({bool force = false}) async => 'account-test';
    });
    tearDown(() => AccountApi.tokenSource = AccountService.idToken);

    test('employeeSeats وmaxEmployees بشكل /account/me — أقرب انتهاءٍ بين الفعّالة غير الملغاة', () {
      final s = AccountSubscription.fromJson(_subJson());
      expect(s.maxEmployees, 7);
      expect(s.employeeSeats.active, 2);
      expect(s.employeeSeats.grants, hasLength(4));
      expect(s.employeeSeats.nearestEnd, DateTime.parse('2026-12-14T12:00:00.000Z').toLocal());
      final none = AccountSubscription.fromJson(_subJson(withSeats: false)..['maxEmployees'] = null);
      expect(none.employeeSeats.active, 0);
      expect(none.employeeSeats.nearestEnd, isNull);
      expect(none.maxEmployees, isNull, reason: 'بلا حدّ');
      expect(AccountEmployeeSeats.fromJson('x').active, 0);
      expect(AccountEmployeeSeats.fromJson({'active': '3', 'list': 'x'}).active, 3);
    });

    test('كود المقاعد ناجحاً: العدد والموعد والاشتراك كما صار — والعاديّ بلا مقاعد', () async {
      server.next = (200, {'ok': true, 'seats': 2, 'seatsUntil': '2026-12-14T12:00:00.000Z', 'subscription': _subJson()});
      final r = await AccountApi.redeemCode('SEAT-1234');
      expect(server.bodies.single, {'code': 'SEAT-1234'});
      expect(r.isSeats, isTrue);
      expect(r.seats, 2);
      expect(r.seatsUntil, DateTime.parse('2026-12-14T12:00:00.000Z').toLocal());
      expect(r.subscription.employeeSeats.active, 2);
      server.next = (200, {'ok': true, 'subscription': _subJson(withSeats: false)});
      final n = await AccountApi.redeemCode('PLAN-1');
      expect((n.isSeats, n.seats, n.seatsUntil), (false, 0, null));
      expect(n.subscription.active, isTrue);
    });

    test('الرفض: seats-unlimited وseats-inactive بصياغتهما، والجديد برسالة الخادم، والمعروف بصياغة التطبيق', () async {
      Future<AccountApiException> rejected(Map<String, Object?> body) async {
        server.next = (400, body);
        try {
          await AccountApi.redeemCode('X');
        } on AccountApiException catch (e) {
          return e;
        }
        fail('لم يُرفض');
      }

      final u = await rejected({'ok': false, 'error': 'seats-unlimited', 'message': 'حسابك بلا حدٍّ للموظّفين — لا يحتاج مقاعد إضافيّة'});
      expect((u.code, u.message, u.status), ('seats-unlimited', 'account.code_seats_unlimited', 400));
      final i = await rejected({'ok': false, 'error': 'seats-inactive', 'message': 'اشتراكك منتهٍ — جدّده أوّلاً ثمّ فعّل كود المقاعد'});
      expect(i.message, 'account.code_seats_inactive');
      final n = await rejected({'ok': false, 'error': 'seats-new-rule', 'message': 'رسالةٌ عربيّة جديدة من الخادم'});
      expect(n.message, 'رسالةٌ عربيّة جديدة من الخادم', reason: 'رمزٌ لا يعرفه التطبيق ⇒ رسالة الخادم');
      final g = await rejected({'ok': false, 'error': 'seats-new-rule'});
      expect(g.message, 'account.err_generic');
      final k = await rejected({'ok': false, 'error': 'already-used', 'message': 'نصّ الخادم'});
      expect(k.message, 'account.code_used', reason: 'المعروف بصياغة التطبيق دائماً');
    });
  });

  group('شاشة الاشتراك', () {
    late _AccountServer server;
    late VisualServer vs;
    setUpAll(visualSetUpAll);
    setUp(() async {
      vs = await visualSetUp(s1bSasOwner);
      server = _AccountServer();
      AccountApi.dio.httpClientAdapter = server;
      AccountApi.tokenSource = ({bool force = false}) async => 'account-test';
    });
    tearDown(() async {
      AccountApi.tokenSource = AccountService.idToken;
      await visualTearDown();
    });

    AccountMe me(Map<String, Object?> sub) => AccountMe(
          registered: true,
          email: 'agent@example.com',
          accountStatus: 'active',
          subscription: AccountSubscription.fromJson(sub.cast<String, dynamic>()),
        );

    for (final (w, s) in const [(320.0, 1.2), (430.0, 1.0)]) {
      testWidgets('@$w ×$s: سطر المقاعد، وكود المقاعد يبقى هنا برسالته، ورفضه بصياغته', (t) async {
        await pumpVisual(
          t,
          VisualDevice('', Size(w, 1400), 2),
          home: (_) => SubscriptionScreen(me: me(_subJson()), fromCompanies: true),
          wrap: (child) => Builder(
            builder: (ctx) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)), child: child),
          ),
        );
        await settle(t, seconds: 1);
        final line = find.byKey(const ValueKey('account-seats-line'));
        expect(line, findsOneWidget);
        expect(t.widget<Text>(line).data, 'مقاعد موظّفين إضافيّة: 2 · حتى 2026/12/14');
        // نجاح كود المقاعد: رسالته، ولا انتقال لـ«شركاتي»
        server.next = (200, {'ok': true, 'seats': 3, 'seatsUntil': '2027-03-01T12:00:00.000Z', 'subscription': _subJson(active: 5)});
        await t.enterText(find.byType(TextField).first, 'SEAT-AAAA');
        await t.tap(find.text('account.code_activate'.tr()));
        await settle(t, seconds: 1);
        expect(find.text('تمّ تفعيل كود المقاعد ✓ — حدّ موظّفيك +3 حتى 2027/03/01'), findsOneWidget);
        if (const String.fromEnvironment('VISUAL_OUT').isNotEmpty) {
          await shoot(t, s1bSasOwner, 'seats_${w.round()}_x$s', VisualDevice('', Size(w, 1400), 2), vs);
        }
        expect(find.byType(CompaniesScreen), findsNothing);
        expect(find.byType(SubscriptionScreen), findsOneWidget);
        expect(t.widget<Text>(line).data, startsWith('مقاعد موظّفين إضافيّة: 5'), reason: 'الاشتراك كما أعاده الخادم');
        await settle(t, seconds: 5);
        // الرفض بصياغته
        server.next = (400, {'ok': false, 'error': 'seats-unlimited', 'message': 'x'});
        await t.enterText(find.byType(TextField).first, 'SEAT-BBBB');
        await t.tap(find.text('account.code_activate'.tr()));
        await settle(t, seconds: 1);
        expect(find.textContaining('حسابك بلا حدٍّ للموظّفين'), findsOneWidget);
        await settle(t, seconds: 5);
        server.next = (400, {'ok': false, 'error': 'seats-inactive'});
        await t.enterText(find.byType(TextField).first, 'SEAT-CCCC');
        await t.tap(find.text('account.code_activate'.tr()));
        await settle(t, seconds: 1);
        expect(find.textContaining('اشتراكك منتهٍ — جدّده أوّلاً'), findsOneWidget);
        await settle(t, seconds: 5);
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('بلا مقاعد ⇒ لا سطر', (t) async {
      await pumpVisual(t, phone, home: (_) => SubscriptionScreen(me: me(_subJson(withSeats: false)), fromCompanies: true));
      await settle(t, seconds: 1);
      expect(find.byKey(const ValueKey('account-seats-line')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('دخول الموظّف المحجوب بالمقاعد', () {
    late SimServer api;
    setUpAll(simSetUpAll);
    setUp(() async => api = await simSetUp());

    test('402 employee-limit: رسالة الخادم كما هي — وبلاها «وصل حدّ الموظّفين» لا «اشتراكٌ منتهٍ»', () async {
      const seatsMsg = 'حساب مديرك تجاوز حدّ الموظّفين بعد انتهاء مقاعده الإضافيّة — تواصل مع مديرك';
      api.reply('POST', '/api/auth/employee-login', 402, {'success': false, 'error': 'employee-limit', 'message': seatsMsg});
      final a = await AuthApi.employeeLogin(username: 'ali', password: 'x');
      expect(a, isA<LoginFailure>());
      expect(((a as LoginFailure).message, a.code), (seatsMsg, 'employee-limit'));
      api.reply('POST', '/api/auth/employee-login', 402, {'success': false, 'error': 'employee-limit'});
      final b = await AuthApi.employeeLogin(username: 'ali', password: 'x') as LoginFailure;
      expect(b.message, 'حساب مديرك وصل حدّ الموظّفين — تواصل مع مديرك.');
      api.reply('POST', '/api/auth/employee-login', 402, {'success': false, 'error': 'subscription-ended'});
      final c = await AuthApi.employeeLogin(username: 'ali', password: 'x') as LoginFailure;
      expect(c.message, 'اشتراك المدير منتهٍ — تواصل مع مديرك.', reason: 'المنتهي كما كان');
      // التنقّل بين الصفحات (switch_to) بالحكم نفسه
      api.reply('POST', '/api/auth/employee-login', 402, {'success': false, 'error': 'employee-limit', 'message': seatsMsg});
      final d = await AuthApi.employeeSwitch(9, token: 'emp-token') as LoginFailure;
      expect(d.message, seatsMsg);
    });
  });
}
