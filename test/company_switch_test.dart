import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/auth_api.dart';
import 'package:rad_mysvcs/screens/account/company_open_flow.dart';
import 'package:rad_mysvcs/screens/account/company_switch_sheet.dart';
import 'package:rad_mysvcs/screens/dashboard/dashboard_screen.dart';
import 'package:rad_mysvcs/services/account_service.dart';
import 'package:rad_mysvcs/services/active_company.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/company_creds_store.dart';
import 'package:rad_mysvcs/services/linked_companies.dart';
import 'package:rad_mysvcs/services/saved_profiles_store.dart';
import 'package:rad_mysvcs/services/sas_login_flow.dart';
import 'package:rad_mysvcs/widgets/active_company_line.dart';

import 'support/ai_status_overlay.dart';
import 'visual_perm/visual_perm_harness.dart';
import 'package:rad_mysvcs/screens/top_actions.dart';

/// «تبديل الشركة» داخل التطبيق (طلب المالك ٢١ أكتوبر): مربّعٌ جنب «الصفحات»
/// في ترويسة الرئيسيّة — أو الاسم وسطر الشركة زرّه حين لا يتّسع العرض — يفتح
/// ورقة شركات الحساب، والدخول مسار «شركاتي» نفسه ([CompanyOpenFlow]).
///
/// و«تحسب حساب التنقّل بينهم»: مرجع «العودة للأصل» في «الصفحات» يخصّ شركته
/// وحدها، وفتح شركةٍ يُنهي أيّ تبديلٍ لمديرٍ فرعيٍّ سبقه.
void main() {
  final shell0 = CompanyOpenFlow.shellBuilder;
  const supernetUrl = 'https://reseller-supernet.net';
  const jtUrl = 'https://sas.jt.iq';

  LinkedCompany co(String code, String? url, String user,
          {String role = 'admin', String? label}) =>
      LinkedCompany(
          sasCode: code,
          sasUrl: url,
          username: user,
          label: label ?? code,
          role: role);

  ActiveCompanyInfo at(String code, String url, String user,
          {bool emp = false}) =>
      ActiveCompanyInfo(
          label: code,
          sasCode: code,
          sasUrl: url,
          username: user,
          isEmployee: emp);

  group('مربّع «الشركات» حين يبقى للاسم عرضه', () {
    bool fits(double w, int squares, {double scale = 1}) {
      final narrow = w < 360;
      return CompanySwitch.fitsSquare(
          width: w,
          textScale: scale,
          squares: squares,
          side: narrow ? 38 : 42,
          gap: narrow ? 6 : 8);
    }

    test('خمسة مربّعات (الشركات · الصفحات · المساعد · الجرس · الترس)', () {
      expect(fits(430, 5), isTrue); // يبقى للاسم 148
      expect(fits(412, 5), isTrue); // 130
      expect(fits(390, 5), isTrue); // 108
      expect(fits(375, 5), isFalse); // 93 ⇒ الاسم والسطر زرّه
      expect(fits(360, 5), isFalse); // 78
      expect(fits(320, 5), isFalse); // 66
    });

    test('بلا المساعد (أربعة مربّعات) يتّسع حتى ٣٢٠', () {
      expect(fits(360, 4), isTrue); // 128
      expect(fits(320, 4), isTrue); // 110
    });

    test('خطّ النظام المكبَّر يحتاج عرضاً أكبر', () {
      expect(fits(390, 5, scale: 1.2), isFalse); // 108 < 124.8
      expect(fits(430, 5, scale: 1.2), isTrue);
    });
  });

  group('حال صفوف الورقة من الجلسة القائمة', () {
    final two = [co('supernet', supernetUrl, 'mahdi'), co('jt', jtUrl, 'ali.jt')];

    test('الصفحة نفسها (الساس واليوزر، بلا حساسيّة حالة) ⇒ «مفتوحة الآن» وحدها', () {
      expect(companyRowStates(two, at('supernet', supernetUrl, 'Mahdi')),
          [CompanyRowState.current, CompanyRowState.other]);
    });

    test('مديرٌ فرعيٌّ بُدّل إليه من «الصفحات» ⇒ صفحة ساسه «مفتوحة بحساب …»', () {
      expect(companyRowStates(two, at('jt', jtUrl, 'jt.sub1')),
          [CompanyRowState.other, CompanyRowState.insideAsOther]);
    });

    test('صفحتان على الساس نفسه ⇒ المفتوحة وحدها، والأخرى تُفتح', () {
      final same = [
        co('jt', jtUrl, 'ali.jt'),
        co('jt', 'https://www.sas.jt.iq/admin', 'jt.two'),
      ];
      expect(companyRowStates(same, at('jt', jtUrl, 'jt.two')),
          [CompanyRowState.other, CompanyRowState.current]);
    });

    test('الساس بالمضيف حين يغيب الكود', () {
      expect(companyRowStates(two, at('', 'https://SAS.jt.iq/', 'ali.jt')),
          [CompanyRowState.other, CompanyRowState.current]);
    });

    test('جلسة موظّف، أو بلا شركة، أو ربطٌ كموظّف ⇒ لا «مفتوحة»', () {
      expect(companyRowStates(two, at('jt', jtUrl, 'ali.jt', emp: true)),
          [CompanyRowState.other, CompanyRowState.other]);
      expect(companyRowStates(two, null),
          [CompanyRowState.other, CompanyRowState.other]);
      expect(
          companyRowStates([co('jt', jtUrl, 'ali.jt', role: 'employee')],
              at('jt', jtUrl, 'ali.jt')),
          [CompanyRowState.other]);
    });
  });

  group('مرجع «العودة للأصل» يخصّ شركته وحدها', () {
    const vault = FlutterSecureStorage();

    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    /// مرجعٌ كما كتبه ٣.٠.٥ فما قبله — بلا ساس.
    Future<void> legacyOriginal(String user, String password) async {
      final enc = await SavedProfilesStore.encrypt(password);
      await vault.write(
          key: 'switcher.original',
          value: jsonEncode({'u': user, 'p': enc, 'n': user, 'o': 'accounts'}));
    }

    test('من الشركة نفسها (المضيف نفسه) ⇒ يبقى', () async {
      await SavedProfilesStore.setOriginal(
          username: 'ali.jt', plainPassword: 'p1', sasUrl: jtUrl);
      final o =
          await SavedProfilesStore.originalFor('https://www.SAS.jt.iq/admin');
      expect(o?.username, 'ali.jt');
      expect(o?.password, 'p1');
    });

    test('🚨 بعد فتح شركةٍ أخرى ⇒ لا «العودة لـ…» ويُمسح المرجع', () async {
      await SavedProfilesStore.setOriginal(
          username: 'ali.jt', plainPassword: 'p1', sasUrl: jtUrl);
      expect(await SavedProfilesStore.originalFor(supernetUrl), isNull);
      expect(await SavedProfilesStore.readOriginal(), isNull);
    });

    test('مرجعٌ قديم تطابق كلمة سرّه هذه الشركة ⇒ يُقبل ويُختم بساسها', () async {
      await legacyOriginal('ali.jt', 'p1');
      await CompanyCredsStore.upsert(
          sasUrl: jtUrl, username: 'ali.jt', password: 'p1');
      final o = await SavedProfilesStore.originalFor(jtUrl);
      expect(o?.username, 'ali.jt');
      expect((await SavedProfilesStore.readOriginal())?.sasUrl, jtUrl);
    });

    test('مرجعٌ قديم من شركةٍ أخرى ⇒ يُمسح', () async {
      await legacyOriginal('ali.jt', 'p1');
      await CompanyCredsStore.upsert(
          sasUrl: jtUrl, username: 'ali.jt', password: 'p1');
      expect(await SavedProfilesStore.originalFor(supernetUrl), isNull);
      expect(await SavedProfilesStore.readOriginal(), isNull);
    });
  });

  group('الترويسة والورقة', () {
    setUpAll(visualSetUpAll);

    final square = find.byKey(const ValueKey('top-actions-company-switch'));
    const longName = 'جي تي نت للاتصالات وخدمات الإنترنت — فرع الكرادة الشرقية';
    final linked = [
      co('supernet', supernetUrl, 'mahdi', label: 'سوبرنت'),
      co('jt', jtUrl, 'ali.jt', label: longName),
    ];

    late AiStatusOverlay server;
    late _AccountServer account;
    late List<Map<String, Object?>> completed;

    Future<void> setUpOwner(
      Scenario s, {
      List<LinkedCompany>? companies,
      Map<String, dynamic>? ai,
      Map<String, Object> routes = const {},
    }) async {
      final inner = await visualSetUp(s);
      server = AiStatusOverlay(inner, status: ai ?? aiStatusOff, routes: {...routes});
      ApiClient.dio.httpClientAdapter = server;
      AiAssistantState.reset();
      AiAssistantState.now = DateTime.now;
      final list = companies ?? linked;
      account = _AccountServer(list);
      AccountApi.dio.httpClientAdapter = account;
      AccountApi.tokenSource = ({bool force = false}) async => 'account-test';
      LinkedCompanies.reset();
      LinkedCompanies.items.value = List.unmodifiable(list);
      completed = [];
      CompanyOpenFlow.completeSession = (
        LoginSuccess res, {
        required String username,
        required String password,
        required String sasUrl,
        required bool remember,
        String? companyLabel,
        String? sasCode,
      }) async {
        completed.add({
          'user': username,
          'sas': sasUrl,
          'label': companyLabel,
          'code': sasCode,
          'admin': res.adminId,
        });
        return SasLoginOutcome.ok;
      };
      CompanyOpenFlow.shellBuilder =
          () => const Scaffold(body: Center(child: Text('SHELL')));
    }

    Future<void> finish(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      await visualTearDown();
      LinkedCompanies.reset();
      AiAssistantState.reset();
      AccountApi.tokenSource = AccountService.idToken;
      CompanyOpenFlow.completeSession = SasLoginFlow.completeSafely;
      CompanyOpenFlow.shellBuilder = shell0;
    }

    Future<void> openDashboard(WidgetTester t, double width) async {
      await pumpVisual(t, VisualDevice('', Size(width, 932), 3),
          home: (_) => const DashboardScreen());
      await settle(t);
      expect(t.takeException(), isNull);
    }

    testWidgets('عرضٌ يتّسع ⇒ مربّع «الشركات» جنب «الصفحات» من جهة الاسم',
        (t) async {
      await setUpOwner(s1bSasOwner);
      await openDashboard(t, 430);
      expect(square, findsOneWidget);
      expect(find.byType(CompanySwitchLine), findsNothing);
      // «الصفحات» بمكانه، والشركات يمينه (أقرب للاسم بالعربيّة).
      final pages = find.byTooltip('الصفحات');
      expect(pages, findsOneWidget);
      expect(t.getRect(square).left, greaterThan(t.getRect(pages).right));
      await t.tap(square);
      await settle(t, seconds: 2);
      expect(find.text('تبديل الشركة'), findsWidgets);
      expect(find.text(longName), findsOneWidget, reason: 'الاسم كاملاً بسطرين');
      expect(find.text('مفتوحة الآن'), findsOneWidget);
      await finish(t);
    });

    testWidgets('عرضٌ ضيّق والمساعد ظاهر ⇒ الاسم وسطر الشركة زرّه (بالارتفاع نفسه)',
        (t) async {
      await setUpOwner(s1bSasOwner, ai: aiStatusOn);
      await openDashboard(t, 375);
      expect(square, findsNothing);
      expect(find.byType(CompanySwitchLine), findsOneWidget);
      final line = find.descendant(
          of: find.byType(CompanySwitchLine),
          matching: find.byType(ActiveCompanyLine));
      expect(t.getSize(find.byType(CompanySwitchLine)).height,
          moreOrLessEquals(t.getSize(line).height, epsilon: 0.5),
          reason: 'السهم لا يزيد ارتفاع الترويسة المحسوب');
      await t.tap(find.byType(CompanySwitchTap));
      await settle(t, seconds: 2);
      expect(find.text('تبديل الشركة'), findsWidgets);
      await finish(t);
    });

    // ٢٢ أكتوبر (المالك: «زرّ التبديل بين الأدمنية والصفحات مو موجود بكلّ صفحات
    // التطبيق»): رأس كلّ تبويب ([TabHeader]) يحمل «الشركات» و«الصفحات» كالرئيسيّة.
    for (final w in [320.0, 360.0, 430.0]) {
      testWidgets('رأس التبويب على $w: «الشركات» و«الصفحات» والعنوان كاملاً', (t) async {
        await setUpOwner(s1bSasOwner, ai: aiStatusOn);
        await pumpVisual(t, VisualDevice('', Size(w, 932), 3),
            home: (_) => Scaffold(
                  body: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TabHeader(title: 'المشتركون', subtitle: const Text('سطر')),
                    ),
                  ),
                ));
        await settle(t);
        expect(t.takeException(), isNull, reason: 'لا فيضان على $w');
        expect(square, findsOneWidget);
        expect(find.byTooltip('الصفحات'), findsOneWidget);
        expect(find.text('المشتركون'), findsOneWidget, reason: 'يصغر ولا يُبتر');
        await t.tap(square);
        await settle(t, seconds: 2);
        expect(find.text('تبديل الشركة'), findsWidgets);
        await finish(t);
      });
    }

    testWidgets('شركةٌ واحدة ⇒ لا زرّ ولا سهم', (t) async {
      await setUpOwner(s1bSasOwner, companies: [linked.first]);
      await openDashboard(t, 430);
      expect(square, findsNothing);
      expect(find.byType(CompanySwitchLine), findsNothing);
      await finish(t);
    });

    testWidgets('موظّف ⇒ لا زرّ (ولا سؤال عن شركات الحساب)', (t) async {
      await setUpOwner(s2ElEmpSubs);
      await openDashboard(t, 430);
      expect(square, findsNothing);
      expect(find.byType(CompanySwitchLine), findsNothing);
      expect(account.calls, 0);
      await finish(t);
    });

    testWidgets('🚨 فتح شركةٍ أخرى: مسار «شركاتي» نفسه، ويُنهي تبديل المدير الفرعيّ',
        (t) async {
      await setUpOwner(s1bSasOwner, routes: {
        'POST /api/auth/login': {
          'success': true,
          'token': 'jt-session',
          'user': {'id': 'jt:77', 'username': 'ali.jt', 'role': 'admin'},
        },
      });
      await CompanyCredsStore.upsert(
          sasUrl: jtUrl, username: 'ali.jt', password: 'pw-jt');
      // تبديلٌ سابق لمديرٍ فرعيٍّ في سوبرنت.
      await SavedProfilesStore.setOriginal(
          username: 'mahdi', plainPassword: 'pw-main', sasUrl: supernetUrl);
      await openDashboard(t, 430);
      await t.tap(square);
      await settle(t, seconds: 2);

      // الصفحة المفتوحة لا تُنقر.
      await t.tap(find.text('سوبرنت').last);
      await settle(t, seconds: 1);
      expect(server.requests.where((r) => r.path == '/api/auth/login'), isEmpty);

      await t.tap(find.text(longName));
      await settle(t, seconds: 3);
      final logins =
          server.requests.where((r) => r.path == '/api/auth/login').toList();
      expect(logins, hasLength(1));
      expect((logins.single.data as Map)['sasUrl'], jtUrl,
          reason: 'دخول ساس الشركة المختارة لا ساس الجلسة');
      expect(completed, [
        {
          'user': 'ali.jt',
          'sas': jtUrl,
          'label': longName,
          'code': 'jt',
          'admin': 'jt:77',
        }
      ]);
      expect(await SavedProfilesStore.readOriginal(), isNull,
          reason: 'لا «العودة لـ…» من الشركة السابقة');
      expect(find.text('SHELL'), findsOneWidget, reason: 'التطبيق كلّه من جديد');
      await finish(t);
    });

    testWidgets('رفضٌ يخصّ الشركة (حدّ الشركات) ⇒ رسالته بالورقة والجلسة كما هي',
        (t) async {
      await setUpOwner(s1bSasOwner, routes: {
        'POST /api/auth/login': {
          'success': false,
          'error': 'company-limit',
          'message': 'بلغت حدّ الشركات لباقتك',
        },
      });
      await CompanyCredsStore.upsert(
          sasUrl: jtUrl, username: 'ali.jt', password: 'pw-jt');
      await SavedProfilesStore.setOriginal(
          username: 'mahdi', plainPassword: 'pw-main', sasUrl: supernetUrl);
      await openDashboard(t, 430);
      await t.tap(square);
      await settle(t, seconds: 2);
      await t.tap(find.text(longName));
      await settle(t, seconds: 3);
      expect(find.text('بلغت حدّ الشركات لباقتك'), findsOneWidget);
      expect(completed, isEmpty);
      expect(find.text('SHELL'), findsNothing);
      expect((await SavedProfilesStore.readOriginal())?.username, 'mahdi',
          reason: 'دخولٌ مرفوض لا يمسّ شيئاً');
      expect(ActiveCompany.current?.sasCode, 'supernet');
      await finish(t);
    });
  });
}

/// `GET /api/account/companies` — شركات الحساب، ويعدّ النداءات.
class _AccountServer implements HttpClientAdapter {
  _AccountServer(this.companies);
  final List<LinkedCompany> companies;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (o.path == '/api/account/companies') {
      calls++;
      return ResponseBody.fromString(
        jsonEncode({
          'success': true,
          'companies': [
            for (final c in companies)
              {
                'sasCode': c.sasCode,
                'sasUrl': c.sasUrl,
                'username': c.username,
                'label': c.label,
                'role': c.role,
              }
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );
    }
    return ResponseBody.fromString('{"success":false}', 404, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}
