import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/util/bidi.dart';
import '../../core/util/format.dart';
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
/// المشتركين»): تقريرٌ فوريّ من قراءات الكارتات نفسها، والموجة تعيد القديم وحده في الخلفيّة (التقرير يتحدّث معها)؛ عبر الـVPN من
/// فحص الخادم الأخير (يُعاد إن قدُم). المشكلة بحدود «تنبيه المشترك» ([SubscribersCheck]). الضغط على مشترك يفتح نافذته.
class SubscribersCheckScreen extends StatefulWidget {
  const SubscribersCheckScreen({
    super.key,
    required this.subscribers,
    required this.viaVpn,
    this.probing,
    this.onRefreshStale,
    this.onForceAll,
    this.big = false,
  });

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

class _SubscribersCheckScreenState extends State<SubscribersCheckScreen> {
  ConnectionProblemKind? _kind;

  static const _kinds = [
    (ConnectionProblemKind.cable, 'الكيبل', LucideIcons.cable),
    (ConnectionProblemKind.signal, 'الإشارة', LucideIcons.signalLow),
    (ConnectionProblemKind.ccq, 'CCQ', LucideIcons.activity),
    (ConnectionProblemKind.fiberRx, 'ضوء الفايبر', LucideIcons.sun),
    (ConnectionProblemKind.fiberTemp, 'حرارة الفايبر', LucideIcons.thermometer),
  ];

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
  void _refresh({bool initial = false}) {
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

  bool get _busy => widget.viaVpn ? VpnNow.subscribers.busy : (widget.probing?.value ?? false);

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final subs = widget.subscribers();
    final r = widget.viaVpn ? SubscribersCheck.vpn(subs, _limits) : SubscribersCheck.local(subs, _limits);
    final rows = _kind == null ? r.rows : r.of(_kind!);
    final mergedAll = MergedMode.active.value && MergedMode.focused == null;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('الفحص العامّ للمشتركين',
            style: AppType.title(color: AppColors.textHi).copyWith(fontSize: 16)),
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
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brand))
                : Icon(LucideIcons.refreshCw, size: 19, color: AppColors.textMid),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.huge),
        children: [
          _summary(r),
          const SizedBox(height: Sp.md),
          if (r.rows.isNotEmpty) ...[
            _kindChips(r),
            const SizedBox(height: Sp.sm),
          ],
          if (r.read == 0 && !_busy)
            _notice(LucideIcons.info, widget.viaVpn
                ? 'لا قراءات عبر الـVPN بعد — اضغط «تحديث» ليفحص الخادم'
                : 'لا قراءات بعد — يُفحص المشتركون الآن من موبايلك')
          else if (r.rows.isEmpty && r.read > 0)
            _notice(LucideIcons.circleCheck, 'لا مشاكل ✓ — كلّ المقروئين ضمن حدود «تنبيه المشترك»', good: true)
          else
            for (final row in rows) ...[
              _row(row, mergedAll),
              const SizedBox(height: Sp.sm),
            ],
          if (r.unread > 0) ...[
            const SizedBox(height: Sp.xs),
            Text(
              'لم يُقرأ ${formatIQD(r.unread)} — بلا عنوانٍ لجهازه، أو جهازه لا يردّ${widget.viaVpn ? ' عبر الـVPN' : ''}',
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12),
            ),
          ],
          if (widget.big) ...[
            const SizedBox(height: Sp.xs),
            Text('الحساب كبير — الفحص للصفوف المحمّلة في القائمة',
                style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _summary(SubsCheckReport r) {
    final bad = r.rows.length;
    final tone = bad == 0 ? AppTone.success : AppTone.danger;
    return Container(
      key: const ValueKey('subs-check-summary'),
      padding: const EdgeInsets.all(Sp.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(R.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: tone.softBg, borderRadius: BorderRadius.circular(R.md)),
          child: Icon(bad == 0 ? LucideIcons.shieldCheck : LucideIcons.triangleAlert, size: 22, color: tone.fill),
        ),
        const SizedBox(width: Sp.md),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(bad == 0 ? 'لا مشاكل' : '${formatIQD(bad)} بمشكلة',
                style: AppType.title(color: tone.fill).copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
              'قُرئ ${formatIQD(r.read)} من ${formatIQD(r.total)} · ${widget.viaVpn ? 'عبر VPN' : 'من موبايلك على الشبكة'}'
              '${_busy ? ' · يحدّث…' : ''}',
              style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 12.5),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _kindChips(SubsCheckReport r) {
    Widget chip(String label, int n, bool on, VoidCallback tap, {Key? key}) => Padding(
          padding: const EdgeInsetsDirectional.only(end: Sp.x6),
          child: ChoiceChip(
            key: key,
            label: Text('$label $n'),
            selected: on,
            onSelected: (_) => tap(),
            labelStyle: AppType.label(color: on ? AppColors.onBrand : AppColors.textHi).copyWith(fontSize: 12.5),
            selectedColor: AppColors.brand,
            backgroundColor: AppColors.surface,
            side: BorderSide(color: on ? AppColors.brand : AppColors.border),
            showCheckmark: false,
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip('الكل', r.rows.length, _kind == null, () => setState(() => _kind = null)),
        for (final (k, label, _) in _kinds)
          if (r.of(k).isNotEmpty)
            chip(label, r.of(k).length, _kind == k, () => setState(() => _kind = k), key: ValueKey('subs-check-kind-${k.name}')),
      ]),
    );
  }

  Widget _row(SubsCheckRow row, bool mergedAll) {
    final s = row.sub;
    final name = s.fullName.trim().isEmpty ? s.username : s.fullName.trim();
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(R.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('subs-check-row-${s.companyKey ?? ''}|${s.username}'),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SubscriberDetailScreen(sub: s),
          fullscreenDialog: true,
        )),
        child: Container(
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label(color: AppColors.textHi).copyWith(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              if (mergedAll && s.companyKey != null) CompanyTag(companyKey: s.companyKey!, fontSize: 11),
            ]),
            const SizedBox(height: 2),
            Text(iso(s.username), style: AppType.muted(color: AppColors.textMid).copyWith(fontSize: 11.5)),
            const SizedBox(height: Sp.x6),
            Wrap(spacing: Sp.x6, runSpacing: Sp.xs, children: [
              for (final p in row.problems)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTone.danger.softBg,
                    borderRadius: BorderRadius.circular(R.pill),
                    border: Border.all(color: AppTone.danger.softBorder),
                  ),
                  child: Text(p.label, style: AppType.label(color: AppTone.danger.fill).copyWith(fontSize: 12)),
                ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _notice(IconData icon, String text, {bool good = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Sp.huge),
        child: Column(children: [
          Icon(icon, size: 34, color: good ? AppColors.success : AppColors.textLow),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: AppType.label(color: AppColors.textMid).copyWith(height: 1.6)),
        ]),
      );
}
