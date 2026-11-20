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
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() {
      final q = _searchCtrl.text.trim();
      if (q != _query) setState(() => _query = q);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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
      content: Text([r.message ?? 'تمّ الشحن', if (line != null) line].join('\n'), style: const TextStyle(height: 1.5)),
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
          child: ListView(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom + 32),
            children: [
              if (!_loading && !_enabled)
                _notEnabled()
              else ...[
                _hero(),
                _scopeNote(),
                Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: _searchField()),
                if (_loading)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator()))
                else if (rows.isEmpty)
                  _empty()
                else
                  for (final m in rows)
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
          ),
        ),
      ),
    );
  }

  Widget _hero() {
    final debt = _totalOtherDebt;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(Sp.lg),
      decoration: BoxDecoration(color: AppColors.brandSurface, borderRadius: BorderRadius.circular(R.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('رصيد إيداعك', style: AppType.label(color: AppColors.onBrandSecondary)),
                    const SizedBox(height: 4),
                    Row(
                      textBaseline: TextBaseline.alphabetic,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      children: [
                        Text(_balance == null ? '—' : formatIQDSigned(_balance!),
                            textDirection: TextDirection.ltr,
                            style: AppType.amount(color: AppColors.onBrand).copyWith(fontSize: 22)),
                        const SizedBox(width: 6),
                        Text('د.ع', style: AppType.body(color: AppColors.onBrandSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: AppColors.onBrandFill2, borderRadius: BorderRadius.circular(R.sm)),
                child: Text(arCount(_rows.length, one: 'مدير واحد', two: 'مديران', few: 'مدراء', many: 'مديراً'),
                    style: AppType.bodyBold(color: AppColors.onBrand)),
              ),
            ],
          ),
          if (debt > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(LucideIcons.receipt, size: 14, color: AppColors.onBrandStrong),
                const SizedBox(width: 6),
                Text('ديون أخرى عليهم ', style: AppType.label(color: AppColors.onBrandSecondary)),
                Text('${formatIQD(debt)} د.ع', style: AppType.bodyBold(color: AppColors.onBrand)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _scopeNote() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          Icon(LucideIcons.info, size: 13, color: AppColors.textMid),
          const SizedBox(width: 6),
          Expanded(
            child: Text('ايرث لنك تسمح بشحن رصيدهم وحده — لا سحب ولا نقاط ولا تعديل معلومات',
                style: AppType.muted().copyWith(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Sp.md),
      child: Row(
        children: [
          Icon(LucideIcons.search, color: AppColors.textMid, size: 18),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: AppType.input(color: AppColors.textHi),
              decoration: InputDecoration(
                hintText: 'ابحث باسم المدير',
                hintStyle: AppType.input(color: AppColors.textLow),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: Sp.md),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// الميزة لم تُفتح للحساب بعد — ولصاحبه «تحويل الرصيد» كما كان (لا يفقد التحويل في الانتظار).
  Widget _notEnabled() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(Sp.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(LucideIcons.userCog, size: 36, color: AppColors.textLow),
          const SizedBox(height: 10),
          Text('قسم «المدراء» لم يُفتح لحسابك بعد',
              textAlign: TextAlign.center, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 14)),
          const SizedBox(height: 4),
          Text('يُفتح قريباً — شحن رصيد حساباتك التابعة وديونها الأخرى من هنا',
              textAlign: TextAlign.center, style: AppType.muted().copyWith(fontSize: 12)),
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
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(Sp.huge),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
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
    final m = manager;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: AppColors.brandSoftBg, borderRadius: BorderRadius.circular(R.card)),
                alignment: Alignment.center,
                child: Icon(LucideIcons.shield, size: 17, color: AppColors.brandAccent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textHi, height: 1.2)),
                    const SizedBox(height: 2),
                    Text('حساب تابع · #${m.index}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMid, height: 1.25)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                icon: LucideIcons.receipt,
                label: 'ديون أخرى',
                value: m.otherDebt > 0 ? '${formatIQD(m.otherDebt)} د.ع' : 'لا شيء',
                color: m.otherDebt > 0 ? AppColors.warning : AppColors.textMid,
              ),
              if (m.lastTopupAmount != null && m.lastTopupAt != null)
                _chip(
                  icon: LucideIcons.arrowUpToLine,
                  label: 'آخر شحن',
                  value: '${formatIQD(m.lastTopupAmount!)} · ${_ymd(m.lastTopupAt!)}${m.lastTopupAsDebt ? ' · آجل' : ''}',
                  color: AppColors.brand,
                ),
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onTopup,
                  style: FilledButton.styleFrom(
                    backgroundColor: topupLocked ? LockedStyle.box : AppColors.brand,
                    foregroundColor: topupLocked ? LockedStyle.title : AppColors.onBrand,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
                  ),
                  icon: topupLocked ? const PermLockIcon(size: 15) : const Icon(LucideIcons.arrowUpToLine, size: 16),
                  label: const Text('شحن رصيد', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDebts,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textHi,
                    side: BorderSide(color: AppColors.border),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
                  ),
                  icon: debtsLocked ? const PermLockIcon(size: 15) : Icon(LucideIcons.receipt, size: 16, color: AppColors.warning),
                  label: Text('ديون أخرى',
                      style: TextStyle(fontWeight: FontWeight.w700, color: debtsLocked ? LockedStyle.title : null)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({required IconData icon, required String label, required String value, required Color color, VoidCallback? onTap, bool ltr = false}) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(R.sm)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(fontSize: 10.5, height: 1.3, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.85))),
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
