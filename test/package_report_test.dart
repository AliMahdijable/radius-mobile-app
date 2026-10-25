import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/package_report_api.dart';
import 'package:rad_mysvcs/api/view_scope_api.dart';

/// «توزيع الباقات والأرباح» (#٥، ٢٥ أكتوبر) — عقد GET /api/reports/finance/packages في التطبيق، وقسم «الباقات» في «نطاق العرض».
///
/// الحرّاس: ما لم يُعرف null لا صفر (أعدادٌ تعذّرت ⇒ «—»)، والكلفة والربح من الخادم وحده (owner)، والمختصر بلا «باقات أخرى»
/// ولا الساكن، و٤٠٣ يُعرَف قفلاً لا «تعذّراً»، والتطبيق يطلب القسم الجديد (?sv=2).
void main() {
  Map<String, dynamic> row(String key, String name,
          {int? total, int? active, int acts = 0, int ext = 0, num revenue = 0, Map<String, dynamic> owner = const {}}) =>
      {
        'key': key,
        'name': name,
        'profile_id': key.startsWith('p:') ? int.parse(key.substring(2)) : null,
        'price': 35000,
        'subscribers_total': total,
        'subscribers_active': active,
        'activations': acts,
        'sync_activations': 0,
        'extensions': ext,
        'revenue': revenue,
        ...owner,
      };

  Map<String, dynamic> ownerBody() => {
        'success': true,
        'data': {
          'owner': true,
          'cost_exempt': false,
          'provider': 'sas4',
          'rows': [
            row('p:7', 'D-Active 75', total: 260, active: 231, acts: 25, ext: 9, revenue: 1375000,
                owner: {'unit_cost': 36000, 'cost': 900000, 'profit_total': 475000, 'profit_estimated': 4389000}),
            row('p:5', 'FTTH 50', total: 412, active: 365, acts: 38, ext: 12, revenue: 1330000,
                owner: {'unit_cost': 21000, 'cost': 798000, 'profit_total': 532000, 'profit_estimated': 5110000}),
            row('p:3', 'اقتصاديّة', total: 0, active: 0), // ساكنة: لا مشتركين ولا حركة
            row('p:9', 'Gaming', total: 74, active: 66, acts: 11, ext: 3),
            row('p:11', 'أعمال', total: 9, active: 8, acts: 2),
            row('p:12', 'ليليّة', total: 5, active: 5, acts: 1),
            row('other', 'باقات أخرى', total: 17, active: 4),
            row('unknown', 'باقة غير معروفة', acts: 3, revenue: 90000),
          ],
          'totals': {
            'packages': 7,
            'subscribers_total': 777,
            'subscribers_active': 679,
            'activations': 80,
            'sync_activations': 0,
            'extensions': 24,
            'revenue': 2795000,
            'cost': 1698000,
            'profit_total': 1097000,
            'cost_rows': 104,
            'cost_known_rows': 100,
            'cost_complete': false,
            'profit_estimated': 9499000,
            'estimate_missing_packages': 1,
          },
        },
        'unavailable_parts': [],
      };

  group('PackageReport.fromBody', () {
    test('المالك: الصفوف والمجاميع والكلفة والربح كما ردّها الخادم', () {
      final r = PackageReport.fromBody(ownerBody())!;
      expect(r.owner, isTrue);
      expect(r.provider, 'sas4');
      expect(r.rows.length, 8);
      final a = r.rows.first;
      expect([a.key, a.name, a.profileId, a.subscribersTotal, a.subscribersActive, a.activations, a.extensions],
          ['p:7', 'D-Active 75', 7, 260, 231, 25, 9]);
      expect([a.unitCost, a.cost, a.profitTotal, a.profitEstimated], [36000, 900000, 475000, 4389000]);
      expect(r.totals.costComplete, isFalse);
      expect([r.totals.costRows, r.totals.costKnownRows, r.totals.estimateMissingPackages], [104, 100, 1]);
      expect(r.countsKnown, isTrue);
      expect(r.unavailableParts, isEmpty);
    });

    test('🚨 الموظّف وأعدادٌ تعذّرت: null لا صفر، ولا كلفة ولا ربح، والجزء مسمّى (في الجسم أو data بلا تكرار)', () {
      final r = PackageReport.fromBody({
        'success': true,
        'data': {
          'owner': false,
          'cost_exempt': false,
          'rows': [row('p:5', 'FTTH 50', acts: 38, revenue: 1330000), row('p:7', 'D-Active', acts: 40)],
          'totals': {'packages': 2, 'subscribers_total': null, 'subscribers_active': null, 'activations': 78, 'extensions': 0, 'revenue': 1330000},
          'unavailable_parts': ['subscribers'],
        },
        'unavailable_parts': ['subscribers'],
      })!;
      expect(r.owner, isFalse);
      expect(r.countsKnown, isFalse);
      expect(r.totals.subscribersTotal, isNull);
      expect(r.rows.first.subscribersActive, isNull);
      expect(r.rows.first.profitTotal, isNull);
      expect(r.totals.profitEstimated, isNull);
      expect(r.unavailableParts, ['subscribers']);
      // بلا أعداد: المختصر بالتفعيلات
      expect(r.topRows(4).top.map((x) => x.key), ['p:7', 'p:5']);
    });

    test('data ليست كائناً ⇒ null (لا تقريرٌ فارغٌ مزعوم)', () {
      expect(PackageReport.fromBody({'success': true, 'data': null}), isNull);
      expect(PackageReport.fromBody({'success': true, 'data': []}), isNull);
    });
  });

  group('topRows — مختصر الرئيسيّة', () {
    test('الأكثر فعّالين أوّلاً؛ بلا «باقات أخرى» ولا «غير معروفة» ولا الساكنة؛ والباقي يُعدّ', () {
      final r = PackageReport.fromBody(ownerBody())!;
      final (:top, :rest) = r.topRows(4);
      expect(top.map((x) => x.key), ['p:5', 'p:7', 'p:9', 'p:11']);
      expect(rest, 1); // p:12 — والساكنة p:3 و other و unknown خارج العدّ
    });
  });

  group('PackageReportApi.fetch', () {
    late _FakeAdapter adapter;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      adapter = _FakeAdapter();
      ApiClient.dio.httpClientAdapter = adapter;
    });

    test('الطلب: الفترة يوماً كاملاً + نطاق التقارير + الموظّف، والردّ محلَّل', () async {
      adapter.reply = (200, ownerBody());
      final r = await PackageReportApi.fetch(
        from: DateTime(2026, 9, 26, 15),
        to: DateTime(2026, 10, 25, 9),
        userIds: const ['jt:10', ''],
        employeeId: 4,
      );
      expect(adapter.lastPath, '/api/reports/finance/packages');
      expect(adapter.lastQuery['date_from'], '2026-09-26 00:00:00');
      expect(adapter.lastQuery['date_to'], '2026-10-25 23:59:59');
      expect(adapter.lastQuery['user_ids'], 'jt:10');
      expect(adapter.lastQuery['employee_id'], '4');
      expect(r.data?.rows.length, 8);
      expect(r.error, isNull);
    });

    test('🚨 ٤٠٣ (صلاحيّةٌ سُحبت) ⇒ status 403 بلا بيانات — الواجهة تُقفل لا «تعذّر»', () async {
      adapter.reply = (403, {'success': false, 'message': 'لا تملك صلاحيّة التقرير الماليّ'});
      final r = await PackageReportApi.fetch(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 25));
      expect(r.status, 403);
      expect(r.data, isNull);
      expect(r.error, 'لا تملك صلاحيّة التقرير الماليّ');
    });

    test('٤٠٩ (تعذّر) ⇒ رسالة الخادم العربيّة', () async {
      adapter.reply = (409, {'success': false, 'code': 'PACKAGE_REPORT_UNAVAILABLE', 'message': 'تعذّر تجهيز التقرير الآن'});
      final r = await PackageReportApi.fetch(from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 25));
      expect(r.status, 409);
      expect(r.error, 'تعذّر تجهيز التقرير الآن');
    });

    test('«كل الشركات»: الشركة المختارة موجَّهةً (x-company-key) بلا user_ids — نطاقها من جلستها', () async {
      adapter.reply = (200, ownerBody());
      await PackageReportApi.fetch(
        from: DateTime(2026, 10, 1),
        to: DateTime(2026, 10, 25),
        userIds: const ['jt:10'],
        companyKey: 'c0123456789ab',
      );
      expect(adapter.lastQuery.containsKey('user_ids'), isFalse);
      expect(adapter.lastHeaders['x-company-key'], 'c0123456789ab');
    });
  });

  group('«نطاق العرض» — قسم «الباقات»', () {
    late _FakeAdapter adapter;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      FlutterSecureStorage.setMockInitialValues({});
      adapter = _FakeAdapter();
      ApiClient.dio.httpClientAdapter = adapter;
    });

    test('التطبيق يطلب القسم الجديد (?sv=2) في القراءة والكتابة، وتسميته عنده', () async {
      adapter.reply = (200, {
        'success': true,
        'managers': [],
        'sections': [
          for (final k in ['subscribers', 'wallet', 'revenue', 'activities', 'wa_banner', 'packages']) {'key': k, 'hidden': k == 'packages'},
        ],
      });
      final r = await ViewScopeApi.load();
      expect(adapter.lastQuery['sv'], '2');
      expect(r.sections.map((s) => s.key).last, 'packages');
      expect(r.sections.last.hidden, isTrue);
      await ViewScopeApi.setSection('packages', false);
      expect(adapter.lastQuery['sv'], '2');
      expect(adapter.lastBody, {'sectionKey': 'packages', 'hidden': false});
      expect(dashSectionLabels['packages']?.title, 'توزيع الباقات');
    });
  });

  test('كلّ مفتاح pkgdist.* في الشاشتين موجودٌ بالعربيّة والإنجليزيّة (ومفاتيح الأجزاء والبطاقة في المركز)', () {
    final ar = jsonDecode(File('assets/translations/ar.json').readAsStringSync()) as Map<String, dynamic>;
    final en = jsonDecode(File('assets/translations/en.json').readAsStringSync()) as Map<String, dynamic>;
    final used = <String>{
      for (final f in [
        'lib/screens/dashboard/widgets/packages_summary_card.dart',
        'lib/screens/reports/package_distribution_screen.dart',
      ])
        for (final m in RegExp(r"'pkgdist\.([a-z0-9_]+)'").allMatches(File(f).readAsStringSync())) m.group(1)!,
      // packagePartText يبنيها: 'pkgdist.part_$part'
      'part_activity', 'part_package_cost', 'part_packages', 'part_subscribers', 'part_other',
    };
    expect(used.length, greaterThan(20));
    for (final k in used) {
      expect((ar['pkgdist'] as Map).containsKey(k), isTrue, reason: 'ar pkgdist.$k');
      expect((en['pkgdist'] as Map).containsKey(k), isTrue, reason: 'en pkgdist.$k');
    }
    for (final k in ['packages', 'packages_hint']) {
      expect((ar['reports'] as Map).containsKey(k), isTrue, reason: 'ar reports.$k');
      expect((en['reports'] as Map).containsKey(k), isTrue, reason: 'en reports.$k');
    }
  });
}

/// خادمٌ وهميّ لـ`ApiClient.dio` — يردّ بما في [reply] ويحفظ آخر طلب.
class _FakeAdapter implements HttpClientAdapter {
  (int, Map<String, dynamic>) reply = (200, {'success': true});
  RequestOptions? _last;

  String get lastPath => _last!.path;
  Map<String, dynamic> get lastQuery => _last!.queryParameters;
  Map<String, dynamic> get lastHeaders => _last!.headers;
  Map<String, dynamic> get lastBody => Map<String, dynamic>.from(_last!.data as Map);

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    _last = options;
    final (status, body) = reply;
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
