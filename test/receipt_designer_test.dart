import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/receipt_settings_api.dart';
import 'package:rad_mysvcs/core/platform/app_platform.dart';
import 'package:rad_mysvcs/core/platform/desktop_layout.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/core/widgets/permission_locked.dart';
import 'package:rad_mysvcs/screens/desktop/desk_zoom.dart';
import 'package:rad_mysvcs/screens/print_templates/designer/designer_controller.dart';
import 'package:rad_mysvcs/screens/print_templates/designer/designer_elements.dart';
import 'package:rad_mysvcs/screens/print_templates/designer/element_inspector_sheet.dart';
import 'package:rad_mysvcs/screens/print_templates/designer/elements_tab.dart';
import 'package:rad_mysvcs/screens/print_templates/designer/preview_pane.dart';
import 'package:rad_mysvcs/screens/print_templates/print_templates_screen.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/services/receipt_layout.dart';

import 'sim_el/sim_harness.dart';

/// «تصميم الوصل» في التطبيق (spec §4.4/§4.6) — بروتوكول الحفظ أوّلاً (لا يضيع تصميمٌ أبداً):
///   • الأعمدة السبعة كلّها، ومفاتيح v1 الستّة والثلاثون، و`layout` مضغوطاً (null حين يكون افتراضيّاً)، و`if_updated_at`
///     (null = «لم أرَ صفّاً»؛ خادمٌ أقدم بلا رمز)، وبلا `logo_data` (الشعار المحفوظ يبقى).
///   • `v` لا يَنزل (v2 المحفوظ يُحفظ v3)، والمفاتيح التي لا يعرفها التطبيق تبقى.
///   • تراجعٌ وإعادةٌ للافتراضيّ، ورسائل 400 و409 («تحديث») و413، والقفل (لا إخفاء)، وبلا QR لايرث لنك.
const _png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

Map<String, dynamic> _row({Object? updatedAt = '2026-11-01T07:05:00.000Z', Map<String, dynamic>? design, bool token = true}) => {
      'shop_name': 'مكتب النور',
      'shop_address': 'النجف',
      'shop_phone': '0780 111 2222',
      'footer_text': null,
      'show_qr': 1,
      'paper_size': 'pos',
      'logo_data': _png,
      'auto_print': 0,
      'design': design ??
          {
            ...receiptV1AllDefaults,
            'font_size_base': 11,
            'layout': {
              'v': 2,
              'density': 'compact',
              'fields': {
                'phone': {'show': false},
              },
              'future_key': {'x': 1},
            },
          },
      if (token) 'updated_at': updatedAt,
    };

ReceiptDesignController _ctl(
  Map<String, dynamic> row, {
  List<Map<String, dynamic>>? sent,
  ReceiptSaveResult Function(Map<String, dynamic> body)? reply,
}) =>
    ReceiptDesignController(
      fetch: () async => ReceiptDesignLoad.ok(ReceiptSettings.fromJson(row)),
      save: (body) async {
        sent?.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
        return reply?.call(body) ??
            ReceiptSaveResult(
              ok: true,
              status: 200,
              message: 'تم',
              design: Map<String, dynamic>.from(body['design'] as Map),
              hasDesign: true,
              updatedAt: '2026-11-01T08:00:00.000Z',
              hasUpdatedAt: true,
            );
      },
    );

void _expectBody(Map<String, dynamic> body, {required Object? token, bool hasToken = true}) {
  for (final k in ReceiptDesignController.columnKeys) {
    expect(body.containsKey(k), isTrue, reason: 'العمود $k يُرسل دائماً (الغائب يمحوه الخادم)');
  }
  expect(body.containsKey('logo_data'), isFalse, reason: 'الشعار المحفوظ يبقى');
  final design = body['design'] as Map<String, dynamic>;
  expect(design.keys.where((k) => k != 'layout').toSet(), receiptV1AllDefaults.keys.toSet(),
      reason: 'مفاتيح v1 الستّة والثلاثون وحدها');
  expect(design.containsKey('layout'), isTrue);
  expect(body.containsKey('if_updated_at'), hasToken);
  if (hasToken) expect(body['if_updated_at'], token);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('١. بروتوكول الحفظ (المتحكّم)', () {
    test('تعديلٌ على تصميم v2: الأعمدة السبعة + ٣٦ مفتاحاً + layout v3 بمفتاحه المجهول + if_updated_at، بلا الشعار', () async {
      final sent = <Map<String, dynamic>>[];
      final c = _ctl(_row(), sent: sent);
      await c.load();
      expect([c.loading, c.loadError, c.dirty, c.logo?.isNotEmpty], [false, null, false, true]);
      expect(c.layout!['v'], 3, reason: 'v لا يقلّ عن ٣ منذ التحميل');
      c.setShown('username', false);
      expect(c.dirty, isTrue);
      final r = await c.save();
      expect(r.ok, isTrue);
      final body = sent.single;
      _expectBody(body, token: '2026-11-01T07:05:00.000Z');
      final design = body['design'] as Map<String, dynamic>;
      expect(design['font_size_base'], 11, reason: 'المحفوظ يبقى');
      expect(design['paper_width_mm'], 80, reason: 'الغائب افتراضيّ');
      final layout = design['layout'] as Map<String, dynamic>;
      expect(layout['v'], 3, reason: 'v2 المحفوظ يُحفظ v3 — لا يَنزل');
      expect(layout['density'], 'compact');
      expect(layout['future_key'], {'x': 1}, reason: 'مفتاحٌ من نسخةٍ أحدث يبقى كما هو');
      expect(layout['fields'], {
        'username': {'show': false},
        'phone': {'show': false},
      });
      expect([body['shop_name'], body['show_qr'], body['paper_size'], body['auto_print']], ['مكتب النور', true, 'pos', false]);
      // بعد الحفظ: الرمز الجديد، ولا «غير محفوظ».
      expect([c.dirty, c.updatedAt], [false, '2026-11-01T08:00:00.000Z']);
      c.setV1('font_size_base', 12);
      await c.save();
      expect(sent.last['if_updated_at'], '2026-11-01T08:00:00.000Z', reason: 'رمز الحفظ التالي من الردّ');
    });

    test('لا صفّ بعد (updated_at null) ⇒ if_updated_at: null مُرسَل؛ وخادمٌ أقدم (بلا updated_at) ⇒ بلا رمز', () async {
      final sent = <Map<String, dynamic>>[];
      final fresh = _ctl(_row(updatedAt: null, design: null)..['design'] = null, sent: sent);
      await fresh.load();
      expect(fresh.layout, isNull);
      fresh.setColumn('auto_print', true);
      await fresh.save();
      _expectBody(sent.last, token: null);
      expect((sent.last['design'] as Map)['layout'], isNull, reason: 'بلا layout ⇒ يبقى وصل v1');

      final old = _ctl(_row(token: false), sent: sent);
      await old.load();
      old.setV1('font_size_base', 12);
      await old.save();
      _expectBody(sent.last, token: null, hasToken: false);
    });

    test('تصميمٌ افتراضيّ ⇒ layout: null (v1 حرفيّاً)، و«إعادة للافتراضي» لا تمسّ المحتوى', () async {
      final sent = <Map<String, dynamic>>[];
      final c = _ctl(_row(), sent: sent);
      await c.load();
      c.resetToDefault();
      await c.save();
      final body = sent.single;
      expect((body['design'] as Map)['layout'], isNull);
      expect((body['design'] as Map)['font_size_base'], 13);
      expect([body['shop_name'], body['shop_address'], body['shop_phone']], ['مكتب النور', 'النجف', '0780 111 2222']);
    });

    test('التراجع: خطوةً خطوة حتى التحميل، والكتابة المتّصلة لقطةٌ واحدة، وحدّ ٣٠', () async {
      final c = _ctl(_row());
      await c.load();
      final before = jsonEncode(c.buildSaveBody());
      c.setField('amount', {'pt': 14});
      c.setField('amount', {'bold': false});
      for (final s in ['ا', 'ال', 'الم', 'المب']) {
        c.setField('amount', {'label': s}, typing: true);
      }
      c.undo();
      expect(c.styleOf('amount').containsKey('label'), isFalse, reason: 'الكتابة كلّها تراجعٌ واحد');
      c.undo();
      c.undo();
      expect(jsonEncode(c.buildSaveBody()), before);
      expect([c.canUndo, c.dirty], [false, false]);
      for (var i = 0; i < 40; i++) {
        c.setV1('font_size_base', 9 + i % 10);
      }
      var n = 0;
      while (c.canUndo) {
        c.undo();
        n++;
      }
      expect(n, ReceiptDesignController.maxUndo);
    });

    test('القوالب: الورق ومفاتيح v1 والكثافة و«أسود فقط» — الحقول كما هي', () async {
      final c = _ctl(_row());
      await c.load();
      c.applyTemplate('a4_formal');
      expect([c.paperSize, c.design['font_size_base'], c.design['border_style']], ['a4', 14, 'none']);
      expect(c.styleOf('phone'), {'show': false});
      final l = c.compactLayout!;
      expect(l.containsKey('density'), isFalse, reason: 'normal لا يُحفظ');
      expect(l['future_key'], {'x': 1});
      c.applyTemplate('pos58_compact');
      expect([c.paperSize, c.design['paper_width_mm'], c.compactLayout!['density'], c.compactLayout!['mono']],
          ['pos', 58, 'compact', true]);
    });

    test('الترتيب: صفٌّ لأعلى قسمه ثمّ إلى القسم المجاور، والقسم بين الأقسام', () async {
      final c = _ctl(_row(design: {}));
      await c.load();
      for (var i = 0; i < 3; i++) {
        c.move('balance_debt', -1);
      }
      expect(c.rowOrder['transaction']!.first, 'balance_debt', reason: 'أعلى المعاملة');
      c.move('balance_debt', -1);
      expect(c.rowOrder['package']!.last, 'balance_debt', reason: 'من أعلى قسمه إلى آخر القسم السابق');
      c.move('balance_debt', 1);
      expect(c.rowOrder['transaction']!.first, 'balance_debt');
      c.move('phone', 1); // آخر المشترك ⇒ أوّل الباقة
      expect(c.rowOrder['package']!.first, 'phone');
      c.move('transaction', -1);
      expect(c.bodyOrder, ['subscriber', 'transaction', 'package']);
      final order = c.compactLayout!['order'] as Map;
      expect(order['body'], ['subscriber', 'transaction']);
      expect((order['transaction'] as List).first, 'balance_debt');
      // مسار الحفظ لا يحمل تكراراً ولا غير صفّ (الخادم يرفضهما).
      final all = [for (final s in receiptBodySections) ...((order[s] as List?) ?? const [])];
      expect(all.toSet().length, all.length);
    });

    test('خادمٌ أقدم يُسقط مفاتيح v3: الحفظ «ناجح» بمسارات ما لم يُحفظ', () async {
      final c = _ctl(
        _row(),
        reply: (body) => ReceiptSaveResult(
          ok: true,
          message: 'تم',
          status: 200,
          hasDesign: true,
          design: {
            ...Map<String, dynamic>.from(body['design'] as Map),
            'layout': const {'v': 2, 'density': 'compact'},
          },
        ),
      );
      await c.load();
      c.setField('amount', {'pt': 14});
      final r = await c.save();
      expect(r.ok, isTrue);
      expect(r.notSaved, containsAll(['fields', 'future_key']));
      expect(r.message, contains('لم يحفظ'));
    });

    test('الخادم ينظّف النصوص (فراغٌ وسطرٌ في آخرها، \\r\\n، عزل الاتّجاه، ترتيب الحركات): «حُفظ» بلا إنذار، ويُتبنّى ما حفظه',
        () async {
      // تنظيف الخادم الحقيقيّ (cleanStr في receiptDesign.js) لهذه النصوص — مسجّلٌ من Node. الأخير: شدّةٌ ثمّ فتحة
      // (كما يكتبها الكيبورد) ⇐ NFC: الفتحة ثمّ الشدّة.
      const typed = ['سدّد قبل {expiry_date} ', 'شكراً لكم\n', ' سطر\r\nثانٍ ', '\u2068{phone}\u2069 ', 'م\u064Fحم\u0651\u064Eد'];
      const saved = ['سدّد قبل {expiry_date}', 'شكراً لكم', 'سطر\nثانٍ', '{phone}', 'م\u064Fحم\u064E\u0651د'];
      expect([for (final s in typed) receiptServerCleanText(s, multiline: true)], saved);
      final sent = <Map<String, dynamic>>[];
      final c = _ctl(
        _row(),
        sent: sent,
        reply: (body) {
          final design = jsonDecode(jsonEncode(body['design'])) as Map<String, dynamic>;
          final layout = design['layout'] as Map<String, dynamic>;
          for (final t in (layout['texts'] as List).cast<Map>()) {
            final k = typed.indexOf(t['text'] as String);
            if (k >= 0) t['text'] = saved[k];
          }
          return ReceiptSaveResult(
            ok: true,
            status: 200,
            message: 'تم',
            design: design,
            hasDesign: true,
            updatedAt: '2026-11-01T08:00:00.000Z',
            hasUpdatedAt: true,
          );
        },
      );
      await c.load();
      for (final s in typed) {
        c.addText();
        c.setText(c.texts.length - 1, {'text': s});
      }
      final r = await c.save();
      expect([r.ok, r.notSaved, r.message], [true, isEmpty, 'حُفظ تصميم الوصل'], reason: 'حُفظ كلّه — لا «لم يحفظ الخادم»');
      final body = sent.single['design'] as Map;
      expect([for (final t in (body['layout'] as Map)['texts'] as List) (t as Map)['text']], typed,
          reason: 'النصّ يُرسل كما كُتب — الخادم ينظّفه');
      expect([for (final t in c.texts) t['text']], saved, reason: 'ما حفظه الخادم يُتبنّى: الحفظ التالي لا يُنذر');
      expect(c.dirty, isFalse);
      c.setText(0, {'bold': true});
      final again = await c.save();
      expect([again.ok, again.notSaved], [true, isEmpty]);
    });

    test('409 ⇒ تعارض، والتصميم كما هو (لا يُتبنّى شيء)', () async {
      final c = _ctl(
        _row(),
        reply: (_) => const ReceiptSaveResult(ok: false, status: 409, code: 'STALE_DESIGN', message: 'تغيّر'),
      );
      await c.load();
      c.setField('amount', {'pt': 14});
      final r = await c.save();
      expect([r.ok, r.conflict], [false, true]);
      expect(c.dirty, isTrue);
    });
  });

  group('٢. الشاشة على الخادم الوهميّ', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp();
      ReceiptSettingsApi.clearCache();
      PermissionsService.debugSet(isEmployee: false);
    });
    tearDown(() {
      PermissionsService.debugReset();
      ProviderService.debugSet(null);
      ReceiptSettingsApi.clearCache();
    });

    const v = SimVariant(390, dark: false);

    Future<void> open(WidgetTester t) async {
      await pumpSim(t, v, home: (_) => const PrintTemplatesScreen(canRaster: false));
      await t.pump(const Duration(milliseconds: 300));
    }

    Finder rowSwitch(String name) => find.descendant(
          of: find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first,
          matching: find.byType(Switch),
        );

    testWidgets('إخفاء صفّ ثمّ «حفظ»: جسم POST كما يجب، و«حفظ» يختفي بعده', (t) async {
      server.reply('GET', '/api/v2/receipt-settings', 200, {'success': true, 'data': _row()});
      server.reply('POST', '/api/v2/receipt-settings', 200, {
        'success': true,
        'message': 'تم حفظ إعدادات الوصل',
        'design': {...receiptV1AllDefaults, 'layout': null},
        'updated_at': '2026-11-01T08:00:00.000Z',
      });
      await open(t);
      expect(find.text('تصميم الوصل'), findsOneWidget);
      expect(find.text('حفظ'), findsNothing, reason: '«حفظ» حين يتغيّر شيء');
      await t.scrollUntilVisible(find.text('اسم المستخدم'), 120, scrollable: find.byType(Scrollable).last);
      await t.tap(rowSwitch('اسم المستخدم'));
      await t.pump();
      expect(find.text('حفظ'), findsOneWidget);
      await t.tap(find.text('حفظ'));
      await t.pump(const Duration(milliseconds: 300));
      final body = server.bodies('POST', '/api/v2/receipt-settings').single;
      _expectBody(body, token: '2026-11-01T07:05:00.000Z');
      final layout = (body['design'] as Map)['layout'] as Map;
      expect([layout['v'], layout['future_key'], (layout['fields'] as Map)['username']], [3, {'x': 1}, {'show': false}]);
      expect(find.text('حفظ'), findsNothing);
      await simDrain(t);
    });

    for (final c in [
      (status: 400, body: {'success': false, 'code': 'LAYOUT_BAD_VALUE', 'path': 'fields.username.pt', 'message': 'قيمةٌ غير مقبولة: «اسم المستخدم ← الحجم» = 13'}, text: 'قيمةٌ غير مقبولة: «اسم المستخدم ← الحجم» = 13'),
      (status: 413, body: {'success': false, 'code': 'BODY_TOO_BIG', 'message': 'الطلب أكبر من المسموح — صغّر الشعار ثمّ احفظ'}, text: 'الطلب أكبر من المسموح — صغّر الشعار ثمّ احفظ'),
    ]) {
      testWidgets('رفض ${c.status}: رسالة الخادم بمسارها، والتعديل باقٍ', (t) async {
        server.reply('GET', '/api/v2/receipt-settings', 200, {'success': true, 'data': _row()});
        server.reply('POST', '/api/v2/receipt-settings', c.status, c.body);
        await open(t);
        await t.tap(rowSwitch('اسم المحلّ'));
        await t.pump();
        await t.tap(find.text('حفظ'));
        await t.pump(const Duration(milliseconds: 300));
        expect(find.textContaining(c.text), findsOneWidget);
        expect(find.text('حفظ'), findsOneWidget, reason: 'لم يُحفظ ⇒ «حفظ» باقٍ');
        await simDrain(t);
      });
    }

    testWidgets('409: «تحديث (تضيع تعديلاتك)» يجلب التصميم من جديد', (t) async {
      server.reply('GET', '/api/v2/receipt-settings', 200, {'success': true, 'data': _row()});
      server.reply('POST', '/api/v2/receipt-settings', 409, {
        'success': false,
        'code': 'STALE_DESIGN',
        'message': 'تغيّر تصميم الوصل من جهازٍ آخر بعد فتحك له — حدّث ثمّ أعد تعديلك',
      });
      await open(t);
      await t.tap(rowSwitch('اسم المحلّ'));
      await t.pump();
      await t.tap(find.text('حفظ'));
      await t.pumpAndSettle();
      expect(find.text('تحديث (تضيع تعديلاتك)'), findsOneWidget);
      await t.tap(find.text('تحديث (تضيع تعديلاتك)'));
      await t.pumpAndSettle();
      expect(server.calls('GET', '/api/v2/receipt-settings'), hasLength(2));
      expect(find.text('حفظ'), findsNothing);
      await simDrain(t);
    });

    testWidgets('موظّفٌ بلا صلاحيّة: المعاينة والعناصر ظاهرة، والتعديل مقفل لا مخفيّ', (t) async {
      PermissionsService.debugSet(isEmployee: true, permissions: {'subscribers.view': true});
      server.reply('GET', '/api/v2/receipt-settings', 200, {'success': true, 'data': _row()});
      await open(t);
      expect(find.text('عرضٌ فقط — لا صلاحيّة لتعديل التصميم'), findsOneWidget);
      expect(find.text('اسم المحلّ'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(PermLockIcon), findsWidgets);
      await t.tap(find.text('اسم المحلّ'));
      await t.pumpAndSettle();
      expect(find.text('يظهر في الوصل'), findsOneWidget, reason: 'الخصائص تُرى');
      await t.tap(find.text('يظهر في الوصل'));
      await t.pump();
      expect(find.text('حفظ'), findsNothing, reason: 'لا تعديل');
      await t.pump(const Duration(seconds: 3));
      expect(server.calls('POST', '/api/v2/receipt-settings'), isEmpty);
      await simDrain(t);
    });

    testWidgets('ايرث لنك: لا QR على الوصل — ملاحظةٌ مكانه، وموظّفها «يغيّره صاحب الحساب»', (t) async {
      ProviderService.debugSet('earthlink');
      server.reply('GET', '/api/v2/receipt-settings', 200, {'success': true, 'data': _row()});
      await open(t);
      await t.scrollUntilVisible(find.text('رمز QR غير متاح لهذه الشركة — لا يُطبع على وصلها'), 160,
          scrollable: find.byType(Scrollable).last);
      expect(find.text('التعليق تحت الرمز'), findsNothing);
      await t.pumpWidget(const SizedBox());
      PermissionsService.debugSet(isEmployee: true, permissions: {'subscribers.view': true});
      await open(t);
      expect(find.text('تصميم الوصل يغيّره صاحب الحساب'), findsOneWidget);
      await simDrain(t);
    });
  });

  group('٣. الحاسبة: الأعمدة من عرض الشاشة لا النافذة', () {
    late SimServer server;
    setUpAll(simSetUpAll);
    setUp(() async {
      server = await simSetUp();
      ReceiptSettingsApi.clearCache();
      PermissionsService.debugSet(isEmployee: false);
      AppPlatform.debugIsDesktop = true;
    });
    tearDown(() {
      AppPlatform.debugIsDesktop = null;
      PermissionsService.debugReset();
      ReceiptSettingsApi.clearCache();
    });

    /// كغلاف الحاسبة (desktop_shell.dart `_content`): النافذة = المحتوى + القائمة الجانبيّة ٢٧٢ + ١٦، والشاشة في منطقة
    /// المحتوى — MediaQuery بعرضها وDesktopScope وDeskZoom ومكدّس القسم.
    Future<void> openDesk(WidgetTester t, double content) async {
      server.reply('GET', '/api/v2/receipt-settings', 200, {'success': true, 'data': _row()});
      await pumpSim(
        t,
        SimVariant(content + 272 + 16, dark: false),
        settle: false,
        home: (_) => Builder(
          builder: (context) {
            final mq = MediaQuery.of(context);
            return Row(
              children: [
                const SizedBox(width: 272),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: content,
                        height: c.maxHeight,
                        child: MediaQuery(
                          data: mq.copyWith(size: Size(content, c.maxHeight), padding: EdgeInsets.zero),
                          child: DesktopScope(
                            child: DeskZoom(
                              scale: 1,
                              child: Navigator(
                                onGenerateRoute: (_) =>
                                    MaterialPageRoute(builder: (_) => const PrintTemplatesScreen(canRaster: false)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      await t.pumpAndSettle();
    }

    double previewWidth(WidgetTester t) => t.getSize(find.byType(PreviewPane)).width;

    for (final c in [
      (content: 736.0, three: false, label: 'نافذة ١٠٢٤ (محتوى ٧٣٦): الخصائص مكان القائمة'),
      (content: 960.0, three: false, label: 'نصف شاشة ١٩٢٠ (محتوى ٩٦٠): الخصائص مكان القائمة'),
      (content: 1264.0, three: true, label: 'محتوى ١٢٦٤: ثلاثة أعمدة'),
    ]) {
      testWidgets('${c.label} — بلا فيضان، والمعاينة ظاهرة', (t) async {
        await openDesk(t, c.content);
        expect(DesktopLayout.wide(t.element(find.byType(PrintTemplatesScreen))), isTrue);
        expect(t.takeException(), isNull);
        expect(previewWidth(t), greaterThanOrEqualTo(280));
        expect(find.byType(ElementsTab).hitTestable(), findsOneWidget);

        await t.tap(find.text('اسم المحلّ').first);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: 'لا «RenderFlex overflowed» والخصائص مفتوحة');
        expect(find.byType(DesignSheet), findsNothing, reason: 'عمودٌ بجانب المعاينة، لا ورقة');
        expect(find.byType(ElementInspector).hitTestable(), findsOneWidget);
        expect(previewWidth(t), greaterThanOrEqualTo(280), reason: 'المعاينة لا تختفي والخصائص مفتوحة');
        expect(find.byType(ElementsTab).hitTestable(), c.three ? findsOneWidget : findsNothing);
        expect(t.getSize(find.byType(ElementInspector)).width, lessThan(c.three ? 380 : 420));
        expect(
          previewWidth(t) + (c.three ? 420 + 380 + 2 : 420 + 1),
          moreOrLessEquals(c.content),
          reason: 'الأعمدة تملأ عرض المحتوى بالضبط',
        );

        await t.tap(find.byTooltip(c.three ? 'إغلاق' : 'رجوع للعناصر'));
        await t.pumpAndSettle();
        expect(find.byType(ElementInspector), findsNothing);
        expect(find.byType(ElementsTab).hitTestable(), findsOneWidget);
        expect(t.takeException(), isNull);
        await simDrain(t);
      });
    }

    testWidgets('محتوى أضيق من عمودين (٦٤٠): تخطيط الهاتف — المعاينة فوق بعرضها، والخصائص ورقة', (t) async {
      await openDesk(t, 640);
      expect(t.takeException(), isNull);
      expect(previewWidth(t), 640);
      await t.tap(find.text('اسم المحلّ').first);
      await t.pumpAndSettle();
      expect(find.byType(DesignSheet), findsOneWidget);
      expect(find.byType(ElementInspector), findsOneWidget);
      expect(t.takeException(), isNull);
      await simDrain(t);
    });
  });

  test('أسماء كلّ العناصر عربيّة (لا معرّفٌ خامّ في القائمة)', () {
    for (final id in [...receiptFieldIds, ...receiptSectionIds, ...receiptContainerIds]) {
      expect(designerElementNames[id], isNotNull, reason: id);
    }
  });
}
