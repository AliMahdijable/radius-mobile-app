import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/fiberx_topup_api.dart';
import '../../core/platform/store_policy.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import 'topup_widgets.dart';

/// شحن محفظة فايبر اكس (زين كاش / كي كارد): رصيد + طريقة + مبلغ ← رابط دفعٍ
/// يُفتح بمتصفّح الوكيل ← «تحقّقت» يتابع النتيجة بـtransactionId.
///
/// لا مال يمرّ بخادمنا (البوّابة تضيف للمحفظة). على الآيفون يُقفل الدفع داخل
/// التطبيق ([StorePolicy.hidePurchaseFlows]) ويُقال «من الموقع».
class FiberxTopupScreen extends StatefulWidget {
  const FiberxTopupScreen({super.key});

  @override
  State<FiberxTopupScreen> createState() => _FiberxTopupScreenState();
}

class _FiberxTopupScreenState extends State<FiberxTopupScreen> {
  FxTopupOptions? _opts;
  bool _loading = true;
  String? _error;
  FxTopupMethod? _method;
  final _amountCtrl = TextEditingController();
  bool _touchedAmount = false;
  bool _busy = false;

  /// رابط دفعٍ أُنشئ، بانتظار «تحقّقت» (لا نُنشئ ثانياً ما دام قائماً).
  FxTopupStart? _pending;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await FiberxTopupApi.options();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _opts = r.data;
      _error = r.data == null ? r.message : null;
      final ms = r.data?.methods ?? const <FxTopupMethod>[];
      if (_method == null || !ms.any((m) => m.id == _method!.id)) {
        _method = ms.isEmpty ? null : ms.first;
      }
    });
  }

  int? get _amount {
    final digits = _amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? null : int.tryParse(digits);
  }

  String? _amountError() {
    final m = _method;
    final a = _amount;
    if (m == null) return 'اختر طريقة الشحن';
    if (a == null || a <= 0) return 'اكتب مبلغاً صحيحاً';
    if (m.minAmount != null && a < m.minAmount!) return 'أقلّ مبلغ ${formatIQD(m.minAmount!)} د.ع';
    if (m.maxAmount != null && a > m.maxAmount!) return 'أكبر مبلغ ${formatIQD(m.maxAmount!)} د.ع';
    return null;
  }

  Future<void> _pay({bool confirmRepeat = false}) async {
    final m = _method;
    final a = _amount;
    final err = _amountError();
    if (m == null || a == null || err != null) {
      setState(() => _touchedAmount = true);
      if (err != null) showSheetSnack(context, err, isError: true);
      return;
    }
    setState(() => _busy = true);
    final r = await FiberxTopupApi.initiate(methodId: m.id, amount: a, confirmRepeat: confirmRepeat);
    if (!mounted) return;
    setState(() => _busy = false);

    // تكرارٌ قريب بالمبلغ نفسه ⇒ تأكيد.
    if (r.code == 'RECENT_DUPLICATE') {
      final ok = await showConfirmSheet(
        context,
        title: 'رابطٌ بالمبلغ نفسه',
        message: r.message ?? 'أنشأت رابط دفعٍ بالمبلغ نفسه قبل قليل. أتريد رابطاً آخر؟',
        confirmLabel: 'أنشئ رابطاً آخر',
        cancelLabel: 'إلغاء',
        icon: LucideIcons.triangleAlert,
      );
      if (ok == true && mounted) await _pay(confirmRepeat: true);
      return;
    }

    final start = r.start;
    if (start == null) {
      // notSure (لم نعرف هل أُنشئ) ⇒ ليست حمراء: لم يُدفع شيء، أعد لاحقاً.
      showSheetSnack(context, r.message ?? 'تعذّر إنشاء رابط الدفع', isError: !r.notSure);
      return;
    }

    setState(() => _pending = start);
    final url = Uri.tryParse(start.paymentUrl);
    final opened = url == null ? false : await launchUrl(url, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!opened && mounted) {
      showSheetSnack(context, 'تعذّر فتح المتصفّح — اضغط «افتح صفحة الدفع»', isError: true);
    }
  }

  Future<void> _check() async {
    final p = _pending;
    if (p == null) return;
    final tx = p.transactionId;
    if (tx == null || tx.isEmpty) {
      // بلا رقم عمليّة: نحدّث الرصيد فقط وندع الوكيل يتأكّد منه.
      await _load();
      if (mounted) showSheetSnack(context, 'حدّثنا الرصيد — تأكّد منه بالأعلى');
      return;
    }
    setState(() => _checking = true);
    final s = await FiberxTopupApi.status(tx);
    if (!mounted) return;
    setState(() => _checking = false);
    if (s.isSuccess) {
      setState(() => _pending = null);
      await _load();
      if (mounted) showSheetSnack(context, 'تمّ الشحن — أُضيف لمحفظتك');
    } else if (s.isFailed) {
      setState(() => _pending = null);
      if (mounted) showSheetSnack(context, 'الدفعة لم تكتمل — لم يُخصم شيء', isError: true);
    } else {
      await _load();
      if (mounted) {
        showSheetSnack(context, s.found ? 'الدفعة قيد المعالجة — تحقّق بعد لحظات' : 'ما لقينا الدفعة بعد — أكمل الدفع ثمّ تحقّق');
      }
    }
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
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('شحن محفظة فايبر اكس',
                  style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
              Text('زين كاش أو كي كارد — يُضاف لمحفظتك',
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
    // الآيفون: لا دفع داخل التطبيق.
    if (StorePolicy.hidePurchaseFlows) {
      return [
        _balance(),
        const SizedBox(height: Sp.lg),
        const TopupStateCard(
          icon: LucideIcons.globe,
          title: 'الشحن من الموقع',
          text: 'اشحن محفظة فايبر اكس من موقع الويب على المتصفّح.',
        ),
      ];
    }
    if (_loading && _opts == null) {
      return const [
        Padding(padding: EdgeInsets.only(top: 80), child: Center(child: CircularProgressIndicator())),
      ];
    }
    if (_opts == null) {
      return [
        TopupStateCard(
          icon: LucideIcons.wifiOff,
          title: 'تعذّر الجلب',
          text: _error ?? 'تعذّر الاتّصال بالخادم',
          action: TextButton(onPressed: _load, child: const Text('إعادة')),
        ),
      ];
    }
    if (!_opts!.enabled) {
      return [
        _balance(),
        const SizedBox(height: Sp.lg),
        const TopupStateCard(
          icon: LucideIcons.lock,
          title: 'غير مفعّل',
          text: 'شحن المحفظة غير مفعّلٍ لحسابك بعد.',
        ),
      ];
    }
    final methods = _opts!.methods;
    return [
      _balance(),
      const SizedBox(height: Sp.lg),
      if (_pending != null)
        _pendingCard()
      else if (methods.isEmpty)
        const TopupStateCard(icon: LucideIcons.ban, title: 'لا طرق', text: 'ما في طرق شحنٍ متاحة الآن.')
      else ...[
        TopupSection(title: 'طريقة الشحن', children: [
          for (var i = 0; i < methods.length; i++) ...[
            if (i > 0) const SizedBox(height: Sp.sm),
            _methodTile(methods[i]),
          ],
        ]),
        const SizedBox(height: Sp.lg),
        _amountSection(),
      ],
    ];
  }

  Widget _balance() => TopupBalanceCard(
        balance: _opts?.balance,
        loading: _loading,
        currency: 'د.ع',
        onRefresh: _loading ? null : _load,
      );

  Widget _methodTile(FxTopupMethod m) {
    final on = _method?.id == m.id;
    final limit = [
      if (m.minAmount != null) 'من ${formatIQD(m.minAmount!)}',
      if (m.maxAmount != null) 'إلى ${formatIQD(m.maxAmount!)}',
    ].join(' ');
    return Material(
      color: on ? AppColors.brandSoftBg : AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        onTap: () => setState(() => _method = m),
        borderRadius: BorderRadius.circular(R.lg),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: on ? AppColors.brand : AppColors.border, width: on ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(m.isZainCash ? LucideIcons.smartphone : LucideIcons.creditCard,
                  size: 20, color: on ? AppColors.brand : AppColors.textMid),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name,
                        style: AppType.bodyBold(color: AppColors.textHi),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (limit.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(limit, style: AppType.muted()),
                    ],
                  ],
                ),
              ),
              if (on) Icon(LucideIcons.check, size: 18, color: AppColors.brand),
            ],
          ),
        ),
      ),
    );
  }

  Widget _amountSection() {
    final err = _touchedAmount ? _amountError() : null;
    return TopupSection(title: 'المبلغ', children: [
      TextField(
        controller: _amountCtrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() => _touchedAmount = true),
        style: AppType.title(color: AppColors.textHi),
        decoration: InputDecoration(
          hintText: '0',
          suffixText: 'د.ع',
          errorText: err,
          filled: true,
          fillColor: AppColors.surfaceInput,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.lg), borderSide: BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.lg), borderSide: BorderSide(color: AppColors.border)),
        ),
      ),
      const SizedBox(height: Sp.md),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: (_busy || _amountError() != null) ? null : () => _pay(),
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand, padding: const EdgeInsets.symmetric(vertical: Sp.md)),
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand))
              : const Text('شحن'),
        ),
      ),
    ]);
  }

  Widget _pendingCard() {
    final p = _pending!;
    return TopupStateCard(
      icon: LucideIcons.externalLink,
      title: 'أكمل الدفع بالمتصفّح',
      text: 'فتحنا صفحة دفع ${formatIQD(p.amount)} د.ع. أكمل الدفع هناك ثمّ ارجع واضغط «تحقّقت».',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _checking ? null : _check,
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand, padding: const EdgeInsets.symmetric(vertical: Sp.md)),
              child: _checking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand))
                  : const Text('تحقّقت من الدفع'),
            ),
          ),
          const SizedBox(height: Sp.sm),
          TextButton(
            onPressed: () async {
              final url = Uri.tryParse(p.paymentUrl);
              if (url != null) {
                await launchUrl(url, mode: LaunchMode.externalApplication).catchError((_) => false);
              }
            },
            child: const Text('افتح صفحة الدفع ثانيةً'),
          ),
          TextButton(
            onPressed: () => setState(() => _pending = null),
            child: Text('إلغاء', style: AppType.body(color: AppColors.textMid)),
          ),
        ],
      ),
    );
  }
}
