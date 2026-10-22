import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/dashboard_api.dart';
import '../../api/earthlink_api.dart';
import '../../api/el_deposit_password.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/format.dart';
import '../../core/widgets/explain_action.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/el_deposit_password_field.dart';
import '../desktop/desk_widgets.dart';

/// ايرث لنك — تحويل الرصيد + كشف الحساب (البند ٤، EarthLink وحدهم).
///
///  ١) تحويل: رصيد الإيداع الحاليّ + مبلغ + موزّعٌ مستهدف + كلمة سرّ
///     الإيداع ← «تحويل» (يُعطَّل تحت ٥٬٠٠٠ أو ناقص الحقول). النجاح
///     يُحدّث الرصيد ويمسح المبلغ.
///  ٢) كشف الحساب: كلمة سرّ الإيداع + «عرض» ← جدول الحركات (التاريخ،
///     الوصف، المشترك، إيداع أخضر/سحب أحمر، الرصيد).
class ElTransferScreen extends StatefulWidget {
  const ElTransferScreen({super.key});

  @override
  State<ElTransferScreen> createState() => _ElTransferScreenState();
}

class _ElTransferScreenState extends State<ElTransferScreen> {
  /// أدنى مبلغ تحويل.
  static const int _minTransfer = 5000;

  // ── الرصيد ──
  num? _balance;
  bool _balanceLoading = true;

  // ── وجهات التحويل ──
  List<ElTransferTarget> _targets = const [];
  bool _targetsLoading = true;
  ElTransferTarget? _target;

  // ── التحويل ──
  final TextEditingController _amountCtrl = TextEditingController();
  // كلمة سرّ الإيداع: المحفوظة على الخادم («محفوظ · تغيير») أو تُكتب.
  final _txDeposit = ElDepositPasswordController();
  int _amount = 0;
  bool _transferring = false;

  // ── كشف الحساب ──
  final _stDeposit = ElDepositPasswordController();
  bool _stLoading = false;
  List<ElStatementEntry>? _statement;
  String? _stError;

  @override
  void initState() {
    super.initState();
    _txDeposit.addListener(_onDepositChanged);
    _stDeposit.addListener(_onDepositChanged);
    _loadAll();
    // محفوظة ⇒ كشف الحساب يُجلب فوراً بلا إدخال.
    ElDepositPassword.load().then((st) {
      if (mounted && st.saved && _statement == null && !_stLoading) {
        _loadStatement(quiet: true);
      }
    });
  }

  void _onDepositChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _txDeposit.removeListener(_onDepositChanged);
    _stDeposit.removeListener(_onDepositChanged);
    _txDeposit.dispose();
    _stDeposit.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadBalance(), _loadTargets()]);
  }

  Future<void> _loadBalance() async {
    if (mounted) setState(() => _balanceLoading = true);
    final w = await DashboardApi.fetchWallet();
    if (!mounted) return;
    setState(() {
      _balance = w?.balance;
      _balanceLoading = false;
    });
  }

  Future<void> _loadTargets() async {
    if (mounted) setState(() => _targetsLoading = true);
    final r = await EarthlinkApi.transferTargets();
    if (!mounted) return;
    setState(() {
      _targets = r.items;
      // إبقاء المختار إن بقي موجوداً، وإلّا إسقاطه.
      if (_target != null &&
          !_targets.any((t) => t.affiliateIndex == _target!.affiliateIndex)) {
        _target = null;
      }
      _targetsLoading = false;
    });
    if (r.message != null) _snack(r.message!, error: true);
  }

  bool get _canTransfer =>
      !_transferring &&
      _target != null &&
      _amount >= _minTransfer &&
      _txDeposit.ready;

  Future<void> _pickTarget() async {
    if (_targets.isEmpty) return;
    HapticFeedback.selectionClick();
    final picked = await showModalBottomSheet<ElTransferTarget>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      builder: (_) => _TargetPickerSheet(items: _targets, selected: _target),
    );
    if (picked == null || !mounted) return;
    setState(() => _target = picked);
  }

  Future<void> _doTransfer() async {
    if (!_canTransfer) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    setState(() => _transferring = true);
    final r = await EarthlinkApi.transfer(
      amount: _amount,
      targetAffiliateIndex: _target!.affiliateIndex,
      // null مع المحفوظة — الخادم يضيفها بنفسه.
      depositPassword: _txDeposit.passwordToSend,
      rememberDepositPassword: _txDeposit.rememberToSend,
    );
    if (!mounted) return;
    setState(() => _transferring = false);
    _snack(
      r.ok
          ? (r.message ?? 'تمّ تحويل ${formatIQD(_amount)} د.ع بنجاح')
          : (r.message ?? 'تعذّر إتمام التحويل'),
      error: !r.ok,
    );
    if (r.ok) {
      HapticFeedback.mediumImpact();
      setState(() {
        _amountCtrl.clear();
        _amount = 0;
      });
      _loadBalance();
    }
  }

  Future<void> _loadStatement({bool quiet = false}) async {
    if (!_stDeposit.ready) {
      _snack('أدخل كلمة سرّ الإيداع أوّلاً', error: true);
      return;
    }
    if (!quiet) {
      FocusScope.of(context).unfocus();
      HapticFeedback.selectionClick();
    }
    setState(() {
      _stLoading = true;
      _stError = null;
    });
    final r = await EarthlinkApi.accountStatement(
      depositPassword: _stDeposit.passwordToSend,
      rememberDepositPassword: _stDeposit.rememberToSend,
    );
    if (!mounted) return;
    setState(() {
      _stLoading = false;
      _statement = r.items;
      _stError = r.message;
    });
    if (r.message != null) _snack(r.message!, error: true);
  }

  /// الخطأ يحمل «اشرحلي» حين يكون رفضاً من الخادم والمساعد مفعّل
  /// ([explainableSnackBar]) — وإلّا الشريط كما كان.
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      explainableSnackBar(
        context,
        msg,
        error: error,
        style: AppType.button(color: AppColors.onBrand),
        backgroundColor: error ? AppColors.errorFill : AppColors.brand,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
        margin: const EdgeInsets.all(Sp.lg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
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
                Text('تحويل الرصيد',
                    style: AppType.title(color: AppColors.textHi)
                        .copyWith(fontSize: 16)),
                Text('تحويل بين الوكلاء + كشف الحساب',
                    style: AppType.muted().copyWith(fontSize: 11)),
              ],
            ),
          ),
        ),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadAll,
            color: AppColors.brandAccent,
            child: ListView(
              padding:
                  const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: [
                _balanceCard(),
                const SizedBox(height: Sp.lg),
                _transferSection(),
                const SizedBox(height: Sp.xl),
                _statementSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════ الرصيد ═══════════════

  Widget _balanceCard() {
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(R.card),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.onBrandFill2,
              borderRadius: BorderRadius.circular(R.icon),
            ),
            child: const Icon(LucideIcons.wallet,
                color: AppColors.onBrand, size: 22),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('رصيد الإيداع الحاليّ',
                    style: AppType.label(color: AppColors.onBrandSecondary)),
                const SizedBox(height: 4),
                if (_balanceLoading)
                  const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.onBrand),
                  )
                else
                  Row(
                    textBaseline: TextBaseline.alphabetic,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    children: [
                      Text(
                        _balance == null ? '—' : formatIQD(_balance!),
                        textDirection: TextDirection.ltr,
                        style: AppType.amount(color: AppColors.onBrand)
                            .copyWith(fontSize: 22),
                      ),
                      const SizedBox(width: 6),
                      Text('د.ع',
                          style: AppType.body(color: AppColors.onBrandSecondary)),
                    ],
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _balanceLoading ? null : _loadBalance,
            icon: const Icon(LucideIcons.refreshCw,
                color: AppColors.onBrandStrong, size: 18),
            tooltip: 'تحديث',
          ),
        ],
      ),
    );
  }

  // ═══════════════ التحويل ═══════════════

  Widget _transferSection() {
    return _SectionCard(
      icon: LucideIcons.arrowRightLeft,
      title: 'تحويل رصيد',
      children: [
        _label('المبلغ'),
        const SizedBox(height: Sp.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceInput,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: AmountTextField(
            controller: _amountCtrl,
            onValue: (v) => setState(() => _amount = v),
          ),
        ),
        const SizedBox(height: Sp.xs),
        Text('أدنى مبلغ للتحويل ${formatIQD(_minTransfer)} د.ع',
            style: AppType.muted(color: AppColors.textMid)),
        const SizedBox(height: Sp.md),
        _label('الموزّع المستهدف'),
        const SizedBox(height: Sp.sm),
        _targetField(),
        const SizedBox(height: Sp.md),
        _label('كلمة سرّ الإيداع'),
        const SizedBox(height: Sp.sm),
        ElDepositPasswordField(
          controller: _txDeposit,
          enabled: !_transferring,
          hint: '••••••',
        ),
        const SizedBox(height: Sp.lg),
        _primaryButton(
          label: 'تحويل',
          icon: LucideIcons.arrowRightLeft,
          loading: _transferring,
          onTap: _canTransfer ? _doTransfer : null,
        ),
      ],
    );
  }

  Widget _targetField() {
    final label = _targetsLoading
        ? 'جارٍ التحميل…'
        : (_target?.affiliateName ??
            (_targets.isEmpty ? 'لا وجهات متاحة' : 'اختر الموزّع'));
    final hasValue = _target != null;
    return Material(
      color: AppColors.surfaceInput,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
        onTap: (_targetsLoading || _targets.isEmpty) ? null : _pickTarget,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(LucideIcons.user,
                  size: 18,
                  color: hasValue ? AppColors.brandAccent : AppColors.textLow),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: Text(
                  label,
                  style: AppType.input(
                      color: hasValue ? AppColors.textHi : AppColors.textLow),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_targetsLoading)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(LucideIcons.chevronDown,
                    size: 18, color: AppColors.textMid),
            ],
          ),
        ),
      ),
    );
  }

  // ═══════════════ كشف الحساب ═══════════════

  Widget _statementSection() {
    return _SectionCard(
      icon: LucideIcons.receiptText,
      title: 'كشف الحساب',
      children: [
        _label('كلمة سرّ الإيداع'),
        const SizedBox(height: Sp.sm),
        ElDepositPasswordField(
          controller: _stDeposit,
          enabled: !_stLoading,
          hint: '••••••',
          onSubmitted: _loadStatement,
        ),
        const SizedBox(height: Sp.md),
        _primaryButton(
          label: 'عرض كشف الحساب',
          icon: LucideIcons.listChecks,
          loading: _stLoading,
          onTap: _stLoading ? null : _loadStatement,
        ),
        if (_statement != null || _stError != null) ...[
          const SizedBox(height: Sp.lg),
          _statementResult(),
        ],
      ],
    );
  }

  Widget _statementResult() {
    if (_stError != null) {
      return _note(LucideIcons.triangleAlert, _stError!, tone: AppTone.danger);
    }
    final rows = _statement ?? const [];
    if (rows.isEmpty) {
      return _note(LucideIcons.inbox, 'لا توجد حركات في كشف الحساب');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: Sp.sm),
          _StatementRow(entry: rows[i]),
        ],
      ],
    );
  }

  // ═══════════════ عناصر مشتركة ═══════════════

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(right: 2),
        child: Text(text, style: AppType.label(color: AppColors.textMid)),
      );

  Widget _primaryButton({
    required String label,
    required IconData icon,
    required bool loading,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null && !loading;
    return SizedBox(
      height: H.button,
      child: Material(
        color: enabled ? AppColors.brand : AppColors.surfaceDisabled,
        borderRadius: BorderRadius.circular(R.button),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: loading ? null : onTap,
          child: Center(
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: AppColors.onBrand),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 18,
                          color: enabled
                              ? AppColors.onBrand
                              : AppColors.textLow),
                      const SizedBox(width: Sp.sm),
                      Text(
                        label,
                        style: AppType.button(
                            color: enabled
                                ? AppColors.onBrand
                                : AppColors.textLow),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _note(IconData icon, String text, {AppTone tone = AppTone.neutral}) {
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: tone.softBg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: tone.softBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tone.fill),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(text,
                style: AppType.body(color: AppColors.textBody)),
          ),
        ],
      ),
    );
  }
}

/// بطاقة قسم: رأسٌ بأيقونة وعنوان ثمّ محتوى.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: H.iconBox,
                height: H.iconBox,
                decoration: BoxDecoration(
                  color: AppColors.brandSoftBg,
                  borderRadius: BorderRadius.circular(R.icon),
                ),
                child: Icon(icon, size: 18, color: AppColors.brand),
              ),
              const SizedBox(width: Sp.md),
              Text(title, style: AppType.cardTitleBold(color: AppColors.textHi)),
            ],
          ),
          const SizedBox(height: Sp.lg),
          ...children,
        ],
      ),
    );
  }
}

/// وصف الحركة بالعربيّة. ايرث لنك يرسل أوصافاً ونوع حركةٍ إنجليزيّةً خاماً
/// («Refill user» · «Withdraw» · «Deposit» …)، والمدير لا يُعرض له إنجليزيّ
/// خام أبداً: تُعرَّب المعروفة، ولا يُستبدَل الوصف بنوع الحركة الخام قطّ،
/// والوصف العربيّ (حين يعرّبه الخادم) يمرّ كما هو، والفراغ يسقط لوصفٍ عامّ نظيف.
String _statementDesc(ElStatementEntry entry) {
  final raw = entry.description?.trim() ?? '';
  const known = {
    'refill user': 'تعبئة مشترك',
    'create user': 'إنشاء مشترك',
    'deposit': 'إيداع رصيد',
    'withdraw': 'سحب رصيد',
    'withdrawal': 'سحب رصيد',
  };
  final mapped = known[raw.toLowerCase()];
  if (mapped != null) return mapped;
  if (raw.isNotEmpty) return raw;
  return entry.isDeposit ? 'إيداع رصيد' : 'سحب رصيد';
}

/// صفّ حركةٍ في كشف الحساب — التاريخ والوصف والمشترك مع إيداع/سحب والرصيد.
class _StatementRow extends StatelessWidget {
  const _StatementRow({required this.entry});
  final ElStatementEntry entry;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final isIn = entry.isDeposit;
    final amount = isIn ? entry.deposit : entry.withdrawal;
    final tone = isIn ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceInput,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _statementDesc(entry),
                  style: AppType.bodyStrong(color: AppColors.textHi),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Sp.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isIn ? '+' : '-'}${formatIQD(amount)}',
                    textDirection: TextDirection.ltr,
                    style: AppType.rowValue(color: tone)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(isIn ? 'إيداع' : 'سحب',
                      style: AppType.muted(color: tone)),
                ],
              ),
            ],
          ),
          const SizedBox(height: Sp.xs),
          // الطرف (اسم المشترك) على سطرٍ مستقلّ وكامل العرض — كان يُزاحم الرصيد
          // والتاريخ في صفٍّ واحد فيفيض على ٣٢٠ ويُقصّ الاسم إلى «…» على ٣٦٠/٣٩٠.
          if (entry.party != null) ...[
            Row(
              children: [
                Icon(LucideIcons.user, size: 12, color: AppColors.textLow),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(entry.party!,
                      style: AppType.muted(color: AppColors.textMid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 3),
          ],
          // الرصيد والتاريخ في السطر التالي — الرصيد مرنٌ يُقصّ عند الضيق
          // والتاريخ ثابتٌ في الطرف، فلا فيضان مهما كبر الرقم.
          Row(
            children: [
              Icon(LucideIcons.wallet, size: 12, color: AppColors.textLow),
              const SizedBox(width: 4),
              Expanded(
                child: Text('الرصيد ${formatIQD(entry.balance)}',
                    textDirection: TextDirection.rtl,
                    style: AppType.muted(color: AppColors.textMid),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              if (entry.date != null) ...[
                const SizedBox(width: Sp.sm),
                Text(entry.date!,
                    textDirection: TextDirection.ltr,
                    style: AppType.muted(color: AppColors.textLow)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// قائمة اختيار الموزّع المستهدف.
class _TargetPickerSheet extends StatefulWidget {
  const _TargetPickerSheet({required this.items, required this.selected});
  final List<ElTransferTarget> items;
  final ElTransferTarget? selected;

  @override
  State<_TargetPickerSheet> createState() => _TargetPickerSheetState();
}

class _TargetPickerSheetState extends State<_TargetPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final q = _q.trim().toLowerCase();
    final items = q.isEmpty
        ? widget.items
        : widget.items
            .where((t) => t.affiliateName.toLowerCase().contains(q))
            .toList();
    final maxH = MediaQuery.sizeOf(context).height * 0.75;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Material(
        color: AppColors.surfaceSheet,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(R.sheet)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Padding(
              padding: EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg,
                  Sp.md + MediaQuery.viewInsetsOf(context).bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: H.grabber,
                      decoration: BoxDecoration(
                        color: AppColors.grabber,
                        borderRadius: BorderRadius.circular(R.pill),
                      ),
                    ),
                  ),
                  const SizedBox(height: Sp.md),
                  Text('اختر الموزّع',
                      textAlign: TextAlign.center,
                      style: AppType.sheetTitle(color: AppColors.textHi)),
                  if (widget.items.length > 6) ...[
                    const SizedBox(height: Sp.md),
                    TextField(
                      onChanged: (v) => setState(() => _q = v),
                      style: AppType.input(color: AppColors.textHi),
                      decoration: InputDecoration(
                        hintText: 'بحث',
                        prefixIcon: Icon(LucideIcons.search,
                            size: 18, color: AppColors.textLow),
                        filled: true,
                        fillColor: AppColors.surfaceInput,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.md),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.md),
                          borderSide: BorderSide(color: AppColors.border),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: Sp.md),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: Sp.sm),
                      itemBuilder: (_, i) {
                        final t = items[i];
                        final selected =
                            widget.selected?.affiliateIndex == t.affiliateIndex;
                        return Material(
                          color: selected
                              ? AppColors.brandSoftBg
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(R.md),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(R.md),
                            onTap: () => Navigator.of(context).pop(t),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: Sp.md, vertical: Sp.md),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(R.md),
                                border: Border.all(
                                    color: selected
                                        ? AppColors.brandSoftBorder
                                        : AppColors.border),
                              ),
                              child: Row(
                                children: [
                                  Icon(LucideIcons.user,
                                      size: 20, color: AppColors.brand),
                                  const SizedBox(width: Sp.md),
                                  Expanded(
                                    child: Text(t.affiliateName,
                                        style: AppType.rowLabelBold(
                                            color: AppColors.textHi),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                  if (selected)
                                    Icon(LucideIcons.circleCheck,
                                        size: 20, color: AppColors.brand),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
