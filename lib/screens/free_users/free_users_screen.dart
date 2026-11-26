import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/free_users_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/permission_locked.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../models/subscriber.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/merged_section.dart';
import '../desktop/desk_widgets.dart';
import '../subscribers/sheets/add_debt_sheet.dart';
import '../subscribers/sheets/movements_sheet.dart';
import '../subscribers/sheets/pay_debt_sheet.dart';
import '../subscribers/sheets/subscriber_picker_sheet.dart';
import '../subscribers/widgets/subscriber_actions.dart';

/// «اليوزرات الفري» بالتطبيق (٢٦ نوفمبر — المالك: «تمام كلشي يعني تطبيق وويب»): يوزرٌ تعطيه الشركة فري يُخصَّص لمشترك بسعره
/// الشهريّ؛ البيع يشغّله ويمدّ «مدفوع لحدّ» بنفس الساعة، والنظام يطفّيه عند انتهائه ويبلّغ المشترك. كالموقع /v2/free-users حرفاً:
/// التخصيص، البيع/التجديد (نقدي/جزئي/دين)، التعديل، السجلّ، «مدّة فحص» لصفحات الفحص، الترك — و«تسديد» و«إضافة دين» بنوافذ صفحة
/// المشتركين نفسها باسم الحامل ورقمه، و«كشف حساب» من بداية حامله. الموظّف بلا مفتاحٍ يرى الزرّ مقفلاً بمكانه لا مخفيّاً.
/// الأزرار (٢٦ نوفمبر — المالك: «مو منطقي … وماخذات مساحه … وزر التسديد مفترض مايظهر الا من يكون بالدين حاكي العمليات»):
/// بنمط «العمليات» بصفحة المشترك — أربع بلاطات (بيع/تجديد · السجلّ · كشف حساب · المزيد) وشيت «إجراءات أخرى» للباقي، وبلوك الدين
/// بزرّ «تسديد» حين يكون عليه دينٌ معروف وحده.
class FreeUsersScreen extends StatefulWidget {
  const FreeUsersScreen({super.key});

  static const title = 'اليوزرات الفري';

  /// «كل الشركات»: للمفتوحة وحدها (الخادم لا يوجّه القسم بعد).
  static Widget mergedPage() =>
      const MergedSection.openOnly(title: title, reason: 'يوزرات الصفحة المفتوحة وحدها', child: FreeUsersScreen());

  @override
  State<FreeUsersScreen> createState() => _FreeUsersScreenState();
}

class _FreeUsersScreenState extends State<FreeUsersScreen> {
  FreeList? _list;
  bool _loading = true;
  FreeState? _view; // null = الكلّ
  int? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await FreeUsersApi.list();
    if (!mounted) return;
    setState(() {
      _list = l;
      _loading = false;
    });
    if (l != null) FreeUsersState.seen(l);
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.errorFill : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.textHi),
          title: Text(FreeUsersScreen.title, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        ),
        title: FreeUsersScreen.title,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
                children: _body(),
              ),
            ),
    );
  }

  List<Widget> _body() {
    final l = _list;
    if (l == null) return [_center(LucideIcons.wifiOff, 'تعذّرت قراءة اليوزرات الفري', 'اسحب للأسفل لإعادة المحاولة')];
    if (!l.enabled) return [_center(LucideIcons.gift, '«اليوزرات الفري» غير مفعّلة لحسابك بعد', l.reason ?? '')];
    final s = l.summary ?? const FreeSummary();
    final items = [for (final it in l.items) if (_view == null || it.state == _view) it];
    final canManage = Perms.has('free.manage');
    return [
      Text('بِع يوزرات الشركة الفري شهريّاً لمشتركيك — يُطفأ اليوزر تلقائيّاً عند انتهاء مدّته ويُبلَّغ المشترك، والبيع يدخل التقارير والتسوية',
          style: AppType.muted(color: AppColors.textMid).copyWith(height: 1.5)),
      const SizedBox(height: Sp.md),
      // البطاقتان بالسطر بارتفاعٍ واحد (تسميةٌ تلتفّ لا تُطيل جارتها وحدها)
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _stat(LucideIcons.gift, 'شغّال', s.active, AppColors.success, AppColors.successSoftBg, FreeState.active)),
          const SizedBox(width: Sp.sm),
          Expanded(
              child: _stat(LucideIcons.hourglass, 'ينتهي خلال يوم', s.endingSoon, AppColors.warningOnSoft, AppColors.warningSoftBg, FreeState.active)),
        ]),
      ),
      const SizedBox(height: Sp.sm),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _stat(LucideIcons.power, 'منتهٍ — مطفأ', s.expired, AppColors.dangerOnSoft, AppColors.dangerSoftBg, FreeState.expired)),
          const SizedBox(width: Sp.sm),
          Expanded(child: _stat(LucideIcons.clock, 'بانتظار البيع', s.pending, AppColors.info, AppColors.infoSoftBg, FreeState.pending)),
        ]),
      ),
      if (s.sales30 > 0) ...[
        const SizedBox(height: Sp.sm),
        _card(Wrap(spacing: Sp.lg, runSpacing: Sp.xs, children: [
          _kv('آخر ٣٠ يوماً', '${s.sales30} بيع'),
          _kv('المجموع', '${formatIQD(s.total30)} د.ع'),
          _kv('المستلم', '${formatIQD(s.paid30)} د.ع'),
          if (s.debt30 > 0) _kv('دين', '${formatIQD(s.debt30)} د.ع', color: AppColors.dangerOnSoft),
        ])),
      ],
      const SizedBox(height: Sp.md),
      FilledButton.icon(
        key: const ValueKey('free-assign'),
        onPressed: canManage ? _assign : null,
        icon: Icon(canManage ? LucideIcons.userPlus : LucideIcons.lock, size: 18),
        label: const Text('تخصيص يوزر'),
      ),
      const SizedBox(height: Sp.md),
      // يلتفّ لسطرٍ ثانٍ ولا يُقصّ عند الحافّة (٣٢٠ بخطٍّ ×١٫٢)
      Wrap(spacing: Sp.sm, runSpacing: Sp.xs, children: [
        _chip(null, 'الكلّ'),
        _chip(FreeState.active, 'شغّال'),
        _chip(FreeState.expired, 'منتهٍ'),
        _chip(FreeState.pending, 'بانتظار البيع'),
      ]),
      const SizedBox(height: Sp.md),
      if (items.isEmpty)
        _center(LucideIcons.gift, _view == null ? 'لا يوزرات فري مخصَّصة بعد' : 'لا شيء بهذه الحالة',
            'خصّص يوزراً فري أعطته الشركة لمشترك بسعره الشهريّ — يُطفأ تلقائيّاً بنفس الساعة حين تنتهي مدّته')
      else
        for (final it in items) ...[_itemCard(l, it), const SizedBox(height: Sp.sm)],
    ];
  }

  // ═══════════════ البطاقة ═══════════════

  Widget _itemCard(FreeList l, FreeItem it) {
    final canSell = Perms.has('free.sell');
    final canPay = Perms.has('subscribers.pay_debt');
    final canStatement = Perms.has('subscribers.view_activity');
    final busy = _busy == it.id;
    final (badgeFg, badgeBg, badgeText) = switch (it.state) {
      FreeState.active => (AppColors.success, AppColors.successSoftBg, 'شغّال'),
      FreeState.expired => (AppColors.dangerOnSoft, AppColors.dangerSoftBg, 'منتهٍ — مطفأ'),
      FreeState.pending => (AppColors.warningOnSoft, AppColors.warningSoftBg, 'بانتظار البيع'),
    };
    return _card(
      key: ValueKey('free-card-${it.id}'),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(it.subName ?? 'بلا اسم مشترك',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyStrong(color: AppColors.textHi)),
              const SizedBox(height: 2),
              Text(iso([it.username, if (it.subPhone != null) it.subPhone!].join(' · ')),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textMid)),
            ]),
          ),
          const SizedBox(width: Sp.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
            decoration: BoxDecoration(color: badgeBg, borderRadius: BorderRadius.circular(R.pill)),
            child: Text(badgeText, style: AppType.microBold(color: badgeFg)),
          ),
        ]),
        const SizedBox(height: Sp.sm),
        Row(children: [
          Expanded(child: _box('السعر الشهريّ', '${formatIQD(it.price)} د.ع')),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: _box('مدفوع لحدّ', it.paidUntil == null ? '—' : iso(it.paidUntil!),
                foot: it.paidUntil == null ? null : freeLeftText(it.minutesLeft)),
          ),
        ]),
        if (it.failCount > 0 && it.state == FreeState.active) ...[
          const SizedBox(height: Sp.sm),
          Container(
            padding: const EdgeInsets.all(Sp.sm),
            decoration: BoxDecoration(
              color: AppColors.warningSoftBg,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.warningSoftBorder),
            ),
            child: Text('انتهت مدّته ولم يُطفأ ${l.where} بعد — النظام يعيد المحاولة (${it.failCount})',
                style: AppType.label(color: AppColors.warningOnSoft)),
          ),
        ],
        if (it.inDebt) ...[
          const SizedBox(height: Sp.sm),
          _debtBlock(it, canPay: canPay, busy: busy),
        ],
        const SizedBox(height: Sp.md),
        // «العمليات» كصفحة المشترك: أربع بلاطات بصفٍّ واحد، والباقي في «المزيد»
        SubscriberActionTiles(actions: [
          SubAction(
            key: ValueKey('free-btn-sell-${it.id}'),
            icon: LucideIcons.badgeDollarSign,
            label: it.state == FreeState.pending ? 'بيع' : 'تجديد',
            filled: true,
            locked: !canSell,
            onTap: busy ? null : () => _sell(it),
          ),
          SubAction(
            key: ValueKey('free-btn-hist-${it.id}'),
            icon: LucideIcons.history,
            label: 'السجلّ',
            onTap: busy ? null : () => _history(it),
          ),
          SubAction(
            key: ValueKey('free-btn-stmt-${it.id}'),
            icon: LucideIcons.fileText,
            label: 'الكشف',
            locked: !canStatement,
            onTap: busy ? null : () => _statement(it),
          ),
          SubAction(
            key: ValueKey('free-btn-more-${it.id}'),
            icon: Icons.more_horiz_rounded,
            label: 'المزيد',
            busy: busy,
            onTap: busy ? null : () => _more(l, it),
          ),
        ]),
      ]),
    );
  }

  /// بلوك الدين (٢٦ نوفمبر — المالك: «زر التسديد مفترض مايظهر الا من يكون بالدين»): عليه دينٌ معروف ⇒ المبلغ وزرّ «تسديد» بجانبه،
  /// كبلوك الدين بصفحة المشترك. لا دين ⇒ لا بلوك ولا «تسديد» أبداً؛ دينٌ لا يُعرف (خادمٌ أقدم، دين الساس، تعذّرٌ) ⇒ «تسديد» في «المزيد».
  Widget _debtBlock(FreeItem it, {required bool canPay, required bool busy}) => Container(
        key: ValueKey('free-debt-${it.id}'),
        padding: const EdgeInsetsDirectional.fromSTEB(Sp.md, Sp.sm, Sp.sm, Sp.sm),
        decoration: BoxDecoration(
          color: AppColors.dangerSoftBg,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.dangerSoftBorder),
        ),
        child: Row(children: [
          Icon(LucideIcons.circleAlert, size: 18, color: AppColors.dangerOnSoft),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('عليه دين', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.dangerOnSoft)),
              Text(iso('${formatIQD(it.debt!)} د.ع'),
                  key: ValueKey('free-debt-amount-${it.id}'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyBold(color: AppColors.dangerOnSoft)),
            ]),
          ),
          const SizedBox(width: Sp.sm),
          FilledButton.icon(
            key: ValueKey('free-btn-pay-${it.id}'),
            // المقفل بمكانه: نقرته رسالة القفل (لا مخفيّ ولا معطّلٌ صامت)
            onPressed: !canPay ? () => showNoPermission(context, action: true) : (busy ? null : () => _debt(it, pay: true)),
            style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: Sp.md)),
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand))
                : Icon(canPay ? LucideIcons.handCoins : LucideIcons.lock, size: 16),
            label: const Text('تسديد'),
          ),
        ]),
      );

  /// «المزيد» = شيت «إجراءات أخرى» نفسه بصفحة المشترك: الدين، ثمّ اليوزر (تعديل، مدّة فحص لصفحات الفحص، ترك بالأحمر).
  Future<void> _more(FreeList l, FreeItem it) {
    final canManage = Perms.has('free.manage');
    final canPay = Perms.has('subscribers.pay_debt');
    final canAddDebt = Perms.has('subscribers.add_debt');
    return showMoreActionsSheet(context, subtitle: it.username, groups: [
      SubActionGroup('الدين', [
        if (!it.debtKnown)
          SubAction(
            key: ValueKey('free-btn-pay-${it.id}'),
            icon: LucideIcons.handCoins,
            label: 'تسديد',
            locked: !canPay,
            onTap: () => _debt(it, pay: true),
          ),
        SubAction(
          key: ValueKey('free-btn-debt-${it.id}'),
          icon: LucideIcons.circlePlus,
          label: 'إضافة دين',
          locked: !canAddDebt,
          onTap: () => _debt(it, pay: false),
        ),
      ]),
      SubActionGroup('اليوزر', [
        SubAction(
          key: ValueKey('free-btn-edit-${it.id}'),
          icon: LucideIcons.pencil,
          label: 'تعديل الاسم والهاتف والسعر',
          locked: !canManage,
          onTap: () => _edit(it),
        ),
        if (l.test && it.state == FreeState.active && canManage)
          SubAction(
            key: ValueKey('free-btn-test-${it.id}'),
            icon: LucideIcons.timer,
            label: 'مدّة فحص',
            onTap: () => _shorten(it),
          ),
        SubAction(
          key: ValueKey('free-btn-release-${it.id}'),
          icon: LucideIcons.logOut,
          label: 'ترك اليوزر',
          color: AppColors.error,
          locked: !canManage,
          onTap: () => _release(l, it),
        ),
      ]),
    ]);
  }

  // ═══════════════ الأفعال ═══════════════

  Future<void> _assign() async {
    final picked = await showSubscriberPickerSheet(context, title: 'اختر اليوزر الفري');
    if (picked == null || !mounted) return;
    final idx = picked.idx;
    if (idx == null || idx.isEmpty) return _snack('اليوزر بلا رقمٍ بالشركة — اختر غيره', error: true);
    if ((_list?.items ?? const []).any((x) => x.idx == idx)) return _snack('هذا اليوزر مخصَّصٌ أصلاً', error: true);
    final done = await showAppSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormSheet(
        title: 'تخصيص يوزر فري',
        subtitle: picked.username,
        submitLabel: 'تخصيص',
        submit: (name, phone, price, confirm) =>
            FreeUsersApi.create(idx: idx, subName: name, subPhone: phone, price: price, confirmNotFree: confirm),
        doneText: 'خُصِّص اليوزر — بِعه الآن ليبدأ اشتراكه',
      ),
    );
    if (done == true) await _load();
  }

  Future<void> _edit(FreeItem it) async {
    final done = await showAppSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FormSheet(
        title: 'تعديل',
        subtitle: it.username,
        submitLabel: 'حفظ',
        name: it.subName ?? '',
        phone: it.subPhone ?? '',
        price: it.price,
        submit: (name, phone, price, _) => FreeUsersApi.update(it.id, subName: name, subPhone: phone, price: price),
        doneText: 'حُفظ — السعر الجديد للبيع القادم',
      ),
    );
    if (done == true) await _load();
  }

  Future<void> _sell(FreeItem it) async {
    final done = await showAppSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SellSheet(item: it),
    );
    if (done == true) await _load();
  }

  Future<void> _history(FreeItem it) => showAppSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: AppColors.scrim,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _HistorySheet(item: it),
      );

  /// المشترك لنوافذ صفحة المشتركين: اسم الحامل ورقمه، ودينه من دفتر شركته (notes كما تقرؤه النافذة).
  Subscriber _subOf(FreeItem it, num? balance) => Subscriber.fromJson({
        'idx': it.idx,
        'username': it.username,
        'firstname': it.subName ?? it.username,
        'lastname': '',
        'phone': it.subPhone,
        if (balance != null) 'notes': '$balance',
      });

  Future<void> _debt(FreeItem it, {required bool pay}) async {
    setState(() => _busy = it.id);
    final d = await FreeUsersApi.debt(it.id);
    if (!mounted) return;
    setState(() => _busy = null);
    if (!d.ok) return _snack(d.message ?? 'تعذّرت قراءة الدين الآن', error: true);
    final sub = _subOf(it, d.balance);
    final ok = pay ? await showPayDebtSheet(context, sub) : await showAddDebtSheet(context, sub);
    if (ok == true) await _load();
  }

  Future<void> _statement(FreeItem it) => showMovementsSheet(context, _subOf(it, null), from: freeDay(it.holderFrom));

  Future<void> _shorten(FreeItem it) async {
    final ctrl = TextEditingController(text: '5');
    final m = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مدّة الفحص'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'ينتهي بعد كم دقيقة؟ (١–١٢٠)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())), child: const Text('تقصير')),
        ],
      ),
    );
    ctrl.dispose();
    if (m == null || m < 1 || m > 120 || !mounted) return;
    setState(() => _busy = it.id);
    final r = await FreeUsersApi.testShorten(it.id, m);
    if (!mounted) return;
    setState(() => _busy = null);
    if (!r.ok) return _snack(r.message ?? 'تعذّر تقصير المدّة', error: true);
    _snack('ينتهي بعد $m دقيقة — راقب الإطفاء والرسالة');
    await _load();
  }

  Future<void> _release(FreeList l, FreeItem it) async {
    final sure = await _confirm('ترك «${it.username}»؟', 'لن يديره النظام بعدها (لا بيع ولا إطفاء).', 'ترك');
    if (sure != true || !mounted) return;
    var enable = false;
    if (it.state == FreeState.expired) {
      enable = await _confirm('إرجاعه شغّالاً ${l.where}؟', 'كما أعطته الشركة', 'نعم، شغّله') == true;
      if (!mounted) return;
    }
    setState(() => _busy = it.id);
    final r = await FreeUsersApi.release(it.id, enable: enable);
    if (!mounted) return;
    setState(() => _busy = null);
    if (!r.ok) return _snack(r.message ?? 'تعذّر الترك', error: true);
    _snack('تُرك اليوزر — لم يعد النظام يديره');
    await _load();
  }

  Future<bool?> _confirm(String title, String body, String yes) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
          ],
        ),
      );

  // ═══════════════ عناصر ═══════════════

  Widget _chip(FreeState? v, String label) => ChoiceChip(
        key: ValueKey('free-view-${v?.name ?? 'all'}'),
        label: Text(label),
        selected: _view == v,
        showCheckmark: false,
        onSelected: (_) => setState(() => _view = v),
      );

  Widget _card(Widget child, {Key? key}) => Container(
        key: key,
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _box(String label, String value, {String? foot}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs + 2),
        decoration: BoxDecoration(color: AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.md)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textMid)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, maxLines: 1, style: AppType.bodyStrong(color: AppColors.textHi)),
          ),
          if (foot != null) Text(foot, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
        ]),
      );

  Widget _kv(String k, String v, {Color? color}) => Text.rich(TextSpan(children: [
        TextSpan(text: '$k ', style: AppType.label(color: AppColors.textMid)),
        TextSpan(text: iso(v), style: AppType.bodyStrong(color: color ?? AppColors.textHi)),
      ]));

  Widget _stat(IconData icon, String label, int n, Color fg, Color bg, FreeState view) => Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.lg),
          onTap: () => setState(() => _view = view),
          child: Container(
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.lg),
              border: Border.all(color: _view == view ? fg : AppColors.border),
            ),
            // الأيقونة والرقم بسطر، والتسمية تحته بعرض البطاقة كلّه — «ينتهي خلال يوم» كانت تُقصّ عند ٣٢٠ بخطٍّ ×١٫٢
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(R.sm)),
                  child: Icon(icon, size: 18, color: fg),
                ),
                const Spacer(),
                Text('$n', style: AppType.statValue(color: fg)),
              ]),
              const SizedBox(height: Sp.xs),
              Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textMid)),
            ]),
          ),
        ),
      );

  Widget _center(IconData icon, String title, String sub) => Padding(
        padding: const EdgeInsets.only(top: Sp.mega),
        child: Column(children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppColors.brandSoftBg, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: AppColors.brand),
          ),
          const SizedBox(height: Sp.md),
          Text(title, textAlign: TextAlign.center, style: AppType.bodyStrong(color: AppColors.textHi)),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: Sp.xs),
            Text(sub, textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textMid)),
          ],
        ]),
      );
}

// ═══════════════ تخصيص / تعديل ═══════════════

typedef _Submit = Future<FreeResult> Function(String name, String phone, int price, bool confirmNotFree);

/// «شهر» · «شهران» · «3 أشهر» · «12 شهراً».
String _monthsText(int m) => switch (m) {
      1 => 'شهر',
      2 => 'شهران',
      >= 3 && <= 10 => '$m أشهر',
      _ => '$m شهراً',
    };

String _digits(String v) =>
    v.replaceAllMapped(RegExp('[٠-٩]'), (m) => '${'٠١٢٣٤٥٦٧٨٩'.indexOf(m[0]!)}').replaceAll(RegExp(r'[^\d]'), '');

class _FormSheet extends StatefulWidget {
  const _FormSheet({
    required this.title,
    required this.subtitle,
    required this.submitLabel,
    required this.submit,
    required this.doneText,
    this.name = '',
    this.phone = '',
    this.price,
  });

  final String title, subtitle, submitLabel, doneText;
  final _Submit submit;
  final String name, phone;
  final int? price;

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  late final _name = TextEditingController(text: widget.name);
  late final _phone = TextEditingController(text: widget.phone);
  late final _price = TextEditingController(text: widget.price == null ? '' : '${widget.price}');
  bool _busy = false;
  String? _warn;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _price.dispose();
    super.dispose();
  }

  int get _priceValue => int.tryParse(_digits(_price.text)) ?? 0;

  Future<void> _go({bool confirm = false}) async {
    setState(() => _busy = true);
    final r = await widget.submit(_name.text.trim(), _digits(_phone.text), _priceValue, confirm);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(widget.doneText)));
      return;
    }
    if (r.code == 'FREE_NOT_FREE_LOOKING') {
      setState(() => _warn = r.message ?? 'لا يبدو هذا اليوزر فري');
      return;
    }
    showSheetSnack(context, r.message ?? 'تعذّر الآن', isError: true);
  }

  Widget _field(String label, TextEditingController c, {TextInputType? type, bool ltr = false, String? hint}) => SheetSection(
        label: label,
        child: SheetBox(
          child: TextField(
            controller: c,
            keyboardType: type,
            textDirection: ltr ? TextDirection.ltr : null,
            style: AppType.input(),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(isDense: true, border: InputBorder.none, hintText: hint),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.gift,
        title: widget.title,
        subtitle: widget.subtitle,
        subtitleLtr: true,
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _busy ? 'جارٍ…' : widget.submitLabel,
        icon: LucideIcons.check,
        enabled: !_busy && _priceValue > 0,
        busy: _busy,
        onPressed: () => _go(),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _field('اسم المشترك', _name, hint: 'الاسم الذي يظهر بالرسائل والتقارير'),
        const SizedBox(height: Sp.md),
        _field('رقم الواتساب', _phone, type: TextInputType.phone, ltr: true, hint: '07XXXXXXXXX'),
        const SizedBox(height: Sp.md),
        _field('السعر الشهريّ (د.ع)', _price, type: TextInputType.number, ltr: true, hint: '25000'),
        if (_warn != null) ...[
          const SizedBox(height: Sp.md),
          Container(
            key: const ValueKey('free-not-free-warn'),
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              color: AppColors.warningSoftBg,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.warningSoftBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_warn!, style: AppType.label(color: AppColors.warningOnSoft).copyWith(height: 1.5)),
              const SizedBox(height: Sp.sm),
              OutlinedButton(onPressed: _busy ? null : () => _go(confirm: true), child: const Text('هو فري — خصّصه')),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ═══════════════ بيع / تجديد ═══════════════

class _SellSheet extends StatefulWidget {
  const _SellSheet({required this.item});
  final FreeItem item;

  @override
  State<_SellSheet> createState() => _SellSheetState();
}

class _SellSheetState extends State<_SellSheet> {
  int _months = 1;
  String _pay = 'cash';
  final _partial = TextEditingController();
  bool _busy = false;
  String? _repeat;
  String? _unknown;

  @override
  void dispose() {
    _partial.dispose();
    super.dispose();
  }

  int get _total => widget.item.price * _months;
  int get _partialValue => int.tryParse(_digits(_partial.text)) ?? 0;
  bool get _partialOk => _pay != 'partial-cash' || (_partialValue > 0 && _partialValue < _total);

  Future<void> _go({bool confirmRepeat = false}) async {
    setState(() => _busy = true);
    final r = await FreeUsersApi.sell(widget.item.id,
        months: _months, paymentType: _pay, partialAmount: _pay == 'partial-cash' ? _partialValue : null, confirmRepeat: confirmRepeat);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      final until = '${r.data['paid_until'] ?? ''}';
      final warning = r.data['warning']?.toString();
      Navigator.of(context).pop(true);
      final m = ScaffoldMessenger.maybeOf(context);
      m?.showSnackBar(SnackBar(
          content: Text('تمّ البيع — مدفوع لحدّ ${until.length > 16 ? until.substring(0, 16) : until}'
              '${r.data['enabled_now'] == true ? ' (شُغّل اليوزر)' : ''}${warning == null || warning.isEmpty ? '' : '\n$warning'}')));
      return;
    }
    if (r.code == 'RECENT_DUPLICATE') {
      setState(() => _repeat = r.message ?? 'بيعٌ قريب على هذا اليوزر');
    } else if (r.code == 'OUTCOME_UNKNOWN') {
      setState(() => _unknown = r.message ?? 'لم يتأكّد البيع — تحقّق قبل أيّ تكرار');
    } else if (r.code == FreeUsersApi.noReply) {
      // انقطع قبل ردّ الخادم ⇒ ربّما تمّ البيع (FreeUsersApi.noReply) — لا «تعذّر» ولا ضغطةٌ ثانية حتى يُراجَع
      setState(() => _unknown = 'انقطع الاتّصال قبل ردّ الخادم — لم يتأكّد البيع. أغلق النافذة واسحب القائمة للتحديث، وتأكّد من «مدفوع لحدّ» قبل أيّ تكرار.');
    } else {
      showSheetSnack(context, r.message ?? 'تعذّر البيع', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final it = widget.item;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.badgeDollarSign,
        title: '${it.state == FreeState.pending ? 'بيع' : 'تجديد'} — ${it.title}',
        subtitle: '${iso(it.username)} · ${iso('${formatIQD(it.price)} د.ع')} شهريّاً',
        onClose: () => Navigator.of(context).pop(),
      ),
      footer: SheetFooterBar(
        label: _busy ? 'جارٍ البيع…' : 'بيع ${formatIQD(_total)} د.ع',
        icon: LucideIcons.check,
        enabled: !_busy && _partialOk && _unknown == null,
        busy: _busy,
        onPressed: () => _go(),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetSection(
          label: 'المدّة',
          child: Wrap(spacing: 7, runSpacing: 7, children: [
            for (final m in const [1, 2, 3, 6, 12])
              SheetQuickChip(label: _monthsText(m), selected: _months == m, onTap: () => setState(() => _months = m)),
          ]),
        ),
        const SizedBox(height: Sp.md),
        SheetSection(
          label: 'الدفع',
          child: Wrap(spacing: 7, runSpacing: 7, children: [
            for (final p in const [('cash', 'نقدي'), ('partial-cash', 'جزئي'), ('non-cash', 'دين')])
              SheetQuickChip(label: p.$2, selected: _pay == p.$1, onTap: () => setState(() => _pay = p.$1)),
          ]),
        ),
        if (_pay == 'partial-cash') ...[
          const SizedBox(height: Sp.md),
          SheetSection(
            label: 'المدفوع الآن (د.ع)',
            child: SheetBox(
              child: TextField(
                key: const ValueKey('free-partial'),
                controller: _partial,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                style: AppType.input(),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(isDense: true, border: InputBorder.none),
              ),
            ),
          ),
        ],
        const SizedBox(height: Sp.md),
        SheetBox(
          child: Row(children: [
            Expanded(child: Text('المجموع', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textMid))),
            Text(iso('${formatIQD(_total)} د.ع'), style: AppType.bodyStrong(color: AppColors.textHi)),
          ]),
        ),
        if (_repeat != null) ...[
          const SizedBox(height: Sp.md),
          Container(
            key: const ValueKey('free-repeat'),
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              color: AppColors.warningSoftBg,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.warningSoftBorder),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_repeat!, style: AppType.label(color: AppColors.warningOnSoft).copyWith(height: 1.5)),
              const SizedBox(height: Sp.sm),
              OutlinedButton(onPressed: _busy ? null : () => _go(confirmRepeat: true), child: const Text('أكّد البيع مرّةً أخرى')),
            ]),
          ),
        ],
        if (_unknown != null) ...[
          const SizedBox(height: Sp.md),
          Container(
            key: const ValueKey('free-unknown'),
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              color: AppColors.dangerSoftBg,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.dangerSoftBorder),
            ),
            child: Text(_unknown!, style: AppType.label(color: AppColors.dangerOnSoft).copyWith(height: 1.5)),
          ),
        ],
      ]),
    );
  }
}

// ═══════════════ السجلّ ═══════════════

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.item});
  final FreeItem item;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  ({List<FreeSale> sales, List<FreeEvent> events})? _h;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(FreeUsersApi.history(widget.item.id).then((h) {
      if (!mounted) return;
      setState(() {
        _h = h;
        _loading = false;
      });
    }));
  }

  String _cut(String? s) => s == null ? '—' : (s.length > 16 ? s.substring(0, 16) : s);

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final h = _h;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.history,
        title: 'السجلّ — ${widget.item.title}',
        subtitle: 'المبيعات والإطفاء والرسائل',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(Sp.xl), child: Center(child: CircularProgressIndicator()))
          : h == null
              ? Text('تعذّرت القراءة الآن', style: AppType.label(color: AppColors.dangerOnSoft))
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  SheetSection(
                    label: 'المبيعات',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (h.sales.isEmpty) Text('لا مبيعات بعد', style: AppType.muted(color: AppColors.textMid)),
                      for (final s in h.sales) ...[
                        SheetBox(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Row(children: [
                              Expanded(
                                  child: Text('${s.methodLabel} · ${_monthsText(s.months)}',
                                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textHi))),
                              Text(iso('${formatIQD(s.total)} د.ع'), style: AppType.bodyStrong(color: AppColors.textHi)),
                            ]),
                            const SizedBox(height: 2),
                            Text(
                              '${iso(_cut(s.createdAt))} · لحدّ ${iso(_cut(s.paidUntilAfter))}${s.debt > 0 ? ' · دين ${iso('${formatIQD(s.debt)} د.ع')}' : ''}',
                              style: AppType.micro(color: AppColors.textMid),
                            ),
                          ]),
                        ),
                        const SizedBox(height: Sp.xs),
                      ],
                    ]),
                  ),
                  const SizedBox(height: Sp.md),
                  SheetSection(
                    label: 'الأحداث',
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (h.events.isEmpty) Text('لا أحداث بعد', style: AppType.muted(color: AppColors.textMid)),
                      for (final e in h.events) ...[
                        SheetBox(
                          child: Row(children: [
                            Expanded(child: Text(e.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textHi))),
                            Text(iso(_cut(e.createdAt)), style: AppType.micro(color: AppColors.textMid)),
                          ]),
                        ),
                        const SizedBox(height: Sp.xs),
                      ],
                    ]),
                  ),
                ]),
    );
  }
}
