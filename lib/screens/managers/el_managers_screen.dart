import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/el_managers_api.dart';
import '../../api/managers_api.dart';
import '../../core/util/format.dart';
import '../../core/widgets/permission_locked.dart';
import '../../services/permissions_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../el/transfer_screen.dart';
import '../reports/v2/report_kit.dart';
import 'custom_debts_screen.dart';
import 'sheets/el_topup_sheet.dart';
import 'sheets/el_wa_phone_sheet.dart';

/// «المدراء» لموزّع ايرث لنك (٢٠ نوفمبر ٢٠٢٦ — المالك: «قسم ايرثلنك نكدر نفتحله قسم المدراء بس خاص بس ديون اخرى وشحن رصيد للمدراء
/// يعني ماكو لا نقاط ولا سحب ولا تغيير معلومات»).
///
/// المدراء = الحسابات التابعة له في ايرث لنك. لكلٍّ عمليّتان ظاهرتان على بطاقته: «شحن رصيد» (من رصيد إيداع الوكيل — نقداً أو آجلاً،
/// والآجل يُسجَّل بـ«ديون أخرى») و«ديون أخرى» (دفترنا كمدراء الساس). ايرث لنك لا تعرض أرصدتهم ⇒ البطاقة تقول «آخر شحن» من سجلّنا.
///
/// الموظّف (المالك: «صلاحيات الموظفين اذا رد ينطي لموظف صلاحيه التحويل»): يدخل بـ`el_managers.view` أو `el_managers.topup`؛ «شحن رصيد»
/// بالثاني و«ديون أخرى» بـ`reports.manager_debts` — وما لا يملكه بمكانه مقفلاً. الشحن بكلمة مرور الإيداع المحفوظة وحدها (الخادم).
/// الميزة لم تُفتح للحساب (المفتاح بالخادم) ⇒ رسالةٌ، ولصاحب الحساب «تحويل الرصيد» القديم من هنا كي لا يفقده.
class ElManagersScreen extends StatefulWidget {
  const ElManagersScreen({super.key});

  @override
  State<ElManagersScreen> createState() => _ElManagersScreenState();
}

class _ElManagersScreenState extends State<ElManagersScreen> {
  num? _balance;
  List<ElManagerRow> _rows = const [];
  bool _loading = true;
  bool _enabled = true;
  bool _depositSaved = false;
  String? _error;

  bool get _canTopup => !Perms.isEmployee || Perms.has('el_managers.topup');
  bool get _canDebts => !Perms.isEmployee || Perms.has('reports.manager_debts');
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await ElManagersApi.list();
    if (!mounted) return;
    setState(() {
      _enabled = r.enabled;
      _balance = r.balance;
      _rows = r.rows;
      _depositSaved = r.depositSaved;
      _error = r.message;
      _loading = false;
    });
  }

  List<ElManagerRow> get _filtered {
    if (_query.isEmpty) return _rows;
    final q = _query.toLowerCase();
    return _rows.where((m) => m.name.toLowerCase().contains(q) || '${m.index}'.contains(q)).toList();
  }

  double get _totalOtherDebt => _rows.fold<double>(0, (a, m) => a + m.otherDebt);

  Future<void> _topup(ElManagerRow m) async {
    if (!_canTopup) return showNoPermission(context, action: true);
    final r = await showElTopupSheet(context, manager: m, balance: _balance, depositSaved: _depositSaved);
    if (r == null || !mounted) return;
    final line = r.noticeLine;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text([r.message ?? 'تمّ الشحن', if (r.feeLine != null) r.feeLine!, if (line != null) line].join('\n'),
          style: const TextStyle(height: 1.5)),
      backgroundColor: AppColors.brand,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 6),
    ));
    _load();
  }

  Future<void> _editWa(ElManagerRow m) async {
    if (!_canTopup) return showNoPermission(context, action: true);
    final saved = await showElWaPhoneSheet(context, manager: m);
    if (saved == true && mounted) _load();
  }

  Future<void> _debts(ElManagerRow m) async {
    if (!_canDebts) return showNoPermission(context, action: true);
    final mgr = Manager.fromJson({'id': m.index, 'username': m.name});
    if (mgr == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ManagerCustomDebtsScreen(manager: mgr)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final rows = _filtered;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: AppColors.textHi),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('المدراء', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
            Text('حساباتك التابعة في ايرث لنك', style: AppType.muted().copyWith(fontSize: 11)),
          ],
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.brandAccent,
          // الشكل الموحّد (المالك ٢٣ نوفمبر: «المدراء والخصومات والسعر الثابت كذلك»): بطاقتا أرقام، ثمّ بطاقة الحسابات التابعة بعنوانها
          // وعددها وحدّ ايرث لنك والبحث، وسطرٌ لكلّ حساب بزرّيه — بدل الرأس الأخضر وبطاقةٍ لكلّ حساب.
          child: ListView(
            padding: EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, MediaQuery.paddingOf(context).bottom + 32),
            children: [
              if (!_loading && !_enabled)
                _notEnabled()
              else ...[
                _kpis(),
                const SizedBox(height: Sp.md),
                RpCard(
                  key: const ValueKey('elmgr-list'),
                  padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      RpTitle(
                        icon: LucideIcons.listOrdered,
                        title: 'حساباتك التابعة',
                        tone: RpTone.neutral,
                        trailing: Text('${formatIQD(rows.length)} مدير', style: AppType.pillBold(color: AppColors.textMid)),
                      ),
                      const SizedBox(height: Sp.x6),
                      _scopeNote(),
                      const SizedBox(height: Sp.md),
                      RpSearchBox(
                        key: const ValueKey('elmgr-search'),
                        query: _query,
                        hint: 'ابحث باسم المدير',
                        onChanged: (v) => setState(() => _query = v.trim()),
                      ),
                      if (_loading) ...[
                        const SizedBox(height: Sp.xl),
                        const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: Sp.xl),
                      ] else if (rows.isEmpty)
                        _empty()
                      else ...[
                        const SizedBox(height: Sp.x6),
                        for (final (i, m) in rows.indexed) ...[
                          if (i > 0) Divider(height: 1, thickness: 1, color: AppColors.divider),
                          _ElManagerTile(
                            manager: m,
                            topupLocked: !_canTopup,
                            debtsLocked: !_canDebts,
                            onTopup: () => _topup(m),
                            onDebts: () => _debts(m),
                            onWa: () => _editWa(m),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// رصيد الإيداع (بإشارته) وعدد الحسابات التابعة وديونها الأخرى — بطاقتا التقارير الموحّدة.
  Widget _kpis() {
    final debt = _totalOtherDebt;
    final bal = _balance;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: RpKpiCard(
              key: const ValueKey('elmgr-kpi-balance'),
              kpi: RpKpi(
                label: 'رصيد إيداعك',
                value: bal ?? 0,
                display: bal == null ? '—' : null,
                icon: LucideIcons.wallet,
                tone: (bal ?? 0) < 0 ? RpTone.loss : RpTone.money,
              ),
              compareWith: '',
            ),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: RpKpiCard(
              key: const ValueKey('elmgr-kpi-count'),
              kpi: RpKpi(
                label: 'المدراء',
                value: _rows.length,
                display: arCount(_rows.length, one: 'مدير واحد', two: 'مديران', few: 'مدراء', many: 'مديراً'),
                icon: LucideIcons.users,
                tone: RpTone.info,
                hint: debt > 0 ? 'ديون أخرى عليهم ${rpMoney(debt)}' : null,
              ),
              compareWith: '',
            ),
          ),
        ],
      ),
    );
  }

  Widget _scopeNote() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: Icon(LucideIcons.info, size: 13, color: AppColors.textMid)),
        const SizedBox(width: 6),
        Expanded(
          child: Text('ايرث لنك تسمح بشحن رصيدهم وحده — لا سحب ولا نقاط ولا تعديل معلومات', style: AppType.micro(color: AppColors.textMid)),
        ),
      ],
    );
  }

  /// الميزة لم تُفتح للحساب بعد — ولصاحبه «تحويل الرصيد» كما كان (لا يفقد التحويل في الانتظار).
  Widget _notEnabled() {
    return RpCard(
      padding: const EdgeInsets.all(Sp.xl),
      child: Column(
        children: [
          Icon(LucideIcons.userCog, size: 36, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text('قسم «المدراء» لم يُفتح لحسابك بعد',
              textAlign: TextAlign.center, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 14)),
          const SizedBox(height: 4),
          Text('يُفتح قريباً — شحن رصيد حساباتك التابعة وديونها الأخرى من هنا',
              textAlign: TextAlign.center, style: AppType.muted().copyWith(fontSize: 12.5)),
          if (!Perms.isEmployee) ...[
            const SizedBox(height: Sp.md),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ElTransferScreen())),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textHi,
                side: BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
              ),
              icon: Icon(LucideIcons.arrowRightLeft, size: 16, color: AppColors.brandAccent),
              label: const Text('تحويل الرصيد', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.xl),
      child: Column(
        children: [
          Icon(LucideIcons.userX, size: 36, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text(_error ?? (_query.isEmpty ? 'لا حسابات تابعة لك في ايرث لنك' : 'لا نتائج لـ«$_query»'),
              textAlign: TextAlign.center, style: AppType.muted(color: AppColors.textHi).copyWith(fontSize: 13)),
        ],
      ),
    );
  }
}

/// التاريخ رقماً «2026/11/18» كتقارير البرو.
String _ymd(DateTime d) => '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

class _ElManagerTile extends StatelessWidget {
  const _ElManagerTile({
    required this.manager,
    required this.onTopup,
    required this.onDebts,
    required this.onWa,
    this.topupLocked = false,
    this.debtsLocked = false,
  });
  final ElManagerRow manager;
  final VoidCallback onTopup;
  final VoidCallback onDebts;
  final VoidCallback onWa;
  final bool topupLocked;
  final bool debtsLocked;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final m = manager;
    // سطرٌ بشكل سطور التقارير الموحّدة (٢٣ نوفمبر): مربّع الأيقونة، الاسم ورقمه، ديونه الأخرى وآخر شحنٍ وواتسابه سطوراً — وزرّا
    // «شحن رصيد» و«ديون أخرى» تحت النصّ.
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const RpIconBox(icon: LucideIcons.shield, tone: RpTone.brand, size: 36),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.bodyBold(color: AppColors.textHi)),
                    Text('حساب تابع · #${m.index}', style: AppType.micro(color: AppColors.textMid)),
                    Text(
                      m.otherDebt > 0 ? 'ديون أخرى ${rpMoney(m.otherDebt)}' : 'ديون أخرى: لا شيء',
                      style: m.otherDebt > 0 ? AppType.microBold(color: AppColors.warning) : AppType.micro(color: AppColors.textLow),
                    ),
                    if (m.lastTopupAmount != null && m.lastTopupAt != null)
                      Text(
                        'آخر شحن ${formatIQD(m.lastTopupAmount!)} · ${_ymd(m.lastTopupAt!)}${m.lastTopupAsDebt ? ' · آجل' : ''}',
                        style: AppType.micro(color: AppColors.textMid),
                      ),
                    const SizedBox(height: Sp.xxs),
                    // واتساب الإشعار: رقم جلسته (لا يُعدَّل) أو المحفوظ (يُعدَّل)، وبلا رقم «أضف رقم واتساب»
                    if (m.waPhone != null)
                      _chip(
                        icon: LucideIcons.messageCircle,
                        label: 'واتساب',
                        value: m.waPhone!,
                        color: AppColors.channelWhatsApp,
                        ltr: true,
                        onTap: m.waEditable && !topupLocked ? onWa : null,
                      )
                    else if (!topupLocked)
                      _chip(
                        icon: LucideIcons.plus,
                        label: 'أضف رقم واتساب',
                        value: '',
                        color: AppColors.textMid,
                        onTap: onWa,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          // الزرّان بعرض السطر (لا تحت النصّ وحده): على ٣٢٠ التفّ «شحن رصيد» سطرين؛ والكلمة سطرٌ واحد يصغر ولا يلتفّ
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onTopup,
                  style: FilledButton.styleFrom(
                    backgroundColor: topupLocked ? LockedStyle.box : AppColors.brand,
                    foregroundColor: topupLocked ? LockedStyle.title : AppColors.onBrand,
                    minimumSize: const Size.fromHeight(36),
                    padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
                  ),
                  icon: topupLocked ? const PermLockIcon(size: 15) : const Icon(LucideIcons.arrowUpToLine, size: 15),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('شحن رصيد', maxLines: 1, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.35)),
                  ),
                ),
              ),
              const SizedBox(width: Sp.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDebts,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textHi,
                    side: BorderSide(color: AppColors.border),
                    minimumSize: const Size.fromHeight(36),
                    padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
                  ),
                  icon: debtsLocked ? const PermLockIcon(size: 15) : Icon(LucideIcons.receipt, size: 15, color: AppColors.warning),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('ديون أخرى',
                        maxLines: 1,
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.35, color: debtsLocked ? LockedStyle.title : null)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(
      {required IconData icon, required String label, required String value, required Color color, VoidCallback? onTap, bool ltr = false}) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(R.sm)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 10.5, height: 1.3, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.85))),
          if (value.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(value,
                textDirection: ltr ? TextDirection.ltr : null,
                style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(LucideIcons.pencil, size: 10, color: color),
          ],
        ],
      ),
    );
    if (onTap == null) return chip;
    return Material(
      color: Colors.transparent,
      child: InkWell(borderRadius: BorderRadius.circular(R.sm), onTap: onTap, child: chip),
    );
  }
}
