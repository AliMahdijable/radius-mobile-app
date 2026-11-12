import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/broadcast_api.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';
import 'package:rad_mysvcs/models/whatsapp_schedule.dart';
import 'package:rad_mysvcs/screens/whatsapp/whatsapp_schedules_screen.dart';
import 'package:rad_mysvcs/widgets/debt_filter_panel.dart';
import 'package:rad_mysvcs/widgets/list_kit.dart';

import 'visual_perm/visual_perm_harness.dart';

/// «تحديد المدينين» داخل «تذكير بالديون المستحقة» التلقائيّ (المالك ١٢ نوفمبر ٢٠٢٦ — الخادم 4d0d0d7، الويب 781ba26).
///   • النموذج: التحديد المحفوظ يُقرأ من صفّ الجدولة، ومفتاحه يُرسَل مع الحفظ حين يتغيّر وحده (كائنٌ أو null) — فحفظُ الوقت لا يمسّه.
///   • الشاشة: اللوحة تظهر بما يعلنه الخادم وحده، العدّ «يطابق الآن» من الخادم، وقائمة من يطابق؛ خطأ التحديد يمنع الحفظ؛ تعذّر
///     العدّ لا يعطّل شيئاً؛ والمخزَّن التالف يُقال ويُصلحه الحفظ.
/// الخادم وهميّ: لا رسالة تُرسَل، والطلبات تُسجَّل لتُثبت ما يُرسَل حرفاً.
class _SchedServer implements HttpClientAdapter {
  _SchedServer(this.inner);
  final HttpClientAdapter inner;

  /// الخادم يعرف التحديد؟ (الأقدم لا يعيد debtFilter مع الجدولات)
  bool capable = true;
  bool ageAvailable = true;

  /// صفّ تذكير الديون موجود على الخادم؟
  bool exists = true;
  bool enabled = true;
  String mode = 'weekly';

  /// المحفوظ على الخادم (null = بلا تحديد).
  Map<String, dynamic>? saved;
  bool invalid = false;

  /// ردّ المعاينة القادم: (status, body) — null ⇒ نجاح بالصفوف أدناه.
  (int, Map<String, dynamic>)? previewFails;

  /// ردّ الحفظ القادم: (status, body) — null ⇒ نجاح.
  (int, Map<String, dynamic>)? saveFails;

  final previews = <Map<String, dynamic>>[];
  final saves = <Map<String, dynamic>>[];
  final toggles = <Map<String, dynamic>>[];

  static const rows = [
    {'username': 'ahmed.k@najaf', 'name': 'أحمد كامل', 'debt': 75000, 'days': null, 'legacy': true},
    {'username': 'hussein77@najaf', 'name': 'حسين عبد الأمير', 'debt': 61000, 'days': 92, 'legacy': false},
    {'username': 'haider.s@najaf', 'name': null, 'debt': 52000, 'days': 31, 'legacy': false},
  ];

  static ResponseBody _json(int status, Object body) => ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  Map<String, dynamic> get _debtRow => {
        'id': 12,
        'admin_id': 'supernet:12',
        'schedule_type': 'debt_reminder',
        'is_enabled': enabled ? 1 : 0,
        'scheduled_time': '11:00:00',
        'active_days': [0, 1, 2, 3, 4, 5, 6],
        'schedule_mode': mode,
        'month_days': mode == 'monthly' ? [1, 15] : null,
        'days_before': null,
        'channel_preference': 'auto',
        'debt_filter': invalid ? null : saved,
        if (invalid) 'debt_filter_invalid': true,
      };

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final m = o.method.toUpperCase();
    final p = o.path;
    if (m == 'GET' && p.startsWith('/api/whatsapp/schedules/')) {
      return _json(200, {
        'success': true,
        'schedules': [
          {
            'id': 11, 'admin_id': 'supernet:12', 'schedule_type': 'expiry_warning', 'is_enabled': 1, 'scheduled_time': '13:00:00',
            'active_days': [0, 1, 2, 3, 4, 5, 6], 'schedule_mode': 'weekly', 'month_days': null, 'days_before': 3,
            'channel_preference': 'auto', if (capable) 'debt_filter': null,
          },
          if (exists) (capable ? _debtRow : (Map<String, dynamic>.from(_debtRow)..remove('debt_filter'))),
        ],
        if (capable)
          'debtFilter': {
            'version': 1, 'schedule': true, 'preview': true, 'amount': true, 'age': ageAvailable, 'ageMeaning': 'oldest_unpaid',
            if (!ageAvailable) 'ageNote': 'عمر الدين غير معروف لمشتركي هذه الشركة بعد (ديونها في الساس) — التحديد بالمبلغ وحده',
            'presets': [7, 15, 30, 60, 90], 'maxAgeDays': 3650, 'maxAmount': 10000000000,
          },
      });
    }
    if (m == 'GET' && p.startsWith('/api/whatsapp/schedule-debt-preview/')) {
      previews.add(Map<String, dynamic>.from(o.queryParameters));
      final f = previewFails;
      if (f != null) return _json(f.$1, f.$2);
      return _json(200, {
        'success': true, 'dryRun': true, 'scheduled': true, 'mode': 'debtors', 'count': 2, 'audience': 3, 'deduped': 0,
        'excludedHighRisk': 0, 'missing': 0, 'rows': rows, 'truncated': false, 'audienceKey': 'a'.padRight(32, '0'), 'total': 9,
        'debtFilter': {'summary': 'x', 'considered': 9, 'kept': 3, 'amountOut': 5, 'ageOut': 1, 'unknownAge': 0, 'legacy': 1},
      });
    }
    if (m == 'POST' && p == '/api/whatsapp/save-schedule') {
      final b = Map<String, dynamic>.from(o.data as Map);
      saves.add(b);
      final f = saveFails;
      if (f != null) return _json(f.$1, f.$2);
      final sd = Map<String, dynamic>.from(b['scheduleData'] as Map);
      if (b['scheduleType'] == 'debt_reminder') {
        exists = true;
        enabled = sd['isEnabled'] == true;
        mode = (sd['scheduleMode'] ?? 'weekly').toString();
        // قاعدة الخادم: المفتاح غائب ⇒ المحفوظ يبقى · null ⇒ يُمسح · كائن ⇒ يُحفظ
        if (sd.containsKey('debtFilter')) {
          saved = sd['debtFilter'] == null ? null : Map<String, dynamic>.from(sd['debtFilter'] as Map);
          invalid = false;
        }
      }
      return _json(200, {'success': true, 'message': 'تم حفظ الجدولة بنجاح', 'cancelledPending': 0});
    }
    if (m == 'PATCH' && p == '/api/whatsapp/schedule-toggle') {
      toggles.add(Map<String, dynamic>.from(o.data as Map));
      return _json(200, {'success': true, 'message': 'تم'});
    }
    return inner.fetch(o, requestStream, cancelFuture);
  }

  @override
  void close({bool force = false}) => inner.close(force: force);
}

const _narrow = VisualDevice('_320', Size(320, 2000), 2);

Map<String, dynamic> _dataOf(Map<String, dynamic> saveBody) => Map<String, dynamic>.from(saveBody['scheduleData'] as Map);

void main() {
  setUpAll(visualSetUpAll);

  group('النموذج', () {
    test('التحديد المحفوظ يُقرأ من الصفّ — أرقامٌ صحيحة للمفاتيح المعروفة وحدها', () {
      final s = WhatsAppSchedule.fromJson({
        'id': 1, 'admin_id': '2', 'schedule_type': 'debt_reminder', 'scheduled_time': '11:00:00',
        'debt_filter': {'minAgeDays': 30, 'minAmount': 50000, 'maxAmount': 100000.0, 'junk': 7},
      });
      expect(s.debtFilter, {'minAgeDays': 30, 'minAmount': 50000, 'maxAmount': 100000});
      expect(s.debtFilterInvalid, isFalse);
      expect(s.sendDebtFilter, isFalse, reason: 'لا يُرسَل إلّا حين يطلبه من غيّره');
      for (final bad in [null, 'x', 5, <int>[], {'minAmount': '50000'}, {'minAmount': -1}, {'minAgeDays': 1.5}]) {
        expect(WhatsAppSchedule.fromJson({'schedule_type': 'debt_reminder', 'debt_filter': bad}).debtFilter, isEmpty, reason: '$bad');
      }
      expect(WhatsAppSchedule.fromJson({'schedule_type': 'debt_reminder', 'debt_filter': null, 'debt_filter_invalid': true}).debtFilterInvalid, isTrue);
    });

    test('الحفظ: المفتاح غائبٌ افتراضاً (المحفوظ يبقى)، وبطلبه كائنٌ بحدوده أو null للمسح — لا كائن فارغ أبداً', () {
      const base = WhatsAppSchedule(adminId: '2', scheduleType: 'debt_reminder', scheduledTime: '11:00:00', activeDays: [1]);
      expect(_dataOf(base.toSaveJson()).containsKey('debtFilter'), isFalse);
      // تحديدٌ في النموذج بلا طلب إرساله: لا يُرسَل
      expect(_dataOf(base.copyWith(debtFilter: {'minAmount': 5}).toSaveJson()).containsKey('debtFilter'), isFalse);
      final set = _dataOf(base.copyWith(debtFilter: {'minAgeDays': 30, 'maxAmount': 100000}, sendDebtFilter: true).toSaveJson());
      expect(set['debtFilter'], {'minAgeDays': 30, 'maxAmount': 100000});
      final clear = _dataOf(base.copyWith(debtFilter: const {}, sendDebtFilter: true).toSaveJson());
      expect(clear.containsKey('debtFilter'), isTrue);
      expect(clear['debtFilter'], isNull);
    });
  });

  group('النداءات', () {
    tearDown(visualTearDown);

    test('الجدولات تحمل ما يدعمه الخادم؛ والخادم الأقدم بلا قدرة', () async {
      final server = _SchedServer(await visualSetUp(s1bSasOwner))..saved = {'minAgeDays': 30};
      ApiClient.dio.httpClientAdapter = server;
      final b = await WhatsAppApi.loadSchedulesBundle();
      expect(b!.schedules, hasLength(2));
      expect(b.debtCap!.age, isTrue);
      expect(b.debtCap!.presets, [7, 15, 30, 60, 90]);
      expect(b.schedules.last.debtFilter, {'minAgeDays': 30});
      expect((await WhatsAppApi.loadSchedules())!.length, 2, reason: 'النداء القديم كما كان');
      server.capable = false;
      final old = await WhatsAppApi.loadSchedulesBundle();
      expect(old!.debtCap, isNull);
      expect(old.schedules.last.debtFilter, isEmpty);
    });

    test('العدّ: الحدود في الاستعلام أرقاماً، والردّ بشكل معاينة التبليغ؛ وتعذّره برمزه', () async {
      final server = _SchedServer(await visualSetUp(s1bSasOwner));
      ApiClient.dio.httpClientAdapter = server;
      final r = await WhatsAppApi.scheduleDebtPreview(const DebtFilter(minAgeDays: 30, minAmount: 50000));
      expect(server.previews.single, {'minAgeDays': 30, 'minAmount': 50000});
      expect(r.preview!.audience, 3);
      expect(r.preview!.count, 2);
      expect(r.preview!.legacy, 1);
      expect(r.preview!.rows.first.name, 'أحمد كامل');
      server.previewFails = (409, {'success': false, 'code': 'SCHEDULE_DEBT_PREVIEW_UNAVAILABLE', 'message': 'تعذّر جلب قائمة المشتركين الآن'});
      final bad = await WhatsAppApi.scheduleDebtPreview(const DebtFilter(maxAmount: 25000));
      expect(bad.preview, isNull);
      expect(bad.code, 'SCHEDULE_DEBT_PREVIEW_UNAVAILABLE');
    });
  });

  group('الشاشة', () {
    tearDown(visualTearDown);

    Future<_SchedServer> open(WidgetTester t, {VisualDevice d = phoneTall, void Function(_SchedServer)? prep}) async {
      final server = _SchedServer(await visualSetUp(s1bSasOwner));
      prep?.call(server);
      ApiClient.dio.httpClientAdapter = server;
      await pumpVisual(t, d, home: (_) => const WhatsAppSchedulesScreen());
      await settle(t, seconds: 2);
      return server;
    }

    Future<void> saveDebt(WidgetTester t) async {
      await t.ensureVisible(find.text('حفظ الجدولة').last);
      await t.pump();
      await t.tap(find.text('حفظ الجدولة').last);
      await settle(t, seconds: 6); // الحفظ + إعادة الجلب + زوال الإشعار السفليّ
    }

    testWidgets('خادمٌ أقدم: لا لوحة، والحفظ كما كان بلا المفتاح', (t) async {
      final server = await open(t, prep: (s) => s.capable = false);
      expect(find.byType(DebtFilterPanel), findsNothing);
      expect(find.byKey(const ValueKey('sched-df-hint')), findsNothing);
      expect(server.previews, isEmpty);
      await saveDebt(t);
      expect(_dataOf(server.saves.single).containsKey('debtFilter'), isFalse);
    });

    testWidgets('بلا تحديدٍ محفوظ: اللوحة ظاهرة تقول «لكلّ من عليه دين»، ولا عدّ؛ وحفظٌ بلا تغيير لا يرسل المفتاح', (t) async {
      final server = await open(t);
      expect(find.byType(DebtFilterPanel), findsOneWidget);
      expect(find.text('بلا تحديد: يصل التذكير لكلّ من عليه دين.'), findsOneWidget);
      expect(find.byKey(const ValueKey('sched-df-saved')), findsNothing);
      expect(find.byKey(const ValueKey('debt-filter-result')), findsNothing);
      expect(server.previews, isEmpty);
      await saveDebt(t);
      expect(_dataOf(server.saves.single).containsKey('debtFilter'), isFalse);
      expect(t.takeException(), isNull);
    });

    testWidgets('تحديدٌ محفوظ: يُعرض بحدوده وعدّه من الخادم؛ وتغيير يومٍ وحده لا يمسّ التحديد', (t) async {
      final server = await open(t, prep: (s) => s.saved = {'minAgeDays': 30, 'minAmount': 50000, 'maxAmount': 100000});
      expect(server.previews.single, {'minAgeDays': 30, 'minAmount': 50000, 'maxAmount': 100000});
      expect(find.text('يصل الآن لمن: أقدم دين 30 يوماً فأكثر · من 50,000 إلى 100,000 د.ع'), findsOneWidget);
      expect(find.text('يُحسب من جديد عند كلّ تنفيذ: من سدّد يخرج، ومن قدُم دينه أو كبر يدخل.'), findsOneWidget);
      final result = find.byKey(const ValueKey('debt-filter-result'));
      expect(find.descendant(of: result, matching: find.textContaining('مديناً يطابقون', findRichText: true)), findsOneWidget);
      expect(find.descendant(of: result, matching: find.textContaining('سيصل 2')), findsOneWidget);
      expect(find.descendant(of: result, matching: find.textContaining('1 دين قديم')), findsOneWidget);
      expect(t.widget<ListFilterChip>(find.byKey(const ValueKey('df-age-30'))).active, isTrue);

      // يومٌ من أيّام الأسبوع وحده ثمّ حفظ ⇒ لا مفتاح تحديد في الطلب (الخادم يُبقي المحفوظ)
      await t.tap(find.widgetWithText(FilterChip, 'جمع').last);
      await t.pump();
      await saveDebt(t);
      final sd = _dataOf(server.saves.single);
      expect(sd.containsKey('debtFilter'), isFalse);
      expect(sd['activeDays'], [0, 1, 2, 3, 4, 6]);
      expect(server.saved, {'minAgeDays': 30, 'minAmount': 50000, 'maxAmount': 100000}, reason: 'باقٍ على الخادم');
      expect(find.textContaining('يصل الآن لمن: أقدم دين 30 يوماً'), findsOneWidget);
    });

    testWidgets('تغيير التحديد: يُعاد العدّ، والحفظ يرسله كائناً، والمحفوظ الجديد يُعرض', (t) async {
      final server = await open(t, prep: (s) => s.saved = {'minAgeDays': 30});
      expect(server.previews, hasLength(1));
      await t.tap(find.byKey(const ValueKey('df-age-60')));
      await settle(t, seconds: 2);
      expect(server.previews.last, {'minAgeDays': 60});
      // المبلغ من الشريحة الجاهزة
      await t.tap(find.text('50 إلى 100 ألف'));
      await settle(t, seconds: 2);
      expect(server.previews.last, {'minAgeDays': 60, 'minAmount': 50000, 'maxAmount': 100000});
      // المحفوظ ما زال القديم حتى يُحفظ
      expect(find.text('يصل الآن لمن: أقدم دين 30 يوماً فأكثر'), findsOneWidget);
      await saveDebt(t);
      expect(_dataOf(server.saves.single)['debtFilter'], {'minAgeDays': 60, 'minAmount': 50000, 'maxAmount': 100000});
      expect(find.text('يصل الآن لمن: أقدم دين 60 يوماً فأكثر · من 50,000 إلى 100,000 د.ع'), findsOneWidget);
      // حفظٌ ثانٍ بلا تغيير: لا مفتاح
      await saveDebt(t);
      expect(_dataOf(server.saves.last).containsKey('debtFilter'), isFalse);
    });

    testWidgets('«مسح» ثمّ حفظ ⇒ null صريح (يُمسح على الخادم)، ويعود «لكلّ من عليه دين»', (t) async {
      final server = await open(t, prep: (s) => s.saved = {'maxAmount': 25000});
      await t.tap(find.text('مسح'));
      await settle(t, seconds: 1);
      expect(find.byKey(const ValueKey('debt-filter-result')), findsNothing);
      await saveDebt(t);
      final sd = _dataOf(server.saves.single);
      expect(sd.containsKey('debtFilter'), isTrue);
      expect(sd['debtFilter'], isNull);
      expect(server.saved, isNull);
      expect(find.text('بلا تحديد: يصل التذكير لكلّ من عليه دين.'), findsOneWidget);
      expect(find.byKey(const ValueKey('sched-df-saved')), findsNothing);
    });

    testWidgets('تحديدٌ فيه خطأ (الأدنى أكبر من الأعلى): لا عدّ ولا حفظ — يُقال', (t) async {
      final server = await open(t);
      await t.enterText(find.byKey(const ValueKey('df-min')), '90000');
      await t.enterText(find.byKey(const ValueKey('df-max')), '20000');
      await settle(t, seconds: 2);
      expect(find.text('الحدّ الأدنى أكبر من الأعلى'), findsOneWidget);
      expect(server.previews, isEmpty);
      await saveDebt(t);
      expect(server.saves, isEmpty);
      expect(find.text('الحدّ الأدنى أكبر من الأعلى'), findsWidgets);
    });

    testWidgets('تعذّر العدّ لا يعطّل شيئاً: سطرٌ قصير و«إعادة»، والحفظ يمضي', (t) async {
      final server = await open(t, prep: (s) {
        s.saved = {'minAmount': 50000};
        s.previewFails = (409, {'success': false, 'code': 'SCHEDULE_DEBT_PREVIEW_UNAVAILABLE', 'message': 'تعذّر جلب قائمة المشتركين الآن — العدّ غير متاح'});
      });
      expect(find.text('تعذّر العدّ الآن — التحديد يُطبَّق عند كلّ تنفيذ'), findsOneWidget);
      expect(find.byKey(const ValueKey('sched-df-list')), findsNothing);
      server.previewFails = null;
      await t.tap(find.text('إعادة'));
      await settle(t, seconds: 2);
      expect(find.textContaining('مديناً يطابقون', findRichText: true), findsOneWidget);
      expect(server.previews, hasLength(2));
    });

    testWidgets('شركةٌ بلا مصدر أعمار: سبب الخادم مكان الشرائح، والمبلغ يعمل', (t) async {
      final server = await open(t, prep: (s) => s.ageAvailable = false);
      expect(find.textContaining('عمر الدين غير معروف لمشتركي هذه الشركة'), findsOneWidget);
      expect(find.byKey(const ValueKey('df-age-30')), findsNothing);
      await t.tap(find.text('حتى 25 ألف'));
      await settle(t, seconds: 2);
      expect(server.previews.single, {'maxAmount': 25000});
      await saveDebt(t);
      expect(_dataOf(server.saves.single)['debtFilter'], {'maxAmount': 25000});
    });

    testWidgets('عمرٌ محفوظ والدفتر غير متاحٍ الآن: لا عدّ، والمحفوظ لا يُمسّ بحفظ غيره', (t) async {
      final server = await open(t, prep: (s) {
        s.ageAvailable = false;
        s.saved = {'minAgeDays': 30};
      });
      expect(find.text('عمر الدين المحفوظ يُطبَّق عند التنفيذ — العدّ غير متاحٍ الآن'), findsOneWidget);
      expect(server.previews, isEmpty);
      await t.tap(find.widgetWithText(FilterChip, 'جمع').last);
      await t.pump();
      await saveDebt(t);
      expect(_dataOf(server.saves.single).containsKey('debtFilter'), isFalse);
      expect(server.saved, {'minAgeDays': 30});
    });

    testWidgets('مخزَّنٌ تالف: يُقال بسطرٍ أحمر، والحفظ يُصلحه (null صريح)', (t) async {
      final server = await open(t, prep: (s) => s.invalid = true);
      expect(find.byKey(const ValueKey('sched-df-invalid')), findsOneWidget);
      await saveDebt(t);
      final sd = _dataOf(server.saves.single);
      expect(sd.containsKey('debtFilter'), isTrue);
      expect(sd['debtFilter'], isNull);
      expect(find.byKey(const ValueKey('sched-df-invalid')), findsNothing);
    });

    testWidgets('رفض الخادم للحفظ يُعرض بنصّه، والتحديد على الشاشة يبقى', (t) async {
      final server = await open(t, prep: (s) {
        s.saveFails = (422, {'success': false, 'code': 'SCHEDULE_DEBT_FILTER_AGE_UNSUPPORTED', 'message': 'عمر الدين غير معروف لمشتركي هذه الشركة بعد. لم تُحفظ الجدولة'});
      });
      await t.tap(find.byKey(const ValueKey('df-age-30')));
      await settle(t, seconds: 2);
      await t.ensureVisible(find.text('حفظ الجدولة').last);
      await t.tap(find.text('حفظ الجدولة').last);
      await settle(t, seconds: 1);
      expect(find.textContaining('لم تُحفظ الجدولة'), findsOneWidget);
      expect(t.widget<ListFilterChip>(find.byKey(const ValueKey('df-age-30'))).active, isTrue);
      expect(server.saved, isNull);
      await settle(t, seconds: 6);
    });

    testWidgets('أوّل تفعيلٍ (لا صفّ بعد) ينشئ الجدولة بالتحديد الذي على الشاشة', (t) async {
      final server = await open(t, prep: (s) {
        s.exists = false;
        s.enabled = false;
      });
      await t.tap(find.text('100 ألف فأكثر'));
      await settle(t, seconds: 2);
      await t.tap(find.byType(Switch).last);
      await settle(t, seconds: 6);
      final sd = _dataOf(server.saves.single);
      expect(sd['isEnabled'], isTrue);
      expect(sd['debtFilter'], {'minAmount': 100000});
      expect(server.toggles, isEmpty);
    });

    testWidgets('«عرض من يطابق الآن»: الأسماء والدين وعمر أقدم دين و«دين قديم»', (t) async {
      final server = await open(t, d: phone, prep: (s) => s.saved = {'minAgeDays': 30, 'minAmount': 50000, 'maxAmount': 100000});
      await t.ensureVisible(find.byKey(const ValueKey('sched-df-list')));
      await settle(t, seconds: 1);
      await shoot(t, s1bSasOwner, 'schedule_debt_filter', phone, server.inner as VisualServer);
      await t.tap(find.byKey(const ValueKey('sched-df-list')));
      await settle(t, seconds: 1);
      expect(find.text('من يطابق التحديد الآن'), findsOneWidget);
      expect(find.text('أحمد كامل'), findsOneWidget);
      expect(find.text('حسين عبد الأمير'), findsOneWidget);
      expect(find.text('haider.s@najaf'), findsOneWidget, reason: 'بلا اسمٍ يُعرض اليوزر');
      expect(find.text('دين قديم'), findsOneWidget);
      expect(find.text('92 يوماً'), findsOneWidget);
      await shoot(t, s1bSasOwner, 'schedule_debt_filter_sheet', phone, server.inner as VisualServer);
    });

    testWidgets('الوضع الداكن و٣٢٠: لا فيض', (t) async {
      final dark = await open(t, d: phoneDark, prep: (s) => s.saved = {'minAgeDays': 30, 'minAmount': 50000, 'maxAmount': 100000});
      await t.ensureVisible(find.byKey(const ValueKey('sched-df-hint')));
      await settle(t, seconds: 1);
      expect(t.takeException(), isNull);
      await shoot(t, s1bSasOwner, 'schedule_debt_filter', phoneDark, dark.inner as VisualServer);
    });

    testWidgets('٣٢٠: اللوحة كاملة بلا فيض، والشهريّ كما كان', (t) async {
      final server = await open(t, d: _narrow, prep: (s) {
        s.saved = {'minAgeDays': 45, 'minAmount': 50000, 'maxAmount': 100000};
        s.mode = 'monthly';
      });
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('df-age-custom')), findsOneWidget, reason: 'عمرٌ ليس من الشرائح يفتح «مدّة أخرى» عليه');
      await shoot(t, s1bSasOwner, 'schedule_debt_filter', _narrow, server.inner as VisualServer);
      await saveDebt(t);
      final sd = _dataOf(server.saves.single);
      expect(sd['scheduleMode'], 'monthly');
      expect(sd['monthDays'], [1, 15]);
      expect(sd.containsKey('debtFilter'), isFalse);
    });
  });
}
