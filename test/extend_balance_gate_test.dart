import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/extend_sheet.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'sim_el/sim_harness.dart';

/// المالك ١٦ نوفمبر (لقطة وكيل من ورقة «تمديد المشترك»: «رصيد المدير 110,378,803 د.ع»، المبلغ المطلوب 1,000، والزرّ معطّلٌ
/// «الرصيد غير كافٍ»): «ليش يكول هيج الرصيد موجود ويكله الرصيد غير كافي؟».
///
/// السبب: رصيد المدير في الساس **سالب** (‎−110,378,803 — يعمل بالآجل أو أدمن رئيسيّ)، والورقة تعرضه بلا ناقص (`formatIQD` يُسقط
/// الإشارة) ثمّ تمنع التمديد لأنّه «أقلّ من السعر». الموقع لا يمنع («لا منع بالرصيد — الساس يحكم») وورقة التفعيل كذلك.
/// الآن: الرصيد بإشارته، والتمديد يُرسل والساس يقرّر، وتنبيهٌ ظاهر — ورفض الساس يصل برسالته.
const _idx = '221';
const _optsPath = '/api/v2/subscribers/$_idx/extension-options';
const _extendPath = '/api/v2/subscribers/$_idx/extend';
const _warn = ValueKey('extend-balance-short');

Subscriber _sub() => Subscriber.fromJson({
      'idx': _idx,
      'username': 'user221',
      'firstname': 'شاكر',
      'lastname': 'حسن',
      'phone': '07701234567',
      'profile_id': 5,
      'profile_name': '20M',
      'expiration': '2026-11-10 18:00:00',
      'remaining_days': -6,
    });

/// ردّ الخادم كما يبنيه من `/user/extensionData` و`/allowedExtensions`: الرصيد رقمٌ بإشارته كما يقوله الساس.
Map<String, dynamic> _opts({required num balance, num points = 0, num price = 1000, num needPoints = 1}) => {
      'success': true,
      'data': {
        'idx': _idx,
        'current_profile_id': 5,
        'current_profile_name': '20M',
        'manager_balance': balance,
        'reward_points_balance': points,
        'packages': [
          {'id': 9, 'name': 'days', 'price': price, 'reward_points_required': needPoints, 'duration': 1},
        ],
      },
    };

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '1', 'auth.admin_username': 'admin'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
  });

  tearDown(PermissionsService.debugReset);

  Future<void> open(WidgetTester t, {SimVariant v = const SimVariant(390, dark: false)}) async {
    await pumpSim(t, v, home: (_) => simLauncher((ctx) => showExtendSheet(ctx, _sub())));
    await simOpen(t);
  }

  /// نصّ قيمة صفّ «رصيد المدير» ولونه كما رُسما.
  Text balanceValue(WidgetTester t) => t.widget<Text>(find.textContaining('110,378,803'));

  for (final v in const [SimVariant(390, dark: false), SimVariant(320, dark: true)]) {
    testWidgets('الحالة المبلَّغة @${v.tag}: الرصيد بالسالب يُعرض بناقصه، والزرّ «تمديد الآن» يعمل، والتنبيه ظاهر', (t) async {
      server.reply('GET', _optsPath, 200, _opts(balance: -110378803));
      server.reply('POST', _extendPath, 200, {'success': true, 'message': 'تم'});
      await open(t, v: v);

      // كان «110,378,803 د.ع» كأنّه رصيدٌ موجود
      final shown = balanceValue(t);
      expect(shown.data, startsWith('−110,378,803'), reason: 'الناقص قبل الرقم (النصّ اتّجاهه LTR)');
      expect(shown.textDirection, TextDirection.ltr);
      expect(shown.style?.color, AppColors.error);

      expect(find.text('sheets.insufficient_balance'.tr()), findsNothing, reason: 'كان الزرّ «الرصيد غير كافٍ» معطّلاً');
      expect(find.byKey(_warn), findsOneWidget);
      expect(t.widget<Text>(find.byKey(_warn)).data, contains('بالسالب'));
      expect(find.text('تمديد الآن'), findsOneWidget);

      await t.ensureVisible(find.text('تمديد الآن'));
      await t.tap(find.text('تمديد الآن'));
      await t.pumpAndSettle();
      final b = server.bodies('POST', _extendPath).single;
      expect([b['profile_id'], b['method']], ['9', 'balance'], reason: 'الطلب يخرج — الساس يقرّر');
      await simDrain(t);
    });
  }

  testWidgets('الساس يرفض فعلاً ⇒ رسالته هو تظهر، والورقة تبقى، ولا طلب ثانٍ من نفسه', (t) async {
    server.reply('GET', _optsPath, 200, _opts(balance: -110378803));
    server.reply('POST', _extendPath, 422, {'success': false, 'message': 'رصيد المدير غير كافٍ لإتمام العمليّة'});
    await open(t);
    await t.ensureVisible(find.text('تمديد الآن'));
    await t.tap(find.text('تمديد الآن'));
    await t.pumpAndSettle();
    expect(find.text('رصيد المدير غير كافٍ لإتمام العمليّة'), findsOneWidget);
    expect(find.text('sheets.extend_subscriber'.tr()), findsOneWidget, reason: 'الورقة لم تُغلق');
    expect(server.calls('POST', _extendPath), hasLength(1));
    await simDrain(t);
  });

  testWidgets('رصيدٌ موجب أقلّ من المبلغ (500 < 1,000): لا منع — تنبيهٌ بلا «بالسالب»، والطلب يخرج', (t) async {
    server.reply('GET', _optsPath, 200, _opts(balance: 500));
    server.reply('POST', _extendPath, 200, {'success': true, 'message': 'تم'});
    await open(t);
    expect(find.byKey(_warn), findsOneWidget);
    final w = t.widget<Text>(find.byKey(_warn)).data!;
    expect(w, contains('أقلّ من المبلغ'));
    expect(w, isNot(contains('بالسالب')));
    final shown = t.widget<Text>(find.textContaining('500 '));
    expect(shown.data, isNot(contains('−')));
    await t.ensureVisible(find.text('تمديد الآن'));
    await t.tap(find.text('تمديد الآن'));
    await t.pumpAndSettle();
    expect(server.calls('POST', _extendPath), hasLength(1));
    await simDrain(t);
  });

  testWidgets('رصيدٌ كافٍ: لا تنبيه ولا ناقص ولا لون خطأ — كما كان', (t) async {
    server.reply('GET', _optsPath, 200, _opts(balance: 110378803));
    await open(t);
    expect(find.byKey(_warn), findsNothing);
    final shown = balanceValue(t);
    expect(shown.data, startsWith('110,378,803'));
    expect(shown.style?.color, isNot(AppColors.error));
    expect(find.text('تمديد الآن'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('النقاط لم تتغيّر: نقاطٌ ناقصة ⇒ «النقاط غير كافية» معطّلاً، ولا تنبيه رصيد', (t) async {
    server.reply('GET', _optsPath, 200, _opts(balance: -110378803, points: 0, needPoints: 1));
    await open(t);
    await t.ensureVisible(find.text('النقاط (1)'));
    await t.tap(find.text('النقاط (1)'));
    await t.pumpAndSettle();
    expect(find.text('sheets.insufficient_points'.tr()), findsOneWidget);
    expect(find.byKey(_warn), findsNothing, reason: 'التنبيه للدفع بالرصيد وحده');
    await t.tap(find.text('sheets.insufficient_points'.tr()), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(server.calls('POST', _extendPath), isEmpty);
    await simDrain(t);
  });

  // ── ورقة التفعيل: الصفّ نفسه «رصيد المدير» (هي لا تمنع بالرصيد أصلاً) ─────────────────────────────
  group('ورقة التفعيل — رصيد المدير بإشارته', () {
    Future<void> openActivate(WidgetTester t, num balance) async {
      server.reply('GET', '/api/v2/subscribers/$_idx/activation-data', 200, {
        'success': true,
        'data': {
          'user_price': 35000,
          'price_after_discount': 35000,
          'profile_name': '20M',
          'profile_duration': '30',
          'current_balance': 0,
          'manager_balance': balance,
        },
      });
      await pumpSim(t, const SimVariant(390, dark: false), home: (_) => simLauncher((ctx) => showActivateSheet(ctx, _sub())));
      await simOpen(t);
    }

    testWidgets('رصيدٌ سالب ⇒ «−110,378,803» بلون الخطأ (كان «110,378,803» كأنّه موجود)', (t) async {
      await openActivate(t, -110378803);
      final shown = balanceValue(t);
      expect(shown.data, startsWith('−110,378,803'));
      expect(shown.style?.color, AppColors.error);
      await simDrain(t);
    });

    testWidgets('رصيدٌ موجب ⇒ كما كان', (t) async {
      await openActivate(t, 110378803);
      final shown = balanceValue(t);
      expect(shown.data, startsWith('110,378,803'));
      expect(shown.style?.color, isNot(AppColors.error));
      await simDrain(t);
    });
  });

  testWidgets('السعر صفر (بلا «دايني» ولا مدّة): «السعر غير متوفر» معطّلاً — لا يُرسل شيء ولو كان الرصيد لا يمنع', (t) async {
    server.reply('GET', _optsPath, 200, _opts(balance: -5000, price: 0, needPoints: 0));
    await open(t);
    expect(find.text('sheets.no_price'.tr()), findsOneWidget);
    expect(find.byKey(_warn), findsNothing);
    await t.tap(find.text('sheets.no_price'.tr()), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(server.calls('POST', _extendPath), isEmpty);
    await simDrain(t);
  });
}
