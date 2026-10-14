import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/add_subscriber_sheet.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/services/subscriber_events.dart';

import 'sim_harness.dart';

/// محاكاة شيت «مشترك جديد» لايرث لنك (`el_add_subscriber_sheet.dart`) —
/// مالٌ حقيقيّ: الرصيد/الكارت يُشحنان على الوكيل ودفترنا يسجّل الدين.
///
/// كلّ حالةٍ × (٣٢٠ · ٣٦٠ · ٣٩٠) × (فاتح · داكن)، ولقطتها في
/// `shots/el_add/`. وما يُحرس فوق الرسم:
///   • الطرق: رصيد · كارت · تجريبي (يختفي حين لا تبقى حصّة).
///   • فحص الاسم (متاح/مستخدم/أُنشئ متأخّراً/تعذّر) وقراءة الكارت
///     (صالح/غير صالح/RATE_LIMITED/باقةٌ خارج قائمتنا).
///   • نقدي/دين/جزئي — بالمبلغ الذي يصل الخادم فعلاً.
///   • كلّ نتيجةٍ من الخادم: النجاح (ومعه فشل الدفتر، و`recheck`)،
///     و«ربّما أُضيف» (قفل + سطرٌ باقٍ + تحديث القائمة)، والرفض المؤكّد
///     (بلا قفل)، والمهلة — ولا إعادة إرسالٍ تلقائيّة أبداً.
///   • لا يُغلق أثناء الإضافة (سحب/حاجز/رجوع)، والنجاح يُغلق مسار الورقة
///     وحده ولو فُتح فوقها مسارٌ آخر أثناء الطلب.
const _screen = 'el_add';

const _subtitle = 'إضافة مشترك على ايرث لنك';
const _submit = 'إضافة المشترك';
const _submitting = 'جاري الإضافة...';
const _locked = 'راجع قائمة المشتركين أوّلاً';
const _okSnack = 'تمت إضافة المشترك';
const _unclearDefault =
    'ما وصل ردّ واضح — ربّما أُضيف المشترك. راجع قائمة المشتركين قبل ما تعيد المحاولة';

const _suffix = '@alnoor-net';
const _createPath = '/api/v2/subscribers';

/// رسائل الخادم كما يصوغها (طويلة، ومبلغ الدين في آخرها — قصّها يُسقطه).
const _unconfirmedMsg = 'تعذّر تأكيد الإنشاء من ايرث لنك — راجع قائمة '
    'المشتركين قبل إعادة المحاولة، وإن ظهر المشترك فقد أُنشئ: سجّل عليه ديناً '
    'بـ35000 د.ع يدويّاً ولا تُعِد الإضافة';
const _lateMsg = 'يبدو أنّ إضافة ali1 السابقة مرّت متأخّرة عند ايرث لنك — '
    'لا تُضِفه باسمٍ آخر. راجع قائمة المشتركين، وإن ظهر فسجّل عليه ديناً '
    'يدويّاً بمبلغ 35,000 د.ع';
const _duplicateMsg =
    'أضفت مشتركاً بهذا الاسم قبل لحظات — تحقّق من القائمة قبل إعادة المحاولة';
const _elUnavailableMsg =
    'تعذّر إنشاء المشترك لدى ايرث لنك — وتحقّقنا أنّه لم يُنشأ، أعد المحاولة';
const _takenMsg = 'اسم الدخول مستخدَمٌ مسبقاً — اختر اسماً آخر';
const _priceUnknownMsg = 'سعر بيع الباقة «Economy» غير محدَّد — اضبط سعر البيع '
    'من صفحة الباقات، أو اختر الدفع النقديّ';
const _appUpdateMsg = 'حدّث التطبيق إلى آخر نسخة لإضافة مشتركي ايرث لنك';
const _debtWriteMsg =
    'تمّ إنشاء المشترك لكن لم يُسجَّل الدين في دفترنا — سجّله يدويّاً';
const _lateCreateUserMsg = 'هذا الاسم أُنشئ عند ايرث لنك من إضافةٍ سابقة لم '
    'تتأكّد — لا تُضِفه باسمٍ آخر، راجع قائمة المشتركين';
const _rateLimitedMsg =
    'محاولاتٌ كثيرة للتحقّق من الكارت — انتظر دقيقةً ثمّ أعد المحاولة';
const _cardBadMsg = 'الكارت مستعمَل سابقاً أو رقمه غير صحيح';

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  /// خيارات الإضافة — رصيد + كارت، والتجريبيّ مسموحٌ لكن بلا حصّة (فيُخفى).
  void options({
    int testCount = 0,
    bool deposit = true,
    bool card = true,
    bool test = true,
    num? balance = 100000,
  }) {
    server.reply('GET', '/api/v2/el/create-options', 200, {
      'success': true,
      'data': {
        'user_suffix': _suffix,
        'packages': [
          {'id': '7', 'name': 'Economy', 'price': 35000, 'cost_price': 20000},
          {'id': '8', 'name': 'Standard', 'price': 45000, 'cost_price': 28000},
          {
            'id': '12',
            'name': 'Ta3leem 50,000 Plus 3 Months',
            'price': 150000,
            'cost_price': 93000,
          },
        ],
        'deposit_balance': balance,
        'test_count': testCount,
        'methods': {'deposit': deposit, 'card': card, 'test': test},
      },
    });
  }

  setUp(() async {
    server = await simSetUp();
    ProviderService.debugSet('earthlink');
    options();
    server.reply('POST', '/api/v2/el/check-username', 200, {
      'success': true,
      'data': {'available': true, 'user_id': 'ali1$_suffix'},
    });
    server.reply('POST', _createPath, 200, {
      'success': true,
      'data': {'username': 'ali1$_suffix', 'idx': 9},
    });
  });

  // ─────────────────────────── أدوات ───────────────────────────

  Future<void> open(WidgetTester t, SimVariant v,
      {GlobalKey<NavigatorState>? nav,
      void Function(Future<bool?>)? onResult}) async {
    await pumpSim(t, v,
        navigatorKey: nav,
        home: (_) => simLauncher((c) {
              final f = showAddSubscriberSheet(c);
              onResult?.call(f);
            }));
    await simOpen(t);
    expect(find.text(_subtitle), findsOneWidget, reason: 'شيت ايرث لنك');
  }

  Finder field(String hint) => find.widgetWithText(TextField, hint);

  /// الاسم والهاتف واسم الدخول وكلمة المرور، وينتظر فحص الاسم (٥٠٠ms).
  Future<void> fillBasics(WidgetTester t, {String username = 'ali1'}) async {
    await t.enterText(field('الاسم'), 'علي');
    await t.enterText(field('اختياري'), 'حسن');
    await t.enterText(field('07XX XXX XXXX'), '07701234567');
    await t.enterText(field('ahmed'), username);
    await t.enterText(field('••••••••'), 'pw123456');
    await t.pump(const Duration(milliseconds: 600));
    await t.pumpAndSettle();
  }

  Future<void> pickPackage(WidgetTester t, String name) async {
    final pick = find.text('اختر الباقة');
    await t.ensureVisible(pick);
    await t.pumpAndSettle();
    await t.tap(pick);
    await t.pumpAndSettle();
    await t.tap(find.textContaining(name).last);
    await t.pumpAndSettle();
  }

  /// رصيد أونلاين كاملاً: الأساسيّات + باسورد الإيداع + Economy (الدين افتراضيّ).
  Future<void> fillDeposit(WidgetTester t) async {
    await fillBasics(t);
    await t.enterText(field('باسورد الإيداع'), 'dep-pass');
    await t.pumpAndSettle();
    await pickPackage(t, 'Economy');
    expect(find.text(_submit), findsOneWidget);
  }

  Future<void> chooseMethod(WidgetTester t, String label) async {
    await t.ensureVisible(find.text(label));
    await t.pumpAndSettle();
    await t.tap(find.text(label));
    await t.pumpAndSettle();
  }

  /// الكارت: رقم + Pin ثمّ القراءة بعد توقّف الإدخال (٩٠٠ms).
  Future<void> enterCard(WidgetTester t) async {
    await chooseMethod(t, 'كارت');
    await t.enterText(field('رقم الكارت'), '4400112233');
    await t.enterText(field('Pin'), '9081');
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
  }

  Future<void> tapSubmit(WidgetTester t) async {
    await t.tap(find.text(_submit));
    await t.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester t, Finder f) async {
    await t.ensureVisible(f);
    await t.pumpAndSettle();
  }

  bool footerEnabled(WidgetTester t, String label) {
    // الزرّ حيٌّ ⇔ InkWell فوق التسمية له onTap.
    final ink = t.widget<InkWell>(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first);
    return ink.onTap != null;
  }

  int creates() => server.calls('POST', _createPath).length;

  // ─────────────────────────── الطرق ───────────────────────────

  simCase(_screen, 'deposit_default', (t, v) async {
    await open(t, v);
    expect(find.text('رصيد أونلاين'), findsOneWidget);
    expect(find.text('كارت'), findsOneWidget);
    expect(find.text('تجريبي'), findsNothing,
        reason: 'التجريبيّ مسموحٌ لكن بلا حصّة (test_count 0) ⇒ مخفيّ');
    expect(find.text('باسورد الإيداع *'), findsOneWidget);
    expect(footerEnabled(t, _submit), isFalse);
    expect(find.text(_suffix), findsOneWidget);
    await simCheck(t, v, _screen, 'deposit_default');
  });

  simCase(_screen, 'test_method', (t, v) async {
    options(testCount: 3);
    await open(t, v);
    expect(find.text('تجريبي ٢٤ ساعة · بقي 3'), findsOneWidget);
    await chooseMethod(t, 'تجريبي');
    expect(find.text('يُنشأ المشترك باشتراكٍ تجريبيّ لمدّة ٢٤ ساعة — بقي لك 3'),
        findsOneWidget);
    expect(find.text('طريقة الدفع'), findsNothing, reason: 'التجريبيّ بلا دفع');
    expect(find.text('باسورد الإيداع *'), findsNothing);
    await fillBasics(t);
    await pickPackage(t, 'Standard');
    await simCheck(t, v, _screen, 'test_method');
    await tapSubmit(t);
    final body = server.bodies('POST', _createPath).single;
    expect(body['method'], 'test');
    expect(body['profile_id'], 8);
    expect(body.containsKey('payment_type'), isFalse);
    expect(body.containsKey('paid_amount'), isFalse);
    expect(body.containsKey('deposit_password'), isFalse);
    await simDrain(t);
  });

  simCase(_screen, 'no_methods', (t, v) async {
    options(deposit: false, card: false, test: false);
    await open(t, v);
    expect(find.text('لا توجد طريقة إضافة متاحة لحسابك'), findsOneWidget);
    expect(footerEnabled(t, _submit), isFalse);
    await simCheck(t, v, _screen, 'no_methods');
  });

  simCase(_screen, 'load_failed_then_retry', (t, v) async {
    server.reply('GET', '/api/v2/el/create-options', 503, {
      'success': false,
      'message': 'ايرث لنك لا يستجيب الآن — حاول بعد قليل',
    });
    await open(t, v);
    expect(find.text('ايرث لنك لا يستجيب الآن — حاول بعد قليل'), findsOneWidget);
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    await simCheck(t, v, _screen, 'load_failed_then_retry');
    options();
    await t.tap(find.text('إعادة المحاولة'));
    await t.pumpAndSettle();
    expect(find.text('رصيد أونلاين'), findsOneWidget);
  });

  // ─────────────────────────── اسم الدخول ───────────────────────────

  simCase(_screen, 'username_available', (t, v) async {
    await open(t, v);
    await fillBasics(t);
    expect(simText('✓ متاح — ali1$_suffix'), findsOneWidget);
    final checks = server.bodies('POST', '/api/v2/el/check-username');
    expect(checks.single['username'], 'ali1', reason: 'مؤجَّل: فحصٌ واحد');
    await reveal(t, simText('✓ متاح — ali1$_suffix'));
    await simCheck(t, v, _screen, 'username_available');
  });

  simCase(_screen, 'username_taken', (t, v) async {
    server.reply('POST', '/api/v2/el/check-username', 200, {
      'success': true,
      'data': {'available': false},
    });
    await open(t, v);
    await fillBasics(t);
    await t.enterText(field('باسورد الإيداع'), 'dep-pass');
    await pickPackage(t, 'Economy');
    expect(find.text('✗ مستخدم — اختر اسماً آخر'), findsOneWidget);
    expect(footerEnabled(t, _submit), isFalse, reason: 'اسمٌ مستخدم يمنع');
    await reveal(t, find.text('✗ مستخدم — اختر اسماً آخر'));
    await simCheck(t, v, _screen, 'username_taken');
    await t.tap(find.text(_submit), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(creates(), 0);
  });

  simCase(_screen, 'username_late_create', (t, v) async {
    server.reply('POST', '/api/v2/el/check-username', 200, {
      'success': true,
      'data': {'available': false, 'message': _lateCreateUserMsg},
    });
    await open(t, v);
    await fillBasics(t);
    expect(find.text('⚠ $_lateCreateUserMsg'), findsOneWidget);
    expect(find.text('✗ مستخدم — اختر اسماً آخر'), findsNothing);
    final p = t.renderObject<RenderParagraph>(
        find.text('⚠ $_lateCreateUserMsg'));
    expect(p.didExceedMaxLines, isFalse, reason: 'نصّ الخادم كاملاً');
    await reveal(t, find.text('⚠ $_lateCreateUserMsg'));
    await simCheck(t, v, _screen, 'username_late_create');
  });

  simCase(_screen, 'username_check_failed', (t, v) async {
    server.reply('POST', '/api/v2/el/check-username', 500,
        {'success': false, 'message': 'Internal Server Error'});
    await open(t, v);
    await fillBasics(t);
    await t.enterText(field('باسورد الإيداع'), 'dep-pass');
    await pickPackage(t, 'Economy');
    expect(find.text('تعذّر الفحص — سيتحقّق الخادم عند الإضافة'), findsOneWidget);
    expect(footerEnabled(t, _submit), isTrue, reason: 'التعذّر لا يمنع');
    await reveal(t, find.text('تعذّر الفحص — سيتحقّق الخادم عند الإضافة'));
    await simCheck(t, v, _screen, 'username_check_failed');
  });

  // ─────────────────────────── الكارت ───────────────────────────

  simCase(_screen, 'card_idle', (t, v) async {
    await open(t, v);
    await chooseMethod(t, 'كارت');
    expect(find.text('اكتب رقم الكارت والـPin لقراءة باقته'), findsOneWidget);
    expect(find.text('اختر الباقة'), findsNothing, reason: 'الكارت يحدّد الباقة');
    await reveal(t, find.text('اكتب رقم الكارت والـPin لقراءة باقته'));
    await simCheck(t, v, _screen, 'card_idle');
  });

  simCase(_screen, 'card_valid', (t, v) async {
    server.reply('POST', '/api/v2/el/card-info', 200, {
      'success': true,
      'data': {'valid': true, 'profile_id': 7, 'profile_name': 'Economy'},
    });
    await open(t, v);
    await fillBasics(t);
    await enterCard(t);
    final reads = server.bodies('POST', '/api/v2/el/card-info');
    expect(reads, hasLength(1), reason: 'قراءةٌ واحدة بعد توقّف الإدخال');
    expect(reads.single, {'card_identifier': '4400112233', 'card_pin': '9081'});
    expect(find.text('باقة الكارت: Economy'), findsOneWidget);
    expect(find.text('35,000 د.ع'), findsWidgets);
    expect(find.text('رصيد الإيداع'), findsNothing, reason: 'للرصيد وحده');
    expect(footerEnabled(t, _submit), isTrue);
    await reveal(t, find.text('باقة الكارت: Economy'));
    await simCheck(t, v, _screen, 'card_valid');
    await tapSubmit(t);
    final body = server.bodies('POST', _createPath).single;
    expect(body['method'], 'card');
    expect(body['card_identifier'], '4400112233');
    expect(body['card_pin'], '9081');
    expect(body.containsKey('profile_id'), isFalse, reason: 'الكارت يحدّدها');
    expect(body['payment_type'], 'debt');
    expect(body['paid_amount'], 0);
    await simDrain(t);
  });

  simCase(_screen, 'card_invalid', (t, v) async {
    server.reply('POST', '/api/v2/el/card-info', 200, {
      'success': true,
      'data': {'valid': false, 'message': _cardBadMsg},
    });
    await open(t, v);
    await fillBasics(t);
    await enterCard(t);
    expect(find.text(_cardBadMsg), findsOneWidget);
    expect(footerEnabled(t, _submit), isFalse);
    await reveal(t, find.text(_cardBadMsg));
    await simCheck(t, v, _screen, 'card_invalid');
  });

  simCase(_screen, 'card_rate_limited', (t, v) async {
    // كما يردّه الخادم: 200 success:false (سقف ٢٠ تحقّقاً/دقيقة).
    server.reply('POST', '/api/v2/el/card-info', 200, {
      'success': false,
      'code': 'RATE_LIMITED',
      'message': _rateLimitedMsg,
    });
    await open(t, v);
    await fillBasics(t);
    await enterCard(t);
    expect(find.text(_rateLimitedMsg), findsOneWidget, reason: 'نصّ الخادم');
    expect(footerEnabled(t, _submit), isFalse);
    await reveal(t, find.text(_rateLimitedMsg));
    await simCheck(t, v, _screen, 'card_rate_limited');
    // السطر نفسه زرّ «أعد القراءة».
    server.reply('POST', '/api/v2/el/card-info', 200, {
      'success': true,
      'data': {'valid': true, 'profile_id': 7, 'profile_name': 'Economy'},
    });
    await t.tap(find.text(_rateLimitedMsg));
    await t.pumpAndSettle();
    expect(server.calls('POST', '/api/v2/el/card-info'), hasLength(2));
    expect(find.text('باقة الكارت: Economy'), findsOneWidget);
  });

  simCase(_screen, 'card_unknown_package', (t, v) async {
    server.reply('POST', '/api/v2/el/card-info', 200, {
      'success': true,
      'data': {'valid': true, 'profile_id': 99, 'profile_name': 'Turbo 75'},
    });
    await open(t, v);
    await fillBasics(t);
    await enterCard(t);
    expect(find.text('باقة الكارت: Turbo 75'), findsOneWidget);
    expect(find.text('—'), findsWidgets, reason: 'سعرٌ مجهول لا «0 د.ع»');
    expect(find.textContaining('بعد الإضافة'), findsNothing,
        reason: 'لا بانر دينٍ بسعرٍ مجهول');
    await chooseMethod(t, 'نقدي');
    await reveal(t, find.text('باقة الكارت: Turbo 75'));
    await simCheck(t, v, _screen, 'card_unknown_package');
    await tapSubmit(t);
    final body = server.bodies('POST', _createPath).single;
    expect(body['payment_type'], 'cash');
    expect(body.containsKey('paid_amount'), isFalse,
        reason: 'نقديٌّ بسعرٍ مجهول لا يُرسل ٠ يُقرأ «لم يدفع»');
    await simDrain(t);
  });

  // ─────────────────────────── الدفع ───────────────────────────

  Future<void> payCase(WidgetTester t, SimVariant v, String state,
      {required String tile,
      required String banner,
      required String paymentType,
      required num paid,
      int? chip}) async {
    await open(t, v);
    await fillDeposit(t);
    if (tile != 'دين') await chooseMethod(t, tile);
    if (chip != null) {
      final f = find.text(_fmt(chip));
      await reveal(t, f);
      await t.tap(f);
      await t.pumpAndSettle();
    }
    expect(find.text(banner), findsOneWidget);
    await reveal(t, find.text(banner));
    await simCheck(t, v, _screen, state);
    await tapSubmit(t);
    final body = server.bodies('POST', _createPath).single;
    expect(body['method'], 'deposit');
    expect(body['deposit_password'], 'dep-pass');
    expect(body['profile_id'], 7);
    expect(body['payment_type'], paymentType);
    expect(body['paid_amount'], paid);
    await simDrain(t);
  }

  simCase(_screen, 'pay_debt',
      (t, v) => payCase(t, v, 'pay_debt',
          tile: 'دين',
          banner: 'دين المشترك بعد الإضافة',
          paymentType: 'debt',
          paid: 0));

  simCase(_screen, 'pay_cash',
      (t, v) => payCase(t, v, 'pay_cash',
          tile: 'نقدي',
          banner: 'رصيد المشترك بعد الإضافة',
          paymentType: 'cash',
          paid: 35000));

  simCase(_screen, 'pay_partial',
      (t, v) => payCase(t, v, 'pay_partial',
          tile: 'جزئي',
          banner: 'دين المشترك بعد الإضافة',
          paymentType: 'partial',
          paid: 10000,
          chip: 10000));

  simCase(_screen, 'low_balance', (t, v) async {
    options(balance: 15000);
    await open(t, v);
    await fillDeposit(t);
    expect(find.text('رصيد الإيداع أقلّ من كلفة الباقة'), findsOneWidget);
    expect(footerEnabled(t, _submit), isTrue, reason: 'تنبيهٌ لا منع');
    await reveal(t, find.text('رصيد الإيداع أقلّ من كلفة الباقة'));
    await simCheck(t, v, _screen, 'low_balance');
  });

  // ─────────────────────────── النتائج ───────────────────────────

  /// يملأ ويُرسل بالردّ [reply] ويُعيد عدّاد تحديث القائمة قبل الإرسال.
  Future<int> submitWith(WidgetTester t, SimVariant v, SimHandler reply) async {
    server.on('POST', _createPath, reply);
    await open(t, v);
    await fillDeposit(t);
    final before = SubscriberEvents.dataChanged.value;
    await tapSubmit(t);
    expect(creates(), 1);
    return before;
  }

  /// ربّما أُضيف: قفل + السطر فوق الزرّ + تحديث القائمة + لا إعادة أبداً.
  Future<void> unclearCase(WidgetTester t, SimVariant v, String state,
      SimHandler reply, String note) async {
    final before = await submitWith(t, v, reply);
    expect(SubscriberEvents.dataChanged.value, before + 1,
        reason: 'القائمة تُحدَّث');
    expect(find.text(_locked), findsOneWidget);
    expect(footerEnabled(t, _locked), isFalse);
    expect(find.text(note), findsNWidgets(2), reason: 'الإشعار + سطر القفل');
    expect(find.text(_subtitle), findsOneWidget, reason: 'لم يُغلق');
    await simCheck(t, v, _screen, state);
    // بعد زوال الإشعار يبقى السطر كاملاً — والزمن لا يُعيد الإرسال.
    await t.pump(const Duration(minutes: 3));
    await t.pumpAndSettle();
    expect(find.text(note), findsOneWidget);
    final p = t.renderObject<RenderParagraph>(find.text(note));
    expect(p.didExceedMaxLines, isFalse, reason: 'لا قصّ يُسقط مبلغ الدين');
    await simCheck(t, v, _screen, '${state}_note');
    await t.tap(find.text(_locked));
    await t.pumpAndSettle();
    expect(creates(), 1, reason: 'لا إعادة إرسال — لا تلقائيّاً ولا بالضغط');
    await simDrain(t);
  }

  /// رفضٌ مؤكّد: رسالةٌ عابرة، بلا قفل ولا تحديث، والمحاولة بيد المدير.
  Future<void> rejectCase(WidgetTester t, SimVariant v, String state,
      SimHandler reply, String message) async {
    final before = await submitWith(t, v, reply);
    expect(find.text(message), findsOneWidget);
    expect(find.text(_locked), findsNothing);
    expect(SubscriberEvents.dataChanged.value, before, reason: 'لم يُضف');
    expect(find.text(_subtitle), findsOneWidget);
    await simCheck(t, v, _screen, state);
    await t.pump(const Duration(minutes: 3));
    await t.pumpAndSettle();
    expect(find.text(message), findsNothing, reason: 'زال الإشعار');
    expect(creates(), 1, reason: 'لا إعادة تلقائيّة');
    expect(footerEnabled(t, _submit), isTrue);
    await tapSubmit(t);
    expect(creates(), 2, reason: 'إعادةٌ بيد المدير مسموحة');
    await simDrain(t);
  }

  simCase(_screen, 'outcome_success', (t, v) async {
    Future<bool?>? result;
    server.reply('POST', _createPath, 200, {
      'success': true,
      'data': {'username': 'ali1$_suffix', 'idx': 9},
    });
    await open(t, v, onResult: (f) => result = f);
    await fillDeposit(t);
    final before = SubscriberEvents.dataChanged.value;
    await tapSubmit(t);
    expect(find.text(_subtitle), findsNothing, reason: 'أُغلق بالنجاح');
    expect(find.text(_okSnack), findsOneWidget);
    expect(SubscriberEvents.dataChanged.value, before + 1);
    expect(await result, isTrue);
    await simCheck(t, v, _screen, 'outcome_success');
    await simDrain(t);
  });

  simCase(_screen, 'outcome_success_debt_not_recorded', (t, v) async {
    await submitWith(
        t,
        v,
        (_) => const SimReply(200, {
              'success': true,
              'data': {'username': 'ali1$_suffix', 'idx': 9},
              'debt_write': {'ok': false, 'message': _debtWriteMsg},
            }));
    expect(find.text(_subtitle), findsNothing);
    expect(find.text(_okSnack), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    expect(find.text(_debtWriteMsg), findsOneWidget, reason: 'يلي النجاح');
    await simCheck(t, v, _screen, 'outcome_success_debt_not_recorded');
    await simDrain(t);
  });

  simCase(_screen, 'outcome_success_recheck', (t, v) async {
    final before = await submitWith(
        t,
        v,
        (_) => const SimReply(200, {
              'success': true,
              'data': {
                'username': 'ali1$_suffix',
                'idx': null,
                'confirmed_by': 'recheck',
              },
            }));
    expect(find.text(_subtitle), findsNothing);
    expect(find.text(_okSnack), findsOneWidget);
    expect(SubscriberEvents.dataChanged.value, before + 1);
    await simCheck(t, v, _screen, 'outcome_success_recheck');
    await simDrain(t);
  });

  simCase(
      _screen,
      'outcome_create_unconfirmed_503',
      (t, v) => unclearCase(
          t,
          v,
          'outcome_create_unconfirmed_503',
          (_) => const SimReply(503, {
                'success': false,
                'code': 'CREATE_UNCONFIRMED',
                'message': _unconfirmedMsg,
              }),
          _unconfirmedMsg));

  simCase(
      _screen,
      'outcome_create_late_suspected_200',
      (t, v) => unclearCase(
          t,
          v,
          'outcome_create_late_suspected_200',
          (_) => const SimReply(200, {
                'success': false,
                'code': 'CREATE_LATE_SUSPECTED',
                'message': _lateMsg,
              }),
          _lateMsg));

  simCase(
      _screen,
      'outcome_recent_duplicate_409',
      (t, v) => unclearCase(
          t,
          v,
          'outcome_recent_duplicate_409',
          (_) => const SimReply(409, {
                'success': false,
                'code': 'RECENT_DUPLICATE',
                'message': _duplicateMsg,
              }),
          _duplicateMsg));

  simCase(
      _screen,
      'outcome_timeout',
      (t, v) => unclearCase(
          t, v, 'outcome_timeout', simTimeout, _unclearDefault));

  simCase(
      _screen,
      'outcome_gateway_502_html',
      (t, v) => unclearCase(
          t,
          v,
          'outcome_gateway_502_html',
          (_) => const SimReply.html(502,
              '<html><body><h1>502 Bad Gateway</h1>cloudflare</body></html>'),
          _unclearDefault));

  simCase(
      _screen,
      'outcome_el_unavailable_503',
      (t, v) => rejectCase(
          t,
          v,
          'outcome_el_unavailable_503',
          (_) => const SimReply(503, {
                'success': false,
                'code': 'EL_UNAVAILABLE',
                'message': _elUnavailableMsg,
              }),
          _elUnavailableMsg));

  simCase(
      _screen,
      'outcome_username_taken_200',
      (t, v) => rejectCase(
          t,
          v,
          'outcome_username_taken_200',
          (_) => const SimReply(200, {
                'success': false,
                'code': 'USERNAME_TAKEN',
                'message': _takenMsg,
              }),
          _takenMsg));

  simCase(
      _screen,
      'outcome_price_unknown_200',
      (t, v) => rejectCase(
          t,
          v,
          'outcome_price_unknown_200',
          (_) => const SimReply(200, {
                'success': false,
                'code': 'PRICE_UNKNOWN',
                'message': _priceUnknownMsg,
              }),
          _priceUnknownMsg));

  simCase(
      _screen,
      'outcome_app_update_required_400',
      (t, v) => rejectCase(
          t,
          v,
          'outcome_app_update_required_400',
          (_) => const SimReply(400, {
                'success': false,
                'code': 'APP_UPDATE_REQUIRED',
                'message': _appUpdateMsg,
              }),
          _appUpdateMsg));

  // ─────────────────────────── أثناء الإضافة ───────────────────────────

  simCase(_screen, 'submitting_cannot_close', (t, v) async {
    server.reply('POST', _createPath, 503, {
      'success': false,
      'code': 'CREATE_UNCONFIRMED',
      'message': _unconfirmedMsg,
    });
    server.hold('POST', _createPath);
    await open(t, v);
    await fillDeposit(t);
    await t.tap(find.text(_submit));
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    expect(find.text(_submitting), findsOneWidget);
    await simCheck(t, v, _screen, 'submitting_cannot_close');

    // ١) السحب للأسفل.
    await t.drag(find.text(_subtitle), const Offset(0, 500));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(_subtitle), findsOneWidget, reason: 'السحب لا يُغلق');
    // ٢) النقر على الحاجز فوق الورقة.
    await t.tapAt(Offset(v.width / 2, 8));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(_subtitle), findsOneWidget, reason: 'الحاجز لا يُغلق');
    // ٣) زرّ الرجوع.
    await t.binding.handlePopRoute();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(_subtitle), findsOneWidget, reason: 'الرجوع لا يُغلق');
    // ٤) ✕ معطّلة أثناءها.
    await t.tap(find.byIcon(Icons.close_rounded));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(_subtitle), findsOneWidget, reason: '✕ لا يُغلق');

    server.release('POST', _createPath);
    await t.pumpAndSettle();
    expect(find.text(_locked), findsOneWidget);
    expect(creates(), 1);
    await simDrain(t);
  });

  simCase(_screen, 'success_page_pushed_on_top', (t, v) async {
    final nav = GlobalKey<NavigatorState>();
    Future<bool?>? result;
    server.hold('POST', _createPath);
    await open(t, v, nav: nav, onResult: (f) => result = f);
    await fillDeposit(t);
    await t.tap(find.text(_submit));
    await t.pump();
    // إشعارٌ يفتح شاشةً فوق الورقة أثناء الطلب.
    unawaited(nav.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('تفاصيل المشترك')),
        body: const Center(child: Text('شاشةٌ فُتحت فوق الورقة')),
      ),
    )));
    await t.pumpAndSettle();
    final before = SubscriberEvents.dataChanged.value;
    server.release('POST', _createPath);
    await t.pumpAndSettle();
    expect(find.text('شاشةٌ فُتحت فوق الورقة'), findsOneWidget,
        reason: 'الشاشة العليا باقية — لم تُغلق بدل الورقة');
    expect(find.text(_subtitle, skipOffstage: false), findsNothing,
        reason: 'مسار الورقة وحده أُزيل');
    expect(await result, isTrue);
    expect(SubscriberEvents.dataChanged.value, before + 1);
    expect(find.text(_okSnack), findsOneWidget);
    await simCheck(t, v, _screen, 'success_page_pushed_on_top');
    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(find.text(simOpenLabel), findsOneWidget);
    expect(find.text(_subtitle, skipOffstage: false), findsNothing);
    expect(creates(), 1);
    await simDrain(t);
  });

  simCase(_screen, 'success_dialog_on_top', (t, v) async {
    final nav = GlobalKey<NavigatorState>();
    server.hold('POST', _createPath);
    await open(t, v, nav: nav);
    await fillDeposit(t);
    await t.tap(find.text(_submit));
    await t.pump();
    unawaited(showDialog<void>(
      context: nav.currentState!.overlay!.context,
      builder: (_) => const AlertDialog(content: Text('تنبيهٌ وصل أثناء الإضافة')),
    ));
    // الورقة تحت الحوار ظاهرة ودوّارة الزرّ تدور — لا استقرار قبل الردّ.
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    server.release('POST', _createPath);
    await t.pumpAndSettle();
    expect(find.text('تنبيهٌ وصل أثناء الإضافة'), findsOneWidget,
        reason: 'الحوار باقٍ');
    expect(find.text(_subtitle, skipOffstage: false), findsNothing,
        reason: 'الورقة تحته أُزيلت');
    await simCheck(t, v, _screen, 'success_dialog_on_top');
    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(find.text(simOpenLabel), findsOneWidget);
    await simDrain(t);
  });
}

String _fmt(int v) {
  final s = v.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
