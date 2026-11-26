import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../services/merged_mode.dart';
import '../../../api/op_voids_api.dart';
import '../../../api/payment_voids_api.dart';
import '../../../api/subscribers_api.dart';
import '../../../core/util/format.dart';
import '../../../models/subscriber.dart';
import '../../../core/widgets/design_sheet.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';
import '../../../core/util/server_time.dart';
import '../../../core/widgets/app_sheet.dart';
import '../../../widgets/payment_void_bits.dart';
import '../../../services/permissions_service.dart';
import '../../sales/sales_screen.dart' show openSaleVoidById;
import 'op_void_sheet.dart';
import 'payment_void_sheet.dart';

/// Subscriber movements / account-statement sheet — direct port of
/// v1's _SubscriberMovementsSheetContent from
/// mobile-app/lib/screens/subscribers/subscriber_details_screen.dart.
///
/// Pulls the financial transaction history (activations / extensions
/// / debt-pay / balance-add / balance-deduct) through
/// /api/reports/account-statement for a 5-year window, groups by date
/// (اليوم / أمس / يyyy-mm-dd) and renders each row as an icon + type
/// badge + description + admin + time + signed amount.
///
/// Horizontally-scrollable filter chips at the top mirror v1: الكل /
/// تفعيل / تمديد / تسديد / إضافة دين. Refresh icon retries the same
/// fetch (no pagination — the window is wide enough by design).
///
/// «إلغاء تسديد» (١١ نوفمبر ٢٠٢٦): سطر التسديد يحمل زرّ إلغائه حين تُفتح الميزة للصفحة (والموظّف بلا صلاحيّتها يراه مقفلاً)،
/// والملغى بشارته ومبلغه مشطوب، وسطر الإلغاء نفسه (تسديدٌ بمبلغٍ سالب: رجع دينه) باسمه «إلغاء تسديد» تحت فلتر الديون.
/// مشتركٌ من شركةٍ أخرى في «كل الشركات» بلا زرّ — الخادم لا يوجّه الإلغاء.
/// [from] (٢٦ نوفمبر): يوزرٌ فري ⇒ من بداية حامله (قسم «اليوزرات الفري»)؛ غيابه ⇒ النافذة كاملةً كما كانت.
Future<void> showMovementsSheet(BuildContext context, Subscriber sub, {DateTime? from}) {
  return showAppSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MovementsSheet(sub: sub, from: from),
  );
}

class _MovementsSheet extends StatefulWidget {
  const _MovementsSheet({required this.sub, this.from});
  final Subscriber sub;
  final DateTime? from;

  @override
  State<_MovementsSheet> createState() => _MovementsSheetState();
}

class _MovementsSheetState extends State<_MovementsSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _all = const [];
  String _typeFilter = 'all';

  /// «إلغاء تسديد»: حال التسديدات المعروضة وهل يلغي هذا الفاعل.
  PaymentVoidStatus _voids = PaymentVoidStatus.off;
  int _voidsGen = 0;

  /// «إلغاء إضافة دين/رصيد» (١٧ نوفمبر): حال الإضافات المعروضة وهل يلغي هذا الفاعل كلّ نوع.
  OpVoidStatus _opVoids = OpVoidStatus.off;
  int _opGen = 0;

  /// الإلغاء للشركة المفتوحة وحدها: صفٌّ بمفتاح شركة («كل الشركات») كشفه موجَّهٌ لها، والخادم لا يوجّه الإلغاء.
  bool get _voidHere => widget.sub.companyKey == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // «كل الشركات»: كشف حساب المشترك لشركة صفّه موجَّهاً — الخادم يسمح بقراءته (36f4cd2، ٢٢ أكتوبر؛ كان «يعمل من الشركة
    // وحدها»). الوضع العاديّ كما هو حرفاً (MergedOps.run بلا مفتاحٍ يشغّل النداء كما هو).
    final txs = await MergedOps.run(
      widget.sub,
      () => SubscribersApi.loadMovements(username: widget.sub.username, idx: widget.sub.idx, from: widget.from),
    );
    if (!mounted) return;
    setState(() {
      if (txs == null) {
        _error = 'تعذّر جلب الحركات — تحقّق من الاتصال';
      } else {
        _all = txs;
      }
      _loading = false;
    });
    if (txs != null) {
      _loadVoids(txs);
      _loadOpVoids(txs);
    }
  }

  Future<void> _loadOpVoids(List<Map<String, dynamic>> txs) async {
    final gen = ++_opGen;
    final ids = <int>[
      if (_voidHere)
        for (final t in txs)
          if (OpVoidsApi.opIdOf(t) != null) OpVoidsApi.opIdOf(t)!,
    ];
    final st = ids.isEmpty ? OpVoidStatus.off : await OpVoidsApi.status(ids);
    if (!mounted || gen != _opGen) return;
    setState(() => _opVoids = st);
  }

  /// رصيد المشترك كما يعرضه السجلّ الآن (أحدث حركةٍ تحمل رصيداً) — لمعاينة «الآن ⇒ بعد الإلغاء».
  num? get _currentBalance {
    for (final t in _all) {
      final b = t['balance_after'] == null ? null : _MovementTile._readSigned(t['balance_after']);
      if (b != null) return b;
    }
    return null;
  }

  /// «شراء» (بيع موادّ على دين المشترك): رقم البيع من الخادم (sale_id) لزرّ «إلغاء البيع» القائم.
  static int? _saleIdOf(Map<String, dynamic> t) {
    final v = t['sale_id'];
    final n = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
    return n != null && n > 0 ? n : null;
  }

  /// يوم الحركة بتوقيت بغداد (YYYY-MM-DD) — قائمة المبيعات تُقرأ لذلك اليوم.
  static String _baghdadDay(Object? createdAt) {
    final d = parseServerUtc(createdAt?.toString() ?? '')?.toUtc().add(const Duration(hours: 3));
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  Future<void> _openSaleVoid(Map<String, dynamic> txn) async {
    final id = _saleIdOf(txn);
    final day = _baghdadDay(txn['created_at']);
    if (id == null || day.isEmpty || !_voidHere) return;
    final changed = await openSaleVoidById(context, saleId: id, day: day);
    if (!mounted) return;
    if (changed == true) await _load();
  }

  Future<void> _openOpVoid(Map<String, dynamic> txn) async {
    final id = OpVoidsApi.opIdOf(txn);
    final kind = OpVoidsApi.opKindOf(txn);
    if (id == null || kind == null || !_voidHere) return;
    final changed = await showOpVoidSheet(
      context,
      opId: id,
      kind: kind,
      creditKind: OpVoidsApi.opCreditKindOf(txn),
      amount: _MovementTile.readAmount(txn['amount']),
      subscriber: widget.sub.username,
      currentBalance: _currentBalance,
    );
    if (!mounted) return;
    if (changed == true) {
      await _load();
    } else {
      _loadOpVoids(_all);
    }
  }

  Future<void> _loadVoids(List<Map<String, dynamic>> txs) async {
    final gen = ++_voidsGen;
    final ids = <int>[
      if (_voidHere)
        for (final t in txs)
          if (PaymentVoidsApi.paymentIdOf(t) != null) PaymentVoidsApi.paymentIdOf(t)!,
    ];
    final st = ids.isEmpty ? PaymentVoidStatus.off : await PaymentVoidsApi.status(ids);
    if (!mounted || gen != _voidsGen) return;
    setState(() => _voids = st);
  }

  Future<void> _openVoid(Map<String, dynamic> txn) async {
    final id = PaymentVoidsApi.paymentIdOf(txn);
    if (id == null || !_voidHere) return;
    final changed = await showPaymentVoidSheet(
      context,
      paymentId: id,
      amount: _MovementTile.readAmount(txn['amount']),
      subscriber: widget.sub.username,
    );
    if (!mounted) return;
    // أُلغي أو حُسم ⇒ الكشف من جديد (سطر الإلغاء والدين بعده)؛ وإلّا الحال وحده
    if (changed == true) {
      await _load();
    } else {
      _loadVoids(_all);
    }
  }

  /// نوع الحركة للفلتر: إلغاء التسديد يعيد الدين فيُفرز مع «إضافة دين» لا مع «تسديد»؛ وDEBT_PAY (كشف الدفتر) تسديد؛ و«إضافة رصيد»
  /// (١٧ نوفمبر) فلترها وحدها ([_isCreditRow]).
  static String _kindOf(Map<String, dynamic> t) {
    final type = (t['action_type'] ?? '').toString().toUpperCase();
    // «إلغاء إضافة رصيد» مع «إضافة رصيد»، و«إلغاء إضافة دين» مع «إضافة دين».
    if (OpVoidsApi.isOpVoidRow(t)) return OpVoidsApi.voidKindOf(t) == 'add_credit' ? 'CREDIT_ADD' : 'BALANCE_ADD';
    if (PaymentVoidsApi.isVoidRow(t)) return 'BALANCE_ADD';
    if (_isCreditRow(t)) return 'CREDIT_ADD';
    if (type == 'DEBT_PAY') return 'BALANCE_DEDUCT';
    return type;
  }

  /// «إضافة رصيد»: سطر BALANCE_ADD بمبلغٍ سالب ووصفه «إضافة رصيد …» (الساس والشركات المُضافة)، أو is_credit من كشف دفتر ايرث لنك
  /// (سطر DEBT_PAY) — رصيدٌ للمشترك، لا «إنقاص دين» ولا «تسديد».
  static bool _isCreditRow(Map<String, dynamic> t) {
    if (t['is_credit'] == true) return true;
    final type = (t['action_type'] ?? '').toString().toUpperCase();
    final desc = (t['description'] ?? '').toString().trimLeft();
    return (type == 'BALANCE_ADD' || type == 'DEBT_PAY') && desc.startsWith('إضافة رصيد');
  }

  List<Map<String, dynamic>> get _filtered {
    if (_typeFilter == 'all') return _all;
    return _all.where((t) => _kindOf(t) == _typeFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: _Header(
        sub: widget.sub,
        loading: _loading,
        onRefresh: _loading ? null : _load,
        onClose: () => Navigator.of(context).pop(),
      ),
      scrollable: false,
      bodyPadding: EdgeInsets.zero,
      body: Column(
        children: [
          _FilterChips(
            current: _typeFilter,
            onChange: (v) => setState(() => _typeFilter = v),
          ),
          Divider(height: 1, color: AppColors.divider),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.brand),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.circleAlert, size: 36, color: AppColors.error),
              const SizedBox(height: Sp.sm),
              Text(
                _error!,
                style: AppType.subtitle(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: Sp.md),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(LucideIcons.refreshCw, size: 14),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    final list = _filtered;
    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(Sp.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.inbox, size: 40, color: AppColors.textLow),
              const SizedBox(height: Sp.sm),
              Text(
                _typeFilter == 'all'
                    ? 'لا توجد حركات لعرضها'
                    : 'لا توجد حركات بهذا النوع',
                style: AppType.subtitle(color: AppColors.textMid),
              ),
            ],
          ),
        ),
      );
    }

    // Group by date label. Server returns DESC so we preserve insertion
    // order while building the group map.
    final grouped = <String, List<Map<String, dynamic>>>{};
    final order = <String>[];
    for (final t in list) {
      final key = _dateGroupKey(t['created_at']?.toString() ?? '');
      grouped.putIfAbsent(key, () {
        order.add(key);
        return [];
      }).add(t);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.sm, Sp.md, Sp.huge),
      itemCount:
          order.fold<int>(0, (sum, key) => sum + 1 + grouped[key]!.length),
      itemBuilder: (_, index) {
        var i = index;
        for (final key in order) {
          if (i == 0) return _DateHeader(label: key);
          i--;
          final group = grouped[key]!;
          if (i < group.length) {
            final t = group[i];
            final pid = _voidHere ? PaymentVoidsApi.paymentIdOf(t) : null;
            final oid = _voidHere ? OpVoidsApi.opIdOf(t) : null;
            return _MovementTile(
              txn: t,
              voided: _voids.of(pid),
              voidAction: _voids.actionFor(pid),
              onVoid: () => _openVoid(t),
              opVoided: _opVoids.of(oid),
              opAction: _opVoids.actionFor(oid, OpVoidsApi.opKindOf(t)),
              onOpVoid: () => _openOpVoid(t),
              saleAction: !_voidHere || _saleIdOf(t) == null
                  ? PaymentVoidAction.none
                  : (Perms.has('sales.void') ? PaymentVoidAction.open : PaymentVoidAction.locked),
              onSale: () => _openSaleVoid(t),
            );
          }
          i -= group.length;
        }
        return const SizedBox.shrink();
      },
    );
  }

  String _dateGroupKey(String iso) {
    // ⚠️ `parseServerUtc` لا `DateTime.tryParse`: التوقيت من قاعدتنا
    // وهي UTC، والنصّ عارٍ. القراءة المحلّيّة تُزيحه ثلاث ساعات — فحركةٌ
    // بعد منتصف الليل تُجمَّع تحت «أمس».
    final dt = parseServerUtc(iso);
    if (dt == null) return '—';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.sub,
    required this.loading,
    required this.onRefresh,
    required this.onClose,
  });
  final Subscriber sub;
  final bool loading;
  final VoidCallback? onRefresh;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      // Roomier header — top=Sp.sm (8 vs old 4) so the title sits
      // clear of the handle, bigger icon-box (8 vs 6) so the brand
      // emblem reads at a comfortable size, and an extra px on the
      // subtitle line so the subscriber name has visible space
      // under the title rather than touching it.
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.sm, Sp.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.brandSoftBg,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Icon(LucideIcons.history, color: AppColors.brand, size: 18),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'سجل الحركات',
                  style: AppType.label(color: AppColors.textHi).copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  sub.fullName,
                  style: AppType.muted(color: AppColors.textMid).copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: loading
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brand,
                    ),
                  )
                : const Icon(LucideIcons.refreshCw, size: 18),
            color: AppColors.textMid,
            visualDensity: VisualDensity.compact,
            onPressed: onRefresh,
          ),
          IconButton(
            icon: const Icon(LucideIcons.x, size: 20),
            color: AppColors.textMid,
            visualDensity: VisualDensity.compact,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Horizontally-scrollable filter chips — 5 entries match v1.
class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.current, required this.onChange});
  final String current;
  final ValueChanged<String> onChange;

  static const _filters = [
    ('all', 'الكل'),
    ('SUBSCRIBER_ACTIVATE', 'تفعيل'),
    ('SUBSCRIBER_EXTEND', 'تمديد'),
    ('BALANCE_DEDUCT', 'تسديد'),
    ('CREDIT_ADD', 'إضافة رصيد'),
    ('BALANCE_ADD', 'إضافة دين'),
  ];

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    // Taller chip strip (48 vs the original 38) — Arabic chip labels
    // need extra vertical breathing room because the descenders on
    // letters like ع, ج clipped against the pill border before. Also
    // gives the row enough whitespace under the header so the sheet
    // doesn't read as a wall of controls.
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: 8),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final (value, label) = _filters[i];
          final selected = value == current;
          return InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onChange(value);
            },
            borderRadius: BorderRadius.circular(R.pill),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.brandSoftBg : AppColors.surface,
                borderRadius: BorderRadius.circular(R.pill),
                border: Border.all(
                  color:
                      selected ? AppColors.brandSoftBorder : AppColors.border,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: AppType.label(
                  color: selected ? AppColors.brand : AppColors.textMid,
                ).copyWith(
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, Sp.sm, 4, 4),
      child: Row(
        children: [
          Text(
            label,
            style: AppType.muted(color: AppColors.brand).copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              color: AppColors.border,
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  const _MovementTile({
    required this.txn,
    this.voided,
    this.voidAction = PaymentVoidAction.none,
    this.onVoid,
    this.opVoided,
    this.opAction = PaymentVoidAction.none,
    this.onOpVoid,
    this.saleAction = PaymentVoidAction.none,
    this.onSale,
  });

  /// «شراء»: زرّ «إلغاء البيع» القائم (يفتح نافذته) · مقفلٌ بلا sales.void · لا زرّ.
  final PaymentVoidAction saleAction;
  final VoidCallback? onSale;
  final Map<String, dynamic> txn;

  /// «إلغاء إضافة دين/رصيد» (١٧ نوفمبر): حال الإضافة في قيد الإلغاء، وزرّها، ونداؤه.
  final OpVoidItem? opVoided;
  final PaymentVoidAction opAction;
  final VoidCallback? onOpVoid;

  /// حال هذا التسديد في قيد الإلغاء («ملغى» · «بانتظار حسم») — أو null.
  final PaymentVoidItem? voided;

  /// زرّ «إلغاء التسديد»: يفتح النافذة · مقفلٌ لموظّفٍ بلا صلاحيّة · لا زرّ.
  final PaymentVoidAction voidAction;
  final VoidCallback? onVoid;

  /// أقلّ عرضٍ لسطر النوع يتّسع فيه الوقت مع شارة الإلغاء (النوع ~٦٦ + أطول شارة ~٧٤ + الوقت ~٣٤ وفواصلها).
  static const double _timeWithBadgeMin = 190;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final type = (txn['action_type'] ?? '').toString().toUpperCase();
    final desc = PaymentVoidsApi.cleanNote(
        (txn['description'] ?? txn['action_description'] ?? '').toString());
    final admin = (txn['admin_name'] ?? txn['admin_username'] ?? '').toString();
    final createdAt = txn['created_at']?.toString() ?? '';
    final rawAmt = txn['amount'];
    final amount = readAmount(rawAmt);

    // 🐛 بلاغ ٢٠٢٦-٠٩-٠٤: «من أسدّد دين أو أفعّل ما يطلع لي الدين
    // الباقي وراء الحركة».
    //
    // القيمة كانت مسجّلةً في `action_data.new_balance` طوال الوقت
    // (٢٢ ألف تفعيل و١٢ ألف تسديد)، لكنّ نقطة الـAPI كانت تُسقطها من
    // الردّ. الآن تصل باسم `balance_after`.
    //
    // ⚠️ و`null` ليس صفراً: سجلٌّ قديم بلا القيمة يجب أن **يُخفي**
    // السطر لا أن يعرض «الدين: 0» — وهو رقمٌ يكذب.
    //
    // 🐛 ١١ نوفمبر: كانت تُقرأ بـ`readAmount` وهو يُسقط الإشارة — فالدين (سالبٌ عند الخادم) يظهر «رصيد دائن» أخضر، وسطر
    // «إلغاء تسديد» يقول عكس ما جرى. الرصيد **موقَّع**: سالبٌ = دينٌ عليه.
    final rawBalance = txn['balance_after'];
    final double? balanceAfter = rawBalance == null ? null : _readSigned(rawBalance);

    final (icon, color, label) = _visualFor(
      type,
      desc,
      isVoid: PaymentVoidsApi.isVoidRow(txn),
      negative: (_readSigned(rawAmt) ?? 0) < 0,
      opVoidKind: OpVoidsApi.isOpVoidRow(txn) ? (OpVoidsApi.voidKindOf(txn) ?? 'add_debt') : null,
      isSale: _MovementsSheetState._saleIdOf(txn) != null,
    );
    // سطر إضافةٍ تُلغى ⇒ زرّها وشارتها؛ وإلّا زرّ التسديد كما كان.
    final isOp = opAction != PaymentVoidAction.none || opVoided != null;
    // «شراء»: زرّ «إلغاء البيع» (بلا شارة — حاله في قسم المبيعات).
    final isSale = !isOp && saleAction != PaymentVoidAction.none;
    final v = voided;
    final ov = opVoided;
    final voidedDone = isOp ? (ov != null && ov.isDone) : (!isSale && v != null && v.isDone);
    final hasBadge = isOp ? ov != null : (!isSale && v != null);
    // زرّ الفتح بلا معالجٍ لا يُعرض؛ والمقفل («لا صلاحيّة») لا يحتاج معالجاً.
    final rawAction = isOp ? opAction : (isSale ? saleAction : voidAction);
    final press = isOp ? onOpVoid : (isSale ? onSale : onVoid);
    final action = rawAction == PaymentVoidAction.open && press == null ? PaymentVoidAction.none : rawAction;

    // ⚠️ نفس السبب: UTC عارٍ يُقرأ محلّيّاً فيتأخّر ثلاث ساعات.
    final dt = parseServerUtc(createdAt);
    final timeStr = dt != null
        ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}'
        : '';

    final card = Container(
      margin: const EdgeInsets.only(bottom: 6),
      // Bottom padding generous (12) so Arabic descenders (ع، ج، ق)
      // in the description text don't get clipped by the card border.
      // The user reported lines 'المدفوع: 175,000 د.ع | الدين: 65,000'
      // visibly cut at the bottom in the movements sheet.
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // النوع وشارة الإلغاء والوقت في ما يتّسع: حين يضيق (أضيق هاتف + شارة) يُسقَط الوقت أوّلاً — الشارة
                    // تقول حال المال والوقت لا — وما بقي يضيق ولا يفيض.
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) => Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(R.sm),
                              ),
                              child: Text(
                                label,
                                style: AppType.label(color: color).copyWith(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (isOp && ov != null) ...[
                              const SizedBox(width: 4),
                              Flexible(child: OpVoidBadge(item: ov)),
                            ] else if (!isOp && v != null) ...[
                              const SizedBox(width: 4),
                              Flexible(child: PaymentVoidBadge(item: v)),
                            ],
                            if (timeStr.isNotEmpty && (!hasBadge || box.maxWidth >= _timeWithBadgeMin)) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  timeStr,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.fade,
                                  style: AppType.muted(color: AppColors.textLow).copyWith(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (amount != 0)
                      Text(
                        '${formatIQD(amount.round())} د.ع',
                        // الملغى: مبلغه مشطوبٌ خافت — سطر إلغائه أعاد دينه
                        style: AppType.label(color: voidedDone ? AppColors.textLow : color).copyWith(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          decoration: voidedDone ? TextDecoration.lineThrough : null,
                          decorationColor: voidedDone ? AppColors.textLow : null,
                        ),
                      ),
                    // مكان زرّ الإلغاء (يُرسم فوق الكرت — انظر آخر build): فراغٌ بعرضه فلا يغطّي المبلغ
                    if (action != PaymentVoidAction.none) const SizedBox(width: 26),
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    desc,
                    style: AppType.subtitle(color: AppColors.textHi)
                        .copyWith(fontSize: 12.5, height: 1.55),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                // ── الدين المتبقّي بعد هذه الحركة ──────────────
                //
                // ⚠️ يُخفى عند `null` لا يُعرض صفراً: الصفر رقمٌ يعني
                // «لا دين عليه»، والغياب يعني «لا نعرف». خلطُهما يجعل
                // سجلّاً قديماً يبدو كأنّه سدّد كلّ شيء.
                if (balanceAfter != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        balanceAfter < 0
                            ? LucideIcons.trendingDown
                            : (balanceAfter > 0
                                ? LucideIcons.trendingUp
                                : LucideIcons.check),
                        size: 11,
                        color: balanceAfter < 0
                            ? AppColors.error
                            : (balanceAfter > 0
                                ? AppColors.success
                                : AppColors.textMid),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          balanceAfter == 0
                              ? 'لا دين بعدها'
                              : (balanceAfter < 0
                                  ? 'الدين بعدها: '
                                      '${formatIQD(balanceAfter.abs().round())} د.ع'
                                  : 'رصيد دائن: '
                                      '${formatIQD(balanceAfter.round())} د.ع'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.label(
                            color: balanceAfter < 0
                                ? AppColors.error
                                : (balanceAfter > 0
                                    ? AppColors.success
                                    : AppColors.textMid),
                          ).copyWith(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
                if (admin.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(LucideIcons.user,
                          size: 10, color: AppColors.textLow),
                      const SizedBox(width: 4),
                      Text(
                        admin,
                        style: AppType.muted(color: AppColors.textLow).copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (action == PaymentVoidAction.none) return card;
    // الزرّ فوق الكرت بمحاذاة سطره الأوّل: مساحة لمسٍ ٣٢ بلا أن يكبر الكرت (سطر النوع أقصر منها).
    return Stack(
      children: [
        card,
        PositionedDirectional(
          top: 3,
          end: 5,
          child: PaymentVoidRowButton(
            action: action,
            resume: hasBadge,
            onOpen: press ?? () {},
            tipOpen: isOp ? 'إلغاء الحركة' : (isSale ? 'إلغاء البيع' : null),
            tipLocked: isOp ? 'إلغاء الحركة — لا صلاحيّة' : (isSale ? 'إلغاء البيع — لا صلاحيّة' : null),
            tipResume: isOp ? 'إكمال إلغاء الحركة' : null,
          ),
        ),
      ],
    );
  }

  static (IconData, Color, String) _visualFor(
    String type,
    String desc, {
    bool isVoid = false,
    bool negative = false,
    String? opVoidKind,
    bool isSale = false,
  }) {
    // «إلغاء إضافة دين/رصيد» (١٧ نوفمبر): السطر المقابل باسمه (الخادم يعلّمه op_void).
    if (opVoidKind != null) return (LucideIcons.undo2, AppColors.error, opVoidLabel(opVoidKind));
    // «شراء» (١٨ نوفمبر): بيع موادّ على دين المشترك — باسمه لا «إضافة دين».
    if (isSale && type == 'BALANCE_ADD') return (LucideIcons.shoppingCart, AppColors.warning, 'شراء');
    // «إلغاء تسديد»: تسديدٌ بمبلغٍ سالب (أو معلَّمٌ من دفتر ايرث لنك) — رجع دينه.
    if (isVoid) return (LucideIcons.undo2, AppColors.error, 'إلغاء تسديد');
    // سطر تسوية الربط (الدين كان أُعيد يدويّاً بإضافة دين — محاسبةٌ بلا أثرٍ على دين المشترك): باسمه كما في التقارير،
    // لا «إنقاص دين» أخضر كأنّ دينه نقص.
    if (type == 'BALANCE_ADD' && desc.trimLeft().startsWith('تسوية إلغاء تسديد')) {
      return (LucideIcons.undo2, AppColors.textMid, 'تسوية إلغاء تسديد');
    }
    // «إضافة رصيد» (١٧ نوفمبر): باسمها — والتعويض بلا نقد محايد.
    if ((type == 'BALANCE_ADD' || type == 'DEBT_PAY') && desc.trimLeft().startsWith('إضافة رصيد')) {
      return desc.contains('(تعويض)')
          ? (LucideIcons.coins, AppColors.brandAccent, 'إضافة رصيد (تعويض)')
          : (LucideIcons.coins, AppColors.success, 'إضافة رصيد');
    }
    // «إضافة دين» بمبلغٍ سالب تُنقص الدين (إلغاء بيعٍ على الدين).
    if (type == 'BALANCE_ADD' && negative) return (LucideIcons.minus, AppColors.success, 'إنقاص دين');
    switch (type) {
      case 'SUBSCRIBER_ACTIVATE':
        // Cash vs non-cash differs in the description text only.
        final isNonCash = desc.contains('غير نقدي');
        return (
          LucideIcons.zap,
          AppColors.brand,
          isNonCash ? 'تفعيل أجل' : 'تفعيل'
        );
      case 'SUBSCRIBER_EXTEND':
        return (LucideIcons.repeat, AppColors.brandAccent, 'تمديد');
      case 'BALANCE_DEDUCT':
      case 'DEBT_PAY':
        return (LucideIcons.banknote, AppColors.success, 'تسديد دين');
      case 'BALANCE_ADD':
        return (LucideIcons.plus, AppColors.warning, 'إضافة دين');
      case 'PAYMENT_ADD':
        return (LucideIcons.wallet, AppColors.brand, 'إيراد');
      default:
        return (LucideIcons.receipt, AppColors.textMid, type);
    }
  }

  /// مبلغ الحركة **بلا إشارته** — العرض يسمّي الاتّجاه بنوع الحركة لا بالسالب.
  static double readAmount(dynamic raw) => _readSigned(raw)?.abs() ?? 0;

  /// القيمة بإشارتها — للرصيد بعد الحركة (سالبٌ = دين) ولتمييز المبلغ السالب. null إن لم تُقرأ.
  static double? _readSigned(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    final s = raw.toString().replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(s);
  }
}
