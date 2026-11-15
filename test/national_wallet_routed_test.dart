import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/national_wallet_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/national/national_wallet_topup_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';

import 'sim_el/sim_harness.dart';

/// «تعبئة محفظة المشترك» من «كل الشركات» (١٥ نوفمبر — بلاغ المالك: وكيلٌ بصفحتَي وطنيّ فتح النافذة من شيت تفعيل مشترك صفحةٍ فسألت
/// الصفحة المفتوحة ⇒ «المشترك غير موجود ضمن مشتركي حسابك»). النافذة تأخذ شركة صفّ المشترك لحظة فتحها:
///   • القراءة بمفتاح شركته (لا توكن الصفحة المفتوحة)، واسم الشركة في رأس النافذة.
///   • التحويل والكارت: مرجع نافذة المشترك يُسكّ أوّلاً من شركته (GET المشترك موجَّهاً) ثمّ الكتابة بالمفتاح والمرجع — كتابةٌ واحدة.
///   • صفٌّ بلا مفتاح في الوضع ⇒ للمفتوحة صراحةً بلا مفتاحٍ ولا مرجع؛ وخارج الوضع كما كان حرفاً.
///   • نتائج طبقة التوجيه: «لم يتأكّد» لما لا يُعرف أثره، ورفضٌ بنصّه لما لم يُرسل.
const _v = SimVariant(390, dark: false);
const _sid = '555';
const _base = '/api/v2/ftth/subscriptions/$_sid/wallet';
const _kOpen = 'c0000000000a1';
const _kB = 'c0000000000b2';
const _ref = 'r_AAAAAAAAAAAAAAAAAAAAAA';

Map<String, Object?> _info() => {
      'success': true,
      'data': {
        'transfer': {'ok': true, 'reason': null},
        'card': {'ok': true, 'reason': null},
        'partner_balance': 1250000,
        'customer_balance': 5000,
        'target': {'name': 'مريم عبد الله', 'phone': '•••4567'},
        'limits': {'min': 1000, 'max': 1000000, 'step': 250},
        'recent': null,
      },
    };

Map<String, Object?> _companies() => {
      'routing': true,
      'writes': true,
      'companies': [
        // المفتوحة: صفحة الجلسة (watani:15742)؛ والأخرى صفحة وطنيٍّ ثانية للحساب نفسه
        {'key': _kOpen, 'code': 'watani', 'username': 'main-a', 'name': 'الوطني · الرئيسيّ', 'provider': 'kit', 'status': 'ok',
          'admin_id': 'watani:15742', 'ns': 'watani|main-a', 'currency': 'IQD', 'color_index': 0},
        {'key': _kB, 'code': 'watani', 'username': 'member-b', 'name': 'الوطني · الفريق', 'provider': 'kit', 'status': 'ok',
          'admin_id': 'watani:1380', 'ns': 'watani|member-b', 'currency': 'IQD', 'color_index': 1},
      ],
    };

/// خادم المحاكاة + صدى مفتاح الشركة كالخادم الحقيقيّ، ومرجع النافذة على قراءة المشترك الموجَّهة.
class _Echo implements HttpClientAdapter {
  _Echo(this.inner);
  final SimServer inner;

  /// false ⇒ قراءة المشترك لا تسكّ مرجعاً (الخادم رفضها أو تعذّرت).
  bool mint = true;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final r = await inner.fetch(o, rs, cf);
    final key = o.headers['x-company-key'] as String?;
    if (key == null) return r;
    final extra = <String, List<String>>{
      'x-company-key': [key],
      if (mint && o.method.toUpperCase() == 'GET' && o.uri.path == '/api/v2/subscribers/$_sid') 'x-company-ref': [_ref],
    };
    return ResponseBody(r.stream, r.statusCode, headers: {...r.headers, ...extra});
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 120));
  }
  await t.pumpAndSettle();
}

String? _h(RequestOptions r, String name) => r.headers[name]?.toString();

void main() {
  group('القراءة النقيّة', () {
    test('مرجع النافذة: التحويل والكارت برقم الاشتراك يطلبانه — والقراءة وغير الرقميّ والطرق الأخرى لا', () {
      for (final tail in ['transfer', 'card']) {
        final need = CompanyRefs.requireOf('POST', '/api/v2/ftth/subscriptions/12469826/wallet/$tail');
        expect((need?.idx, need?.kind), ('12469826', CompanyRefKind.subject), reason: tail);
        expect(CompanyRefs.requireOf('post', '/api/v2/ftth/subscriptions/7/wallet/$tail/')?.idx, '7', reason: 'شرطةٌ أخيرة وحروفٌ صغيرة');
      }
      for (final (m, p) in [
        ('GET', '/api/v2/ftth/subscriptions/555/wallet/topup'),
        ('POST', '/api/v2/ftth/subscriptions/555/wallet/topup'),
        ('GET', '/api/v2/ftth/subscriptions/555/wallet/transfer'),
        ('PUT', '/api/v2/ftth/subscriptions/555/wallet/transfer'),
        ('POST', '/api/v2/ftth/subscriptions/abc/wallet/transfer'),
        ('POST', '/api/v2/ftth/subscriptions/555/wallet/transfer/x'),
        ('POST', '/api/v2/ftth/subscriptions/555/wallet'),
        ('POST', '/api/v2/ftth/subscriptions/555/device'),
        ('POST', '/api/v2/ftth/team/5/wallet-refill'),
      ]) {
        expect(CompanyRefs.requireOf(m, p), isNull, reason: '$m $p');
      }
      // لا يُسكّ عليها مرجع ولا تُستهلك (مرجع النافذة باقٍ بعد الكتابة)
      expect(CompanyRefs.mintOf('GET', '/api/v2/ftth/subscriptions/555/wallet/topup'), isNull);
      // كتابات المشترك القائمة كما كانت
      expect(CompanyRefs.requireOf('POST', '/api/v2/subscribers/555/pay-debt')?.kind, CompanyRefKind.subject);
      expect(CompanyRefs.requireOf('POST', '/api/v2/subscribers/555/activate')?.kind, CompanyRefKind.activate);
    });

    test('نتائج طبقة التوجيه: مجهول الأثر ⇒ «لم يتأكّد»، والمرفوض قبل المعالج ⇒ رفضٌ بنصّه (لم يُرسل شيء)', () {
      for (final code in ['COMPANY_SESSION_EXPIRED', 'COMPANY_UPSTREAM_UNAVAILABLE', 'COMPANY_ROUTE_ECHO']) {
        final r = WalletTopupResult.of({'success': false, 'code': code, 'message': 'تعذّر التأكّد من النتيجة'});
        expect((r.state, r.code, r.message), (WalletTopupState.unknown, code, 'تعذّر التأكّد من النتيجة'), reason: code);
      }
      for (final code in ['COMPANY_REF_REQUIRED', 'COMPANY_REF_EXPIRED', 'COMPANY_REF_MISMATCH', 'COMPANY_ROUTE_NOT_ALLOWED',
        'COMPANY_ROUTE_WRITES_PAUSED', 'COMPANY_ROUTE_DISABLED', 'COMPANY_NEEDS_LOGIN', 'COMPANY_ROUTE_BUSY', 'WALLET_ROUTED_OFF', 'OWNER_ONLY']) {
        final r = WalletTopupResult.of({'success': false, 'code': code, 'message': 'لم يُنفَّذ شيء'});
        expect((r.state, r.message), (WalletTopupState.rejected, 'لم يُنفَّذ شيء'), reason: code);
      }
      // ردّ المعالج نفسه كما كان
      expect(WalletTopupResult.of({'success': false, 'code': 'OUTCOME_UNKNOWN', 'message': 'لم يتأكّد'}).state, WalletTopupState.unknown);
      expect(WalletTopupResult.of({'success': false, 'code': 'RECENT_DUPLICATE', 'message': 'أكّد'}).state, WalletTopupState.repeat);
    });
  });

  group('النافذة في «كل الشركات»', () {
    late SimServer server;
    late _Echo echo;
    setUpAll(simSetUpAll);

    Future<void> up(WidgetTester t, {bool merged = true}) async {
      server = await simSetUp(secure: {'auth.admin_id': 'watani:15742', 'auth.admin_username': 'main-a'});
      echo = _Echo(server);
      ApiClient.dio.httpClientAdapter = echo;
      PermissionsService.debugSet(isEmployee: false);
      ProviderService.debugSet('watani', label: 'المشروع الوطني');
      AccountApi.tokenSource = ({bool force = false}) async => 'acct';
      MergedMode.reset();
      CompanyRefs.reset();
      MergedMode.fetchRaw = () async => Map<String, dynamic>.from(_companies());
      if (merged) expect(await t.runAsync(() => MergedMode.enter()), isTrue, reason: 'الوضع يُفتح بشركتين صالحتين');
    }

    tearDown(() {
      MergedMode.reset();
      CompanyRefs.reset();
      PermissionsService.debugReset();
      ProviderService.debugSet(null);
    });

    WalletTopupResult? got;
    Future<void> open(WidgetTester t, String? key) async {
      got = null;
      await pumpSim(t, _v, home: (_) => simLauncher((c) async => got = await showNationalWalletTopupSheet(c, sid: _sid, companyKey: key)));
      await simOpen(t);
      await _settle(t);
    }

    Future<void> typeAmount(WidgetTester t, String text) async {
      final f = find.byType(TextField).at(0);
      await t.ensureVisible(f);
      await t.enterText(f, text);
      await t.pump();
    }

    testWidgets('مشترك صفحةٍ أخرى: القراءة بمفتاح شركته، ثمّ مرجع نافذته من شركته، ثمّ تحويلٌ واحد بالمفتاح والمرجع — واسم الشركة في الرأس', (t) async {
      await up(t);
      server.reply('GET', '$_base/topup', 200, _info());
      server.reply('GET', '/api/v2/subscribers/$_sid', 200, {'success': true, 'data': {'idx': _sid, 'username': 'FBG555'}});
      server.reply('POST', '$_base/transfer', 200, {
        'success': true, 'outcome': 'applied', 'data': {'amount': 25000, 'payment_type': 'cash', 'cash_paid': 25000, 'debt_added': 0, 'customer_balance': 30000},
      });
      await open(t, _kB);
      expect(find.text('تعبئة محفظة المشترك'), findsOneWidget);
      expect(find.textContaining('«الوطني · الفريق»'), findsOneWidget, reason: 'اسم شركة الصفّ في رأس النافذة');
      expect(find.textContaining('مريم عبد الله'), findsOneWidget);
      final info = server.calls('GET', '$_base/topup');
      expect(info, hasLength(1));
      expect((_h(info.single, 'x-company-key'), _h(info.single, 'x-account-token'), info.single.headers.containsKey('Authorization'), _h(info.single, 'x-company-ref')),
          (_kB, 'acct', false, null), reason: 'القراءة لشركة الصفّ بتوكن الحساب — بلا توكن الصفحة المفتوحة وبلا مرجع');
      await typeAmount(t, '25000');
      await t.tap(find.textContaining('حوّل 25,000'));
      await _settle(t);
      // الترتيب: قراءة المشترك موجَّهةً (تسكّ المرجع) قبل الكتابة
      final order = [for (final r in server.requests) '${r.method.toUpperCase()} ${r.uri.path} ${_h(r, 'x-company-key') ?? '-'}'];
      final iSub = order.indexOf('GET /api/v2/subscribers/$_sid $_kB');
      final iPost = order.indexOf('POST $_base/transfer $_kB');
      expect(iSub >= 0 && iPost > iSub, isTrue, reason: order.join(' | '));
      final post = server.calls('POST', '$_base/transfer');
      expect(post, hasLength(1), reason: 'كتابةٌ واحدة');
      expect((_h(post.single, 'x-company-key'), _h(post.single, 'x-company-ref'), post.single.headers.containsKey('Authorization')), (_kB, _ref, false));
      expect(post.single.data, {'amount': 25000, 'paymentType': 'cash'});
      expect(server.requests.where((r) => r.uri.path.startsWith(_base) && _h(r, 'x-company-key') != _kB), isEmpty,
          reason: 'لا نداء للنافذة ذهب للشركة المفتوحة');
      expect(got?.state, WalletTopupState.applied);
      expect(find.text('تعبئة محفظة المشترك'), findsNothing, reason: 'أُغلقت');
      await simDrain(t);
    });

    testWidgets('الكارت لمشترك صفحةٍ أخرى: المفتاح والمرجع كذلك، ورقم الكارت لا يبقى', (t) async {
      await up(t);
      server.reply('GET', '$_base/topup', 200, _info());
      server.reply('GET', '/api/v2/subscribers/$_sid', 200, {'success': true, 'data': {'idx': _sid, 'username': 'FBG555'}});
      server.reply('POST', '$_base/card', 200, {'success': true, 'outcome': 'applied', 'data': {'credited': 15000, 'customer_balance': 20000}});
      await open(t, _kB);
      await t.tap(find.text('بكارت'));
      await t.pumpAndSettle();
      final f = find.byType(TextField).at(0);
      await t.enterText(f, '١٢٣٤٥٦٧٨٩٠١٢');
      await t.pump();
      await t.tap(find.text('عبّئ بالكارت'));
      await _settle(t);
      final post = server.calls('POST', '$_base/card');
      expect(post, hasLength(1));
      expect((_h(post.single, 'x-company-key'), _h(post.single, 'x-company-ref')), (_kB, _ref));
      expect(post.single.data, {'pin': '123456789012'});
      expect(got?.state, WalletTopupState.applied);
      await simDrain(t);
    });

    testWidgets('مرجع النافذة لم يُسكّ (قراءة المشترك رُفضت): الكتابة تذهب بلا مرجع والخادم يرفضها بنصّه — النافذة تبقى ولا «تمّ» كاذب', (t) async {
      await up(t);
      echo.mint = false;
      server.reply('GET', '$_base/topup', 200, _info());
      server.reply('GET', '/api/v2/subscribers/$_sid', 409, {'success': false, 'code': 'COMPANY_UPSTREAM_UNAVAILABLE', 'message': 'تعذّر جلب بيانات الشركة الآن'});
      server.reply('POST', '$_base/transfer', 409, {'success': false, 'code': 'COMPANY_REF_REQUIRED', 'message': 'تغيّرت بيانات النافذة أو انتهت — أغلقها وافتحها من جديد. لم يُنفَّذ شيء'});
      await open(t, _kB);
      await typeAmount(t, '25000');
      await t.tap(find.textContaining('حوّل 25,000'));
      await _settle(t);
      final post = server.calls('POST', '$_base/transfer');
      expect(post, hasLength(1));
      expect((_h(post.single, 'x-company-key'), _h(post.single, 'x-company-ref')), (_kB, null));
      expect(got, isNull, reason: 'لم تُغلق بنتيجة');
      expect(find.textContaining('لم يُنفَّذ شيء'), findsOneWidget, reason: 'نصّ الخادم يبقى في النافذة');
      expect(find.text('تعبئة محفظة المشترك'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('المفتاح مطفأ لهذه الشركة (wallet_routed): النافذة تعرض نصّ الخادم ولا شيء يُرسل', (t) async {
      await up(t);
      server.reply('GET', '$_base/topup', 409, {'success': false, 'code': 'WALLET_ROUTED_OFF',
        'message': 'تعبئة محفظة مشترك هذه الشركة من صفحتها الآن — افتحها وحدها من «شركاتي» (لم يُرسل شيء)'});
      await open(t, _kB);
      expect(find.textContaining('من صفحتها الآن'), findsOneWidget);
      expect(_h(server.calls('GET', '$_base/topup').single, 'x-company-key'), _kB);
      expect(server.requests.where((r) => r.method.toUpperCase() == 'POST'), isEmpty);
      await simDrain(t);
    });

    testWidgets('البلاغ نفسه: شيت تفعيل مشترك صفحةٍ أخرى ⇒ «محفظة المشترك» لا تكفي ⇒ «شحن المحفظة» ⇒ النافذة تسأل شركته هو (لا الصفحة المفتوحة)', (t) async {
      await up(t);
      server.reply('GET', '/api/v2/subscribers/$_sid/activation-data', 200, {
        'success': true,
        'data': {
          'idx': _sid, 'username': 'FBG555', 'profile_name': 'Basic', 'profile_id': 11, 'user_price': 40000,
          'price_after_discount': 40000, 'base_price': 40000, 'current_balance': 0,
          'manager_balance': 1999.97, 'manager_balance_is_limit': true,
          'provider': 'watani', 'provider_label': 'المشروع الوطني',
          'packages': [{'id': 11, 'name': 'Basic', 'price': 40000, 'cost': null, 'days': null}],
          'package_change_allowed': false, 'package_change_timing': ['now'], 'card_payment': true,
          'customer_wallet': {'balance': 0, 'price': 35000, 'enough': false, 'topup': true},
        },
      });
      server.reply('GET', '$_base/topup', 200, _info());
      final sub = Subscriber.fromJson({'idx': _sid, 'username': 'FBG555', 'firstname': 'مشترك', 'profile_id': 11, 'profile_name': 'Basic'}).withCompany(_kB);
      await pumpSim(t, _v, home: (_) => Scaffold(
            body: Builder(builder: (c) => Center(child: TextButton(onPressed: () => showActivateSheet(c, sub), child: const Text('open')))),
          ));
      await t.tap(find.text('open'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await _settle(t);
      expect(_h(server.calls('GET', '/api/v2/subscribers/$_sid/activation-data').single, 'x-company-key'), _kB);
      // عضو فريق: السطر باسمه «حدّ محفظتك» (الخادم يعرض حدّه مع علَمه)
      expect(find.text('حدّ محفظتك'), findsOneWidget);
      final tile = find.text('محفظة المشترك');
      await t.ensureVisible(tile.first);
      await t.tap(tile.first);
      await _settle(t);
      expect(find.text('رصيد محفظة المشترك لا يكفي'), findsOneWidget, reason: '«شحن المحفظة؟»');
      await t.tap(find.text('شحن المحفظة'));
      await _settle(t);
      expect(find.text('تعبئة محفظة المشترك'), findsOneWidget);
      final info = server.calls('GET', '$_base/topup');
      expect(info, hasLength(1));
      expect((_h(info.single, 'x-company-key'), info.single.headers.containsKey('Authorization')), (_kB, false),
          reason: 'النافذة لشركة صفّ المشترك — كانت تذهب بلا مفتاح للصفحة المفتوحة فتقول «غير موجود»');
      expect(find.textContaining('مريم عبد الله'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('صفٌّ بلا مفتاح في الوضع (مشترك الشركة المفتوحة): للمفتوحة صراحةً — بلا مفتاحٍ ولا مرجعٍ ولا قراءة مشترك، ولا اسم شركةٍ أخرى في الرأس', (t) async {
      await up(t);
      server.reply('GET', '$_base/topup', 200, _info());
      server.reply('POST', '$_base/transfer', 200, {
        'success': true, 'outcome': 'applied', 'data': {'amount': 25000, 'payment_type': 'cash', 'cash_paid': 25000, 'debt_added': 0, 'customer_balance': 30000},
      });
      await open(t, null);
      // بلا مفتاح ⇒ اسم الشركة المفتوحة كما تسمّيها الجلسة ([MergedMode.rowCompanyName]) — لا اسم الشركة الأخرى
      final openName = MergedMode.rowCompanyName(null); // عدّة المحاكاة قد لا تسمّي الجلسة المفتوحة (null) — في التطبيق اسمها
      if (openName != null) expect(find.textContaining('«$openName»'), findsOneWidget, reason: 'بلا مفتاح ⇒ اسم المفتوحة');
      expect(find.textContaining('«الوطني · الفريق»'), findsNothing, reason: 'لا اسم شركةٍ أخرى على نافذة المفتوحة');
      await typeAmount(t, '25000');
      await t.tap(find.textContaining('حوّل 25,000'));
      await _settle(t);
      final mine = server.requests.where((r) => r.uri.path.startsWith(_base)).toList();
      expect(mine, hasLength(2));
      for (final r in mine) {
        expect((_h(r, 'x-company-key'), _h(r, 'x-company-ref')), (null, null), reason: '${r.method} ${r.uri.path}');
      }
      expect(server.calls('GET', '/api/v2/subscribers/$_sid'), isEmpty, reason: 'لا سكّ مرجعٍ للمفتوحة');
      expect(got?.state, WalletTopupState.applied);
      await simDrain(t);
    });

    testWidgets('خارج الوضع كما كان حرفاً: بلا مفتاحٍ ولا مرجع، والرأس بلا اسم شركة', (t) async {
      await up(t, merged: false);
      server.reply('GET', '$_base/topup', 200, _info());
      server.reply('POST', '$_base/transfer', 200, {
        'success': true, 'outcome': 'applied', 'data': {'amount': 25000, 'payment_type': 'non-cash', 'cash_paid': 0, 'debt_added': 25000, 'customer_balance': 30000},
      });
      await open(t, null);
      expect(find.text('من محفظتك في بوّابة الوطني أو بكارت الشركة'), findsOneWidget);
      await typeAmount(t, '25000');
      await t.tap(find.text('دين'));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('حوّل 25,000'));
      await _settle(t);
      expect(server.bodies('POST', '$_base/transfer').single, {'amount': 25000, 'paymentType': 'non-cash'});
      expect(server.requests.where((r) => _h(r, 'x-company-key') != null), isEmpty);
      expect(server.calls('GET', '/api/v2/subscribers/$_sid'), isEmpty);
      expect(got?.debtAdded, 25000);
      await simDrain(t);
    });
  });
}
