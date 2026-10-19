import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rad_mysvcs/api/ai_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/api_error_tap.dart';
import 'package:rad_mysvcs/core/widgets/explain_action.dart';
import 'package:rad_mysvcs/core/widgets/sheet_scaffold.dart';
import 'package:rad_mysvcs/screens/account/account_widgets.dart';
import 'package:rad_mysvcs/screens/assistant/assistant_sheet.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/ai_consent.dart';

import 'sim_el/sim_harness.dart';

/// «اشرحلي» في إشعار الخطأ — يظهر فقط حين: خطأٌ (لا نجاح) + طلبٌ (صريح أو
/// مستنتجٌ من ردّ الخادم المرفوض) + الخادم يقول إنّ المساعد مفتوح. والمساعد
/// مطفأً (الافتراضيّ) فالإشعار كما كان حرفيّاً: لا زرّ ولا مدّةٌ أطول.
void main() {
  const v = SimVariant(390, dark: false);
  const activatePath = '/api/v2/subscribers/77/activate';
  const explainPath = '/api/v2/ai/explain';
  const statusPath = '/api/v2/ai/status';
  const serverMsg = 'حسابك ما يسمح بالتفعيل بالرصيد';

  const on = <String, dynamic>{
    'success': true,
    'enabled': true,
    'can_use': true,
    'explain': true,
    'ask': true,
    'quota': {'left': 7, 'limit': 10},
  };

  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(secure: {'auth.admin_id': '2251'});
    AiAssistantState.reset();
    AiConsent.debugAccepted = true; // الموافقة في assistant_sheet_test
    server.reply('POST', activatePath, 409, {
      'success': false,
      'code': 'CREDIT_NOT_ALLOWED',
      'message': serverMsg,
    });
    server.reply('POST', explainPath, 200, {
      'success': true,
      'answer': {
        'title': 'الساس ما يسمح لحسابك بالتفعيل بالرصيد',
        'body': 'صلاحيّة التفعيل بالرصيد مقفلة عند شركتك.',
        'steps': ['فعّل بالكارت', 'أو اطلب الصلاحيّة من الشركة'],
        'status': 'needs_support',
        'related': [],
      },
      'quota': {'left': 6, 'limit': 10},
    });
  });

  tearDown(() {
    AiAssistantState.reset();
    ApiErrorTap.clear();
    AiConsent.debugReset();
  });

  void setOn([Map<String, dynamic> s = on]) {
    server.reply('GET', statusPath, 200, s);
    AiAssistantState.debugSet(AiStatus.fromJson(s, mode: AiMode.company));
  }

  /// يطلب التفعيل (يرفضه الخادم) ثمّ يعرض [shown] إشعارَ خطأ كما تفعل الشيتات.
  Future<void> failAndSnack(
    WidgetTester t, {
    String? shown,
    bool isError = true,
    ExplainRequest? explain,
    bool autoExplain = true,
    bool callServer = true,
  }) async {
    await pumpSim(t, v,
        home: (_) => simLauncher((c) async {
              String msg = shown ?? serverMsg;
              if (callServer) {
                final r = await ApiClient.dio
                    .post<Map<String, dynamic>>(activatePath, data: {
                  'paymentType': 'cash',
                  'activationData': 'x',
                  'method': 'credit'
                });
                msg = shown ?? '${r.data?['message']}';
              }
              if (!c.mounted) return;
              showSheetSnack(c, msg,
                  isError: isError, explain: explain, autoExplain: autoExplain);
            }));
    await t.tap(find.text(simOpenLabel));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Finder pill() => find.text('اشرحلي');

  testWidgets('🚨 المساعد مطفأ (الافتراضيّ): لا زرّ، والمدّة ٣ث كما كانت',
      (t) async {
    server.reply('GET', statusPath, 200, {'success': true, 'enabled': false});
    AiAssistantState.debugSet(
        const AiStatus(enabled: false, mode: AiMode.company));
    await failAndSnack(t);
    expect(find.text(serverMsg), findsOneWidget);
    expect(pill(), findsNothing);
    await t.pump(const Duration(milliseconds: 2800));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text(serverMsg), findsNothing, reason: 'زال عند ٣ث');
    expect(server.calls('POST', explainPath), isEmpty);
    await simDrain(t);
  });

  testWidgets('مفتوح + خطأ الخادم الذي يعرضه الإشعار ⇒ «اشرحلي»، ويبقى ٦ث',
      (t) async {
    setOn();
    await failAndSnack(t);
    expect(pill(), findsOneWidget);
    await t.pump(const Duration(seconds: 4));
    expect(find.text(serverMsg), findsOneWidget, reason: 'لا يزول قبل ٦ث');
    await t.pump(const Duration(seconds: 3));
    expect(find.text(serverMsg), findsNothing);
    await simDrain(t);
  });

  testWidgets('رسالةٌ محلّيّة (لا ردّ مرفوض) ⇒ لا زرّ', (t) async {
    setOn();
    await failAndSnack(t, shown: 'أدخل المبلغ', callServer: false);
    expect(find.text('أدخل المبلغ'), findsOneWidget);
    expect(pill(), findsNothing);
    await simDrain(t);
  });

  testWidgets('إشعار نجاح ⇒ لا زرّ ولو مع طلبٍ صريح', (t) async {
    setOn();
    await failAndSnack(t,
        shown: 'تمّ التفعيل',
        isError: false,
        explain: const ExplainRequest(code: 'X_Y', screen: 'activate'));
    expect(pill(), findsNothing);
    await simDrain(t);
  });

  testWidgets('طلبٌ صريح ⇒ الزرّ؛ وautoExplain:false يمنع الاستنتاج',
      (t) async {
    setOn();
    await failAndSnack(t,
        shown: 'تعذّر الحفظ',
        callServer: false,
        explain: const ExplainRequest(code: 'SAVE_FAILED', screen: 'settings'));
    expect(pill(), findsOneWidget);
    await simDrain(t);
    await failAndSnack(t, autoExplain: false);
    expect(pill(), findsNothing);
    await simDrain(t);
  });

  testWidgets('موظّفٌ بلا صلاحيّة المساعد ⇒ لا زرّ', (t) async {
    setOn(const {
      'success': true,
      'enabled': true,
      'can_use': false,
      'reason': 'no_permission'
    });
    await failAndSnack(t);
    expect(pill(), findsNothing);
    await simDrain(t);
  });

  testWidgets(
      'الحالة تصل بعد الإشعار (أوّل خطأ في الجلسة) ⇒ يُسأل عنها ويظهر الزرّ',
      (t) async {
    server.reply('GET', statusPath, 200, on);
    expect(AiAssistantState.gate.value, isNull);
    await failAndSnack(t);
    await t.pump(const Duration(milliseconds: 300));
    expect(server.calls('GET', statusPath), hasLength(1));
    expect(pill(), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('لا خطأ يُشرح ⇒ لا سؤال عن الحالة أصلاً', (t) async {
    server.reply('GET', statusPath, 200, on);
    await failAndSnack(t, shown: 'أدخل المبلغ', callServer: false);
    await t.pump(const Duration(milliseconds: 300));
    expect(server.calls('GET', statusPath), isEmpty);
    await simDrain(t);
  });

  testWidgets(
      'النقر ⇒ نافذة «اشرحلي» بالخطأ كما ظهر، والطلب برمزه وشاشته وعمليّته',
      (t) async {
    setOn();
    await failAndSnack(t);
    await t.tap(pill());
    await t.pumpAndSettle();
    expect(find.byType(AssistantSheet), findsOneWidget);
    expect(find.text(serverMsg), findsOneWidget,
        reason: 'الرسالة كما ظهرت في أعلى النافذة');
    final body = server.bodies('POST', explainPath).single;
    expect(body['code'], 'CREDIT_NOT_ALLOWED');
    expect(body['screen'], 'activate');
    expect(body['http_status'], 409);
    expect(body['context'], {'action': 'activate', 'method': 'credit'});
    expect(find.text('الساس ما يسمح لحسابك بالتفعيل بالرصيد'), findsOneWidget);
    expect(find.text('اسأل سؤال ثاني'), findsOneWidget);
    await simDrain(t);
  });

  testWidgets('قارئ الشاشة: «اشرحلي» زرٌّ مسمّى له نقرة', (t) async {
    final semantics = t.ensureSemantics();
    setOn();
    await failAndSnack(t);
    final node = t.getSemantics(
        find.bySemanticsLabel('اشرحلي هذا الخطأ — المساعد الذكي'));
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(data.flagsCollection.isButton, isTrue);
    semantics.dispose();
    await simDrain(t);
  });

  group('شريط شاشات الحساب (showAccountSnack)', () {
    Future<void> accountSnack(WidgetTester t) async {
      ApiErrorTap.debugNote(ApiErrorNote(
        at: DateTime.now(),
        method: 'POST',
        path: '/api/account/companies',
        status: 403,
        code: 'company-limit',
        message: 'وصلت حدّ الشركات في باقتك',
      ));
      await pumpSim(t, v,
          home: (_) => Scaffold(
                body: Builder(
                  builder: (c) => Center(
                    child: TextButton(
                      onPressed: () => showAccountSnack(
                          c, 'وصلت حدّ الشركات في باقتك',
                          error: true),
                      child: const Text(simOpenLabel),
                    ),
                  ),
                ),
              ));
      await t.tap(find.text(simOpenLabel));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
    }

    testWidgets('مفتوح ⇒ الزرّ داخل الشريط', (t) async {
      setOn();
      await accountSnack(t);
      expect(pill(), findsOneWidget);
      await t.tap(pill());
      await t.pumpAndSettle();
      expect(find.byType(AssistantSheet), findsOneWidget);
      expect(server.bodies('POST', explainPath).single['screen'], 'companies');
      await simDrain(t);
    });

    testWidgets('مطفأ ⇒ الشريط كما كان', (t) async {
      AiAssistantState.debugSet(
          const AiStatus(enabled: false, mode: AiMode.company));
      server.reply('GET', statusPath, 200, {'success': true, 'enabled': false});
      await accountSnack(t);
      expect(find.text('وصلت حدّ الشركات في باقتك'), findsOneWidget);
      expect(pill(), findsNothing);
      await simDrain(t);
    });
  });

  // مراجعة: شاشاتٌ تبني شريطها بنفسها (التحويل، ربط الواتساب، الموظّفون) —
  // عبر explainableSnackBar.
  group('شريطٌ تبنيه الشاشة (explainableSnackBar)', () {
    Future<void> screenSnack(WidgetTester t,
        {bool error = true, bool callServer = true, String? shown}) async {
      await pumpSim(t, v,
          home: (_) => simLauncher((c) async {
                String msg = shown ?? serverMsg;
                if (callServer) {
                  final r = await ApiClient.dio
                      .post<Map<String, dynamic>>(activatePath, data: {
                    'paymentType': 'cash',
                    'activationData': 'x',
                    'method': 'credit'
                  });
                  msg = shown ?? '${r.data?['message']}';
                }
                if (!c.mounted) return;
                ScaffoldMessenger.of(c).showSnackBar(explainableSnackBar(
                  c,
                  msg,
                  error: error,
                  backgroundColor: Colors.red,
                ));
              }));
      await t.tap(find.text(simOpenLabel));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('مفتوح + رفض الخادم ⇒ «اشرحلي» يفتح المساعد بالخطأ نفسه',
        (t) async {
      setOn();
      await screenSnack(t);
      expect(find.text(serverMsg), findsOneWidget);
      expect(pill(), findsOneWidget);
      await t.tap(pill());
      await t.pumpAndSettle();
      expect(find.byType(AssistantSheet), findsOneWidget);
      expect(server.bodies('POST', explainPath).single['code'],
          'CREDIT_NOT_ALLOWED');
      await simDrain(t);
    });

    testWidgets('مطفأ ⇒ الشريط نصٌّ وحده كما كان', (t) async {
      server.reply('GET', statusPath, 200, {'success': true, 'enabled': false});
      AiAssistantState.debugSet(
          const AiStatus(enabled: false, mode: AiMode.company));
      await screenSnack(t);
      expect(find.text(serverMsg), findsOneWidget);
      expect(pill(), findsNothing);
      await simDrain(t);
    });

    testWidgets('نجاح أو رسالةٌ محلّيّة ⇒ بلا زرّ', (t) async {
      setOn();
      await screenSnack(t, error: false);
      expect(pill(), findsNothing);
      await simDrain(t);
    });
  });
}
