import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/balance_requests_api.dart';
import '../../api/company_route.dart';
import '../../api/managers_api.dart';
import '../../core/widgets/app_sheet.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/sheet_scaffold.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../desktop/desk_widgets.dart';
import '../managers/sheets/balance_op_sheet.dart';
import 'balance_request_widgets.dart';

/// «طلبات الرصيد» — داخل «المدراء» للمدير الأعلى (المالك ٢٣ نوفمبر). طلبات مدرائه الفرعيّين: «بانتظارك» (ومعها «قيد التأكّد»)،
/// «مقبولة»، «مرفوضة». «قبول وشحن» يفتح نافذة «شحن رصيد» نفسها معبّأةً بالمبلغ وبما اختاره هو («استلمته» كما هي) ومعها رقم
/// الطلب — الخادم يحجزه قبل الساس ويختمه بعده فلا يُشحن مرّتين.
class IncomingBalanceRequestsScreen extends StatefulWidget {
  const IncomingBalanceRequestsScreen({super.key, this.focusId});

  /// من إشعار: الطلب نفسه يُفتح فوق القائمة.
  final int? focusId;

  @override
  State<IncomingBalanceRequestsScreen> createState() => _IncomingBalanceRequestsScreenState();
}

enum _Tab { pending, done, closed }

class _IncomingBalanceRequestsScreenState extends State<IncomingBalanceRequestsScreen> {
  _Tab _tab = _Tab.pending;
  IncomingPage? _page;
  bool _loading = true;
  bool _failed = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load(openFocus: true);
  }

  String get _status => switch (_tab) { _Tab.pending => 'pending', _Tab.done => 'done', _Tab.closed => 'closed' };

  Future<void> _load({bool openFocus = false}) async {
    final gen = ++_gen;
    setState(() {
      _loading = _page == null;
      _failed = false;
    });
    final p = await BalanceRequestsApi.incoming(status: _status, limit: 50);
    if (!mounted || gen != _gen) return;
    setState(() {
      _loading = false;
      _failed = p == null;
      if (p != null) _page = p;
    });
    unawaited(BalanceReqState.refreshCount(force: true));
    if (openFocus && p != null && widget.focusId != null) {
      for (final r in p.items) {
        if (r.id == widget.focusId) {
          unawaited(_details(r));
          break;
        }
      }
    }
  }

  Future<void> _details(BalanceRequest r) async {
    final changed = await showBalanceRequestDetails(context, r);
    if (changed == true && mounted) await _load();
  }

  Future<void> _accept(BalanceRequest r) async {
    if (await acceptBalanceRequest(context, r) && mounted) await _load();
  }

  Future<void> _reject(BalanceRequest r) async {
    if (await rejectBalanceRequest(context, r) && mounted) await _load();
  }

  Future<void> _resolve(BalanceRequest r, bool charged) async {
    if (await resolveBalanceRequest(context, r, charged: charged) && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final p = _page;
    final waiting = p == null ? 0 : p.pending + p.processing;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: deskPageBar(
        context,
        mobile: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppColors.textHi),
          title: Text('طلبات الرصيد', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        ),
        title: 'طلبات الرصيد',
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          key: const ValueKey('balreq-incoming-list'),
          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
          children: [
            Wrap(spacing: 7, runSpacing: 7, children: [
              for (final t in _Tab.values)
                SheetQuickChip(
                  key: ValueKey('balreq-tab-${t.name}'),
                  label: switch (t) {
                    _Tab.pending => waiting > 0 ? 'بانتظارك $waiting' : 'بانتظارك',
                    _Tab.done => 'مقبولة',
                    _Tab.closed => 'مرفوضة',
                  },
                  selected: _tab == t,
                  onTap: () {
                    if (_tab == t) return;
                    setState(() {
                      _tab = t;
                      _page = null;
                    });
                    _load();
                  },
                ),
            ]),
            const SizedBox(height: Sp.md),
            if (_loading)
              const Padding(padding: EdgeInsets.all(Sp.xl), child: Center(child: CircularProgressIndicator()))
            else if (_failed && p == null)
              Padding(
                padding: const EdgeInsets.all(Sp.xl),
                child: Column(children: [
                  Text('تعذّر تحميل الطلبات', style: AppType.body(color: AppColors.textMid)),
                  TextButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                ]),
              )
            else if (p == null || p.items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Sp.xl),
                child: Text(
                  _tab == _Tab.pending ? 'لا طلبات بانتظارك' : 'لا شيء هنا بعد',
                  textAlign: TextAlign.center,
                  style: AppType.body(color: AppColors.textLow),
                ),
              )
            else
              for (final r in p.items) ...[
                _IncomingCard(
                  request: r,
                  onOpen: () => _details(r),
                  onAccept: r.isPending ? () => _accept(r) : null,
                  onReject: r.isPending ? () => _reject(r) : null,
                  onResolve: r.isProcessing ? (charged) => _resolve(r, charged) : null,
                ),
                const SizedBox(height: Sp.sm),
              ],
          ],
        ),
      ),
    );
  }
}

class _IncomingCard extends StatelessWidget {
  const _IncomingCard({required this.request, required this.onOpen, this.onAccept, this.onReject, this.onResolve});
  final BalanceRequest request;
  final VoidCallback onOpen;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final void Function(bool charged)? onResolve;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final sub = r.sub;
    final title = sub?.title ?? '—';
    final initial = title.characters.isEmpty ? '؟' : title.characters.first;
    final ai = r.ai;
    final aiLine = ai != null && ai.status == 'done' && ai.lines.isNotEmpty ? ai.lines.first : null;
    return BalanceReqCard(
      key: ValueKey('balreq-in-${r.id}'),
      onTap: onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: AppTone.info.softBg,
            child: Text(initial, style: AppType.title(color: AppTone.info.fill)),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 2, style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 15)),
              Text(
                [if (sub?.username != null && sub!.username != title) sub.username!, balanceReqWhen(r.createdAt)].join(' · '),
                maxLines: 2,
                style: AppType.muted(),
              ),
            ]),
          ),
          const SizedBox(width: Sp.sm),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(balanceReqIqd(r.amount), style: AppType.amount(color: AppColors.textHi).copyWith(fontSize: 20)),
            ),
            const SizedBox(height: Sp.xs),
            BalanceReqStatusChip(r, forParent: true),
          ]),
        ]),
        const SizedBox(height: Sp.sm),
        Wrap(spacing: Sp.sm, runSpacing: Sp.xs, children: [
          BalanceReqMethodChip(r),
          if (r.hasImage) const ToneChip(label: 'بوصل', icon: LucideIcons.image, dense: true),
        ]),
        if (aiLine != null) ...[
          const SizedBox(height: Sp.sm),
          BalanceReqHint(
            icon: LucideIcons.scanText,
            tone: aiLine.level == 'ok' ? AppTone.success : aiLine.level == 'warn' ? AppTone.warning : AppTone.info,
            text: 'قراءة الوصل: ${aiLine.text}',
          ),
        ] else if (ai != null && ai.status == 'pending') ...[
          const SizedBox(height: Sp.sm),
          const BalanceReqHint(icon: LucideIcons.scanText, text: 'قراءة الوصل… لحظات'),
        ],
        if (r.isPending && r.payMethod == 'cash') ...[
          const SizedBox(height: Sp.sm),
          const BalanceReqHint(icon: LucideIcons.banknote, tone: AppTone.warning, text: 'يسلّمك كاش — اشحن بعد ما تستلم'),
        ],
        if (r.isPending && r.payMethod == 'loan') ...[
          const SizedBox(height: Sp.sm),
          const BalanceReqHint(icon: LucideIcons.info, tone: AppTone.info, text: 'آجل — ينشحن ويصير ديناً عليه'),
        ],
        if (r.isProcessing) ...[
          const SizedBox(height: Sp.sm),
          BalanceReqHint(
            icon: LucideIcons.triangleAlert,
            tone: AppTone.warning,
            text: r.unverified
                ? 'لم يتأكّد الشحن — راجع رصيده بالساس ثمّ اختر'
                : 'قيد الشحن — إن بقي هكذا راجع رصيده ثمّ اختر',
          ),
        ],
        if (r.status == 'done' && r.done != null) ...[
          const SizedBox(height: Sp.sm),
          BalanceReqHint(
            icon: LucideIcons.circleCheck,
            tone: AppTone.success,
            text: [
              'شُحن ${balanceReqIqd(r.done!.amount ?? r.amount)}',
              if (r.done!.viaLabel.isNotEmpty) r.done!.isLoan ? 'آجل' : 'استلمته ${r.done!.viaLabel}',
              if (r.decidedBy != null) 'بيد ${r.decidedBy}',
            ].join(' · '),
          ),
        ],
        if (r.status == 'rejected' && r.rejectReason != null) ...[
          const SizedBox(height: Sp.sm),
          BalanceReqHint(icon: LucideIcons.messageSquareText, tone: AppTone.danger, text: 'سبب الرفض: ${r.rejectReason}'),
        ],
        if (onAccept != null || onReject != null) ...[
          const SizedBox(height: Sp.md),
          Row(children: [
            if (onAccept != null)
              Expanded(
                child: FilledButton.icon(
                  key: ValueKey('balreq-accept-${r.id}'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brand, minimumSize: const Size.fromHeight(46)),
                  onPressed: onAccept,
                  icon: const Icon(LucideIcons.circleCheck, size: 18, color: AppColors.onBrand),
                  label: Text('قبول وشحن', style: AppType.button(color: AppColors.onBrand)),
                ),
              ),
            if (onReject != null) ...[
              const SizedBox(width: Sp.sm),
              OutlinedButton(
                key: ValueKey('balreq-reject-${r.id}'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(96, 46)),
                onPressed: onReject,
                child: Text('رفض', style: AppType.button(color: AppColors.error)),
              ),
            ],
          ]),
        ],
        if (onResolve != null) ...[
          const SizedBox(height: Sp.md),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                key: ValueKey('balreq-resolve-done-${r.id}'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: () => onResolve!(true),
                child: Text('تمّ الشحن', style: AppType.button(color: AppColors.textHi)),
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: OutlinedButton(
                key: ValueKey('balreq-resolve-pending-${r.id}'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                onPressed: () => onResolve!(false),
                child: Text('لم يُشحن', style: AppType.button(color: AppColors.textHi)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}

// ─────────────── الإجراءات (مشتركةٌ بين القائمة والتفاصيل والإشعار) ───────────────

/// «قبول وشحن»: نافذة «شحن رصيد» نفسها معبّأة (المبلغ، الآجل، «استلمته» بما اختاره هو) ومعها رقم الطلب ⇒ true إن شُحن.
Future<bool> acceptBalanceRequest(BuildContext context, BalanceRequest r) async {
  final sasId = int.tryParse(r.sub?.sasId ?? '');
  if (sasId == null) {
    unawaited(showSheetSnack(context, 'تعذّر معرفة المدير الفرعيّ — حدّث القائمة', isError: true));
    return false;
  }
  // حساب المدير الفرعيّ من ساس الصفحة المفتوحة (القسم لها وحدها)
  final m = await CompanyRoute.runOpen(() => ManagersApi.details(sasId));
  if (!context.mounted) return false;
  if (m == null) {
    unawaited(showSheetSnack(context, 'تعذّر قراءة حساب المدير الفرعيّ من الساس — حاول بعد قليل', isError: true));
    return false;
  }
  final done = await showBalanceOpSheet(
    context,
    m,
    preselected: BalanceOpKind.deposit,
    fromRequest: BalanceOpPrefill(
      requestId: r.id,
      amount: r.amount,
      isLoan: r.payMethod == 'loan',
      via: r.suggestedVia,
      label: r.methodLabel,
    ),
  );
  unawaited(BalanceReqState.refreshCount(force: true));
  return done == true;
}

/// «رفض» بسببٍ اختياريّ يراه الفرعيّ ⇒ true إن رُفض.
Future<bool> rejectBalanceRequest(BuildContext context, BalanceRequest r) async {
  final reason = await showAppSheet<String>(
    context: context,
    barrierColor: AppColors.scrim,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _RejectSheet(request: r),
  );
  if (reason == null || !context.mounted) return false;
  final res = await BalanceRequestsApi.reject(r.id, reason);
  if (!context.mounted) return false;
  unawaited(showSheetSnack(context, res.ok ? 'رُفض الطلب — وصله إشعار' : (res.message ?? 'تعذّر الرفض'), isError: !res.ok));
  unawaited(BalanceReqState.refreshCount(force: true));
  return res.ok;
}

/// ورقة الرفض تملك حقلها (يُتخلّص منه مع الورقة بعد انتهاء حركتها) ⇒ السبب (قد يكون فارغاً) أو null إن أُغلقت.
class _RejectSheet extends StatefulWidget {
  const _RejectSheet({required this.request});
  final BalanceRequest request;

  @override
  State<_RejectSheet> createState() => _RejectSheetState();
}

class _RejectSheetState extends State<_RejectSheet> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.circleX,
        title: 'رفض الطلب',
        subtitle: '${r.sub?.title ?? ''} · ${balanceReqIqd(r.amount)}',
        tint: AppTone.danger.fill,
        tintBg: AppTone.danger.softBg,
        onClose: () => Navigator.of(context).pop(),
      ),
      body: SheetSection(
        label: 'سبب الرفض',
        hint: 'يراه هو',
        child: SheetNoteField(
          key: const ValueKey('balreq-reject-reason'),
          controller: _ctrl,
          hint: 'مثلاً: المبلغ بالصورة غير المطلوب — أرسل الوصل الصحيح',
          maxLength: 200,
          minLines: 2,
        ),
      ),
      footer: SheetFooterBar(
        key: const ValueKey('balreq-reject-confirm'),
        label: 'رفض الطلب',
        icon: LucideIcons.circleX,
        color: AppColors.error,
        onPressed: () => Navigator.of(context).pop(_ctrl.text.trim()),
      ),
    );
  }
}

/// حسم «قيد التأكّد»: [charged] تمّ الشحن (راجعت رصيده) / لم يُشحن (يعود للانتظار) ⇒ true إن حُسم.
Future<bool> resolveBalanceRequest(BuildContext context, BalanceRequest r, {required bool charged}) async {
  final yes = await showConfirmSheet(
    context,
    title: charged ? 'تمّ شحنه فعلاً؟' : 'لم يُشحن؟',
    message: charged
        ? 'راجعت رصيده بالساس ووصل ${balanceReqIqd(r.attempt?.amount ?? r.amount)} — يُختم الطلب «شُحن» ويصله إشعار'
        : 'راجعت رصيده بالساس ولم يصل شيء — يعود الطلب «بانتظارك» وتشحنه من جديد',
    confirmLabel: charged ? 'نعم، تمّ الشحن' : 'نعم، لم يُشحن',
    icon: charged ? LucideIcons.circleCheck : LucideIcons.rotateCcw,
  );
  if (yes != true || !context.mounted) return false;
  final res = await BalanceRequestsApi.resolve(r.id, charged: charged);
  if (!context.mounted) return false;
  if (!res.ok) unawaited(showSheetSnack(context, res.message ?? 'تعذّر الحفظ', isError: true));
  unawaited(BalanceReqState.refreshCount(force: true));
  return res.ok;
}

/// تفاصيل الطلب: صورة الحوالة و«قراءة الوصل» والأسطر ⇒ true إن تغيّر (قُبل/رُفض/حُسم).
Future<bool?> showBalanceRequestDetails(BuildContext context, BalanceRequest r) => showAppSheet<bool>(
      context: context,
      barrierColor: AppColors.scrim,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _DetailsSheet(request: r),
    );

class _DetailsSheet extends StatefulWidget {
  const _DetailsSheet({required this.request});
  final BalanceRequest request;

  @override
  State<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<_DetailsSheet> {
  Future<dynamic>? _img;

  @override
  void initState() {
    super.initState();
    if (widget.request.hasImage) _img = BalanceRequestsApi.image(widget.request.id);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final ai = r.ai;
    return DesignSheet(
      header: SheetHeaderBar(
        icon: LucideIcons.handCoins,
        title: 'طلب رصيد — ${r.sub?.title ?? ''}',
        subtitle: 'أرسله ${balanceReqWhen(r.createdAt)}${r.hasImage ? ' · بوصل' : ''}',
        onClose: () => Navigator.of(context).pop(),
      ),
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_img != null) ...[
          FutureBuilder<dynamic>(
            future: _img,
            builder: (context, snap) {
              final bytes = snap.data;
              return Container(
                key: const ValueKey('balreq-detail-image'),
                height: 320,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(R.card),
                  border: Border.all(color: AppColors.border),
                ),
                child: snap.connectionState != ConnectionState.done
                    ? const Center(child: CircularProgressIndicator())
                    : bytes == null
                        ? Center(child: Text('حُذفت صورة الحوالة (٧ أيّام) أو تعذّر تحميلها', style: AppType.body(color: AppColors.textLow)))
                        : InteractiveViewer(
                            child: Image.memory(
                              bytes,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Center(
                                child: Text('تعذّر عرض صورة الحوالة', style: AppType.body(color: AppColors.textLow)),
                              ),
                            ),
                          ),
              );
            },
          ),
          const SizedBox(height: Sp.md),
        ],
        if (ai != null && ai.status == 'done' && ai.lines.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(Sp.md),
            decoration: BoxDecoration(
              color: (ai.level == 'ok' ? AppTone.success : ai.level == 'warn' ? AppTone.warning : AppTone.info).softBg,
              borderRadius: BorderRadius.circular(R.card / 2),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('قراءة الوصل', style: AppType.label(color: AppColors.textMid)),
              const SizedBox(height: Sp.xs),
              for (final l in ai.lines)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(l.text, style: AppType.body(color: AppColors.textHi)),
                ),
            ]),
          ),
          const SizedBox(height: Sp.md),
        ],
        SheetRowsGroup(rows: [
          SheetRowData(label: 'المبلغ المطلوب', value: balanceReqIqd(r.amount), strong: true),
          SheetRowData(label: 'كيف دفع', value: r.methodLabel),
          if (r.note != null) SheetRowData(label: 'ملاحظته', value: r.note!),
          SheetRowData(label: 'الحال', value: balanceReqStatus(r, forParent: true).label),
          if (r.sub?.username != null) SheetRowData(label: 'اليوزر', value: r.sub!.username!),
        ]),
      ]),
      footer: r.isPending
          ? SheetFooterBar(
              key: const ValueKey('balreq-detail-accept'),
              label: 'قبول وشحن — ${balanceReqIqd(r.amount)}',
              icon: LucideIcons.circleCheck,
              onPressed: () async {
                if (await acceptBalanceRequest(context, r) && context.mounted) Navigator.of(context).pop(true);
              },
              leading: SheetFooterIconButton(
                key: const ValueKey('balreq-detail-reject'),
                icon: LucideIcons.x,
                color: AppColors.error,
                onTap: () async {
                  if (await rejectBalanceRequest(context, r) && context.mounted) Navigator.of(context).pop(true);
                },
              ),
            )
          : null,
    );
  }
}

/// نقر إشعار «طلب رصيد» (الأعلى) أو «طلبك شُحن/رُفض» (الفرعيّ) ⇒ القسم نفسه؛ غيره false.
Future<bool> openBalanceRequestPush(NavigatorState nav, Map<String, String> data, {required Widget Function() subScreen}) async {
  final type = data['type'];
  if (type == 'balance_request') {
    unawaited(BalanceReqState.refreshCount(force: true));
    await nav.push(MaterialPageRoute(
        builder: (_) => IncomingBalanceRequestsScreen(focusId: int.tryParse(data['request_id'] ?? ''))));
    return true;
  }
  if (type == 'balance_request_update') {
    unawaited(BalanceReqState.refreshMe(force: true));
    await nav.push(MaterialPageRoute(builder: (_) => subScreen()));
    return true;
  }
  return false;
}
