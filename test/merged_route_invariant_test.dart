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
///   ٣. طبقة الـAPI: لا وجهة مشتركة (لا `X.yKey =` ولا static routeKey ولا حقلٌ يحمل مفتاحاً ولا قراءةٌ للشريط)، ولا
///      x-company-key إلّا من المعترض، وكتابات المال (المبيعات، التسويات، الصرفيات، الثابتة) كلّها بشركةٍ صريحة من أيّ ملفّ،
///      وكلّ كتابةٍ على مشتركٍ من خارج lib/api صريحة الشركة إلّا الجماعيّة (مرفوضةٌ في «كل الشركات») — فحصٌ ثابتٌ للكود
///      (النصوص والتعليقات مُقنَّعة) + خادمٌ وهميّ يرى الترويسات. وكلّ قراءةٍ لواجهة قسمٍ من خارجه مراجَعةٌ بطريقة تثبيتها.
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

/// المصدر مُقنَّعاً: محتوى النصوص والتعليقات فراغاتٌ بطوله (المواضع والأسطر كما هي، وعلامات الاقتباس باقية) — البحث في الكود
/// وحده، ومطابقة الأقواس لا يخدعها قوسٌ في نصّ أو تعليق.
String _mask(String s) {
  final out = s.codeUnits.toList();
  final n = s.length;
  void blank(int from, int to) {
    for (var k = from; k < to && k < n; k++) {
      if (out[k] != 0x0A) out[k] = 0x20;
    }
  }

  bool ident(int c) =>
      (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c == 0x24;
  late int Function(int) str;
  int interp(int j) {
    var depth = 1;
    while (j < n) {
      final c = s.codeUnitAt(j);
      if (c == 0x27 || c == 0x22) {
        j = str(j);
        continue;
      }
      if (c == 0x7B) depth++;
      if (c == 0x7D && --depth == 0) return j + 1;
      j++;
    }
    return n;
  }

  str = (int j) {
    final q = s.codeUnitAt(j);
    final raw = j > 0 && s.codeUnitAt(j - 1) == 0x72 && (j < 2 || !ident(s.codeUnitAt(j - 2)));
    final triple = j + 2 < n && s.codeUnitAt(j + 1) == q && s.codeUnitAt(j + 2) == q;
    final ql = triple ? 3 : 1;
    final start = j + ql;
    var k = start;
    while (k < n) {
      final c = s.codeUnitAt(k);
      if (!raw && c == 0x5C) {
        k += 2;
        continue;
      }
      if (!raw && c == 0x24 && k + 1 < n && s.codeUnitAt(k + 1) == 0x7B) {
        k = interp(k + 2);
        continue;
      }
      if (c == q && (!triple || (k + 2 < n && s.codeUnitAt(k + 1) == q && s.codeUnitAt(k + 2) == q))) {
        blank(start, k);
        return k + ql;
      }
      k++;
    }
    blank(start, n);
    return n;
  };
  var i = 0;
  while (i < n) {
    final c = s.codeUnitAt(i);
    if (c == 0x2F && i + 1 < n && s.codeUnitAt(i + 1) == 0x2F) {
      final e = s.indexOf('\n', i);
      final end = e < 0 ? n : e;
      blank(i, end);
      i = end;
    } else if (c == 0x2F && i + 1 < n && s.codeUnitAt(i + 1) == 0x2A) {
      var depth = 1;
      var k = i + 2;
      while (k < n && depth > 0) {
        if (s.startsWith('/*', k)) {
          depth++;
          k += 2;
        } else if (s.startsWith('*/', k)) {
          depth--;
          k += 2;
        } else {
          k++;
        }
      }
      blank(i, k);
      i = k;
    } else if (c == 0x27 || c == 0x22) {
      i = str(i);
    } else {
      i++;
    }
  }
  return String.fromCharCodes(out);
}

/// ملفّات lib: نصّها ونسختها المُقنَّعة ([_mask]).
Map<String, ({String raw, String code})> _libMasked() => {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>())
        if (f.path.endsWith('.dart'))
          f.path.replaceAll('\\', '/'): (raw: f.readAsStringSync(), code: _mask(f.readAsStringSync())),
    };

/// القوس المغلق لـ`(` عند [open] في كودٍ مُقنَّع.
int _close(String code, int open) {
  var depth = 0;
  for (var i = open; i < code.length; i++) {
    final c = code.codeUnitAt(i);
    if (c == 0x28) depth++;
    if (c == 0x29 && --depth == 0) return i;
  }
  return code.length;
}

/// [pos] بين قوسَي نداءٍ يطابق [opener] (ينتهي بـ`(`) — الكتابة/القراءة داخل `CompanyRoute.runOpen(...)` مثلاً، ولو في دالّةٍ
/// أو قائمةٍ داخله.
bool _inside(String code, int pos, RegExp opener) {
  for (final o in opener.allMatches(code)) {
    final open = o.end - 1;
    if (open >= pos) break;
    if (_close(code, open) > pos) return true;
  }
  return false;
}

/// النصوص الثابتة في الملفّ (`const _base = '/api/v2/sales'`) — لفكّ `$_base` في المسارات.
Map<String, String> _consts(String raw, String code) => {
      for (final m in RegExp(r'''const\s+(?:String\s+)?(\w+)\s*=\s*(['"])([^'"]*)\2''').allMatches(raw))
        if (code.startsWith('const', m.start)) m.group(1)!: m.group(3)!,
    };

/// الوسيط الأوّل عند [at] إن كان نصّاً حرفيّاً (بأيّ علامة) — والثوابت فيه مفكوكة؛ وإلّا null.
String? _literal(String raw, String code, int at, Map<String, String> consts) {
  var i = at;
  while (i < code.length && (code[i] == ' ' || code[i] == '\n')) {
    i++;
  }
  if (i < code.length && code[i] == 'r') i++;
  if (i >= code.length || (code[i] != "'" && code[i] != '"')) return null;
  final e = code.indexOf(code[i], i + 1);
  if (e < 0) return null;
  return raw.substring(i + 1, e).replaceAllMapped(RegExp(r'\$\{?(\w+)\}?'), (m) => consts[m.group(1)!] ?? m.group(0)!);
}

/// نداء كتابةٍ على dio (`ApiClient.dio.post<…>(`، `_dio.put(`، `dio.request(`…) — حتى القوس المفتوح.
final _dioWrite = RegExp(r'[A-Za-z_]*[dD]io\s*\.\s*(post|put|patch|delete|request|postUri|putUri|patchUri|deleteUri)\s*(?:<[^()]*?>)?\s*\(');

int _lineOf(String code, int pos) => '\n'.allMatches(code.substring(0, pos)).length + 1;

/// مسار مشترك: الإضافة (`/api/v2/subscribers`) أو ما تحته (`/:idx/...`) — لا `-usage` ولا `-summary`.
bool _subscriberPath(String p) => p == '/api/v2/subscribers' || p.startsWith('/api/v2/subscribers/');

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
    final lib = _libMasked();

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
          api.add('${e.key}:${_lineOf(e.value.code, m.start)} ${m.group(0)}');
        }
        for (final m in reads.allMatches(e.value.code)) {
          api.add('${e.key}:${_lineOf(e.value.code, m.start)} ${m.group(0)}');
        }
      }
      expect(api, isEmpty, reason: 'وجهةٌ محفوظةٌ في طبقة الـAPI أو مأخوذةٌ من الشريط/القسم — مرّرها معاملاً');
    });

    test('قراءات الأقسام من خارجها مراجَعةٌ واحدةً واحدة وبطريقة تثبيتها مفحوصة (المفتوحة، أو شركة الصفّ، أو قيمةٌ بلا طلب) — '
        'الجديد يُراجَع', () {
      // واجهات «قوائم أخرى» (بادئاتها موجَّهةٌ حين يُعرض قسمها لشركةٍ أخرى): نداءٌ لها من ملفٍّ خارج قسمها يأخذ وجهة قسمٍ ظاهرٍ
      // ما لم يحدّد شركته — فكلّ موضعٍ هنا بطريقته، وتُفحص الطريقة في كلّ موضعٍ من الملفّ؛ وموضعٌ جديدٌ يفشل حتى يُراجَع.
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
      // open: داخل CompanyRoute.runOpen/pin · row: بشركة صفّها (MergedOps.* أو CompanyRoute.pin/run) · value: قيمةٌ بلا نداء ·
      // implicit: ضمنيٌّ عن قصد (يتبع قاعدة المعترض: المفتوحة، أو يُرفض تحت قسمٍ موجَّه) — سببه مكتوب.
      const reviewed = <String, (String, String)>{
        'lib/screens/accounts/accounts_screen.dart ManagersApi.fetchPassword': ('open', '«الصفحات» (OpenCompanyScope)'),
        'lib/screens/accounts/accounts_screen.dart ManagersApi.listFull': ('open', '«الصفحات» (OpenCompanyScope)'),
        'lib/screens/app_modules.dart TicketsApi.servedByProvider': ('value', 'قيمةٌ ثابتة، لا طلب'),
        'lib/screens/network_devices/fiber/fiber_outage_screen.dart BroadcastApi.broadcast': ('open', 'مشتركو أجهزة المفتوحة'),
        'lib/services/fiber/fiber_monitor.dart BroadcastApi.broadcast': ('open', '«رجع النت» بالخلفيّة'),
        'lib/screens/packages/packages_screen.dart ManagersApi.lite': ('open', 'قسم «للمفتوحة وحدها»'),
        'lib/screens/reports/activity_log_report_screen.dart ExpensesApi.list': ('open', 'تقرير المفتوحة'),
        'lib/screens/reports/all_managers_debts_screen.dart ManagerDebtsApi.list': ('open', 'تقرير المفتوحة'),
        'lib/screens/reports/all_managers_debts_screen.dart ManagerDebtsApi.summary': ('open', 'تقرير المفتوحة'),
        'lib/screens/reports/all_managers_debts_screen.dart ManagerMovementsApi.list': ('open', 'تقرير المفتوحة'),
        'lib/screens/reports/all_managers_debts_screen.dart ManagersApi.listFull': ('open', 'تقرير المفتوحة'),
        'lib/screens/reports/widgets/report_filters.dart EmployeesApi.list': ('open', 'فلاتر تقارير المفتوحة'),
        'lib/screens/reports/widgets/report_filters.dart ManagersApi.lite': ('open', 'فلاتر تقارير المفتوحة'),
        'lib/screens/subscribers/connection_alert_flow.dart PortalSettingsApi.fillAgentCode': ('row', 'MergedOps.run (بلا مفتاح ⇒ المفتوحة)'),
        'lib/screens/subscribers/sheets/activate_sheet.dart CardsApi.codeCardNotAllowed': ('value', 'ثابت رمز رفض، لا طلب'),
        'lib/screens/subscribers/sheets/activate_sheet.dart CardsApi.codeNoCards': ('value', 'ثابت رمز رفض، لا طلب'),
        'lib/screens/subscribers/subscribers_screen.dart ManagersApi.lite':
            ('implicit', 'الوضع العاديّ/الكبير وحده (لا أقسام موجَّهة خارج «كل الشركات»)؛ «كل الشركات» بمفتاح كلّ شركة'),
        'lib/screens/subscribers/subscribers_screen.dart TelegramApi.listBindings':
            ('implicit', 'الوضع العاديّ/الكبير وحده؛ «كل الشركات»: CompanyRoute.run(مفتاح الشركة)'),
        'lib/screens/whatsapp/widgets/send_scope_panel.dart SendScopeApi.fetch':
            ('implicit', 'إعدادات الصفحة التي تعرضه (adminIdFor يتبع النطاق) — قسم التبليغات لشركته'),
        'lib/screens/whatsapp/widgets/send_scope_panel.dart SendScopeApi.update':
            ('implicit', 'كتابةٌ ضمنيّة ⇒ المفتوحة، أو تُرفض تحت قسمٍ موجَّهٍ لغيرها'),
        'lib/services/manager_notice.dart ManagersApi.sendBalanceUpdatePush': ('implicit', 'من أفعال المدراء — كتابةٌ ضمنيّة'),
        'lib/services/manager_notice.dart ManagersApi.sendTelegram': ('implicit', 'من أفعال المدراء — كتابةٌ ضمنيّة'),
        'lib/services/permissions_service.dart EmployeesApi.me': ('open', 'صلاحيّات الجلسة'),
        'lib/widgets/manual_wa_chip.dart WaContactRiskApi.one': ('open', 'واتساب المفتوحة'),
        'lib/api/whatsapp_api.dart PortalSettingsApi.fillAgentCode': ('row', 'CompanyRoute.pin(شركة المشترك؛ بلا مفتاح ⇒ المفتوحة)'),
      };
      final open = RegExp(r'CompanyRoute\s*\.\s*(?:runOpen|pin)\s*(?:<[^()]*?>)?\s*\(');
      final row = RegExp(r'MergedOps\s*\.\s*(?:run|write|writeAt|pinned)\s*(?:<[^()]*?>)?\s*\(|CompanyRoute\s*\.\s*(?:pin|run|runOpen)\s*(?:<[^()]*?>)?\s*\(');
      final found = <String, List<int>>{};
      for (final e in lib.entries) {
        if (sectionDirs.any(e.key.startsWith)) continue;
        for (final a in apis.entries) {
          if (e.key == 'lib/api/${a.value}.dart') continue;
          for (final m in RegExp('\\b${a.key}\\s*\\.\\s*([a-z]\\w*)\\b').allMatches(e.value.code)) {
            (found['${e.key} ${a.key}.${m.group(1)}'] ??= []).add(m.start);
          }
        }
      }
      expect(found.keys.toSet().difference(reviewed.keys.toSet()), isEmpty,
          reason: 'نداءٌ جديد لواجهة قسمٍ من خارجه — ثبّته للمفتوحة (CompanyRoute.runOpen) أو بشركة صفّه (MergedOps/pin)، ثمّ أضفه هنا بطريقته');
      expect(reviewed.keys.toSet().difference(found.keys.toSet()), isEmpty, reason: 'موضعٌ مراجَعٌ زال — احذفه من القائمة');
      final unpinned = <String>[];
      for (final r in reviewed.entries) {
        final file = r.key.split(' ').first;
        final code = lib[file]!.code;
        for (final at in found[r.key] ?? const <int>[]) {
          final where = '${r.key} (سطر ${_lineOf(code, at)})';
          switch (r.value.$1) {
            case 'open':
              if (!_inside(code, at, open)) unpinned.add('$where: ليس داخل CompanyRoute.runOpen/pin');
            case 'row':
              if (!_inside(code, at, row)) unpinned.add('$where: ليس بشركة صفّه (MergedOps/CompanyRoute.pin)');
            case 'value':
              final after = code.substring(at).replaceFirst(RegExp(r'^\w+\s*\.\s*\w+'), '').trimLeft();
              if (after.startsWith('(')) unpinned.add('$where: نداءٌ لا قيمة');
            case 'implicit':
              break;
            default:
              unpinned.add('$where: طريقةٌ مجهولة ${r.value.$1}');
          }
        }
      }
      expect(unpinned, isEmpty, reason: 'موضعٌ مراجَعٌ لم يعد بطريقته');
    });

    test('كتابات المال في كلّ lib: كلّ نداء dio يكتب على مسار مال يحمل شركته صراحةً من معامل companyKey — أيّاً كان ملفّه وصيغته '
        '(post/put/patch/delete/request، علامتا الاقتباس، `\$_base`)', () {
      const prefixes = ['/api/v2/sales', '/api/v2/settlements', '/api/admin/expenses', '/api/v2/expenses'];
      // ملفّات المال: كلّ كتابةٍ فيها مهما كان مسارها (متغيّراً أو دالّة)
      const moneyFiles = {
        'lib/api/sales_api.dart', 'lib/api/settlements_api.dart', 'lib/api/expenses_api.dart', 'lib/api/recurring_expenses_api.dart',
      };
      const markers = ['CompanyRoute.explicit(companyKey', '_routed(companyKey'];
      final bad = <String>[];
      final perFile = <String, int>{};
      for (final e in lib.entries) {
        final raw = e.value.raw;
        final code = e.value.code;
        final consts = _consts(raw, code);
        for (final c in _dioWrite.allMatches(code)) {
          final open = c.end - 1;
          final close = _close(code, open);
          final path = _literal(raw, code, open + 1, consts);
          if (c.group(1) == 'request' && RegExp(r'''method:\s*(['"])GET\1''').hasMatch(raw.substring(open, close))) continue;
          if (path != null && CompanyRoute.readsByPost.contains(path)) continue;
          final money = moneyFiles.contains(e.key) || (path != null && prefixes.any(path.startsWith));
          if (!money) continue;
          perFile[e.key] = (perFile[e.key] ?? 0) + 1;
          final args = code.substring(open, close).replaceAll(RegExp(r'\s+'), '');
          if (!markers.any((m) => args.contains(m.replaceAll(' ', '')))) {
            bad.add('${e.key}:${_lineOf(code, c.start)} ${c.group(1)} ${path ?? '(مسارٌ غير حرفيّ)'}');
          }
        }
      }
      expect(bad, isEmpty, reason: 'كتابة مالٍ بلا شركةٍ صريحة — تأخذ الشركة المفتوحة أو تُرفض بدل شركتها');
      for (final f in moneyFiles) {
        expect(perFile[f] ?? 0, greaterThan(0), reason: '$f: الفحص لم يجد كتابات (تغيّرت الصيغة؟)');
      }
    });

    test('كتابات المشترك: كلّ نداءٍ لها من خارج lib/api صريح الشركة (MergedOps، CompanyRoute.pin/runOpen) — والجماعيّة وحدها '
        'ضمنيّة، وهي مرفوضةٌ في «كل الشركات» قبل أيّ طلب (والمعترض يرفض الضمنيّة على مشترك فيه)', () {
      // ١. واجهات الكتابة على مسار مشترك، مشتقّةٌ من lib/api: نداء dio يكتب على /api/v2/subscribers… (حرفيّاً أو بدالّةٍ مساعدة
      //    تبنيه)، أو دالّةٌ تنادي واحدةً منها — القراءات بـPOST (CompanyRoute.readsByPost) مستثناة.
      final writers = <String>{};
      final bodies = <String, ({String file, String body})>{};
      final decl = RegExp(r'\n  static ');
      for (final e in lib.entries) {
        if (!e.key.startsWith('lib/api/')) continue;
        final raw = e.value.raw;
        final code = e.value.code;
        final consts = _consts(raw, code);
        final classes = [
          for (final m in RegExp(r'\n(?:abstract\s+|final\s+|sealed\s+)?class\s+(\w+)').allMatches(code)) (at: m.start, name: m.group(1)!),
        ];
        final members = <({int at, String cls, String name})>[];
        for (final d in decl.allMatches(code)) {
          // اسم الدالّة: آخر معرّفٍ قبل أوّل `(` خارج <> — حقلٌ أو جالبٌ (`=`، `;`، `=>` قبله) ليس دالّة
          var k = d.end;
          var angle = 0;
          var stop = -1;
          while (k < code.length) {
            final ch = code[k];
            if (ch == '<') angle++;
            if (ch == '>') angle--;
            if (angle == 0 && (ch == '(' || ch == '=' || ch == ';' || ch == '{')) {
              stop = ch == '(' ? k : -1;
              break;
            }
            k++;
          }
          if (stop < 0) continue;
          final name = RegExp(r'(\w+)\s*(?:<[^()]*>)?\s*$').firstMatch(code.substring(d.end, stop))?.group(1);
          final cls = classes.lastWhere((c) => c.at < d.start, orElse: () => (at: 0, name: '')).name;
          if (name != null && cls.isNotEmpty) members.add((at: d.start, cls: cls, name: name));
        }
        for (var i = 0; i < members.length; i++) {
          final end = i + 1 < members.length ? members[i + 1].at : code.length;
          bodies['${members[i].cls}.${members[i].name}'] = (file: e.key, body: code.substring(members[i].at, end));
        }
        for (final c in _dioWrite.allMatches(code)) {
          final open = c.end - 1;
          var path = _literal(raw, code, open + 1, consts);
          if (path == null) {
            // دالّةٌ مساعدة تبني المسار (`_path(idx)`)
            final h = RegExp(r'\s*(\w+)\s*\(').matchAsPrefix(code, open + 1)?.group(1);
            final def = h == null ? null : RegExp('\\b$h\\s*\\([^)]*\\)\\s*(?:=>|\\{)').firstMatch(code);
            if (def != null && raw.substring(def.start, (def.end + 200).clamp(0, raw.length)).contains('/api/v2/subscribers')) {
              path = '/api/v2/subscribers/(helper)';
            }
          }
          if (path == null || !_subscriberPath(path) || CompanyRoute.readsByPost.contains(path)) continue;
          final m = members.lastWhere((m) => m.at < c.start, orElse: () => (at: 0, cls: '', name: ''));
          if (m.cls.isNotEmpty) writers.add('${m.cls}.${m.name}');
        }
      }
      // من ينادي كاتبةً كاتب
      for (var changed = true; changed;) {
        changed = false;
        for (final b in bodies.entries) {
          if (writers.contains(b.key)) continue;
          final cls = b.key.split('.').first;
          final calls = writers.any((w) {
            final (wc, wn) = (w.split('.').first, w.split('.').last);
            return RegExp('\\b$wc\\s*\\.\\s*$wn\\s*\\(').hasMatch(b.value.body) ||
                (wc == cls && RegExp('(?<![.\\w])$wn\\s*\\(').hasMatch(b.value.body.substring(b.value.body.indexOf('(') + 1)));
          });
          if (calls) {
            writers.add(b.key);
            changed = true;
          }
        }
      }
      expect(writers, {
        'EarthlinkApi.createSubscriber', 'EarthlinkApi.setAccountPassword', 'KitCardApi.start', 'PrivateNotesApi.save',
        'SubscriberPricesApi.remove', 'SubscriberPricesApi.set', 'SubscribersApi.activate', 'SubscribersApi.activateDetailed',
        'SubscribersApi.addCredit', 'SubscribersApi.addDebt', 'SubscribersApi.cancelProfileChange', 'SubscribersApi.createSubscriber',
        'SubscribersApi.delete', 'SubscribersApi.disconnect', 'SubscribersApi.extend', 'SubscribersApi.generatePortalQrToken',
        'SubscribersApi.payDebt', 'SubscribersApi.receiptLink', 'SubscribersApi.setDiscount', 'SubscribersApi.setLocation',
        'SubscribersApi.toggle', 'SubscribersApi.toggleResult', 'SubscribersApi.transferSubscriber', 'SubscribersApi.updateSubscriber',
      }, reason: 'واجهة كتابةٍ على مشتركٍ جديدة (أو زالت) — راجع نداءاتها أدناه ثمّ حدّث القائمة');

      // ٢. كلّ نداءٍ لها من خارج lib/api
      final pinned = RegExp(r'MergedOps\s*\.\s*(?:run|write|writeAt|pinned)\s*(?:<[^()]*?>)?\s*\(|'
          r'CompanyRoute\s*\.\s*(?:pin|runOpen)\s*(?:<[^()]*?>)?\s*\(');
      // `_co(...)` في شيتَي «مشترك جديد»: شركة الشيت (run بمفتاحها)، وبلاها في «كل الشركات» ⇒ المفتوحة صراحةً
      final co = RegExp(r'(?<![.\w])_co\s*\(');
      final coDef = RegExp(r'Future<T>\s+_co<T>\(Future<T> Function\(\) f\)\s*\{\s*final c = widget\.company;\s*'
          r'if \(c != null\) return CompanyRoute\.run\(c\.key, f\);\s*'
          r'return MergedMode\.active\.value \? CompanyRoute\.runOpen\(f\) : f\(\);\s*\}');
      // الجماعيّة: صفوف «كل الشركات» تُرفض قبلها بسببٍ (MergedOps.bulkRefusal)، والضمنيّة على مشترك يرفضها المعترض في الوضع
      const bulk = {
        'lib/screens/subscribers/subscribers_screen.dart SubscribersApi.disconnect',
        'lib/screens/subscribers/subscribers_screen.dart SubscribersApi.toggle',
        'lib/screens/subscribers/subscribers_screen.dart SubscribersApi.delete',
        'lib/screens/subscribers/sheets/bulk_activate_sheet.dart SubscribersApi.activateDetailed',
        'lib/screens/subscribers/sheets/bulk_pay_debt_sheet.dart SubscribersApi.payDebt',
      };
      final implicit = <String>[];
      final seen = <String>{};
      for (final e in lib.entries) {
        if (e.key.startsWith('lib/api/')) continue;
        final code = e.value.code;
        for (final w in writers) {
          final (wc, wn) = (w.split('.').first, w.split('.').last);
          for (final m in RegExp('\\b$wc\\s*\\.\\s*$wn\\b').allMatches(code)) {
            final site = '${e.key} $w';
            seen.add(site);
            if (bulk.contains(site)) continue;
            if (_inside(code, m.start, pinned)) continue;
            if (_inside(code, m.start, co) && coDef.hasMatch(e.value.raw)) continue;
            implicit.add('$site (سطر ${_lineOf(code, m.start)})');
          }
        }
      }
      expect(implicit, isEmpty,
          reason: 'كتابةٌ على مشتركٍ بلا شركةٍ صريحة — في «كل الشركات» يرفضها المعترض (رقم الصفّ لا يُعرف لأيّ شركة): مرّرها بـMergedOps');
      expect(bulk.difference(seen), isEmpty, reason: 'نداءٌ جماعيّ مراجَعٌ زال — احذفه من القائمة');
      for (final f in bulk.map((b) => b.split(' ').first).toSet()) {
        expect(lib[f]!.code.contains('MergedOps.bulkRefusal') || lib[f]!.code.contains('_bulkRowsOrRefuse'), isTrue,
            reason: '$f: العمليّة الجماعيّة بلا حارس «كل الشركات»');
      }
    });

    test('كشف الحساب لا يُفتح بلا قرار شركة: كلّ `AccountStatementScreen(` يمرّر companyKey (التحقّق الثالث من 179)', () {
      final sites = <String>[];
      final bad = <String>[];
      for (final e in lib.entries) {
        if (e.key == 'lib/screens/reports/account_statement_screen.dart') continue; // تعريفه
        final code = e.value.code;
        for (final m in RegExp(r'\bAccountStatementScreen\s*\(').allMatches(code)) {
          final open = m.end - 1;
          final at = '${e.key}:${_lineOf(code, m.start)}';
          sites.add(at);
          if (!RegExp(r'\bcompanyKey\s*:').hasMatch(code.substring(open, _close(code, open)))) bad.add(at);
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
          final at = '${e.key}:${_lineOf(code, m.start)}';
          // أعمق نداء تنقّلٍ يحويه
          RegExpMatch? inner;
          for (final n in nav.allMatches(code)) {
            final open = n.end - 1;
            if (open >= m.start) break;
            if (_close(code, open) > m.start) inner = n;
          }
          if (inner == null) {
            if (values.containsKey(e.key)) {
              seenValues.add(e.key);
            } else {
              bad.add('$at: يُبنى خارج نداء تنقّل — راجعه وأضفه بطريقة دخوله');
            }
            continue;
          }
          final open = inner.end - 1;
          final args = code.substring(open, _close(code, open));
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
      final pr = RegExp(r'\.\s*pushAndRemoveUntil\s*\(').allMatches(flow).where((n) => n.end - 1 < use && _close(flow, n.end - 1) > use);
      expect(pr, isNotEmpty, reason: 'shellBuilder يُدخل بـpushAndRemoveUntil');
      expect(removeAll.hasMatch(flow.substring(pr.last.end - 1, _close(flow, pr.last.end - 1))), isTrue);
    });
  });
}
