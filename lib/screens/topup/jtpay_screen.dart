import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/jtpay_api.dart';
import '../../api/self_deposit_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../services/active_company.dart';
import '../../services/auth_storage.dart';
import '../../services/jtpay_pending.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import 'pay_nav_policy.dart';
import 'topup_pay_page.dart';
import 'topup_widgets.dart';

/// «شحن من pay الجزيرة» — لوكلاء شركة الجزيرة (لاسلكي/فايبر).
///
/// المالك ٣٠ أكتوبر: «الصفحه ال pay هي الي رح تنشحن ومنها يحول المبلغ للساس… بعد اتمام العمليه نكله تريد تحويل
/// للصفحه نفسها او نخيره لصفحه ثانيه».
///
/// ١) تعبئة رصيد pay بزين كاش أو بطاقة: الرسوم من الموقع ⇒ صفحة الدفع داخل التطبيق ([TopupPayPage]) ⇒ رجوعها
///    يُلتقط ولا يُحمَّل ([HostReturnNavPolicy]) ويُحفظ ([JtpayPendingStore]) ثمّ يُسلَّم للخادم.
/// ٢) بعد الشحن: «تحويل لصفحتك بالساس» أو «لصفحة ثانية» باسمها — بتأكيد، مرّةً واحدة.
/// ٣) آخر العمليّات و«تحقّق»، وسجلّ موقع الشحن نفسه.
class JtpayScreen extends StatefulWidget {
  const JtpayScreen({super.key});

  @override
  State<JtpayScreen> createState() => _JtpayScreenState();
}

/// ما تقوله بطاقة النتيجة لعمليّة — منطقٌ صافٍ يُختبر بلا رسم.
TopupResultView describeJtpayOp(JtpayOp op) {
  final amount = op.amount == null ? '' : '${formatIQD(op.amount!)} د.ع';
  final bal = op.balanceAfter == null ? null : 'رصيد pay الآن: ${formatIQD(op.balanceAfter!)} د.ع';
  if (op.isTopup) {
    return switch (op.status) {
      JtpayStatus.success => TopupResultView(
          tone: AppTone.success,
          icon: LucideIcons.circleCheck,
          title: 'انشحن $amount برصيد pay',
          body: 'تريد تحوّله هسّه؟ لصفحتك بالساس أو لصفحة ثانية.',
          balanceLine: bal,
          refLine: op.orderNo == null ? null : 'رقم العمليّة بموقع الشحن: ${op.orderNo}',
        ),
      JtpayStatus.failed => TopupResultView(
          tone: AppTone.danger,
          icon: LucideIcons.circleX,
          title: 'لم يتمّ الدفع',
          body: op.message ?? 'موقع الشحن ما سجّل الدفعة — إذا انسحب مبلغ تواصل مع دعم الجزيرة برقم العمليّة.',
          refLine: op.orderNo == null ? null : 'رقم العمليّة بموقع الشحن: ${op.orderNo}',
        ),
      JtpayStatus.awaitingPayment => TopupResultView(
          tone: AppTone.info,
          icon: LucideIcons.clock,
          title: 'ما كمل الدفع',
          body: 'إذا دفعت فعلاً اضغط «تحقّق». وإذا ما دفعت ما انسحب شيء.',
          refLine: op.orderNo == null ? null : 'رقم العمليّة بموقع الشحن: ${op.orderNo}',
          checkable: true,
        ),
      JtpayStatus.expired => TopupResultView(
          tone: AppTone.warning,
          icon: LucideIcons.clock,
          title: 'انتهت مهلة رابط الدفع',
          body: 'إذا دفعت قبل ما تنتهي اضغط «تحقّق»، وإلّا ابدأ دفعة جديدة.',
          refLine: op.orderNo == null ? null : 'رقم العمليّة بموقع الشحن: ${op.orderNo}',
          checkable: true,
        ),
      JtpayStatus.pending || JtpayStatus.processing => TopupResultView(
          tone: AppTone.warning,
          icon: LucideIcons.hourglass,
          title: 'بانتظار تأكيد موقع الشحن',
          body: 'وصلت الدفعة وموقع الشحن ما أكّدها بعد — اضغط «تحقّق» بعد دقيقة.',
          refLine: op.orderNo == null ? null : 'رقم العمليّة بموقع الشحن: ${op.orderNo}',
          checkable: true,
        ),
      JtpayStatus.unknown => TopupResultView(
          tone: AppTone.warning,
          icon: LucideIcons.circleHelp,
          title: 'غير مؤكَّد',
          body: op.message ?? 'ما تأكّدنا من نتيجة الدفعة — اضغط «تحقّق» قبل ما تدفع مرّة ثانية.',
          refLine: op.orderNo == null ? null : 'رقم العمليّة بموقع الشحن: ${op.orderNo}',
          checkable: true,
        ),
    };
  }
  final where = op.kind == 'to_sas' ? 'لصفحتك بالساس' : 'إلى ${op.target ?? 'الصفحة'}';
  return switch (op.status) {
    JtpayStatus.success => TopupResultView(
        tone: AppTone.success,
        icon: LucideIcons.circleCheck,
        title: 'تحوّل $amount $where',
        body: op.kind == 'to_sas' && op.sasAfter != null
            ? 'رصيد صفحتك بالساس صار ${formatIQD(op.sasAfter!)} د.ع.'
            : 'انخصم المبلغ من رصيد pay.',
        balanceLine: bal,
      ),
    JtpayStatus.failed => TopupResultView(
        tone: AppTone.danger,
        icon: LucideIcons.circleX,
        title: 'لم يتمّ التحويل',
        body: op.message ?? 'موقع الشحن رفض التحويل — رصيدك ما تغيّر.',
        balanceLine: bal,
      ),
    _ => TopupResultView(
        tone: AppTone.warning,
        icon: LucideIcons.circleHelp,
        title: 'التحويل غير مؤكَّد',
        body: op.message ?? 'ما تأكّدنا من التحويل — راجع رصيدك وسجلّ موقع الشحن قبل ما تعيد.',
        balanceLine: bal,
      ),
  };
}

class _JtpayScreenState extends State<JtpayScreen> {
  JtpayOverview? _ov;
  bool _loading = true;
  String? _error;

  final _amountCtrl = TextEditingController();
  String? _method;
  JtpayQuote? _quote;
  bool _quoting = false;
  Timer? _quoteTimer;
  int _quoteSeq = 0;

  bool _busy = false;
  JtpayOp? _shown;
  bool _checking = false;

  /// رابطٌ التُقط ولم يتأكّد الخادم من استلامه.
  List<JtpayPending> _pending = const [];

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_scheduleQuote);
    _load();
  }

  @override
  void dispose() {
    _quoteTimer?.cancel();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<String?> _adminId() async {
    try {
      return await AuthStorage.readAdminId();
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _deliverPending();
    final r = await JtpayApi.overview();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _ov = r.data ?? _ov;
      _error = r.data == null ? r.message : null;
      final ms = _ov?.methods ?? const <JtpayMethod>[];
      if (_method == null || !ms.any((m) => m.id == _method)) _method = ms.isEmpty ? null : ms.first.id;
    });
  }

  // ───────────── الرسوم ─────────────

  /// المبلغ كما سيُرسل: اختصار الآلاف كبقيّة حقول المال (25 ⇒ 25,000) ولو لم يخرج المؤشّر بعد.
  int? get _amount {
    final v = AmountShorthand.parse(_amountCtrl.text);
    if (v <= 0) return null;
    return AmountShorthand.applies(v) ? AmountShorthand.expand(v) : v;
  }

  String? _amountError() {
    final o = _ov;
    final a = _amount;
    if (o == null) return null;
    if (a == null || a <= 0) return 'اكتب المبلغ';
    if (a < o.minAmount) return 'أقلّ مبلغ ${formatIQD(o.minAmount)} د.ع';
    if (a > o.maxAmount) return 'أكبر مبلغ ${formatIQD(o.maxAmount)} د.ع';
    return null;
  }

  void _scheduleQuote() {
    _quoteTimer?.cancel();
    final a = _amount;
    final m = _method;
    if (_quote != null && (a == null || _quote!.amount != a)) setState(() => _quote = null);
    if (a == null || m == null || _amountError() != null) return;
    _quoteTimer = Timer(const Duration(milliseconds: 500), () => _fetchQuote(a, m));
  }

  Future<void> _fetchQuote(int amount, String method) async {
    final seq = ++_quoteSeq;
    setState(() => _quoting = true);
    final r = await JtpayApi.quote(amount: amount, method: method);
    if (!mounted || seq != _quoteSeq) return;
    setState(() {
      _quoting = false;
      _quote = r.data;
    });
  }

  // ───────────── التعبئة ─────────────

  Future<void> _pay() async {
    final a = _amount;
    final m = _method;
    final err = _amountError();
    if (a == null || m == null || err != null) {
      showSheetSnack(context, err ?? 'اختر طريقة الدفع', isError: true);
      return;
    }
    final label = _ov?.methods.firstWhere((x) => x.id == m, orElse: () => JtpayMethod(m, m)).label ?? m;
    final q = _quote;
    final ok = await showConfirmSheet(
      context,
      title: 'دفع ${formatIQD(q?.total ?? a)} د.ع',
      message: q == null
          ? 'تنشحن ${formatIQD(a)} د.ع برصيد pay عن طريق $label.'
          : 'المبلغ ${formatIQD(q.amount)} + رسوم الدفع الالكتروني ${formatIQD(q.fee)} = ${formatIQD(q.total)} د.ع.\n'
              'تنفتح صفحة $label داخل التطبيق — كمّل الدفع وانتظر يرجع التطبيق وحده.',
      confirmLabel: 'المتابعة للدفع',
      cancelLabel: 'إلغاء',
      icon: LucideIcons.creditCard,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final r = await JtpayApi.topup(amount: a, method: m);
    if (!mounted) return;
    final start = r.data;
    if (start == null) {
      setState(() {
        _busy = false;
        if (r.op != null) _shown = r.op;
      });
      showSheetSnack(context, r.message ?? 'تعذّر بدء الدفع', isError: true);
      return;
    }
    final adminId = await _adminId();
    if (!mounted) return;
    final res = await Navigator.of(context).push<PayPageResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TopupPayPage(
          payUrl: start.payUrl,
          policy: HostReturnNavPolicy(returnHost: start.returnHost),
          methodLabel: label,
          // يُكتب قبل أن تُغلق الصفحة — الرجوع لا يضيع إن انقطع ما بعده.
          onCaptured: (url) async {
            final id = (adminId == null || adminId.isEmpty) ? await _adminId() : adminId;
            if (id == null || id.isEmpty) return;
            await JtpayPendingStore.put(JtpayPending(opId: start.op.id, adminId: id, returnUrl: url, at: DateTime.now(), amount: a));
          },
        ),
      ),
    );
    if (!mounted) return;
    final ret = res?.returnUrl;
    JtpayOp? op;
    if (ret != null) {
      op = await _deliver(start.op.id, ret);
    } else {
      // أُغلقت الصفحة قبل الرجوع: نسأل الموقع (قد يكون دفع).
      op = (await JtpayApi.status(start.op.id, check: true)).data;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _shown = op ?? start.op;
    });
    if (op?.succeeded == true) HapticFeedback.mediumImpact();
    unawaited(_refreshOverview());
  }

  /// يسلّم رابط الرجوع — ويعيد عند انقطاع الشبكة (الخادم يمنع تسليم الرابط نفسه مرّتين).
  Future<JtpayOp?> _deliver(String opId, String returnUrl) async {
    const waits = [Duration.zero, Duration(seconds: 2), Duration(seconds: 5)];
    JtpayReply<JtpayOp>? r;
    for (final w in waits) {
      if (w > Duration.zero) await Future<void>.delayed(w);
      r = await JtpayApi.deliverReturn(opId: opId, returnUrl: returnUrl);
      final retry = r.notSent || r.noVerdict || r.code == 'BUSY' || r.code == 'SITE_UNREACHABLE';
      if (!retry) break;
    }
    final op = r?.data ?? r?.op;
    if (op != null && op.received) await JtpayPendingStore.remove(opId);
    if (r?.code == 'NOT_AWAITING' || r?.code == 'RETURN_USED' || r?.code == 'BAD_RETURN' || r?.code == 'NOT_FOUND') {
      // الخادم لن يقبله أبداً (نسخته محفوظةٌ عنده إن احتاجت مراجعة) — لا يبقى يُعاد.
      await JtpayPendingStore.remove(opId);
    }
    return op;
  }

  /// روابط رجوعٍ لم تُسلَّم (قتل التطبيق، انقطاع) — تُسلَّم عند فتح الشاشة.
  Future<void> _deliverPending() async {
    final list = await JtpayPendingStore.forAdmin(await _adminId());
    for (final p in list) {
      final op = await _deliver(p.opId, p.returnUrl);
      if (op != null && mounted) setState(() => _shown = op);
    }
    final left = await JtpayPendingStore.forAdmin(await _adminId());
    if (mounted) setState(() => _pending = left);
  }

  Future<void> _refreshOverview() async {
    final r = await JtpayApi.overview();
    if (!mounted || r.data == null) return;
    setState(() => _ov = r.data);
  }

  Future<void> _check(JtpayOp op) async {
    setState(() => _checking = true);
    final r = await JtpayApi.status(op.id, check: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      if (r.data != null) _shown = r.data;
    });
    if (r.data == null) showSheetSnack(context, r.message ?? 'تعذّر التحقّق', isError: true);
    unawaited(_refreshOverview());
  }

  // ───────────── التحويل ─────────────

  /// آخر رصيد pay معروف: رصيد ما بعد العمليّة المعروضة أحدث من النظرة حتى تتحدّث.
  num? get _latestBalance => _shown?.balanceAfter ?? _ov?.balance;

  Future<void> _transfer({required String to, int? suggested}) async {
    final ov = _ov;
    if (ov == null) return;
    final res = await showAppSheet<JtpayOp>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      builder: (_) => _TransferSheet(
        to: to,
        balance: _latestBalance,
        minAmount: ov.minAmount,
        suggested: suggested,
      ),
    );
    if (!mounted || res == null) return;
    setState(() => _shown = res);
    if (res.succeeded) HapticFeedback.mediumImpact();
    unawaited(_refreshOverview());
  }

  // ───────────── الرسم ─────────────

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final ov = _ov;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.textHi),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('شحن من pay الجزيرة', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
              Text(ov?.sectionLabel ?? 'زين كاش أو بطاقة — ثمّ تحويل للساس',
                  style: AppType.muted().copyWith(fontSize: 11)),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.brandAccent,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Inset.route(context)),
            children: _children(),
          ),
        ),
      ),
    );
  }

  List<Widget> _children() {
    final ov = _ov;
    if (ov == null) {
      if (_loading) {
        return const [Padding(padding: EdgeInsets.all(Sp.huge), child: Center(child: CircularProgressIndicator()))];
      }
      return [
        TopupStateCard(
          icon: LucideIcons.wifiOff,
          title: 'تعذّر فتح موقع الشحن',
          text: _error ?? 'أعد المحاولة بعد قليل',
          action: OutlinedButton(onPressed: _load, child: const Text('أعد المحاولة')),
        ),
      ];
    }
    final user = ActiveCompany.current?.shownUsername;
    final shown = _shown;
    return [
      if (_pending.isNotEmpty) ...[
        TopupNoticeCard(
          view: const TopupResultView(
            tone: AppTone.warning,
            icon: LucideIcons.hourglass,
            title: 'دفعةٌ بانتظار التسليم لموقع الشحن',
            body: 'رجعت من صفحة الدفع وما وصلنا موقع الشحن بعد — نعيد المحاولة تلقائيّاً.',
          ),
          actionLabel: 'أعد الآن',
          busy: _loading,
          onAction: _load,
        ),
        const SizedBox(height: Sp.md),
      ],
      TopupBalanceCard(
        label: 'رصيد pay',
        balance: ov.balance,
        loading: _loading,
        currency: 'د.ع',
        pageLine: [ov.sectionLabel, if ((user ?? '').isNotEmpty) iso(user!)].join(' · '),
        onRefresh: _load,
      ),
      if (shown != null) ...[
        const SizedBox(height: Sp.md),
        _resultCard(shown),
      ],
      if ((ov.notice ?? '').isNotEmpty) ...[
        const SizedBox(height: Sp.md),
        TopupNoticeCard(
          view: TopupResultView(tone: AppTone.info, icon: LucideIcons.megaphone, title: 'تنويه موقع الشحن', body: ov.notice!),
        ),
      ],
      const SizedBox(height: Sp.lg),
      TopupSection(title: 'تعبئة رصيد pay', children: [_topupForm(ov)]),
      const SizedBox(height: Sp.lg),
      TopupSection(title: 'تحويل من رصيد pay', children: [_transferButtons(ov)]),
      if (ov.recent.isNotEmpty) ...[
        const SizedBox(height: Sp.lg),
        TopupSection(title: 'آخر العمليّات', children: [for (final op in ov.recent) _opRow(op)]),
      ],
      const SizedBox(height: Sp.md),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: () => showAppSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            barrierColor: AppColors.scrim,
            builder: (_) => const _SiteHistorySheet(),
          ),
          icon: Icon(LucideIcons.history, size: 16, color: AppColors.brandAccent),
          label: Text('سجلّ موقع الشحن', style: AppType.link(color: AppColors.brandAccent)),
        ),
      ),
    ];
  }

  Widget _resultCard(JtpayOp op) {
    final view = describeJtpayOp(op);
    final card = TopupNoticeCard(
      view: view,
      actionLabel: view.checkable && op.canCheck ? 'تحقّق' : null,
      busy: _checking,
      onAction: view.checkable && op.canCheck ? () => _check(op) : null,
      onDismiss: () => setState(() => _shown = null),
    );
    // بعد الشحن: سؤال المالك — «للصفحة نفسها أو لصفحة ثانية».
    if (op.isTopup && op.succeeded) {
      final amt = op.amount?.round();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card,
          const SizedBox(height: Sp.sm),
          SizedBox(
            height: H.button,
            child: FilledButton.icon(
              onPressed: () => _transfer(to: 'sas', suggested: amt),
              icon: const Icon(LucideIcons.arrowDownToLine, size: 18),
              label: const Text('حوّله لصفحتك بالساس'),
            ),
          ),
          const SizedBox(height: Sp.sm),
          SizedBox(
            height: H.button,
            child: OutlinedButton.icon(
              onPressed: () => _transfer(to: 'page', suggested: amt),
              icon: const Icon(LucideIcons.send, size: 18),
              label: const Text('حوّله لصفحة ثانية'),
            ),
          ),
        ],
      );
    }
    return card;
  }

  static const _methodHints = {
    'zaincash': 'ادفع من محفظة زين كاش — يرجع التطبيق وحده بعد الدفع',
    'qi': 'ماستر كارد أو فيزا أو كي كارد — صفحة الدفع داخل التطبيق',
  };

  void _setAmount(int v) {
    HapticFeedback.selectionClick();
    final t = AmountShorthand.format(v);
    _amountCtrl.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }

  Widget _topupForm(JtpayOverview ov) {
    final err = _amountCtrl.text.isEmpty ? null : _amountError();
    final q = _quote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetBox(
          focused: false,
          child: AmountTextField(
            controller: _amountCtrl,
            enabled: !_busy,
            currency: 'د.ع',
            onValue: (_) => setState(() {}),
          ),
        ),
        if (ov.quickAmounts.isNotEmpty) ...[
          const SizedBox(height: Sp.sm),
          Wrap(
            spacing: Sp.sm,
            runSpacing: Sp.sm,
            children: [
              for (final v in ov.quickAmounts)
                if (v >= ov.minAmount && v <= ov.maxAmount)
                  SheetQuickChip(
                    label: formatIQD(v),
                    selected: _amount == v,
                    enabled: !_busy,
                    onTap: () => _setAmount(v),
                  ),
            ],
          ),
        ],
        const SizedBox(height: Sp.sm),
        Text(
          err ?? 'أقلّ مبلغ ${formatIQD(ov.minAmount)} د.ع · أكثر مبلغ ${formatIQD(ov.maxAmount)} د.ع',
          style: err == null ? AppType.muted(color: AppColors.textMid) : AppType.body(color: AppTone.danger.onSoft),
        ),
        const SizedBox(height: Sp.lg),
        for (var i = 0; i < ov.methods.length; i++) ...[
          if (i > 0) const SizedBox(height: Sp.sm),
          TopupMethodTile(
            method: SelfDepositMethod(
              id: ov.methods[i].id,
              internalName: ov.methods[i].id,
              flow: SelfDepositFlow.redirect,
              name: ov.methods[i].label,
            ),
            subtitle: _methodHints[ov.methods[i].id],
            selected: _method == ov.methods[i].id,
            enabled: !_busy,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _method = ov.methods[i].id);
              _scheduleQuote();
            },
          ),
        ],
        const SizedBox(height: Sp.lg),
        if (_quoting)
          Text('نحسب الرسوم…', style: AppType.muted())
        else if (q != null)
          SheetRowsGroup(rows: [
            SheetRowData(label: 'المبلغ', value: '${formatIQD(q.amount)} د.ع'),
            SheetRowData(label: 'رسوم الدفع الالكتروني', value: '${formatIQD(q.fee)} د.ع'),
            SheetRowData(label: 'المجموع', value: '${formatIQD(q.total)} د.ع', strong: true),
          ]),
        const SizedBox(height: Sp.lg),
        SizedBox(
          height: H.button,
          child: FilledButton.icon(
            onPressed: _busy || ov.methods.isEmpty ? null : _pay,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(LucideIcons.creditCard, size: 18),
            label: Text(q == null ? 'ادفع' : 'ادفع ${formatIQD(q.total)} د.ع'),
          ),
        ),
      ],
    );
  }

  Widget _transferButtons(JtpayOverview ov) {
    final can = (_latestBalance ?? 0) >= ov.minAmount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          can ? 'حوّل من رصيد pay لصفحتك بالساس أو لصفحة ثانية باسمها.' : 'رصيد pay أقلّ من ${formatIQD(ov.minAmount)} د.ع — عبّي أوّلاً.',
          style: AppType.muted(color: AppColors.textMid),
        ),
        const SizedBox(height: Sp.md),
        SizedBox(
          height: H.button,
          child: OutlinedButton.icon(
            onPressed: can ? () => _transfer(to: 'sas') : null,
            icon: const Icon(LucideIcons.arrowDownToLine, size: 18),
            label: const Text('لصفحتك بالساس'),
          ),
        ),
        const SizedBox(height: Sp.sm),
        SizedBox(
          height: H.button,
          child: OutlinedButton.icon(
            onPressed: can ? () => _transfer(to: 'page') : null,
            icon: const Icon(LucideIcons.send, size: 18),
            label: const Text('لصفحة ثانية'),
          ),
        ),
      ],
    );
  }

  /// صفّ عمليّة: النوع والمبلغ، ثمّ الحال بكلمةٍ ملوّنة والوقت في السطر الثاني — لا حبّة في الطرف تقصّ المبلغ
  /// عند ٣٢٠ (كسجلّ شحن الرصيد).
  Widget _opRow(JtpayOp op) {
    final tone = switch (op.status) {
      JtpayStatus.success => AppTone.success,
      JtpayStatus.failed => AppTone.danger,
      JtpayStatus.awaitingPayment => AppTone.info,
      _ => AppTone.warning,
    };
    final at = op.createdAt;
    final when = at == null
        ? ''
        : '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')} '
            '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final rest = [
      if (op.methodLabel != null) op.methodLabel!,
      if (op.target != null) iso(op.target!),
      if (when.isNotEmpty) iso(when),
    ].join(' · ');
    return InkWell(
      onTap: () => setState(() => _shown = op),
      borderRadius: BorderRadius.circular(R.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${op.kindLabel ?? op.kind}${op.amount == null ? '' : ' · ${formatIQD(op.amount!)} د.ع'}',
              style: AppType.bodyStrong(color: AppColors.textHi),
            ),
            const SizedBox(height: Sp.xxs),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: op.statusLabel ?? '', style: AppType.bodyStrong(color: tone.onSoft).copyWith(fontSize: 12.5)),
                if (rest.isNotEmpty) TextSpan(text: ' · $rest', style: AppType.muted()),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════ ورقة التحويل ═════════════════════════

class _TransferSheet extends StatefulWidget {
  const _TransferSheet({required this.to, required this.balance, required this.minAmount, this.suggested});

  /// `sas` · `page`
  final String to;
  final num? balance;
  final int minAmount;
  final int? suggested;

  @override
  State<_TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends State<_TransferSheet> {
  late final _amountCtrl = TextEditingController(
      text: widget.suggested != null && (widget.balance == null || widget.suggested! <= widget.balance!)
          ? AmountShorthand.format(widget.suggested!)
          : '');
  final _targetCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  int? get _amount {
    final v = AmountShorthand.parse(_amountCtrl.text);
    if (v <= 0) return null;
    return AmountShorthand.applies(v) ? AmountShorthand.expand(v) : v;
  }

  bool get _toSas => widget.to == 'sas';

  Future<void> _submit({bool confirmRepeat = false}) async {
    final a = _amount;
    final target = _targetCtrl.text.trim();
    String? err;
    if (a == null || a < widget.minAmount) err = 'أقلّ مبلغ ${formatIQD(widget.minAmount)} د.ع';
    if (err == null && widget.balance != null && a! > widget.balance!) err = 'رصيد pay (${formatIQD(widget.balance!)}) أقلّ من المبلغ';
    if (err == null && !_toSas && !RegExp(r'^[A-Za-z0-9@._-]{2,64}$').hasMatch(target)) {
      err = 'اكتب اسم الصفحة مثل ما مسجّل بالنظام (مثل admin@name)';
    }
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (!confirmRepeat) {
      final ok = await showConfirmSheet(
        context,
        title: 'تأكيد التحويل',
        message: _toSas
            ? 'تحويل ${formatIQD(a!)} د.ع من رصيد pay لصفحتك بالساس.'
            : 'تحويل ${formatIQD(a!)} د.ع من رصيد pay إلى الصفحة ${iso(target)}.\nتأكّد من الاسم — التحويل لا يرجع.',
        confirmLabel: 'حوّل',
        cancelLabel: 'إلغاء',
        icon: LucideIcons.send,
        tone: _toSas ? AppTone.brand : AppTone.warning,
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await JtpayApi.transfer(to: widget.to, amount: a!, target: _toSas ? null : target, confirmRepeat: confirmRepeat);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.code == 'RECENT_DUPLICATE') {
      final again = await showConfirmSheet(
        context,
        title: 'نفس التحويل صار قبل شوي',
        message: r.message ?? 'حوّلت نفس المبلغ لنفس الصفحة قبل قليل. تريده مرّة ثانية؟',
        confirmLabel: 'حوّل مرّة ثانية',
        cancelLabel: 'لا',
        icon: LucideIcons.triangleAlert,
        tone: AppTone.warning,
      );
      if (again == true && mounted) await _submit(confirmRepeat: true);
      return;
    }
    final op = r.data ?? r.op;
    if (op != null) {
      Navigator.of(context).pop(op);
      return;
    }
    if (r.noVerdict) {
      // وصل الطلب ولم يصل الحكم: لا «فشل» — يُراجَع قبل أيّ إعادة.
      setState(() => _error = 'ما تأكّدنا من التحويل — راجع رصيدك وسجلّ العمليّات قبل ما تعيد');
      return;
    }
    setState(() => _error = r.message ?? 'لم يتمّ التحويل');
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final bal = widget.balance;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: _toSas ? LucideIcons.arrowDownToLine : LucideIcons.send,
        title: _toSas ? 'تحويل لصفحتك بالساس' : 'تحويل لصفحة ثانية',
        subtitle: bal == null ? 'رصيد pay: —' : 'رصيد pay: ${formatIQD(bal)} د.ع',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_toSas) ...[
            SheetSection(
              label: 'اسم الصفحة',
              footnote: 'مثل ما مسجّل بنظام الجزيرة — التحويل لا يرجع',
              child: SheetBox(
                focused: false,
                icon: LucideIcons.user,
                child: TextField(
                  controller: _targetCtrl,
                  enabled: !_busy,
                  textDirection: TextDirection.ltr,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.emailAddress,
                  style: AppType.input(),
                  decoration: InputDecoration(
                    hintText: 'admin@name',
                    hintStyle: AppType.input(color: AppColors.textLow),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(height: Sp.lg),
          ],
          SheetSection(
            label: 'المبلغ (د.ع)',
            footnote: 'أقلّ مبلغ ${formatIQD(widget.minAmount)} د.ع',
            child: SheetBox(
              focused: false,
              child: AmountTextField(
                controller: _amountCtrl,
                enabled: !_busy,
                currency: 'د.ع',
                onValue: (_) => setState(() {}),
              ),
            ),
          ),
          if (bal != null && bal >= widget.minAmount) ...[
            const SizedBox(height: Sp.sm),
            Wrap(
              spacing: Sp.sm,
              runSpacing: Sp.sm,
              children: [
                SheetQuickChip(
                  label: 'كلّ الرصيد',
                  suggested: true,
                  selected: _amount == bal.floor(),
                  onTap: () {
                    final t = AmountShorthand.format(bal.floor());
                    setState(() => _amountCtrl.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length)));
                  },
                ),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Sp.md),
            Text(_error!, style: AppType.body(color: AppTone.danger.onSoft)),
          ],
        ],
      ),
      footer: SheetFooterBar(
        label: 'حوّل',
        icon: LucideIcons.send,
        busy: _busy,
        onPressed: _busy ? null : _submit,
      ),
    );
  }
}

// ═════════════════════════ سجلّ موقع الشحن ═════════════════════════

class _SiteHistorySheet extends StatefulWidget {
  const _SiteHistorySheet();

  @override
  State<_SiteHistorySheet> createState() => _SiteHistorySheetState();
}

class _SiteHistorySheetState extends State<_SiteHistorySheet> {
  static const _tabs = [('recharge', 'التعبئة'), ('credit', 'الرصيد'), ('transfer', 'التحويلات')];
  String _tab = 'recharge';
  final Map<String, JtpayReply<List<JtpaySiteRow>>> _cache = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetch(_tab);
  }

  Future<void> _fetch(String tab) async {
    setState(() => _loading = true);
    final r = await JtpayApi.siteHistory(tab);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _cache[tab] = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final r = _cache[_tab];
    final rows = r?.data ?? const <JtpaySiteRow>[];
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.history,
        title: 'سجلّ موقع الشحن',
        subtitle: 'كما يعرضه موقع pay الجزيرة',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Sp.sm,
            runSpacing: Sp.sm,
            children: [
              for (final (id, label) in _tabs)
                SheetQuickChip(
                  label: label,
                  selected: _tab == id,
                  onTap: () {
                    setState(() => _tab = id);
                    if (!_cache.containsKey(id)) _fetch(id);
                  },
                ),
            ],
          ),
          const SizedBox(height: Sp.md),
          if (_loading && r == null)
            const Padding(padding: EdgeInsets.all(Sp.huge), child: Center(child: CircularProgressIndicator()))
          else if (r != null && r.data == null)
            Text(r.message ?? 'تعذّر جلب السجلّ', style: AppType.body(color: AppTone.danger.onSoft))
          else if (rows.isEmpty)
            Text('لا توجد عمليّات', style: AppType.muted())
          else
            for (final row in rows) _siteRow(row),
        ],
      ),
    );
  }

  Widget _siteRow(JtpaySiteRow row) {
    final amt = row.amount;
    final title = [
      if (row.op != null) row.op!,
      if (amt != null) '${amt > 0 && _tab != 'recharge' ? '+' : ''}${formatIQD(amt)} د.ع',
    ].join(' · ');
    final sub = [
      if (row.no != null) '#${row.no}',
      if (row.status != null) row.status!,
      if (row.method != null) row.method!,
      if (row.kind != null) row.kind!,
      if (row.party != null) iso(row.party!),
      if (row.at != null) row.at!.substring(0, row.at!.length >= 16 ? 16 : row.at!.length),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.isEmpty ? '—' : title, style: AppType.bodyStrong(color: AppColors.textHi)),
          const SizedBox(height: Sp.xxs),
          Text(sub, style: AppType.muted()),
        ],
      ),
    );
  }
}
