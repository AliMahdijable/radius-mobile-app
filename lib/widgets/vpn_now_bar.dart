import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/vpn_now.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

/// شريط «أنت خارج شبكتك» أسفل قسم المشتركين/الأجهزة (٥ نوفمبر — المالك: «يطلع له فد هنت صغير جوا يقدر يخفيه ويقدر يعطيه فحص الان»).
///
/// الحالات (صفحة «حالات الفحص عبر VPN» التي وافق عليها):
/// * خارج الشبكة + VPN مربوط ⇒ «تقدر تفحص … عبر الـVPN» [فحص الآن] [×]؛ بلا VPN ⇒ «اربط VPN مرّة وحدة» [ربط VPN] [×].
/// * يفحص ⇒ دائرة + «يفحص مشتركينك… ١٢٠ من ٣١٠» + خطّ تقدّم. انتهى ⇒ النتيجة وسطرها الثاني [×]. فشل ⇒ أحمر [صفحة VPN] [أعد].
/// * [×] على الهنت يخفيه لباقي اليوم ([VpnNow.dismiss])؛ والفحص الجاري أو نتيجته تظهر ولو رجع للشبكة.
/// ظهوره لا يفتح أيّ اتّصال — الخادم يدخل الـVPN فقط بالضغط.
class VpnNowBar extends StatefulWidget {
  const VpnNowBar({
    super.key,
    required this.kind,
    required this.offNetwork,
    required this.onOpenVpn,
    this.onShowProblems,
  });

  final VpnNowKind kind;

  /// الشاشة تقرّر: لا يردّ أيّ جهازٍ من شبكة الوكيل.
  final bool offNetwork;
  final VoidCallback onOpenVpn;
  final VoidCallback? onShowProblems;

  @override
  State<VpnNowBar> createState() => _VpnNowBarState();
}

class _VpnNowBarState extends State<VpnNowBar> {
  ({bool linked, String? via})? _route;
  bool _routeKnown = false;
  bool _dismissed = false;

  VpnNowJob get _job => VpnNow.jobOf(widget.kind);

  @override
  void initState() {
    super.initState();
    _job.addListener(_changed);
    VpnNow.dismissals.addListener(_reloadDismiss);
    if (widget.offNetwork) _resolve();
  }

  @override
  void didUpdateWidget(covariant VpnNowBar old) {
    super.didUpdateWidget(old);
    if (widget.offNetwork && !old.offNetwork) _resolve();
  }

  @override
  void dispose() {
    _job.removeListener(_changed);
    VpnNow.dismissals.removeListener(_reloadDismiss);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _reloadDismiss() async {
    final d = await VpnNow.dismissedToday(widget.kind);
    if (mounted) setState(() => _dismissed = d);
  }

  Future<void> _resolve() async {
    final d = await VpnNow.dismissedToday(widget.kind);
    final r = await VpnNow.route();
    if (!mounted) return;
    setState(() {
      _dismissed = d;
      _route = r;
      _routeKnown = true;
    });
  }

  String get _what => widget.kind == VpnNowKind.devices ? 'أجهزتك' : 'مشتركينك';

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final job = _job;
    Widget? child;
    switch (job.phase) {
      case VpnBarPhase.running:
        child = _running(job);
      case VpnBarPhase.done:
        child = _done(job);
      case VpnBarPhase.failed:
        child = _failed(job);
      case VpnBarPhase.idle:
        // الميزة غير مفتوحة لحسابه/لا صلاحيّة (route == null) ⇒ لا هنت
        if (widget.offNetwork && !_dismissed && _routeKnown && _route != null) {
          child = _route!.linked ? _offer() : _link();
        }
    }
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.bottomCenter,
      child: child == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(Sp.md, Sp.xs, Sp.md, Sp.sm),
              child: _card(child: child, tone: job.phase == VpnBarPhase.failed ? _Tone.danger : _Tone.normal),
            ),
    );
  }

  // ───────────────────── الحالات ─────────────────────

  Widget _offer() => Row(children: [
        _circle(LucideIcons.wifiOff, AppColors.warningOnSoft, AppColors.warningSoftBg),
        const SizedBox(width: Sp.sm),
        Expanded(child: _texts('أنت خارج شبكتك', 'تقدر تفحص $_what عبر الـVPN')),
        _primary('فحص الآن', LucideIcons.shieldCheck, () => _job.run()),
        _close(() => VpnNow.dismiss(widget.kind)),
      ]);

  Widget _link() => Row(children: [
        _circle(LucideIcons.shieldOff, AppColors.textMid, AppColors.surfaceSunken),
        const SizedBox(width: Sp.sm),
        Expanded(child: _texts('أنت خارج شبكتك', 'اربط VPN مرّة وحدة حتى تفحص من بعيد')),
        _primary('ربط VPN', LucideIcons.shieldPlus, widget.onOpenVpn),
        _close(() => VpnNow.dismiss(widget.kind)),
      ]);

  Widget _running(VpnNowJob job) => Column(
        key: const ValueKey('vpn-now-running'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.brandAccent),
            ),
            const SizedBox(width: Sp.sm + 2),
            Expanded(child: _texts(job.line ?? 'يتّصل بالـVPN…', job.sub)),
          ]),
          const SizedBox(height: Sp.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(R.pill),
            child: LinearProgressIndicator(
              value: job.value,
              minHeight: 6,
              color: AppColors.brandAccent,
              backgroundColor: AppColors.surfaceSunken,
            ),
          ),
        ],
      );

  Widget _done(VpnNowJob job) => Row(children: [
        _circle(LucideIcons.check, AppColors.successFill, AppColors.successSoftBg),
        const SizedBox(width: Sp.sm),
        Expanded(child: _texts(job.line ?? '', job.sub, subColor: AppColors.warningOnSoft)),
        if (widget.onShowProblems != null && widget.kind == VpnNowKind.subscribers && (job.sub ?? '').contains('بمشكلة'))
          _secondary('المشاكل', null, widget.onShowProblems!),
        _close(job.clear),
      ]);

  Widget _failed(VpnNowJob job) {
    final vpnPage = job.reason == null || job.reason == 'tunnel_failed' || job.reason == 'no_vpn';
    return Row(children: [
      _circle(LucideIcons.shieldAlert, AppColors.dangerOnSoft, AppColors.surface),
      const SizedBox(width: Sp.sm),
      Expanded(
        child: Text(job.line ?? 'تعذّر الفحص', style: AppType.bodyStrong(color: AppColors.dangerOnSoft), maxLines: 3),
      ),
      if (vpnPage) _secondary('صفحة VPN', null, widget.onOpenVpn),
      const SizedBox(width: 4),
      _secondary('أعد', LucideIcons.refreshCw, () => _job.run()),
      _close(job.clear),
    ]);
  }

  // ───────────────────── عناصر ─────────────────────

  Widget _texts(String a, String? b, {Color? subColor}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(a, style: AppType.bodyStrong(), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (b != null && b.isNotEmpty)
            Text(b, style: AppType.micro(color: subColor ?? AppColors.textMid), maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      );

  Widget _circle(IconData i, Color fg, Color bg) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(i, size: 19, color: fg),
      );

  Widget _primary(String t, IconData i, VoidCallback onTap) => FilledButton.icon(
        onPressed: onTap,
        icon: Icon(i, size: 16),
        label: Text(t),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: AppColors.onBrand,
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.sm),
          minimumSize: const Size(0, 38),
          textStyle: AppType.body().copyWith(fontWeight: FontWeight.w700, fontSize: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
        ),
      );

  Widget _secondary(String t, IconData? i, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textHi,
          side: BorderSide(color: AppColors.border),
          backgroundColor: AppColors.surface,
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm + 2, vertical: Sp.sm),
          minimumSize: const Size(0, 38),
          textStyle: AppType.body().copyWith(fontWeight: FontWeight.w700, fontSize: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.md)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (i != null) ...[Icon(i, size: 15), const SizedBox(width: 4)],
          Text(t),
        ]),
      );

  Widget _close(VoidCallback onTap) => IconButton(
        tooltip: 'إخفاء',
        onPressed: onTap,
        icon: Icon(LucideIcons.x, size: 18, color: AppColors.textLow),
        visualDensity: VisualDensity.compact,
      );

  Widget _card({required Widget child, required _Tone tone}) => Container(
        padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.xs, Sp.md),
        decoration: BoxDecoration(
          color: tone == _Tone.danger ? AppColors.dangerSoftBg : AppColors.surface,
          borderRadius: BorderRadius.circular(R.lg),
          border: Border.all(color: tone == _Tone.danger ? AppColors.dangerSoftBorder : AppColors.border),
          boxShadow: [BoxShadow(color: AppColors.textHi.withValues(alpha: 0.07), blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: child,
      );
}

enum _Tone { normal, danger }

/// حال الجهاز من آخر «فحص الآن» عبر الـVPN (٣٠ دقيقة) — حبّةٌ تحت اسم الجهاز: «واصل · 41 ms» أو «لا يستجيب» + VPN.
class VpnDevicePill extends StatelessWidget {
  const VpnDevicePill({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: VpnNow.version,
      builder: (context, _, __) {
        final r = VpnNow.deviceFor(id);
        if (r == null) return const SizedBox.shrink();
        final up = r.alive;
        final text = up
            ? [
                'واصل',
                if (r.ms != null) '\u2066${r.ms} ms\u2069',
                if (r.stations != null) '${r.stations} متّصل',
              ].join(' · ')
            : 'لا يستجيب';
        return Padding(
          padding: const EdgeInsets.only(top: Sp.xs),
          child: Wrap(spacing: Sp.xs, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _VpnPill(
              text: text,
              fg: up ? AppColors.successFill : AppColors.dangerOnSoft,
              bg: up ? AppColors.successSoftBg : AppColors.dangerSoftBg,
              border: up ? AppColors.successSoftBorder : AppColors.dangerSoftBorder,
            ),
            const VpnTag(),
          ]),
        );
      },
    );
  }
}

/// علامة «VPN» الصغيرة: القراءة جاءت عبر الـVPN لا من موبايلك.
class VpnTag extends StatelessWidget {
  const VpnTag({super.key});

  @override
  Widget build(BuildContext context) => _VpnPill(
        text: 'VPN',
        icon: LucideIcons.shieldCheck,
        fg: AppColors.brandOnSoft,
        bg: AppColors.brandSoftBg,
        border: AppColors.brandSoftBorder,
      );
}

class _VpnPill extends StatelessWidget {
  const _VpnPill({required this.text, required this.fg, required this.bg, required this.border, this.icon});
  final String text;
  final Color fg, bg, border;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 11, color: fg), const SizedBox(width: 3)],
          Text(text, style: AppType.micro(color: fg).copyWith(fontWeight: FontWeight.w700)),
        ]),
      );
}
