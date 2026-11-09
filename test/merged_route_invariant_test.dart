import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/account_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/company_route.dart';
import 'package:rad_mysvcs/api/expenses_api.dart';
import 'package:rad_mysvcs/api/recurring_expenses_api.dart';
import 'package:rad_mysvcs/api/sales_api.dart';
import 'package:rad_mysvcs/api/settlements_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «كل الشركات» — قاعدة الوجهة (٩ نوفمبر، مراجعة 179 — CompanyRoute.decide):
///   ١. الكتابة لا تأخذ وجهة قسمٍ أبداً: بلا اختيارٍ صريح ⇒ المفتوحة، وإن كان أعلى ما يُرى لمسارها قسماً لشركةٍ أخرى ⇒ لا تُرسل.
///   ٢. الصريح أوّلاً (معامل النداء، ثمّ أعمق نطاق)، والقراءة تتبع أعلى نطاقٍ ظاهر — مرتّباً بموضع صفحته لا بلحظة دخوله.
///   ٣. طبقة الـAPI: لا وجهة مشتركة (لا `X.yKey =` ولا static routeKey)، ولا x-company-key إلّا من المعترض، وكتابات المال
///      (المبيعات، التسويات، الصرفيات، الثابتة) كلّها بشركةٍ صريحة — فحصٌ ثابتٌ للنصّ + خادمٌ وهميّ يرى الترويسات.
const _kB = 'c0000000000b2';
const _kC = 'c0000000000c3';

RequestOptions _req(String method, String path, {Map<String, dynamic>? extra}) =>
    RequestOptions(method: method, path: path, baseUrl: 'https://pro.example', extra: extra);

class _Srv implements HttpClientAdapter {
  final asked = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? rs, Future<void>? cf) async {
    final key = o.headers['x-company-key'] as String?;
    asked.add('${o.method.toUpperCase()} ${o.uri.path} ${key ?? '-'}');
    return ResponseBody.fromString(jsonEncode({'success': true, 'data': {}}), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      if (key != null) 'x-company-key': [key],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// ملفّات lib بلا التعليقات (`///` و`//`) — الفحص الثابت يقرأ الكود لا وصفه.
Map<String, String> _libSources() {
  final out = <String, String>{};
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final code = f
        .readAsLinesSync()
        .map((l) {
          final t = l.trimLeft();
          if (t.startsWith('//')) return '';
          final i = l.indexOf(' // ');
          return i >= 0 ? l.substring(0, i) : l;
        })
        .join('\n');
    out[f.path.replaceAll('\\', '/')] = code;
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(CompanyRoute.debugReset);

  group('١. الكتابة لا تأخذ وجهة قسم', () {
    test('قسمٌ موجَّهٌ ظاهرٌ لمسارها ⇒ لا تُرسل (رفضٌ باسم شركته) — لكلّ أفعال الكتابة', () {
      final s = Object();
      CompanyRoute.enterSection(s, _kB, const ['/api/admin/expenses', '/api/v2/sales']);
      for (final m in ['POST', 'PUT', 'PATCH', 'DELETE']) {
        final d = CompanyRoute.decide(_req(m, '/api/admin/expenses/5'));
        expect(d.key, isNull, reason: m);
        expect(d.refusedFor, _kB, reason: '$m بلا شركةٍ صريحة والشاشة تعرض غيرها ⇒ لا تُرسل');
      }
      // القراءة نفسها تتبع القسم
      expect(CompanyRoute.decide(_req('GET', '/api/admin/expenses')).key, _kB);
      // مسارٌ لا يطابق ⇒ المفتوحة بلا رفض
      final other = CompanyRoute.decide(_req('POST', '/api/v2/subscribers/9/pay-debt'));
      expect((other.key, other.refused), (null, false));
    });

    test('قسمٌ مخفيّ (مركون) ⇒ الكتابة للمفتوحة بلا رفض، والقراءة كذلك — ولا يأخذها أبداً', () {
      final s = Object();
      CompanyRoute.enterSection(s, _kB, const ['/api/admin/expenses'], parked: true);
      final w = CompanyRoute.decide(_req('POST', '/api/admin/expenses'));
      expect((w.key, w.refused), (null, false));
      expect(CompanyRoute.decide(_req('GET', '/api/admin/expenses')).key, isNull);
      expect(CompanyRoute.sectionKeyFor('/api/admin/expenses'), isNull);
    });

    test('صفحةٌ للمفتوحة فوق القسم ⇒ كتابتها الضمنيّة للمفتوحة بلا رفض (هي أعلى ما يُرى)', () {
      final s = Object();
      final open = Object();
      CompanyRoute.enterSection(s, _kB, const ['/api/v2/managers']);
      CompanyRoute.enterOpen(open);
      final w = CompanyRoute.decide(_req('POST', '/api/v2/managers/5/balance'));
      expect((w.key, w.refused), (null, false));
      expect(CompanyRoute.decide(_req('GET', '/api/v2/managers')).key, isNull);
      expect(CompanyRoute.shadowed(s), isTrue);
      CompanyRoute.leaveSection(open);
      expect(CompanyRoute.decide(_req('GET', '/api/v2/managers')).key, _kB);
      expect(CompanyRoute.shadowed(s), isFalse);
    });

    test('قراءاتٌ بـPOST تتبع القسم كالقراءة، والرفع (readings) كتابة', () {
      final s = Object();
      CompanyRoute.enterSection(s, _kB, const ['/api/v2/sales', '/api/v2/whatsapp', '/api/v2/connection-alerts']);
      expect(CompanyRoute.decide(_req('POST', '/api/v2/sales/debt-status')).key, _kB);
      expect(CompanyRoute.decide(_req('POST', '/api/v2/whatsapp/contact-risk')).key, _kB);
      expect(CompanyRoute.decide(_req('POST', '/api/v2/connection-alerts/readings')).refusedFor, _kB);
    });
  });

  group('٢. الصريح أوّلاً، والقراءة لأعلى نطاقٍ ظاهر بموضع صفحته', () {
    test('معامل النداء يغلب كلّ نطاق، وأعمق نطاقٍ يغلب ما فوقه', () async {
      final s = Object();
      CompanyRoute.enterSection(s, _kB, const ['/api/admin/expenses']);
      String? k(RequestOptions o) => CompanyRoute.decide(o).key;
      bool refused(RequestOptions o) => CompanyRoute.decide(o).refused;
      // صريحٌ بالمعامل
      expect(k(_req('POST', '/api/admin/expenses', extra: {'companyKey': _kC})), _kC);
      expect(k(_req('POST', '/api/admin/expenses', extra: {'companyOpen': true})), isNull);
      expect(refused(_req('POST', '/api/admin/expenses', extra: {'companyOpen': true})), isFalse);
      expect(CompanyRoute.explicit(_kC).extra, {'companyKey': _kC});
      expect(CompanyRoute.explicit(null).extra, {'companyOpen': true});
      expect(CompanyRoute.explicit('not-a-key').extra, {'companyOpen': true}, reason: 'مفتاحٌ غير صالح ⇒ المفتوحة صراحةً');
      // النطاقات: أعمقها يغلب
      await CompanyRoute.runOpen(() async {
        expect(k(_req('POST', '/api/admin/expenses')), isNull);
        expect(refused(_req('POST', '/api/admin/expenses')), isFalse);
        await CompanyRoute.run(_kC, () async {
          expect(k(_req('GET', '/api/admin/expenses')), _kC, reason: 'run داخل runOpen لشركته');
          expect(k(_req('POST', '/api/admin/expenses')), _kC);
          await CompanyRoute.runOpen(() async => expect(k(_req('GET', '/api/admin/expenses')), isNull));
        });
        // المعامل يغلب النطاق
        expect(k(_req('POST', '/api/admin/expenses', extra: {'companyKey': _kC})), _kC);
      });
      await CompanyRoute.pin(null, () async => expect(k(_req('GET', '/api/admin/expenses')), isNull));
      await CompanyRoute.pin(_kC, () async => expect(k(_req('PUT', '/api/admin/expenses/1')), _kC));
      // خارج كلّ نطاق: القراءة للقسم، والكتابة مرفوضة
      expect(k(_req('GET', '/api/admin/expenses')), _kB);
      expect(refused(_req('POST', '/api/admin/expenses')), isTrue);
    });

    test('الترتيب بموضع الصفحة: الجذر فوق أقسام الحاسبة، وعودة قسمٍ من الإخفاء لا ترفعه فوق صفحة المفتوحة', () {
      final pane = Object();
      final rootOpen = Object();
      // قسمٌ في جزء الحاسبة (الطبقة 0) دخل بعد صفحةٍ للمفتوحة في الجذر (الطبقة 1) — الجذر فوقه مهما كان الترتيب
      CompanyRoute.enterOpen(rootOpen, order: (level: 1, seq: 5));
      CompanyRoute.enterSection(pane, _kB, const ['/api/v2/managers'], order: (level: 0, seq: 9));
      expect(CompanyRoute.sectionKeyFor('/api/v2/managers'), isNull, reason: 'الجذر فوق الجزء');
      CompanyRoute.leaveSection(rootOpen);
      expect(CompanyRoute.sectionKeyFor('/api/v2/managers'), _kB);

      // الجزء نفسه: القسم (صفحته 10) ثمّ «الصفحات» فوقه (صفحته 11) — أُخفي الجزء وعاد: الترتيب بالصفحة لا بالدخول
      final section = Object();
      final pages = Object();
      CompanyRoute.enterSection(section, _kB, const ['/api/v2/managers'], order: (level: 0, seq: 10));
      CompanyRoute.enterOpen(pages, order: (level: 0, seq: 11));
      CompanyRoute.enterSection(section, _kB, const ['/api/v2/managers'], order: (level: 0, seq: 10), parked: true);
      CompanyRoute.leaveSection(pages); // أُخفي الجزء
      CompanyRoute.enterOpen(pages, order: (level: 0, seq: 11)); // ظهر
      CompanyRoute.enterSection(section, _kB, const ['/api/v2/managers'], order: (level: 0, seq: 10)); // ظهر بعدها
      expect(CompanyRoute.sectionKeyFor('/api/v2/managers'), isNull, reason: '«الصفحات» فوق القسم ولو دخل بعدها');
      CompanyRoute.leaveSection(pane);
    });

    test('قسمٌ داخل قسم (الصرفيات ⇒ التسويات) لشركةٍ واحدة: لا رفع ولا تلويث', () {
      final outer = Object();
      final inner = Object();
      var tainted = 0;
      CompanyRoute.enterSection(outer, _kB, const ['/api/admin/expenses'], onTaint: () => tainted++);
      CompanyRoute.enterSection(inner, _kB, const ['/api/v2/settlements', '/api/admin/expenses']);
      expect(CompanyRoute.decide(_req('GET', '/api/admin/expenses')).key, _kB);
      CompanyRoute.leaveSection(inner);
      expect(CompanyRoute.decide(_req('GET', '/api/admin/expenses')).key, _kB);
      return Future<void>.delayed(Duration.zero, () => expect(tainted, 0));
    });

    test('معرّف المدير لمسارات /:adminId يتبع القاعدة نفسها', () async {
      CompanyRoute.adminIdOf = (k) => k == _kC ? 'jt:22' : null;
      addTearDown(() => CompanyRoute.adminIdOf = null);
      final s = Object();
      CompanyRoute.enterSection(s, _kB, const ['/api/telegram'], adminId: 'el:77');
      expect(CompanyRoute.adminIdFor('/api/telegram/status'), 'el:77');
      await CompanyRoute.run(_kC, () async => expect(CompanyRoute.adminIdFor('/api/telegram/status'), 'jt:22'));
      await CompanyRoute.runOpen(() async => expect(CompanyRoute.adminIdFor('/api/telegram/status'), isNull));
    });
  });

  group('٤. ما يُخفى أو يُغطّى لا تبقى شاشته بما وصلها', () {
    test('طلبٌ ضمنيّ من بادئاته ذهب لغير شركته ⇒ يُعلَم (مخفيّاً أو مغطّى)؛ والصريح لا', () async {
      final hidden = Object();
      final covered = Object();
      final open = Object();
      var hiddenTaint = 0, coveredTaint = 0;
      CompanyRoute.enterSection(hidden, _kB, const ['/api/admin/expenses'], parked: true, onTaint: () => hiddenTaint++);
      CompanyRoute.enterSection(covered, _kB, const ['/api/v2/managers'], onTaint: () => coveredTaint++);
      CompanyRoute.enterOpen(open);
      CompanyRoute.decide(_req('GET', '/api/admin/expenses'));
      CompanyRoute.decide(_req('GET', '/api/v2/managers'));
      await Future<void>.delayed(Duration.zero);
      expect((hiddenTaint, coveredTaint), (1, 1));
      // الصريح لا يُعلِم
      CompanyRoute.decide(_req('GET', '/api/admin/expenses', extra: {'companyOpen': true}));
      await CompanyRoute.runOpen(() async => CompanyRoute.decide(_req('GET', '/api/v2/managers')));
      await CompanyRoute.run(_kB, () async => CompanyRoute.decide(_req('GET', '/api/admin/expenses')));
      await Future<void>.delayed(Duration.zero);
      expect((hiddenTaint, coveredTaint), (1, 1));
    });
  });

  group('المعترض: الرفض لا يصل الخادم، والصريح يصل بمفتاحه', () {
    late _Srv srv;
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({'auth.token': 't', 'auth.admin_id': 'supernet:12'});
      SharedPreferences.setMockInitialValues({});
      srv = _Srv();
      ApiClient.dio.httpClientAdapter = srv;
      AccountApi.tokenSource = ({bool force = false}) async => 'acct';
      CompanyRoute.nameOf = (k) => k == _kB ? 'الجزيرة' : null;
    });
    tearDown(() => CompanyRoute.nameOf = null);

    test('كتابةٌ ضمنيّة تحت قسمٍ موجَّه ⇒ 409 محلّيّ باسم شركته ولا طلب', () async {
      final s = Object();
      CompanyRoute.enterSection(s, _kB, const ['/api/admin/expenses']);
      final r = await ApiClient.dio.post<Map<String, dynamic>>('/api/admin/expenses', data: {'amount': 1});
      expect(r.statusCode, 409);
      expect(r.data!['code'], CompanyRouteCodes.ambiguous);
      expect(r.data!['message'], contains('«الجزيرة»'));
      expect(r.data!['message'], contains('لم يُنفَّذ شيء'));
      expect(srv.asked, isEmpty, reason: 'لا شيء وصل الخادم');
      // الصريح يصل
      await ApiClient.dio.post<Map<String, dynamic>>('/api/admin/expenses', options: CompanyRoute.explicit(_kB));
      await ApiClient.dio.post<Map<String, dynamic>>('/api/admin/expenses', options: CompanyRoute.explicit(null));
      expect(srv.asked, ['POST /api/admin/expenses $_kB', 'POST /api/admin/expenses -']);
    });

    test('كتابات المال كلّها بشركتها الصريحة — لا تأخذ قسماً ظاهراً ولا تُرفض (المبيعات، التسويات، الصرفيات، الثابتة)', () async {
      // كلّ أقسام المال ظاهرةٌ لشركةٍ أخرى (C): لا شيء منها يُكتب لها إلّا صراحةً
      final s = Object();
      CompanyRoute.enterSection(s, _kC, const ['/api/v2/sales', '/api/v2/settlements', '/api/admin/expenses', '/api/v2/expenses']);
      const lines = [SaleLineInput(itemId: 1, qty: 1, unitPrice: 1000)];
      const cut = SettlementCut(1, 2, 3);
      Future<void> all(String? key) async {
        await SalesApi.createItem(name: 'x', salePrice: 1, companyKey: key);
        await SalesApi.updateItem(1, const {'name': 'y'}, companyKey: key);
        await SalesApi.stock(1, kind: 'adjust', qty: 1, clientRef: 'r', companyKey: key);
        await SalesApi.voidMove(1, 2, 'خطأ', companyKey: key);
        await SalesApi.sell(clientRef: 'r', payment: 'cash', lines: lines, customer: const {'kind': 'walkin'}, companyKey: key);
        await SalesApi.voidSale(1, 'خطأ', companyKey: key);
        await SalesApi.resolve(1, applied: true, companyKey: key);
        await SalesApi.resolveVoid(1, applied: true, companyKey: key);
        await SettlementsApi.open(start: 'now', companyKey: key);
        await SettlementsApi.settle(cut: cut, expected: 1, received: 1, idempotencyKey: 'k', companyKey: key);
        await SettlementsApi.voidSettlement(1, 'خطأ', companyKey: key);
        await ExpensesApi.create(amount: 1, companyKey: key);
        await ExpensesApi.update(id: 1, amount: 2, companyKey: key);
        await ExpensesApi.delete(1, companyKey: key);
        await RecurringExpensesApi.create(
            name: 'x', amount: 1, day: 1, every: 1, startPeriod: '2026-11', mode: 'auto', clientRef: 'r', companyKey: key);
        await RecurringExpensesApi.update(1, const {'amount': 2}, companyKey: key);
        await RecurringExpensesApi.pause(1, companyKey: key);
        await RecurringExpensesApi.resume(1, companyKey: key);
        await RecurringExpensesApi.delete(1, companyKey: key);
        await RecurringExpensesApi.payNow(1, amount: 1, companyKey: key);
        await RecurringExpensesApi.confirm(1, amount: 1, companyKey: key);
        await RecurringExpensesApi.skip(1, companyKey: key);
      }

      await all(null);
      final open = srv.asked.where((a) => !a.startsWith('GET ')).toList();
      expect(open.length, 22);
      expect(open.every((a) => a.endsWith(' -')), isTrue, reason: 'null = المفتوحة صراحةً: $open');
      srv.asked.clear();
      await all(_kB);
      final routed = srv.asked.where((a) => !a.startsWith('GET ')).toList();
      expect(routed.length, 22);
      expect(routed.every((a) => a.endsWith(' $_kB')), isTrue, reason: 'المفتاح الصريح: $routed');
    });
  });

  group('٣. طبقة الـAPI (فحصٌ ثابت)', () {
    final src = _libSources();

    test('لا x-company-key إلّا من المعترض، ولا وجهة صريحة إلّا من معامل', () {
      // يُقرأ صداها في الردود (الكارتات مثلاً)؛ أمّا وضعها على طلبٍ فللمعترض وحده
      final sets = RegExp(r"headers\[\s*'x-company-key'\s*\]\s*=[^=]|'x-company-key'\s*:");
      final header = [
        for (final e in src.entries)
          if (sets.hasMatch(e.value) && e.key != 'lib/api/api_client.dart') e.key,
      ];
      expect(header, isEmpty, reason: 'ترويسة الشركة يضعها المعترض وحده (CompanyRoute.decide)');
      // من يضع extra['companyKey'] بيده — كلٌّ يأخذه من معاملٍ اسمه companyKey (مراجعةٌ لكلّ إضافة)
      const allowed = {
        'lib/api/company_route.dart', // CompanyRoute.explicit
        'lib/api/package_report_api.dart', // معامل companyKey
        'lib/api/connection_auto_api.dart', // معامل companyKey (قراءات «تنبيه المشترك» لكلّ شركة)
      };
      final extra = [
        for (final e in src.entries)
          if (RegExp(r"'companyKey'\s*:").hasMatch(e.value) && !allowed.contains(e.key)) e.key,
      ];
      expect(extra, isEmpty, reason: 'وجهةٌ صريحة بيد ملفٍّ جديد — مرّرها بـCompanyRoute.explicit من معامل');
      for (final f in allowed.where((f) => f != 'lib/api/company_route.dart')) {
        for (final m in RegExp(r"'companyKey'\s*:\s*([A-Za-z_]\w*)").allMatches(src[f]!)) {
          expect(m.group(1), 'companyKey', reason: '$f: المفتاح من معاملٍ لا من حالٍ مشتركة');
        }
      }
    });

    test('لا وجهة مشتركة: لا SalesApi.routeKey ولا أيّ `Class.xKey =` لمفتاح شركة', () {
      final assigns = <String>[];
      for (final e in src.entries) {
        for (final m in RegExp(r'\b([A-Z]\w*)\.([a-z]\w*[Kk]ey)\s*=[^=]').allMatches(e.value)) {
          if (m.group(2) == 'navigatorKey') continue; // مفتاح Navigator لا شركة
          assigns.add('${e.key}: ${m.group(0)}');
        }
      }
      expect(assigns, isEmpty, reason: 'حالٌ مشتركة تحمل وجهة شركة (كـSalesApi.routeKey) تبقى لما بعد شاشتها');
      expect(src['lib/api/sales_api.dart']!.contains('routeKey'), isFalse);
      expect(src.values.any((v) => v.contains('focusOpenCompany')), isFalse,
          reason: '«الكلّ» والإشعار لا يبدّلان الشريط — صفحةٌ مثبَّتةٌ للمفتوحة');
    });

    test('قراءات الأقسام من خارجها مراجَعةٌ واحدةً واحدة (مثبَّتةٌ للمفتوحة، أو بشركة صفّها، أو صفحةٌ للمفتوحة) — الجديد يُراجَع',
        () {
      // واجهات «قوائم أخرى» (بادئاتها موجَّهةٌ حين يُعرض قسمها لشركةٍ أخرى): نداءٌ لها من ملفٍّ خارج قسمها يأخذ وجهة قسمٍ ظاهرٍ
      // ما لم يحدّد شركته — فكلّ موضعٍ هنا بسببه، وموضعٌ جديدٌ يفشل حتى يُراجَع.
      const apis = {
        'BroadcastApi': 'broadcast_api', 'CardsApi': 'cards_api', 'DiscountsApi': 'discounts_api', 'EmployeesApi': 'employees_api',
        'ExpensesApi': 'expenses_api', 'ManagerDebtsApi': 'manager_debts_api', 'ManagerMovementsApi': 'manager_movements_api',
        'ManagersApi': 'managers_api', 'PortalSettingsApi': 'portal_settings_api', 'RecurringExpensesApi': 'recurring_expenses_api',
        'RenewRequestsApi': 'renew_requests_api', 'SendScopeApi': 'send_scope_api', 'SettlementsApi': 'settlements_api',
        'TelegramApi': 'telegram_api', 'TicketsApi': 'tickets_api', 'WaContactRiskApi': 'wa_contact_risk', 'SalesApi': 'sales_api',
      };
      const sectionDirs = [
        'lib/screens/expenses/', 'lib/screens/settlements/', 'lib/screens/managers/', 'lib/screens/message_logs/',
        'lib/screens/portal_settings/', 'lib/screens/renew/', 'lib/screens/tickets/', 'lib/screens/cards/', 'lib/screens/telegram/',
        'lib/screens/broadcast/', 'lib/screens/discounts/', 'lib/screens/employees/', 'lib/screens/sales/',
      ];
      const reviewed = {
        'lib/screens/accounts/accounts_screen.dart ManagersApi.fetchPassword': 'runOpen + OpenCompanyScope («الصفحات»)',
        'lib/screens/accounts/accounts_screen.dart ManagersApi.listFull': 'runOpen + OpenCompanyScope («الصفحات»)',
        'lib/screens/app_modules.dart TicketsApi.servedByProvider': 'قيمةٌ ثابتة، لا طلب',
        'lib/screens/network_devices/fiber/fiber_outage_screen.dart BroadcastApi.broadcast': 'runOpen (مشتركو أجهزة المفتوحة)',
        'lib/services/fiber/fiber_monitor.dart BroadcastApi.broadcast': 'runOpen («رجع النت» بالخلفيّة)',
        'lib/screens/packages/packages_screen.dart ManagersApi.lite': 'قسم «للمفتوحة وحدها» (لا يُوجَّه أبداً)',
        'lib/screens/reports/activity_log_report_screen.dart ExpensesApi.list': 'runOpen (تقرير المفتوحة)',
        'lib/screens/reports/all_managers_debts_screen.dart ManagerDebtsApi.list': 'runOpen (تقرير المفتوحة)',
        'lib/screens/reports/all_managers_debts_screen.dart ManagerDebtsApi.summary': 'runOpen (تقرير المفتوحة)',
        'lib/screens/reports/all_managers_debts_screen.dart ManagerMovementsApi.list': 'runOpen (تقرير المفتوحة)',
        'lib/screens/reports/all_managers_debts_screen.dart ManagersApi.listFull': 'runOpen (تقرير المفتوحة)',
        'lib/screens/reports/widgets/report_filters.dart EmployeesApi.list': 'runOpen (فلاتر تقارير المفتوحة)',
        'lib/screens/reports/widgets/report_filters.dart ManagersApi.lite': 'runOpen (فلاتر تقارير المفتوحة)',
        'lib/screens/subscribers/connection_alert_flow.dart PortalSettingsApi.fillAgentCode': 'MergedOps.run (بلا مفتاح ⇒ المفتوحة)',
        'lib/screens/subscribers/sheets/activate_sheet.dart CardsApi.codeCardNotAllowed': 'ثابت رمز رفض، لا طلب',
        'lib/screens/subscribers/sheets/activate_sheet.dart CardsApi.codeNoCards': 'ثابت رمز رفض، لا طلب',
        'lib/screens/subscribers/subscribers_screen.dart ManagersApi.lite': 'الوضع العاديّ/الكبير للمفتوحة؛ «كل الشركات» بمفتاح كلّ شركة',
        'lib/screens/subscribers/subscribers_screen.dart TelegramApi.listBindings': '«كل الشركات»: CompanyRoute.run(مفتاح الشركة)؛ العاديّ للمفتوحة',
        'lib/screens/whatsapp/widgets/send_scope_panel.dart SendScopeApi.fetch': 'إعدادات المفتوحة (adminIdFor يتبع النطاق)',
        'lib/screens/whatsapp/widgets/send_scope_panel.dart SendScopeApi.update': 'إعدادات المفتوحة — كتابةٌ ضمنيّة ⇒ المفتوحة أو تُرفض',
        'lib/services/manager_notice.dart ManagersApi.sendBalanceUpdatePush': 'من أفعال المدراء للمفتوحة — كتابةٌ ضمنيّة',
        'lib/services/manager_notice.dart ManagersApi.sendTelegram': 'من أفعال المدراء للمفتوحة — كتابةٌ ضمنيّة',
        'lib/services/permissions_service.dart EmployeesApi.me': 'runOpen (صلاحيّات الجلسة)',
        'lib/widgets/manual_wa_chip.dart WaContactRiskApi.one': 'runOpen (واتساب المفتوحة)',
        'lib/api/whatsapp_api.dart PortalSettingsApi.fillAgentCode': 'CompanyRoute.pin(شركة المشترك؛ بلا مفتاح ⇒ المفتوحة)',
      };
      final found = <String>{};
      for (final e in src.entries) {
        if (sectionDirs.any(e.key.startsWith)) continue;
        for (final a in apis.entries) {
          if (e.key == 'lib/api/${a.value}.dart') continue;
          for (final m in RegExp('\\b${a.key}\\.([a-z]\\w*)\\b').allMatches(e.value)) {
            found.add('${e.key} ${a.key}.${m.group(1)}');
          }
        }
      }
      expect(found.difference(reviewed.keys.toSet()), isEmpty,
          reason: 'نداءٌ جديد لواجهة قسمٍ من خارجه — ثبّته للمفتوحة (CompanyRoute.runOpen) أو بشركة صفّه (MergedOps/pin)، ثمّ أضفه هنا بسببه');
      expect(reviewed.keys.toSet().difference(found), isEmpty, reason: 'موضعٌ مراجَعٌ زال — احذفه من القائمة');
    });

    test('كتابات المال: كلّ نداء كتابةٍ يحمل شركته صراحةً من معامل companyKey', () {
      final money = {
        'lib/api/sales_api.dart': '_routed(companyKey',
        'lib/api/settlements_api.dart': 'CompanyRoute.explicit(companyKey)',
        'lib/api/expenses_api.dart': 'CompanyRoute.explicit(companyKey)',
        'lib/api/recurring_expenses_api.dart': 'CompanyRoute.explicit(companyKey)',
      };
      for (final e in money.entries) {
        final code = src[e.key]!;
        final calls = RegExp(r'\.(post|put|patch|delete)<').allMatches(code).toList();
        expect(calls, isNotEmpty, reason: e.key);
        for (final c in calls) {
          // النداء حتّى نهايته: أوّل «;» بعده (كلّ نداءٍ في هذه الملفّات جملةٌ واحدة)
          final end = code.indexOf(';', c.start);
          final call = code.substring(c.start, end < 0 ? code.length : end);
          final line = '\n'.allMatches(code.substring(0, c.start)).length + 1;
          expect(call.contains(e.value), isTrue, reason: '${e.key}:$line كتابةٌ بلا شركةٍ صريحة');
        }
      }
    });
  });
}
