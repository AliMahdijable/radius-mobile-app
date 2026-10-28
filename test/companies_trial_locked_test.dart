import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/core/platform/store_policy.dart';
import 'package:rad_mysvcs/screens/account/companies_screen.dart';
import 'package:rad_mysvcs/services/account_service.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «انتهت التجربة، احذف الشركات» (المالك ٢٧–٢٨ أكتوبر): بعد التجربة سوبرنت مجّانيّ والشركات الأخرى متوقّفة — و«شركاتي»
/// كانت تُخفي الحذف في ضغطةٍ مطوّلة، وفتحُ المتوقّفة يعود إليها بلا كلمة. الآن: شريطٌ يقول السبب، شارة «متوقّفة» وزرّ حذفٍ
/// ظاهر، ونافذةٌ بالسبب و«حذف الشركة» (و«تفعيل كود» على غير الآيفون).

class _Account implements HttpClientAdapter {
  _Account(this.companies);
  List<Map<String, Object?>> companies;
  final removed = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    Object body = {'ok': false};
    if (o.path == '/api/account/companies') {
      body = {'success': true, 'companies': companies};
    } else if (o.path == '/api/account/companies/remove') {
      final d = (o.data as Map).cast<String, dynamic>();
      removed.add(d);
      companies = [for (final x in companies) if (!(x['sasCode'] == d['sasCode'] && x['username'] == d['username'])) x];
      body = {'ok': true, 'companies': companies};
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

const _me = AccountMe(
  registered: true,
  email: 'agent@example.com',
  accountStatus: 'active',
  // كما يعرضه الخادم لموزّع سوبرنت بعد تجربته (homeFreeState): فعّالٌ بلا نهاية.
  subscription: AccountSubscription(status: 'active', active: true, daysLeft: 36500),
);

List<Map<String, Object?>> _companies() => [
      {'sasCode': 'supernet', 'sasUrl': 'https://home.example', 'username': 'home.agent', 'label': 'SuperNet', 'role': 'admin', 'locked': false},
      {'sasCode': 'speednet-iq', 'sasUrl': 'https://sas.speednet.example', 'username': 'remote.agent', 'label': 'Speednet', 'role': 'admin', 'locked': true},
    ];

void main() {
  late _Account account;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    account = _Account(_companies());
    AccountApi.dio.httpClientAdapter = account;
    AccountApi.tokenSource = ({bool force = false}) async => 'account-test';
  });
  tearDown(() {
    AccountApi.tokenSource = AccountService.idToken;
    StorePolicy.debugHidePurchaseFlows = null;
  });

  Future<void> pump(WidgetTester t) async {
    await pumpVisual(t, phone, home: (_) => const CompaniesScreen(me: _me));
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('شريط «انتهت التجربة» + شارة «متوقّفة» وزرّ حذفٍ ظاهر على المتوقّفة وحدها', (t) async {
    await pump(t);
    expect(find.text('انتهت التجربة للشركات الأخرى'), findsOneWidget);
    expect(find.textContaining('احذفها لتبقى مجّاناً'), findsOneWidget);
    expect(find.text('متوقّفة'), findsOneWidget);
    expect(find.byTooltip('حذف الشركة'), findsOneWidget, reason: 'زرّ حذفٍ ظاهر — لا ضغطةٌ مطوّلةٌ وحدها');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('فتح المتوقّفة ⇒ نافذةٌ بالسبب، و«حذف الشركة» يحذفها فيزول الشريط', (t) async {
    await pump(t);
    await t.tap(find.text('Speednet'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('انتهت التجربة لهذه الشركة'), findsOneWidget);
    expect(find.text('تفعيل كود'), findsOneWidget, reason: 'غير الآيفون: طريق التشغيل بكود');
    await t.tap(find.text('حذف الشركة').last);
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(account.removed, [
      {'sasCode': 'speednet-iq', 'username': 'remote.agent'}
    ]);
    expect(find.text('Speednet'), findsNothing);
    expect(find.text('انتهت التجربة للشركات الأخرى'), findsNothing, reason: 'سوبرنت وحدها ⇒ لا شريط');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('آيفون: لا «تفعيل كود» في الشريط ولا النافذة (3.1.1)، والحذف باقٍ', (t) async {
    StorePolicy.debugHidePurchaseFlows = true;
    await pump(t);
    expect(find.textContaining('فعّل كود'), findsNothing);
    await t.tap(find.text('Speednet'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('تفعيل كود'), findsNothing);
    expect(find.text('حذف الشركة'), findsWidgets);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('حسابٌ بلا شركاتٍ متوقّفة: لا شريط ولا شارة (كما كان)', (t) async {
    account.companies = [
      for (final c in _companies()) {...c, 'locked': false}
    ];
    await pump(t);
    expect(find.text('انتهت التجربة للشركات الأخرى'), findsNothing);
    expect(find.text('متوقّفة'), findsNothing);
    expect(find.byTooltip('حذف الشركة'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  test('LinkedCompany.locked: من الخادم، وغيابه false', () {
    expect(LinkedCompany.fromJson({'sasCode': 'x', 'username': 'u', 'locked': true}).locked, isTrue);
    expect(LinkedCompany.fromJson({'sasCode': 'x', 'username': 'u'}).locked, isFalse);
  });
}
