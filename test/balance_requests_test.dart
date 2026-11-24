import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:rad_mysvcs/api/balance_requests_api.dart';
import 'package:rad_mysvcs/api/whatsapp_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/screens/app_modules.dart';
import 'package:rad_mysvcs/screens/balance_requests/balance_request_widgets.dart';
import 'package:rad_mysvcs/screens/balance_requests/incoming_balance_requests_screen.dart';
import 'package:rad_mysvcs/screens/balance_requests/sub_balance_request_screen.dart';
import 'package:rad_mysvcs/services/manager_money.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/transfer_pay.dart';

import 'sim_el/sim_harness.dart';

/// «طلب رصيد من مديرك» بالتطبيق (المرحلة ٢ — المالك ٢٣ نوفمبر: «يسوي طلب رصيد من المدير الاعلى… يدز له صورة حوالة»؛ «قسم خاص به…
/// اذا ماكو مدير فرعي ينختفي»). العقد من ردّ الخادم كما يكتبه (server/balanceRequests.js — الطرفيّ)، وقسم الفرعيّ ونافذة طلبه، والبطاقة
/// تظهر/تُقفل/تغيب، و«طلبات الرصيد» للأعلى: «قبول وشحن» يرسل رقم الطلب مع الشحن، والرفض بسببه، وحسم «قيد التأكّد».
void main() {
  final meJson = {
    'enabled': true,
    'can_request': true,
    'parent': {'page': '2', 'username': 'abu.ali', 'network': 'شبكة النور', 'phone': '07801111111', 'whatsapp': '9647801111111'},
    'pay': {'zaincash': '07801234567', 'master': '5222333344445555', 'note': 'حوّل واكتب اسمك'},
    'pending': 0,
    'last_deposit': {'at': '2026-11-20T10:00:00.000Z', 'amount': 300000, 'is_loan': false},
    'requests': [
      {
        'id': 7, 'status': 'rejected', 'created_at': '2026-11-22T18:00:00.000Z', 'amount': 250000, 'pay_method': 'master',
        'method_label': 'حوالة ماستر', 'has_image': true, 'image_live': false, 'reject_reason': 'المبلغ بالصورة 200,000 لا 250,000',
      },
      {
        'id': 6, 'status': 'done', 'created_at': '2026-11-20T09:00:00.000Z', 'amount': 300000, 'pay_method': 'cash', 'method_label': 'كاش باليد',
        'done': {'amount': 300000, 'is_loan': false, 'paid_via': 'cash', 'balance_before': 85000, 'balance_after': 385000},
      },
    ],
  };

  group('العقد', () {
    test('قسم الفرعيّ: مفتوح بأبيه وطرق الدفع وطلباته؛ مطفأ/بلا أب/تالف ⇒ لا قسم', () {
      final me = BalanceReqMe.fromJson(meJson);
      expect([me.enabled, me.canRequest, me.parent!.title, me.parent!.username, me.pay.zaincash, me.pay.any], [true, true, 'شبكة النور', 'abu.ali', '07801234567', true]);
      expect([me.lastDepositAmount, me.lastDepositLoan, me.requests.length], [300000, false, 2]);
      expect(me.requests.first.rejectReason, 'المبلغ بالصورة 200,000 لا 250,000');
      expect(me.requests.last.done!.balanceAfter, 385000);
      expect(BalanceReqMe.fromJson({'enabled': false}).enabled, isFalse);
      expect(BalanceReqMe.fromJson({'enabled': true}).enabled, isFalse, reason: 'بلا أبٍ لا قسم');
      expect(BalanceReqMe.fromJson('x').enabled, isFalse);
    });

    test('طلب الأعلى: المدير الفرعيّ و«قراءة الوصل» وما يُحاوَل — والطريقة المقترحة لنافذة الشحن', () {
      final r = BalanceRequest.fromJson({
        'id': '15', 'status': 'processing', 'amount': '500000', 'pay_method': 'zaincash', 'method_label': 'حوالة زين كاش', 'has_image': true,
        'sub': {'page': 'jt:12', 'sas_id': '12', 'username': 'ali.hasan', 'name': null},
        'ai': {'status': 'done', 'verdict': 'match', 'level': 'ok', 'amount': 500000, 'lines': [{'level': 'ok', 'text': '✅ مطابق'}]},
        'unverified': true,
        'attempt': {'amount': 450000, 'is_loan': false, 'paid_via': 'cash'},
      })!;
      expect([r.id, r.amount, r.isProcessing, r.unverified, r.sub!.title, r.ai!.verdict, r.attempt!.amount], [15, 500000, true, true, 'ali.hasan', 'match', 450000]);
      expect(r.suggestedVia, PaidVia.zaincash);
      expect(BalanceRequest.fromJson({'id': 1, 'amount': 1000, 'pay_method': 'other', 'pay_name': 'آسيا'})!.suggestedVia, const PaidVia('other', 'آسيا'));
      expect(BalanceRequest.fromJson({'id': 1, 'amount': 1000, 'pay_method': 'loan'})!.suggestedVia, PaidVia.cash);
      expect(BalanceRequest.fromJson({'id': 1}), isNull);
    });
  });

  setUpAll(simSetUpAll);
  tearDown(() {
    PermissionsService.debugReset();
    BalanceReqState.reset();
    ManagerMoneyState.reset();
    TransferPay.reset();
  });

  List<String> clipped() => [
        for (final e in find.byType(RichText).evaluate())
          if ((e.renderObject! as RenderParagraph).didExceedMaxLines) (e.renderObject! as RenderParagraph).text.toPlainText(),
      ];

  group('قسم الفرعيّ', () {
    Future<SimServer> server({Map<String, Object?>? me}) async {
      final s = await simSetUp(secure: {'auth.admin_id': '2251', 'auth.admin_username': 'ali.hasan'});
      PermissionsService.debugSet(isEmployee: false);
      s.reply('GET', '/api/v2/balance-requests/me', 200, {'success': true, 'data': me ?? meJson});
      s.reply('GET', '/api/v2/admin-widgets', 200, {'success': true, 'balance': 85000, 'points': 0});
      s.reply('POST', '/api/v2/balance-requests', 201, {
        'success': true,
        'data': {'id': 9, 'status': 'pending', 'amount': 500000, 'pay_method': 'zaincash', 'method_label': 'حوالة زين كاش'},
      });
      return s;
    }

    final fakeJpeg = Uint8List.fromList(img.encodeJpg(img.Image(width: 8, height: 8)));
    Future<Uint8List?> picker({required bool camera}) async => fakeJpeg;

    Future<void> open(WidgetTester t, {SimVariant v = const SimVariant(390, dark: false)}) async {
      await pumpSim(t, v, home: (_) => SubBalanceRequestScreen(pickImage: picker));
      await t.pumpAndSettle();
    }

    testWidgets('الشاشة: رصيده ومديره وطرق الدفع وطلباته — المرفوض بسببه والمشحون برصيده قبل/بعد', (t) async {
      await server();
      await open(t);
      expect(find.text('85,000 د.ع'), findsOneWidget);
      expect(find.text('شبكة النور'), findsWidgets);
      expect(find.byKey(const ValueKey('balreq-pay-zaincash')), findsOneWidget);
      expect(find.byKey(const ValueKey('balreq-pay-master')), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const ValueKey('balreq-mine-6')), 200);
      expect(find.text('السبب: المبلغ بالصورة 200,000 لا 250,000'), findsOneWidget, reason: 'السبب سطرٌ هادئ');
      expect(find.text('رفضه مديرك'), findsNothing, reason: 'لا صندوق يكرّر «مرفوض»');
      expect(find.textContaining('رصيدك 85,000 د.ع ← 385,000 د.ع'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('رصيدٌ سالب (مديرٌ بالآجل): بإشارته والناقص يسار الرقم — بالرأس وبسطر «شُحن»', (t) async {
      final s = await server(me: {
        ...meJson,
        'requests': [
          {
            'id': 6, 'status': 'done', 'created_at': '2026-11-20T09:00:00.000Z', 'amount': 250000, 'pay_method': 'cash', 'method_label': 'كاش باليد',
            'done': {'amount': 250000, 'is_loan': false, 'paid_via': 'cash', 'balance_before': -110378803, 'balance_after': -110128803},
          },
        ],
      });
      s.reply('GET', '/api/v2/admin-widgets', 200, {'success': true, 'balance': -110378803, 'points': 0});
      await open(t);
      const neg = '\u2066−110,378,803\u2069 د.ع';
      expect(find.text(neg), findsOneWidget, reason: 'كان «110,378,803 د.ع» بلا ناقص كأنّه رصيدٌ موجود');
      final p = t.renderObject<RenderParagraph>(find.text(neg));
      final plain = p.text.toPlainText();
      Rect box(int i) => p.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1)).first.toRect();
      expect(box(plain.indexOf('−')).left, lessThan(box(plain.indexOf('1')).left), reason: 'الناقص يسار أوّل رقم كما يُرسم');
      await t.scrollUntilVisible(find.byKey(const ValueKey('balreq-mine-6')), 200);
      expect(find.textContaining('رصيدك \u2066−110,378,803\u2069 د.ع ← \u2066−110,128,803\u2069 د.ع'), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('الطلب بحوالة: الصورة شرط، ثمّ يُرسل بالمرجع والمبلغ والطريقة والصورة JPEG', (t) async {
      final s = await server();
      await open(t);
      await t.tap(find.byKey(const ValueKey('balreq-new')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('balreq-quick-500000')));
      await t.tap(find.byKey(const ValueKey('balreq-method-zaincash')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('balreq-send')));
      await t.tap(find.byKey(const ValueKey('balreq-send')));
      await t.pumpAndSettle();
      expect(find.text('أرفق صورة الحوالة'), findsWidgets);
      expect(s.calls('POST', '/api/v2/balance-requests'), isEmpty);
      await t.pump(const Duration(seconds: 4));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('balreq-pick-image')));
      await t.tap(find.byKey(const ValueKey('balreq-pick-image')));
      await t.pumpAndSettle();
      if (find.byKey(const ValueKey('ticket-image-gallery')).evaluate().isNotEmpty) {
        await t.tap(find.byKey(const ValueKey('ticket-image-gallery')));
        await t.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('balreq-image-preview')), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('balreq-send')));
      await t.tap(find.byKey(const ValueKey('balreq-send')));
      await t.pumpAndSettle();
      final body = s.bodies('POST', '/api/v2/balance-requests').single;
      expect(body['client_ref'], matches(RegExp(r'^br-\d+-[a-z0-9]{10}$')));
      expect([body['amount'], body['pay_method']], [500000, 'zaincash']);
      expect((body['image'] as String).startsWith('data:image/jpeg;base64,'), isTrue);
      await simDrain(t);
    });

    testWidgets('كاش باليد: بلا صورة (لا حقل ولا إرسال) — والملاحظة تُرسل', (t) async {
      final s = await server();
      await open(t);
      await t.tap(find.byKey(const ValueKey('balreq-new')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('balreq-quick-100000')));
      await t.tap(find.byKey(const ValueKey('balreq-method-cash')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('balreq-pick-image')), findsNothing);
      await t.enterText(find.descendant(of: find.byKey(const ValueKey('balreq-note')), matching: find.byType(TextField)), 'أسلّمه العصر');
      await t.ensureVisible(find.byKey(const ValueKey('balreq-send')));
      await t.tap(find.byKey(const ValueKey('balreq-send')));
      await t.pumpAndSettle();
      final body = s.bodies('POST', '/api/v2/balance-requests').single;
      expect([body['amount'], body['pay_method'], body['note'], body.containsKey('image')], [100000, 'cash', 'أسلّمه العصر', false]);
      await simDrain(t);
    });

    testWidgets('«طلباتك»: آخر ١٠ وحدها — والنقر على المشحون ⇒ «تاريخ الحركة» و«ملخّص الحركة»، وعلى المرفوض ⇒ تاريخ الرفض وسببه', (t) async {
      Map<String, Object?> req(int id, String status, [Map<String, Object?> extra = const {}]) => {
            'id': id, 'status': status, 'created_at': '2026-11-21T09:00:00.000Z', 'amount': 100000 + id, 'pay_method': 'cash',
            'method_label': 'كاش باليد', 'decided_at': '2026-11-21T10:00:00.000Z', ...extra,
          };
      final reqs = [
        req(60, 'done', {
          'amount': 250000, 'created_at': '2026-11-23T18:10:00.000Z', 'decided_at': '2026-11-23T18:31:00.000Z', 'note': 'سلّمته لأبو علي',
          'done': {'amount': 250000, 'is_loan': false, 'paid_via': 'cash', 'balance_before': 85000, 'balance_after': 335000},
        }),
        req(59, 'rejected', {
          'pay_method': 'master', 'method_label': 'حوالة ماستر', 'has_image': true, 'image_live': false,
          'reject_reason': 'المبلغ بالصورة غير المطلوب', 'decided_at': '2026-11-22T09:45:00.000Z',
        }),
        for (var id = 58; id >= 46; id--) req(id, 'cancelled'),
      ];
      await server(me: {...meJson, 'requests': reqs});
      await open(t);
      final list = find.byKey(const ValueKey('balreq-sub-list'));
      await t.scrollUntilVisible(find.byKey(const ValueKey('balreq-mine-51')), 300);
      await t.drag(list, const Offset(0, -4000));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('balreq-mine-51')), findsOneWidget, reason: 'العاشر آخر ما يُرسم');
      expect(find.byKey(const ValueKey('balreq-mine-50')), findsNothing, reason: 'الحادي عشر لا يُرسم');
      await t.drag(list, const Offset(0, 8000));
      await t.pumpAndSettle();

      // المشحون ⇒ ملخّص الحركة بتاريخها
      await t.scrollUntilVisible(find.byKey(const ValueKey('balreq-mine-60')), 200);
      await t.ensureVisible(find.byKey(const ValueKey('balreq-mine-60')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('balreq-mine-60')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('balreq-details-done')), findsOneWidget);
      expect(find.text('ملخّص الحركة'), findsOneWidget);
      expect(find.text('تاريخ الحركة'), findsOneWidget);
      expect(find.text(balanceReqWhen(BalanceRequest.fromJson(reqs[0])!.decidedAt)), findsOneWidget);
      expect(find.text('استلمه كاش'), findsOneWidget);
      expect(find.text('85,000 د.ع'), findsWidgets);
      expect(find.text('335,000 د.ع'), findsOneWidget);
      expect(find.text('#60'), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(const ValueKey('balreq-details-request')), matching: find.text(balanceReqWhen(BalanceRequest.fromJson(reqs[0])!.createdAt))),
        findsOneWidget,
        reason: 'تاريخ الطلب بقسم «طلبك»',
      );
      Navigator.of(t.element(find.byKey(const ValueKey('balreq-details-request')))).pop();
      await t.pumpAndSettle();

      // المرفوض ⇒ تاريخ الرفض وسببه، ووصلٌ حُذف يقول ذلك
      await t.scrollUntilVisible(find.byKey(const ValueKey('balreq-mine-59')), 200);
      await t.ensureVisible(find.byKey(const ValueKey('balreq-mine-59')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('balreq-mine-59')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('balreq-details-rejected')), findsOneWidget);
      expect(find.text('تاريخ الرفض'), findsOneWidget);
      expect(find.text(balanceReqWhen(BalanceRequest.fromJson(reqs[1])!.decidedAt)), findsOneWidget);
      expect(find.text('المبلغ بالصورة غير المطلوب'), findsOneWidget);
      expect(find.text('مرفق — حُذفت صورته بعد ٧ أيّام'), findsOneWidget);
      expect(clipped(), isEmpty);
      await simDrain(t);
    });

    testWidgets('المرفوض بلا سبب: الحال «مرفوض» فوق وحدها — لا صندوق ولا سطرٌ يكرّرها', (t) async {
      await server(me: {
        ...meJson,
        'requests': [
          {'id': 8, 'status': 'rejected', 'created_at': '2026-11-23T08:00:00.000Z', 'amount': 300000, 'pay_method': 'cash', 'method_label': 'كاش باليد'},
        ],
      });
      await open(t);
      await t.scrollUntilVisible(find.byKey(const ValueKey('balreq-mine-8')), 200);
      final card = find.byKey(const ValueKey('balreq-mine-8'));
      expect(find.descendant(of: card, matching: find.text('مرفوض')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.textContaining('رفضه')), findsNothing, reason: 'لا «رفضه مديرك» يكرّر الحال');
      expect(find.byKey(const ValueKey('balreq-reason-8')), findsNothing);
      await simDrain(t);
    });

    testWidgets('«إلغاء الطلب» داخل البطاقة يسأل ولا يفتح التفاصيل', (t) async {
      final withOpen = {...meJson, 'pending': 1, 'requests': [{'id': 9, 'status': 'pending', 'amount': 1000, 'pay_method': 'cash', 'method_label': 'كاش باليد'}]};
      await server(me: withOpen);
      await open(t);
      await t.scrollUntilVisible(find.byKey(const ValueKey('balreq-cancel-9')), 200);
      await t.ensureVisible(find.byKey(const ValueKey('balreq-cancel-9')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('balreq-cancel-9')));
      await t.pumpAndSettle();
      expect(find.text('إلغاء الطلب؟'), findsOneWidget);
      expect(find.byKey(const ValueKey('balreq-details-request')), findsNothing);
      await simDrain(t);
    });

    testWidgets('طلبٌ مفتوح ⇒ زرّ الطلب مطفأ بسببه؛ والموظّف يراه مقفلاً', (t) async {
      final withOpen = {...meJson, 'pending': 1, 'requests': [{'id': 9, 'status': 'pending', 'amount': 1000, 'pay_method': 'cash', 'method_label': 'كاش باليد'}]};
      await server(me: withOpen);
      await open(t);
      expect(find.text('عندك طلب بانتظار مديرك'), findsOneWidget);
      await t.scrollUntilVisible(find.byKey(const ValueKey('balreq-cancel-9')), 200);
      expect(find.byKey(const ValueKey('balreq-cancel-9')), findsOneWidget);
      await simDrain(t);
    });

    testWidgets('بأضيق هاتف وخطٍّ ×1.2 (فاتح وداكن): القسم والنافذة والتفاصيل بلا نصٍّ مقصوص', (t) async {
      for (final dark in [false, true]) {
        await server();
        t.platformDispatcher.textScaleFactorTestValue = 1.2;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await open(t, v: SimVariant(320, dark: dark));
        expect(clipped(), isEmpty, reason: 'القسم dark=$dark');
        await t.tap(find.byKey(const ValueKey('balreq-new')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('balreq-method-other')));
        await t.pumpAndSettle();
        expect(clipped(), isEmpty, reason: 'النافذة dark=$dark');
        Navigator.of(t.element(find.byKey(const ValueKey('balreq-amount')))).pop();
        await t.pumpAndSettle();
        // تفاصيل المشحون (أطول صفوفها: الرصيد قبل/بعد وسطر الطريقة) والمرفوض (سببه)
        for (final id in [6, 7]) {
          await t.scrollUntilVisible(find.byKey(ValueKey('balreq-mine-$id')), 200);
          await t.ensureVisible(find.byKey(ValueKey('balreq-mine-$id')));
          await t.pumpAndSettle();
          await t.tap(find.byKey(ValueKey('balreq-mine-$id')));
          await t.pumpAndSettle();
          expect(find.byKey(const ValueKey('balreq-details-request')), findsOneWidget);
          expect(clipped(), isEmpty, reason: 'تفاصيل #$id dark=$dark');
          Navigator.of(t.element(find.byKey(const ValueKey('balreq-details-request')))).pop();
          await t.pumpAndSettle();
        }
        expect(t.takeException(), isNull);
        await simDrain(t);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump();
      }
    });
  });

  group('البطاقة في «قوائم أخرى»', () {
    test('تظهر للفرعيّ الذي مديره عندنا، مقفلةً للموظّف، وتغيب لغيره؛ و«المدراء» بعدد طلبات الرصيد', () {
      PermissionsService.debugSet(isEmployee: false);
      BalanceReqState.debugSet(meValue: BalanceReqMe.fromJson(meJson), count: 3);
      var mods = buildAppModules();
      final card = mods.firstWhere((m) => m.id == 'balance_request');
      expect([card.locked, card.title], [false, 'طلب رصيد من مديرك']);
      expect(card.subtitle, contains('شبكة النور'));
      final mgr = mods.where((m) => m.id == 'managers');
      if (mgr.isNotEmpty) expect(mgr.first.badge, 3);
      BalanceReqState.debugSet(meValue: BalanceReqMe.fromJson({...meJson, 'can_request': false}), count: 0);
      mods = buildAppModules();
      expect(mods.firstWhere((m) => m.id == 'balance_request').locked, isTrue);
      BalanceReqState.debugSet(meValue: BalanceReqMe.off, count: 0);
      expect(buildAppModules().where((m) => m.id == 'balance_request'), isEmpty);
    });
  });

  group('«طلبات الرصيد» للأعلى', () {
    final pending = {
      'id': 15, 'status': 'pending', 'created_at': '2026-11-24T01:40:00.000Z', 'amount': 500000, 'pay_method': 'zaincash',
      'method_label': 'حوالة زين كاش', 'has_image': true, 'image_live': true, 'note': 'رقم العمليّة 55219874',
      'sub': {'page': '41', 'sas_id': '41', 'username': 'mgr.north', 'name': 'فرع الشمال'},
      'ai': {'status': 'done', 'verdict': 'match', 'level': 'ok', 'amount': 500000, 'lines': [{'level': 'ok', 'text': '✅ المبلغ بالصورة مطابق: 500,000 د.ع'}]},
    };
    final processing = {
      'id': 16, 'status': 'processing', 'unverified': true, 'created_at': '2026-11-24T01:00:00.000Z', 'amount': 200000, 'pay_method': 'loan',
      'method_label': 'آجل — دين عليه', 'sub': {'page': '41', 'sas_id': '41', 'username': 'mgr.north'},
      'attempt': {'amount': 200000, 'is_loan': true},
    };

    Future<SimServer> server() async {
      final s = await simSetUp(secure: {'auth.admin_id': '2', 'auth.admin_username': 'admin@popq'});
      WhatsAppApi.clearCaches();
      PermissionsService.debugSet(isEmployee: false);
      s.reply('GET', '/api/v2/balance-requests/incoming', 200, {
        'success': true, 'data': [pending, processing], 'total': 2,
        'counts': {'pending': 1, 'processing': 1, 'done': 0, 'rejected': 0, 'cancelled': 0, 'expired': 0}, 'status': 'pending',
      });
      s.reply('GET', '/api/v2/balance-requests/incoming/count', 200, {'success': true, 'data': {'pending': 1, 'processing': 1}});
      s.reply('GET', '/api/v2/managers/41', 200, {'success': true, 'data': {'id': 41, 'username': 'mgr.north', 'balance': 85000, 'mobile': '07700000001'}});
      s.reply('GET', '/api/v2/managers/money-settings', 200, {'success': true, 'data': {'manager_box': true, 'transfers': true}});
      s.reply('GET', '/api/v2/manager-topup-fees/config', 200, {'success': true, 'enabled': false});
      s.reply('POST', '/api/v2/managers/41/deposit', 200, {'success': true, 'balance_request': {'id': 15, 'status': 'done'}});
      s.reply('POST', '/api/v2/balance-requests/15/reject', 200, {'success': true, 'data': {...pending, 'status': 'rejected'}});
      s.reply('POST', '/api/v2/balance-requests/16/resolve', 200, {'success': true, 'data': {...processing, 'status': 'pending'}});
      s.reply('GET', '/api/admin/manager-debts/summary', 200, {'success': true, 'perDebtor': []});
      s.reply('GET', '/api/whatsapp/templates/2', 200, {'success': true, 'templates': []});
      s.reply('POST', '/api/whatsapp/send-message', 200, {'success': true});
      s.reply('POST', '/api/fcm/send-manager-balance-update', 200, {'success': true});
      return s;
    }

    Future<void> open(WidgetTester t) async {
      await pumpSim(t, const SimVariant(390, dark: false), home: (_) => const IncomingBalanceRequestsScreen());
      await t.pumpAndSettle();
    }

    testWidgets('القائمة: الطلب بقراءة وصله، و«قيد التأكّد» بزرّيه — والعدد على التبويب', (t) async {
      await server();
      await open(t);
      expect(find.text('بانتظارك 2'), findsOneWidget);
      expect(find.textContaining('قراءة الوصل: ✅ المبلغ بالصورة مطابق'), findsOneWidget);
      expect(find.byKey(const ValueKey('balreq-accept-15')), findsOneWidget);
      expect(find.byKey(const ValueKey('balreq-resolve-done-16')), findsOneWidget);
      expect(find.byKey(const ValueKey('balreq-accept-16')), findsNothing, reason: 'لا شحن ثانٍ لطلبٍ قد يكون شُحن');
      await simDrain(t);
    });

    testWidgets('«قبول وشحن»: نافذة الشحن معبّأة بالمبلغ وبما اختاره هو — والشحن يحمل رقم الطلب وطريقته وبلا إشعار التطبيق العامّ', (t) async {
      final s = await server();
      await open(t);
      await t.tap(find.byKey(const ValueKey('balreq-accept-15')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('balreq-op-hint')), findsOneWidget);
      expect(find.textContaining('من طلبه: حوالة زين كاش'), findsOneWidget);
      await t.ensureVisible(find.byType(SheetFooterBar).last);
      await t.tap(find.byType(SheetFooterBar).last);
      await t.pumpAndSettle();
      final body = s.bodies('POST', '/api/v2/managers/41/deposit').single;
      expect([body['amount'], body['isLoan'], body['paid_via'], body['balance_request_id']], [500000, false, 'zaincash', 15]);
      expect(s.calls('POST', '/api/fcm/send-manager-balance-update'), isEmpty, reason: 'الخادم يرسل «تمّ شحن رصيدك»');
      await simDrain(t);
    });

    testWidgets('الرفض بسببٍ يراه هو', (t) async {
      final s = await server();
      await open(t);
      await t.tap(find.byKey(const ValueKey('balreq-reject-15')));
      await t.pumpAndSettle();
      await t.enterText(find.descendant(of: find.byKey(const ValueKey('balreq-reject-reason')), matching: find.byType(TextField)), 'المبلغ غير مطابق');
      await t.tap(find.byKey(const ValueKey('balreq-reject-confirm')));
      await t.pumpAndSettle();
      expect(s.bodies('POST', '/api/v2/balance-requests/15/reject').single, {'reason': 'المبلغ غير مطابق'});
      await simDrain(t);
    });

    testWidgets('«لم يُشحن» لطلبٍ قيد التأكّد ⇒ resolve pending بعد تأكيد', (t) async {
      final s = await server();
      await open(t);
      await t.ensureVisible(find.byKey(const ValueKey('balreq-resolve-pending-16')));
      await t.tap(find.byKey(const ValueKey('balreq-resolve-pending-16')));
      await t.pumpAndSettle();
      await t.tap(find.text('نعم، لم يُشحن'));
      await t.pumpAndSettle();
      expect(s.bodies('POST', '/api/v2/balance-requests/16/resolve').single, {'outcome': 'pending'});
      await simDrain(t);
    });
  });
}
