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

import 'support/route_reviewed.dart';
import 'support/route_scan.dart';

/// «كل الشركات» — قاعدة الوجهة (٩ نوفمبر، مراجعة 179 — CompanyRoute.decide):
///   ١. الكتابة لا تأخذ وجهة قسمٍ أبداً: بلا اختيارٍ صريح ⇒ المفتوحة، وإن كان أعلى ما يُرى لمسارها قسماً لشركةٍ أخرى ⇒ لا تُرسل.
///   ٢. الصريح أوّلاً (معامل النداء، ثمّ أعمق نطاق)، والقراءة تتبع أعلى نطاقٍ ظاهر — مرتّباً بموضع صفحته لا بلحظة دخوله.
///   ٣. طبقة الـAPI: لا وجهة مشتركة (لا `X.yKey =` ولا static routeKey ولا حقلٌ يحمل مفتاحاً ولا قراءةٌ للشريط)، ولا
///      x-company-key إلّا من المعترض، وكتابات المال (المبيعات، التسويات، الصرفيات، الثابتة) كلّها بشركةٍ صريحة من أيّ ملفّ،
///      وكلّ كتابةٍ على مشتركٍ من خارج lib/api صريحة الشركة إلّا الجماعيّة (مرفوضةٌ في «كل الشركات») — فحصٌ ثابتٌ للكود
///      (النصوص والتعليقات مُقنَّعة) + خادمٌ وهميّ يرى الترويسات. وكلّ قراءةٍ لواجهة قسمٍ من خارجه مراجَعةٌ بطريقة تثبيتها.
///   مراجعة 179 للإصدار 180 (route3_verify.json ٥–١١): غلاف كلّ كتابةٍ على مشتركٍ مراجَعٌ حرفاً (لا runOpen ولا غلافٌ يتبدّل،
///      ولا إغلاقٌ مؤجَّل داخله)، والجماعيّة بحارسها في دالّتها؛ مصدر companyKey لكلّ كتابة مالٍ وشيت مال في الشاشات كلّها؛ كتّاب المشترك
///      خارج /api/v2/subscribers (واتساب، إعداد الجهاز، الأرشيف، تلغرام، فايبر اكس) كلٌّ بطريقته؛ «المفتوحة»/«الصفّ» لا يقبل أحدهما
///      غلاف الآخر؛ القراءات بـPOST قائمةٌ مراجَعة (test/support/route_reviewed.dart) وبـPOST وحده؛ كلّ مستقبِلٍ لـDio خادمنا
///      (pipe، _d…) والمسار محلولٌ أو مراجَع. الفحوص دوالّ (test/support/route_checks.dart) يثبت merged_route_proof_test أنّ كلّاً
///      منها يفشل على نمطه السيّئ مزروعاً.
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

    test('القراءة بـPOST للـPOST وحده (مراجعة 179): PUT/PATCH/DELETE على مسارٍ منها كتابةٌ — لا تأخذ وجهة القسم الظاهر بل تُرفض', () {
      final s = Object();
      CompanyRoute.enterSection(s, _kB, const ['/api/v2/sales', '/api/v2/subscribers']);
      expect(CompanyRoute.decide(_req('POST', '/api/v2/sales/debt-status')).key, _kB, reason: 'POST قراءة ⇒ تتبع القسم');
      for (final p in ['/api/v2/sales/debt-status', '/api/v2/subscribers/lookup']) {
        for (final m in ['PUT', 'PATCH', 'DELETE']) {
          final d = CompanyRoute.decide(_req(m, p));
          expect((d.key, d.refusedFor), (null, _kB), reason: '$m $p كتابة: لا تأخذ شركة القسم — تُرفض');
        }
      }
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
    final lib = loadLib();

    test('لا x-company-key إلّا من المعترض، ولا وجهة صريحة إلّا من معامل — بعلامتَي الاقتباس، وفي الخريطة أو بإسنادٍ لـextra', () {
      // يُقرأ صداها في الردود (الكارتات مثلاً)؛ أمّا وضعها على طلبٍ فللمعترض وحده
      final sets = RegExp(r'''headers\s*\[\s*(['"])x-company-key\1\s*\]\s*=[^=]|(['"])x-company-key\2\s*:''');
      final header = [
        for (final e in src.entries)
          if (sets.hasMatch(e.value) && e.key != 'lib/api/api_client.dart') e.key,
      ];
      expect(header, isEmpty, reason: 'ترويسة الشركة يضعها المعترض وحده (CompanyRoute.decide)');
      // من يضع extra['companyKey'] / extra['companyOpen'] بيده (خريطةً أو إسناداً) — كلٌّ يأخذه من معاملٍ اسمه companyKey
      const allowed = {
        'lib/api/company_route.dart', // CompanyRoute.explicit
        'lib/api/package_report_api.dart', // معامل companyKey
        'lib/api/connection_auto_api.dart', // معامل companyKey (قراءات «تنبيه المشترك» لكلّ شركة)
      };
      final extra = RegExp(r'''(['"])company(?:Key|Open)\1\s*:|\[\s*(['"])company(?:Key|Open)\2\s*\]\s*=[^=]''');
      final hand = [
        for (final e in src.entries)
          if (extra.hasMatch(e.value) && !allowed.contains(e.key)) e.key,
      ];
      expect(hand, isEmpty, reason: 'وجهةٌ صريحة بيد ملفٍّ جديد — مرّرها بـCompanyRoute.explicit من معامل');
      for (final f in allowed.where((f) => f != 'lib/api/company_route.dart')) {
        expect(RegExp(r'''(['"])companyOpen\1''').hasMatch(src[f]!), isFalse, reason: '$f: «المفتوحة صراحةً» لـexplicit وحده');
        final uses = RegExp(r'''(['"])companyKey\1\s*:\s*([A-Za-z_]\w*)''').allMatches(src[f]!).toList();
        expect(uses, isNotEmpty, reason: f);
        for (final m in uses) {
          expect(m.group(2), 'companyKey', reason: '$f: المفتاح من معاملٍ لا من حالٍ مشتركة');
        }
      }
    });

    test('لا وجهة مشتركة: لا SalesApi.routeKey ولا أيّ `Class.xKey =` لمفتاح شركة، ولا حقلٌ في lib/api يحمله ولا قراءةٌ للشريط', () {
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
      // طبقة الـAPI لا تحفظ مفتاحاً بين النداءات ولا تقرأ اختيار الشاشة: الوجهة من معامل النداء أو من المعترض وحده
      final holder = RegExp(r'static\s+(?:final\s+|late\s+)?(?:String\?|ValueNotifier<String\?>)\s+'
          r'(\w*(?:[Kk]ey|[Cc]ompany|[Rr]oute|[Ff]ocus)\w*)\s*[;=]');
      final reads = RegExp(r'MergedMode\s*\.\s*(?:focus|focused)\b|MergedSection\s*\.|\bsectionKey(?:For)?\b|\brouteKeyOf\b');
      final api = <String>[];
      for (final e in lib.entries) {
        if (!e.key.startsWith('lib/api/') || e.key == 'lib/api/company_route.dart') continue;
        for (final m in holder.allMatches(e.value.code)) {
          api.add('${e.key}:${lineOf(e.value.code, m.start)} ${m.group(0)}');
        }
        for (final m in reads.allMatches(e.value.code)) {
          api.add('${e.key}:${lineOf(e.value.code, m.start)} ${m.group(0)}');
        }
      }
      expect(api, isEmpty, reason: 'وجهةٌ محفوظةٌ في طبقة الـAPI أو مأخوذةٌ من الشريط/القسم — مرّرها معاملاً');
    });

    test('قراءات الأقسام من خارجها مراجَعةٌ واحدةً واحدة وبطريقة تثبيتها مفحوصة — «المفتوحة» بـrunOpen/pin(null وحدهما، و«شركة '
        'الصفّ» بالصفّ أو <…>.companyKey وحدهما (لا يقبل أحدهما غلاف الآخر)، ولا غلاف يأخذ الشريط وسيطاً — الجديد يُراجَع', () {
      // واجهات «قوائم أخرى» (بادئاتها موجَّهةٌ حين يُعرض قسمها لشركةٍ أخرى): نداءٌ لها من ملفٍّ خارج قسمها يأخذ وجهة قسمٍ ظاهرٍ
      // ما لم يحدّد شركته — فكلّ موضعٍ بطريقته (test/support/route_reviewed.dart reviewedSectionSites)، وتُفحص الطريقة في كلّ
      // موضعٍ من الملفّ؛ وموضعٌ جديدٌ يفشل حتى يُراجَع.
      final v = sectionVerdict(lib);
      expect(v, isEmpty, reason: v.join('\n'));
    });

    test('القراءات بـPOST: الثابت المنتَج يساوي القائمة المراجَعة حرفاً (كلٌّ بمدخل الخادم الذي يقابله أو سببه)، والقراءة بـPOST وحده',
        () {
      expect(CompanyRoute.readsByPost, reviewedReadPaths,
          reason: 'مسارٌ أُضيف لـreadsByPost (يُعامَل قراءةً: يتبع القسم ولا يُرفض) أو زال — راجعه وأضفه لـtest/support/route_reviewed.dart '
              'بمدخل الخادم الذي يقابله');
      for (final p in reviewedReadPaths) {
        expect(CompanyRoute.isRead('POST', p), isTrue, reason: p);
        for (final m in ['PUT', 'PATCH', 'DELETE']) {
          expect(CompanyRoute.isRead(m, p), isFalse, reason: '$m $p كتابة — لا تُعامَل قراءة');
        }
      }
    });

    test('كتابات المال في كلّ lib: كلّ نداء كتابةٍ على أيّ Dio (ApiClient.dio/pipe وأسماؤهما: _d…) على مسار مال يحمل شركته صراحةً '
        'من معامل companyKey — والمسار محلولٌ (حرفيّ، ثابت، محلّيّ، دالّةٌ مساعدة، أو حرفيٌّ عند كلّ من يمرّره) أو مراجَع', () {
      final v = dioVerdict(lib);
      expect(v, isEmpty, reason: v.join('\n'));
    });

    test('كتابات المشترك: الواجهات مشتقّةٌ من lib/api، وكلّ نداءٍ لها من خارجها بغلافه المراجَع حرفاً (الصفّ أو مفتاحه، لا runOpen ولا '
        'غلافٌ يتبدّل) وخارج أيّ إغلاقٍ مؤجَّل — والجماعيّة وحدها ضمنيّة، كلٌّ بدالّته وحارسه قبله فيها', () {
      final v = writerVerdict(lib);
      expect(v, isEmpty, reason: v.join('\n'));
    });

    test('شركة كتابات المال في الشاشات (المجلّدات كلّها): كلّ كتابة مالٍ وكلّ شيت مالٍ يأخذ companyKey من مصدرٍ مراجَع — شجرة القسم أو '
        'ما حمله الشيت أو محلّيٌّ نُسخ منها — لا من الشريط، وnull (المفتوحة صراحةً) في موضعٍ مراجَعٍ وحده', () {
      final v = moneyKeyVerdict(lib);
      expect(v, isEmpty, reason: v.join('\n'));
    });

    test('كتّابٌ لكلّ مشتركٍ خارج /api/v2/subscribers (رسائله، إعداد جهازه، وصله المؤرشف، تلغرامه، إشعار فايبر اكس): كلّ نداءٍ '
        'مراجَعٌ بطريقته — للمفتوحة صراحةً، أو بشركة صفّه، أو بعد حارس «للشركة وحدها»، أو خلف بوّابةٍ لا تُبلَغ إلّا لصفٍّ بلا مفتاح', () {
      final v = sideVerdict(lib);
      expect(v, isEmpty, reason: v.join('\n'));
    });

    test('كشف الحساب لا يُفتح بلا قرار شركة: كلّ `AccountStatementScreen(` يمرّر companyKey (التحقّق الثالث من 179)', () {
      final sites = <String>[];
      final bad = <String>[];
      for (final e in lib.entries) {
        if (e.key == 'lib/screens/reports/account_statement_screen.dart') continue; // تعريفه
        final code = e.value.code;
        for (final m in RegExp(r'\bAccountStatementScreen\s*\(').allMatches(code)) {
          final open = m.end - 1;
          final at = '${e.key}:${lineOf(code, m.start)}';
          sites.add(at);
          if (!RegExp(r'\bcompanyKey\s*:').hasMatch(code.substring(open, closeOf(code, open)))) bad.add(at);
        }
      }
      expect(sites, isNotEmpty, reason: 'الفحص لم يجد مواضع (تغيّرت الصيغة؟)');
      expect(bad, isEmpty, reason: 'كشفٌ بلا شركته يُطلب من الشركة المفتوحة ويُصدَّر تحت اسم مشترك غيرها — مرّر sub.companyKey');
    });

    test('الغلاف (MainShell) أوّل صفحات الجذر وحده: كلّ مدخلٍ إليه يزيل ما تحته — ملخّص «انتهت اليوم» يقيس «لا شيء فوقه» بذلك', () {
      final nav = RegExp(r'\.\s*(pushAndRemoveUntil|pushReplacement|push)\s*(?:<[^()]*?>)?\s*\(');
      final removeAll = RegExp(r'\(\s*\w+\s*\)\s*=>\s*false');
      // قيمةٌ تُبنى خارج نداء التنقّل — مراجَعةٌ بطريقة دخولها
      const values = {
        'lib/screens/splash_screen.dart': 'next ⇒ pushReplacement من أوّل صفحات الجذر (البداية) فيحلّ محلّها',
        'lib/screens/account/company_open_flow.dart': 'shellBuilder ⇒ pushAndRemoveUntil((_) => false)',
      };
      final bad = <String>[];
      final seenValues = <String>{};
      for (final e in lib.entries) {
        if (e.key == 'lib/screens/main_shell.dart') continue;
        final code = e.value.code;
        for (final m in RegExp(r'\bMainShell\s*\(').allMatches(code)) {
          final at = '${e.key}:${lineOf(code, m.start)}';
          // أعمق نداء تنقّلٍ يحويه
          final inner = innermost(code, m.start, nav);
          if (inner == null) {
            if (values.containsKey(e.key)) {
              seenValues.add(e.key);
            } else {
              bad.add('$at: يُبنى خارج نداء تنقّل — راجعه وأضفه بطريقة دخوله');
            }
            continue;
          }
          final open = inner.end - 1;
          final args = code.substring(open, closeOf(code, open));
          if (inner.group(1) != 'pushAndRemoveUntil' || !removeAll.hasMatch(args)) {
            bad.add('$at: ${inner.group(1)} يُبقي ما تحت الغلاف');
          }
        }
      }
      expect(bad, isEmpty, reason: 'مدخلٌ يُبقي صفحةً تحت الغلاف ⇒ الرجوع يعود إليها، و«لا شيء فوقه» يُقرأ خطأً');
      expect(seenValues, values.keys.toSet(), reason: 'موضعٌ مراجَعٌ زال — احذفه من القائمة');
      // shellBuilder يُدخل بإزالة ما تحته
      final flow = lib['lib/screens/account/company_open_flow.dart']!.code;
      final use = flow.indexOf('shellBuilder()');
      expect(use, greaterThan(0));
      final pr = RegExp(r'\.\s*pushAndRemoveUntil\s*\(')
          .allMatches(flow)
          .where((n) => n.end - 1 < use && closeOf(flow, n.end - 1) > use);
      expect(pr, isNotEmpty, reason: 'shellBuilder يُدخل بـpushAndRemoveUntil');
      expect(removeAll.hasMatch(flow.substring(pr.last.end - 1, closeOf(flow, pr.last.end - 1))), isTrue);
    });
  });
}
