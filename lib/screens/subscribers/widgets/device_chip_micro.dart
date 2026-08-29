import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../api/device_probe_api.dart';
import '../../../models/device_health.dart';
import '../../../theme/colors.dart';
import '../../../theme/spacing.dart';
import '../../../theme/typography.dart';

/// Notifier that lets the list-view wave broadcast cache updates to
/// every visible card at once. Wave loop calls `bump()` after each
/// concurrent batch; chips listen and re-render against the freshly
/// warmed cache without re-probing themselves.
class DeviceProbeBus {
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static void bump() => tick.value = tick.value + 1;
}

/// Device-health row for a subscriber list card. Shows the metrics
/// the admin needs at a glance:
///   ONT  → RX dBm + temperature (°C)
///   UBNT → signal dBm + CCQ % + LAN speed
/// Plus a refresh button (40dp tap area) to re-probe just this sub.
///
/// Reads from DeviceProbeApi's cache only — never starts an unsolicited
/// probe (the list wave owns that). The refresh button explicitly
/// asks for a force-probe via `probe(force: true)`.
///
/// Wrapped in AnimatedSwitcher so the row fades in smoothly when the
/// wave fills the cache for this sub, instead of popping into view.
class DeviceChipMicro extends StatefulWidget {
  const DeviceChipMicro({
    super.key,
    required this.ip,
    required this.username,
  });
  final String? ip;
  final String username;

  @override
  State<DeviceChipMicro> createState() => _DeviceChipMicroState();
}

class _DeviceChipMicroState extends State<DeviceChipMicro> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await DeviceProbeApi.probe(
        fallbackIp: widget.ip ?? '',
        subscriberUsername: widget.username,
        force: true,
      );
      DeviceProbeBus.bump();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // theme-dep (dark-mode)
    final clean = widget.ip?.trim() ?? '';
    // مطلب 2026-07-12: لا نُخفي الـwidget لو IP فارغ — المشترك ممكن
    // يكون له customIp في DeviceConfig (offline case). نبحث بالـusername
    // أوّلاً؛ لو ما لقينا نجرّب بالـSAS IP.
    return ValueListenableBuilder<int>(
      valueListenable: DeviceProbeBus.tick,
      builder: (_, __, ___) {
        final snap = DeviceProbeApi.cachedForUser(widget.username) ??
            (clean.isEmpty ? null : DeviceProbeApi.cached(clean));
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SizeTransition(
              sizeFactor: anim,
              axisAlignment: -1,
              child: child,
            ),
          ),
          child: snap == null
              ? const SizedBox(key: ValueKey('empty'), height: 0)
              : Padding(
                  key: const ValueKey('row'),
                  padding: const EdgeInsets.only(top: 6),
                  child: _row(snap),
                ),
        );
      },
    );
  }

  Widget _row(DeviceHealthSnapshot snap) {
    return Row(
      children: [
        Expanded(child: _metrics(snap)),
        const SizedBox(width: 6),
        _refreshButton(),
      ],
    );
  }

  Widget _metrics(DeviceHealthSnapshot snap) {
    if (snap.kind == DeviceKind.ont && snap.ont != null) {
      return _ontMetrics(snap.ont!);
    }
    if (snap.kind == DeviceKind.ubiquiti && snap.ubnt != null) {
      return _ubntMetrics(snap.ubnt!);
    }
    return const SizedBox.shrink();
  }

  // ── ONT layout: [ONT badge]  RX -22.5 dBm  •  45 °C ───────────────
  Widget _ontMetrics(OntOpticalInfo o) {
    final rxColor = o.rxOk ? AppColors.brand : AppColors.error;
    final tempColor = o.tempOk ? AppColors.brand : AppColors.warning;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        _kindBadge('ONT', AppColors.brandAccent, LucideIcons.signalHigh),
        _stat(
          icon: LucideIcons.signal,
          label: 'RX',
          value: '${o.rxPower} dBm',
          color: rxColor,
          danger: !o.rxOk,
        ),
        _stat(
          icon: LucideIcons.thermometer,
          label: 'حرارة',
          value: '${o.temperature}°C',
          color: tempColor,
          danger: !o.tempOk,
        ),
      ],
    );
  }

  // ── UBNT layout: [UBNT]  -67 dBm  •  CCQ 95%  •  LAN 1G ───────────
  Widget _ubntMetrics(UbiquitiStatus u) {
    final signalColor = _signalColor(u.signalDbm);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        _kindBadge('UBNT', AppColors.success, LucideIcons.wifi),
        if (u.signalDbm != null)
          _stat(
            icon: LucideIcons.signal,
            label: 'إشارة',
            value: '${u.signalDbm} dBm',
            color: signalColor,
            danger: u.signalHealth == 'bad',
          ),
        if (u.ccqPercent != null)
          _stat(
            icon: LucideIcons.gauge,
            label: 'CCQ',
            value: '${u.ccqPercent}%',
            color: _healthColor(u.ccqHealth),
            danger: u.ccqHealth == 'bad',
          ),
        if (u.lanSpeedShort != null)
          _stat(
            icon: LucideIcons.cable,
            label: 'LAN',
            value: u.lanSpeedShort!,
            color: _healthColor(u.lanHealth),
            danger: u.lanHealth == 'bad',
          ),
      ],
    );
  }

  /// Leading rounded-square badge identifying the device family.
  Widget _kindBadge(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(R.sm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: AppType.label(color: color)
                .copyWith(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  /// Single metric in the inline list: small icon + value, with the
  /// label as a faint prefix. Sized to read comfortably (12px value,
  /// 9.5px label) but still tight enough so 3 of them fit on one line
  /// in the typical card width.
  Widget _stat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool danger = false,
  }) {
    final body = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10.5, color: color),
        const SizedBox(width: 3),
        Text(
          '$label ',
          style: AppType.muted(color: AppColors.textMid)
              .copyWith(fontSize: 9.5, fontWeight: FontWeight.w600),
        ),
        Text(
          value,
          style: AppType.label(color: color)
              .copyWith(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        // مطلب 2026-06-11: قيمة 'خطرة' لازم تنوّه — مثل v1.
        // المثلث الأحمر يظهر بجنب أي قيمة خارج النطاق الصحي
        // (rx/temp/signal/ccq/lan) فالأمر يلاحظها المدير ع الفور.
        if (danger) ...[
          const SizedBox(width: 3),
          Icon(
            LucideIcons.triangleAlert,
            size: 10,
            color: AppColors.error,
          ),
        ],
      ],
    );
    // Wrap dangerous values in a soft red pill so they pop visually
    // even when scanning down a long list of green readings.
    if (danger) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.dangerSoftBg,
          borderRadius: BorderRadius.circular(R.sm),
        ),
        child: body,
      );
    }
    return body;
  }

  /// 36×36 tap target — meets Material's 36dp guidance for inline
  /// action icons on a list row (we don't need the full 48dp here
  /// since the card itself is tappable). Spinner while probing.
  Widget _refreshButton() {
    return Material(
      color: Colors.transparent,
      child: InkResponse(
        onTap: _refreshing ? null : _refresh,
        radius: 22,
        highlightShape: BoxShape.circle,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceInput,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border),
          ),
          child: _refreshing
              ? SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: AppColors.brandAccent,
                  ),
                )
              : Icon(LucideIcons.refreshCw, size: 14, color: AppColors.textMid),
        ),
      ),
    );
  }

  static Color _signalColor(int? signal) {
    if (signal == null) return AppColors.textMid;
    if (signal > -65) return AppColors.brand;
    if (signal > -75) return AppColors.warning;
    return AppColors.error;
  }

  static Color _healthColor(String h) {
    switch (h) {
      case 'good':
        return AppColors.brand;
      case 'warn':
        return AppColors.warning;
      case 'bad':
        return AppColors.error;
      default:
        return AppColors.textMid;
    }
  }
}
