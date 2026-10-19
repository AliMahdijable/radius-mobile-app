import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:rad_mysvcs/api/ai_api.dart';
import 'package:rad_mysvcs/api/api_client.dart';
import 'package:rad_mysvcs/api/api_error_tap.dart';
import 'package:rad_mysvcs/core/widgets/sheet_scaffold.dart';
import 'package:rad_mysvcs/screens/assistant/assistant_consent_sheet.dart';
import 'package:rad_mysvcs/screens/assistant/assistant_sheet.dart';
import 'package:rad_mysvcs/services/ai_assistant_state.dart';
import 'package:rad_mysvcs/services/ai_consent.dart';

import '../text_crush_test.dart' show findCrushedText;
import 'sim_harness.dart';

/// المساعد الذكيّ (3.0.4) — نافذة «اشرحلي»/«كيف أسوّي؟» وزرّ «اشرحلي» في
/// إشعار الخطأ، كما يراها المدير: بالعربيّة وبخطّ التطبيق، بعرضَي ٣٢٠ و٣٩٠
/// وبالوضعين، أمام خادمٍ وهميّ (لا نداء للنموذج ولا للشبكة).
///
/// اللقطات في `shots/ai_assistant/` — للمراجعة (والمقارنة الصارمة متاحة:
/// `--dart-define=SIM_STRICT_GOLDENS=true`). وفي آخر الملفّ الحالات نفسها
/// بعرض ٣٢٠ وخطٍّ مكبَّر ١٫٢ (أقصى ما يسمح به التطبيق) بلا لقطة: لا فيضان
/// ولا نصّ مسحوق.
const _screen = 'ai_assistant';
const _statusPath = '/api/v2/ai/status';
const _explainPath = '/api/v2/ai/explain';
const _askPath = '/api/v2/ai/ask';
const _feedbackPath = '/api/v2/ai/feedback';

const _variants = <SimVariant>[
  SimVariant(320, dark: false),
  SimVariant(320, dark: true),
  SimVariant(390, dark: false),
  SimVariant(390, dark: true),
];

void _case(
    String state, Future<void> Function(WidgetTester t, SimVariant v) body) {
  for (final v in _variants) {
    testWidgets('$_screen/$state @${v.tag}', (t) async {
      debugDisableShadows = false;
      try {
        await body(t, v);
      } finally {
        debugDisableShadows = true;
      }
    });
  }
}

const _on = <String, dynamic>{
  'success': true,
  'enabled': true,
  'can_use': true,
  'explain': true,
  'ask': true,
  'quota': {
    'left': 7,
    'limit': 10,
    'scope': 'account',
    'resets_at': '2026-10-19T00:00:00+03:00'
  },
  'plan': {'code': 'trial', 'label': 'تجربة'},
  'upgrade_hint': null,
  'suggestions': [
    'شلون أفعّل مشترك بالكارت؟',
    'شلون أغيّر باقة مشترك فعّال؟',
    'شلون أربط الواتساب؟',
  ],
  'slogan': 'أوّل نظام وكلاء بالعراق بيه مساعد ذكي',
  'disclaimer': 'المساعد يشرح ويرشد فقط — ما ينفّذ أيّ عمليّة',
};

Map<String, dynamic> _answer({
  required String title,
  String body = '',
  List<String> steps = const [],
  String status = 'answered',
  List<String> related = const [],
  int left = 6,
  Map<String, String>? support,
}) =>
    {
      'success': true,
      'answer': {
        'title': title,
        'body': body,
        'steps': steps,
        'status': status,
        'related': related,
      },
      'support': support,
      'quota': {
        'left': left,
        'limit': 10,
        'scope': 'account',
        'resets_at': '2026-10-19T00:00:00+03:00'
      },
      'cached': false,
      'tier': 'light',
      'ref': 'c8f1a2b3',
      // الخادم يوقّع نصّ الجواب للسجلّ (يُعاد حرفيّاً مع السؤال التالي).
      'history_text': [title, if (body.isNotEmpty) body, ...steps].join('\n'),
      'history_sig': 'SigSigSigSigSigSigSigSigSigSig01',
    };

final _packageExplain = _answer(
  title: 'ما تگدر تغيّر باقة مشترك فعّال «حالاً»',
  body:
      'الساس عند شركتك يصفّر تاريخ الانتهاء إذا تغيّرت الباقة والمشترك فعّال، '
      'فالتطبيق يمنعها حتى ما يخسر المشترك أيّامه.',
  steps: const [
    'افتح المشترك واضغط «تعديل»',
    'اختار الباقة الجديدة وخلّي التوقيت «عند الانتهاء»',
    'احفظ — الباقة الجديدة تبدأ من يوم انتهاء الحاليّة',
  ],
  related: const ['تغيير الباقة', 'التمديد'],
);

/// اللقطة والفحوص ([simCheck]) — أو الفحوص وحدها بلا لقطة (الخطّ المكبَّر).
Future<void> _check(WidgetTester t, SimVariant v, String state,
    {required bool shot}) async {
  if (shot) {
    await simCheck(t, v, _screen, state);
  } else {
    expect(t.takeException(), isNull, reason: '$state: استثناء/فيضان');
    expect(simRawTextViolations(), isEmpty, reason: '$state: نصٌّ خام');
  }
  expect(findCrushedText(t), isEmpty, reason: '$state: نصٌّ مسحوق');
}

void main() {
  late SimServer server;

  setUpAll(simSetUpAll);

  setUp(() async {
    server = await simSetUp(
        secure: {'auth.admin_id': '2251', 'auth.admin_username': 'mahdi'});
    AiAssistantState.reset();
    server.reply('GET', _statusPath, 200, _on);
    AiAssistantState.debugSet(AiStatus.fromJson(_on, mode: AiMode.company));
    // وافق من قبل — نافذة الموافقة نفسها حالةٌ مستقلّة («consent»).
    AiConsent.debugAccepted = true;
  });

  tearDown(() {
    AiAssistantState.reset();
    ApiErrorTap.clear();
    AiConsent.debugReset();
  });

  Future<void> openAsk(WidgetTester t, SimVariant v) async {
    await pumpSim(t, v,
        home: (_) => simLauncher((c) => AssistantSheet.showAsk(c)));
    await simOpen(t);
  }

  Future<void> ask(WidgetTester t, String q) async {
    await t.enterText(find.byType(EditableText), q);
    await t.pump();
    await t.tap(find.byIcon(LucideIcons.sendHorizontalDir));
    await t.pumpAndSettle();
  }

  Future<void> runAskEmpty(WidgetTester t, SimVariant v,
      {bool shot = true}) async {
    await openAsk(t, v);
    expect(find.text('المساعد الذكي'), findsOneWidget);
    expect(find.text('شلون أفعّل مشترك بالكارت؟'), findsOneWidget);
    expect(find.text('باقي لك اليوم: 7'), findsOneWidget);
    expect(server.calls('POST', _askPath), isEmpty,
        reason: 'لا سؤال قبل أن يسأل المدير');
    await _check(t, v, 'ask_empty', shot: shot);
  }

  Future<void> runAskThread(WidgetTester t, SimVariant v,
      {bool shot = true}) async {
    final replies = <Map<String, dynamic>>[
      _answer(
        title: 'التفعيل بالكارت من نافذة التفعيل',
        body:
            'إذا شركتك مفعّلة الكارتات، تختار «كارت» بطريقة الدفع والتطبيق يأخذ أوّل كارت متوفّر لنفس الباقة.',
        steps: const [
          'افتح المشترك واضغط «تفعيل»',
          'اختار طريقة الدفع «كارت»',
          'أكّد — يظهر لك آخر أربع أرقام من الكارت',
        ],
        related: const ['الكارتات'],
        left: 6,
      ),
      _answer(
        title: 'إذا ماكو كارت لنفس الباقة',
        body:
            'التطبيق يرفض التفعيل ويگلك ماكو كارتات للباقة — ما يُخصم شي من رصيدك.',
        left: 5,
      ),
      _answer(
        title: 'ما أعرف بالضبط',
        body: 'سعر الكارت بالجملة تحدّده الشركة المزوّدة، وما عندي معلومته.',
        status: 'unknown',
        left: 4,
        // بقيم المالك كما يخزّنها الإنتاج: يوزر تلغرام ورقمٌ دوليّ بلا رابط.
        support: const {
          'telegram': 'mysvcs_support',
          'whatsapp': '9647700000000'
        },
      ),
    ];
    var n = 0;
    server.on('POST', _askPath, (_) => SimReply(200, replies[n++]));
    await openAsk(t, v);
    await ask(t, 'شلون أفعّل مشترك بالكارت؟');
    await ask(t, 'وإذا خلصت الكارتات؟');
    await ask(t, 'بيش سعر الكارت بالجملة؟');
    final bodies = server.bodies('POST', _askPath);
    expect(bodies, hasLength(3));
    expect(bodies[2]['history'], hasLength(4),
        reason: 'الدوران السابقان سياقٌ للثالث');
    expect(find.text('تلغرام'), findsOneWidget);
    expect(find.text('باقي لك اليوم: 4'), findsOneWidget);
    // تقييمٌ لكلّ جواب (الأوّل قد يخرج من القائمة الكسولة بالخطّ المكبَّر).
    expect(find.text('مفيد'), findsWidgets);
    await _check(t, v, 'ask_thread', shot: shot);
  }

  Future<void> runConsent(WidgetTester t, SimVariant v,
      {bool shot = true}) async {
    AiConsent.debugReset();
    await openAsk(t, v);
    expect(find.byType(AssistantConsentSheet), findsOneWidget);
    expect(find.text('موافق، كمّل'), findsOneWidget);
    expect(find.text('مو هسه'), findsOneWidget);
    expect(server.requests.where((r) => r.method == 'POST'), isEmpty,
        reason: 'لا طلب قبل الموافقة');
    await _check(t, v, 'consent', shot: shot);
  }

  Future<void> runExplainFeedback(WidgetTester t, SimVariant v,
      {bool shot = true}) async {
    server.reply('POST', _explainPath, 200, _packageExplain);
    server.reply('POST', _feedbackPath, 200, {'success': true, 'saved': true});
    await pumpSim(t, v,
        home: (_) => simLauncher((c) => AssistantSheet.showExplain(
              c,
              const ExplainRequest(
                code: 'PACKAGE_CHANGE_ACTIVE_FORBIDDEN',
                message:
                    'تغيير باقة مشترك فعّال حالاً يصفّر تاريخ انتهائه — اختر «عند الانتهاء»',
                screen: 'package_change',
                httpStatus: 403,
              ),
            )));
    await simOpen(t);
    await t.tap(find.text('مفيد'));
    await t.pumpAndSettle();
    expect(server.bodies('POST', _feedbackPath).single,
        {'ref': 'c8f1a2b3', 'helpful': true});
    expect(find.text('وصلنا رأيك — شكراً'), findsOneWidget);
    await _check(t, v, 'explain_feedback', shot: shot);
  }

  Future<void> runExplainAnswer(WidgetTester t, SimVariant v,
      {bool shot = true}) async {
    server.reply('POST', _explainPath, 200, _packageExplain);
    await pumpSim(t, v,
        home: (_) => simLauncher((c) => AssistantSheet.showExplain(
              c,
              const ExplainRequest(
                code: 'PACKAGE_CHANGE_ACTIVE_FORBIDDEN',
                message:
                    'تغيير باقة مشترك فعّال حالاً يصفّر تاريخ انتهائه — اختر «عند الانتهاء»',
                screen: 'package_change',
                httpStatus: 403,
                context: {
                  'action': 'package_change',
                  'package_change_mode': 'now'
                },
              ),
            )));
    await simOpen(t);
    final sent = server.bodies('POST', _explainPath).single;
    expect(sent['code'], 'PACKAGE_CHANGE_ACTIVE_FORBIDDEN');
    expect(sent['screen'], 'package_change');
    expect(find.text('اسأل سؤال ثاني'), findsOneWidget);
    expect(find.text('نسخ الجواب'), findsOneWidget);
    await _check(t, v, 'explain_answer', shot: shot);
  }

  Future<void> runQuotaExhausted(WidgetTester t, SimVariant v,
      {bool shot = true}) async {
    final hint = Map<String, dynamic>.from(_on)
      ..['upgrade_hint'] = 'باقة الأعمال: 100 سؤال باليوم';
    AiAssistantState.debugSet(AiStatus.fromJson(hint, mode: AiMode.company));
    server.reply('POST', _askPath, 429, {
      'success': false,
      'code': 'AI_QUOTA_EXHAUSTED',
      'message': 'خلصت أسئلة اليوم — ترجع باچر أو رقّي باقتك',
      'quota': {
        'left': 0,
        'limit': 10,
        'scope': 'account',
        'resets_at': '2026-10-19T00:00:00+03:00'
      },
    });
    await openAsk(t, v);
    await ask(t, 'شلون أسدّد دين مشترك؟');
    expect(find.byType(EditableText), findsNothing,
        reason: 'الحقل يُقفل بعد نفاد الحصّة');
    expect(find.text('باقي لك اليوم: 0'), findsOneWidget);
    await _check(t, v, 'quota_exhausted', shot: shot);
  }

  // ─── زرّ «اشرحلي» في إشعار الخطأ ───

  Future<void> failThenSnack(WidgetTester t, SimVariant v,
      {required String message}) async {
    server.reply('POST', '/api/v2/subscribers/77/activate', 409, {
      'success': false,
      'code': 'CREDIT_NOT_ALLOWED',
      'message': message,
    });
    await pumpSim(t, v,
        home: (_) => simLauncher((c) async {
              final r = await ApiClient.dio.post<Map<String, dynamic>>(
                '/api/v2/subscribers/77/activate',
                data: {
                  'paymentType': 'cash',
                  'activationData': 'x',
                  'method': 'credit'
                },
              );
              if (!c.mounted) return;
              showSheetSnack(c, '${r.data?['message']}', isError: true);
            }));
    await t.tap(find.text(simOpenLabel));
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> runSnackInline(WidgetTester t, SimVariant v,
      {bool shot = true}) async {
    await failThenSnack(t, v, message: 'حسابك ما يسمح بالتفعيل بالرصيد');
    expect(find.text('اشرحلي'), findsOneWidget);
    await _check(t, v, 'snack_inline', shot: shot);
    await simDrain(t);
  }

  Future<void> runSnackStacked(WidgetTester t, SimVariant v,
      {bool shot = true}) async {
    await failThenSnack(t, v,
        message:
            'الساس رفض التفعيل بالرصيد لهذا الحساب — صلاحيّة «التفعيل بالرصيد» '
            'مقفلة عند الشركة، اطلبها منهم أو فعّل بالكارت');
    expect(find.text('اشرحلي'), findsOneWidget);
    await _check(t, v, 'snack_stacked', shot: shot);
    await simDrain(t);
  }

  final scenarios =
      <String, Future<void> Function(WidgetTester, SimVariant, {bool shot})>{
    'consent': runConsent,
    'ask_empty': runAskEmpty,
    'ask_thread': runAskThread,
    'explain_answer': runExplainAnswer,
    'explain_feedback': runExplainFeedback,
    'quota_exhausted': runQuotaExhausted,
    'snack_inline': runSnackInline,
    'snack_stacked': runSnackStacked,
  };
  scenarios.forEach((state, run) => _case(state, (t, v) => run(t, v)));

  // ─── خطٌّ مكبَّر (١٫٢ — سقف التطبيق) بأضيق عرض: لا فيضان ولا سحق ───
  group('خطّ ١٫٢ @w320', () {
    scenarios.forEach((state, run) {
      testWidgets(state, (t) async {
        t.platformDispatcher.textScaleFactorTestValue = 1.2;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await run(t, const SimVariant(320, dark: false), shot: false);
      });
    });
  });
}
