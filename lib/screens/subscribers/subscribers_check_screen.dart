import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
import '../../core/util/server_time.dart';
import '../../models/merged_company.dart';
import '../../models/subscriber.dart';
import '../../services/connection_alerts.dart';
import '../../services/merged_mode.dart';
import '../../services/subscribers_check.dart';
import '../../services/vpn_now.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/company_tag.dart';
import 'subscriber_detail_screen.dart';
import 'widgets/device_chip_micro.dart';

/// «الفحص العامّ» للمشتركين (٨ نوفمبر — المالك: «أ» و«تره فحص المشتركين ثكيل كلش… مو مثل مايعرضون الاشارات وسرعته بكارت
/// المشتركين»، ثمّ مع صورة الصفحة: «يحتاجلها ترتيب اكثر واظهار معلومات ال ccq كذلك وتصميم افضل»): تقريرٌ فوريّ من قراءات
/// الكارتات نفسها، والموجة تعيد القديم وحده في الخلفيّة (التقرير يتحدّث معها)؛ عبر الـVPN من فحص الخادم الأخير (يُعاد إن قدُم).
///
/// الترتيب: بطاقة ملخّص بثلاثة أقسام تُفتح بالضغط — «بمشكلة» (مجموعاتٍ بنوعها، الأسوأ أوّلاً) · «سليم» (الأقرب للحدّ أوّلاً) ·
/// «لم يُقرأ» (ولماذا). وكلّ مشتركٍ بمقاييسه كلّها كالكارت: الإشارة وCCQ والكيبل (أو ضوء الفايبر وحرارته) — المشكلة حمراء،
/// والقريب من الحدّ برتقاليّ. المشكلة بحدود «تنبيه المشترك» ([SubscribersCheck]). الضغط على مشترك يفتح نافذته.
class SubscribersCheckScreen extends StatefulWidget {
  const SubscribersCheckScreen({
    super.key,
    required this.subscribers,
    required this.viaVpn,
    this.probing,
    this.onRefreshStale,
    this.onForceAll,
    this.big = false,
    this.companies,
    this.openCompany,
    this.vpnAllowed = true,
  });

  /// «كل الشركات» (٨ نوفمبر — المالك: «مايعرض مثل الاجهزه مشتركين كل شركه ونتيجه فحوصاتهم… ايرث لنك رابطلها vpn والسوبرنت
  /// تشتغل لوكل»): شركات القائمة بترتيبها — كلٌّ بطريقها كـ«الفحص الشامل»: المفتوحة [openCompany] من شبكتك (ما لم يكن [viaVpn])،
  /// وغيرها بفحص الخادم عبر VPN شركتها، وبلا طريقٍ تُسمّى. null خارج الوضع.
  final List<MergedCompany>? companies;
  final String? openCompany;

  /// الفحص عبر VPN مفعّلٌ للموظّف (صاحب الحساب دائماً).
  final bool vpnAllowed;

  /// القائمة الحيّة (المحمّلة) من شاشة المشتركين.
  final List<Subscriber> Function() subscribers;
  final bool viaVpn;

  /// موجة الهاتف جارية (على الشبكة).
  final ValueListenable<bool>? probing;

  /// على الشبكة: الموجة للقديم وحده (خفيفة) — تُنادى عند الفتح وبـ«تحديث».
  final VoidCallback? onRefreshStale;

  /// على الشبكة: إعادة فحص الكلّ (ثقيلة، بطلبٍ صريح).
  final VoidCallback? onForceAll;

  /// حسابٌ كبير: الصفوف المحمّلة وحدها.
  final bool big;

  @override
  State<SubscribersCheckScreen> createState() => _SubscribersCheckScreenState();
}

enum _Seg { problems, healthy, missing }

/// درجة المقياس: سليم · قريبٌ من الحدّ · مشكلة.
enum _Lvl { ok, near, bad }

/// رأس مجموعةٍ في قسم «بمشكلة».
class _Group {
  const _Group(this.kind, this.count);
  final ConnectionProblemKind kind;
  final int count;
}

class _SubscribersCheckScreenState extends State<SubscribersCheckScreen> {
  _Seg _seg = _Seg.problems;
  ConnectionProblemKind? _kind;

  /// «كل الشركات»: شركةٌ مختارة من بطاقة «الشركات» ⇒ مشتركوها وحدهم (والضغط ثانيةً يعيد الكلّ).
  String? _company;

  bool get _merged => (widget.companies ?? const []).isNotEmpty;

  /// الشركة المفتوحة تُقرأ من شبكتك (الموجة) ما لم يكن الفحص عبر الـVPN.
  bool _isLocal(String key) => !widget.viaVpn && key == widget.openCompany;

  /// شركاتٌ تُفحص عبر VPN شركتها (بطلبٍ موجَّه بمفتاحها) — وآخرها المفتوحة نفسها تكملةً لموجة الهاتف: مشتركو الفايبر (ONU بلا
  /// عنوانٍ يصله الموبايل) ضوؤهم من الأولت يقرؤه الخادم عبر نفق الشركة (صورة المالك ٨ نوفمبر: «قُرئ 0 من 80» وأولته «ONU 80/101»).
  /// فشل تكملتها لا يُسمّى (طريقها شبكتك).
  List<VpnMergedCompany> get _vpnCompanies {
    final cs = widget.companies ?? const <MergedCompany>[];
    return [
      for (final c in cs)
        if (!_isLocal(c.key)) (key: c.key, name: c.name),
      for (final c in cs)
        if (_isLocal(c.key)) (key: c.key, name: c.name),
    ];
  }

  /// (النوع، اسم الشريحة، عنوان المجموعة، الأيقونة)
  static const _kinds = [
    (ConnectionProblemKind.cable, 'الكيبل', 'الكيبل مفصول أو 10 ميكا', LucideIcons.cable),
    (ConnectionProblemKind.signal, 'الإشارة', 'إشارة ضعيفة', LucideIcons.signal),
    (ConnectionProblemKind.ccq, 'CCQ', 'CCQ منخفض', LucideIcons.activity),
    (ConnectionProblemKind.fiberRx, 'ضوء الفايبر', 'ضوء الفايبر ضعيف', LucideIcons.sun),
    (ConnectionProblemKind.fiberTemp, 'حرارة الفايبر', 'حرارة الفايبر عالية', LucideIcons.thermometer),
  ];

  static ({ConnectionProblemKind kind, String chip, String group, IconData icon}) _kindOf(ConnectionProblemKind k) {
    final x = _kinds.firstWhere((e) => e.$1 == k);
    return (kind: x.$1, chip: x.$2, group: x.$3, icon: x.$4);
  }

  @override
  void initState() {
    super.initState();
    DeviceProbeBus.tick.addListener(_changed);
    VpnNow.subscribers.addListener(_changed);
    ConnectionAlertSettings.current.addListener(_changed);
    widget.probing?.addListener(_changed);
    ConnectionAlertSettings.ensureLoaded();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh(initial: true));
  }

  @override
  void dispose() {
    DeviceProbeBus.tick.removeListener(_changed);
    VpnNow.subscribers.removeListener(_changed);
    ConnectionAlertSettings.current.removeListener(_changed);
    widget.probing?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// الفتح والتحديث: على الشبكة الموجة للقديم وحده؛ عبر الـVPN فحص الخادم إن قدُمت قراءته (أو بالتحديث صراحةً).
  /// «كل الشركات»: الموجة للمفتوحة، وفحص الخادم لغيرها — عند الفتح لمن قدُمت قراءاته (١٠ د) أو لم تُفحص، وبالتحديث للكلّ.
  void _refresh({bool initial = false}) {
    if (_merged) {
      if (!widget.viaVpn && widget.openCompany != null) widget.onRefreshStale?.call();
      if (!widget.vpnAllowed || VpnNow.subscribers.busy) return;
      final now = DateTime.now();
      final todo = [
        for (final c in _vpnCompanies)
          if (!initial ||
              VpnNow.readingsAtFor(c.key) == null ||
              now.difference(VpnNow.readingsAtFor(c.key)!) > const Duration(minutes: 10))
            c,
      ];
      if (todo.isNotEmpty) VpnNow.subscribers.run(only: todo);
      return;
    }
    if (!widget.viaVpn) {
      widget.onRefreshStale?.call();
      return;
    }
    if (VpnNow.subscribers.busy) return;
    final at = VpnNow.readingsAtFor(null);
    if (!initial || at == null || DateTime.now().difference(at) > const Duration(minutes: 10)) {
      VpnNow.subscribers.run();
    }
  }

  ConnectionAlertThresholds _limits(String? company) =>
      (company == null ? null : VpnNow.limitsOf(company)) ?? ConnectionAlertSettings.current.value;

  bool get _busy => _merged
      ? ((widget.probing?.value ?? false) || VpnNow.subscribers.busy)
      : (widget.viaVpn ? VpnNow.subscribers.busy : (widget.probing?.value ?? false));

  SubsCheckReport _report(List<Subscriber> subs) {
    if (_merged) return SubscribersCheck.mixed(subs, _limits, companyNote: _companyNote);
    return widget.viaVpn ? SubscribersCheck.vpn(subs, _limits) : SubscribersCheck.local(subs, _limits);
  }

  /// سبب شركةٍ لم تُفحص عبر الـVPN (لمن لم يُقرأ من مشتركيها) — والموظّف بلا مفتاحه يُقال له.
  String? _companyNote(String? key) {
    if (key == null || _isLocal(key)) return null;
    if (!widget.vpnAllowed) return 'الفحص عبر VPN غير مفعّل لك';
    return VpnNow.noteOf(key);
  }

  void _open(Subscriber s) => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SubscriberDetailScreen(sub: s),
        fullscreenDialog: true,
      ));

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final all = widget.subscribers();
    final full = _merged ? _report(all) : null;
    final subs = _company == null
        ? all
        : [
            for (final x in all)
              if (x.companyKey == _company) x
          ];
    final r = _company == null && full != null ? full : _report(subs);
    final mergedAll = MergedMode.active.value && MergedMode.focused == null;
    final items = _items(r);
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('الفحص العامّ للمشتركين', style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
        iconTheme: IconThemeData(color: AppColors.textHi),
        actions: [
          if (!widget.viaVpn && widget.onForceAll != null)
            IconButton(
              key: const ValueKey('subs-check-force'),
              tooltip: 'إعادة فحص الكلّ (أبطأ)',
              onPressed: _busy ? null : widget.onForceAll,
              icon: Icon(LucideIcons.radar, size: 20, color: AppColors.textMid),
            ),
          IconButton(
            key: const ValueKey('subs-check-refresh'),
            tooltip: 'تحديث',
            onPressed: _busy ? null : () => _refresh(),
            icon: _busy
                ? SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
                : Icon(LucideIcons.refreshCw, size: 19, color: AppColors.textMid),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _summary(r),
                const SizedBox(height: Sp.md),
                if (_merged && full != null) ...[
                  _companiesCard(all, full),
                  const SizedBox(height: Sp.md),
                ],
                if (_seg == _Seg.problems && r.rows.isNotEmpty) ...[
                  _kindChips(r),
                  const SizedBox(height: Sp.xs),
                ],
                if (_seg == _Seg.healthy && r.healthy.isNotEmpty)
                  _caption(LucideIcons.arrowDownWideNarrow, 'الأقرب إلى حدّ المشكلة أوّلاً'),
                if (_seg == _Seg.missing && r.missing.isNotEmpty)
                  _caption(LucideIcons.info, 'بلا قراءةٍ لجهازه — اضغط المشترك لتفتح نافذته'),
              ]),
            ),
          ),
          if (items.isEmpty)
            SliverToBoxAdapter(child: _empty(r))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((_, i) => _item(items[i], mergedAll), childCount: items.length),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.xs, Sp.lg, Sp.huge),
            sliver: SliverToBoxAdapter(child: _footer(mergedAll)),
          ),
        ],
      ),
    );
  }

  /// صفوف القسم المفتوح: «بمشكلة» مجموعاتٍ بأسوأ نوع (أو نوعٌ واحد بالشريحة)، «سليم»، أو «لم يُقرأ».
  List<Object> _items(SubsCheckReport r) {
    switch (_seg) {
      case _Seg.problems:
        if (_kind != null) return r.of(_kind!);
        final counts = <ConnectionProblemKind, int>{};
        for (final row in r.rows) {
          counts[row.worst!] = (counts[row.worst!] ?? 0) + 1;
        }
        final out = <Object>[];
        ConnectionProblemKind? last;
        for (final row in r.rows) {
          if (row.worst != last) {
            last = row.worst;
            out.add(_Group(last!, counts[last]!));
          }
          out.add(row);
        }
        return out;
      case _Seg.healthy:
        return r.healthy;
      case _Seg.missing:
        return r.missing;
    }
  }

  Widget _item(Object it, bool mergedAll) {
    if (it is _Group) return _groupHeader(it);
    if (it is SubsCheckRow) return _row(it, mergedAll);
    return _missRow(it as SubsMissing, mergedAll);
  }

  // ─────────────────── الملخّص ───────────────────

  Widget _summary(SubsCheckReport r) {
    final bad = r.rows.length;
    final none = r.read == 0;
    final tone = none ? AppTone.neutral : (bad == 0 ? AppTone.success : AppTone.danger);
    final title = none ? 'لا قراءات بعد' : (bad == 0 ? 'لا مشاكل' : '${formatIQD(bad)} بمشكلة');
    final at = widget.viaVpn ? VpnNow.readingsAt : null;
    final source = _merged
        ? 'كل الشركات — كلّ شركةٍ بطريقها'
        : (widget.viaVpn ? 'عبر VPN${at != null ? ' · ${timeAgoAr(at)}' : ''}' : 'من موبايلك على الشبكة');
    final pct = r.total == 0 ? 0.0 : r.read / r.total;
    return Container(
      key: const ValueKey('subs-check-summary'),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.md)),
            child: Icon(
              none ? LucideIcons.radar : (bad == 0 ? LucideIcons.shieldCheck : LucideIcons.triangleAlert),
              size: 22,
              color: tone.fill,
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title,
                  style: AppType.title(color: none ? AppColors.textHi : tone.fill)
                      .copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('$source${_busy ? ' · يحدّث…' : ''}',
                  style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
            ]),
          ),
        ]),
        const SizedBox(height: Sp.md),
        Row(children: [
          Expanded(
            child: Text('قُرئ ${formatIQD(r.read)} من ${formatIQD(r.total)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.label(color: AppColors.textMid).copyWith(fontSize: 12.5)),
          ),
          Text('${(pct * 100).round()}%',
              textDirection: TextDirection.ltr,
              style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: Sp.x6),
        ClipRRect(
          borderRadius: BorderRadius.circular(R.pill),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: AppColors.surfaceSunken,
            color: AppColors.brand,
          ),
        ),
        const SizedBox(height: Sp.md),
        Row(children: [
          Expanded(child: _segTile(_Seg.problems, bad, 'بمشكلة', AppTone.danger, LucideIcons.triangleAlert)),
          const SizedBox(width: Sp.sm),
          Expanded(child: _segTile(_Seg.healthy, r.healthy.length, 'سليم', AppTone.success, LucideIcons.circleCheck)),
          const SizedBox(width: Sp.sm),
          Expanded(child: _segTile(_Seg.missing, r.missing.length, 'لم يُقرأ', AppTone.info, LucideIcons.circleDashed)),
        ]),
      ]),
    );
  }

  Widget _segTile(_Seg seg, int n, String label, AppTone tone, IconData icon) {
    final on = _seg == seg;
    return Material(
      color: on ? tone.softBg : AppColors.surfaceSunken,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        key: ValueKey('subs-check-seg-${seg.name}'),
        borderRadius: BorderRadius.circular(R.md),
        onTap: () => setState(() {
          _seg = seg;
          _kind = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Sp.sm, horizontal: Sp.xs),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: on ? tone.softBorder : Colors.transparent, width: BW.selected),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(formatIQD(n),
                style: AppType.title(color: n == 0 ? AppColors.textLow : tone.fill)
                    .copyWith(fontSize: 19, fontWeight: FontWeight.w700, height: 1.2)),
            const SizedBox(height: 2),
            Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 13, color: on ? tone.fill : AppColors.textLow),
              const SizedBox(width: Sp.xs),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(color: on ? AppColors.textHi : AppColors.textMid)
                        .copyWith(fontSize: 12.5, fontWeight: on ? FontWeight.w700 : FontWeight.w600)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  // ─────────────────── «كل الشركات»: الشركات ───────────────────

  /// سطرٌ لكلّ شركة كـ«الفحص الشامل»: طريقها (من شبكتك / عبر VPN الشركة / لماذا لم تُفحص) وكم قُرئ من مشتركيها وكم بمشكلة —
  /// والضغط يعرض مشتركيها وحدهم.
  Widget _companiesCard(List<Subscriber> all, SubsCheckReport full) {
    final total = <String, int>{};
    for (final x in all) {
      final k = x.companyKey;
      if (k != null) total[k] = (total[k] ?? 0) + 1;
    }
    final read = <String, int>{};
    final viaVpn = <String, int>{};
    final bad = <String, int>{};
    for (final row in [...full.healthy, ...full.rows]) {
      final k = row.sub.companyKey;
      if (k == null) continue;
      read[k] = (read[k] ?? 0) + 1;
      if (row.reading?.vpn ?? false) viaVpn[k] = (viaVpn[k] ?? 0) + 1;
    }
    for (final row in full.rows) {
      final k = row.sub.companyKey;
      if (k != null) bad[k] = (bad[k] ?? 0) + 1;
    }
    final shown = [
      for (final c in widget.companies!)
        if ((total[c.key] ?? 0) > 0) c
    ];
    final picked = _company == null ? null : shown.where((c) => c.key == _company).firstOrNull;
    final hint = picked != null
        ? '«${picked.name}» وحدها — اضغطها ثانيةً لعرض الكلّ'
        : (shown.length > 1 ? 'اضغط شركةً لعرض مشتركيها وحدهم' : null);
    return Container(
      key: const ValueKey('subs-check-companies'),
      padding: const EdgeInsets.all(Sp.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final c in shown)
          _companyRow(c,
              total: total[c.key] ?? 0, read: read[c.key] ?? 0, viaVpn: viaVpn[c.key] ?? 0, bad: bad[c.key] ?? 0),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(Sp.sm, Sp.xs, Sp.sm, 2),
            child: Row(children: [
              Icon(picked != null ? LucideIcons.filter : LucideIcons.mousePointerClick,
                  size: 13, color: AppColors.textLow),
              const SizedBox(width: Sp.x6),
              Expanded(
                child: Text(hint,
                    key: const ValueKey('subs-check-companies-hint'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5)),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _companyRow(MergedCompany c, {required int total, required int read, required int viaVpn, required int bad}) {
    final on = _company == c.key;
    final counts = 'قُرئ ${formatIQD(read)} من ${formatIQD(total)}';
    final job = VpnNow.subscribers;
    final local = _isLocal(c.key);
    final note = _companyNote(c.key);
    final at = VpnNow.readingsAtFor(c.key);
    final probing = widget.probing?.value ?? false;
    // المفتوحة: من الهاتف أوّلاً، وما قُرئ عبر VPN شركتها (ضوء الأولت) يُقال
    final localWay = viaVpn == 0 ? 'من شبكتك' : (viaVpn == read ? 'عبر VPN الشركة' : 'من شبكتك وعبر VPN الشركة');
    final (IconData icon, AppTone tone, String text) = local
        ? (probing
            ? (LucideIcons.loader, AppTone.brand, 'يُقرأ من شبكتك… · $counts')
            : job.busy && job.current == c.key
                ? (LucideIcons.loader, AppTone.brand, 'يُكمَّل عبر VPN الشركة… · $counts')
                : (LucideIcons.circleCheck, AppTone.success, '$localWay · $counts'))
        : job.busy && job.current == c.key
            ? (LucideIcons.loader, AppTone.brand, 'يُفحص عبر VPN الشركة… · $counts')
            : job.busy && job.queue.contains(c.key)
                ? (LucideIcons.hourglass, AppTone.neutral, 'بانتظار دورها عبر VPN · $counts')
                // شركةٌ غير المفتوحة قُرئ بعض مشتركيها من شبكتك (أجهزتهم يصلها موبايلك) — يُقال ذلك قبل حال الـVPN
                : read > viaVpn && (note != null || at == null)
                    ? (
                        LucideIcons.circleCheck,
                        AppTone.success,
                        '${viaVpn > 0 ? 'من شبكتك وعبر VPN الشركة' : 'من شبكتك'} · $counts'
                            '${note != null ? ' · ${note.contains('تحتاج VPN') ? 'بلا VPN للباقي' : 'تعذّر VPN للباقي'}' : ''}'
                      )
                    : note != null
                        ? (
                            note.contains('تحتاج VPN') ? LucideIcons.shieldOff : LucideIcons.triangleAlert,
                            AppTone.warning,
                            note
                          )
                        : at != null
                            ? (
                                LucideIcons.circleCheck,
                                AppTone.success,
                                '${read > viaVpn ? 'من شبكتك وعبر VPN الشركة' : 'عبر VPN الشركة'} · ${timeAgoAr(at)} · $counts'
                              )
                            : (LucideIcons.circleDashed, AppTone.neutral, 'لم تُفحص بعد عبر VPN · $counts');
    final waiting = tone == AppTone.neutral;
    return Material(
      key: ValueKey('subs-check-company-${c.key}'),
      color: on ? AppTone.brand.softBg : Colors.transparent,
      borderRadius: BorderRadius.circular(R.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.md),
        onTap: () => setState(() {
          _company = on ? null : c.key;
          _kind = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: on ? AppTone.brand.softBorder : Colors.transparent),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: AppColors.company(c.colorIndex), shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: Sp.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AppType.label(color: AppColors.textHi).copyWith(fontSize: 13.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.muted(color: tone == AppTone.warning ? tone.onSoft : AppColors.textMid)
                        .copyWith(fontSize: 11.5)),
              ]),
            ),
            const SizedBox(width: Sp.x6),
            if (on) ...[
              _pillSmall('معروضة', AppTone.brand),
              const SizedBox(width: Sp.x6),
            ] else if (bad > 0) ...[
              _pillSmall('${formatIQD(bad)} بمشكلة', AppTone.danger),
              const SizedBox(width: Sp.x6),
            ],
            Icon(icon, size: 18, color: waiting ? AppColors.textLow : tone.fill),
          ]),
        ),
      ),
    );
  }

  Widget _pillSmall(String text, AppTone tone) => Container(
        padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 2),
        decoration: BoxDecoration(
          color: tone.softBg,
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: tone.softBorder),
        ),
        child: Text(text, style: AppType.label(color: tone.onSoft).copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
      );

  // ─────────────────── شرائح الأنواع ───────────────────

  Widget _kindChips(SubsCheckReport r) {
    Widget chip(String label, IconData? icon, int n, bool on, VoidCallback tap, Key key) => Material(
          color: on ? AppTone.danger.softBg : AppColors.surface,
          borderRadius: BorderRadius.circular(R.pill),
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(R.pill),
            onTap: tap,
            child: Container(
              height: H.chipSm,
              padding: const EdgeInsets.symmetric(horizontal: Sp.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.pill),
                border: Border.all(color: on ? AppTone.danger.softBorder : AppColors.border),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: on ? AppTone.danger.fill : AppColors.textMid),
                  const SizedBox(width: Sp.xs),
                ],
                Text(label,
                    style: AppType.label(color: on ? AppTone.danger.onSoft : AppColors.textHi)
                        .copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(width: Sp.x6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.x6, vertical: 1),
                  decoration: BoxDecoration(
                    color: on ? AppTone.danger.fill : AppColors.surfaceSunken,
                    borderRadius: BorderRadius.circular(R.pill),
                  ),
                  child: Text(formatIQD(n),
                      style: AppType.label(color: on ? AppColors.onBrand : AppColors.textMid)
                          .copyWith(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
        );
    // سطرٌ ثانٍ لا تمريرٌ جانبيّ — كلّ الأنواع ظاهرة
    return Wrap(
      spacing: Sp.x6,
      runSpacing: Sp.x6,
      children: [
        chip('الكل', null, r.rows.length, _kind == null, () => setState(() => _kind = null),
            const ValueKey('subs-check-kind-all')),
        for (final (k, label, _, icon) in _kinds)
          if (r.of(k).isNotEmpty)
            chip(label, icon, r.of(k).length, _kind == k, () => setState(() => _kind = k),
                ValueKey('subs-check-kind-${k.name}')),
      ],
    );
  }

  Widget _groupHeader(_Group g) {
    final k = _kindOf(g.kind);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, Sp.sm, 2, Sp.sm),
      child: Row(children: [
        Icon(k.icon, size: 15, color: AppTone.danger.fill),
        const SizedBox(width: Sp.x6),
        Text(k.group,
            style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: Sp.x6),
        Text('(${formatIQD(g.count)})', style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5)),
        const SizedBox(width: Sp.sm),
        Expanded(child: Container(height: 1, color: AppColors.border)),
      ]),
    );
  }

  Widget _caption(IconData icon, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, Sp.sm),
        child: Row(children: [
          Icon(icon, size: 14, color: AppColors.textLow),
          const SizedBox(width: Sp.x6),
          Expanded(child: Text(text, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5))),
        ]),
      );

  // ─────────────────── صفّ مشترك ───────────────────

  String _nameOf(Subscriber s) => s.fullName.trim().isEmpty ? s.username : s.fullName.trim();

  Widget _row(SubsCheckRow row, bool mergedAll) {
    final s = row.sub;
    final x = row.reading;
    final bad = {for (final p in row.problems) p.kind};
    final problem = bad.isNotEmpty;
    final meta = <String>[
      iso(s.username),
      if (x?.device != null) iso(x!.device!),
      if (x?.via != null) 'من ${x!.via}',
      if (!widget.viaVpn && x?.at != null) timeAgoAr(x!.at),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('subs-check-row-${s.companyKey ?? ''}|${s.username}'),
          onTap: () => _open(s),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: problem ? AppTone.danger.softBorder : AppColors.border),
            ),
            child: Stack(children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(Sp.md + 2, Sp.md, Sp.sm, Sp.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(_nameOf(s),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.label(color: AppColors.textHi)
                              .copyWith(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    ),
                    if (mergedAll && s.companyKey != null) ...[
                      const SizedBox(width: Sp.x6),
                      CompanyTag(companyKey: s.companyKey!, fontSize: 11),
                    ],
                    const SizedBox(width: Sp.xs),
                    Icon(LucideIcons.chevronLeft, size: 17, color: AppColors.textLow),
                  ]),
                  const SizedBox(height: 2),
                  Text(meta.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5)),
                  if (x != null) ...[
                    const SizedBox(height: Sp.sm),
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: Sp.xs),
                      child: _metrics(x, bad, _limits(s.companyKey)),
                    ),
                  ],
                ]),
              ),
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: problem ? AppTone.danger.fill : AppColors.success),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// مقاييس المشترك خاناتٍ متساوية كالكارت — المشكلة حمراء (بحدود المدير)، والقريب من الحدّ برتقاليّ.
  Widget _metrics(SubsReading x, Set<ConnectionProblemKind> bad, ConnectionAlertThresholds t) {
    _Lvl lvl(ConnectionProblemKind k, bool near) => bad.contains(k) ? _Lvl.bad : (near ? _Lvl.near : _Lvl.ok);
    final cells = <Widget>[
      if (x.sig != null) _cell('الإشارة', '${x.sig} dBm', lvl(ConnectionProblemKind.signal, x.sig! - t.signalDbm <= 5)),
      if (x.ccq != null) _cell('CCQ', '${x.ccq}%', lvl(ConnectionProblemKind.ccq, x.ccq! - t.ccqPct <= 10)),
      if (x.lan != null) _cell('الكيبل', _lanText(x.lan!), lvl(ConnectionProblemKind.cable, false)),
      if (x.rx != null)
        _cell(
            'الضوء', '${x.rx!.toStringAsFixed(1)} dBm', lvl(ConnectionProblemKind.fiberRx, x.rx! - t.fiberRxDbm <= 2)),
      if (x.temp != null)
        _cell('الحرارة', '${x.temp!.round()}°C', lvl(ConnectionProblemKind.fiberTemp, t.fiberTempC - x.temp! <= 5)),
    ];
    if (cells.isEmpty && x.ms != null) cells.add(_cell('الاستجابة', '${x.ms} ms', _Lvl.ok));
    if (cells.isEmpty) return const SizedBox.shrink();
    return Row(children: [
      for (var i = 0; i < cells.length; i++) ...[
        if (i > 0) const SizedBox(width: Sp.x6),
        Expanded(child: cells[i]),
      ],
    ]);
  }

  static String _lanText(String lan) => switch (lan) {
        'unplugged' => 'مفصول',
        'on' => 'موصول',
        '1000' => '1G',
        _ => int.tryParse(lan) != null ? '${lan}M' : lan,
      };

  Widget _cell(String label, String value, _Lvl l) {
    final fg = switch (l) {
      _Lvl.bad => AppTone.danger.fill,
      _Lvl.near => AppColors.warning,
      _Lvl.ok => AppColors.textHi,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.x6),
      decoration: BoxDecoration(
        color: l == _Lvl.bad ? AppTone.danger.softBg : AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: l == _Lvl.bad ? AppTone.danger.softBorder : Colors.transparent),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                AppType.muted(color: l == _Lvl.bad ? AppTone.danger.onSoft : AppColors.textLow).copyWith(fontSize: 11)),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            textDirection: TextDirection.ltr,
            style: AppType.label(color: fg).copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ]),
    );
  }

  // ─────────────────── من لم يُقرأ ───────────────────

  Widget _missRow(SubsMissing m, bool mergedAll) {
    final s = m.sub;
    final (text, tone) = switch (m.why) {
      SubsMissWhy.dead => ('لا يستجيب', AppTone.danger),
      SubsMissWhy.company => (
          (m.note ?? '').contains('تحتاج VPN') ? 'شركته تحتاج VPN' : 'لم تُفحص شركته',
          AppTone.warning
        ),
      SubsMissWhy.offline => ('غير متّصل', AppTone.neutral),
      SubsMissWhy.noMetrics => ('جهازٌ بلا قياسات', AppTone.neutral),
      SubsMissWhy.noReply => (
          _busy ? 'بانتظار الفحص' : (widget.viaVpn ? 'لم يُقرأ عبر VPN' : 'جهازه لم يردّ'),
          AppTone.warning
        ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.sm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('subs-check-miss-${s.companyKey ?? ''}|${s.username}'),
          onTap: () => _open(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm + 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(_nameOf(s),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          AppType.label(color: AppColors.textHi).copyWith(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(iso(s.username),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5)),
                ]),
              ),
              if (mergedAll && s.companyKey != null) ...[
                CompanyTag(companyKey: s.companyKey!, fontSize: 11),
                const SizedBox(width: Sp.x6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
                decoration: BoxDecoration(
                  color: tone.softBg,
                  borderRadius: BorderRadius.circular(R.pill),
                  border: Border.all(color: tone.softBorder),
                ),
                child: Text(text,
                    style: AppType.label(color: tone.onSoft).copyWith(fontSize: 11.5, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ─────────────────── الفراغ والتذييل ───────────────────

  Widget _empty(SubsCheckReport r) {
    if (r.read == 0 && _seg != _Seg.missing) {
      if (_busy) {
        return _notice(LucideIcons.radar,
            widget.viaVpn ? 'يفحص الخادم المشتركين عبر الـVPN…' : 'يُقرأ المشتركون الآن من موبايلك…');
      }
      return _notice(
          LucideIcons.info,
          widget.viaVpn
              ? 'لا قراءات عبر الـVPN بعد — اضغط «تحديث» ليفحص الخادم'
              : 'لا قراءات بعد — يُفحص المشتركون الآن من موبايلك');
    }
    return switch (_seg) {
      _Seg.problems =>
        _notice(LucideIcons.circleCheck, 'لا مشاكل ✓ — كلّ المقروئين ضمن حدود «تنبيه المشترك»', good: true),
      _Seg.healthy => _notice(LucideIcons.triangleAlert, 'لا أحد سليم — كلّ المقروئين بمشكلة'),
      _Seg.missing => _notice(LucideIcons.circleCheck, 'قُرئ الجميع ✓', good: true),
    };
  }

  static String _num(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

  Widget _footer(bool mergedAll) {
    final t = _limits(null);
    final lines = <String>[
      // «كل الشركات»: الحدود لكلّ شركةٍ وحدها — لا سطرٌ واحد يصدق على الكلّ
      if (!mergedAll)
        'حدّ المشكلة من «تنبيه المشترك»: الإشارة أضعف من ${iso('${t.signalDbm} dBm')} · CCQ ${iso('${t.ccqPct}%')} أو أقلّ'
            ' · الضوء أضعف من ${iso('${_num(t.fiberRxDbm)} dBm')} · الحرارة فوق ${iso('${t.fiberTempC}°C')}',
      if (widget.big) 'الحساب كبير — الفحص للصفوف المحمّلة في القائمة',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final l in lines)
        Padding(
          padding: const EdgeInsets.only(top: Sp.xs),
          child: Text(l, style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5, height: 1.5)),
        ),
    ]);
  }

  Widget _notice(IconData icon, String text, {bool good = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.huge, horizontal: Sp.lg),
        child: Column(children: [
          Icon(icon, size: 34, color: good ? AppColors.success : AppColors.textLow),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: AppType.label(color: AppColors.textMid).copyWith(height: 1.6)),
        ]),
      );
}
