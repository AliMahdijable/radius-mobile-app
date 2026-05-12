import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/receipt_printer.dart' show ReceiptData;
import '../../models/subscriber_model.dart';
import '../../providers/receipt_archive_provider.dart';
import '../../providers/subscribers_provider.dart';
import '../../widgets/app_snackbar.dart';

/// تجديد/تفعيل اشتراك أكثر من مشترك دفعة واحدة. يفتح مودلاً يعرض كل مشترك
/// محدّد بسطر فيه باقته وسعرها ودينه الحالي و3 خيارات دفع (دين/نقدي/جزئي،
/// الافتراضي دين)، ثم ينفّذ على الجميع بالتسلسل ويؤرشف وصلاً لكل عملية.
///
/// النتيجة المُرجَعة: `true` لو نُفِّذت عملية واحدة على الأقل (كي تخرج
/// الشاشة الأمّ من وضع التحديد)، غير ذلك `null`.
Future<bool?> showBulkRenewSheet(
  BuildContext context,
  List<SubscriberModel> subscribers,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _BulkRenewSheet(subscribers: subscribers),
  );
}

enum _PayMethod { debt, cash, partial }

extension _PayMethodX on _PayMethod {
  String get label => switch (this) {
        _PayMethod.debt => 'دين',
        _PayMethod.cash => 'نقدي',
        _PayMethod.partial => 'جزئي',
      };
  ReceiptPaymentMethod get receiptMethod => switch (this) {
        _PayMethod.debt => ReceiptPaymentMethod.credit,
        _PayMethod.cash => ReceiptPaymentMethod.cash,
        _PayMethod.partial => ReceiptPaymentMethod.partial,
      };
}

double _toD(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) {
    return double.tryParse(v.replaceAll(RegExp(r'[^0-9.\-]'), '')) ?? 0;
  }
  return 0;
}

double _pickPositive(List<dynamic> cands) {
  for (final c in cands) {
    final d = _toD(c);
    if (d > 0) return d;
  }
  return 0;
}

double _parseMoney(String s) =>
    double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

class _RenewRow {
  final SubscriberModel sub;
  final double originalPrice; // قبل الخصم
  final double discount;
  final dynamic units; // activation_units من activationData
  final double currentBalance; // سالب = دين، موجب = رصيد
  final bool loadFailed; // تعذّر جلب بيانات التفعيل
  _PayMethod method;
  final TextEditingController partialCtrl;

  _RenewRow({
    required this.sub,
    required this.originalPrice,
    required this.discount,
    required this.units,
    required this.currentBalance,
    this.loadFailed = false,
    this.method = _PayMethod.debt,
  }) : partialCtrl = TextEditingController();

  bool get renewable => !loadFailed;
  double get finalPrice {
    final p = originalPrice - discount;
    return p < 0 ? 0.0 : p;
  }

  double get partialAmount => _parseMoney(partialCtrl.text);

  /// المقبوض نقداً فعلياً لهذا السطر (لو "جزئي" تجاوز السعر، الفائض يصير
  /// رصيداً للمشترك — لا نقصّه هنا).
  double get cashIn => switch (method) {
        _PayMethod.cash => finalPrice,
        _PayMethod.partial => partialAmount,
        _PayMethod.debt => 0.0,
      };

  /// الرصيد بعد العملية (مطابق لمنطق activateSubscriber).
  double get newBalance => switch (method) {
        _PayMethod.cash => currentBalance,
        _PayMethod.partial => currentBalance - finalPrice + partialAmount,
        _PayMethod.debt => currentBalance - finalPrice,
      };
}

class _BulkRenewSheet extends ConsumerStatefulWidget {
  final List<SubscriberModel> subscribers;
  const _BulkRenewSheet({required this.subscribers});

  @override
  ConsumerState<_BulkRenewSheet> createState() => _BulkRenewSheetState();
}

class _BulkRenewSheetState extends ConsumerState<_BulkRenewSheet> {
  bool _loading = true;
  bool _processing = false;
  List<_RenewRow> _rows = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.partialCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll() async {
    final notifier = ref.read(subscribersProvider.notifier);
    final subs = widget.subscribers.where((s) => s.idx != null).toList();
    final rows = <_RenewRow>[];
    const concurrency = 6;
    for (var i = 0; i < subs.length; i += concurrency) {
      if (!mounted) return;
      final batch = subs.skip(i).take(concurrency).toList();
      final results = await Future.wait(batch.map((s) async {
        Map<String, dynamic>? ad;
        try {
          ad = await notifier.getActivationData(int.parse(s.idx!));
        } catch (_) {
          ad = null;
        }
        return MapEntry(s, ad);
      }));
      for (final e in results) {
        final s = e.key;
        final ad = e.value;
        if (ad == null) {
          rows.add(_RenewRow(
            sub: s,
            originalPrice: 0,
            discount: 0,
            units: null,
            currentBalance: s.debtAmount,
            loadFailed: true,
          ));
          continue;
        }
        final price = _pickPositive([
          ad['user_price'],
          ad['sale_price'],
          ad['sell_price'],
          s.price,
        ]);
        rows.add(_RenewRow(
          sub: s,
          originalPrice: price,
          discount: (s.discount ?? 0).toDouble(),
          units: ad['units'],
          currentBalance: s.debtAmount,
        ));
      }
      if (mounted) setState(() => _rows = List.of(rows));
    }
    if (mounted) setState(() => _loading = false);
  }

  void _setAll(_PayMethod m) {
    setState(() {
      for (final r in _rows) {
        if (r.renewable) r.method = m;
      }
    });
  }

  // ── الملخّص ────────────────────────────────────────────────────
  ({int debt, int cash, int partial, double cashTotal}) get _summary {
    var d = 0, c = 0, p = 0;
    var ct = 0.0;
    for (final r in _rows) {
      if (!r.renewable) continue;
      switch (r.method) {
        case _PayMethod.debt:
          d++;
          break;
        case _PayMethod.cash:
          c++;
          ct += r.cashIn;
          break;
        case _PayMethod.partial:
          p++;
          ct += r.cashIn;
          break;
      }
    }
    return (debt: d, cash: c, partial: p, cashTotal: ct);
  }

  Future<void> _confirmAndRun() async {
    final renewable = _rows.where((r) => r.renewable).toList();
    if (renewable.isEmpty) {
      AppSnackBar.error(context, 'لا يوجد مشترك قابل للتجديد');
      return;
    }
    // تحقّق من المبالغ الجزئية — يكفي أن يكون أكبر من صفر. لو تجاوز السعر،
    // الفائض يُسجَّل رصيداً للمشترك (نفس منطق التفعيل الفردي).
    for (final r in renewable) {
      if (r.method == _PayMethod.partial && r.partialAmount <= 0) {
        AppSnackBar.error(
            context, 'أدخل المبلغ الجزئي للمشترك ${r.sub.username}');
        return;
      }
    }

    final s = _summary;
    final n = renewable.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تأكيد تجديد $n اشتراك'),
        content: Text(
          'دين: ${s.debt}  ·  نقدي: ${s.cash}  ·  جزئي: ${s.partial}\n'
          'إجمالي المقبوض نقداً: ${AppHelpers.formatMoney(s.cashTotal)} د.ع\n\n'
          'يُسجَّل وصل لكل عملية في الأرشيف. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            child: const Text('تجديد الآن'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _process(renewable);
  }

  Future<void> _process(List<_RenewRow> rows) async {
    setState(() => _processing = true);
    final notifier = ref.read(subscribersProvider.notifier);
    final navigator = Navigator.of(context, rootNavigator: true);
    final progress = ValueNotifier<int>(0);
    final n = rows.length;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const SizedBox(
              width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 16),
          Expanded(
            child: ValueListenableBuilder<int>(
              valueListenable: progress,
              builder: (_, done, __) =>
                  Text('جارٍ التجديد... $done/$n', style: const TextStyle(fontSize: 13)),
            ),
          ),
        ]),
      ),
    );

    final failed = <String>[]; // "username — السبب"
    final succeeded = <_RenewRow>[];
    var ok = 0;
    var done = 0;
    for (final r in rows) {
      final id = int.parse(r.sub.idx!);
      try {
        final res = await notifier.activateSubscriber(
          userId: id,
          userPrice: r.finalPrice,
          activationUnits: r.units,
          currentNotes: r.currentBalance.toString(),
          isCash: r.method != _PayMethod.debt,
          isPartialCash: r.method == _PayMethod.partial,
          partialCashAmount: r.method == _PayMethod.partial ? r.partialAmount : 0,
          packageName: r.sub.profileName,
          originalPrice: r.originalPrice,
          discountAmount: r.discount,
        );
        if (res.ok) {
          ok++;
          succeeded.add(r);
          final nb = r.newBalance;
          // أرشفة الوصل (fire-and-forget — فشلها لا يُفشل العملية).
          try {
            await archivePrintedReceipt(
              ref,
              data: ReceiptData(
                subscriberName: r.sub.username,
                firstName: r.sub.fullName,
                phoneNumber: r.sub.displayPhone,
                packageName: r.sub.profileName ?? '',
                packagePrice: r.finalPrice,
                paidAmount: r.cashIn,
                debtAmount: nb < 0 ? nb.abs() : 0,
                remainingAmount: nb < 0 ? nb.abs() : 0,
                operationType: 'activation',
              ),
              operation: ReceiptOperation.activate,
              paymentMethod: r.method.receiptMethod,
              subscriberId: r.sub.idx,
              subscriberUsername: r.sub.username,
            );
          } catch (_) {/* الأرشفة best-effort */}
        } else {
          failed.add('${r.sub.username} — ${res.errorMessage ?? 'فشل'}');
        }
      } catch (e) {
        failed.add('${r.sub.username} — خطأ');
      }
      progress.value = ++done;
    }

    // حدّث القائمة لتعكس تواريخ الانتهاء/الأرصدة الجديدة.
    try {
      await notifier.loadSubscribers();
    } catch (_) {}

    // أرسل إشعارات «التفعيل» عبر قائمة انتظار الواتساب بالباك-اند (تُرسَل
    // واحدة بعد الأخرى) — نلتقط تاريخ الانتهاء الجديد من القائمة المُحدَّثة.
    var waQueued = 0;
    String? waReason;
    if (succeeded.isNotEmpty) {
      final freshByUsername = <String, SubscriberModel>{};
      for (final s in ref.read(subscribersProvider).subscribers) {
        freshByUsername[s.username.toLowerCase()] = s;
      }
      final items = succeeded.map((r) {
        final fresh = freshByUsername[r.sub.username.toLowerCase()];
        final nb = r.newBalance;
        return <String, dynamic>{
          'idx': r.sub.idx,
          'username': r.sub.username,
          'phone': r.sub.displayPhone,
          'firstname': r.sub.firstname,
          'lastname': r.sub.lastname,
          'package_name': r.sub.profileName ?? '',
          'package_price': r.originalPrice,
          'discount_amount': r.discount,
          'discounted_price': r.finalPrice,
          'paid_amount': r.cashIn,
          'new_balance': nb,
          'expiration': fresh?.expiration ?? r.sub.expiration ?? '',
        };
      }).toList();
      final qr = await notifier.queueActivationNotices(items);
      waQueued = qr.queued;
      waReason = qr.reason;
    }

    navigator.pop(); // أغلق نافذة التقدّم
    progress.dispose();
    if (!mounted) return;

    // نص حالة الواتساب للملخّص.
    String? waDetail() {
      if (succeeded.isEmpty) return null;
      if (waQueued > 0) return '$waQueued رسالة واتساب في قائمة الإرسال';
      if (waReason == 'notifications_disabled' || waReason == 'feature_off') {
        return 'إشعارات الواتساب مُعطَّلة — لم تُضف رسائل';
      }
      if (waReason == 'no_template') {
        return 'لا يوجد قالب «إشعار التفعيل» نشط — لم تُرسل رسائل';
      }
      return 'لم تُضف رسائل واتساب';
    }

    // اعرض ملخّصاً ثم أغلق المودل.
    if (failed.isEmpty) {
      AppSnackBar.success(context, 'تم تجديد $ok اشتراك بنجاح',
          detail: waDetail());
      Navigator.pop(context, true);
    } else {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ok > 0 ? 'تم تجديد $ok — فشل ${failed.length}' : 'فشل التجديد (${failed.length})'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                if (waDetail() != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('📨 ${waDetail()}',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
                for (final f in failed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text('• $f', style: const TextStyle(fontSize: 12.5)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('حسناً')),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, ok > 0);
    }
  }

  // ── البناء ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = _summary;
    final renewableCount = _rows.where((r) => r.renewable).length;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              Icon(LucideIcons.calendarPlus, size: 20, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'تجديد اشتراك ${widget.subscribers.length} مشترك',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ]),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),

          // "اجعل الكل"
          if (!_loading && renewableCount > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(children: [
                Text('اجعل الكل:',
                    style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurface.withOpacity(0.7))),
                const SizedBox(width: 8),
                for (final m in _PayMethod.values) ...[
                  OutlinedButton(
                    onPressed: () => _setAll(m),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      minimumSize: const Size(0, 30),
                    ),
                    child: Text(m.label, style: const TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 6),
                ],
              ]),
            ),

          const Divider(height: 1),

          // القائمة
          Expanded(
            child: _loading && _rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: _rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _rowCard(theme, _rows[i]),
                  ),
          ),

          // الملخّص + الأزرار
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                  top: BorderSide(
                      color: theme.colorScheme.onSurface.withOpacity(0.12))),
            ),
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (!_loading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          'دين ${s.debt} · نقدي ${s.cash} · جزئي ${s.partial}'
                          '   |   نقداً: ${AppHelpers.formatMoney(s.cashTotal)} د.ع',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface.withOpacity(0.75),
                          ),
                        ),
                      ),
                    ]),
                  ),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _processing ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46)),
                      child: const Text('إلغاء',
                          style: TextStyle(
                              fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: (_loading || _processing || renewableCount == 0)
                          ? null
                          : _confirmAndRun,
                      icon: const Icon(LucideIcons.calendarPlus, size: 16),
                      label: Text(
                        'تجديد الآن ($renewableCount)',
                        style: const TextStyle(
                            fontFamily: 'Cairo', fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowCard(ThemeData theme, _RenewRow r) {
    final disabled = !r.renewable;
    final bal = r.currentBalance;
    final nb = r.newBalance;
    return Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.cardTheme.color ?? Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.sub.fullName.isNotEmpty ? r.sub.fullName : r.sub.username,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (r.sub.username.isNotEmpty &&
                        r.sub.username != r.sub.fullName)
                      Text(
                        r.sub.username,
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface.withOpacity(0.5)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // السعر
              if (!disabled)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (r.discount > 0)
                      Text(
                        AppHelpers.formatMoney(r.originalPrice),
                        style: TextStyle(
                          fontSize: 10,
                          decoration: TextDecoration.lineThrough,
                          color: theme.colorScheme.onSurface.withOpacity(0.4),
                        ),
                      ),
                    Text(
                      '${AppHelpers.formatMoney(r.finalPrice)} د.ع',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: AppTheme.primary),
                    ),
                  ],
                )
              else
                const Text('تعذّر جلب بيانات التفعيل',
                    style: TextStyle(fontSize: 11, color: Colors.red)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              if (r.sub.profileName != null && r.sub.profileName!.isNotEmpty)
                _chip(theme, LucideIcons.wifi, r.sub.profileName!, AppTheme.primary),
              const SizedBox(width: 6),
              if (bal.abs() >= 1)
                _chip(
                  theme,
                  bal < 0 ? LucideIcons.creditCard : LucideIcons.wallet,
                  bal < 0
                      ? 'دين ${AppHelpers.formatMoney(bal.abs())}'
                      : 'رصيد ${AppHelpers.formatMoney(bal)}',
                  bal < 0 ? Colors.red : Colors.green,
                ),
            ]),
            if (!disabled) ...[
              const SizedBox(height: 8),
              SegmentedButton<_PayMethod>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 11.5, fontFamily: 'Cairo'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                segments: const [
                  ButtonSegment(value: _PayMethod.debt, label: Text('دين')),
                  ButtonSegment(value: _PayMethod.cash, label: Text('نقدي')),
                  ButtonSegment(value: _PayMethod.partial, label: Text('جزئي')),
                ],
                selected: {r.method},
                onSelectionChanged: (sel) =>
                    setState(() => r.method = sel.first),
              ),
              if (r.method == _PayMethod.partial) ...[
                const SizedBox(height: 8),
                Row(children: [
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: r.partialCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'المبلغ نقداً',
                        isDense: true,
                        border: OutlineInputBorder(),
                        suffixText: 'د.ع',
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final v in _quickAmounts(r.finalPrice))
                          ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(AppHelpers.formatMoney(v),
                                style: const TextStyle(fontSize: 10.5)),
                            onPressed: () => setState(() {
                              r.partialCtrl.text =
                                  (r.partialAmount + v).toStringAsFixed(0);
                            }),
                          ),
                      ],
                    ),
                  ),
                ]),
              ],
              if (r.method != _PayMethod.cash) ...[
                const SizedBox(height: 6),
                Text(
                  nb < 0
                      ? 'الدين بعد العملية: ${AppHelpers.formatMoney(nb.abs())} د.ع'
                      : nb > 0
                          ? 'رصيد بعد العملية: ${AppHelpers.formatMoney(nb)} د.ع'
                          : 'لا دين بعد العملية',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: nb < 0 ? Colors.red.shade700 : Colors.green.shade700,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(ThemeData theme, IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }

  List<double> _quickAmounts(double price) {
    const presets = <double>[5000, 10000, 15000, 25000, 35000, 50000];
    return [for (final v in presets) if (v < price) v];
  }
}
