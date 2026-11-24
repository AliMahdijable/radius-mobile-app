import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/balance_requests_api.dart';
import '../../api/dashboard_api.dart';
import '../../core/util/amount_input.dart';
import '../../core/util/format.dart';
import '../../core/util/phone.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import '../tickets/ticket_image.dart';
import 'balance_request_widgets.dart';

/// «طلباتك»: آخر عشرة (المالك ٢٤ نوفمبر: «الطلبات اخر ١٠ قرات») — الخادم يعيد عشرين.
const kBalanceReqSubList = 10;

/// «طلب رصيد من مديرك» — قسم المدير الفرعيّ (المالك ٢٣ نوفمبر: «النظام يكشف المدراء الفرعيين، اللي فوقهم مدير عندنا مسجل… يسوي
/// طلب رصيد من المدير الاعلى… يدز له صورة حوالة… نحط بيها الماستر كارد مالته والتواصل مالته»). رصيده، ومديره (واتساب/اتصال)،
/// و«ادفع لمديرك» (بيانات بوّابة المشترك عنده)، وطلباته بحالها — والطلب: المبلغ + «كيف دفعت؟» + صورة الحوالة.
class SubBalanceRequestScreen extends StatefulWidget {
  const SubBalanceRequestScreen({super.key, this.wallet = DashboardApi.fetchWallet, this.pickImage = pickTicketImage});

  /// رصيد الصفحة بالساس (admin-widgets) — قابلٌ للحقن في الاختبار.
  final Future<WalletResult?> Function() wallet;
  final TicketImagePicker pickImage;

  @override
  State<SubBalanceRequestScreen> createState() => _SubBalanceRequestScreenState();
}

class _SubBalanceRequestScreenState extends State<SubBalanceRequestScreen> {
  num? _balance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait([
      BalanceReqState.refreshMe(force: true),
      widget.wallet().then((w) {
        if (mounted && w != null) setState(() => _balance = w.balance);
      }).catchError((_) {}),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _request(BalanceReqMe me) async {
    final ok = await showBalanceRequestSheet(context, me, pickImage: widget.pickImage);
    if (ok == true && mounted) {
      unawaited(showSheetSnack(context, 'وصل طلبك لمديرك — يوصلك إشعار بردّه', isError: false));
      await BalanceReqState.refreshMe(force: true);
    }
  }

  Future<void> _cancel(BalanceRequest r) async {
    final yes = await showConfirmSheet(
      context,
      title: 'إلغاء الطلب؟',
      message: 'طلب ${balanceReqIqd(r.amount)} — يُحذف من قائمة مديرك',
      confirmLabel: 'إلغاء الطلب',
      tone: AppTone.danger,
      icon: LucideIcons.x,
    );
    if (yes != true || !mounted) return;
    final res = await BalanceRequestsApi.cancel(r.id);
    if (!mounted) return;
    if (!res.ok) {
      unawaited(showSheetSnack(context, res.message ?? 'تعذّر الإلغاء', isError: true));
    }
    await BalanceReqState.refreshMe(force: true);
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
          title: Text('طلب رصيد من مديرك', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        ),
        title: 'طلب رصيد من مديرك',
      ),
      body: ValueListenableBuilder<BalanceReqMe>(
        valueListenable: BalanceReqState.me,
        builder: (context, me, _) {
          if (_loading && !me.enabled) return const Center(child: CircularProgressIndicator());
          if (!me.enabled) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(Sp.xl),
                child: Text('«طلب رصيد من مديرك» غير متاح لحسابك',
                    textAlign: TextAlign.center, style: AppType.body(color: AppColors.textMid)),
              ),
            );
          }
          final parent = me.parent!;
          final open = me.requests.where((r) => r.isOpen).toList();
          return RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              key: const ValueKey('balreq-sub-list'),
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
              children: [
                _Hero(balance: _balance, me: me),
                const SizedBox(height: Sp.md),
                FilledButton.icon(
                  key: const ValueKey('balreq-new'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    disabledBackgroundColor: AppColors.surfaceDisabled,
                    minimumSize: const Size.fromHeight(H.button),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button)),
                  ),
                  onPressed: me.canRequest && open.isEmpty ? () => _request(me) : null,
                  icon: Icon(LucideIcons.handCoins, size: 20, color: me.canRequest && open.isEmpty ? AppColors.onBrand : AppColors.textLow),
                  label: Text(open.isEmpty ? 'طلب رصيد' : 'عندك طلب بانتظار مديرك',
                      style: AppType.button(color: me.canRequest && open.isEmpty ? AppColors.onBrand : AppColors.textLow)),
                ),
                if (!me.canRequest) ...[
                  const SizedBox(height: Sp.sm),
                  const BalanceReqHint(icon: LucideIcons.lock, text: 'طلب الرصيد لمدير الصفحة وحده'),
                ],
                const SizedBox(height: Sp.lg),
                const _SectionLabel('مديرك'),
                _ParentCard(parent: parent),
                if (me.pay.any) ...[
                  const SizedBox(height: Sp.lg),
                  const _SectionLabel('ادفع لمديرك', trailing: 'اضغط الرقم للنسخ'),
                  _PayCard(pay: me.pay, owner: parent.title),
                  const SizedBox(height: Sp.sm),
                  const BalanceReqHint(
                    icon: LucideIcons.info,
                    text: 'حوّل وأرسل صورة الحوالة مع الطلب — أو اطلب «كاش» وسلّمه باليد، أو «آجل» يصير ديناً عليك',
                  ),
                ],
                const SizedBox(height: Sp.lg),
                const _SectionLabel('طلباتك'),
                if (me.requests.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Sp.lg),
                    child: Text('لا طلبات بعد', textAlign: TextAlign.center, style: AppType.body(color: AppColors.textLow)),
                  )
                else
                  // آخر عشرة وحدها — والنقر يفتح تفاصيله (المالك: «من ينقر عليه يظهر تاريخ الحركة وملخّص الحركة»)
                  for (final r in me.requests.take(kBalanceReqSubList)) ...[
                    _MyRequestCard(
                      request: r,
                      parent: parent,
                      onCancel: r.isPending ? () => _cancel(r) : null,
                      onTap: () => showMyBalanceRequestDetails(context, r, parent),
                    ),
                    const SizedBox(height: Sp.sm),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Sp.sm, right: Sp.xs, left: Sp.xs),
        child: Row(children: [
          Expanded(child: Text(text, maxLines: 2, style: AppType.label(color: AppColors.textMid))),
          if (trailing != null) Text(trailing!, maxLines: 1, style: AppType.muted()),
        ]),
      );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.balance, required this.me});
  final num? balance;
  final BalanceReqMe me;

  @override
  Widget build(BuildContext context) {
    final last = me.lastDepositAt;
    return Container(
      key: const ValueKey('balreq-hero'),
      padding: const EdgeInsets.all(Sp.xl),
      decoration: BoxDecoration(color: AppColors.brandSurface, borderRadius: BorderRadius.circular(R.card)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(LucideIcons.wallet, size: 18, color: AppColors.onBrandSecondary),
          const SizedBox(width: Sp.sm),
          Text('رصيدك بالساس', style: AppType.label(color: AppColors.onBrandSecondary)),
        ]),
        const SizedBox(height: Sp.sm),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(balance == null ? '—' : balanceReqIqdSigned(balance!),
              style: AppType.amount(color: AppColors.onBrand).copyWith(fontSize: 30)),
        ),
        const SizedBox(height: Sp.md),
        Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
          if (last != null)
            _HeroChip(
              icon: LucideIcons.history,
              text: 'آخر شحن ${balanceReqWhen(last)}${me.lastDepositLoan ? ' (آجل)' : ''}',
            ),
          if (me.pending > 0) const _HeroChip(icon: LucideIcons.hourglass, text: 'طلبٌ بانتظار مديرك'),
        ]),
      ]),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs + 2),
        decoration: BoxDecoration(color: AppColors.onBrand.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(R.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AppColors.onBrand),
          const SizedBox(width: Sp.xs),
          Flexible(child: Text(text, maxLines: 2, style: AppType.label(color: AppColors.onBrand))),
        ]),
      );
}

class _ParentCard extends StatelessWidget {
  const _ParentCard({required this.parent});
  final BalanceReqParent parent;

  Future<void> _open(BuildContext context, Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
    if (!ok && context.mounted) unawaited(showSheetSnack(context, 'تعذّر فتح التطبيق', isError: true));
  }

  @override
  Widget build(BuildContext context) {
    final wa = parent.whatsapp ?? parent.phone;
    final tel = parent.phone ?? parent.whatsapp;
    final initial = parent.title.characters.isEmpty ? '؟' : parent.title.characters.first;
    return BalanceReqCard(
      child: Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppTone.brand.softBg,
          child: Text(initial, style: AppType.title(color: AppTone.brand.fill)),
        ),
        const SizedBox(width: Sp.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(parent.title, maxLines: 2, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 15)),
            if (parent.username != null)
              Text(parent.username!, maxLines: 1, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr,
                  style: AppType.muted()),
          ]),
        ),
        if (wa != null)
          _RoundAction(
            key: const ValueKey('balreq-parent-wa'),
            icon: LucideIcons.messageCircle,
            label: 'واتساب',
            tone: AppTone.whatsapp,
            onTap: () => _open(context, Uri.parse('https://wa.me/${waPhone(wa)}')),
          ),
        if (tel != null) ...[
          const SizedBox(width: Sp.sm),
          _RoundAction(
            key: const ValueKey('balreq-parent-call'),
            icon: LucideIcons.phone,
            label: 'اتصال',
            tone: AppTone.brand,
            onTap: () => _open(context, Uri(scheme: 'tel', path: tel.replaceAll(RegExp(r'[^0-9+]'), ''))),
          ),
        ],
      ]),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({super.key, required this.icon, required this.label, required this.tone, required this.onTap});
  final IconData icon;
  final String label;
  final AppTone tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(R.card),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Sp.xs),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 20, backgroundColor: tone.softBg, child: Icon(icon, size: 18, color: tone.fill)),
            const SizedBox(height: 4),
            Text(label, style: AppType.muted()),
          ]),
        ),
      );
}

class _PayCard extends StatelessWidget {
  const _PayCard({required this.pay, required this.owner});
  final BalanceReqPay pay;
  final String owner;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      if (pay.zaincash != null) _PayRow(key: const ValueKey('balreq-pay-zaincash'), icon: LucideIcons.smartphone, title: 'زين كاش', value: pay.zaincash!, owner: owner),
      if (pay.master != null) _PayRow(key: const ValueKey('balreq-pay-master'), icon: LucideIcons.creditCard, title: 'ماستر كارد', value: pay.master!, owner: owner),
    ];
    return BalanceReqCard(
      padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.sm),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: AppColors.border),
          rows[i],
        ],
        if (pay.note != null) ...[
          Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Sp.sm),
            child: BalanceReqHint(icon: LucideIcons.stickyNote, text: pay.note!),
          ),
        ],
      ]),
    );
  }
}

class _PayRow extends StatelessWidget {
  const _PayRow({super.key, required this.icon, required this.title, required this.value, required this.owner});
  final IconData icon;
  final String title;
  final String value;
  final String owner;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (context.mounted) unawaited(showSheetSnack(context, 'نُسخ رقم $title', isError: false));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Sp.md),
          child: Row(children: [
            CircleAvatar(radius: 18, backgroundColor: AppTone.info.softBg, child: Icon(icon, size: 17, color: AppTone.info.fill)),
            const SizedBox(width: Sp.md),
            // الرقم بسطره تحت الاسم ويصغر ليتّسع — لا يُقصّ رقمٌ يُحوَّل إليه (المالك: «لا رقم يُقصّ»)
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$title — باسم $owner', maxLines: 2, style: AppType.muted()),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value, textDirection: TextDirection.ltr, style: AppType.bodyStrong(color: AppColors.textHi).copyWith(fontSize: 15)),
                ),
              ]),
            ),
            const SizedBox(width: Sp.sm),
            Icon(LucideIcons.copy, size: 16, color: AppColors.textLow),
          ]),
        ),
      );
}

class _MyRequestCard extends StatelessWidget {
  const _MyRequestCard({required this.request, required this.parent, this.onCancel, this.onTap});
  final BalanceRequest request;
  final BalanceReqParent parent;
  final VoidCallback? onCancel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final d = r.done;
    return BalanceReqCard(
      key: ValueKey('balreq-mine-${r.id}'),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(balanceReqIqd(r.amount), style: AppType.amount(color: AppColors.textHi).copyWith(fontSize: 20)),
              ),
              const SizedBox(height: Sp.xs),
              Wrap(spacing: Sp.sm, runSpacing: Sp.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                BalanceReqMethodChip(r),
                if (r.hasImage) const ToneChip(label: 'بوصل', icon: LucideIcons.image, dense: true),
                Text(balanceReqWhen(r.createdAt), style: AppType.muted()),
              ]),
            ]),
          ),
          const SizedBox(width: Sp.sm),
          BalanceReqStatusChip(r),
          if (onTap != null) ...[
            const SizedBox(width: Sp.xs),
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
            ),
          ],
        ]),
        if (d != null) ...[
          const SizedBox(height: Sp.md),
          BalanceReqHint(
            icon: LucideIcons.circleCheck,
            tone: AppTone.success,
            text: [
              '${parent.title} شحن ${balanceReqIqd(d.amount ?? r.amount)}',
              if (d.viaLabel.isNotEmpty) d.isLoan ? 'آجل — دين عليك' : 'استلمه ${d.viaLabel}',
              if (d.balanceBefore != null && d.balanceAfter != null)
                'رصيدك ${balanceReqIqdSigned(d.balanceBefore!)} ← ${balanceReqIqdSigned(d.balanceAfter!)}',
            ].join(' · '),
          ),
        ],
        if (r.status == 'rejected') ...[
          const SizedBox(height: Sp.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              color: AppTone.danger.softBg,
              borderRadius: BorderRadius.circular(R.card / 2),
              border: Border.all(color: AppTone.danger.softBorder),
            ),
            child: BalanceReqHint(
              icon: LucideIcons.messageSquareText,
              tone: AppTone.danger,
              text: r.rejectReason == null ? 'رفضه مديرك' : 'سبب الرفض من مديرك: «${r.rejectReason}»',
            ),
          ),
        ],
        if (r.note != null) ...[
          const SizedBox(height: Sp.sm),
          BalanceReqHint(icon: LucideIcons.stickyNote, text: r.note!),
        ],
        if (onCancel != null) ...[
          const SizedBox(height: Sp.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              key: ValueKey('balreq-cancel-${r.id}'),
              onPressed: onCancel,
              icon: Icon(LucideIcons.x, size: 16, color: AppColors.textMid),
              label: Text('إلغاء الطلب', style: AppType.label(color: AppColors.textMid)),
            ),
          ),
        ],
      ]),
    );
  }
}

// ─────────────── تفاصيل طلبه ───────────────

/// تفاصيل طلبه حين ينقر بطاقته (المالك ٢٤ نوفمبر: «الطلب المرفوض والناجح من ينقر عليه يظهر تاريخ الحركة وملخّص الحركة»): ما جرى
/// أوّلاً بتاريخه — «ملخّص الحركة» للمشحون (المبلغ، كيف سُجّل، رصيده قبل/بعد بإشارته)، الرفض وسببه، الإلغاء، الانتهاء، أو حاله — ثمّ
/// طلبه نفسه. كالموقع (lib/balance-requests.ts requestDetails).
Future<void> showMyBalanceRequestDetails(BuildContext context, BalanceRequest r, BalanceReqParent parent) => showAppSheet<void>(
      context: context,
      barrierColor: AppColors.scrim,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MyDetailsSheet(request: r, parent: parent),
    );

class _MyDetailsSheet extends StatelessWidget {
  const _MyDetailsSheet({required this.request, required this.parent});
  final BalanceRequest request;
  final BalanceReqParent parent;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final d = r.done;
    final s = balanceReqStatus(r);
    final (String, List<SheetRowData>)? what = switch (r.status) {
      'done' when d != null => (
          'ملخّص الحركة',
          [
            SheetRowData(label: 'تاريخ الحركة', value: balanceReqWhen(r.decidedAt)),
            SheetRowData(label: 'شُحن لك', value: balanceReqIqd(d.amount ?? r.amount), strong: true),
            SheetRowData(label: 'كيف سُجّل', value: d.isLoan ? 'آجل — دين عليك' : (d.viaLabel.isEmpty ? '—' : 'استلمه ${d.viaLabel}')),
            if (d.balanceBefore != null) SheetRowData(label: 'رصيدك قبل', value: balanceReqIqdSigned(d.balanceBefore!)),
            if (d.balanceAfter != null) SheetRowData(label: 'رصيدك بعد', value: balanceReqIqdSigned(d.balanceAfter!), strong: true),
            SheetRowData(label: 'شحنه', value: parent.title),
          ],
        ),
      'rejected' => (
          'الرفض',
          [
            SheetRowData(label: 'تاريخ الرفض', value: balanceReqWhen(r.decidedAt)),
            SheetRowData(label: 'السبب', value: r.rejectReason ?? 'لم يذكر سبباً'),
            SheetRowData(label: 'رفضه', value: parent.title),
          ],
        ),
      'cancelled' => (
          'الإلغاء',
          [SheetRowData(label: 'تاريخ الإلغاء', value: balanceReqWhen(r.decidedAt)), const SheetRowData(label: 'ألغاه', value: 'أنت')],
        ),
      'expired' => (
          'انتهى بلا ردّ',
          [
            SheetRowData(label: 'تاريخ الانتهاء', value: balanceReqWhen(r.decidedAt)),
            const SheetRowData(label: 'السبب', value: 'مرّت ٧ أيّام بلا ردٍّ من مديرك'),
          ],
        ),
      'pending' => ('الحال', [const SheetRowData(label: 'الحال', value: 'بانتظار مديرك — يوصلك إشعار بردّه')]),
      'processing' => ('الحال', [const SheetRowData(label: 'الحال', value: 'قيد الشحن — مديرك يشحنه الآن')]),
      _ => null,
    };
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.handCoins,
        title: 'طلب ${balanceReqIqd(r.amount)}',
        subtitle: '${r.methodLabel.isEmpty ? r.payMethod : r.methodLabel} · ${s.label}',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (what != null) ...[
          SheetSection(
            key: ValueKey('balreq-details-${r.status}'),
            label: what.$1,
            child: _DetailRows(what.$2),
          ),
          const SizedBox(height: Sp.lg),
        ],
        SheetSection(
          key: const ValueKey('balreq-details-request'),
          label: 'طلبك',
          child: _DetailRows([
            SheetRowData(label: 'رقم الطلب', value: '#${r.id}'),
            SheetRowData(label: 'تاريخ الطلب', value: balanceReqWhen(r.createdAt)),
            SheetRowData(label: 'المبلغ المطلوب', value: balanceReqIqd(r.amount)),
            SheetRowData(label: 'كيف دفعت', value: r.methodLabel.isEmpty ? r.payMethod : r.methodLabel),
            if (r.hasImage) SheetRowData(label: 'الوصل', value: r.imageLive ? 'مرفق' : 'مرفق — حُذفت صورته بعد ٧ أيّام'),
            if (r.note != null) SheetRowData(label: 'ملاحظتك', value: r.note!),
          ]),
        ),
      ]),
    );
  }
}

/// صفوف التفاصيل: التسمية بعرضها كاملةً والقيمة تلتفّ بما بقي (تاريخ، سبب الرفض، ملاحظة) — SheetRowsGroup للأرقام القصيرة يقصّ
/// التسمية بجانب قيمةٍ طويلة (٣٢٠ × ١٫٢: «تاريخ الطلب…»). القيمة باتّجاه السطر العربيّ (الأرقام والتواريخ تبقى بترتيبها).
class _DetailRows extends StatelessWidget {
  const _DetailRows(this.rows);
  final List<SheetRowData> rows;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rows[i].label, style: AppType.body(color: AppColors.textLabel)),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Text(
                  rows[i].value,
                  textAlign: TextAlign.end,
                  maxLines: 8,
                  style: AppType.body(color: rows[i].valueColor ?? AppColors.textHi)
                      .copyWith(fontWeight: rows[i].strong ? FontWeight.w700 : FontWeight.w600),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ─────────────── نافذة الطلب ───────────────

/// «طلب رصيد»: المبلغ + «كيف دفعت؟» (حوّلت له: زين كاش/ماستر/أخرى بصورة الحوالة؛ بلا حوالة: كاش باليد/آجل) + ملاحظة.
/// المرجع ثابتٌ للنافذة: إعادة الإرسال بعد ردٍّ ضاع تعيد الطلب نفسه (الخادم).
Future<bool?> showBalanceRequestSheet(BuildContext context, BalanceReqMe me, {TicketImagePicker pickImage = pickTicketImage}) =>
    showAppSheet<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RequestSheet(me: me, pickImage: pickImage),
    );

String newBalanceRequestRef() {
  final r = math.Random.secure();
  final rand = List.generate(10, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[r.nextInt(36)]).join();
  return 'br-${DateTime.now().millisecondsSinceEpoch}-$rand';
}

class _RequestSheet extends StatefulWidget {
  const _RequestSheet({required this.me, required this.pickImage});
  final BalanceReqMe me;
  final TicketImagePicker pickImage;

  @override
  State<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends State<_RequestSheet> {
  final _amountCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final String _ref = newBalanceRequestRef();
  int _amount = 0;
  String? _method;
  Uint8List? _image;
  bool _picking = false;
  bool _sending = false;

  static const _quick = [100000, 250000, 500000, 1000000];
  bool get _transfer => _method == 'zaincash' || _method == 'master' || _method == 'other';

  String? get _problem {
    if (_amount < 1000) return 'اكتب المبلغ (1,000 أو أكثر)';
    if (_method == null) return 'اختر كيف دفعت';
    if (_method == 'other' && _nameCtrl.text.trim().isEmpty) return 'اكتب اسم الطريقة (أخرى)';
    if (_transfer && _image == null) return 'أرفق صورة الحوالة';
    return null;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _nameCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _setAmount(int v) {
    _amountCtrl.text = formatIQD(v);
    setState(() => _amount = v);
  }

  Future<void> _pick() async {
    if (_picking) return;
    final camera = await askTicketImageSource(context);
    if (camera == null || !mounted) return;
    setState(() => _picking = true);
    try {
      final bytes = await widget.pickImage(camera: camera);
      if (bytes != null && mounted) setState(() => _image = bytes);
    } on TicketImageError catch (e) {
      if (mounted) unawaited(showSheetSnack(context, e.message, isError: true));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _send() async {
    final p = _problem;
    if (p != null) {
      unawaited(showSheetSnack(context, p, isError: true));
      return;
    }
    setState(() => _sending = true);
    final r = await BalanceRequestsApi.create(
      clientRef: _ref,
      amount: _amount,
      payMethod: _method!,
      payName: _method == 'other' ? _nameCtrl.text : null,
      note: _noteCtrl.text,
      imageJpeg: _transfer ? _image : null,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (!r.ok) {
      unawaited(showSheetSnack(context, r.message ?? 'تعذّر إرسال الطلب', isError: true));
      return;
    }
    Navigator.of(context).pop(true);
  }

  Widget _methodChip(String key, String label, IconData icon) => SheetQuickChip(
        key: ValueKey('balreq-method-$key'),
        label: label,
        icon: icon,
        selected: _method == key,
        enabled: !_sending,
        onTap: () => setState(() {
          _method = key;
          if (!_transfer) _image = null;
        }),
      );

  @override
  Widget build(BuildContext context) {
    final parent = widget.me.parent!;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.handCoins,
        title: 'طلب رصيد',
        subtitle: 'من ${parent.title} — يوصله إشعار فوراً',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SheetSection(
          label: 'المبلغ',
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AmountShorthandBox(
              controller: _amountCtrl,
              child: AmountTextField(
                key: const ValueKey('balreq-amount'),
                controller: _amountCtrl,
                enabled: !_sending,
                onValue: (v) => setState(() => _amount = v.round()),
              ),
            ),
            const SizedBox(height: Sp.sm),
            Wrap(spacing: 7, runSpacing: 7, children: [
              for (final q in _quick)
                SheetQuickChip(
                  key: ValueKey('balreq-quick-$q'),
                  label: formatIQD(q),
                  selected: _amount == q,
                  enabled: !_sending,
                  onTap: () => _setAmount(q),
                ),
            ]),
          ]),
        ),
        const SizedBox(height: Sp.lg),
        SheetSection(
          label: 'كيف دفعت؟',
          footnote: 'مديرك يشوف اختيارك ويأكّده عند الشحن',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('حوّلت له', style: AppType.muted()),
            const SizedBox(height: Sp.xs),
            Wrap(spacing: 7, runSpacing: 7, children: [
              _methodChip('zaincash', 'زين كاش', LucideIcons.smartphone),
              _methodChip('master', 'ماستر كارد', LucideIcons.creditCard),
              _methodChip('other', 'أخرى', LucideIcons.landmark),
            ]),
            const SizedBox(height: Sp.sm),
            Text('بلا حوالة', style: AppType.muted()),
            const SizedBox(height: Sp.xs),
            Wrap(spacing: 7, runSpacing: 7, children: [
              _methodChip('cash', 'كاش باليد', LucideIcons.banknote),
              _methodChip('loan', 'آجل — دين عليّ', LucideIcons.hourglass),
            ]),
            if (_method == 'other') ...[
              const SizedBox(height: Sp.sm),
              SheetNoteField(
                key: const ValueKey('balreq-other-name'),
                controller: _nameCtrl,
                hint: 'اسم الطريقة (مثلاً: آسيا حوالة)',
                maxLength: 40,
                maxLines: 1,
                enabled: !_sending,
                icon: LucideIcons.landmark,
              ),
            ],
          ]),
        ),
        if (_transfer) ...[
          const SizedBox(height: Sp.lg),
          SheetSection(
            label: 'صورة الحوالة',
            hint: 'للحوالة وحدها',
            child: _ImagePickBox(image: _image, busy: _picking, enabled: !_sending, onPick: _pick),
          ),
        ],
        const SizedBox(height: Sp.lg),
        SheetSection(
          label: 'ملاحظة',
          child: SheetNoteField(
            key: const ValueKey('balreq-note'),
            controller: _noteCtrl,
            hint: 'رقم العمليّة أو أيّ شيءٍ يفيد مديرك',
            maxLength: 200,
            enabled: !_sending,
          ),
        ),
      ]),
      footer: SheetFooterBar(
        key: const ValueKey('balreq-send'),
        label: _amount >= 1000 ? 'إرسال الطلب — ${balanceReqIqd(_amount)}' : 'إرسال الطلب',
        icon: LucideIcons.send,
        busy: _sending,
        onPressed: _send,
      ),
    );
  }
}

class _ImagePickBox extends StatelessWidget {
  const _ImagePickBox({required this.image, required this.busy, required this.enabled, required this.onPick});
  final Uint8List? image;
  final bool busy;
  final bool enabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final img = image;
    return Row(children: [
      Container(
        width: 96,
        height: 120,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(R.icon),
          border: Border.all(color: AppColors.border),
        ),
        child: img == null
            ? Icon(LucideIcons.imagePlus, color: AppColors.textLow)
            : Image.memory(
                img,
                key: const ValueKey('balreq-image-preview'),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(LucideIcons.imageOff, color: AppColors.textLow),
              ),
      ),
      const SizedBox(width: Sp.md),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(img == null ? 'لم تُرفق صورة بعد' : 'صورة الحوالة جاهزة', style: AppType.bodyStrong(color: AppColors.textHi)),
          const SizedBox(height: Sp.sm),
          OutlinedButton.icon(
            key: const ValueKey('balreq-pick-image'),
            onPressed: enabled && !busy ? onPick : null,
            icon: busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(LucideIcons.camera, size: 18, color: AppColors.textHi),
            label: Text(img == null ? 'أرفق الصورة' : 'تغيير الصورة', style: AppType.button(color: AppColors.textHi)),
          ),
        ]),
      ),
    ]);
  }
}
