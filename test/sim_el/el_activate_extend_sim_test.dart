import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/core/widgets/design_sheet.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/extend_sheet.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/services/subscriber_events.dart';
import 'package:rad_mysvcs/widgets/package_picker_field.dart';

import 'sim_harness.dart';

/// محاكاة شيتَي التجديد والتمديد بوضع ايرث لنك (`provider: 'earthlink'` في
/// ردّ activation-data / extension-options): رسمٌ وتفاعلٌ أساسيّ أمام خادمٍ
/// وهميّ — مبدّل الباقة، رصيد أونلاين | كارت، نقدي/دين/جزئي، قفل الباقة
/// للفعّال، والنتائج الأساسيّة (نجاح · مهلة · حارس التكرار).
const _activate = 'el_activate';
const _extend = 'el_extend';
const _activatePath = '/api/v2/subscribers/55/activate';
const _extendPath = '/api/v2/subscribers/55/extend';

Subscriber _sub({bool? canChange, String? note}) => Subscriber.fromJson({
      'idx': '55',
      'username': 'ali1@alnoor-net',
      'firstname': 'علي',
      'lastname': 'حسن الموسوي',
      'profile_id': 7,
      'profile_name': 'Economy',
      'expiration': '2026-10-12 10:00:00',
      if (canChange != null) 'can_change_package': canChange,
      if (note != null) 'package_change_note': note,
    });

/// باقات ايرث لنك كما يرسلها الخادم — أكثر من ستّ (فيظهر البحث في القائمة).
const _elPackages = [
  {'id': 7, 'name': 'Economy', 'price': 35000, 'cost': 20000},
  {'id': 8, 'name': 'Standard', 'price': 45000, 'cost': 28000},
  {'id': 9, 'name': 'Plus', 'price': 55000, 'cost': 34000},
  {'id': 10, 'name': 'Turbo', 'price': 65000, 'cost': 41000},
  {'id': 11, 'name': 'More', 'price': 80000, 'cost': 52000},
  {'id': 12, 'name': 'Ta3leem 50,000 Plus 3 Months', 'price': 150000, 'cost': 93000},
  {'id': 13, 'name': 'Business Pro 100M', 'price': 250000, 'cost': 180000},
];

const _lockNote =
    'تتغيّر الباقة للمنتهي أو لمن بقي له يومٌ فأقلّ — هذا المشترك ما زال فعّالاً';

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  /// activation-data بشكل خادم Pro لايرث لنك (earthlinkRoutes.activationData).
  void activationData({bool? changeAllowed = true, String? changeNote}) {
    server.reply('GET', '/api/v2/subscribers/55/activation-data', 200, {
      'success': true,
      'data': {
        'idx': '55',
        'username': 'ali1@alnoor-net',
        'provider': 'earthlink',
        'profile_id': 7,
        'profile_name': 'Economy',
        'profile_duration': null,
        'units': null,
        'user_price': 35000,
        'base_price': 35000,
        'discount_amount': 5000,
        'price_after_discount': 30000,
        'price_source': 'normal',
        'custom_price': null,
        'needs_repricing': false,
        'manager_cost': 20000,
        'current_balance': -15000,
        'manager_balance': 250000,
        'reward_points': 0,
        'expiration': '2026-10-12 10:00:00',
        'activation_methods': {'credit': true, 'deposit': true, 'card': true},
        'cards': {
          'enabled': false,
          'profile_id': 7,
          'profile_name': 'Economy',
          'available': null,
        },
        'packages': _elPackages,
        if (changeAllowed != null) 'package_change_allowed': changeAllowed,
        if (changeNote != null) 'package_change_note': changeNote,
      },
    });
  }

  /// extension-options بشكل الخادم: الباقة الحاليّة وحدها، و«النقاط» = عدّاد
  /// التجارب الباقي، و`reward_points_required: 1` (earthlinkRoutes.extensionOptions).
  void extensionOptions({num points = 3, num required = 1, bool two = false}) {
    server.reply('GET', '/api/v2/subscribers/55/extension-options', 200, {
      'success': true,
      'data': {
        'provider': 'earthlink',
        'current_profile_id': 7,
        'current_profile_name': 'Economy',
        'manager_balance': 0,
        'reward_points_balance': points,
        'packages': [
          {
            'id': 7,
            'name': 'Economy',
            'price': 0,
            'reward_points_required': required,
            'duration': '٢٤ ساعة',
          },
          if (two)
            {
              'id': 8,
              'name': 'Standard',
              'price': 0,
              'reward_points_required': required,
              'duration': '٢٤ ساعة',
            },
        ],
      },
    });
  }

  setUp(() async {
    server = await simSetUp();
    ProviderService.debugSet('earthlink');
    CardsState.reset();
    activationData();
    extensionOptions();
  });

  Future<void> openActivate(WidgetTester t, SimVariant v, {Subscriber? sub}) async {
    await pumpSim(t, v,
        home: (_) => simLauncher((c) => showActivateSheet(c, sub ?? _sub())));
    await simOpen(t);
    expect(find.text('تجديد اشتراك'), findsOneWidget);
  }

  Future<void> openExtend(WidgetTester t, SimVariant v, {Subscriber? sub}) async {
    await pumpSim(t, v,
        home: (_) => simLauncher((c) => showExtendSheet(c, sub ?? _sub())));
    await simOpen(t);
    expect(find.text('تمديد المشترك'), findsOneWidget);
  }

  Future<void> reveal(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester t, String s) async {
    await reveal(t, find.text(s));
    await t.tap(find.text(s));
    await t.pumpAndSettle();
  }

  /// حقل الباقة نفسه (اسم الباقة يتكرّر في بطاقة الباقة وصفّ «الحاليّة»).
  Future<void> openPicker(WidgetTester t) async {
    await reveal(t, find.byType(PackagePickerField));
    await t.tap(find.byType(PackagePickerField));
    await t.pumpAndSettle();
  }

  bool footerEnabled(WidgetTester t, String label) {
    final ink = t.widget<InkWell>(find
        .ancestor(of: find.text(label), matching: find.byType(InkWell))
        .first);
    return ink.onTap != null;
  }

  Finder field(String hint) => find.widgetWithText(TextField, hint);

  // ═══════════════════════════ التجديد ═══════════════════════════

  simCase(_activate, 'deposit_default', (t, v) async {
    await openActivate(t, v);
    expect(find.text('طريقة الدفع لايرث لنك'), findsOneWidget);
    expect(find.text('رصيد أونلاين'), findsOneWidget);
    expect(find.text('30,000 د.ع'), findsOneWidget, reason: 'بعد الخصم');
    expect(find.text('35,000'), findsOneWidget, reason: 'الأصليّ مشطوباً');
    expect(find.text('كلفة الباقة المختارة'), findsOneWidget);
    expect(footerEnabled(t, 'تجديد الآن'), isFalse, reason: 'بلا باسورد إيداع');
    await simCheck(t, v, _activate, 'deposit_default');
    await t.enterText(field('باسورد الإيداع'), 'dep-pass');
    await t.pumpAndSettle();
    expect(footerEnabled(t, 'تجديد الآن'), isTrue);
    await reveal(t, find.text('طريقة الدفع لايرث لنك'));
    await simCheck(t, v, _activate, 'deposit_filled');
  });

  simCase(_activate, 'card_method', (t, v) async {
    await openActivate(t, v);
    await tapText(t, 'كارت');
    expect(field('رقم الكارت'), findsOneWidget);
    expect(field('Pin'), findsOneWidget);
    expect(field('باسورد الإيداع'), findsNothing);
    await t.enterText(field('رقم الكارت'), '4400112233');
    await t.enterText(field('Pin'), '9081');
    await t.pumpAndSettle();
    expect(footerEnabled(t, 'تجديد الآن'), isTrue);
    await reveal(t, field('Pin'));
    await simCheck(t, v, _activate, 'card_method');
  });

  simCase(_activate, 'package_picker', (t, v) async {
    await openActivate(t, v);
    await openPicker(t);
    // ورقة الباقات فوق الشيت: البحث (أكثر من ستّ) و«الحاليّة».
    expect(find.text('اختر الباقة'), findsWidgets);
    await simCheck(t, v, _activate, 'package_picker');
    await t.tap(find.textContaining('Standard').last);
    await t.pumpAndSettle();
    expect(find.text('40,000 د.ع'), findsOneWidget,
        reason: 'سعر Standard ناقص الخصم');
    expect(find.text('45,000'), findsOneWidget, reason: 'الأصليّ مشطوباً');
    await simCheck(t, v, _activate, 'package_changed');
  });

  simCase(_activate, 'package_locked', (t, v) async {
    activationData(changeAllowed: false, changeNote: _lockNote);
    await openActivate(t, v);
    expect(find.text(_lockNote), findsOneWidget);
    await reveal(t, find.text(_lockNote));
    await simCheck(t, v, _activate, 'package_locked');
    // الحقل لا يُفتح.
    await t.tap(find.byType(PackagePickerField));
    await t.pumpAndSettle();
    expect(find.text('اختر الباقة'), findsNothing);
  });

  simCase(_activate, 'partial', (t, v) async {
    await openActivate(t, v);
    await tapText(t, 'جزئي');
    await tapText(t, '10,000');
    expect(find.text('الدين بعد التفعيل'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(SheetResultBanner),
            matching: find.text('35,000 د.ع')),
        findsOneWidget,
        reason: '−15,000 − 30,000 + 10,000');
    await reveal(t, find.text('الدين بعد التفعيل'));
    await simCheck(t, v, _activate, 'partial');
  });

  simCase(_activate, 'submit_success', (t, v) async {
    server.reply('POST', _activatePath, 200, {'success': true});
    await openActivate(t, v);
    await t.enterText(field('باسورد الإيداع'), 'dep-pass');
    await t.pumpAndSettle();
    final before = SubscriberEvents.dataChanged.value;
    await t.tap(find.text('تجديد الآن'));
    await t.pumpAndSettle();
    final body = server.bodies('POST', _activatePath).single;
    expect(body['method'], 'deposit');
    expect(body['depositPassword'], 'dep-pass');
    expect(body['profile_id'], 7);
    expect(body['paymentType'], 'non-cash');
    expect((body['activationData'] as Map)['base_price'], 35000);
    expect(find.text('تم التجديد بنجاح'), findsOneWidget);
    expect(find.text('طريقة الدفع لايرث لنك'), findsNothing, reason: 'أُغلق');
    expect(SubscriberEvents.dataChanged.value, before + 1);
    await simCheck(t, v, _activate, 'submit_success');
    await simDrain(t);
  });

  simCase(_activate, 'submit_success_debt_not_recorded', (t, v) async {
    // الخادم يُبلغ فشل قيد الدين في دفترنا بعد تفعيلٍ تمّ (earthlinkRoutes.activate).
    const msg = 'تمّ التفعيل لكن لم يُسجَّل الدين في دفترنا — سجّله يدويّاً';
    server.reply('POST', _activatePath, 200, {
      'success': true,
      'data': {'new_balance': -15000},
      'debt_write': {'ok': false, 'message': msg},
    });
    await openActivate(t, v);
    await t.enterText(field('باسورد الإيداع'), 'dep-pass');
    await t.pumpAndSettle();
    await t.tap(find.text('تجديد الآن'));
    await t.pumpAndSettle();
    expect(find.text('تم التجديد بنجاح'), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    await simCheck(t, v, _activate, 'submit_success_debt_not_recorded');
    expect(find.text(msg), findsOneWidget,
        reason: 'تنبيه «لم يُسجَّل الدين» من الخادم يضيع — المدير يظنّ الدين قُيّد');
    await simDrain(t);
  });

  simCase(_activate, 'submit_timeout', (t, v) async {
    server.on('POST', _activatePath, simTimeout);
    await openActivate(t, v);
    await t.enterText(field('باسورد الإيداع'), 'dep-pass');
    await t.pumpAndSettle();
    final before = SubscriberEvents.dataChanged.value;
    await t.tap(find.text('تجديد الآن'));
    await t.pumpAndSettle();
    await simCheck(t, v, _activate, 'submit_timeout');
    expect(find.text('راجع انتهاء المشترك أوّلاً'), findsOneWidget,
        reason: 'ربّما تفعّل ⇒ قفل');
    expect(SubscriberEvents.dataChanged.value, before + 1);
    expect(server.calls('POST', _activatePath), hasLength(1));
    // ربّما تفعّل — فالإشعار يجب أن يقول ذلك، لا «خطأ» عارياً يدعو للإعادة.
    expect(find.text('خطأ'), findsNothing,
        reason: 'مهلة تجديد ايرث لنك تُعرض «خطأ» عارياً — والنتيجة مجهولة');
    expect(
        find.text(
            'ما وصل ردّ واضح — ربّما تفعّل المشترك. راجع تاريخ انتهائه قبل ما تعيد المحاولة'),
        findsOneWidget,
        reason: 'مهلة تجديد ايرث لنك تُعرض «خطأ» بدل «ربّما تفعّل»');
    await simDrain(t);
  });

  simCase(_activate, 'recent_duplicate_confirm', (t, v) async {
    var n = 0;
    server.on('POST', _activatePath, (_) {
      n++;
      return n == 1
          ? const SimReply(409, {
              'success': false,
              'code': 'RECENT_DUPLICATE',
              'message': 'جدّدت هذا المشترك قبل لحظات — أكّد إن أردت تجديداً آخر',
            })
          : const SimReply(200, {'success': true});
    });
    await openActivate(t, v);
    await t.enterText(field('باسورد الإيداع'), 'dep-pass');
    await t.pumpAndSettle();
    await t.tap(find.text('تجديد الآن'));
    await t.pumpAndSettle();
    expect(find.text('تفعيل مكرّر'), findsOneWidget);
    await simCheck(t, v, _activate, 'recent_duplicate_confirm');
    await t.tap(find.text('أكّد التفعيل'));
    await t.pumpAndSettle();
    final bodies = server.bodies('POST', _activatePath);
    expect(bodies, hasLength(2));
    expect(bodies.first.containsKey('confirmRepeat'), isFalse);
    expect(bodies.last['confirmRepeat'], isTrue);
    expect(find.text('تم التجديد بنجاح'), findsOneWidget);
    await simDrain(t);
  });

  // ═══════════════════════════ التمديد ═══════════════════════════

  simCase(_extend, 'points_ok', (t, v) async {
    await openExtend(t, v);
    expect(find.text('الباقة'), findsWidgets);
    expect(find.text('1 نقطة'), findsWidgets);
    expect(find.text('رصيد المدير'), findsNothing, reason: 'ايرث لنك: لا رصيد');
    expect(find.text('طريقة الدفع'), findsNothing, reason: 'بالنقاط حصراً');
    expect(footerEnabled(t, 'تمديد الآن'), isTrue);
    await simCheck(t, v, _extend, 'points_ok');
  });

  simCase(_extend, 'insufficient_points', (t, v) async {
    extensionOptions(points: 0);
    await openExtend(t, v);
    expect(find.text('النقاط غير كافية'), findsOneWidget);
    expect(footerEnabled(t, 'النقاط غير كافية'), isFalse);
    await simCheck(t, v, _extend, 'insufficient_points');
  });

  simCase(_extend, 'no_points_support', (t, v) async {
    extensionOptions(required: 0);
    await openExtend(t, v);
    expect(find.text('الباقة لا تدعم الدفع بالنقاط'), findsOneWidget);
    await simCheck(t, v, _extend, 'no_points_support');
  });

  simCase(_extend, 'package_picker', (t, v) async {
    extensionOptions(two: true);
    await openExtend(t, v);
    await openPicker(t);
    await simCheck(t, v, _extend, 'package_picker');
    await t.tap(find.textContaining('Standard').last);
    await t.pumpAndSettle();
    expect(find.text('Standard'), findsWidgets);
  });

  simCase(_extend, 'package_locked', (t, v) async {
    await openExtend(t, v,
        sub: _sub(
            canChange: false,
            note: 'باقة More لا تتغيّر عند ايرث لنك — مدّد على الباقة نفسها'));
    expect(
        find.text('باقة More لا تتغيّر عند ايرث لنك — مدّد على الباقة نفسها'),
        findsOneWidget);
    await simCheck(t, v, _extend, 'package_locked');
  });

  simCase(_extend, 'submit_success', (t, v) async {
    server.reply('POST', _extendPath, 200, {'success': true});
    await openExtend(t, v);
    final before = SubscriberEvents.dataChanged.value;
    await t.tap(find.text('تمديد الآن'));
    await t.pumpAndSettle();
    final body = server.bodies('POST', _extendPath).single;
    expect(body['method'], 'points');
    expect(body['profile_id'], '7');
    expect(find.text('تم التمديد بنجاح'), findsOneWidget);
    expect(SubscriberEvents.dataChanged.value, before + 1);
    await simCheck(t, v, _extend, 'submit_success');
    await simDrain(t);
  });

  simCase(_extend, 'submit_recent_duplicate', (t, v) async {
    // الخادم: 409 RECENT_DUPLICATE ويقبل `confirmRepeat:true` للتمديد (كالتجديد).
    const msg = 'مدّدت هذا المشترك قبل لحظات — أكّد الإعادة إن أردت تمديداً آخر';
    server.reply('POST', _extendPath, 409,
        {'success': false, 'code': 'RECENT_DUPLICATE', 'message': msg});
    await openExtend(t, v);
    await t.tap(find.text('تمديد الآن'));
    await t.pumpAndSettle();
    await simCheck(t, v, _extend, 'submit_recent_duplicate');
    expect(find.text(msg), findsOneWidget);
    await simDrain(t);
    // الرسالة تطلب «أكّد الإعادة» — فيجب أن يُعرض ما يؤكّدها ويُرسل confirmRepeat.
    final confirm = find.textContaining('أكّد');
    final offered = confirm.evaluate().any((e) => e.widget is Text &&
        (e.widget as Text).data != msg);
    expect(offered, isTrue,
        reason: 'لا زرّ «أكّد» — التمديد لا يُرسل confirmRepeat أبداً');
  });

  simCase(_extend, 'submit_rejected', (t, v) async {
    server.reply('POST', _extendPath, 200, {
      'success': false,
      'message': 'ايرث لنك رفض التمديد — نقاط الوكيل لا تكفي الآن',
    });
    await openExtend(t, v);
    await t.tap(find.text('تمديد الآن'));
    await t.pumpAndSettle();
    expect(find.text('ايرث لنك رفض التمديد — نقاط الوكيل لا تكفي الآن'),
        findsOneWidget);
    expect(find.text('تمديد المشترك'), findsOneWidget, reason: 'لم يُغلق');
    await simCheck(t, v, _extend, 'submit_rejected');
    await simDrain(t);
  });
}
