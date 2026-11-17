import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/cards_api.dart';
import 'package:rad_mysvcs/api/subscribers_api.dart';
import 'package:rad_mysvcs/models/subscriber.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/activate_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/extend_sheet.dart';
import 'package:rad_mysvcs/screens/subscribers/sheets/pay_debt_sheet.dart';
import 'package:rad_mysvcs/services/manual_wa_prefs.dart';
import 'package:rad_mysvcs/services/op_wa_notice.dart';
import 'package:rad_mysvcs/services/permissions_service.dart';
import 'package:rad_mysvcs/services/provider_service.dart';
import 'package:rad_mysvcs/theme/colors.dart';

import 'sim_el/sim_harness.dart';

/// «هل أُرسلت رسالة العمليّة؟» (١٧ نوفمبر — المالك: «اكيد لازم يظهرله ان انرسلت رساله حتى يعرف»).
///
/// الخادم يردّ فور نجاح العمليّة ولا ينتظر الإشعار (≤ ١٫٥ث)، فنتيجة الرسالة إمّا في الردّ (`wa`) أو تُسأل بعده من
/// `GET /api/v2/subscribers/:idx/op-wa`. ما يحرسه هذا الملفّ على ورقة التسديد الحقيقيّة أمام خادمٍ وهميّ بالعقد نفسه:
///   • «أُرسلت» تُقال دائماً: مع النجاح إن حضرت، وتُكمل نصّه في مكانه إن وصلت وهو ظاهر، وإشعاراً باسم المشترك إن تأخّرت؛
///   • «لم تُرسل» بسببها حين يملك المدير ما يفعله — بعد إشعار النجاح لا فوقه؛ وما اختاره بنفسه لا يُقال (١١ يونيو)؛
///   • السؤال يقف عند أوّل جوابٍ حاسم، وعند ردٍّ لا يُقرأ، وعند انقضاء المواعيد — ولا سؤال أصلاً في الوضع اليدويّ؛
///   • الإشعار يبقى بعد إغلاق الورقة.
const _idx = '55';
const _payPath = '/api/v2/subscribers/$_idx/pay-debt';
const _waPath = '/api/v2/subscribers/$_idx/op-wa';
const _ok = 'تم التسديد بنجاح';
const _okSent = 'تم التسديد بنجاح — وأُرسلت الرسالة للمشترك';
const _lateSent = 'أُرسلت رسالة التسديد إلى «أحمد علي»';
String _failed(String reason) => 'لم تُرسل رسالة التسديد إلى «أحمد علي»: $reason';

Subscriber _sub() => Subscriber.fromJson({
      'idx': _idx,
      'username': 'user55',
      'firstname': 'أحمد',
      'lastname': 'علي',
      'phone': '07701234567',
      'notes': '-25000',
      'profile_id': 5,
      'profile_name': '20M',
    });

final _isolates = RegExp(r'[\u2066-\u2069]');

/// الإشعارات العائمة الظاهرة الآن: (النصّ بلا محارف العزل، أحمر؟) بترتيب رسمها.
List<(String, bool)> _snacks(WidgetTester t) {
  final out = <(String, bool)>[];
  final mats = find.byWidgetPredicate(
    (w) => w is Material && w.elevation == 8 && (w.color == AppColors.successFill || w.color == AppColors.errorFill),
  );
  for (final e in mats.evaluate()) {
    final m = e.widget as Material;
    final texts = find.descendant(of: find.byWidget(m), matching: find.byType(Text)).evaluate();
    final s = texts.map((x) => ((x.widget as Text).data ?? '').replaceAll(_isolates, '')).where((x) => x.isNotEmpty).join(' | ');
    out.add((s, m.color == AppColors.errorFill));
  }
  return out;
}

/// لحظة ظهور إشعار النجاح (بالساعة الوهميّة) — منها تُقاس مواعيد الإشعارات والأسئلة.
late DateTime _shownAt;

/// يتقدّم الوقت (الوهميّ) حتى [ms] من ظهور إشعار النجاح، ثمّ تُصرَّف الطلبات المعلّقة وردودها (بضع ميلّي ثوانٍ).
Future<void> _at(WidgetTester t, int ms) async {
  final left = _shownAt.add(Duration(milliseconds: ms)).difference(t.binding.clock.now());
  await t.pump(left.isNegative ? Duration.zero : left);
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 1));
  }
}

void main() {
  late SimServer server;

  /// ردود `op-wa` بالترتيب؛ بعد آخرها يتكرّر الأخير.
  void waReplies(List<Object> states) {
    var i = 0;
    server.on('GET', _waPath, (req) {
      final s = states[i < states.length ? i : states.length - 1];
      i++;
      if (s is SimReply) return s;
      if (s == 'timeout') simTimeout(req);
      final m = s is Map ? s : {'state': s, 'reason': null};
      return SimReply(200, {'success': true, 'data': m});
    });
  }

  List<RequestOptions> asks() => server.calls('GET', _waPath);

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '1', 'auth.admin_username': 'admin'});
    PermissionsService.debugSet(isEmployee: false);
    ProviderService.debugSet(null);
    ManualWaPrefs.enabled.value = false;
    OpWaNotice.pollGaps = OpWaNotice.defaultPollGaps;
  });

  tearDown(() {
    PermissionsService.debugReset();
    ManualWaPrefs.enabled.value = false;
    OpWaNotice.pollGaps = OpWaNotice.defaultPollGaps;
  });

  /// يفتح ورقة التسديد ويسدّد كامل الدين. بعده: الردّ وصل والورقة أُغلقت، و[_shownAt] لحظة ظهور إشعار النجاح.
  Future<void> pay(WidgetTester t, {Map<String, dynamic>? wa, SimVariant v = const SimVariant(390, dark: false)}) async {
    server.reply('POST', _payPath, 200, {
      'success': true,
      'message': 'تم التسديد',
      'data': {'new_balance': 0},
      if (wa != null) 'wa': wa,
    });
    await pumpSim(t, v, home: (_) => simLauncher((ctx) => showPayDebtSheet(ctx, _sub())));
    await simOpen(t);
    await t.ensureVisible(find.text('كامل الدين'));
    await t.tap(find.text('كامل الدين'));
    await t.pump();
    await t.ensureVisible(find.text('تسديد الآن'));
    await t.tap(find.text('تسديد الآن'));
    // الطلب وردّه وإغلاق الورقة — بخطواتٍ صغيرة حتى لا يُتجاوز موعد السؤال الأوّل (٠٫٩ث)
    DateTime? seen;
    for (var i = 0; i < 80; i++) {
      await t.pump(const Duration(milliseconds: 10));
      if (seen == null && _snacks(t).isNotEmpty) seen = t.binding.clock.now();
      if (seen != null && find.text('تسديد دين').evaluate().isEmpty) break;
    }
    expect(seen, isNotNull, reason: 'إشعار النجاح ظهر');
    _shownAt = seen!;
    expect(find.text('تسديد دين'), findsNothing, reason: 'الورقة أُغلقت بعد النجاح');
    expect(t.binding.clock.now().difference(_shownAt).inMilliseconds, lessThan(800), reason: 'قبل موعد السؤال الأوّل');
    expect(server.calls('POST', _payPath), hasLength(1));
  }

  group('ما يُقال وما لا يُقال', () {
    test('أُرسلت ⇒ تُقال؛ اختيار المدير ⇒ صمت؛ ما يملك له فعلاً ⇒ بسببه؛ والرمز التقنيّ لا يظهر', () async {
      await simSetUpAll();
      WhatsAppSendInfo wa(bool sent, [String? r]) => WhatsAppSendInfo(sent: sent, reason: r);
      expect(OpWaNotice.verdictOf(null), isNull);
      expect(OpWaNotice.verdictOf(wa(true))!.sent, isTrue);
      expect(OpWaNotice.verdictOf(wa(true, 'feature_off'))!.sent, isTrue, reason: 'المُرسَل مُرسَل');
      for (final silent in [
        null,
        '',
        '  ',
        'notifications_disabled',
        'no_template',
        'feature_off',
        'feature_off:sendOnPayment',
        'feature_off:sendOnActivation',
        'feature_off:subscriber_excluded',
      ]) {
        expect(OpWaNotice.verdictOf(wa(false, silent)), isNull, reason: 'صمت: $silent');
      }
    });

    testWidgets('نصوص الأسباب بالعربيّة — والرمز الداخليّ لا يخرج للمدير', (t) async {
      await pumpSim(t, const SimVariant(390, dark: false), home: (_) => const SizedBox.shrink());
      String said(String reason) {
        final v = OpWaNotice.verdictOf(WhatsAppSendInfo(sent: false, reason: reason));
        expect(v, isNotNull, reason: reason);
        expect(v!.sent, isFalse);
        return v.reason!;
      }

      expect(said('not_connected'), 'الواتساب غير متصل');
      expect(said('no_phone'), 'لا يوجد رقم هاتف للمشترك');
      expect(said('feature_off:employee_no_wa_permission'), 'ليست لديك صلاحيّة واتساب — يفعّلها المدير');
      expect(said('loopback_error:http_403'), 'تعذّر التحقّق من الواتساب الآن');
      expect(said('loopback_error:templates:timeout'), 'تعذّر التحقّق من الواتساب الآن');
      expect(said('send_failed'), 'تعذّر الإرسال');
      expect(said('no_admin_id'), 'تعذّر الإرسال');
      expect(said('Request failed with status code 500'), 'تعذّر الإرسال', reason: 'نصٌّ تقنيّ لاتينيّ لا يُعرض');
      expect(said('الرقم غير مسجّل على واتساب'), 'الرقم غير مسجّل على واتساب', reason: 'نصّ الخادم العربيّ كما هو');
      for (final r in ['not_connected', 'loopback_error:http_403', 'send_failed', 'no_admin_id', 'feature_off:employee_no_wa_permission']) {
        expect(simForbiddenMatch(said(r)), isNull, reason: 'لا رمز خام في نصّ $r');
      }
    });

    test('قراءة الخادم ⇒ نتيجةٌ بشكل ردّ العمليّة؛ وغير المحسوم بلا نتيجة', () {
      expect(const OpWaRead('sent', null).info!.sent, isTrue);
      final f = const OpWaRead('failed', 'send_failed').info!;
      expect([f.sent, f.reason], [false, 'send_failed']);
      final s = const OpWaRead('skipped', 'not_connected').info!;
      expect([s.sent, s.reason], [false, 'not_connected']);
      for (final st in ['pending', 'none', 'unreachable']) {
        expect(OpWaRead(st, null).info, isNull, reason: st);
      }
    });
  });

  group('النتيجة في ردّ العمليّة', () {
    for (final v in const [SimVariant(390, dark: false), SimVariant(320, dark: true)]) {
      testWidgets('أُرسلت ⇒ إشعارٌ واحد «تم التسديد — وأُرسلت الرسالة»، ولا سؤال للخادم @${v.tag}', (t) async {
        waReplies(['sent']);
        await pay(t, wa: {'sent': true, 'reason': null}, v: v);
        expect(_snacks(t), [(_okSent, false)]);
        await _at(t, 2900);
        expect(_snacks(t), [(_okSent, false)]);
        await _at(t, 3150);
        expect(_snacks(t), isEmpty);
        await simDrain(t);
        expect(_snacks(t), isEmpty);
        expect(asks(), isEmpty, reason: 'النتيجة حضرت في الردّ');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('لم تُرسل (الواتساب غير متصل) ⇒ النجاح أوّلاً ثمّ التحذير بعده لا فوقه، باسم المشترك', (t) async {
      waReplies(['sent']);
      await pay(t, wa: {'sent': false, 'reason': 'not_connected'});
      expect(_snacks(t), [(_ok, false)], reason: 'المال أخضر وحده أوّلاً');
      await _at(t, 2900);
      expect(_snacks(t), [(_ok, false)], reason: 'التحذير لا يغطّي النجاح');
      await _at(t, 3100);
      expect(_snacks(t), [(_failed('الواتساب غير متصل'), true)]);
      await _at(t, 7900);
      expect(_snacks(t), [(_failed('الواتساب غير متصل'), true)], reason: 'خمس ثوانٍ ليُقرأ');
      await _at(t, 8200);
      expect(_snacks(t), isEmpty);
      await simDrain(t);
      expect(asks(), isEmpty);
    });

    testWidgets('اختيار المدير (إشعار التسديد مطفأ) ⇒ النجاح وحده، بلا سؤالٍ ولا تحذير', (t) async {
      waReplies(['sent']);
      await pay(t, wa: {'sent': false, 'reason': 'feature_off:sendOnPayment'});
      expect(_snacks(t), [(_ok, false)]);
      await _at(t, 3200);
      expect(_snacks(t), isEmpty);
      await simDrain(t);
      expect(_snacks(t), isEmpty);
      expect(asks(), isEmpty);
    });

    testWidgets('نصّ الخادم العربيّ يُعرض كما هو، والرمز التقنيّ بجملةٍ عامّة', (t) async {
      await pay(t, wa: {'sent': false, 'reason': 'loopback_error:http_403'});
      await _at(t, 3100);
      expect(_snacks(t), [(_failed('تعذّر التحقّق من الواتساب الآن'), true)]);
      expect(simRawTextViolations(), isEmpty, reason: 'لا رمز خام ظاهر');
      await simDrain(t);
    });
  });

  group('النتيجة ليست في الردّ ⇒ تُسأل', () {
    testWidgets('أُرسلت وإشعار النجاح ظاهر ⇒ يكتمل نصّه في مكانه (إشعارٌ واحد دائماً)', (t) async {
      waReplies(['pending', 'sent']);
      await pay(t);
      expect(_snacks(t), [(_ok, false)]);
      expect(asks(), isEmpty, reason: 'السؤال الأوّل بعد ٠٫٩ث');
      await _at(t, 850);
      expect(asks(), isEmpty);
      await _at(t, 950);
      expect(asks(), hasLength(1));
      expect(_snacks(t), [(_ok, false)], reason: 'pending ⇒ لا تغيير');
      await _at(t, 2150);
      expect(asks(), hasLength(1), reason: 'الثاني بعد ١٫٣ث من جواب الأوّل');
      await _at(t, 2300);
      expect(asks(), hasLength(2));
      expect(_snacks(t), [(_okSent, false)], reason: 'النصّ اكتمل في المكان نفسه');
      // طلب السؤال: نوع العمليّة وكم مضى على الضغط
      final q = asks().last.queryParameters;
      expect(q['op'], 'pay');
      expect(q['age_ms'], isA<int>());
      expect(q['age_ms'] as int, greaterThanOrEqualTo(0));
      await _at(t, 5100);
      expect(_snacks(t), [(_okSent, false)], reason: 'ثلاث ثوانٍ من اكتماله');
      await _at(t, 5400);
      expect(_snacks(t), isEmpty);
      await simDrain(t);
      expect(_snacks(t), isEmpty, reason: 'لا إشعار «أُرسلت» ثانٍ');
      expect(asks(), hasLength(2), reason: 'وقف عند الجواب الحاسم');
      expect(t.takeException(), isNull);
    });

    testWidgets('أُرسلت بعد زوال إشعار النجاح ⇒ إشعارٌ صغير باسم المشترك', (t) async {
      waReplies(['pending', 'pending', 'pending', 'sent']);
      await pay(t);
      await _at(t, 4200); // ٠٫٩ + ١٫٣ + ١٫٨ = ٤٫٠ث
      expect(asks(), hasLength(3));
      expect(_snacks(t), isEmpty, reason: 'النجاح زال والنتيجة لم تُحسم');
      await _at(t, 7200); // + ٣ث
      expect(asks(), hasLength(4));
      expect(_snacks(t), [(_lateSent, false)]);
      await _at(t, 10400);
      expect(_snacks(t), isEmpty);
      await simDrain(t);
      expect(asks(), hasLength(4));
    });

    testWidgets('الواتساب غير متصل (تخطٍّ بسببه) ⇒ التحذير بعد النجاح', (t) async {
      waReplies(['pending', {'state': 'skipped', 'reason': 'not_connected'}]);
      await pay(t);
      await _at(t, 2400);
      expect(asks(), hasLength(2));
      expect(_snacks(t), [(_ok, false)], reason: 'النجاح يكمل ثوانيه أوّلاً');
      await _at(t, 3100);
      expect(_snacks(t), [(_failed('الواتساب غير متصل'), true)]);
      await simDrain(t);
      expect(asks(), hasLength(2));
    });

    testWidgets('موظّفٌ بلا صلاحيّة واتساب ⇒ يُقال له ولمن يطلبها', (t) async {
      waReplies([{'state': 'skipped', 'reason': 'feature_off:employee_no_wa_permission'}]);
      await pay(t);
      await _at(t, 3200);
      expect(_snacks(t), [(_failed('ليست لديك صلاحيّة واتساب — يفعّلها المدير'), true)]);
      await simDrain(t);
      expect(asks(), hasLength(1));
    });

    testWidgets('فشل الإرسال بنصّ الخادم ⇒ يُعرض نصّه', (t) async {
      waReplies([{'state': 'failed', 'reason': 'الرقم غير مسجّل على واتساب'}]);
      await pay(t);
      await _at(t, 3200);
      expect(_snacks(t), [(_failed('الرقم غير مسجّل على واتساب'), true)]);
      await simDrain(t);
    });

    testWidgets('اختيار المدير (تخطٍّ: الإشعار مطفأ / المشترك مستثنى) ⇒ صمتٌ بعد سؤالٍ واحد', (t) async {
      for (final r in ['feature_off:sendOnPayment', 'notifications_disabled', 'no_template', 'feature_off:subscriber_excluded']) {
        server.requests.clear();
        waReplies([{'state': 'skipped', 'reason': r}]);
        await pay(t);
        await simDrain(t);
        expect(_snacks(t), isEmpty, reason: r);
        expect(asks(), hasLength(1), reason: r);
        await t.pumpWidget(const SizedBox.shrink());
      }
    });

    testWidgets('«لا إشعار لهذه العمليّة»: مرّتان ثمّ صمت — والأولى لا تُسكت نتيجةً تلحقها', (t) async {
      waReplies(['none', 'none', 'sent']);
      await pay(t);
      await simDrain(t);
      expect(asks(), hasLength(2));
      expect(_snacks(t), isEmpty);
      await t.pumpWidget(const SizedBox.shrink());

      server.requests.clear();
      waReplies(['none', 'sent']);
      await pay(t);
      await _at(t, 2400);
      expect(asks(), hasLength(2));
      expect(_snacks(t), [(_okSent, false)]);
      await simDrain(t);
    });

    testWidgets('ردٌّ لا يُقرأ (رفض/خادمٌ بلا المسار) ⇒ لا سؤال ثانٍ؛ وانقطاع الشبكة ⇒ محاولتان', (t) async {
      // بلا معالج ⇒ 404
      await pay(t);
      await simDrain(t);
      expect(asks(), hasLength(1));
      expect(_snacks(t), isEmpty);
      await t.pumpWidget(const SizedBox.shrink());

      server.requests.clear();
      waReplies([const SimReply(409, {'success': false, 'code': 'COMPANY_ROUTE_NOT_ALLOWED', 'message': 'غير متاح'})]);
      await pay(t);
      await simDrain(t);
      expect(asks(), hasLength(1));
      expect(_snacks(t), isEmpty, reason: 'رفض القراءة لا يُعرض بعد عمليّةٍ نجحت');
      await t.pumpWidget(const SizedBox.shrink());

      server.requests.clear();
      waReplies(['timeout']);
      await pay(t);
      await simDrain(t);
      expect(asks(), hasLength(2), reason: 'شبكةٌ غائبة: محاولتان ثمّ صمت');
      expect(_snacks(t), isEmpty);
      await t.pumpWidget(const SizedBox.shrink());

      server.requests.clear();
      waReplies(['timeout', 'sent']);
      await pay(t);
      await _at(t, 2400);
      expect(_snacks(t), [(_okSent, false)], reason: 'انقطاعٌ عابر ثمّ النتيجة');
      await simDrain(t);
    });

    testWidgets('لم تُحسم أبداً ⇒ يقف عند آخر موعد (≈٤٠ث) بصمتٍ وبلا مؤقّتٍ معلّق', (t) async {
      waReplies(['pending']);
      await pay(t);
      await _at(t, 30000);
      expect(asks().length, lessThan(OpWaNotice.defaultPollGaps.length));
      await _at(t, 42000);
      expect(asks(), hasLength(OpWaNotice.defaultPollGaps.length));
      await _at(t, 100000);
      expect(asks(), hasLength(OpWaNotice.defaultPollGaps.length), reason: 'لا سؤال بعد آخر موعد');
      expect(_snacks(t), isEmpty);
      final total = OpWaNotice.defaultPollGaps.fold<Duration>(Duration.zero, (a, b) => a + b);
      expect(total.inSeconds, inInclusiveRange(35, 45));
    });
  });

  group('الوضع اليدويّ والورقة', () {
    testWidgets('«الإرسال اليدويّ»: الطلب بـskipAutoWa ولا سؤال عن رسالةٍ تلقائيّة لم تُرسل أصلاً', (t) async {
      ManualWaPrefs.enabled.value = true;
      waReplies(['sent']);
      await pay(t, wa: {'sent': false, 'reason': 'not_connected'});
      expect(server.bodies('POST', _payPath).single['skipAutoWa'], isTrue);
      expect(_snacks(t), [(_ok, false)]);
      await _at(t, 3200);
      expect(_snacks(t), isEmpty, reason: 'لا تحذير إرسالٍ تلقائيّ في الوضع اليدويّ (wa هنا عن المعاينة لا عن إرسال)');
      await _at(t, 6000);
      expect(_snacks(t), isEmpty);
      await simDrain(t);
      expect(asks(), isEmpty);
      expect(_snacks(t), isEmpty);
    });

    testWidgets('«الإرسال اليدويّ» وردٌّ بلا نتيجة: لا سؤال للخادم أيضاً', (t) async {
      ManualWaPrefs.enabled.value = true;
      waReplies(['sent']);
      await pay(t);
      expect(_snacks(t), [(_ok, false)]);
      await simDrain(t);
      expect(asks(), isEmpty, reason: 'لا رسالة تلقائيّة تُنتظر نتيجتها');
      expect(_snacks(t), isEmpty);
    });

    testWidgets('الوضع التلقائيّ لا يرسل skipAutoWa، والإشعار المتأخّر يظهر والورقة مغلقة', (t) async {
      waReplies(['pending', 'pending', 'pending', {'state': 'failed', 'reason': 'send_failed'}]);
      await pay(t);
      expect(server.bodies('POST', _payPath).single.containsKey('skipAutoWa'), isFalse);
      expect(find.text('تسديد دين'), findsNothing);
      await _at(t, 7200);
      expect(_snacks(t), [(_failed('تعذّر الإرسال'), true)]);
      expect(find.text(simOpenLabel), findsOneWidget, reason: 'على الصفحة خلف الورقة');
      await simDrain(t);
    });
  });

  group('التفعيل (المسارات الثلاثة)', () {
    const dataPath = '/api/v2/subscribers/$_idx/activation-data';
    const actPath = '/api/v2/subscribers/$_idx/activate';
    const okRenew = 'تم التجديد بنجاح';
    const okRenewSent = 'تم التجديد بنجاح — وأُرسلت الرسالة للمشترك';

    /// يضغط «تجديد الآن» وينتظر إشعار النجاح وإغلاق الورقة — ويضبط [_shownAt].
    Future<void> renew(WidgetTester t) async {
      await t.ensureVisible(find.text('تجديد الآن').last);
      await t.pumpAndSettle();
      await t.tap(find.text('تجديد الآن').last);
      DateTime? seen;
      for (var i = 0; i < 80; i++) {
        await t.pump(const Duration(milliseconds: 10));
        if (seen == null && _snacks(t).isNotEmpty) seen = t.binding.clock.now();
        if (seen != null && find.text('تجديد اشتراك').evaluate().isEmpty) break;
      }
      expect(seen, isNotNull, reason: 'إشعار النجاح ظهر');
      _shownAt = seen!;
      expect(find.text('تجديد اشتراك'), findsNothing, reason: 'الورقة أُغلقت');
    }

    Future<void> open(WidgetTester t, Subscriber sub) async {
      CardsState.reset();
      await pumpSim(t, const SimVariant(390, dark: false), home: (_) => simLauncher((c) => showActivateSheet(c, sub)));
      await simOpen(t);
      expect(find.text('تجديد اشتراك'), findsOneWidget);
    }

    testWidgets('SAS4: الردّ بلا نتيجة ⇒ يُسأل بـop=activate، و«أُرسلت» تُكمل «تم التجديد بنجاح»', (t) async {
      server.reply('GET', dataPath, 200, {
        'success': true,
        'data': {
          'user_price': 46000,
          'price_after_discount': 46000,
          'profile_name': '20M',
          'profile_duration': '30',
          'current_balance': 0,
          'manager_balance': 900000,
        },
      });
      server.reply('POST', actPath, 200, {'success': true});
      waReplies(['sent']);
      await open(t, _sub());
      await renew(t);
      expect(_snacks(t), [(okRenew, false)]);
      await _at(t, 1000);
      expect(asks().single.queryParameters['op'], 'activate');
      expect(_snacks(t), [(okRenewSent, false)]);
      await simDrain(t);
      expect(_snacks(t), isEmpty);
      expect(t.takeException(), isNull);
    });

    testWidgets('ايرث لنك: النجاح ⇒ «لم يُسجَّل الدين» ⇒ «لم تُرسل» — كلٌّ في دوره ولا يغطّي أحدها الآخر', (t) async {
      ProviderService.debugSet('earthlink');
      addTearDown(() => ProviderService.debugSet(null));
      server.reply('GET', dataPath, 200, {
        'success': true,
        'data': {
          'idx': _idx,
          'username': 'user55',
          'provider': 'earthlink',
          'profile_id': 7,
          'profile_name': 'Economy',
          'profile_duration': null,
          'units': null,
          'user_price': 35000,
          'base_price': 35000,
          'discount_amount': 0,
          'price_after_discount': 35000,
          'price_source': 'normal',
          'custom_price': null,
          'needs_repricing': false,
          'manager_cost': 20000,
          'current_balance': 0,
          'manager_balance': 250000,
          'reward_points': 0,
          'expiration': '2026-10-12 10:00:00',
          'activation_methods': {'credit': true, 'deposit': true, 'card': true},
          'cards': {'enabled': false, 'profile_id': 7, 'profile_name': 'Economy', 'available': null},
          'packages': [
            {'id': 7, 'name': 'Economy', 'price': 35000, 'cost': 20000},
          ],
          'package_change_allowed': true,
        },
      });
      const debtWarn = 'تفعّل المشترك لكن لم يُسجَّل الدين — سجّله يدويّاً';
      server.reply('POST', actPath, 200, {
        'success': true,
        'debt_write': {'ok': false, 'message': debtWarn},
      });
      waReplies([{'state': 'skipped', 'reason': 'not_connected'}]);
      await open(
        t,
        Subscriber.fromJson({'idx': _idx, 'username': 'user55', 'firstname': 'أحمد', 'lastname': 'علي', 'profile_id': 7, 'profile_name': 'Economy'}),
      );
      await t.enterText(find.widgetWithText(TextField, 'كلمة مرور الإيداع'), 'dep-pass');
      await t.pumpAndSettle();
      await renew(t);
      expect(_snacks(t), [(okRenew, false)]);
      await _at(t, 2900);
      expect(asks(), hasLength(1), reason: 'النتيجة حُسمت والنجاح ما زال ظاهراً');
      expect(_snacks(t), [(okRenew, false)]);
      await _at(t, 3100);
      expect(_snacks(t), [(debtWarn, true)], reason: 'تحذير المال قبل نتيجة الرسالة');
      await _at(t, 10900);
      expect(_snacks(t), [(debtWarn, true)], reason: 'ثماني ثوانٍ كاملة بلا غطاء');
      await _at(t, 11150);
      expect(_snacks(t), [('لم تُرسل رسالة التفعيل إلى «أحمد علي»: الواتساب غير متصل', true)]);
      await _at(t, 16300);
      expect(_snacks(t), isEmpty);
      await simDrain(t);
      expect(asks(), hasLength(1));
    });

    testWidgets('الشركة المُضافة/فايبر اكس: النتيجة في الردّ ⇒ إشعارٌ واحد، ولا سؤال', (t) async {
      const uuid = '0b0d6c4e-1a2b-4c3d-9e8f-001122334455';
      server.reply('GET', '/api/v2/subscribers/$uuid/activation-data', 200, {
        'success': true,
        'data': {
          'provider': 'fiberx',
          'idx': uuid,
          'username': 'fxu',
          'profile_name': 'لايت',
          'profile_id': 13,
          'user_price': 40000,
          'base_price': 40000,
          'price_after_discount': 40000,
          'discount_amount': 0,
          'price_source': 'sell_price',
          'custom_price': null,
          'overridden_discount': 0,
          'needs_repricing': false,
          'current_balance': 0,
          'manager_balance': 500000,
          'packages': [
            {'id': 13, 'name': 'لايت', 'price': 40000, 'cost': 35000, 'days': 30},
          ],
          'package_change_allowed': true,
        },
      });
      server.reply('POST', '/api/v2/subscribers/$uuid/activate', 200, {
        'success': true,
        'wa': {'sent': true, 'reason': null},
      });
      await open(t, Subscriber.fromJson({'idx': uuid, 'username': 'fxu', 'firstname': 'علي', 'profile_id': 5, 'profile_name': 'لايت'}));
      await renew(t);
      expect(_snacks(t), [(okRenewSent, false)]);
      await simDrain(t);
      expect(server.calls('GET', '/api/v2/subscribers/$uuid/op-wa'), isEmpty);
      expect(_snacks(t), isEmpty);
    });
  });

  group('التمديد (الربط نفسه)', () {
    const optsPath = '/api/v2/subscribers/$_idx/extension-options';
    const extendPath = '/api/v2/subscribers/$_idx/extend';

    testWidgets('نجاحٌ بلا نتيجة ⇒ يُسأل بـop=extend، و«أُرسلت» تُكمل «تم التمديد بنجاح»', (t) async {
      server.reply('GET', optsPath, 200, {
        'success': true,
        'data': {
          'idx': _idx,
          'current_profile_id': 5,
          'current_profile_name': '20M',
          'manager_balance': 500000,
          'reward_points_balance': 0,
          'packages': [
            {'id': 9, 'name': 'days', 'price': 1000, 'reward_points_required': 1, 'duration': 1},
          ],
        },
      });
      server.reply('POST', extendPath, 200, {'success': true, 'message': 'تم'});
      waReplies(['sent']);
      await pumpSim(t, const SimVariant(390, dark: false), home: (_) => simLauncher((ctx) => showExtendSheet(ctx, _sub())));
      await simOpen(t);
      await t.ensureVisible(find.text('تمديد الآن'));
      await t.tap(find.text('تمديد الآن'));
      DateTime? seen;
      for (var i = 0; i < 80; i++) {
        await t.pump(const Duration(milliseconds: 10));
        if (seen == null && _snacks(t).isNotEmpty) seen = t.binding.clock.now();
        if (seen != null && find.text('تمديد الآن').evaluate().isEmpty) break;
      }
      _shownAt = seen!;
      expect(_snacks(t), [('تم التمديد بنجاح', false)]);
      await _at(t, 1000);
      expect(asks().single.queryParameters['op'], 'extend');
      expect(_snacks(t), [('تم التمديد بنجاح — وأُرسلت الرسالة للمشترك', false)]);
      await simDrain(t);
      expect(_snacks(t), isEmpty);
    });
  });
}
