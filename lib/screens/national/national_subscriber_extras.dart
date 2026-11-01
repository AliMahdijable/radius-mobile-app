import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/national_portal_api.dart';
import '../../api/national_sheet_api.dart';
import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/widgets/design_sheet.dart';
import '../../core/widgets/permission_locked.dart';
import '../../models/subscriber.dart';
import '../../services/permissions_service.dart';
import '../../services/provider_service.dart';
import '../../services/subscriber_refresh_signal.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../subscribers/sheets/consumption_sheet.dart' show fmtBytes;
import 'national_labels.dart';
import 'national_task_sheet.dart';
import 'national_tickets_screen.dart' show showNationalTicketSheet;
import 'national_widgets.dart';

/// أقسام البوّابة في صفحة مشترك الوطنيّ (١ نوفمبر — المالك: «اقسام البوابة البقية… تكملها»): محفظته، و«سجل الأخطاء» لاشتراكه،
/// وتذاكره، ومهامّه، وجلساته السابقة — كما في صفحة المشترك بالبوّابة. كرتٌ واحد مطويّ: سطرٌ بخمس حبّات، والنقر يفتح القسم تحتها
/// (واحداً في المرّة) ويجلبه حينها لا قبل، وما جُلب يبقى حتى السحب للتحديث. قليلٌ في المرّة (١٠) و«المزيد» للباقي.
///
/// يظهر حين يقول الخادم إنّ الأقسام التجريبيّة مفتوحةٌ لهذا الحساب (`lookups.beta`)، خارج «كل الشركات» (عقد الخادم §3) — أو حين
/// يرفض الخادم سؤال موظّفٍ عنها (403: لا مفتاح له يقرأ به) فتبقى بمكانها مقفلةً. الموظّف بلا مفتاح القسم يراه مقفلاً بمكانه
/// (المحفظة = «التقارير الماليّة» أو «سجلّ حركات المشترك»، والباقي = «عرض المشتركين») — وصاحب الحساب لا تقفله هذه المفاتيح أبداً —
/// وما لا يملكه مستخدم البوّابة نفسه يُقفل بسببه (`portal_locks` أو ردٌّ `locked`) — لا خطأ ولا قائمة فارغة.
enum NationalSheetSection { wallet, errors, tickets, tasks, sessions }

extension on NationalSheetSection {
  String get label => switch (this) {
        NationalSheetSection.wallet => 'المحفظة',
        NationalSheetSection.errors => 'سجل الأخطاء',
        NationalSheetSection.tickets => 'التذاكر',
        NationalSheetSection.tasks => 'المهامّ',
        NationalSheetSection.sessions => 'الجلسات',
      };

  IconData get icon => switch (this) {
        NationalSheetSection.wallet => LucideIcons.wallet,
        NationalSheetSection.errors => LucideIcons.circleAlert,
        NationalSheetSection.tickets => LucideIcons.headset,
        NationalSheetSection.tasks => LucideIcons.listChecks,
        NationalSheetSection.sessions => LucideIcons.history,
      };

  /// مفاتيح الموظّف (أيٌّ منها — من كتالوجه القائم، كما يفحصها الخادم §9؛ لا مفتاح جديد).
  List<String> get perms =>
      this == NationalSheetSection.wallet ? const ['reports.financial', 'subscribers.view_activity'] : const ['subscribers.view'];

  /// مفتاح القسم في `portal_locks` (سبب القفل الجاهز من الخادم §2). المحفظة: `sub_wallet` = حركاتها (القسم كلّه)؛ أمّا رصيدها وحده
  /// (`sub_balance`) فلا يقفل القسم — الردّ نفسه يقول `balance_locked` والحركات تظهر.
  String get lockKey => switch (this) {
        NationalSheetSection.wallet => 'sub_wallet',
        NationalSheetSection.errors => 'sub_errors',
        NationalSheetSection.tickets => 'sub_tickets',
        NationalSheetSection.tasks => 'sub_tasks',
        NationalSheetSection.sessions => 'sub_sessions',
      };

  String get empty => switch (this) {
        NationalSheetSection.wallet => 'لا حركات في محفظة المشترك',
        NationalSheetSection.errors => 'لا توجد أخطاء — الجلسة لا تحتوي على أخطاء',
        NationalSheetSection.tickets => 'لا تذاكر لهذا المشترك',
        NationalSheetSection.tasks => 'لا مهامّ لهذا المشترك',
        NationalSheetSection.sessions => 'لا جلسات سابقة',
      };

  String get unit => switch (this) {
        NationalSheetSection.wallet => 'حركة',
        NationalSheetSection.errors => 'خطأ',
        NationalSheetSection.tickets => 'تذكرة',
        NationalSheetSection.tasks => 'مهمّة',
        NationalSheetSection.sessions => 'جلسة',
      };
}

class NationalSubscriberExtras extends StatefulWidget {
  const NationalSubscriberExtras({super.key, required this.sub});
  final Subscriber sub;

  /// مشتركٌ للمشروع الوطنيّ برقمه، خارج «كل الشركات» (الأقسام تقرأ بجلسة الحساب المفتوح وحده).
  static bool shownFor(Subscriber sub) =>
      ProviderService.isKit && ProviderService.parentIsZone && sub.companyKey == null && (sub.idx ?? '').isNotEmpty;

  @override
  State<NationalSubscriberExtras> createState() => _NationalSubscriberExtrasState();
}

class _NationalSubscriberExtrasState extends State<NationalSubscriberExtras> {
  NationalBeta? _beta;
  NationalSheetSection? _open;

  final _wallet = NationalPaged<NationalMoneyRow>();
  final _errors = NationalPaged<NationalErrorRow>();
  final _tickets = NationalPaged<NationalTicket>();
  final _tasks = NationalPaged<NationalTaskRef>();
  final _sessions = NationalPaged<NationalSessionRow>();

  /// قسمٌ ردّ الخادم عليه بقفل («لا صلاحيّة في البوّابة»، أو أُطفئ التجريبيّ) — لا خطأٌ عابر.
  final Map<NationalSheetSection, NationalLock> _locks = {};

  String get _idx => widget.sub.idx ?? '';

  NationalPaged<Object?> _paged(NationalSheetSection s) => switch (s) {
        NationalSheetSection.wallet => _wallet,
        NationalSheetSection.errors => _errors,
        NationalSheetSection.tickets => _tickets,
        NationalSheetSection.tasks => _tasks,
        NationalSheetSection.sessions => _sessions,
      };

  @override
  void initState() {
    super.initState();
    unawaited(_ask());
    SubscriberRefreshSignal.tick.addListener(_refresh);
  }

  @override
  void didUpdateWidget(covariant NationalSubscriberExtras old) {
    super.didUpdateWidget(old);
    // مشتركٌ آخر في المكان نفسه (الحاسبة: لوحة التفاصيل): لا يبقى شيءٌ من سابقه
    if (old.sub.idx != widget.sub.idx) {
      _resetAll();
      _open = null;
    }
  }

  @override
  void dispose() {
    SubscriberRefreshSignal.tick.removeListener(_refresh);
    for (final s in NationalSheetSection.values) {
      _paged(s).dispose();
    }
    super.dispose();
  }

  Future<void> _ask() async {
    final b = await NationalSheetApi.beta();
    if (!mounted) return;
    setState(() => _beta = b);
  }

  void _resetAll() {
    for (final s in NationalSheetSection.values) {
      _paged(s).reset();
    }
    _locks.clear();
  }

  /// السحب للتحديث: ما جُلب يُنسى، والقسم المفتوح يُجلب من جديد.
  void _refresh() {
    if (!mounted) return;
    _resetAll();
    final s = _open;
    setState(() {});
    if (s != null && _canOpen(s)) _next(s);
  }

  /// الموظّف وحده يُقفل بمفتاح القسم — صاحب الحساب لا (قدراته من الخادم تخصّ الساس لا أقسام البوّابة؛ العقد §9).
  bool _employeeLocked(NationalSheetSection s) => Perms.isEmployee && !Perms.hasAny(s.perms);

  /// قفل البوّابة: ردٌّ مقفل وصل، أو سببٌ جاهز في `portal_locks` (فلا نداء أصلاً).
  NationalLock? _lockOf(NationalSheetSection s) {
    final got = _locks[s];
    if (got != null) return got;
    final why = _beta?.lockOf(s.lockKey);
    return why == null ? null : NationalLock(message: why);
  }

  bool _canOpen(NationalSheetSection s) => !_employeeLocked(s) && _lockOf(s) == null;

  void _tap(NationalSheetSection s) {
    if (_employeeLocked(s)) {
      showNoPermission(context);
      return;
    }
    if (_open == s) {
      setState(() => _open = null);
      return;
    }
    setState(() => _open = s);
    if (_canOpen(s) && !_paged(s).started) _next(s);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<NationalResult<NationalPage<T>>> Function(int page) _fetch<T>(
    NationalSheetSection s,
    Future<NationalSheetResult<NationalPage<T>>> Function(String idx, {int page}) api,
  ) =>
      (page) async {
        final r = await api(_idx, page: page);
        if (r.ok) return NationalResult.ok(r.data);
        if (r.locked) {
          _locks[s] = r.lock!;
          return NationalResult.fail(r.lock!.message);
        }
        return NationalResult.fail(r.error, relogin: r.relogin);
      };

  void _next(NationalSheetSection s) {
    bool alive() => mounted;
    switch (s) {
      case NationalSheetSection.wallet:
        _wallet.next(_fetch(s, NationalSheetApi.wallet), onChange: _changed, alive: alive);
      case NationalSheetSection.errors:
        _errors.next(_fetch(s, NationalSheetApi.errors), onChange: _changed, alive: alive);
      case NationalSheetSection.tickets:
        _tickets.next(_fetch(s, NationalSheetApi.tickets), onChange: _changed, alive: alive);
      case NationalSheetSection.tasks:
        _tasks.next(_fetch(s, NationalSheetApi.tasks), onChange: _changed, alive: alive);
      case NationalSheetSection.sessions:
        _sessions.next(_fetch(s, NationalSheetApi.sessions), onChange: _changed, alive: alive);
    }
  }

  void _retry(NationalSheetSection s) {
    _paged(s).reset();
    _locks.remove(s);
    setState(() {});
    _next(s);
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final b = _beta;
    // مفتوحةٌ للحساب، أو موظّفٌ رفض الخادم سؤاله (refused) ⇒ بمكانها مقفلةً بمفاتيحه لا مخفيّة
    if (b == null || !b.shown) return const SizedBox.shrink();
    final open = _open;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.card), side: BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(LucideIcons.landmark, size: 18, color: AppColors.brandAccent),
                      const SizedBox(width: Sp.sm),
                      Expanded(
                        child: Text('من بوّابة الوطني', style: AppType.cardTitle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: Sp.sm),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in NationalSheetSection.values)
                        if (permShown(s.perms))
                          _SectionChip(
                            label: s.label,
                            icon: s.icon,
                            selected: open == s,
                            locked: _employeeLocked(s) || _lockOf(s) != null,
                            onTap: () => _tap(s),
                          ),
                    ],
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.topCenter,
              child: open == null
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Divider(height: 1, color: AppColors.divider),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.sm, Sp.lg, Sp.md),
                          child: _section(open),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(NationalSheetSection s) {
    final lock = _lockOf(s);
    if (lock != null) return NationalPortalLockBox(title: lock.title, text: lock.message);
    final p = _paged(s);
    if (p.rows.isEmpty) {
      if (p.error != null) return _ErrorRow(text: p.error!, onRetry: () => _retry(s));
      if (p.pending) return const _BusyRow(text: 'جارٍ الجلب من بوّابة المشروع الوطني…');
      if (p.loading || p.page == 0) return const _BusyRow(text: 'جارٍ التحميل…');
      final empty = Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.md),
        child: Text(s.empty, textAlign: TextAlign.center, style: AppType.muted()),
      );
      if (s != NationalSheetSection.wallet) return empty;
      // رصيد المحفظة مستقلٌّ عن حركاتها (البوّابة تعرض «رصيد المحفظة» وحده، والحركات بنافذتها الافتراضيّة بلا تاريخ): زبونٌ بلا حركاتٍ
      // فيها رصيده يُقال — أو «لا صلاحيّة» أو «—» — ثمّ «لا حركات» (مراجعة ١ نوفمبر: كان يُخفى الرصيد مع القائمة الفارغة).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_balance(), Divider(height: 1, color: AppColors.divider), empty],
      );
    }
    final rows = <Widget>[
      if (s == NationalSheetSection.wallet) _balance(),
      for (final r in p.rows) _row(s, r),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: AppColors.divider),
          rows[i],
        ],
        // فشل الصفحة التالية يُقال بـ«إعادة» ولو بقيت صفحاتٌ أخرى (مراجعة ١ نوفمبر: كان «المزيد» يعلق بلا رسالة)
        if (p.error != null)
          _ErrorRow(text: p.error!, onRetry: () => _next(s))
        else if (p.hasMore)
          // والصفحة التالية «جارٍ» (pending، تُسأل وحدها بعد ٤ث): دوّارةٌ لا نداءٌ ثانٍ لها
          _MoreRow(loading: p.loading || p.pending, shown: p.rows.length, total: p.total, unit: s.unit, onTap: () => _next(s)),
      ],
    );
  }

  Widget _row(NationalSheetSection s, Object? r) => switch (s) {
        NationalSheetSection.wallet => _WalletLine(r: r as NationalMoneyRow),
        NationalSheetSection.errors => _ErrorLine(r: r as NationalErrorRow, username: widget.sub.username),
        NationalSheetSection.tickets => _TicketLine(
            t: r as NationalTicket,
            onTap: r.id == null ? null : () => showNationalTicketSheet(context, r),
          ),
        NationalSheetSection.tasks => _TaskLine(
            t: r as NationalTaskRef,
            onTap: r.id == null
                ? null
                : () => showNationalTaskSheet(context, NationalTask(id: r.id, title: r.title, status: '', customer: _customer)),
          ),
        NationalSheetSection.sessions => _SessionLine(r: r as NationalSessionRow),
      };

  /// اسم المشترك للورقة التي تُفتح من صفّه (المهمّة لا تحمل غير رقمها وعنوانها).
  NationalRef get _customer => NationalRef(null, widget.sub.fullName);

  /// رصيد محفظة المشترك كما تعرضه البوّابة («رصيد المحفظة»): صفرٌ معروف صفر، والمجهول «—»، والمقفل وحده «لا صلاحيّة».
  Widget _balance() {
    final b = NationalCustomerBalance.fromRaw(_wallet.raw);
    final v = b.balance;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Row(
        children: [
          Icon(b.locked ? LucideIcons.lock : LucideIcons.wallet, size: 16, color: b.locked ? AppColors.textLow : AppColors.success),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text('رصيد محفظة المشترك', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textLabel)),
          ),
          Text(
            // formatIQD يُسقط الإشارة — رصيدٌ سالب يُقال سالباً لا موجباً
            b.locked ? 'لا صلاحيّة' : (v == null ? '—' : '${v < 0 ? '−' : ''}${formatIQD(v)}'),
            textDirection: b.locked ? null : TextDirection.ltr,
            style: b.locked ? AppType.muted() : AppType.amount(color: AppColors.textHi).copyWith(fontSize: 15),
          ),
        ],
      ),
    );
  }
}

/* ───────────────────────────── أجزاء ───────────────────────────── */

/// حبّة قسم: مختارة (بلون العلامة = مفتوحٌ تحتها، والنقر ثانيةً يطويه)، أو مقفلة (قفلٌ بدل الأيقونة، خافتة) — بمكانها لا تختفي.
class _SectionChip extends StatelessWidget {
  const _SectionChip({required this.label, required this.icon, required this.selected, required this.locked, required this.onTap});
  final String label;
  final IconData icon;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final fg = locked ? LockedStyle.title : (selected ? AppColors.brand : AppColors.textHi);
    return Semantics(
      button: true,
      selected: selected,
      label: locked ? '$label — مقفل' : label,
      excludeSemantics: true,
      child: Material(
        color: selected ? AppColors.brandSoftBg : (locked ? LockedStyle.box : AppColors.surface),
        shape: StadiumBorder(side: BorderSide(color: selected ? AppColors.brandSoftBorder : AppColors.border)),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(locked ? LucideIcons.lock : icon, size: 14, color: locked ? LockedStyle.glyph : fg),
                const SizedBox(width: 5),
                Text(label, style: AppType.label(color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BusyRow extends StatelessWidget {
  const _BusyRow({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: Sp.sm),
          Flexible(child: Text(text, style: AppType.muted())),
        ],
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 16, color: AppColors.error),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppType.body(color: AppColors.textMid))),
          TextButton.icon(onPressed: onRetry, icon: const Icon(LucideIcons.refreshCw, size: 15), label: const Text('إعادة')),
        ],
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow({required this.loading, required this.shown, required this.total, required this.unit, required this.onTap});
  final bool loading;
  final int shown;
  final int? total;
  final String unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return Padding(
      padding: const EdgeInsets.only(top: Sp.xs),
      child: Row(
        children: [
          if (total != null) Expanded(child: Text('$shown من $total $unit', style: AppType.micro(color: AppColors.textMid))) else const Spacer(),
          TextButton(
            onPressed: loading ? null : onTap,
            child: loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('المزيد'),
          ),
        ],
      ),
    );
  }
}

String _day(String? v) => v == null || v.length < 10 ? (v ?? '') : v.substring(0, 10);

class _WalletLine extends StatelessWidget {
  const _WalletLine({required this.r});
  final NationalMoneyRow r;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final amt = r.amount;
    final sign = r.isOut ? '−' : (r.isIn ? '+' : '');
    final color = r.isOut ? AppColors.error : (r.isIn ? AppColors.success : AppColors.textHi);
    final method = nationalPayMethod(r.payMethod.isNotEmpty ? r.payMethod : r.method);
    // «المنفّذ»: أنت، أو اسم عضو «فريقي» (by_name — ولو كان by null)، وإلّا «مستخدمٌ آخر لحسابك» — كـ«محفظتي»
    final maker = nationalMaker(r.by, r.byName);
    final meta = [
      iso(nationalTime(r.at)),
      if ((r.planName ?? '').isNotEmpty) iso(r.planName!),
      if ((r.ends ?? '').isNotEmpty) 'ينتهي ${iso(_day(r.ends))}',
      if (method != '—') method,
      if (maker != null) maker,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nationalTxType(r.type), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textHi)),
                const SizedBox(height: 2),
                Text(meta, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppType.micro(color: AppColors.textMid)),
              ],
            ),
          ),
          const SizedBox(width: Sp.sm),
          Text(
            amt == null ? '—' : '$sign${formatIQD(amt.abs())}',
            textDirection: TextDirection.ltr,
            style: AppType.amount(color: color).copyWith(fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.r, required this.username});
  final NationalErrorRow r;

  /// يوزر المشترك — يُذكر يوزر الخطأ حين يختلف عنه وحده (جهازٌ آخر حاول بالاشتراك).
  final String username;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final other = r.username != null && r.username!.toLowerCase() != username.toLowerCase() ? r.username : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(LucideIcons.circleAlert, size: 15, color: AppColors.warning),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.message.isEmpty ? '—' : iso(r.message),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body(color: AppColors.textBody),
                ),
                const SizedBox(height: 2),
                Text(
                  [iso(nationalTime(r.at)), if (other != null) 'اليوزر ${iso(other)}'].join(' · '),
                  style: AppType.micro(color: AppColors.textMid),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketLine extends StatelessWidget {
  const _TicketLine({required this.t, this.onTap});
  final NationalTicket t;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    final st = nationalTicketStatus(t.status);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title.isEmpty ? '—' : t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textHi)),
                  const SizedBox(height: 2),
                  Text(
                    [if (t.displayId.isNotEmpty) iso(t.displayId), iso(nationalTime(t.createdAt))].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.micro(color: AppColors.textMid),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Sp.sm),
            ToneChip(label: st.label, tone: st.tone, dense: true),
            if (onTap != null) ...[
              const SizedBox(width: Sp.xs),
              Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
            ],
          ],
        ),
      ),
    );
  }
}

class _TaskLine extends StatelessWidget {
  const _TaskLine({required this.t, this.onTap});
  final NationalTaskRef t;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.sm + 2),
        child: Row(
          children: [
            Icon(LucideIcons.clipboardList, size: 16, color: AppColors.textMid),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Text(nationalTaskTitle(t.title), maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label(color: AppColors.textHi)),
            ),
            if (onTap != null) ...[
              const SizedBox(width: Sp.xs),
              Text('التفاصيل', style: AppType.micro(color: AppColors.textMid)),
              Icon(LucideIcons.chevronLeft, size: 16, color: AppColors.textLow),
            ],
          ],
        ),
      ),
    );
  }
}

/// مدّة الجلسة «س:د» (أو «د دقيقة» لما دون الساعة).
String nationalDuration(int? seconds) {
  if (seconds == null || seconds < 0) return '—';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h == 0) return m == 0 ? 'أقلّ من دقيقة' : arMinutes(m);
  return '$h:${m.toString().padLeft(2, '0')} ساعة';
}

class _SessionLine extends StatelessWidget {
  const _SessionLine({required this.r});
  final NationalSessionRow r;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep
    String bytes(int? b) => b == null ? '—' : fmtBytes(b);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Sp.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        nationalTime(r.startedAt),
                        textDirection: TextDirection.ltr,
                        maxLines: 1,
                        style: AppType.label(color: AppColors.textHi),
                      ),
                    ),
                    if (r.live) ...[
                      const SizedBox(width: Sp.sm),
                      const ToneChip(label: 'متصل الآن', tone: AppTone.success, dense: true),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  ['المدّة ${nationalDuration(r.seconds)}', if (r.ip != null) iso(r.ip!)].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.micro(color: AppColors.textMid),
                ),
              ],
            ),
          ),
          const SizedBox(width: Sp.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(iso('↓ ${bytes(r.down)}'), style: AppType.micro(color: AppColors.textHi)),
              Text(iso('↑ ${bytes(r.up)}'), style: AppType.micro(color: AppColors.textMid)),
            ],
          ),
        ],
      ),
    );
  }
}
