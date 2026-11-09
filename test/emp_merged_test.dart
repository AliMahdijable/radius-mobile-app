import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/merged_dashboard_api.dart';
import 'package:rad_mysvcs/api/merged_devices_api.dart';
import 'package:rad_mysvcs/api/merged_finance_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/merged_company.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/dashboard/dashboard_screen.dart';
import 'package:rad_mysvcs/screens/employees/sheets/employee_pages_sheet.dart';
import 'package:rad_mysvcs/screens/expenses/expenses_screen.dart';
import 'package:rad_mysvcs/screens/reports/financial_report_screen.dart';
import 'package:rad_mysvcs/screens/settlements/settlements_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/subscriber_detail_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/subscribers_screen.dart';
import 'package:rad_mysvcs/screens/subscribers/widgets/filter_chips_bar.dart';
import 'package:rad_mysvcs/services/auth_storage.dart';
import 'package:rad_mysvcs/services/employee_session.dart';
import 'package:rad_mysvcs/services/merged_mode.dart';
import 'package:rad_mysvcs/services/merged_report_loader.dart';
import 'package:rad_mysvcs/widgets/merged_company_strip.dart';
import 'package:rad_mysvcs/widgets/merged_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'emp_merged/emp_merged_fixture.dart';
import 'visual_perm/visual_perm_harness.dart';

/// «كل الصفحات» للموظّف — المحاكاة (٩ نوفمبر، المالك: «تكمل وسوي محاكه لوضع الموظفين الي مسنودين لاكثر من صفحه — وينعرضون
/// اليوزرية كلهم مثل ما المدير والاجهزه والفحص الشامل والخ (حاله حال المدير حسب الصلاحيات المعطاه اله)»).
///
/// موظّفٌ بأربع صفحات (emp_merged_fixture.dart): ألف صفحته الحاليّة بكلّ الصلاحيّات، باء ساسٌ بعيد بلا مالٍ ولا أجهزة (403
/// مسمّاة)، جيم ايرث لنك، دال معطّلٌ فيها. المعترضات الحقيقيّة على ApiClient.dio، والخادم وهميٌّ يردّ بالمسار + المفتاح.
Subscriber _sub(String? key, String idx, {int debt = 0}) => Subscriber(
      idx: idx,
      username: 'u$idx',
      firstname: 'مشترك',
      lastname: idx,
      notes: debt == 0 ? null : '-$debt',
      companyKey: key,
    );

void main() {
  setUpAll(visualSetUpAll);

  bool noAccountToken(EmpServer srv) => srv.all.every((o) => !o.headers.containsKey('x-account-token'));

  group('١ الطلب الموجَّه للموظّف (المعترض)', () {
    testWidgets('١-١ توكنه هو (Bearer + x-auth-token) ومفتاح الصفحة — لا توكن حسابٍ يُسأل ولا يُرسل', (t) async {
      final srv = await empUp();
      await t.runAsync(() => MergedMode.load(fresh: true));
      final list = srv.all.firstWhere((o) => o.uri.path == '/api/v2/employee-merged/companies');
      expect(list.headers['Authorization'], 'Bearer $empToken', reason: 'صفحاته تُسأل بتوكنه');
      expect(list.headers.containsKey('x-company-key'), isFalse, reason: 'سؤال الصفحات طلبٌ عاديّ لا موجَّه');
      final r = await t.runAsync(() => CompanyRoute.run(kB, () => ApiClient.dio.get<dynamic>('/api/v2/subscribers')));
      expect(r!.statusCode, 200);
      final o = srv.routed.single;
      expect(o.headers['x-company-key'], kB);
      expect(o.headers['Authorization'], 'Bearer $empToken');
      expect(o.headers['x-auth-token'], empToken);
      expect(o.headers.containsKey('x-account-token'), isFalse);
      expect(o.extra['_routedEmp'], isTrue);
      expect(accountTokenAsked, 0, reason: 'لا حساب له — لا يُطلب توكن حساب');
      await empDown();
    });

    testWidgets('١-٢ المالك كما كان حرفاً: توكن الحساب + المفتاح، بلا Authorization ولا x-auth-token، ولا قفل مسبق', (t) async {
      final inner = await visualSetUp(s1bSasOwner);
      final srv = EmpServer(inner);
      ApiClient.dio.httpClientAdapter = srv;
      AccountApi.tokenSource = ({bool force = false}) async => 'acct-1';
      MergedMode.reset();
      await t.runAsync(() => CompanyRoute.run(kB, () => ApiClient.dio.get<dynamic>('/api/v2/admin-widgets')));
      final o = srv.routed.single;
      expect(o.headers['x-account-token'], 'acct-1');
      expect(o.headers['x-company-key'], kB);
      expect(o.headers.containsKey('Authorization'), isFalse);
      expect(o.headers.containsKey('x-auth-token'), isFalse);
      expect(o.extra.containsKey('_routedEmp'), isFalse);
      expect(MergedMode.employeeSession, isFalse);
      expect(MergedMode.writeLockFor(kB), isNull, reason: 'المالك: الخادم يحكم كتابته كما كان');
      // نصّ رفض المالك كما كان (رسالة الخادم بلا اسم الشركة)
      const c = MergedCompany(key: kB, code: 'jt', username: 'u', name: nameB, provider: MergedProvider.sas4, colorIndex: 1,
          adminId: 'jt:1', ns: 'n', currency: 'IQD', home: false, status: MergedStatus.ok, index: 1);
      expect(MergedMode.failText(c, {'success': false, 'code': 'PERMISSION_DENIED', 'message': 'ليس لديك صلاحيّة'}, 'x', status: 403),
          'ليس لديك صلاحيّة');
      await visualTearDown();
    });

    testWidgets('١-٣ جمع المشتركين: كلّ طلبٍ بمفتاح صفحته (ألف وباء وجيم)، والمعطّلة لا تُطلب وتُسمّى', (t) async {
      final srv = await empUp();
      final r = await t.runAsync(() => MergedSubscribers.load(fresh: true));
      expect(srv.routed.map((o) => o.headers['x-company-key']).toSet(), {kA, kB, kC});
      for (final o in srv.routed) {
        expect(o.headers['Authorization'], 'Bearer $empToken', reason: '${o.uri.path} @${o.headers['x-company-key']}');
        expect(o.headers['x-auth-token'], empToken);
      }
      expect(noAccountToken(srv), isTrue);
      expect(r!.rows.map((s) => '${s.companyKey}:${s.idx}').toSet(),
          {'$kA:1', '$kA:2', '$kA:3', '$kB:1', '$kB:9', '$kC:21', '$kC:22'}, reason: 'idx 1 في ساسين ⇒ صفّان');
      expect(r.missing.map((c) => c.name), [nameD]);
      expect(r.failed, isEmpty);
      await empDown();
    });

    testWidgets('١-٤ ٤٠١ بلا صدى = جلسته هو انتهت ⇒ مسار الطرد العاديّ برسالة الخادم (لا 409 الصدى المصطنع)', (t) async {
      final srv = await empUp();
      await t.runAsync(() => MergedMode.enter());
      expect(MergedMode.active.value, isTrue);
      await t.runAsync(EmployeeSession.leaveToAccount); // بلا سببٍ معلّق من اختبارٍ سابق
      srv.sessionEnded = true;
      final before = authExpiredSignal.value;
      final r = await t.runAsync(() => CompanyRoute.run(kB, () => ApiClient.dio.get<dynamic>('/api/v2/subscribers')));
      expect(r!.statusCode, 401);
      expect((r.data as Map)['code'], 'EMPLOYEE_SESSION_REVOKED', reason: 'ردّ الخادم كما هو — لا COMPANY_ROUTE_ECHO');
      expect(authExpiredSignal.value, before + 1, reason: 'طُرد مرّةً');
      expect(EmployeeSession.kickMessage, revokedText, reason: 'بسبب الخادم لا «انتهت الجلسة»');
      expect(await t.runAsync(AuthStorage.readToken), isNull, reason: 'الجلسة مُسحت');
      expect(MergedMode.active.value, isFalse, reason: 'SessionManager صفّر الوضع');
      await empDown();
    });

    testWidgets('١-٥ ٤٠١ بصدى المفتاح = رفض تلك الصفحة (SESSION_REQUIRED) ⇒ يمرّ برسالته ولا تُمسّ جلسته', (t) async {
      final srv = await empUp();
      srv.sessionRequiredFor = kB;
      final before = authExpiredSignal.value;
      final r = await t.runAsync(() => CompanyRoute.run(kB, () => ApiClient.dio.get<dynamic>('/api/v2/subscribers')));
      expect(r!.statusCode, 401);
      expect((r.data as Map)['code'], 'SESSION_REQUIRED');
      expect(authExpiredSignal.value, before, reason: 'لا طرد');
      expect(await t.runAsync(AuthStorage.readToken), empToken);
      await empDown();
    });

    testWidgets('١-٦ بلا صدى: البيانات لا تُقبل (409 الصدى «…الصفحة»)، ورفض حرّاس الموظّف يمرّ برسالته', (t) async {
      final srv = await empUp();
      srv.dropEcho = true;
      final r = await t.runAsync(() => CompanyRoute.run(kB, () => ApiClient.dio.get<dynamic>('/api/v2/subscribers')));
      expect(r!.statusCode, 409);
      expect((r.data as Map)['code'], CompanyRouteCodes.echo);
      expect((r.data as Map)['message'], contains('الصفحة'));
      srv.disabledFor = kB;
      final r2 = await t.runAsync(() => CompanyRoute.run(kB, () => ApiClient.dio.get<dynamic>('/api/v2/subscribers')));
      expect(r2!.statusCode, 403);
      expect((r2.data as Map)['code'], 'EMPLOYEE_DISABLED', reason: 'رفضٌ بلا بيانات — رسالته تُعرض');
      await empDown();
    });
  });

  group('٢ الكتابة', () {
    testWidgets('٢-١ على صفحته الحاليّة: هويّة المشترك أوّلاً ثمّ التسديد بمرجعه وتوكنه — ينجح', (t) async {
      final srv = await empUp();
      await t.runAsync(() => MergedMode.load(fresh: true));
      final s = _sub(kA, '2', debt: 5000);
      expect(MergedOps.writeLock(s), isNull);
      final r = await t.runAsync(() => MergedOps.write(s, () => SubscribersApi.payDebt(idx: '2', amount: 5000, skipAutoWa: true)));
      expect(r!.ok, isTrue, reason: '${r.message}');
      final get = srv.routed.firstWhere((o) => o.method == 'GET' && o.uri.path == '/api/v2/subscribers/2');
      expect(get.headers['x-company-key'], kA);
      final pay = srv.routed.firstWhere((o) => o.method == 'POST');
      expect(pay.uri.path, '/api/v2/subscribers/2/pay-debt');
      expect(pay.headers['x-company-key'], kA);
      expect(pay.headers['x-company-ref'], 'r_${'S' * 22}');
      expect(pay.headers['Authorization'], 'Bearer $empToken');
      expect(noAccountToken(srv), isTrue);
      await empDown();
    });

    testWidgets('٢-٢ على صفحةٍ أخرى: مقفلةٌ قبل الإرسال بسببها — لا يصل الخادمَ طلب كتابة', (t) async {
      final srv = await empUp();
      await t.runAsync(() => MergedMode.load(fresh: true));
      final s = _sub(kB, '9', debt: 2500);
      expect(MergedOps.writeLock(s), MergedMode.writeLockedText);
      expect(MergedMode.writeLockedText, 'انتقل إلى الصفحة من «صفحاتي» لتنفيذها');
      expect(MergedOps.writeLock(_sub(kC, '22')), MergedMode.writeLockedText);
      // ولو نُودي مباشرةً (مدخلٌ نُسي قفله): المعترض لا يرسلها — ردٌّ محلّيّ بالسبب
      final r = await t.runAsync(() => MergedOps.write(s, () => SubscribersApi.payDebt(idx: '9', amount: 2500, skipAutoWa: true)));
      expect(r!.ok, isFalse);
      expect(r.message, MergedMode.writeLockedText);
      expect(srv.routed.where((o) => o.method != 'GET'), isEmpty, reason: 'لم يُرسل شيء');
      await empDown();
    });

    testWidgets('٢-٣ «فُرضت» (ردّ الصفحات قال مفتوحة والخادم أوقفها): رسالة الخادم 409 WRITES_PAUSED تُعرض كما هي', (t) async {
      final srv = await empUp(companies: companiesBody(writesB: true));
      await t.runAsync(() => MergedMode.load(fresh: true));
      final s = _sub(kB, '9', debt: 2500);
      expect(MergedOps.writeLock(s), isNull, reason: 'الردّ قال مفتوحة');
      final r = await t.runAsync(() => MergedOps.write(s, () => SubscribersApi.payDebt(idx: '9', amount: 2500, skipAutoWa: true)));
      expect(r!.ok, isFalse);
      expect(r.message, pausedServerText);
      final post = srv.routed.singleWhere((o) => o.method == 'POST');
      expect(post.headers['x-company-key'], kB);
      expect(post.headers['x-company-ref'], 'r_${'S' * 22}', reason: 'الطلب المفروض يحمل مرجعه كغيره');
      await empDown();
    });

    testWidgets('٢-٤ أوقف الخادم التنفيذ كلّه (writes:false): صفحته الحاليّة أيضاً مقفلةٌ بسببٍ آخر — يخرج وينفّذها من صفحته', (t) async {
      await empUp(companies: companiesBody(writes: false));
      await t.runAsync(() => MergedMode.load(fresh: true));
      expect(MergedOps.writeLock(_sub(kA, '2')), MergedMode.writePausedHereText);
      expect(MergedOps.writeLock(_sub(kB, '9')), MergedMode.writeLockedText);
      expect(MergedOps.writeLock(_sub(null, '9')), isNull, reason: 'مشتركٌ بلا صفحة (الوضع العاديّ) لا يُقفل');
      await empDown();
    });
  });

  group('٣ الوضع للموظّف', () {
    testWidgets('٣-١ مؤهَّل بثلاث صفحات صالحة (المعطّلة خارجها)، وصفحته الحاليّة هي المفتوحة — بمعرّفها لا بمعرّف جلسته', (t) async {
      await empUp();
      expect(MergedMode.employeeSession, isTrue);
      await t.runAsync(() => MergedMode.load(fresh: true));
      expect(MergedMode.eligible, isTrue);
      expect(MergedMode.usable.map((c) => c.key), [kA, kB, kC]);
      expect(MergedMode.companyOf(kD)!.message, contains('معطّل'));
      expect(MergedMode.currentPage?.key, kA);
      expect(MergedMode.currentPage?.employeeId, 11);
      expect(await t.runAsync(AuthStorage.readAdminId), 'supernet:12', reason: 'جلسته تحفظ معرّفاً بصيغةٍ أخرى');
      expect(await t.runAsync(MergedMode.openAdminId), '2251', reason: 'المفتوحة = صفحته الحاليّة من ردّ صفحاته');
      await empDown();
    });

    testWidgets('٣-٢ أقلّ من صفحتين (companies:[]) ⇒ لا «كل الصفحات»', (t) async {
      await empUp(companies: companiesBody(fewer: true));
      await t.runAsync(() => MergedMode.load(fresh: true));
      expect(MergedMode.eligible, isFalse);
      expect(await t.runAsync(MergedMode.enter), isFalse);
      await empDown();
    });

    testWidgets('٣-٣ التفضيل لكلّ موظّف (مفتاحٌ غير مفتاح المالك): يُحفظ، يعود عند الفتح، ويُمسح بالخروج', (t) async {
      await empUp();
      final login = MergedMode.employeeLogin;
      expect(login(), 'ali.m', reason: 'اسم دخوله من صفحاته (الأصليّة)');
      final key = 'merged.active.emp.${sha256.convert(utf8.encode('ali.m')).toString().substring(0, 16)}';
      expect(await t.runAsync(MergedMode.enter), isTrue);
      final p = (await t.runAsync(SharedPreferences.getInstance))!;
      expect(p.getBool(key), isTrue);
      expect(p.getKeys().where((k) => k.startsWith('merged.active.') && !k.startsWith('merged.active.emp.')), isEmpty);
      // تبديل صفحةٍ/خروج: SessionManager يصفّر — وفتح التطبيق يعيده
      MergedMode.reset();
      expect(MergedMode.active.value, isFalse);
      await t.runAsync(MergedMode.restore);
      expect(MergedMode.active.value, isTrue);
      // موظّفٌ آخر على الجهاز نفسه لا يرثه
      MergedMode.reset();
      MergedMode.employeeLogin = () => 'other.emp';
      await t.runAsync(MergedMode.restore);
      expect(MergedMode.active.value, isFalse);
      MergedMode.employeeLogin = () => 'ali.m';
      await t.runAsync(MergedMode.restore);
      expect(MergedMode.active.value, isTrue);
      await t.runAsync(MergedMode.exit);
      expect(p.getBool(key), isNull);
      MergedMode.employeeLogin = login;
      await empDown();
    });

    testWidgets('٣-٤ مفتاح الإيقاف: سؤال الصفحات 409 ⇒ غير متاح برسالة الخادم؛ وردٌّ موجَّه 409 وهو فيه ⇒ يعود لصفحته', (t) async {
      final srv = await empUp();
      expect(await t.runAsync(MergedMode.enter), isTrue);
      final fell = MergedMode.fellBack.value;
      srv.killSwitch = true;
      final r = await t.runAsync(() => CompanyRoute.run(kB, () => ApiClient.dio.get<dynamic>('/api/v2/subscribers')));
      expect((r!.data as Map)['code'], CompanyRouteCodes.disabled);
      expect(MergedMode.active.value, isFalse, reason: 'عاد لصفحته');
      expect(MergedMode.stopped.value, stopText);
      expect(MergedMode.fellBack.value, fell + 1, reason: 'MainShell يقول لماذا مرّةً');
      expect(MergedMode.eligible, isFalse);
      // فتح «صفحاتي» لاحقاً: سؤالٌ طازج يقول الشيء نفسه
      await t.runAsync(() => MergedMode.load(fresh: true));
      expect(MergedMode.eligible, isFalse);
      expect(MergedMode.stopped.value, stopText);
      expect(await t.runAsync(MergedMode.enter), isFalse);
      // أُعيد فتحه
      srv.killSwitch = false;
      await t.runAsync(() => MergedMode.load(fresh: true));
      expect(MergedMode.eligible, isTrue);
      expect(MergedMode.stopped.value, isNull);
      await empDown();
    });
  });

  group('٤ الرفض المسمّى (صلاحيّاته في كلّ صفحة)', () {
    testWidgets('٤-١ قائمة صفحةٍ ترفض الصلاحيّة ⇒ تُسمّى بها (لا صفر ولا «ليس لديك صلاحيّة» بلا اسم)', (t) async {
      final srv = await empUp();
      srv.listDeniedB = true;
      final r = await t.runAsync(() => MergedSubscribers.load(fresh: true));
      final f = r!.failed.single;
      expect(f.company.key, kB);
      expect(f.error, 'ليس لديك صلاحيّة لهذا في «$nameB»');
      expect(r.rows.where((s) => s.companyKey == kB), isEmpty);
      await empDown();
    });

    testWidgets('٤-٢ الرصيد: باء بلا reports.financial بخريطتها — الخادم يردّ رقماً (الساس لا يقنّع) ولا يُطلب ولا يُعرض، ويُسمّى', (t) async {
      final srv = await empUp();
      await t.runAsync(() => MergedMode.load(fresh: true));
      expect(MergedMode.companyOf(kB)!.permissions!['reports.financial'], isFalse);
      final w = await t.runAsync(MergedDashboardApi.wallet);
      expect(w!.byKey.keys.toSet(), {kA, kC});
      expect(w.value!.balance, 150000 + 90000, reason: 'رقم باء (77,000) لا يدخل');
      expect(w.reasons[kB], 'لا صلاحيّة لك على رصيدها');
      expect(w.excluded, ['$nameB: لا صلاحيّة لك على رصيدها']);
      final asked = srv.routed.where((o) => o.uri.path == '/api/v2/admin-widgets').map((o) => o.headers['x-company-key']).toSet();
      expect(asked, {kA, kC}, reason: 'رصيد باء لا يُطلب أصلاً');
      await empDown();
    });

    testWidgets('٤-٢ب خادمٌ أقدم بلا خرائط: كما كان — رقم باء يُعرض، والمقنَّع (null) يُسمّى', (t) async {
      final srv = await empUp(companies: companiesBody(withPerms: false));
      await t.runAsync(() => MergedMode.load(fresh: true));
      expect(MergedMode.companyOf(kB)!.permissions, isNull);
      expect(MergedMode.pagePerm(kB, 'reports.financial'), isNull);
      final w = await t.runAsync(MergedDashboardApi.wallet);
      expect(w!.value!.balance, 150000 + 77000 + 90000);
      srv.maskB = true;
      final w2 = await t.runAsync(MergedDashboardApi.wallet);
      expect(w2!.reasons[kB], 'لا صلاحيّة لك على رصيدها');
      expect(w2.value!.balance, 150000 + 90000);
      await empDown();
    });

    testWidgets('٤-٢ج تفعيلات اليوم وواتساب وتقارير القوائم: صفحةٌ بلا مفتاحها لا تُطلب وتُسمّى', (t) async {
      final srv = await empUp();
      await t.runAsync(() => MergedMode.load(fresh: true));
      final d = await t.runAsync(MergedDashboardApi.daily);
      expect(d!.reasons[kB], 'لا صلاحيّة لك على تفعيلاتها');
      expect(d.byKey.keys.toSet(), {kA, kC});
      final wa = await t.runAsync(MergedDashboardApi.whatsApp);
      expect(wa!.isDenied(kB), isTrue);
      expect([wa.connected, wa.total], [1, 2], reason: 'باء لا تُعدّ في «واتساب N/M»');
      final rep = await t.runAsync(() => loadMergedReport<int>(
            perms: const ['reports.daily_activations'],
            supports: (_) => true,
            fetch: (_) async => (ok: true, rows: const [1], error: null, note: null),
          ));
      final pb = rep!.partOf(kB)!;
      expect(pb.denied, isTrue);
      expect(pb.error, 'لا صلاحيّة لك على هذا التقرير فيها');
      expect(rep.total, 2, reason: 'ألف وجيم وحدهما');
      for (final path in ['/api/activities/daily-activations', '/api/whatsapp/connection-status/jt%3A6836']) {
        expect(srv.routed.where((o) => o.uri.path == Uri.decodeComponent(path) && o.headers['x-company-key'] == kB), isEmpty,
            reason: '$path لباء لا يُطلب');
      }
      expect(srv.routed.where((o) => o.headers['x-company-key'] == kB && o.uri.path.startsWith('/api/whatsapp/')), isEmpty);
      await empDown();
    });

    testWidgets('٤-٢د باء بلا subscribers.view: قائمتها لا تُطلب، تُسمّى «لا صلاحيّة» وصفوفها خارج الكلّ', (t) async {
      final srv = await empUp(companies: companiesWithB({...permsB, 'subscribers.view': false}));
      final r = await t.runAsync(() => MergedSubscribers.load(fresh: true));
      final f = r!.failed.single;
      expect(f.company.key, kB);
      expect(f.denied, isTrue);
      expect(f.error, '«$nameB»: لا صلاحيّة لك على مشتركيها');
      expect(r.rows.where((s) => s.companyKey == kB), isEmpty);
      expect(srv.routed.where((o) => o.headers['x-company-key'] == kB), isEmpty, reason: 'لا طلب لباء');
      await empDown();
    });

    testWidgets('٤-٣ التقرير الماليّ: باء (403) خارج المجموع مسمّاةً، والمجموع ألف + جيم', (t) async {
      await empUp();
      await t.runAsync(() => MergedMode.load(fresh: true));
      final srv = ApiClient.dio.httpClientAdapter as EmpServer;
      final m = await t.runAsync(() => MergedFinanceApi.load());
      expect(m!.included.map((p) => p.company.key).toSet(), {kA, kC});
      expect(m.excluded.single, '$nameB: لا صلاحيّة لك على تقريرها');
      expect(srv.routed.where((o) => o.uri.path == '/api/reports/finance' && o.headers['x-company-key'] == kB), isEmpty,
          reason: 'تقرير باء لا يُطلب');
      await empDown();
    });

    testWidgets('٤-٤ الأجهزة («الفحص الشامل» يقرأ منها): صفحته بطلبها العاديّ (تُدار)، جيم موجَّهة، باء 403 مسمّاة', (t) async {
      final srv = await empUp();
      await t.runAsync(() => MergedMode.load(fresh: true));
      final open = await t.runAsync(MergedMode.openAdminId);
      final parts = await t.runAsync(() => MergedDevicesApi.load(MergedMode.usable, openAdminId: open));
      MergedDevicesPart part(String k) => parts!.firstWhere((p) => p.company.key == k);
      expect(part(kA).open, isTrue, reason: 'أجهزة صفحته تُدار من هنا (كلمات سرّها بجلسته)');
      expect(part(kA).devices!.single.name, 'سكتر ألف 1');
      expect(part(kC).open, isFalse);
      expect(part(kC).devices!.single.name, 'برج جيم');
      expect(part(kB).failed, isTrue);
      expect(part(kB).error, '«$nameB»: لا صلاحيّة لك على أجهزتها');
      final devReqs = srv.all.where((o) => o.uri.path == '/api/v2/admin/devices').toList();
      expect(devReqs.map((o) => o.headers['x-company-key']).toList()..sort((a, b) => '$a'.compareTo('$b')),
          [null, kC]..sort((a, b) => '$a'.compareTo('$b')), reason: 'أجهزة باء لا تُطلب (بلا devices.view بخريطتها)');
      // خادمٌ أقدم بلا خرائط: تُطلب ورفضه (403) يُسمّى كما كان
      MergedMode.reset();
      srv.companies = companiesBody(withPerms: false);
      await t.runAsync(() => MergedMode.load(fresh: true));
      final old = await t.runAsync(() => MergedDevicesApi.load(MergedMode.usable, openAdminId: open));
      expect(old!.firstWhere((p) => p.company.key == kB).error, 'ليس لديك صلاحيّة لهذا في «$nameB»');
      await empDown();
    });
  });

  group('٥ الشاشات', () {
    Future<void> down(WidgetTester t) async {
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      await empDown();
    }

    testWidgets('٥-١ «صفحاتي»: «كل الصفحات» أعلاها بعدد الصالحة، والنقر يدخله بلا تسجيل', (t) async {
      await empUp();
      await pumpVisual(t, phone, home: (_) => const EmployeePagesSheet());
      await settle(t, seconds: 2);
      expect(find.text('كل الصفحات'), findsOneWidget);
      expect(find.textContaining('3 صفحات معاً'), findsOneWidget);
      expect(find.text(nameA), findsOneWidget, reason: 'صفحاته تحته كما كانت');
      await t.tap(find.text('كل الصفحات'));
      await settle(t, seconds: 2);
      expect(MergedMode.active.value, isTrue);
      expect(find.textContaining('اضغط للعودة لصفحتك'), findsOneWidget);
      await down(t);
    });

    testWidgets('٥-٢ «صفحاتي» ومفتاح الإيقاف: الخيار بمكانه خافتاً برسالة الخادم ولا يُنقر', (t) async {
      final srv = await empUp();
      srv.killSwitch = true;
      await pumpVisual(t, phone, home: (_) => const EmployeePagesSheet());
      await settle(t, seconds: 2);
      expect(find.text('كل الصفحات'), findsOneWidget);
      expect(find.text(stopText), findsOneWidget);
      await t.tap(find.text('كل الصفحات'));
      await settle(t, seconds: 1);
      expect(MergedMode.active.value, isFalse);
      await down(t);
    });

    testWidgets('٥-٣ المشتركون: صفوف الصفحات الثلاث بشارة كلٍّ منها، و«كل الصفحات · 3 صفحات»، والمعطّلة مسمّاة', (t) async {
      final srv = await empUp();
      await t.runAsync(MergedMode.enter);
      final cmd = ValueNotifier<SubscriberFilter?>(SubscriberFilter.all);
      await pumpVisual(t, phone, home: (_) => SubscribersScreen(filterCmd: cmd));
      await settle(t, seconds: 3);
      expect(find.textContaining('كل الصفحات · 3 صفحات • 7 مشترك'), findsOneWidget);
      Finder chip(String n) => find.descendant(of: find.byType(MergedCompanyStrip), matching: find.text(n));
      expect(chip('الكل'), findsOneWidget);
      expect(chip(nameA), findsOneWidget);
      expect(chip(nameB), findsOneWidget);
      expect(chip(nameC), findsOneWidget);
      expect(find.textContaining('لا تظهر هنا: $nameD'), findsOneWidget);
      expect(find.textContaining('اضغط صفحةً لعرضها وحدها'), findsOneWidget);
      expect(noAccountToken(srv), isTrue);
      // صفحةٌ وحدها
      await t.tap(chip(nameB));
      await settle(t, seconds: 1);
      expect(find.textContaining('«$nameB» • 2 مشترك'), findsOneWidget);
      await down(t);
    });

    testWidgets('٥-٤ الرئيسيّة: رصيد كلّ صفحةٍ بخانتها، وباء «لا صلاحيّة لك على رصيدها» لا صفر', (t) async {
      await empUp();
      await t.runAsync(MergedMode.enter);
      await pumpVisual(t, phone, home: (_) => const DashboardScreen());
      await settle(t, seconds: 3);
      expect(t.takeException(), isNull);
      expect(find.byType(MergedCompanyStrip), findsOneWidget);
      Finder tile(String k) => find.byKey(ValueKey('merged-balance-$k'));
      expect(find.descendant(of: tile(kA), matching: find.text('150,000')), findsOneWidget);
      expect(find.descendant(of: tile(kC), matching: find.text('90,000')), findsOneWidget);
      expect(find.descendant(of: tile(kB), matching: find.textContaining('لا صلاحيّة لك على رصيدها')), findsOneWidget,
          reason: 'لا صفر لصفحةٍ مرفوضة — سببها بخانتها');
      expect(find.textContaining('77,000'), findsNothing, reason: 'رقم باء الحقيقيّ (الساس لا يقنّعه) لا يظهر أبداً');
      // واتساب: باء بلا مفتاحه لا تُفحص ولا تُعدّ، وصفّها يقول لماذا
      expect(find.text('واتساب 1/2'), findsOneWidget);
      await t.tap(find.text('واتساب 1/2'));
      await settle(t, seconds: 1);
      expect(find.descendant(of: find.byKey(const ValueKey('wa-co-$kB')), matching: find.text('لا صلاحيّة لك على واتسابها')),
          findsOneWidget);
      Navigator.of(t.element(find.byKey(const ValueKey('wa-co-$kB')))).pop();
      await settle(t, seconds: 1);
      await down(t);
    });

    testWidgets('٥-٥ التقرير الماليّ: «حسب الصفحة»، وباء خارج المجموع باسمها', (t) async {
      await empUp();
      await t.runAsync(MergedMode.enter);
      await pumpVisual(t, phone, home: (_) => const FinancialReportScreen());
      await settle(t, seconds: 3);
      expect(find.text('حسب الصفحة'), findsOneWidget);
      expect(find.textContaining('خارج المجموع: $nameB'), findsOneWidget);
      await down(t);
    });

    testWidgets('٥-٦ صفحة مشتركٍ من صفحةٍ أخرى: «تسديد» و«تجديد» بمكانهما مقفلَين بالسبب — ولا طلب كتابة', (t) async {
      final srv = await empUp();
      await t.runAsync(() => MergedMode.load(fresh: true));
      MergedMode.active.value = true;
      final s = Subscriber.fromJson(Map<String, dynamic>.from(pageRows[kB]![1])).withCompany(kB);
      await pumpVisual(t, phone, home: (_) => SubscriberDetailScreen(sub: s));
      await settle(t, seconds: 2);
      await t.tap(find.text('تسديد').first);
      await settle(t, seconds: 1);
      expect(find.text(MergedMode.writeLockedText), findsOneWidget, reason: 'السبب لا «اطلبها من مديرك»');
      expect(find.byType(BottomSheet), findsNothing, reason: 'لا شيت');
      await settle(t, seconds: 3);
      await t.scrollUntilVisible(find.text('تجديد الاشتراك'), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('تجديد الاشتراك'));
      await settle(t, seconds: 1);
      // خريطة باء بلا subscribers.activate (ولو ملكها في صفحته الحاليّة): قفل الصلاحيّة يسبق سبب الصفحة — الانتقال إليها لا يفتحه
      expect(MergedMode.can(kB, 'subscribers.activate'), isFalse);
      expect(find.text('ليس لديك صلاحيّة لهذا الإجراء — اطلبها من مديرك'), findsOneWidget, reason: 'صلاحيّته في باء');
      expect(find.byType(BottomSheet), findsNothing);
      await settle(t, seconds: 3);
      // وما يملكه في باء (تسديد) لكنّ كتابتها من «صفحاتي»: سبب الصفحة
      srv.companies = companiesWithB({...permsB, 'subscribers.activate': true});
      await t.runAsync(() => MergedMode.load(fresh: true));
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      await pumpVisual(t, phone, home: (_) => SubscriberDetailScreen(sub: s));
      await settle(t, seconds: 2);
      await t.scrollUntilVisible(find.text('تجديد الاشتراك'), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('تجديد الاشتراك'));
      await settle(t, seconds: 1);
      expect(find.text(MergedMode.writeLockedText), findsOneWidget, reason: 'يملكه في باء ⇒ سبب الصفحة');
      expect(find.byType(BottomSheet), findsNothing);
      expect(srv.routed.where((o) => o.method != 'GET'), isEmpty);
      await settle(t, seconds: 3);
      await down(t);
    });

    testWidgets('٥-٦ب صفحة مشترك باء: كلمة سرّه لا تُطلب (لا subscribers.show_password بخريطة باء) — ومشترك ألف تُطلب', (t) async {
      final srv = await empUp();
      await t.runAsync(() => MergedMode.load(fresh: true));
      MergedMode.active.value = true;
      expect(MergedMode.can(kB, 'subscribers.view_activity'), isFalse, reason: 'خريطة باء لا صفحته الحاليّة');
      expect(MergedMode.can(kA, 'subscribers.view_activity'), isTrue);
      expect(MergedMode.can(null, 'subscribers.view_activity'), isTrue, reason: 'صفّ الوضع العاديّ ⇒ صلاحيّات الجلسة');
      final b = Subscriber.fromJson(Map<String, dynamic>.from(pageRows[kB]![0])).withCompany(kB);
      await pumpVisual(t, phone, home: (_) => SubscriberDetailScreen(sub: b));
      await settle(t, seconds: 2);
      expect(srv.routed.where((o) => o.uri.path.endsWith('/password')), isEmpty);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      final a = Subscriber.fromJson(Map<String, dynamic>.from(pageRows[kA]![0])).withCompany(kA);
      await pumpVisual(t, phone, home: (_) => SubscriberDetailScreen(sub: a));
      await settle(t, seconds: 2);
      expect(srv.routed.where((o) => o.uri.path.endsWith('/password')).map((o) => o.headers['x-company-key']).toSet(), {kA});
      await down(t);
    });

    testWidgets('٥-٧ صفحة مشتركٍ من صفحته الحاليّة: «تسديد» مفتوح', (t) async {
      await empUp();
      await t.runAsync(() => MergedMode.load(fresh: true));
      MergedMode.active.value = true;
      final s = Subscriber.fromJson(Map<String, dynamic>.from(pageRows[kA]![1])).withCompany(kA);
      await pumpVisual(t, phone, home: (_) => SubscriberDetailScreen(sub: s));
      await settle(t, seconds: 2);
      await t.tap(find.text('تسديد').first);
      await settle(t, seconds: 1);
      expect(find.text(MergedMode.writeLockedText), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'شيت التسديد يُفتح');
      await down(t);
    });
  });

  group('٧ «قوائم أخرى» (الصرفيات)', () {
    Future<void> settleReal(WidgetTester t) async {
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('٧-١ صفحةٌ أخرى: قائمتها موجَّهة بتوكنه، وللعرض بالسبب ولو فتح مالكها الكتابة؛ وصفحته الحاليّة كما هي', (t) async {
      final srv = await empUp();
      await t.runAsync(MergedMode.enter);
      const screen = MergedSection(prefixes: ['/api/admin/expenses', '/api/v2/expenses'], child: ExpensesScreen());
      await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => screen);
      await settleReal(t);
      expect(find.textContaining('إيجار ألف'), findsWidgets, reason: '«الكل» = صفحته الحاليّة كما كانت');
      expect(find.textContaining('تعرض صفحتك الحاليّة «$nameA»'), findsOneWidget);
      MergedMode.focus.value = kB;
      await settleReal(t);
      final ex = srv.routed.where((o) => o.uri.path == '/api/admin/expenses').toList();
      expect(ex.map((o) => o.headers['x-company-key']).toSet(), {kB});
      expect(ex.every((o) => o.headers['Authorization'] == 'Bearer $empToken'), isTrue);
      expect(find.textContaining('كهرباء باء'), findsWidgets);
      expect(find.textContaining('«$nameB» للعرض هنا — انتقل إليها من «صفحاتي» لتعديلها'), findsOneWidget);
      // صفحته الحاليّة مختارة: طلبها العاديّ (لا توجيه) — كتابتها كما كانت
      final before = srv.routed.length;
      MergedMode.focus.value = kA;
      await settleReal(t);
      expect(srv.routed.length, before, reason: 'المفتوحة لا تُوجَّه');
      expect(find.textContaining('للعرض هنا'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      await empDown();
    });
  });

  group('٧ب «قوائم أخرى» بخريطة كلّ صفحة', () {
    Future<void> settleReal(WidgetTester t) async {
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('٧ب-١ التسويات: باء بلا settlements.view ⇒ بطاقة «لا صلاحيّة» باسمها ولا طلب؛ ألف كما هي', (t) async {
      final srv = await empUp();
      await t.runAsync(MergedMode.enter);
      MergedMode.focus.value = kB;
      await pumpVisual(t, const VisualDevice('', Size(390, 1400), 1), home: (_) => SettlementsScreen.mergedPage());
      await settleReal(t);
      expect(t.takeException(), isNull);
      expect(find.text('لا صلاحيّة لك على «تسوية الحساب» في «$nameB»'), findsOneWidget);
      expect(find.byKey(const ValueKey('merged-open-only-switch')), findsNothing, reason: 'لا «انتقل إليها» — صلاحيّته هناك لا تتغيّر');
      expect(srv.routed.where((o) => o.uri.path.startsWith('/api/v2/settlements')), isEmpty, reason: 'لا طلب لباء');
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 6));
      await empDown();
    });
  });

  test('٦ نصوص الموظّف: كلّ مفتاح merged_emp له أصلٌ عند المالك (نصٌّ فقط)', () {
    final ar = jsonDecode(File('assets/translations/ar.json').readAsStringSync()) as Map<String, dynamic>;
    final en = jsonDecode(File('assets/translations/en.json').readAsStringSync()) as Map<String, dynamic>;
    final empAr = (ar['merged_emp'] as Map).keys.toSet();
    expect((en['merged_emp'] as Map).keys.toSet(), empAr);
    bool has(Map<String, dynamic> m, String dotted) {
      Object? cur = m;
      for (final p in dotted.split('.')) {
        if (cur is! Map || !cur.containsKey(p)) return false;
        cur = cur[p];
      }
      return cur is String;
    }

    for (final k in empAr) {
      // merged.<k> أو <group>.<key> المكتوب بشرطة (sales_merged_readonly ⇒ sales.merged_readonly)
      final base = (ar['merged'] as Map).containsKey(k) ? 'merged.$k' : k.replaceFirst('_', '.');
      expect(has(ar, base), isTrue, reason: 'merged_emp.$k بلا أصل ($base)');
    }
  });
}
