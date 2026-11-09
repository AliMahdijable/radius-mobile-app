import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/company_route.dart';
import '../../api/renew_requests_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/util/server_time.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../services/merged_mode.dart';
import '../../services/notification_router.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../subscribers/subscriber_detail_screen.dart';
import 'renew_requests_screen.dart';

/// «طلبات التفعيل» (٤ نوفمبر — المالك): بطاقة الطلب، صورة التحويل (تكبيرٌ بملء الشاشة)، النافذة السريعة (من الجرس والإشعار)،
/// وقسمها في صندوق الإشعارات (حين يوجد طلبٌ وحده — المالك: «في حال اكو طلب يظهر بالجرس»).

String renewMonthsLabel(int? n) => n == 1 ? 'شهر' : n == 2 ? 'شهرين' : (n == null ? '' : '$n أشهر');

String renewPayLabel(String? m) => switch (m) {
      'zaincash' => 'زين كاش',
      'master' => 'ماستر',
      'other' => 'تحويل آخر',
      _ => '',
    };

const renewRejectReasons = <String>[
  'لم يصل التحويل',
  'المبلغ غير صحيح',
  'صورة التحويل غير واضحة',
  'الباقة غير متاحة — تواصل معي',
];

({String label, Color fg, Color bg, IconData icon}) renewStatusMeta(String status) => switch (status) {
      'pending' => (label: 'بانتظارك', fg: AppColors.warningOnSoft, bg: AppColors.warningSoftBg, icon: LucideIcons.hourglass),
      'accepted' => (label: 'مقبول', fg: AppColors.info, bg: AppColors.infoSoftBg, icon: LucideIcons.clock),
      'done' => (label: 'تمّ التفعيل', fg: AppColors.success, bg: AppColors.successSoftBg, icon: LucideIcons.circleCheck),
      'rejected' => (label: 'مرفوض', fg: AppColors.dangerOnSoft, bg: AppColors.dangerSoftBg, icon: LucideIcons.circleX),
      'cancelled' => (label: 'ألغاه المشترك', fg: AppColors.textMid, bg: AppColors.surfaceSunken, icon: LucideIcons.x),
      _ => (label: 'انتهت مهلته', fg: AppColors.textMid, bg: AppColors.surfaceSunken, icon: LucideIcons.clock),
    };

/// «Fiber 50 · ٣ أشهر · 105,000 د.ع» — كلّ مقطعٍ معزول (اسم باقةٍ لاتينيّ بجوار رقمٍ لا يلتصقان فينقلب الترتيب).
String renewSummary(RenewRequest r) => isoJoin([
      r.packageName ?? '',
      renewMonthsLabel(r.months),
      if (r.amount != null) '${formatIQD(r.amount!)} د.ع',
    ], ' · ');

String _initials(String name) {
  final w = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).take(2).map((x) => x.characters.first).join();
  return w.isEmpty ? '؟' : w;
}

class RenewStatusChip extends StatelessWidget {
  const RenewStatusChip({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final m = renewStatusMeta(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
      decoration: BoxDecoration(color: m.bg, borderRadius: BorderRadius.circular(R.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(m.icon, size: 12, color: m.fg),
        const SizedBox(width: 4),
        Text(m.label, style: AppType.micro(color: m.fg).copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.title, required this.status, this.size = 40});
  final String title;
  final String status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final m = renewStatusMeta(status);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: m.bg, shape: BoxShape.circle),
      child: Text(_initials(title), style: AppType.bodyBold(color: m.fg).copyWith(fontSize: size * 0.34)),
    );
  }
}

/// صفٌّ مختصر — صندوق الإشعارات وقائمة «طلبات التفعيل».
class RenewRequestTile extends StatelessWidget {
  const RenewRequestTile({super.key, required this.request, required this.onTap});
  final RenewRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final r = request;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        key: ValueKey('renew-tile-${r.id}'),
        borderRadius: BorderRadius.circular(R.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.lg),
            border: Border.all(color: r.isPending ? AppColors.warningSoftBorder : AppColors.border),
          ),
          child: Row(children: [
            _Avatar(title: r.title, status: r.status, size: 38),
            const SizedBox(width: Sp.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyBold(color: AppColors.textHi)),
                  ),
                  const SizedBox(width: Sp.sm),
                  RenewStatusChip(status: r.status),
                ]),
                const SizedBox(height: 2),
                Text(renewSummary(r), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.muted(color: AppColors.textMid)),
                if (r.createdAt != null)
                  Text(timeAgoAr(r.createdAt), style: AppType.micro(color: AppColors.textLow)),
              ]),
            ),
            const SizedBox(width: Sp.xs),
            Icon(LucideIcons.chevronLeft, size: 18, color: AppColors.textLow),
          ]),
        ),
      ),
    );
  }
}

/// صورة التحويل: من الخادم بالتوثيق (ذاكرة الجلسة)، والنقر يكبّرها بملء الشاشة. حُذفت ⇒ سطرٌ يقول ذلك.
class RenewReceiptImage extends StatefulWidget {
  const RenewReceiptImage({super.key, required this.request, this.height = 220, this.openCompany = false});
  final RenewRequest request;
  final double height;

  /// طلب الشركة المفتوحة صراحةً ([RenewRequestDetails.openCompany]).
  final bool openCompany;

  @override
  State<RenewReceiptImage> createState() => _RenewReceiptImageState();
}

class _RenewReceiptImageState extends State<RenewReceiptImage> {
  Uint8List? _bytes;
  bool _gone = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.request.imageAvailable) {
      setState(() {
        _gone = true;
        _loading = false;
      });
      return;
    }
    Future<({Uint8List? bytes, bool gone})> load() => RenewRequestsApi.image(widget.request.id);
    final r = await (widget.openCompany ? CompanyRoute.runOpen(load) : load());
    if (!mounted) return;
    setState(() {
      _bytes = r.bytes;
      _gone = r.gone;
      _loading = false;
    });
  }

  String? _leftLabel() {
    final at = widget.request.imageExpiresAt;
    if (at == null) return null;
    final m = at.difference(DateTime.now()).inMinutes;
    if (m <= 0) return null;
    if (m < 60) return 'تُحذف الصورة بعد ${arMinutes(m)}';
    return 'تُحذف الصورة بعد ${arHours((m / 60).round())}';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    if (_gone) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Icon(LucideIcons.imageOff, size: 16, color: AppColors.textLow),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text('حُذفت صورة التحويل تلقائيّاً بعد ٢٤ ساعة', style: AppType.muted(color: AppColors.textMid))),
        ]),
      );
    }
    final b = _bytes;
    final left = _leftLabel();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Material(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('renew-receipt'),
          onTap: b == null ? null : () => _openViewer(context, b, widget.request.title),
          child: SizedBox(
            height: widget.height,
            child: b != null
                ? Stack(fit: StackFit.expand, children: [
                    Image.memory(b, fit: BoxFit.contain, gaplessPlayback: true),
                    PositionedDirectional(
                      start: Sp.sm,
                      bottom: Sp.sm,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 4),
                        decoration: BoxDecoration(color: AppColors.scrim, borderRadius: BorderRadius.circular(R.pill)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(LucideIcons.zoomIn, size: 14, color: AppColors.onBrand),
                          const SizedBox(width: 4),
                          Text('تكبير', style: AppType.micro(color: AppColors.onBrand)),
                        ]),
                      ),
                    ),
                  ])
                : Center(
                    child: _loading
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(LucideIcons.imageOff, size: 16, color: AppColors.textLow),
                            const SizedBox(width: Sp.xs),
                            Text('تعذّر عرض الصورة', style: AppType.muted(color: AppColors.textMid)),
                          ]),
                  ),
          ),
        ),
      ),
      if (left != null) ...[
        const SizedBox(height: Sp.xs),
        Text(left, style: AppType.micro(color: AppColors.textLow)),
      ],
    ]);
  }
}

void _openViewer(BuildContext context, Uint8List bytes, String name) {
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: AppColors.scrim,
    pageBuilder: (ctx, _, __) => _ReceiptViewer(bytes: bytes, title: 'صورة التحويل — $name'),
  ));
}

class _ReceiptViewer extends StatelessWidget {
  const _ReceiptViewer({required this.bytes, required this.title});
  final Uint8List bytes;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scrim,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.sm, Sp.sm),
            child: Row(children: [
              Expanded(
                child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.bodyBold(color: AppColors.onBrand)),
              ),
              IconButton(
                key: const ValueKey('renew-viewer-close'),
                tooltip: 'إغلاق',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(LucideIcons.x, color: AppColors.onBrand),
              ),
            ]),
          ),
          Expanded(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
            ),
          ),
        ]),
      ),
    );
  }
}

/// تفاصيل الطلب والإجراءات — داخل النافذة السريعة وصفحة القائمة. [onChanged] بعد كلّ إجراءٍ نجح (الطلب كما صار).
class RenewRequestDetails extends StatefulWidget {
  const RenewRequestDetails({
    super.key,
    required this.request,
    this.onChanged,
    this.onOpenSubscriber,
    this.imageHeight = 260,
    this.readOnlyCompany,
    this.openCompany = false,
  });
  final RenewRequest request;

  /// طلبٌ للشركة المفتوحة (من الجرس أو الإشعار أو لافتته — ٩ نوفمبر، كمحادثة التذكرة): الصورة والقبول والرفض و«تمّ» لها صراحةً
  /// ([CompanyRoute.runOpen]) ولو بقي تحتها قسمٌ موجَّهٌ لشركةٍ أخرى ببادئةٍ تطابق («طلبات التفعيل» أو «بوابة المشترك»). false =
  /// كما هو (القائمة في قسمها: لشركة القسم).
  final bool openCompany;

  /// «كل الشركات» (٨ نوفمبر): طلبٌ من شركةٍ غير المفتوحة للعرض هنا — لا قبول ولا رفض ولا «تمّ» ولا فتح مشتركه (كتاباتها وصفحة
  /// مشتركها لشركتها)؛ سطرٌ يقول ذلك باسمها. null = المفتوحة كما كانت.
  final String? readOnlyCompany;
  final void Function(RenewRequest r, String action)? onChanged;
  final VoidCallback? onOpenSubscriber;
  final double imageHeight;

  @override
  State<RenewRequestDetails> createState() => _RenewRequestDetailsState();
}

class _RenewRequestDetailsState extends State<RenewRequestDetails> {
  late RenewRequest _r = widget.request;
  String? _busy;

  @override
  void didUpdateWidget(covariant RenewRequestDetails old) {
    super.didUpdateWidget(old);
    if (old.request != widget.request) _r = widget.request;
  }

  Future<void> _act(String action, {String? reason}) async {
    setState(() => _busy = action);
    Future<({bool ok, String? message, RenewRequest? request})> act() => RenewRequestsApi.act(_r.id, action, reason: reason);
    final res = await (widget.openCompany ? CompanyRoute.runOpen(act) : act());
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (res.request != null) _r = res.request!;
    });
    unawaited(RenewRequestsState.ensureFresh(force: true));
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!res.ok) {
      messenger?.showSnackBar(SnackBar(content: Text(res.message ?? 'تعذّر الآن — حاول مرّة ثانية'), backgroundColor: AppColors.errorFill));
      return;
    }
    messenger?.showSnackBar(SnackBar(
      content: Text(action == 'accept'
          ? 'قُبل الطلب وأُبلغ المشترك — جدّد اشتراكه الآن'
          : action == 'reject'
              ? 'رُفض الطلب وأُبلغ المشترك بالسبب'
              : 'أُبلغ المشترك: «تم تفعيل اشتراكك بنجاح»'),
      backgroundColor: AppColors.brand,
    ));
    widget.onChanged?.call(_r, action);
  }

  Future<void> _reject() async {
    final reason = await showRenewRejectSheet(context, _r.title);
    if (reason == null || !mounted) return;
    await _act('reject', reason: reason);
  }

  Future<void> _done() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('جدّدت اشتراك ${_r.title}؟', style: AppType.sheetTitle(color: AppColors.textHi)),
        content: Text('يصله «تم تفعيل اشتراكك بنجاح». إن جدّدت من صفحة المشترك فلا داعي — يُبلَّغ وحده خلال دقيقة.',
            style: AppType.body(color: AppColors.textBody)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('إلغاء')),
          FilledButton(
            key: const ValueKey('renew-done-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('نعم، تمّ التفعيل'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _act('done');
  }

  Widget _chip(IconData icon, String text, {Color? fg, Color? bg}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 5),
        decoration: BoxDecoration(color: bg ?? AppColors.surfaceSunken, borderRadius: BorderRadius.circular(R.sm)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: fg ?? AppColors.textMid),
          const SizedBox(width: 5),
          Flexible(child: Text(text, style: AppType.label(color: fg ?? AppColors.textBody).copyWith(fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _note(Color bg, Color fg, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Sp.md),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(R.md)),
        child: Text(text, style: AppType.label(color: fg).copyWith(height: 1.5)),
      );

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final r = _r;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _Avatar(title: r.title, status: r.status),
        const SizedBox(width: Sp.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r.title, style: AppType.cardTitleBold(color: AppColors.textHi)),
            if (r.username != null && r.username != r.title)
              Text(r.username!, textDirection: TextDirection.ltr, style: AppType.muted(color: AppColors.textMid)),
          ]),
        ),
        RenewStatusChip(status: r.status),
      ]),
      const SizedBox(height: Sp.md),
      Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
        _chip(LucideIcons.package, isoJoin([r.packageName ?? 'باقته', renewMonthsLabel(r.months)], ' · '),
            fg: AppColors.brand, bg: AppColors.brandSoftBg),
        _chip(LucideIcons.banknote, r.amount != null ? '${formatIQD(r.amount!)} د.ع' : 'المبلغ غير معروف',
            fg: r.amount != null ? AppColors.success : null, bg: r.amount != null ? AppColors.successSoftBg : null),
        if (renewPayLabel(r.payMethod).isNotEmpty)
          _chip(LucideIcons.smartphone, renewPayLabel(r.payMethod), fg: AppColors.info, bg: AppColors.infoSoftBg),
      ]),
      if (!r.samePackage && (r.currentPackage ?? '').isNotEmpty) ...[
        const SizedBox(height: Sp.xs),
        Text('يريد التغيير من باقته ${iso(r.currentPackage!)}', style: AppType.muted(color: AppColors.textMid)),
      ],
      if ((r.note ?? '').isNotEmpty) ...[
        const SizedBox(height: Sp.sm),
        _note(AppColors.surfaceSunken, AppColors.textBody, r.note!),
      ],
      if (r.createdAt != null) ...[
        const SizedBox(height: Sp.sm),
        Text('${timeAgoAr(r.createdAt)}${r.via == 'web' ? ' · من الموقع' : ''}', style: AppType.micro(color: AppColors.textLow)),
      ],
      if (r.isOpen || r.status == 'done' || r.status == 'rejected') ...[
        const SizedBox(height: Sp.md),
        RenewReceiptImage(key: ValueKey('receipt-${r.id}'), request: r, height: widget.imageHeight, openCompany: widget.openCompany),
      ],
      if (r.status == 'accepted') ...[
        const SizedBox(height: Sp.md),
        _note(AppColors.infoSoftBg, AppColors.info,
            'قبلته${r.decidedBy != null ? ' (${r.decidedBy})' : ''} — جدّد اشتراكه من صفحة المشترك، ويُبلَّغ تلقائيّاً «تم تفعيل اشتراكك بنجاح».'),
      ],
      if (r.status == 'done') ...[
        const SizedBox(height: Sp.md),
        _note(AppColors.successSoftBg, AppColors.success,
            r.doneSource == 'detected' ? 'فُعّل اشتراكه وأُبلغ تلقائيّاً' : 'أُبلغ بالتفعيل${r.decidedBy != null ? ' (${r.decidedBy})' : ''}'),
      ],
      if (r.status == 'rejected') ...[
        const SizedBox(height: Sp.md),
        _note(AppColors.dangerSoftBg, AppColors.dangerOnSoft, 'رُفض${r.rejectReason != null ? ': ${r.rejectReason}' : ''}'),
      ],
      const SizedBox(height: Sp.lg),
      if (widget.readOnlyCompany != null)
        _note(AppColors.warningSoftBg, AppTone.warning.onSoft,
            '«${widget.readOnlyCompany}» للعرض هنا — القبول والرفض و«تمّ التفعيل» من صفحتها (بدّل إليها)'),
      if (r.isPending && widget.readOnlyCompany == null)
        SizedBox(
          height: H.button,
          child: FilledButton.icon(
            key: const ValueKey('renew-accept'),
            onPressed: _busy != null ? null : () => _act('accept'),
            icon: _busy == 'accept'
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onBrand))
                : const Icon(LucideIcons.check, size: 18),
            label: const Text('قبول'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button)),
            ),
          ),
        ),
      if (r.isOpen && widget.readOnlyCompany == null) ...[
        if (r.isPending) const SizedBox(height: Sp.sm),
        Row(children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                key: const ValueKey('renew-done'),
                onPressed: _busy != null ? null : _done,
                icon: const Icon(LucideIcons.circleCheck, size: 17),
                label: const Text('تمّ التفعيل'),
                style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button))),
              ),
            ),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                key: const ValueKey('renew-reject'),
                onPressed: _busy != null ? null : _reject,
                icon: Icon(LucideIcons.circleX, size: 17, color: AppColors.error),
                label: Text('رفض', style: TextStyle(color: AppColors.error)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.dangerSoftBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.button)),
                ),
              ),
            ),
          ),
        ]),
      ],
      if (widget.onOpenSubscriber != null && widget.readOnlyCompany == null) ...[
        const SizedBox(height: Sp.xs),
        TextButton.icon(
          key: const ValueKey('renew-open-subscriber'),
          onPressed: widget.onOpenSubscriber,
          icon: const Icon(LucideIcons.userRound, size: 17),
          label: Text(r.status == 'accepted' ? 'صفحة المشترك — للتجديد' : 'صفحة المشترك'),
        ),
      ],
    ]);
  }
}

/// سبب الرفض: أسبابٌ جاهزة أو نصّ (اختياريّ) ⇒ النصّ ('' = بلا سبب)، أو null إن أُلغي.
Future<String?> showRenewRejectSheet(BuildContext context, String name) {
  return showAppSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RejectSheet(name: name),
  );
}

class _RejectSheet extends StatefulWidget {
  const _RejectSheet({required this.name});
  final String name;

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  String? _preset;
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.circleX,
        title: 'رفض طلب ${widget.name}',
        subtitle: 'يصله السبب في تطبيقه — ويقدر يطلب من جديد',
        tint: AppColors.error,
        tintBg: AppColors.dangerSoftBg,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: [
          for (final r in renewRejectReasons)
            ChoiceChip(
              label: Text(r),
              selected: _preset == r && _text.text.trim().isEmpty,
              onSelected: (_) => setState(() {
                _preset = r;
                _text.clear();
              }),
            ),
        ]),
        const SizedBox(height: Sp.md),
        TextField(
          controller: _text,
          maxLength: 200,
          maxLines: 3,
          minLines: 2,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'أو اكتب السبب (اختياريّ)'),
        ),
      ]),
      footer: SheetFooterBar(
        label: 'رفض الطلب',
        icon: LucideIcons.circleX,
        color: AppColors.errorFill,
        onPressed: () => Navigator.of(context).pop(_text.text.trim().isNotEmpty ? _text.text.trim() : (_preset ?? '')),
      ),
    );
  }
}

/// صفحة المشترك من الطلب (للتجديد) — بيوزره كإشعار المشترك نفسه.
Future<void> openRenewSubscriber(BuildContext context, RenewRequest r) async {
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final sub = await NotificationRouter.findSubscriber(r.username ?? r.subscriberIdx);
  if (sub == null) {
    messenger?.showSnackBar(const SnackBar(content: Text('تعذّر إيجاد المشترك الآن — ابحث عنه من «المشتركين»')));
    return;
  }
  await nav.push(MaterialPageRoute(builder: (_) => SubscriberDetailScreen(sub: sub), fullscreenDialog: true));
}

/// النافذة السريعة (الجرس والإشعار): الطلب كاملاً — الصورة والإجراءات — بلا مغادرة الشاشة. بعد الرفض/«تمّ التفعيل» تُغلق،
/// وبعد «قبول» تبقى (التالي: صفحته للتجديد). [openCompany]: طلب الشركة المفتوحة صراحةً ([RenewRequestDetails.openCompany]).
Future<void> showRenewRequestSheet(BuildContext context, RenewRequest request, {String? readOnlyCompany, bool openCompany = false}) {
  return showAppSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.inbox,
        title: 'طلب تجديد اشتراك',
        subtitle: 'راجع صورة التحويل ثمّ اقبل — يُبلَّغ المشترك فوراً',
        onClose: () => Navigator.of(ctx).pop(),
      ),
      body: RenewRequestDetails(
        request: request,
        imageHeight: 300,
        readOnlyCompany: readOnlyCompany,
        openCompany: openCompany,
        onChanged: (r, action) {
          if (action != 'accept' && Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
        },
        onOpenSubscriber: () {
          final nav = Navigator.of(ctx);
          nav.pop();
          unawaited(openRenewSubscriber(nav.context, request));
        },
      ),
    ),
  );
}

/// نقر إشعار «طلب تجديد اشتراك» (FCM أو الحاسبة أو صندوق الإشعارات) ⇒ الطلب نفسه بنافذته؛ غيره false.
Future<bool> openRenewRequestPush(NavigatorState nav, Map<String, String> data) async {
  if (data['type'] != 'renew_request') return false;
  await RenewRequestsState.ensureFresh(force: true);
  final id = int.tryParse(data['request_id'] ?? '');
  RenewRequest? hit;
  for (final r in RenewRequestsState.gate.value?.items ?? const <RenewRequest>[]) {
    if (r.id == id) {
      hit = r;
      break;
    }
  }
  if (!nav.mounted) return true;
  if (hit != null) {
    // الإشعار لشركته المفتوحة (الموجِّه يبدّل لها أوّلاً — CompanyPush) ⇒ الطلب لها صراحةً
    await showRenewRequestSheet(nav.context, hit, openCompany: true);
  } else {
    // لم يعد مفتوحاً (قُبل وفُعّل/رُفض) أو بلا صلاحيّة ⇒ القائمة تقول حاله — قائمة المفتوحة لا مختارة الشريط
    await MergedMode.focusOpenCompany();
    if (!nav.mounted) return true;
    await nav.push(MaterialPageRoute(builder: (_) => RenewRequestsScreen.mergedPage()));
  }
  return true;
}

/// «الكلّ» من الجرس: قسم الطلبات للشركة المفتوحة التي يعرض الجرس طلباتها ([MergedMode.focusOpenCompany]) لا لمختارة الشريط.
Future<void> _openAllRenew(BuildContext context) async {
  final nav = Navigator.of(context);
  await MergedMode.focusOpenCompany();
  if (!nav.mounted) return;
  await nav.push(MaterialPageRoute(builder: (_) => RenewRequestsScreen.mergedPage()));
}

/// قسم «طلبات التجديد» في صندوق الإشعارات — يظهر حين يوجد طلبٌ مفتوح وحده (المالك: «في حال اكو طلب يظهر بالجرس»).
class RenewInboxSection extends StatelessWidget {
  const RenewInboxSection({super.key, this.max = 5});
  final int max;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RenewSnapshot?>(
      valueListenable: RenewRequestsState.gate,
      builder: (context, snap, _) {
        if (snap == null || !snap.on || snap.items.isEmpty) return const SizedBox.shrink();
        final items = snap.items;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: Sp.sm),
            child: Row(children: [
              Icon(LucideIcons.inbox, size: 18, color: AppColors.warning),
              const SizedBox(width: Sp.sm),
              Text('طلبات التجديد', style: AppType.bodyBold(color: AppColors.textHi)),
              const SizedBox(width: Sp.sm),
              if (snap.pending > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.warningSoftBg, borderRadius: BorderRadius.circular(R.pill)),
                  child: Text('${snap.pending}', style: AppType.microBold(color: AppColors.warningOnSoft)),
                ),
              const Spacer(),
              TextButton(
                key: const ValueKey('renew-inbox-all'),
                onPressed: () => unawaited(_openAllRenew(context)),
                child: const Text('الكلّ'),
              ),
            ]),
          ),
          for (final r in items.take(max)) ...[
            RenewRequestTile(request: r, onTap: () => showRenewRequestSheet(context, r, openCompany: true)),
            const SizedBox(height: Sp.sm),
          ],
          if (items.length > max)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => unawaited(_openAllRenew(context)),
                child: Text('و${items.length - max} غيرها…'),
              ),
            ),
          const SizedBox(height: Sp.md),
        ]);
      },
    );
  }
}
