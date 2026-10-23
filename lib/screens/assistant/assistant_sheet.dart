// `hide TextDirection`: الحزمة تصدّر نوع intl الذي يحجب نوع dart:ui.
import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/ai_api.dart';
import '../../core/platform/store_policy.dart';
import '../../core/util/clipboard_helper.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/permission_locked.dart' show LockedStyle;
import '../../core/widgets/sheet_scaffold.dart';
import '../../services/ai_assistant_state.dart';
import '../../services/ai_consent.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'assistant_consent_sheet.dart';
import '../../core/widgets/app_sheet.dart';

/// نافذة المساعد الذكيّ — «اشرحلي» و«كيف أسوّي؟» في ورقةٍ واحدة.
///
/// • «اشرحلي» ([showExplain]): الخطأ كما ظهر، ثمّ شرحه لهذا المدير (مزوّده
///   ودوره وصلاحيّاته — يعرفها الخادم من الجلسة) وما يفعله الآن خطوةً خطوة.
///   و«اسأل سؤال ثاني» ينقلها إلى المحادثة والخطأ سياقٌ لها.
/// • «كيف أسوّي؟» ([showAsk]): محادثةٌ قصيرة عن ميزات التطبيق الحقيقيّة.
///
/// ⚠️ **لا عمليّة تُنفَّذ من هنا** — أجوبةٌ فقط. والمحادثة في الذاكرة وحدها:
/// تُمحى بإغلاق النافذة ولا تُحفظ على الهاتف (والخادم يحفظ نسختها المخفيّة مع
/// الجواب مدّةً محدودة — ٢٤ ساعة، حتى ٣٠ يوماً — كما تقول الموافقة). رسائل الخادم
/// (الحصّة، الصلاحيّة) تُعرض داخل النافذة لا إشعاراً، ودعوة الترقية لا تظهر
/// على آيفون أبداً ([StorePolicy.hidePurchaseFlows]).
///
/// وقبل أوّل فتحٍ على الجهاز موافقةٌ صريحة ([AiConsent]): النصّ يذهب لمزوّد
/// ذكاءٍ اصطناعيّ خارجيّ — فلا نافذة ولا طلب قبل «موافق». ولكلّ جوابٍ «مفيد» /
/// «الجواب غلط» (`POST /api/v2/ai/feedback` بمرجعه وحده).
class AssistantSheet extends StatefulWidget {
  const AssistantSheet({super.key, this.explain, this.screen});

  /// الخطأ المطلوب شرحه — `null` = «كيف أسوّي؟».
  final ExplainRequest? explain;

  /// الشاشة التي فُتحت منها (من قائمة [ExplainRequest.aiScreens]).
  final String? screen;

  static Future<void> showExplain(
          BuildContext context, ExplainRequest request) =>
      _open(context, AssistantSheet(explain: request, screen: request.screen));

  static Future<void> showAsk(BuildContext context, {String? screen}) =>
      _open(context, AssistantSheet(screen: screen));

  static Future<void> _open(BuildContext context, Widget sheet) async {
    // الموافقة أوّلاً (مرّةً على الجهاز) — «اشرحلي» يطلب لحظة فتح النافذة،
    // فلا نافذة قبلها. الرفض لا يُحفظ ولا يُرسل شيئاً.
    if (!await AiConsent.accepted()) {
      if (!context.mounted || !await showAssistantConsentSheet(context)) return;
      await AiConsent.accept();
    }
    if (!context.mounted) return;
    await showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (_) => sheet,
    );
  }

  @override
  State<AssistantSheet> createState() => _AssistantSheetState();
}

enum _Mode { explain, ask }

/// سؤالٌ وجوابه في المحادثة. `reply == null` = ينتظر.
class _Exchange {
  _Exchange(this.question);
  final String question;
  AiReply? reply;
  bool get waiting => reply == null;
}

class _AssistantSheetState extends State<AssistantSheet> {
  late _Mode _mode = widget.explain != null ? _Mode.explain : _Mode.ask;

  AiReply? _explainReply;
  late bool _explainBusy = widget.explain != null;
  bool _started = false;

  final _exchanges = <_Exchange>[];

  /// خطأ «اشرحلي» وجوابه — أوّل المحادثة حين ينتقل المدير للسؤال.
  bool _seeded = false;

  /// رفضٌ لا فائدة بعده من سؤالٍ آخر (الحصّة، الصلاحيّة، أُطفئ) — الحقل يُقفل.
  AiFailure? _blocked;

  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  String get _lang => context.locale.languageCode;

  bool get _busy => _exchanges.isNotEmpty && _exchanges.last.waiting;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.explain != null) _fetchExplain();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// «أعد المحاولة» بعد تعذّرٍ عابر.
  Future<void> _retryExplain() {
    setState(() {
      _explainBusy = true;
      _explainReply = null;
    });
    return _fetchExplain();
  }

  Future<void> _fetchExplain() async {
    final reply = await AiApi.explain(widget.explain!, lang: _lang);
    if (!mounted) return;
    _afterReply(reply);
    setState(() {
      _explainBusy = false;
      _explainReply = reply;
    });
  }

  void _afterReply(AiReply r) {
    AiAssistantState.applyQuota(r.quota);
    final f = r.failure;
    if (f == null) return;
    if (f.isOff) AiAssistantState.turnOff();
    if (f.blocksInput) _blocked = f;
  }

  void _switchToAsk({String? prefill}) {
    setState(() {
      _mode = _Mode.ask;
      _seeded = _explainReply?.answer != null;
      if (prefill != null) _input.text = prefill;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  /// ما سبق من المحادثة (الهاتف لا يحفظه؛ يُرسل مع السؤال التالي): سؤال المدير
  /// نصّاً، وجواب المساعد كما وقّعه الخادم حرفيّاً مع توقيعه — والجواب بلا
  /// توقيع (خادمٌ أقدم) لا يُرسل ولا سؤاله ([AiApi.trimHistory]).
  List<AiTurn> _history() {
    final seed = _explainReply;
    return [
      if (_seeded && seed != null && seed.signed) ...[
        AiTurn.user(_explainContextText()),
        AiTurn.assistant(seed.historyText!, sig: seed.historySig),
      ],
      for (final e in _exchanges)
        if (e.reply case final r? when r.signed) ...[
          AiTurn.user(e.question),
          AiTurn.assistant(r.historyText!, sig: r.historySig),
        ],
    ];
  }

  String _explainContextText() => 'ai.explain_context'
      .tr(namedArgs: {'msg': (widget.explain?.message ?? '').trim()});

  Future<void> _send([String? text]) async {
    final q = (text ?? _input.text).trim();
    if (q.length < 3 || _busy || _blocked != null) return;
    HapticFeedback.selectionClick();
    final history = _history();
    final ex = _Exchange(q);
    setState(() {
      _exchanges.add(ex);
      if (text == null) _input.clear();
    });
    _scrollToEnd();
    final reply = await AiApi.ask(q,
        history: history, screen: widget.screen, lang: _lang);
    if (!mounted) return;
    _afterReply(reply);
    setState(() => ex.reply = reply);
    _scrollToEnd();
  }

  void _retry(_Exchange e) {
    if (_busy) return;
    setState(() => _exchanges.remove(e));
    _send(e.question);
  }

  void _prefillRelated(String feature) {
    final text = 'ai.related_prefill'.tr(namedArgs: {'x': feature});
    if (_mode == _Mode.explain) {
      _switchToAsk(prefill: text);
      return;
    }
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    _focus.requestFocus();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _launch(Uri uri) async {
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* يُعرض الخطأ أدناه */}
    if (!ok && mounted) {
      showSheetSnack(context, 'account.contact_failed'.tr(),
          isError: true, autoExplain: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return ValueListenableBuilder<AiStatus?>(
      valueListenable: AiAssistantState.gate,
      builder: (context, status, _) {
        final asking = _mode == _Mode.ask;
        return DesignSheet(
          header: SheetHeaderBar(
            icon: LucideIcons.sparkles,
            title: 'ai.title'.tr(),
            subtitle: 'ai.slogan'.tr(),
            onClose: () => Navigator.of(context).pop(),
          ),
          scrollable: !asking,
          bodyPadding: asking
              ? EdgeInsets.zero
              : const EdgeInsets.fromLTRB(Sp.xl, Sp.lg, Sp.xl, Sp.lg),
          body: asking ? _conversation(status) : _explainBody(status),
          footer: asking ? _composer(status) : _explainFooter(status),
        );
      },
    );
  }

  // ───────────── «اشرحلي» ─────────────

  Widget _explainBody(AiStatus? status) {
    final req = widget.explain!;
    final reply = _explainReply;
    final answer = reply?.answer;
    final failure = reply?.failure;
    final shown = (req.message ?? '').trim();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetSection(
          label: 'ai.you_saw'.tr(),
          child:
              _ErrorCard(message: shown.isEmpty ? 'ai.no_message'.tr() : shown),
        ),
        const SizedBox(height: Sp.lg),
        Semantics(
          liveRegion: true,
          container: true,
          child: _explainBusy
              ? const _Thinking()
              : answer != null
                  ? _AnswerCard(
                      answer: answer,
                      onRelated:
                          (status?.canAsk ?? false) ? _prefillRelated : null,
                    )
                  : failure != null
                      ? _FailureCard(
                          failure: failure,
                          upgradeHint: status?.upgradeHint,
                          onRetry: failure.retryable ? _retryExplain : null,
                        )
                      : const SizedBox.shrink(),
        ),
        if (answer != null) ...[
          const SizedBox(height: Sp.md),
          _AnswerActions(
            answer: answer,
            support: reply?.support,
            onLaunch: _launch,
            feedbackRef: reply?.ref,
          ),
        ],
        const SizedBox(height: Sp.lg),
        _FootNote(quota: status?.quota),
      ],
    );
  }

  Widget? _explainFooter(AiStatus? status) {
    if (!(status?.canAsk ?? false) || _blocked != null) return null;
    return SheetFooterBar(
      label: 'ai.ask_more'.tr(),
      icon: LucideIcons.messageCircleQuestion,
      onPressed: _explainBusy ? null : () => _switchToAsk(),
      enabled: !_explainBusy,
    );
  }

  // ───────────── «كيف أسوّي؟» ─────────────

  Widget _conversation(AiStatus? status) {
    final seed = _explainReply?.answer;
    final items = <Widget>[
      if (_seeded && seed != null) ...[
        _UserBubble(text: _explainContextText()),
        _AnswerCard(answer: seed, onRelated: _prefillRelated),
      ],
      if (_exchanges.isEmpty && !_seeded)
        _EmptyState(
          // اقتراحات الخادم بالعربيّة وحدها — لا تظهر في واجهةٍ إنجليزيّة.
          suggestions:
              _lang == 'ar' ? (status?.suggestions ?? const []) : const [],
          onPick: (s) => _send(s),
        ),
      for (final e in _exchanges) ...[
        _UserBubble(text: e.question),
        if (e.waiting)
          const _Thinking()
        else if (e.reply!.answer case final a?) ...[
          _AnswerCard(answer: a, onRelated: _prefillRelated),
          if ((a.wantsSupport && e.reply!.support != null) ||
              e.reply!.ref != null)
            _AnswerActions(
              answer: a,
              support: e.reply!.support,
              onLaunch: _launch,
              withCopy: false,
              feedbackRef: e.reply!.ref,
            ),
        ] else
          _FailureCard(
            failure: e.reply!.failure!,
            upgradeHint: status?.upgradeHint,
            onRetry:
                e.reply!.failure!.retryable && !e.reply!.failure!.blocksInput
                    ? () => _retry(e)
                    : null,
          ),
      ],
    ];
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.lg),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: Sp.md),
      itemBuilder: (_, i) => items[i],
    );
  }

  Widget _composer(AiStatus? status) {
    final blocked = _blocked;
    // شاشةٌ قصيرة ولوحة المفاتيح مفتوحة (آيفون SE: ~٣٠٠ نقطة ظاهرة) ⇒ سطر
    // التنبيه والحصّة يُخفى أثناء الكتابة فتبقى المحادثة مقروءة؛ ويعود بإغلاقها.
    final mq = MediaQuery.of(context);
    final roomy = mq.size.height - mq.viewInsets.bottom >= 420;
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.dividerStrong)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // رفضٌ يقفل الحقل (الحصّة، الصلاحيّة): رسالته في المحادثة جواباً
          // للسؤال، والحقل هنا مقفلٌ بسطرها — لا بطاقةٌ ثانية بالكلام نفسه.
          if (blocked != null)
            _InputBox(
              controller: _input,
              focusNode: _focus,
              onSubmit: () {},
              disabledHint: blocked.message,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _InputBox(
                    controller: _input,
                    focusNode: _focus,
                    onSubmit: () => _send(),
                  ),
                ),
                const SizedBox(width: Sp.sm),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _input,
                  builder: (context, v, _) => _SendButton(
                    enabled: v.text.trim().length >= 3 && !_busy,
                    busy: _busy,
                    onTap: () => _send(),
                  ),
                ),
              ],
            ),
          if (roomy) ...[
            const SizedBox(height: Sp.sm),
            _FootNote(quota: status?.quota),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════ القطع ═════════════════════════

/// الرسالة كما ظهرت للمدير — بلا رمز الخادم (لا يُرى رمزٌ تقنيّ في التطبيق).
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Sp.md),
      decoration: BoxDecoration(
        color: AppColors.dangerSoftBg,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.dangerSoftBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child:
                Icon(LucideIcons.circleAlert, size: 18, color: AppColors.error),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: AppType.bodyStrong(color: AppColors.dangerOnSoft)),
          ),
        ],
      ),
    );
  }
}

/// جواب المساعد: عنوان · نصّ · خطوات مرقّمة · ميزاتٌ ذات صلة.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer, this.onRelated});
  final AiAnswer answer;
  final ValueChanged<String>? onRelated;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final related = onRelated == null ? const <String>[] : answer.related;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, Sp.md, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(LucideIcons.sparkles,
                    size: 16, color: AppColors.brandAccent),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  answer.title.isNotEmpty ? answer.title : 'ai.title'.tr(),
                  style: AppType.cardTitleBold(color: AppColors.textHi),
                ),
              ),
            ],
          ),
          if (answer.body.isNotEmpty) ...[
            const SizedBox(height: Sp.x6),
            Text(
              answer.body,
              style:
                  AppType.body(color: AppColors.textBody).copyWith(height: 1.6),
            ),
          ],
          if (answer.steps.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (var i = 0; i < answer.steps.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : Sp.sm),
                child: _Step(n: i + 1, text: answer.steps[i]),
              ),
          ],
          if (related.isNotEmpty) ...[
            const SizedBox(height: Sp.md),
            Wrap(
              spacing: Sp.x6,
              runSpacing: Sp.x6,
              children: [
                for (final r in related)
                  ToneChip(
                    label: r,
                    tone: AppTone.brand,
                    icon: LucideIcons.messageCircleQuestion,
                    onTap: () => onRelated!(r),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: DecoratedBox(
            decoration: BoxDecoration(
                color: AppColors.brandSoftBg, shape: BoxShape.circle),
            child: Center(
              child: Text('$n',
                  style: AppType.microBold(color: AppColors.brandOnSoft)),
            ),
          ),
        ),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(text, style: AppType.body(color: AppColors.textBody)),
          ),
        ),
      ],
    );
  }
}

/// نسخ الجواب، و«تواصل ويّا الدعم» حين لا يعرف المساعد أو الحلّ عند الشركة،
/// و«مفيد» / «الجواب غلط» حين أعطى الخادم مرجعاً للجواب.
class _AnswerActions extends StatelessWidget {
  const _AnswerActions({
    required this.answer,
    required this.support,
    required this.onLaunch,
    this.withCopy = true,
    this.feedbackRef,
  });
  final AiAnswer answer;
  final AiSupport? support;
  final ValueChanged<Uri> onLaunch;
  final bool withCopy;

  /// مرجع الجواب عند الخادم ([AiReply.ref]) — `null` = لا تقييم.
  final String? feedbackRef;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final s = answer.wantsSupport ? support : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s != null) ...[
          Text('ai.contact_support'.tr(), style: AppType.label()),
          const SizedBox(height: Sp.x6),
        ],
        Wrap(
          spacing: Sp.sm,
          runSpacing: Sp.sm,
          children: [
            if (s?.telegram case final tg?)
              _PillButton(
                icon: LucideIcons.send,
                label: 'ai.support_telegram'.tr(),
                tone: AppTone.telegram,
                onTap: () => onLaunch(tg),
              ),
            if (s?.whatsapp case final wa?)
              _PillButton(
                icon: LucideIcons.messageCircle,
                label: 'ai.support_whatsapp'.tr(),
                tone: AppTone.whatsapp,
                onTap: () => onLaunch(wa),
              ),
            if (withCopy)
              _PillButton(
                icon: LucideIcons.copy,
                label: 'ai.copy'.tr(),
                tone: AppTone.neutral,
                onTap: () => copyToClipboard(context, answer.plainText,
                    message: 'ai.copied'.tr()),
              ),
            if (feedbackRef case final ref?)
              _Feedback(key: ValueKey('ai-feedback-$ref'), feedbackRef: ref),
          ],
        ),
      ],
    );
  }
}

/// «مفيد» / «الجواب غلط» — رأيٌ واحد لكلّ جواب، يُرسل بمرجعه وحده (لا نصّ).
/// بعده «وصلنا رأيك — شكراً»؛ وإن تعذّر الإرسال يرجع الزرّان وإشعارٌ بذلك.
class _Feedback extends StatefulWidget {
  const _Feedback({super.key, required this.feedbackRef});
  final String feedbackRef;

  @override
  State<_Feedback> createState() => _FeedbackState();
}

class _FeedbackState extends State<_Feedback> {
  bool _sending = false;

  /// القائمة الكسولة قد تهدم السطر وتبنيه ثانيةً — فالمرجع المقيَّم يُحفظ في
  /// حال الجلسة ([AiAssistantState.ratedRefs]) لا هنا وحده.
  late bool _sent = AiAssistantState.ratedRefs.contains(widget.feedbackRef);

  Future<void> _send(bool helpful) async {
    if (_sending || _sent) return;
    HapticFeedback.selectionClick();
    setState(() => _sending = true);
    final ok = await AiApi.feedback(widget.feedbackRef, helpful: helpful);
    if (!mounted) return;
    if (ok) AiAssistantState.ratedRefs.add(widget.feedbackRef);
    setState(() {
      _sending = false;
      _sent = ok;
    });
    if (!ok) {
      showSheetSnack(context, 'ai.feedback_failed'.tr(),
          isError: true, autoExplain: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (_sent) {
      return Semantics(
        liveRegion: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.circleCheck, size: 16, color: AppColors.success),
              const SizedBox(width: Sp.x6),
              Flexible(
                child: Text('ai.feedback_thanks'.tr(),
                    style: AppType.bodyStrong(color: AppColors.textMid)),
              ),
            ],
          ),
        ),
      );
    }
    return Wrap(
      spacing: Sp.sm,
      runSpacing: Sp.sm,
      children: [
        _PillButton(
          icon: LucideIcons.thumbsUp,
          label: 'ai.helpful'.tr(),
          tone: AppTone.neutral,
          onTap: _sending ? null : () => _send(true),
        ),
        _PillButton(
          icon: LucideIcons.flag,
          label: 'ai.report'.tr(),
          semanticLabel: 'ai.report_a11y'.tr(),
          tone: AppTone.neutral,
          onTap: _sending ? null : () => _send(false),
        ),
      ],
    );
  }
}

/// زرّ حبّةٍ بنغمة — منطقة لمسٍ ٤٤. [onTap] `null` = معطّلٌ لحظيّاً (إرسال).
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
    this.semanticLabel,
  });
  final IconData icon;
  final String label;
  final AppTone tone;
  final VoidCallback? onTap;

  /// وصفٌ أطول لقارئ الشاشة (التسمية الظاهرة قصيرة).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final pill = Material(
      color: tone.softBg,
      shape: StadiumBorder(side: BorderSide(color: tone.softBorder)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: tone.fill),
                const SizedBox(width: Sp.x6),
                Text(label,
                    maxLines: 1, style: AppType.bodyStrong(color: tone.onSoft)),
              ],
            ),
          ),
        ),
      ),
    );
    final a11y = semanticLabel;
    if (a11y == null) return pill;
    return Semantics(
      button: true,
      label: a11y,
      onTap: onTap,
      excludeSemantics: true,
      child: pill,
    );
  }
}

/// رفضٌ أو تعذّر — رسالة الخادم كما هي داخل النافذة (لا إشعار).
class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.failure, this.upgradeHint, this.onRetry});
  final AiFailure failure;
  final String? upgradeHint;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final locked = failure.noPermission;
    final tone = failure.quotaExhausted
        ? AppTone.warning
        : (locked || failure.isOff ? AppTone.neutral : AppTone.danger);
    final icon = locked
        ? LucideIcons.lock
        : failure.quotaExhausted
            ? LucideIcons.hourglass
            : LucideIcons.circleAlert;
    // آيفون: لا دعوة ترقية أبداً، والخادم يرسلها `null` هناك وللموظّف أصلاً.
    final hint = failure.quotaExhausted && !StorePolicy.hidePurchaseFlows
        ? upgradeHint
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Sp.md),
      decoration: BoxDecoration(
        color: locked ? LockedStyle.box : tone.softBg,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: tone.softBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon,
                    size: 18, color: locked ? LockedStyle.glyph : tone.fill),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  failure.message,
                  style: AppType.bodyStrong(
                      color: locked ? LockedStyle.title : tone.onSoft),
                ),
              ),
            ],
          ),
          if (hint != null) ...[
            const SizedBox(height: Sp.x6),
            Text(hint, style: AppType.body(color: AppColors.textMid)),
          ],
          if (onRetry != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(LucideIcons.rotateCw, size: 16),
                label: Text('ai.retry'.tr()),
              ),
            ),
        ],
      ),
    );
  }
}

/// «دا أفكّر…» — مكان الجواب أثناء الانتظار.
class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.brandAccent),
            ),
            const SizedBox(width: Sp.sm),
            Text('ai.thinking'.tr(),
                style: AppType.body(color: AppColors.textMid)),
          ],
        ),
      ),
    );
  }
}

/// سؤال المدير — في طرف النهاية (يسار الشاشة بالعربيّة).
class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return LayoutBuilder(
      builder: (context, c) => Align(
        alignment: AlignmentDirectional.centerEnd,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: c.maxWidth * 0.86),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(R.lg),
            ),
            child: Text(text, style: AppType.body(color: AppColors.onBrand)),
          ),
        ),
      ),
    );
  }
}

/// أوّل المحادثة: ما يستطيعه المساعد + أسئلةٌ مقترحة من الخادم (حسب مزوّد
/// الحساب ودوره).
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.suggestions, required this.onPick});
  final List<String> suggestions;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Sp.sm),
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
                color: AppColors.brandSoftBg, shape: BoxShape.circle),
            child: Icon(LucideIcons.sparkles,
                size: 26, color: AppColors.brandAccent),
          ),
        ),
        const SizedBox(height: Sp.md),
        Text(
          'ai.empty_title'.tr(),
          textAlign: TextAlign.center,
          style: AppType.cardTitleBold(color: AppColors.textHi),
        ),
        const SizedBox(height: Sp.xs),
        Text(
          'ai.empty_hint'.tr(),
          textAlign: TextAlign.center,
          style: AppType.body(color: AppColors.textMid),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: Sp.lg),
          for (final s in suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.sm),
              child: _SuggestionTile(text: s, onTap: () => onPick(s)),
            ),
        ],
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.messageCircleQuestion,
                  size: 16, color: AppColors.brandAccent),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong(color: AppColors.textBody),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// حقل السؤال — حدّه يصير بلون البراند عند التركيز (كـ[SheetBox]).
class _InputBox extends StatefulWidget {
  const _InputBox({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    this.disabledHint,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;

  /// مقفلٌ بهذا السطر (رفضٌ لا سؤال بعده الآن) — بلا لوحة مفاتيح.
  final String? disabledHint;

  @override
  State<_InputBox> createState() => _InputBoxState();
}

class _InputBoxState extends State<_InputBox> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() => setState(() {});

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final disabled = widget.disabledHint;
    if (disabled != null) {
      return Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceDisabled,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.lock, size: 15, color: AppColors.textLow),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(
                disabled,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppType.body(color: AppColors.textMid),
              ),
            ),
          ],
        ),
      );
    }
    final focused = widget.focusNode.hasFocus;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(
          color: focused ? AppColors.brand : AppColors.border,
          width: focused ? BW.selected : BW.normal,
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        minLines: 1,
        maxLines: 4,
        maxLength: 500,
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => widget.onSubmit(),
        style: AppType.input(),
        cursorColor: AppColors.brand,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          counterText: '',
          hintText: 'ai.input_hint'.tr(),
          hintStyle: AppType.input(color: AppColors.textPlaceholder),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton(
      {required this.enabled, required this.busy, required this.onTap});
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final live = enabled && !busy;
    return Semantics(
      button: true,
      enabled: live,
      label: 'ai.send'.tr(),
      onTap: live ? onTap : null,
      excludeSemantics: true,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: live ? AppColors.brand : AppColors.surfaceDisabled,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: live ? onTap : null,
            customBorder: const CircleBorder(),
            child: Icon(
              LucideIcons.sendHorizontalDir,
              size: 19,
              color: live ? AppColors.onBrand : AppColors.textHint,
            ),
          ),
        ),
      ),
    );
  }
}

/// «أجوبة ذكاء اصطناعي وقد تخطئ — يشرح فقط» + الحصّة الباقية اليوم. التنبيه
/// كاملٌ دائماً (بلا «…» بعرض ٣٢٠ أو بخطٍّ مكبَّر).
class _FootNote extends StatelessWidget {
  const _FootNote({required this.quota});
  final AiQuota? quota;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final left = quota?.left;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(LucideIcons.info, size: 13, color: AppColors.textLow),
        ),
        const SizedBox(width: Sp.xs),
        Expanded(
          child: Text('ai.disclaimer'.tr(), style: AppType.muted()),
        ),
        if (left != null) ...[
          const SizedBox(width: Sp.sm),
          ToneChip(
            label: 'ai.quota_left'.tr(namedArgs: {'n': '$left'}),
            tone: left <= 0
                ? AppTone.danger
                : left <= 2
                    ? AppTone.warning
                    : AppTone.brand,
            dense: true,
          ),
        ],
      ],
    );
  }
}
