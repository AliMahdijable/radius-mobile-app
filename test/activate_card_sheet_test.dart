import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

/// §١٢ شيت التفعيل بالكارت — يُرسم كما يراه المدير: بالعربيّة وبخطّ التطبيق
/// الحقيقيّ وبعرض هاتف (٣٦٠)، أمام خادمٍ وهميّ يردّ بعقد الكارتات.
///
/// ما يحرسه: الرصيد افتراضيّ ولا يُرسَل معه `method`؛ الكارت يُرسَل
/// `method:'card'` وحده؛ «لا كارت» يمنع الزرّ؛ «تعذّرت القراءة» لا تمنعه؛
/// ورفض الخادم لا يقلب مصدر المال إلى الرصيد بصمت.
void main() {
  late _Server server;

  setUpAll(() async {
    await loadAppFonts();
    // نقرةٌ تقع على غير هدفها (الإشعار العائم فوق الزرّ مثلاً) تُنجح
    // الاختبار زوراً — فلتكن فشلاً لا تحذيراً.
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    server = _Server();
    ApiClient.dio.httpClientAdapter = server;
    CardsState.reset();
  });

  Map<String, dynamic> cardsData({
    bool credit = true,
    bool card = true,
    Object? available = 3,
  }) =>
      {
        'activation_methods': {'credit': credit, 'card': card},
        'cards': {
          'enabled': card,
          'profile_id': 4,
          'profile_name': 'Family',
          'available': available,
        },
      };

  /// يفتح الشيت وينتظر activation-data.
  Future<void> open(WidgetTester t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final sub = Subscriber.fromJson({
      'idx': '55',
      'username': 'ali@net',
      'firstname': 'علي',
      'lastname': 'حسن',
      'profile_id': 4,
      'profile_name': 'Family',
      'phone': '0770 123 4567',
    });
    await t.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('ar'), Locale('en')],
      path: 'assets/translations',
      startLocale: const Locale('ar'),
      fallbackLocale: const Locale('ar'),
      saveLocale: false,
      assetLoader: const _DiskLoader(),
      child: Builder(
        builder: (ctx) => MaterialApp(
          locale: ctx.locale,
          supportedLocales: ctx.supportedLocales,
          localizationsDelegates: ctx.localizationDelegates,
          home: Scaffold(
            body: Builder(
              builder: (c) => Center(
                child: TextButton(
                  onPressed: () => showActivateSheet(c, sub),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  /// زرّ الشيت السفليّ بتسميته — والتسمية وحدها تقول أيّ طريقٍ سيُدفع.
  Finder footer(String label) => find.text(label);

  Future<void> submit(WidgetTester t, String label) async {
    await t.tap(footer(label));
    await t.pumpAndSettle();
  }

  /// يُفرغ مؤقّت الإشعار العائم قبل نهاية الاختبار.
  Future<void> drainSnack(WidgetTester t) async {
    await t.pump(const Duration(seconds: 6));
    await t.pumpAndSettle();
  }

  testWidgets('🚨 خادمٌ أقدم: لا قسم للكارت، والطلب بلا method كما كان',
      (t) async {
    await open(t);
    expect(find.text('طريقة التفعيل'), findsNothing);
    expect(find.text('طريقة الدفع'), findsOneWidget);
    await submit(t, 'تجديد الآن');
    final body = server.activateBodies.single;
    expect(body.containsKey('method'), isFalse);
    expect(body['paymentType'], 'non-cash');
    expect(find.text('تم التجديد بنجاح'), findsOneWidget);
    await drainSnack(t);
  });

  testWidgets('الطريقان: الرصيد مختار، والكارت يُرسل method=card', (t) async {
    server.activationExtra = cardsData(available: 3);
    server.activateReply = (
      200,
      {
        'success': true,
        'card': {
          'series': '2026-52224',
          'serial_tail': '4821',
          'profile_name': 'Family',
          'remaining': 2,
        },
      }
    );
    CardsState.set(const CardsBadge(enabled: true, remaining: 3));
    await open(t);

    expect(find.text('طريقة التفعيل'), findsOneWidget);
    expect(find.text('رصيد'), findsOneWidget);
    expect(find.text('كارت (3)'), findsOneWidget);
    // الرصيد افتراضيّ: لا سطر كارت، والزرّ «تجديد الآن».
    expect(find.textContaining('يُسحب كارت تلقائيّاً'), findsNothing);
    expect(footer('تجديد الآن'), findsOneWidget);

    await t.tap(find.text('كارت (3)'));
    await t.pumpAndSettle();
    expect(find.textContaining('يُسحب كارت تلقائيّاً'), findsOneWidget);
    expect(find.textContaining('Family'), findsWidgets);
    expect(t.takeException(), isNull);

    await submit(t, 'تجديد بكارت');
    final body = server.activateBodies.single;
    expect(body['method'], 'card');
    expect(body['paymentType'], 'non-cash', reason: 'نوع الدفع مستقلّ');
    expect(body.containsKey('pin'), isFalse);
    expect(find.textContaining('تم التجديد بكارت'), findsOneWidget);
    expect(find.textContaining('4821'), findsOneWidget);
    expect(CardsState.badge.value?.remaining, 2);
    // الشيت أُغلق بالنجاح.
    expect(find.text('طريقة التفعيل'), findsNothing);
    await drainSnack(t);
  });

  testWidgets('لا كارت لهذه الباقة: تحذيرٌ والزرّ معطّل، والرصيد متاح',
      (t) async {
    server.activationExtra = cardsData(available: 0);
    await open(t);
    await t.tap(find.text('كارت (0)'));
    await t.pumpAndSettle();
    expect(find.textContaining('ما عندك كارت لباقة'), findsOneWidget);
    expect(footer('ما عندك كارت لهالباقة'), findsOneWidget);
    await t.tap(footer('ما عندك كارت لهالباقة'));
    await t.pumpAndSettle();
    expect(server.activateBodies, isEmpty, reason: 'الزرّ معطّل');

    await t.tap(find.text('رصيد'));
    await t.pumpAndSettle();
    expect(footer('تجديد الآن'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  /* ── «طريق موقع الشحن» (فايبر الجزيرة): الخادم يقول pay_rail — الكارت بطاقات الوكيل في الموقع أو بطاقةٌ خارجيّة برقمها ── */

  Map<String, dynamic> railData({Object? ownCards = 0, bool otp = false, bool option = true}) => {
        ...cardsData(available: ownCards),
        'manager_balance': 7200,
        'pay_rail': {
          'on': true,
          'ok': true,
          'balance': 7200,
          'amount': 35000,
          'own_cards': ownCards,
          'requires_otp': otp,
          'loan_available': false,
          'external_card': true,
          'option': option ? {'id': '11', 'name': 'Family'} : null,
        },
      };
  const pinKey = ValueKey('rail-card-pin');

  testWidgets('طريق موقع الشحن: بلا بطاقاتٍ بالموقع ⇒ حقل البطاقة الخارجيّة؛ ٨ خانات تفتح الزرّ وتُرسل cardPin مع method=card',
      (t) async {
    server.activationExtra = railData();
    await open(t);
    expect(find.byKey(pinKey), findsNothing, reason: 'الحقل للكارت وحده');
    await t.tap(find.text('كارت (0)'));
    await t.pumpAndSettle();
    expect(find.byKey(pinKey), findsOneWidget);
    expect(footer('ما عندك كارت لهالباقة'), findsOneWidget);
    expect(find.textContaining('اكتب رقم بطاقة خارجيّة'), findsOneWidget, reason: 'السطر يدلّ على البديل');

    // رموزٌ غير الأرقام والحروف الإنكليزيّة لا تُكتب، وما دون ٨ خانات يقفل الزرّ بسببه
    await t.enterText(find.byKey(pinKey), 'AB-12 c');
    await t.pumpAndSettle();
    expect(t.widget<TextField>(find.byKey(pinKey)).controller!.text, 'AB12c');
    expect(footer('رقم البطاقة ٨ خانات'), findsOneWidget);
    await t.tap(footer('رقم البطاقة ٨ خانات'));
    await t.pumpAndSettle();
    expect(server.activateBodies, isEmpty, reason: 'الزرّ معطّل');

    await t.enterText(find.byKey(pinKey), 'AB12cd34');
    await t.pumpAndSettle();
    expect(find.textContaining('يُفعَّل بالبطاقة الخارجيّة'), findsOneWidget);
    await submit(t, 'تجديد بكارت');
    final body = server.activateBodies.single;
    expect(body['method'], 'card');
    expect(body['cardPin'], 'AB12cd34');
    expect(body.containsKey('pin'), isFalse, reason: 'pin حقل ايرث لنك لا هذا');
    expect(t.takeException(), isNull);
    await drainSnack(t);
  });

  testWidgets('طريق موقع الشحن: ببطاقاتٍ بالموقع وبلا رقم ⇒ method=card بلا cardPin؛ والرصيد لا يحمل الرقم ولو كُتب قبله',
      (t) async {
    server.activationExtra = railData(ownCards: 2);
    await open(t);
    await t.tap(find.text('كارت (2)'));
    await t.pumpAndSettle();
    expect(find.byKey(pinKey), findsOneWidget);
    await submit(t, 'تجديد بكارت');
    expect(server.activateBodies.single['method'], 'card');
    expect(server.activateBodies.single.containsKey('cardPin'), isFalse);
    await drainSnack(t);

    server = _Server()..activationExtra = railData(ownCards: 2);
    ApiClient.dio.httpClientAdapter = server;
    await open(t);
    await t.tap(find.text('كارت (2)'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(pinKey), 'AB12cd34');
    await t.pumpAndSettle();
    await t.tap(find.text('رصيد'));
    await t.pumpAndSettle();
    expect(find.byKey(pinKey), findsNothing);
    await submit(t, 'تجديد الآن');
    final body = server.activateBodies.single;
    expect(body.containsKey('method'), isFalse);
    expect(body.containsKey('cardPin'), isFalse);
    await drainSnack(t);
  });

  testWidgets('طريق موقع الشحن: رقمٌ غير مؤكَّد ⇒ صندوق «تأكيد رقم المشترك» برقمه من الساس، والتفعيل مقفلٌ حتى يتأكّد',
      (t) async {
    server.activationExtra = railData(ownCards: 2, otp: true);
    await open(t);
    expect(find.textContaining('يطلب تأكيد رقم هاتف المشترك بالواتساب'), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const ValueKey('rail-otp-phone'))).controller!.text, '07701234567', reason: 'رقمه من الساس');
    expect(find.byKey(const ValueKey('rail-otp-send')), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-otp-code')), findsNothing, reason: 'الرمز بعد الإرسال');
    expect(footer('أكّد رقم المشترك أوّلاً'), findsOneWidget);
    await t.tap(footer('أكّد رقم المشترك أوّلاً'));
    await t.pumpAndSettle();
    expect(server.activateBodies, isEmpty);
    expect(t.takeException(), isNull);
  });

  testWidgets('تأكيد رقم المشترك: «أرسل الرمز» ⇒ خانة الرمز؛ رمزٌ خطأ ⇒ نصّ الموقع؛ الصحيح ⇒ تُعاد قراءة النافذة ويُفعَّل كالعادة',
      (t) async {
    server.activationExtra = railData(ownCards: 2, otp: true);
    server.onOtpConfirmed = () => server.activationExtra = railData(ownCards: 2);
    await open(t);
    final reads = server.activationDataCalls;
    await t.ensureVisible(find.byKey(const ValueKey('rail-otp-phone')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('rail-otp-phone')), '0780 111 2233');
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('rail-otp-send')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('rail-otp-send')));
    await t.pumpAndSettle();
    expect(server.otpBodies('send').single, {'phone': '07801112233'}, reason: 'الرقم كما عُدِّل (أرقامٌ وحدها)');
    expect(find.text('أُرسل رمز التحقّق بالواتساب إلى رقم المشترك'), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-otp-code')), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-otp-send')), findsNothing);

    server.otpConfirmReply = (422, {'success': false, 'code': 'PAY_OTP_WRONG', 'message': 'موقع الشحن: رمز التحقق غير صحيح'});
    await t.ensureVisible(find.byKey(const ValueKey('rail-otp-code')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('rail-otp-code')), '1111');
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('rail-otp-confirm')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('rail-otp-confirm')));
    await t.pumpAndSettle();
    expect(find.text('موقع الشحن: رمز التحقق غير صحيح'), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-otp-code')), findsOneWidget, reason: 'يُعاد بالرمز الصحيح');
    expect(server.activationDataCalls, reads, reason: 'لا إعادة قراءةٍ بعد رفض');

    server.otpConfirmReply = (200, {'success': true, 'verified': true, 'message': 'تم تأكيد رقم الهاتف بنجاح'});
    await t.ensureVisible(find.byKey(const ValueKey('rail-otp-code')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('rail-otp-code')), '4321');
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('rail-otp-confirm')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('rail-otp-confirm')));
    await t.pumpAndSettle();
    expect(server.otpBodies('confirm').last, {'code': '4321'});
    expect(server.activationDataCalls, reads + 1, reason: 'تُعاد قراءة النافذة');
    expect(find.byKey(const ValueKey('rail-otp-phone')), findsNothing, reason: 'لا طلب تأكيدٍ بعد الآن');
    expect(footer('أكّد رقم المشترك أوّلاً'), findsNothing);
    await submit(t, 'تجديد الآن');
    expect(server.activateBodies, hasLength(1), reason: 'يُفعَّل كالعادة');
    expect(t.takeException(), isNull);
    await drainSnack(t);
  });

  testWidgets('تأكيد رقم المشترك: رفض الموقع للرقم يظهر بنصّه والخانة تبقى للتصحيح؛ وانتهاء المهلة يعيد زرّ الإرسال',
      (t) async {
    server.activationExtra = railData(ownCards: 2, otp: true);
    server.otpSendReply = (422, {
      'success': false,
      'code': 'PAY_OTP_REFUSED',
      'message': 'موقع الشحن: لا يمكن ارسال الرمز لكون رقم الهاتف المدخل غير صحيح الرجاء التأكد من الرمز',
    });
    await open(t);
    await t.ensureVisible(find.byKey(const ValueKey('rail-otp-send')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('rail-otp-send')));
    await t.pumpAndSettle();
    expect(find.textContaining('لا يمكن ارسال الرمز لكون رقم الهاتف المدخل غير صحيح'), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-otp-code')), findsNothing);
    expect(t.widget<TextField>(find.byKey(const ValueKey('rail-otp-phone'))).enabled, isTrue);

    server.otpSendReply = (200, {'success': true, 'sent': true, 'message': 'أُرسل رمز التحقّق بالواتساب إلى رقم المشترك'});
    await t.ensureVisible(find.byKey(const ValueKey('rail-otp-send')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('rail-otp-send')));
    await t.pumpAndSettle();
    server.otpConfirmReply = (409, {'success': false, 'code': 'PAY_OTP_EXPIRED', 'message': 'لا رمز مرسَل لهذا المشترك أو انتهت مهلته — أرسل الرمز من جديد'});
    await t.ensureVisible(find.byKey(const ValueKey('rail-otp-code')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('rail-otp-code')), '4321');
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const ValueKey('rail-otp-confirm')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('rail-otp-confirm')));
    await t.pumpAndSettle();
    expect(find.textContaining('انتهت مهلته'), findsOneWidget);
    expect(find.byKey(const ValueKey('rail-otp-send')), findsOneWidget, reason: 'يُرسل من جديد');
    expect(t.takeException(), isNull);
  });

  testWidgets('طريق موقع الشحن: باقة المشترك ليست بين باقات الموقع ⇒ السبب ظاهر والزرّ مقفل', (t) async {
    server.activationExtra = railData(ownCards: 2, option: false);
    await open(t);
    expect(find.textContaining('ليست بين باقات موقع الشحن'), findsOneWidget);
    expect(footer('غير متاح عبر موقع الشحن'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('خارج الطريق (لا pay_rail): لا حقل لرقم بطاقةٍ خارجيّة أبداً', (t) async {
    server.activationExtra = cardsData(available: 3);
    await open(t);
    await t.tap(find.text('كارت (3)'));
    await t.pumpAndSettle();
    expect(find.byKey(pinKey), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('الكارت وحده: مختارٌ بلا بلاطات', (t) async {
    server.activationExtra = cardsData(credit: false, available: 2);
    await open(t);
    expect(find.text('طريقة التفعيل'), findsOneWidget);
    expect(find.text('رصيد'), findsNothing);
    expect(find.textContaining('يُسحب كارت تلقائيّاً'), findsOneWidget);
    expect(footer('تجديد بكارت'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('🚨 تعذّرت القراءة: ليست صفراً — مسموح، و«جرّب مجدّداً» يعيد',
      (t) async {
    server.activationExtra = cardsData(available: null);
    await open(t);
    await t.tap(find.text('كارت'));
    await t.pumpAndSettle();
    expect(find.text('تعذّر قراءة الكارتات — جرّب مجدّداً'), findsOneWidget);
    expect(footer('تجديد بكارت'), findsOneWidget, reason: 'غير ممنوع');

    server.activationExtra = cardsData(available: 5);
    await t.tap(find.text('تعذّر قراءة الكارتات — جرّب مجدّداً'));
    await t.pumpAndSettle();
    expect(server.activationDataCalls, 2);
    expect(find.textContaining('يُسحب كارت تلقائيّاً'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('رفض NO_CARDS: رسالة، والشيت يصير «لا كارت» ويبقى مفتوحاً',
      (t) async {
    server.activationExtra = cardsData(available: 3);
    server.activateReply = (
      409,
      {
        'success': false,
        'code': 'NO_CARDS',
        'message': 'ما عندك كارت متاح لباقة «Family»',
      }
    );
    await open(t);
    await t.tap(find.text('كارت (3)'));
    await t.pumpAndSettle();
    await submit(t, 'تجديد بكارت');
    expect(find.textContaining('ما عندك كارت متاح لباقة'), findsOneWidget);
    expect(find.textContaining('ما عندك كارت لباقة'), findsOneWidget);
    expect(footer('ما عندك كارت لهالباقة'), findsOneWidget);
    expect(find.text('طريقة التفعيل'), findsOneWidget, reason: 'لم يُغلق');
    await drainSnack(t);
    await t.tap(footer('ما عندك كارت لهالباقة'));
    await t.pumpAndSettle();
    expect(server.activateBodies, hasLength(1), reason: 'لا ضغطة ثانية');
  });

  testWidgets('🚨 رفض CARD_NOT_ALLOWED لا يقلب إلى الرصيد بصمت', (t) async {
    server.activationExtra = cardsData(available: 3);
    server.activateReply = (
      403,
      {
        'success': false,
        'code': 'CARD_NOT_ALLOWED',
        'message': 'حسابك في الساس لا يملك صلاحيّة التفعيل بالكارت',
      }
    );
    await open(t);
    await t.tap(find.text('كارت (3)'));
    await t.pumpAndSettle();
    await submit(t, 'تجديد بكارت');
    expect(
      find.text('حسابك في الساس لا يملك صلاحيّة التفعيل بالكارت'),
      findsNWidgets(2),
      reason: 'الإشعار العائم وسطر الكارت',
    );
    expect(footer('حسابك ما يسمح بالكارت'), findsOneWidget);
    await drainSnack(t);
    await t.tap(footer('حسابك ما يسمح بالكارت'));
    await t.pumpAndSettle();
    expect(server.activateBodies, hasLength(1), reason: 'لا ضغطة ثانية');

    // المدير يختار الرصيد بنفسه — ولا شيء قبل ذلك يغيّر المصدر.
    await t.tap(find.text('رصيد'));
    await t.pumpAndSettle();
    expect(footer('تجديد الآن'), findsOneWidget);
    await submit(t, 'تجديد الآن');
    expect(server.activateBodies.last.containsKey('method'), isFalse);
    await drainSnack(t);
  });
}

/// الترجمات من القرص مباشرةً — بلا `rootBundle`، فتعمل داخل وقت الاختبار.
///
/// ⚠️ `Future.value` لا `SynchronousFuture`: المكتبة تجمع المحمّلات بـ
/// `Future.wait`، وهو يُسقط قيمة المستقبل المتزامن (يُنادى قبل أن يحجز
/// خانتها) فتصل الترجمات فارغةً وتظهر المفاتيح بدل النصوص.
class _DiskLoader extends AssetLoader {
  const _DiskLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) =>
      Future.value(jsonDecode(
        File('assets/translations/${locale.languageCode}.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>);
}

/// خادمٌ وهميّ: activation-data وactivate بعقد الكارتات.
class _Server implements HttpClientAdapter {
  Map<String, dynamic> activationExtra = const {};
  (int, Map<String, dynamic>) activateReply = (200, {'success': true});
  // «تأكيد رقم المشترك بالواتساب» (pay-otp)
  (int, Map<String, dynamic>) otpSendReply = (200, {'success': true, 'sent': true, 'message': 'أُرسل رمز التحقّق بالواتساب إلى رقم المشترك'});
  (int, Map<String, dynamic>) otpConfirmReply = (200, {'success': true, 'verified': true, 'message': 'تم تأكيد رقم الهاتف بنجاح'});
  void Function()? onOtpConfirmed;
  final _requests = <RequestOptions>[];

  List<Map<String, dynamic>> otpBodies(String kind) => _requests
      .where((r) => r.path.endsWith('/pay-otp/$kind'))
      .map((r) => Map<String, dynamic>.from(r.data as Map))
      .toList();

  int get activationDataCalls =>
      _requests.where((r) => r.path.endsWith('/activation-data')).length;

  List<Map<String, dynamic>> get activateBodies => _requests
      .where((r) => r.path.endsWith('/activate'))
      .map((r) => Map<String, dynamic>.from(r.data as Map))
      .toList();

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    _requests.add(options);
    final (int, Map<String, dynamic>) reply;
    if (options.path == '/api/v2/subscribers/55/activation-data') {
      reply = (
        200,
        {
          'success': true,
          'data': {
            'user_price': 46000,
            'price_after_discount': 46000,
            'profile_name': 'Family',
            'profile_duration': '30',
            'current_balance': 0,
            'manager_balance': 0,
            ...activationExtra,
          },
        }
      );
    } else if (options.path == '/api/v2/subscribers/55/activate') {
      reply = activateReply;
    } else if (options.path == '/api/v2/subscribers/55/pay-otp/send') {
      reply = otpSendReply;
    } else if (options.path == '/api/v2/subscribers/55/pay-otp/confirm') {
      reply = otpConfirmReply;
      if (reply.$1 == 200) onOtpConfirmed?.call();
    } else {
      reply = (404, {'success': false});
    }
    return ResponseBody.fromString(
      jsonEncode(reply.$2),
      reply.$1,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
